/**
 * NOTICE: first-party code, not a third-party library. This is an unmodified
 * copy of the author's own zero-dependency RFC6455 + DSH Gateway mux client,
 * taken from the same author's DSH_iOS project (native/ws-mux.mjs) and kept in
 * sync with it. Covered by this repository's MIT license; see
 * THIRD-PARTY-NOTICES.md. No external copyright applies.
 *
 * It implements the client half of DSH's /api/remote.mux protocol (verified
 * live against DSH 2026-10-26 by that project). Keep this copy in sync with the
 * upstream file if the mux protocol changes.
 */
/**
 * ws-mux.mjs — zero-dependency RFC6455 WebSocket client for the DSH Gateway
 * stream mux (`/api/remote.mux`), including the logical-stream protocol the
 * shipped web client uses.
 *
 * Why hand-rolled: the DSH GUI accepts the WebSocket upgrade only with the
 * signed `dsh-auth-*` cookie; Node's built-in global `WebSocket` (undici) cannot
 * set request headers, and the bridge must stay zero-dependency.
 *
 * Layer 1 — `WebSocketClient`: TCP/TLS connect + HTTP Upgrade handshake with
 * arbitrary headers, client-side frame masking, text/binary send, fragment
 * reassembly, ping→pong auto-reply, close handshake, 16/64-bit lengths.
 *
 * Layer 2 — `openMux` / `Mux` / `LogicalStream`: the Gateway's JSON mux frames:
 *
 *   client → server            server → client
 *   {type:"open",streamId,     {type:"item",streamId,value}
 *    endpoint,payload}         {type:"end",streamId}
 *   {type:"item",streamId,     {type:"error",streamId,error:{code,message,details}}
 *    value}
 *   {type:"end",streamId}
 *   {type:"cancel",streamId}
 *
 * `payload` is always `{args:{<named wire args>}}` exactly like unary RPC.
 * The Gateway pings every ~2 s and drops peers that miss two pongs; this client
 * replies automatically.
 *
 * Verified live against DSH 2026-10-26 (GUI 127.0.0.1:57968): upgrade 101,
 * `$events` ready frame, broadcast `emit` frames, `waterfall` frames, and
 * session/follow snapshot + live event entries.
 *
 * Usage:
 *   const mux = await openMux({ baseUrl, cookie })
 *   const events = await openEventStream(mux)          // $events channel
 *   const { clientId } = await events.ready
 *   events.onWaterfall((frame) => …)                    // approval/ask requests
 *   await events.answer({ eventId, outcome: {kind:'result', value: …} })
 *   const follow = mux.openStream('session/follow', {request:{address:{…}}})
 *   for await (const item of follow) …                  // snapshot / event / assistant-stream
 */
import crypto from 'node:crypto'
import { EventEmitter } from 'node:events'
import net from 'node:net'
import tls from 'node:tls'

export const MUX_PATH = '/api/remote.mux'
export const EVENTS_ENDPOINT = '$events'
export const EVENTS_RESULT_ENDPOINT = '$events/result'

const WS_GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'
const OPCODE = { continuation: 0x0, text: 0x1, binary: 0x2, close: 0x8, ping: 0x9, pong: 0xa }
const DEFAULT_MAX_MESSAGE_BYTES = 16 * 1024 * 1024
const DEFAULT_HANDSHAKE_TIMEOUT_MS = 10_000

// ---------------------------------------------------------------------------
// Raw RFC6455 client
// ---------------------------------------------------------------------------

/**
 * Minimal RFC6455 client with request-header support.
 *
 * Events: 'open', 'message' ({text, binary, isBinary}), 'ping', 'pong',
 * 'close' ({code, reason, wasClean}), 'error'.
 */
export class WebSocketClient extends EventEmitter {
  /** @param {net.Socket|tls.TLSSocket} socket */
  constructor (socket, { maxMessageBytes = DEFAULT_MAX_MESSAGE_BYTES } = {}) {
    super()
    this.socket = socket
    this.maxMessageBytes = maxMessageBytes
    this.buffered = Buffer.alloc(0)
    this.fragments = []
    this.fragmentsBytes = 0
    this.fragmentOpcode = null
    this.closeSent = false
    this.closeReceived = false
    this.destroyed = false

    socket.on('data', (chunk) => this._onData(chunk))
    socket.on('error', (error) => this._fail(error))
    socket.on('close', () => {
      this.destroyed = true
      if (!this.closeReceived) this.emit('close', { code: 1006, reason: '', wasClean: false })
    })
  }

