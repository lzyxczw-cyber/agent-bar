# DSH → agentbar live bridge (read feed + opt-in approval control)

Status: **live-verified on 2026-11-16** against the running DeepSeek Harness
desktop app **0.2.2-rc.3** (Web GUI at http://127.0.0.1:49469, DSH home
`$HOME/.dsh`). It feeds real session/agent state, the current tool call,
running status and pending approval/question requests into a stable JSON file
and a Unix-socket NDJSON stream.

The Swift app does not need to know anything about DSH: it polls
`bridge/status.json` (or subscribes to `bridge/status.sock`) and renders
the `agents` array.

**The feed does not send prompts.** It never creates/deletes sessions,
changes settings, or writes anything under `$DSH_HOME`. It calls DSH read
endpoints and subscribes to its event stream. The opt-in local **control
channel** (§13) can answer an already-pending `approval/request` with
`allowed-once` / `rejected`, and a supported `user-questions/request`, via
`$events/result`. Question shapes that cannot be validated stay read-only.

---

## 1. Quick start

```bash
cd agent-bar/bridge
node dsh-bridge.mjs                 # foreground; Ctrl+C to stop
# or a one-shot snapshot:
node dsh-bridge.mjs --once
```

Requirements: **Node.js >= 20** (uses global `fetch`; tested on Node 24.14.0).
**No npm installs.** Files in this directory:

```
bridge/
  dsh-bridge.mjs        main process (HTTP polling + WS events + status feed)
  lib/dsh-auth.mjs      DSH home/secret discovery, cookie minting, GUI discovery
  lib/rpc.mjs           DSH Gateway unary RPC client (/api/<endpoint>)
  lib/translate.mjs     optional thoughtZh translation (DeepSeek chat API)
  lib/questions.mjs     user-questions request shape and answer validation
  lib/protocol.mjs      session/list probe: ok / mismatch / unavailable
  vendor/ws-mux.mjs     vendored zero-dependency RFC6455 + /api/remote.mux client
  tools/probe.mjs       read-only connectivity/diagnostic probe
  tools/asar-read.js    read-only reader for DSH's app.asar (endpoint research)
  tools/socket-client.mjs  example NDJSON socket consumer
  status.json           generated feed (schema v1)
  status.sock           generated Unix socket (only while the bridge runs)
  usage-state.json      generated daily usage baselines (mode 0600, keeps
                        "today's tokens" correct across restarts and midnight)
```

The external-agent reporter CLI is at the **repository root**:
`tools/agentbar-report.mjs` (see §11). It is not copied into Application
Support; run it from the checkout (or symlink it into your `PATH`).

A packaged `Agent Bar.app` ships the program files (`dsh-bridge.mjs`, `lib/`,
`vendor/`, this README) in `Contents/Resources/bridge/`. On launch the app runs
`tools/sync-bundled-bridge.sh` and writes that program into
`~/Library/Application Support/AgentBar/bridge/`, then starts Node from there.
`tools/` (probe, socket client, asar reader) stays in the repo. `status.json`,
`status.sock`, `usage-state.json`, `audit.log`, and `control/` are created only
in the runtime directory and are left in place when the program is refreshed.
`./start.sh` is the checkout path that syncs from `bridge/`; a DMG install does
not need it. The app uses a Node already installed on the machine.

Options:

```
--url <origin>         pin the DSH GUI origin (default: $DSH_WEB_URL, then lsof discovery)
--interval <ms>        feed tick interval (default 1000)
--active-window <min>  include sessions active within N minutes (default 15)
--max-agents <n>       cap agents in the feed (default 12)
--all                  include every known session (168 on this machine; verbose)
--once                 discover, print one snapshot to stdout, exit
--no-translate         disable thoughtZh translation (enabled by default)
--translate-external   also translate external agents' thoughts (opt-in: sends
                       Codex/WorkBuddy/... local reasoning to the DeepSeek API)
--no-external          ignore external agent reports
--agents-dir <dir>     external report directory (default: ~/Library/Application Support/AgentBar/agents;
                       env AGENTBAR_AGENTS_DIR also works)
--no-ws                HTTP polling only (no approval/event stream)
--no-socket            do not create status.sock
--out <file>           status.json path
--socket <file>        socket path
--verbose              log received events and page failures
```

Run it detached (example; no launchd needed):

```bash
cd agent-bar/bridge
nohup node dsh-bridge.mjs > /tmp/dsh-bridge.log 2>&1 &
```

---

## 2. Interface the Swift app consumes

### 2a. File `bridge/status.json` (schema 1, atomic write, mode 0600)

Rewritten on change (plus a 5 s heartbeat while running). Example (real data,
trimmed):

