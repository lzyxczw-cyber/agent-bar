/**
 * rpc.mjs — minimal read-only client for the DSH Gateway unary RPC at /api/<endpoint>.
 *
 * Wire format (verified on DSH 0.2.2-rc.3):
 *   POST /api/<endpoint>
 *   {"type":"client-request","rpcId":"<uuid>","method":"<endpoint>","payload":{"args":{...}}}
 *   -> {"type":"server-response","rpcId":"...","result":{"ok":true,"value":...}}
 * RPC-level failures keep HTTP 200 and arrive as {ok:false,error:{code,message,details}}.
 * Missing/expired auth cookie answers HTTP 401 (plain text), unknown endpoint 404.
 */
import { randomUUID } from 'node:crypto';

export class DshRpcError extends Error {
  constructor (code, message, details, status) {
    super (message);
    this.name = 'DshRpcError';
    this.code = code;
    this.details = details || {};
    this.status = status;
  }
}

export class DshNetworkError extends Error {
  constructor (message, cause) {
    super (message);
    this.name = 'DshNetworkError';
    this.cause = cause;
  }
}

export class DshRpc {
  constructor ({ origin, cookie, timeoutMs = 5000 }) {
    if (!origin) throw new TypeError ('origin is required');
    if (!cookie || !cookie.name) throw new TypeError ('cookie is required');
    this.origin = origin.replace (/\/+$/, '');
    this.cookie = cookie;
    this.timeoutMs = timeoutMs;
  }

  /** One unary RPC call. Throws DshRpcError / DshNetworkError. */
  async call (endpoint, args = {}) {
    const rpcId = randomUUID ();
    const body = JSON.stringify ({ type: 'client-request', rpcId, method: endpoint, payload: { args } });
    let response;
    try {
      response = await fetch (this.origin + '/api/' + endpoint, {
        method: 'POST',
        headers: { 'content-type': 'application/json', cookie: this.cookie.name + '=' + this.cookie.value },
        body,
        signal: AbortSignal.timeout (this.timeoutMs)
      });
    } catch (error) {
      throw new DshNetworkError ('DSH RPC ' + endpoint + ' network error: ' + error.message, error);
    }
    const text = await response.text ();
    if (response.status === 401) throw new DshRpcError ('auth/unauthorized', 'DSH auth cookie rejected (401)', {}, 401);
    if (response.status === 404) throw new DshRpcError ('gateway/not-found', 'DSH endpoint not found: ' + endpoint, {}, 404);
    let parsed;
    try { parsed = JSON.parse (text); } catch {
      throw new DshRpcError ('gateway/protocol', 'DSH returned non-JSON response (HTTP ' + response.status + ')', { body: text.slice (0, 200) }, response.status);
    }
    const result = parsed && parsed.result;
    if (!result || typeof result !== 'object') throw new DshRpcError ('gateway/protocol', 'DSH response has no result envelope', {}, response.status);
    if (result.ok !== true) {
      const error = result.error || {};
      throw new DshRpcError (error.code || 'gateway/internal', error.message || 'DSH RPC failed', error.details || {}, response.status);
    }
    return result.value;
  }

  /** session/list -> SessionSummary[] (already sorted by updatedAt desc). */
  async listSessions () {
    const value = await this.call ('session/list', { _request: {} });
    return Array.isArray (value && value.items) ? value.items : [];
  }

  /**
   * session/page. `address` is a session page address object
   * ({kind:'session',sessionId} or the subagent form), normalizing the
   * "past cursor" error by retrying at the cursor reported by the host.
   */
  async page (address, throughSeq, maxMessages = 2) {
    const normalizedAddress = typeof address === 'string'
      ? { kind: 'session', sessionId: address }
      : address;
    const request = { address: normalizedAddress, throughSeq, maxMessages };
    try {
      return await this.call ('session/page', { request });
    } catch (error) {
      if (error instanceof DshRpcError && error.code === 'gateway/bad-request' && typeof error.message === 'string') {
        const marker = 'past cursor ';
        const at = error.message.lastIndexOf (marker);
        if (at >= 0) {
          const cursor = Number (error.message.slice (at + marker.length).trim ());
          if (Number.isSafeInteger (cursor) && cursor >= 0 && cursor !== throughSeq) {
            return this.call ('session/page', { request: { ...request, throughSeq: cursor } });
          }
        }
      }
      throw error;
    }
  }
}