  /**
   * Open a WebSocket connection.
   * @param {string|URL} url ws:// or wss:// URL
   * @param {object} [options]
   * @param {Record<string,string>} [options.headers] extra request headers (e.g. Cookie)
   * @param {number} [options.timeoutMs] handshake timeout
   * @param {number} [options.maxMessageBytes]
   */
  static connect (url, { headers = {}, timeoutMs = DEFAULT_HANDSHAKE_TIMEOUT_MS, maxMessageBytes } = {}) {
    const target = typeof url === 'string' ? new URL(url) : url
    const secure = target.protocol === 'wss:'
    const host = target.hostname.replace(/^\[|\]$/g, '')
    const port = target.port !== '' ? Number(target.port) : secure ? 443 : 80
    const key = crypto.randomBytes(16).toString('base64')
    const requestLines = [
      `GET ${target.pathname}${target.search} HTTP/1.1`,
      `Host: ${target.host}`,
      'Upgrade: websocket',
      'Connection: Upgrade',
      `Sec-WebSocket-Key: ${key}`,
      'Sec-WebSocket-Version: 13',
      ...Object.entries(headers).flatMap(([name, value]) => (value === undefined || value === null ? [] : [`${name}: ${value}`])),
      '',
      ''
    ]
    const requestText = requestLines.join('\r\n')

    return new Promise((resolve, reject) => {
      const socket = secure
        ? tls.connect({ host, port, servername: host })
        : net.connect({ host, port })
      let settled = false
      let input = Buffer.alloc(0)
      const timer = setTimeout(() => {
        finish(new Error(`WebSocket handshake with ${target.host} timed out after ${timeoutMs}ms`))
      }, timeoutMs)
      timer.unref?.()

      const finish = (error, client) => {
        if (settled) return
        settled = true
        clearTimeout(timer)
        socket.off('error', onError)
        socket.off('data', onHandshakeData)
        socket.off('close', onClose)
        if (error) {
          socket.destroy()
          reject(error)
        } else {
          resolve(client)
        }
      }
      const onError = (error) => finish(error)
      const onClose = () => finish(new Error(`WebSocket connection to ${target.host} closed during handshake`))
      const onHandshakeData = (chunk) => {
        input = Buffer.concat([input, chunk])
        const boundary = input.indexOf('\r\n\r\n')
        if (boundary === -1) {
          if (input.length > 64 * 1024) finish(new Error('WebSocket handshake response headers too large'))
          return
        }
        const head = input.subarray(0, boundary).toString('latin1')
        const rest = input.subarray(boundary + 4)
        const lines = head.split('\r\n')
        const statusLine = lines.shift() ?? ''
        const statusMatch = /^HTTP\/1\.1\s+(\d{3})/.exec(statusLine)
        if (statusMatch === null) return finish(new Error(`malformed WebSocket handshake status: ${statusLine}`))
        const status = Number(statusMatch[1])
        const responseHeaders = {}
        for (const line of lines) {
          const colon = line.indexOf(':')
          if (colon <= 0) continue
          responseHeaders[line.slice(0, colon).trim().toLowerCase()] = line.slice(colon + 1).trim()
        }
        if (status !== 101) {
          const body = rest.toString('utf8').slice(0, 200)
          return finish(new Error(`WebSocket upgrade rejected: HTTP ${status} ${statusLine.slice(statusLine.indexOf(' ') + 1)}${body ? ` — ${body}` : ''}`))
        }
        if (String(responseHeaders.upgrade ?? '').toLowerCase() !== 'websocket') {
          return finish(new Error('WebSocket upgrade response missing Upgrade: websocket'))
        }
        const expectedAccept = crypto.createHash('sha1').update(`${key}${WS_GUID}`).digest('base64')
        if (responseHeaders['sec-websocket-accept'] !== expectedAccept) {
          return finish(new Error('WebSocket upgrade response has an invalid Sec-WebSocket-Accept'))
        }
        if ((responseHeaders['sec-websocket-extensions'] ?? '') !== '') {
          return finish(new Error('WebSocket server negotiated an unsupported extension'))
        }
        socket.off('error', onError)
        socket.off('data', onHandshakeData)
        socket.off('close', onClose)
        const client = new WebSocketClient(socket, { ...(maxMessageBytes === undefined ? {} : { maxMessageBytes }) })
        socket.on('error', (error) => client._fail(error))
        if (rest.length > 0) client._onData(rest)
        client.emit('open')
        finish(null, client)
      }

      socket.on('error', onError)
      socket.on('close', onClose)
      socket.on('data', onHandshakeData)
      socket.once(secure ? 'secureConnect' : 'connect', () => socket.write(requestText))
    })
  }