```json
{
  "schema": 1,
  "ts": 1794841066805,
  "bridge": { "pid": 2283, "startedAt": 1794841061000, "uptimeMs": 5805, "focusSessionId": "ce2302a1-..." },
  "dsh": {
    "url": "http://127.0.0.1:49469",
    "source": "env",
    "connected": true,
    "eventsConnected": true,
    "error": null,
    "sessionsKnown": 168
  },
  "counts": { "agents": 3, "running": 3, "approvals": 1 },
  "agents": [
    {
      "id": "session-13c9a6bc-ec08-4958-bd67-05262092bce0",
      "name": "飞书助手机器人配置与部署",
      "status": "approval",
      "busy": true,
      "tool": null,
      "detail": null,
      "project": "default-workspace",
      "cwd": "/Users/you/Documents/deepseek-harness/default-workspace",
      "model": "deepseek-flash",
      "preset": "cordis",
      "permissions": "danger-full-access",
      "origin": "session",
      "parentId": null,
      "focus": false,
      "lastActivity": 1794840344476,
      "approvals": [
        {
          "id": "82d7ad77-...",
          "kind": "question",
          "tool": "ask_user_question",
          "command": "这个「一排 agent 图标，选中的展开成长条显示运行状态、其余被挤到右端」的组件，你要做在哪里？",
          "reason": "...",
          "createdAt": 1794841066000
        }
      ]
    },
    {
      "id": "ce2302a1-b92c-413d-81d3-51fdb55ba048",
      "name": "DSH实时数据桥接原型调研",
      "status": "running",
      "busy": true,
      "tool": "run_code",
      "detail": "const s=require('./status.json'); console.log(...)",
      "project": "default-workspace",
      "origin": "subagent",
      "parentId": "session-d357ff06-...",
      "focus": true,
      "approvals": []
    }
  ]
}
```

Field notes:

| field | meaning |
| --- | --- |
| `dsh.connected` | HTTP polling to DSH is working |
| `dsh.eventsConnected` | live `$events` WebSocket is attached (approvals arrive only while true) |
| `agents[].status` | DSH rows: `approval` (pending approval/question), `running` (turn executing), `idle` (not executing). The menu bar shows `idle` as 待命, not as a completed round. External rows in the same array may also be `waiting`, `done` (this round ended), or `failed` |
| `agents[].busy` | turn is executing (independent of approval status) |
| `agents[].tool` / `detail` | current in-flight tool call + one-line argument summary, or null between tool calls |
| `agents[].approvals[]` | pending approval/question requests; `command` is the tool command when known, else the reason |
| `agents[].focus` | true for the DSH session that launched the bridge (`$DSH_SESSION_ID`) |
| `agents[].origin` | `session` (top-level) or `subagent` (child agent session) |
| `agents[].project` | basename of the session's working directory (the DSH "project") |

Feed contents are already filtered: running sessions + sessions active in the
last 15 min + any session with a pending approval, sorted approval → running →
idle, capped at 12 (`--all` lifts the filter).

### 2b. Unix socket `bridge/status.sock` (stream, mode 0600)

Newline-delimited JSON. On connect the client immediately receives the latest
snapshot, then one line per tick (~1 s):

```json
{"type":"snapshot", "schema":1, "ts":..., "dsh":{...}, "counts":{...}, "agents":[...]}
```

Test it with:

```bash
node tools/socket-client.mjs ./status.sock
```

No request/answer protocol: the socket is one-way telemetry (read-only).

---

## 3. How it works (the discovered DSH interfaces)

### 3.1 Auth — minting a browser-session cookie from the durable secret

DSH's Web GUI authenticates every request with an HMAC-signed cookie:

```
name  = "dsh-auth-" + base64url(sha256(authority))       e.g. authority "127.0.0.1:49469"
value = "v1." + base64url(JSON payload) + "." + base64url(HMAC-SHA256(secret, body))
payload = {"version":1,"authority":"127.0.0.1:49469","issuedAt":<ms>,"expiresAt":<ms>}
```

Source of truth (read directly from the shipped app.asar):

- `dsh/node_modules/@deepseek-ai/dsh-client-connection/src/browser-auth.ts`
  (mirrored in `lib/index.js`) — cookie name/format/HMAC, the 32-byte secret
  persisted under credential key `client-connection/browser-session`, the
  desktop launch token (random per process, only ever sent to Electron main via
  IPC, so not readable from disk), and the rule that a valid browser cookie is
  admitted as the **owner browser peer**.
- `dsh/node_modules/@deepseek-ai/dsh-desktop-host/lib/index.js` — desktop host
  boots the web app with `--host 127.0.0.1 --port 0` and sends
  `authenticatedUrl(...)` to Electron via `process.send({type:'ready',url})`.