  get open () {
    return !this.destroyed && !this.closeSent
  }

  // -- outbound ------------------------------------------------------------

  sendText (text) {
    return this._sendFrame(OPCODE.text, Buffer.from(String(text), 'utf8'))
  }

  sendBinary (data) {
    return this._sendFrame(OPCODE.binary, Buffer.isBuffer(data) ? data : Buffer.from(data))
  }

  ping (payload = Buffer.alloc(0)) {
    if (payload.length > 125) throw new Error('WebSocket ping payload must be <= 125 bytes')
    return this._sendFrame(OPCODE.ping, payload)
  }

  /** Send a close frame and half-close the socket. */
  close (code = 1000, reason = '') {
    if (this.closeSent || this.destroyed) return
    this.closeSent = true
    const reasonBytes = Buffer.from(String(reason), 'utf8').subarray(0, 123)
    const payload = Buffer.alloc(2 + reasonBytes.length)
    payload.writeUInt16BE(code & 0xffff, 0)
    reasonBytes.copy(payload, 2)
    try {
      this._sendFrame(OPCODE.close, payload)
    } catch {
      /* ignore */
    }
    this.socket.end()
    // Safety net: drop the socket if the peer never closes it.
    const timer = setTimeout(() => this.socket.destroy(), 2000)
    timer.unref?.()
  }

  terminate () {
    this.destroyed = true
    this.socket.destroy()
  }

  _sendFrame (opcode, payload) {
    if (this.destroyed || this.socket.destroyed) throw new Error('WebSocket is not open')
    const mask = crypto.randomBytes(4)
    const length = payload.length
    let header
    if (length < 126) {
      header = Buffer.alloc(2 + 4)
      header[1] = 0x80 | length
    } else if (length < 65536) {
      header = Buffer.alloc(4 + 4)
      header[1] = 0x80 | 126
      header.writeUInt16BE(length, 2)
    } else {
      header = Buffer.alloc(10 + 4)
      header[1] = 0x80 | 127
      header.writeBigUInt64BE(BigInt(length), 2)
    }
    header[0] = 0x80 | opcode
    const maskOffset = header.length - 4
    mask.copy(header, maskOffset)
    const masked = Buffer.allocUnsafe(length)
    for (let index = 0; index < length; index += 1) masked[index] = payload[index] ^ mask[index & 3]
    this.socket.write(Buffer.concat([header, masked]))
  }

  // -- inbound -------------------------------------------------------------

  _onData (chunk) {
    if (this.destroyed) return
    this.buffered = this.buffered.length === 0 ? chunk : Buffer.concat([this.buffered, chunk])
    for (;;) {
      const frame = this._parseFrame()
      if (frame === null) return
      this._handleFrame(frame)
      if (this.destroyed) return
    }
  }

  _parseFrame () {
    const buffer = this.buffered
    if (buffer.length < 2) return null
    const first = buffer[0]
    const second = buffer[1]
    const fin = (first & 0x80) !== 0
    const rsv = first & 0x70
    const opcode = first & 0x0f
    const masked = (second & 0x80) !== 0
    let length = second & 0x7f
    let offset = 2
    if (length === 126) {
      if (buffer.length < offset + 2) return null
      length = buffer.readUInt16BE(offset)
      offset += 2
    } else if (length === 127) {
      if (buffer.length < offset + 8) return null
      const big = buffer.readBigUInt64BE(offset)
      if (big > BigInt(this.maxMessageBytes)) {
        this._fail(new Error(`WebSocket frame exceeds max message size (${String(big)} bytes)`))
        return null
      }
      length = Number(big)
      offset += 8
    }
    let maskKey = null
    if (masked) {
      if (buffer.length < offset + 4) return null
      maskKey = buffer.subarray(offset, offset + 4)
      offset += 4
    }
    if (buffer.length < offset + length) return null
    let payload = buffer.subarray(offset, offset + length)
    if (maskKey !== null) {
      payload = Buffer.from(payload)
      for (let index = 0; index < payload.length; index += 1) payload[index] ^= maskKey[index & 3]
    }
    this.buffered = buffer.subarray(offset + length)
    return { fin, rsv, opcode, payload }
  }

  _handleFrame ({ fin, rsv, opcode, payload }) {
    if (rsv !== 0) {
      this._protocolError('non-zero RSV bits without a negotiated extension')
      return
    }
    switch (opcode) {
      case OPCODE.text:
      case OPCODE.binary: {
        if (this.fragmentOpcode !== null) {
          this._protocolError('new data frame while a fragmented message is open')
          return
        }
        if (fin) {
          this._emitMessage(opcode, payload)
          return
        }
        this.fragmentOpcode = opcode
        this.fragments = [payload]
        this.fragmentsBytes = payload.length
        return
      }
      case OPCODE.continuation: {
        if (this.fragmentOpcode === null) {
          this._protocolError('continuation frame without an open fragmented message')
          return
        }
        this.fragments.push(payload)
        this.fragmentsBytes += payload.length
        if (this.fragmentsBytes > this.maxMessageBytes) {
          this._fail(new Error('WebSocket fragmented message exceeds max message size'))
          return
        }
        if (!fin) return
        const complete = Buffer.concat(this.fragments)
        const messageOpcode = this.fragmentOpcode
        this.fragmentOpcode = null
        this.fragments = []
        this.fragmentsBytes = 0
        this._emitMessage(messageOpcode, complete)
        return
      }
      case OPCODE.ping: {
        this.emit('ping', payload)
        if (payload.length <= 125) {
          try {
            this._sendFrame(OPCODE.pong, payload)
          } catch {
            /* ignore */
          }
        }
        return
      }
      case OPCODE.pong:
        this.emit('pong', payload)
        return
      case OPCODE.close: {
        this.closeReceived = true
        let code = 1005
        let reason = ''
        if (payload.length >= 2) {
          code = payload.readUInt16BE(0)
          reason = payload.subarray(2).toString('utf8')
        }
        if (!this.closeSent) {
          this.closeSent = true
          try {
            this._sendFrame(OPCODE.close, payload.subarray(0, Math.min(payload.length, 125)))
          } catch {
            /* ignore */
          }
        }
        this.socket.end()
        this.destroyed = true
        this.emit('close', { code, reason, wasClean: true })
        return
      }
      default:
        this._protocolError(`unsupported WebSocket opcode 0x${opcode.toString(16)}`)
    }
  }

  _emitMessage (opcode, payload) {
    if (payload.length > this.maxMessageBytes) {
      this._fail(new Error('WebSocket message exceeds max message size'))
      return
    }
    const isBinary = opcode === OPCODE.binary
    this.emit('message', { isBinary, binary: isBinary ? payload : null, text: isBinary ? null : payload.toString('utf8') })
  }

  _protocolError (message) {
    try {
      this.close(1002, message.slice(0, 100))
    } catch {
      /* ignore */
    }
    this._fail(new Error(`WebSocket protocol error: ${message}`))
  }

  _fail (error) {
    if (this.destroyed) return
    this.destroyed = true
    this.socket.destroy()
    this.emit('error', error)
  }
}

// ---------------------------------------------------------------------------
// Gateway stream mux (logical streams over one WebSocket)
// ---------------------------------------------------------------------------

/** One logical Remote stream opened on the mux. */
export class LogicalStream extends EventEmitter {
  constructor (mux, { streamId, endpoint }) {
    super()
    this.mux = mux
    this.streamId = streamId
    this.endpoint = endpoint
    this.closed = false
    this.pending = []
    this.waiters = []
    this.terminalError = null
    this.finished = new Promise((resolve) => { this._resolveFinished = resolve })
  }