- `dsh/node_modules/@deepseek-ai/dsh-host-webserver/src/index.ts` — HTTP server
  + exact-path WebSocket upgrade routes.
- The durable secret itself lives at `$DSH_HOME/.credentials.yaml` →
  `records["client-connection/browser-session"].payload.secret` (32 bytes,
  base64url). `$DSH_HOME` is `$HOME/.dsh` here.
- Why not read the browser cookie directly? The Chrome cookie row for this GUI is
  Chromium-encrypted (`value` empty, `encrypted_value` 211 bytes), so it
  cannot be read without Keychain access. Minting from the durable secret is
  equivalent, stable across restarts, and needs no browser.
- What about the `?token=` launch URL? It is random per DSH process and only
  exists in Electron main-process memory / the browser address bar; it is not
  persisted. Minting avoids it entirely.

### 3.2 Gateway HTTP unary RPC

Dispatcher source: `dsh/node_modules/@deepseek-ai/dsh-api-gateway/src/index.ts`
(+ `README.md`) and `dsh/node_modules/@deepseek-ai/dsh-client-connection/src/index.ts`
(`/api` route). Wire format:

```http
POST /api/session/list
content-type: application/json
cookie: dsh-auth-...=v1....

{"type":"client-request","rpcId":"<uuid4>","method":"session/list","payload":{"args":{"_request":{}}}}
-> {"type":"server-response","rpcId":"...","result":{"ok":true,"value":{...}}}
```

Endpoints used by this bridge:

| endpoint | args | gives |
| --- | --- | --- |
| `session/list` | `{"_request":{}}` | all sessions: `sessionId, running, updatedAt, cwd, origin, parentSessionId, projections.values{title,permissions,agentPreset,modelSelection,subagentCatalog}, projections.asOfSeq` |
| `session/page` | `{"request":{"address":{"kind":"session","sessionId":"..."},"throughSeq":<asOfSeq>,"maxMessages":2}}` | tail of the durable event log: `tool/call` / `tool/result` / `approval/*` events used to derive the current tool call. Subagent sessions require their durable parent address: `{"kind":"subagent","parentSessionId":"session-...","childSessionId":"<uuid>","mode":"<from parent projections.subagentCatalog>"}` |

RPC failures keep HTTP 200 with `result.ok=false` and a typed `code` (e.g.
`session/agent-busy`, `gateway/bad-request`); HTTP 401 means the cookie was
rejected.

### 3.3 Gateway WebSocket stream mux `/api/remote.mux` and `$events`

Sources: `dsh/node_modules/@deepseek-ai/dsh-api-gateway/src/stream-{protocol,server}.ts`,
`src/types/access.ts` and the `$events` forwarding contract in its README.
The socket is authenticated by the same cookie and multiplexes logical streams:

```
client -> {"type":"open","streamId":"<uuid>","endpoint":"$events","payload":{"args":{}}}
server -> {"type":"item","streamId":"<uuid>","value":{"type":"ready","clientId":"...","host":{...}}}
          {"type":"item",...,"value":{"type":"emit","event":"api-session/status","args":["session-...",true]}}
          {"type":"item",...,"value":{"type":"waterfall","event":"approval/request","eventId":"...","agentId":"session-...","request":{...}}}
          {"type":"item",...,"value":{"type":"cancel","eventId":"..."}}
```

Events used:

- `api-session/status` `[sessionId, running]` — turn started/finished.
- `api-session/activity` `[sessionId, epochMs]`, `api-session/added`
  `[SessionSummary]`, `api-session/removed` `[sessionId]` — keep the
  session map fresh.
- `approval/request` waterfall — pending tool approval
  (`{toolName, callId, reason, displayReason:{en,zh,...}}`).
- `user-questions/request` waterfall — pending user question
  (`{questions:[{id,question,header,options}]}`).
- `cancel` `{eventId}` — the interaction was answered/cancelled elsewhere.

The bridge only **observes** waterfalls; it never posts `$events/result`.
Live-verified: a pending user question was re-delivered to a fresh bridge
connection, appeared in `status.json` as `status:"approval"`, and closing
the bridge did not cancel it (the GUI kept showing it).

### 3.4 GUI discovery

The desktop DSH host picks a random loopback port at every start. Discovery order:

1. `--url`
2. `$DSH_WEB_URL` (exported into DSH shells; currently http://127.0.0.1:49469)
3. `lsof -nP -iTCP -sTCP:LISTEN -Fpcn` loopback listeners, desktop
   (`DeepSeek Harness`) processes first, then everything else; each candidate
   is probed with `GET /` + minted cookie until the DSH index HTML answers.

If DSH restarts on another port, the next failed HTTP call drops the bridge into
re-discovery and it re-attaches automatically (5 s throttle).

---

## 4. Failure behaviour

- DSH not running / credentials missing: `dsh.connected=false`, `dsh.error`
  describes the reason, `agents` is empty. The bridge keeps retrying (5 s
  throttle) and keeps serving `status.json` + socket.
- DSH restarts or moves port: HTTP failure → re-discover → re-attach.
- WebSocket drops: `dsh.eventsConnected=false`; HTTP polling keeps working,
  reconnects with 1→15 s exponential backoff. Pending approvals are re-delivered
  after reconnect (verified).
- `$DSH_HOME` misconfigured: the bridge reports the credential-store path in
  `dsh.error` and does not crash.
- No DeepSeek key / DeepSeek unreachable: `thoughtZh` stays `null`, the rest of
  the feed is unaffected (one throttled status-only log line, no text/key).
- External agents directory missing or unreadable: silently ignored; malformed,
  stale or unreadable report files are skipped without failing the tick.
- No DSH writes except an explicit local approval or supported question answer (§13); the only shell-out is read-only `lsof`.

---

## 5. Limitations / what is NOT possible

- **The feed does not send prompts; approvals and supported questions can be
  answered through an opt-in local control channel.** A local `control/`
  directory accepts a decision for an already-pending `approval/request`, or a
  supported `user-questions/request`; the bridge then posts `$events/result`
  (see §13). Question shapes that fail validation stay read-only.
  `--no-control` disables this entirely.
- Current-tool granularity: derived by polling `session/page` every ~1.2 s for
  running/approval sessions. Between tool calls it is null (model thinking);
  a tool call shorter than the poll interval may be missed.
- `session/list` is a heavy call (~200 KB for 168 sessions on this machine), so
  it is cached for 2.5 s; `session/page` tails are also cached briefly. Feed
  latency is ~1 s plus DSH's own projection watermark lag.
- Approval state is event-driven. Pending requests are re-delivered on
  (re)connect (verified for a question), but a request already answered before
  the bridge starts is of course not reported.
- No chat token stream / transcript content is exposed (not needed for a notch
  status bar; the `session/follow` stream could add it later).
- Session filtering is heuristic: `running` OR updated in last 15 min OR
  pending approval, cap 12. Archived/historical sessions are excluded unless
  `--all`.
- Tested against DSH desktop **0.2.2-rc.3** only. DSH is pre-release; endpoints,
  event names and the cookie format can change between versions.
- Requires access to the same macOS user's `$DSH_HOME` (secret file mode 0600).
- `thoughtZh` is machine translation: idiomatic nuance can be lost. The UI must
  fall back to `thought` when `thoughtZh` is null.
- External agent rows are only as fresh as their reporter: without a heartbeat
  every ≤120 s they disappear from the feed (by design, so dead wrappers do not
  linger).
- The whole feed (session titles, cwd paths, tool commands) is local-only; the
  socket is 0600 and `status.json` is 0600. Do not expose them over a network.

---

## 6. Security notes

- The bridge reads the 32-byte browser-session signing secret from
  `$DSH_HOME/.credentials.yaml` and mints a short-lived (24 h) equivalent of the
  normal GUI cookie **in memory**. It never logs or persists the secret/cookie.
- It does not use the `?token=` launch URL, does not touch Chrome's cookie DB,
  and does not need Keychain access.
- Feed reads only; the one write is `$events/result` for an explicit local
  approval decision (see §13). No `session/prompt`, `session/cancel`, or
  settings writes exist. The control directory is 0700, the token file 0600,
  and every attempt is appended to `audit.log` (0600).
- `thoughtZh` translation sends only the reasoning text to
  `api.deepseek.com` (the one outbound network call besides the local DSH
  loopback). The API key from env / `refs.DEEPSEEK_API_KEY` is used solely as
  the bearer header and is never logged, persisted or exposed in the feed.
- External agent report files are ordinary user-owned local JSON (0600 on the
  files the CLI writes). The bridge only reads them; it never deletes or
  rewrites them.

---

## 7. Verification log (exact commands, 2026-11-16)

```bash
cd agent-bar/bridge

# cookie minting + unary RPC (168 real sessions, 3 running)
node dsh-bridge.mjs --once

# discovery fallback without $DSH_WEB_URL (finds 49469 via lsof)
env -u DSH_WEB_URL node dsh-bridge.mjs --once

# graceful failure when DSH home/credentials are missing
DSH_HOME=/tmp/dsh-home-does-not-exist node dsh-bridge.mjs --once   # exits 1, prints error JSON

# live run: events + status.json + socket
node dsh-bridge.mjs --interval 1000 &
node tools/socket-client.mjs ./status.sock     # 2 NDJSON snapshot lines
cat status.json                                # counts, tool calls, pending question
node tools/probe.mjs --seconds 3               # prints $events frames incl. a real waterfall
```

Observed highlights: `session/list` returned 168 sessions (3 running), the
current tool call was resolved for all three running sessions including a
subagent one (`ce2302a1-...` via its durable parent address), and a real
`user-questions/request` waterfall was captured and exposed as a pending
question. After each test the bridge was stopped with SIGTERM (socket cleaned up,
no leftover process).

---

## 8. If DSH changes / for future work

- Inspect the shipped sources with `tools/asar-read.js`:
  `node tools/asar-read.js list dsh/node_modules/@deepseek-ai/dsh-api-gateway`
  `node tools/asar-read.js grep 'remote.mux|events|approval/request' dsh/node_modules/@deepseek-ai`
  (app.asar is a file at
  `/Applications/DeepSeek Harness.app/Contents/Resources/app.asar`).
- If the cookie format changes: `lib/dsh-auth.mjs` (format) and
  `dsh-client-connection/src/browser-auth.ts` (source).
- If endpoints change: `dsh-api-session-controller/src` (session methods) and
  `dsh-api-gateway/README.md` (RPC/mux).
- Natural next step for the notch UI: render `status.json`; later add a
  `session/follow` stream for assistant deltas, and (optional, explicit
  opt-in only) an approval forwarding layer using `$events/result` — not part
  of this local bridge.

---

Prior art / cross-check used while building this: the user's own zero-dependency
reverse-engineering notes for the DSH iOS companion live under
`/Volumes/XC1_DATA/DSH_iOS/native/` (`API-NOTES.md`, `WS-EVENTS-NOTES.md`,
`ws-mux.mjs`); the WebSocket client in `vendor/ws-mux.mjs` is vendored from
there and was live-verified by that project. This bridge adds the credential
minting, auto-discovery, HTTP polling, tool-call derivation and the status feed.

---

## 9. status feed v2 additions (2026-11-17)

Status-feed additions used by the notch UI:

- `agents[].thought`: latest assistant `reasoning` text from the session page (trimmed to 1600 chars).
- `agents[].process`: last ~10 process steps, `{kind: think|tool|result|reply, label, detail, at(ms)}`.
- `agents[].tokens`: per-session token usage (`uncachedInputTokens + outputTokens`).
- `usage.tokensToday` / `usage.sessionsToday`: aggregate over sessions updated since local midnight.
- `account`: `{status, currency, balance, bonusBalance, usageUrl, topUpUrl}` from
  `account/getState` + `account/getBalance` (client metadata: version/locale/timezoneOffsetSeconds);
  60s cache, failures become `status: "failed"`.
- session page depth is now 8 messages (was 2) to provide process context.
- `agents[].thoughtZh`: Simplified-Chinese translation of `thought` (see §10), else `null`.
  `thought` itself is never modified.
- external agents are merged into the same `agents` array with
  `origin:"external"`, `external:true` and ids prefixed `ext:` (see §11).
- `bridge.translate`: `{enabled, keySource, cached, pending}` diagnostics
  (no text, no key).

All new fields are optional; consumers can ignore them.

---

## 10. `thoughtZh` — localized thinking (on by default for DSH)

The notch UI is Chinese-first, so the bridge can translate each agent's latest
English reasoning into Simplified Chinese. The result is a **separate field**;
`agents[].thought` always keeps the original text and encoding.

Translation applies to **DSH sessions by default**. External agent reports
(Codex reasoning, WorkBuddy spans, any `tools/agentbar-report.mjs --thought`)
come from other applications' local state and are **not** sent to a third-party
API unless `--translate-external` is passed. Without that flag their `thought`
is shown as-is and `thoughtZh` stays `null`.

- **Key resolution** (in this order; the environment wins):
  1. `$DEEPSEEK_API_KEY`
  2. `$DSH_HOME/.credentials.yaml` → `refs.DEEPSEEK_API_KEY`

  The key is only used in the `Authorization: Bearer <key>` header of the
  translation request. It is **never logged, written to disk, or included in
  `status.json`**. No key = feature silently disabled (`thoughtZh` stays null).
- **Request**: `POST https://api.deepseek.com/chat/completions` with
  `model:"deepseek-chat"`, `temperature:0.2`, `max_tokens:400`, an 8 s
  timeout, and the user message truncated to 1200 characters. System prompt:

  ```
  你是翻译器。把英文技术思考翻译成简体中文，保留代码、路径、工具名、专有名词，不解释，只输出译文。
  ```
- **Scheduling**: asynchronous and fire-and-forget from the 1 s tick — the feed
  never waits for DeepSeek. At most **one** translation request is in flight,
  at least **8 s** between two requests for the same agent, and only when the
  thought text actually changed (tracked by sha256).
- **Cache**: LRU of **64** translations keyed by sha256 of the source text.
- **Falls back to `null`** (the App then shows `thought` unchanged) when the
  text is empty, already mostly Chinese, there is no API key, or the request
  fails. A failed text is retried no more often than every 60 s. Failures log at
  most one throttled **status-only** line ("thought translation failed
  (HTTP 503)..."), never the text or the key.
- **`--no-translate`** turns the whole feature off (`thoughtZh` is then always
  null). `--once` waits up to 12 s for queued translations before printing, so
  the printed snapshot already contains `thoughtZh`.
- Without a `thoughtZh` the App must keep using `thought`; the bridge never
  removes or rewrites the original.

Example agent row with both fields:

```json
{
  "id": "session-...",
  "thought": "Let me check the build output and run the tests.",
  "thoughtZh": "让我检查构建输出并运行测试。"
}
```

---

## 11. External agents — Codex / Claude Code / any CLI agent

Any local process can show up in the notch by writing **one JSON file per
agent** into:

```
~/Library/Application Support/AgentBar/agents/<id>.json
```

The directory is updated by the reporter, not by the bridge. The bridge scans it
on every tick; a **missing directory is fine**. Override the location with
`--agents-dir <dir>` or `AGENTBAR_AGENTS_DIR` (the env var also applies to
the reporter CLI).

### 11.1 Report schema (lenient: every field but `id` is optional)

```json
{
  "id": "codex",
  "name": "Codex",
  "status": "running",
  "project": "agent-notch",
  "tool": "Bash: swift build",
  "detail": "optional argument summary",
  "thought": "optional latest thinking",
  "tokens": 1234,
  "startedAt": 1763337600000,
  "updatedAt": 1763337660000,
  "approvals": [
    { "id": "a1", "tool": "Bash", "command": "Bash: rm -rf build", "reason": "optional", "createdAt": 1763337600000 }
  ],
  "process": [
    { "kind": "tool", "label": "Bash", "detail": "swift build", "at": 1763337600000 }
  ]
}
```

| field | type | notes |
| --- | --- | --- |
| `id` | string | falls back to the file name; final feed id is `"ext:<id>"` |
| `name` | string | display name, defaults to `id` |
| `status` | string | `idle` (待命, has not started), `running`, `waiting`, `done` (this round ended), `failed`. Anything else is `idle`, not `done` |
| `project` / `tool` / `detail` | string | shown as-is; `tool`/`detail` are the "current action" line |
| `thought` | string | latest reasoning; translated to `thoughtZh` only with `--translate-external` (DSH sessions are translated by default) |
| `tokens` | number | optional token counter |
| `startedAt` | number (ms) | first report time; preserved by the CLI |
| `updatedAt` | number (ms) | heartbeat time; defaults to the file mtime |
| `approvals[]` | array | normalized to `{id, kind:"approval", tool, command, reason, createdAt}`; **display-only** — the bridge's control channel only answers DSH approval events, not external reports. Codex, Claude Code, WorkBuddy, Grok Bot, and Hermes have no safe local write path from this process (token + still-pending id), so the panel does not offer Allow |
| `process[]` | array | last 10 steps kept as `{kind, label, detail, at}` |
| `appBundleID` | string | optional macOS bundle id; the notch uses it for "open app" / double-click |
| `sessions[]` | array | optional child sessions, normalized to `{id, project, tool, detail, status, startedAt, updatedAt, tokens, thought}`; unknown session status is `idle`, not `done`. The notch shows them under the parent row |

### 11.2 How rows are merged into `status.json`

- `id`: `"ext:<file-id>"` (never collides with DSH session ids).
- `origin: "external"`, `external: true`, `focus: false`, `parentId: null`.
- `cwd` / `model` / `preset` / `permissions` are `null` unless the report
  provides them; `busy` is `true` only for `status:"running"`.
- `appBundleID` and up to 6 child `sessions` are passed through for the grouped
  adapters (one parent row per desktop app).
- `lastActivity` = `updatedAt` → `startedAt` → file mtime.
- **Freshness**: a report whose `updatedAt` (or file mtime when absent) is
  older than **120 s** is treated as stale and hidden; reports older than
  **10 min** are ignored entirely. The bridge never deletes report files.
  Deleting the file removes the agent from the next tick.
- External rows take part in the same sort (`approval` → running/waiting →
  others) and `--max-agents` cap as DSH rows. `counts` include them.

### 11.3 Reporter CLI `tools/agentbar-report.mjs`

Zero dependencies, executable, atomic write (temp + rename) with mode **0600**,
creates the directory with mode 0700 when needed. `startedAt` is written once
and preserved by later heartbeats; `updatedAt` is always `Date.now()`. Fields
not passed in are preserved, so a heartbeat can be one line.

```bash
cd agent-bar

# first report (creates the JSON + sets startedAt)
node tools/agentbar-report.mjs \
  --id codex --name Codex --status running --project agent-notch \
  --tool "Bash: swift build" --thought "正在编译..."

# heartbeat / progress update (only passed fields change)
node tools/agentbar-report.mjs --id codex --status running --tool "Bash: swift test"

# finish / fail
node tools/agentbar-report.mjs --id codex --status done
node tools/agentbar-report.mjs --id codex --status failed --detail "exit 1"

# remove the report entirely
node tools/agentbar-report.mjs --id codex --remove

# JSON form (or pipe JSON on stdin when no other flags are given)
node tools/agentbar-report.mjs --json '{"id":"codex","status":"running","tool":"Bash"}'
echo '{"id":"codex","status":"done"}' | node tools/agentbar-report.mjs
```

All fields from the schema except timestamps can be set through `--json`
(`updatedAt` is always refreshed, `startedAt` is kept from the first write).
`--dir <dir>` / `AGENTBAR_AGENTS_DIR` point the CLI at another directory.
Because shell hooks sometimes pipe their own JSON into a command, the CLI only
auto-reads stdin when no field flags are present; use `--json -` to be explicit.

### 11.4 Integration examples (heartbeat every 30–60 s, report done at the end)

**Codex (wrapper around the CLI).** Codex takes tens of seconds to minutes, so a
wrapper that heartbeats every 45 s and reports the exit status is the simplest
integration:

```bash
#!/bin/bash
# codex-island.sh — run Codex with an Agent Bar heartbeat.
set -u
REPORT="node /path/to/agent-bar/tools/agentbar-report.mjs"
ID="${AGENT_ISLAND_ID:-codex}"
PROJECT="$(basename "$PWD")"

"$REPORT" --id "$ID" --name Codex --status running --project "$PROJECT" --tool "Codex" >/dev/null
( while sleep 45; do
    "$REPORT" --id "$ID" --status running --project "$PROJECT" >/dev/null
  done ) &
HEARTBEAT=$!

codex "$@"
STATUS=$?
kill "$HEARTBEAT" 2>/dev/null
if [ "$STATUS" -eq 0 ]; then
  "$REPORT" --id "$ID" --status done --detail "exit 0" >/dev/null
else
  "$REPORT" --id "$ID" --status failed --detail "exit $STATUS" >/dev/null
fi
exit "$STATUS"
```

**Claude Code (legacy hooks).** Older builds installed `PreToolUse` / `Stop`
hooks that reported a tool name. The desktop watcher now reads Claude Code's
transcripts directly (§11.5), so installation is no longer needed. This
example is kept for understanding old setups; remove it with
`node tools/agentbar-install-adapter.mjs uninstall-claude`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "node /path/to/agent-bar/tools/agentbar-report.mjs --id claude-code --name 'Claude Code' --status running --tool 'Claude Code' >/dev/null"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "node /path/to/agent-bar/tools/agentbar-report.mjs --id claude-code --status done >/dev/null"
          }
        ]
      }
    ]
  }
}
```

For any other CLI agent the pattern is the same: report `running` at start,
refresh `updatedAt` every 30–60 s while it works, then report `done` /
`failed`, or `--remove` when it is gone.

### 11.5 Claude Code transcripts (read-only)

`tools/agentbar-app-adapters.mjs` reads `~/.claude/projects/<encoded-cwd>/*.jsonl`
(override the config root with `CLAUDE_CONFIG_DIR`). Nothing is written to
`~/.claude/`.

- Only first-level `.jsonl` files; subdirectories such as `tool-results/` are
  ignored. Files whose last meaningful record is older than 15 minutes are
  dropped.
- The last record types `assistant` / `user` drive the state: an unanswered
  `tool_use`, a `tool_result`, or a real user prompt means `running`;
  `stop_reason: end_turn` without a tool call means `done`.
- `project` is `basename(cwd)`; `detail` carries the git branch.
- `tokens` is **today's** total, deduplicated by `message.id`, summing
  `input_tokens + output_tokens + cache_creation_input_tokens` and excluding
  `cache_read_input_tokens`.
- Files ending in `continued-in` are skipped: the successor transcript already
  contains their history, so showing both would duplicate the session.
- Thinking text is truncated to 600 characters. Approvals stay read-only:
  transcripts cannot answer a pending permission prompt.

---

## 12. Verification log — v2 additions (2026-11-17)

```bash
cd agent-bar

# translation in a one-shot snapshot (key never printed)
node bridge/dsh-bridge.mjs --once
#   -> bridge.translate {enabled:true, keySource:"credentials", ...}
#   -> active sessions carry agents[].thoughtZh (Chinese); thought unchanged

# feature off
node bridge/dsh-bridge.mjs --once --no-translate
#   -> bridge.translate.enabled=false, thoughtZh=null

# external agent round-trip
node tools/agentbar-report.mjs --id codex --name Codex --status running \
  --project agent-notch --tool "Bash: swift build" --thought "正在编译..."
node bridge/dsh-bridge.mjs --once         # agents[] contains id "ext:codex",
                                          # origin "external", external true
node tools/agentbar-report.mjs --id codex --remove
node bridge/dsh-bridge.mjs --once         # ext:codex is gone again

# isolated directory + freshness checks (no App Support writes)
AGENTBAR_AGENTS_DIR=/tmp/island-agents node bridge/dsh-bridge.mjs --once
```

Observed on macOS 27.0 / Node 24.14.0: DeepSeek translation of a normal
reasoning chunk takes ~0.5–1 s; a fresh report appears in the next snapshot and
disappears immediately after `--remove`; stale (>120 s) and malformed reports
are skipped without affecting the DSH rows.

---

## 13. Approval control (opt-in write path, 2026-11-17)

This is the only code path that writes to DSH.

### 13.1 Threat model and guards

- Same local user only: the bridge and the notch App run as the same macOS user,
  and the control directory lives inside the per-user App Support directory.
- The bridge generates a fresh random 32-byte token on every start and writes it
  to `control/token` (0600). A request must include that token; comparisons use
  `crypto.timingSafeEqual`.
- A request can only answer an **already pending** event that this bridge
  event stream received. It carries an event id, decision, and optional session
  id; the bridge rejects unknown/stale ids, session mismatches, bad tokens, and
  requests older than 60 s.
- Approval decisions are `allowed-once` and `rejected`. Question decisions are
  `answered` (value `{answers:[{id, selected, custom?}]}`, `selected` = option
  labels) and `cancelled` (`UserQuestionError` / `ASK_CANCELLED`). Unknown
  intents and other shapes that fail `buildQuestionResult` stay read-only.
  There is no way to send a prompt or change a command.
- Every attempt (ok, stale, bad token, offline, error) is appended to
  `audit.log` with timestamp, approval id, session id, tool, command, decision,
  and result. `audit.log` and the control token are 0600; the directory is 0700.
- `--no-control` disables the channel; `--control-dir <dir>` moves it.

### 13.2 Request file schema

The notch App writes one JSON file atomically into `control/request-*.json`:

```json
{
  "schema": 1,
  "approvalId": "<eventId from agents[].approvals[].id>",
  "sessionId": "session-...",
  "tool": "bash",
  "command": "allowed-once: ...",
  "decision": "allowed-once",
  "requestedAt": 1763337600000,
  "token": "<contents of control/token>"
}
```

`decision` must be `allowed-once` or `rejected` for an approval, or `answered`
/ `cancelled` for a supported question. An `answered` request also carries
`answers`. The bridge consumes at most
four request files per tick, deletes handled files, and retries a file only
while the event stream is offline (up to 15 s).

### 13.3 Answer path

On success the bridge calls the shipped ws-mux helper:

```js
await this.events.answer({
  eventId: approval.id,
  outcome: { kind: 'result', value: request.decision }
})
```

which posts `$events/result` with the event stream's `clientId` and `eventId`.
For an approval, `value` is the decision string. For a question, `value` is
`{answers:[...]}` from `bridge/lib/questions.mjs`, or the cancel outcome is
`{kind:'rejected', error:{name:'UserQuestionError', code:'ASK_CANCELLED', ...}}`.
The pending item is removed locally; the next snapshot drops it.

### 13.4 Verification

Tested 2026-11-17 against DSH 0.2.2-rc.3 with a fresh `workspace-write` session:

- a Bash escalation triggered `approval/request`; the notch card appeared;
- first long-press armed the dangerous double-confirm; second long-press wrote a
  `request-*.json`;
- bridge audit recorded `allowed-once`; the approval disappeared; the session
  resumed and created the requested file; `turn/end` completed;
- a second request was rejected from the UI (`rejected`); audit recorded it and
  the agent observed the refusal.

Supported `user-questions/request` items can be answered from the panel.
Shapes that `normalizeUserQuestions` marks `answerable: false` (unknown intent,
duplicate labels, and similar) stay read-only and must be answered in the DSH GUI.

If `session/list` is reached but its envelope, auth, or route does not match,
`dsh.protocol` is `mismatch` and the menu-bar chip shows 协议不匹配 instead of
falling back to simulated demo agents.