  /** Async-iterate every `item` value until end/error/close. */
  [Symbol.asyncIterator] () {
    return {
      next: () => this._next(),
      return: async () => {
        this.cancel()
        return { value: undefined, done: true }
      }
    }
  }

  _next () {
    if (this.pending.length > 0) return Promise.resolve({ value: this.pending.shift(), done: false })
    if (this.terminalError !== null) return Promise.reject(this.terminalError)
    if (this.closed) return Promise.resolve({ value: undefined, done: true })
    return new Promise((resolve, reject) => {
      this.waiters.push({ resolve, reject })
    })
  }

  _push (value) {
    const waiter = this.waiters.shift()
    if (waiter !== undefined) {
      waiter.resolve({ value, done: false })
      return
    }
    this.pending.push(value)
  }

  _finish (error = null) {
    if (this.closed) return
    this.closed = true
    this.terminalError = error
    for (const waiter of this.waiters.splice(0)) {
      if (error !== null) waiter.reject(error)
      else waiter.resolve({ value: undefined, done: true })
    }
    this.emit('end')
    this._resolveFinished()
  }

  /** Send one uplink item for stream methods that read input. */
  sendItem (value) {
    if (this.closed) throw new Error(`Remote stream ${this.streamId} is closed`)
    this.mux._send({ type: 'item', streamId: this.streamId, value })
  }

  /** Half-close the uplink (idempotent). */
  end () {
    if (this.closed) return
    this.mux._send({ type: 'end', streamId: this.streamId })
  }

  /** Cancel this logical stream; the server stops the Host iterator. */
  cancel () {
    if (this.closed) return
    this.mux._send({ type: 'cancel', streamId: this.streamId })
    this._finish()
  }
}

/** Authenticated Gateway stream mux connection. */
export class Mux {
  constructor (socket, { baseUrl, cookie }) {
    this.socket = socket
    this.baseUrl = baseUrl
    this.cookie = cookie
    this.streams = new Map()
    this.closed = false
    this._closeWaiters = []
    socket.on('message', ({ isBinary, text }) => this._onMessage({ isBinary, text }))
    socket.on('ping', () => { /* pong already sent by WebSocketClient */ })
    socket.on('error', (error) => this._failAll(error))
    socket.on('close', (info) => this._onSocketClose(info))
  }

  /** Open one logical stream; `args` are the endpoint's named wire args. */
  openStream (endpoint, args = {}) {
    if (this.closed) throw new Error('Gateway stream mux is closed')
    if (typeof endpoint !== 'string' || endpoint === '') throw new TypeError('endpoint must be a non-empty string')
    if (args === null || typeof args !== 'object' || Array.isArray(args)) throw new TypeError('args must be a plain object')
    const streamId = crypto.randomUUID()
    const stream = new LogicalStream(this, { streamId, endpoint })
    this.streams.set(streamId, stream)
    this._send({ type: 'open', streamId, endpoint, payload: { args } })
    return stream
  }

  /**
   * Reply to a scoped forwarded-event waterfall (approval/request,
   * user-questions/request). Goes over the Gateway's unary `$events/result`
   * HTTP RPC, not the WebSocket, mirroring the shipped web client.
   *
   * @param {object} options
   * @param {string} options.clientId `$events` ready frame's clientId
   * @param {string} options.eventId waterfall frame's eventId
   * @param {{kind:'next'}|{kind:'result',value?:unknown}|{kind:'rejected',error:object}} options.outcome
   */
  async answerWaterfall ({ clientId, eventId, outcome }) {
    if (typeof clientId !== 'string' || clientId === '') throw new TypeError('clientId is required')
    if (typeof eventId !== 'string' || eventId === '') throw new TypeError('eventId is required')
    if (!outcome || typeof outcome !== 'object') throw new TypeError('outcome is required')
    const rpcId = crypto.randomUUID()
    const response = await fetch(`${this.baseUrl}/api/${EVENTS_RESULT_ENDPOINT}`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', cookie: this.cookieHeader() },
      body: JSON.stringify({
        type: 'client-request',
        rpcId,
        method: EVENTS_RESULT_ENDPOINT,
        payload: { args: { clientId, eventId, outcome } }
      })
    })
    if (response.status === 401) throw new Error('Gateway rejected the auth cookie for $events/result (HTTP 401)')
    const text = await response.text()
    let message
    try {
      message = JSON.parse(text)
    } catch {
      throw new Error(`$events/result returned non-JSON (HTTP ${response.status}): ${text.slice(0, 200)}`)
    }
    if (message?.result?.ok !== true) {
      const error = message?.result?.error ?? {}
      const failure = new Error(`$events/result failed: ${error.code ?? 'unknown'} ${error.message ?? ''}`.trim())
      failure.code = error.code
      failure.details = error.details
      throw failure
    }
    return message.result.value
  }

  cookieHeader () {
    return `${this.cookie.name}=${this.cookie.value}`
  }

  _send (frame) {
    if (this.socket.destroyed) throw new Error('Gateway stream mux socket is closed')
    this.socket.sendText(JSON.stringify(frame))
  }

  _onMessage ({ isBinary, text }) {
    if (isBinary) {
      this._failAll(new Error('Gateway stream mux sent a binary frame'))
      this.socket.close(1003, 'text frames required')
      return
    }
    let frame
    try {
      frame = JSON.parse(text)
    } catch {
      this._failAll(new Error('Gateway stream mux sent invalid JSON'))
      this.socket.close(1008, 'invalid JSON')
      return
    }
    if (!frame || typeof frame !== 'object' || typeof frame.type !== 'string') return
    const stream = typeof frame.streamId === 'string' ? this.streams.get(frame.streamId) : undefined
    switch (frame.type) {
      case 'item':
        if (stream !== undefined && Object.hasOwn(frame, 'value')) {
          stream.emit('item', frame.value)
          stream._push(frame.value)
        }
        return
      case 'end':
        if (stream !== undefined) {
          this.streams.delete(frame.streamId)
          stream._finish()
        }
        return
      case 'error': {
        if (stream === undefined) return
        this.streams.delete(frame.streamId)
        const error = frame.error ?? {}
        const failure = new Error(`Remote stream ${frame.streamId} failed: ${error.code ?? 'unknown'} ${error.message ?? ''}`.trim())
        failure.code = error.code
        failure.details = error.details
        stream.emit('stream-error', failure)
        stream._finish(failure)
        return
      }
      default:
        return
    }
  }

  _failAll (error) {
    for (const [streamId, stream] of this.streams) {
      this.streams.delete(streamId)
      stream._finish(error)
    }
  }

  _onSocketClose (info) {
    if (this.closed) return
    this.closed = true
    const error = new Error(`Gateway stream mux closed (${info.code}${info.reason ? ` ${info.reason}` : ''})`)
    this._failAll(error)
    for (const waiter of this._closeWaiters.splice(0)) waiter.resolve(info)
  }

  /** Close the mux, cancelling every open logical stream. */
  close (code = 1000, reason = 'client done') {
    if (this.closed) return Promise.resolve()
    for (const stream of this.streams.values()) stream.cancel()
    this.streams.clear()
    return new Promise((resolve) => {
      this._closeWaiters.push({ resolve })
      this.socket.close(code, reason)
      const timer = setTimeout(() => {
        this.socket.terminate()
        resolve({ code: 1006, reason: 'forced', wasClean: false })
      }, 1500)
      timer.unref?.()
    })
  }
}

/** Convert an http(s) base URL to the mux WebSocket URL. */
export function muxUrl (baseUrl) {
  const url = new URL(baseUrl)
  if (url.protocol !== 'http:' && url.protocol !== 'https:') throw new TypeError(`baseUrl must be http(s): ${baseUrl}`)
  url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:'
  url.pathname = MUX_PATH
  url.search = ''
  url.hash = ''
  return url
}

/**
 * Open one authenticated Gateway stream mux.
 *
 * @param {object} options
 * @param {string} options.baseUrl upstream origin, e.g. http://127.0.0.1:57968
 * @param {{name:string,value:string}|string} options.cookie DSH auth cookie
 * @param {number} [options.timeoutMs] handshake timeout
 */
export async function openMux ({ baseUrl, cookie, timeoutMs = DEFAULT_HANDSHAKE_TIMEOUT_MS } = {}) {
  if (typeof baseUrl !== 'string' || baseUrl === '') throw new TypeError('baseUrl is required')
  const parsed = new URL(baseUrl)
  const normalizedCookie = typeof cookie === 'string'
    ? (() => {
        const colon = cookie.indexOf('=')
        if (colon <= 0) throw new TypeError('cookie string must look like "name=value"')
        return { name: cookie.slice(0, colon), value: cookie.slice(colon + 1) }
      })()
    : cookie
  if (!normalizedCookie || typeof normalizedCookie.name !== 'string' || typeof normalizedCookie.value !== 'string') {
    throw new TypeError('cookie {name,value} is required')
  }
  const socket = await WebSocketClient.connect(muxUrl(baseUrl), {
    timeoutMs,
    headers: {
      Cookie: `${normalizedCookie.name}=${normalizedCookie.value}`,
      Origin: parsed.origin,
      'User-Agent': 'dsh-native-ws-mux/1.0'
    }
  })
  return new Mux(socket, { baseUrl: parsed.origin, cookie: normalizedCookie })
}

// ---------------------------------------------------------------------------
// $events channel helper (forwarded Host events + waterfall answers)
// ---------------------------------------------------------------------------

/**
 * Open the `$events` forwarded-event stream and expose its lifecycle:
 *   await events.ready                  -> {clientId, host}
 *   events.onEmit(fn) / onWaterfall(fn) / onCancel(fn)
 *   await events.answer({eventId, outcome})
 */
export class EventsChannel extends EventEmitter {
  constructor (mux) {
    super()
    this.mux = mux
    this.clientId = null
    this.ready = new Promise((resolve, reject) => {
      this._resolveReady = resolve
      this._rejectReady = reject
    })
    this.stream = mux.openStream(EVENTS_ENDPOINT, {})
    this.stream.on('stream-error', (error) => {
      this._rejectReady(error)
      this.emit('error', error)
    })
    this.stream.on('end', () => {
      this._rejectReady(new Error('$events stream ended'))
      this.emit('close')
    })
    void this._consume()
  }

  async _consume () {
    try {
      for await (const item of this.stream) {
        if (!item || typeof item !== 'object' || typeof item.type !== 'string') continue
        if (item.type === 'ready') {
          this.clientId = item.clientId
          this._resolveReady({ clientId: item.clientId, host: item.host })
          this.emit('ready', item)
        } else if (item.type === 'emit') {
          this.emit('emit', item)
        } else if (item.type === 'waterfall') {
          this.emit('waterfall', item)
        } else if (item.type === 'cancel') {
          this.emit('cancel', item)
        } else {
          this.emit('unknown', item)
        }
      }
    } catch (error) {
      this._rejectReady(error)
      this.emit('error', error)
    }
  }

  onEmit (handler) { this.on('emit', handler) }
  onWaterfall (handler) { this.on('waterfall', handler) }
  onCancel (handler) { this.on('cancel', handler) }

  /** Answer one waterfall frame delivered to this channel. */
  answer ({ eventId, outcome }) {
    if (this.clientId === null) return Promise.reject(new Error('$events ready frame has not arrived yet'))
    return this.mux.answerWaterfall({ clientId: this.clientId, eventId, outcome })
  }

  close () {
    this.stream.cancel()
  }
}

/** Open the `$events` channel on an existing mux. */
export function openEventStream (mux) {
  return new EventsChannel(mux)
}

/** Named-arg request for session/follow on one top-level session. */
export function followSessionRequest (sessionId, { assistantStream = true, maxMessages } = {}) {
  if (typeof sessionId !== 'string' || sessionId === '') throw new TypeError('sessionId is required')
  return {
    request: {
      address: { kind: 'session', sessionId },
      ...(assistantStream === true ? { assistantStream: true } : {}),
      ...(Number.isFinite(maxMessages) ? { maxMessages } : {})
    }
  }
}

export default { WebSocketClient, Mux, LogicalStream, openMux, openEventStream, EventsChannel, followSessionRequest }
