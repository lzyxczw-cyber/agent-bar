# Claude Code 只读会话支持 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让状态条直接读取 Claude Code 的本地会话文件，显示项目、分支、当前工具、最新思考和今日 token，最多 3 个并发会话。

**Architecture:** 在现有 adapter watcher 中新增 `claude` 组：增量 tail 读取 `~/.claude/projects/*/*.jsonl`，把记录归约成会话状态（纯函数放 `tools/lib/adapter-logic.mjs`），再产出标准 external-agent 报告交给 `aggregateApp` 折叠。全程只读，不改 Claude 配置，不接管审批。

**Tech Stack:** Node.js ≥ 20（无第三方依赖）、node:test、现有 `tools/agentbar-app-adapters.mjs` / `tools/lib/adapter-logic.mjs` / `tests/*.mjs`。

**Spec:** `docs/superpowers/specs/2026-11-19-claude-transcript-support-design.md`

## Global Constraints

- 只读：不得写入 `~/.claude/` 下任何文件，不修改 Claude 配置。
- 不新增依赖；测试用 `node --test`，Swift 测试不动。
- 报告继续走 `writeReport`（目录 0700、文件 0600、`source = agentbar-app-adapters`）。
- 日志不得包含消息正文；只记文件名尾部和错误类型。
- tick 预算：每次每文件最多读 256 KB；首次看到文件最多回读 16 MB。
- 活跃窗口：最后一条有效记录起 15 分钟（`15 * 60 * 1000`）。
- token 口径：只计本地当天、按 `message.id` 去重、`input + output + cache_creation`，不含 `cache_read`。
- 最多同时上报 3 个会话；父行摘要取最后活动的会话。
- 文案用中文；代码注释用英文，遵循现有文件的空格风格（`function name (`）。

## Review Focus

- **写入中的半行 JSON**：watcher 可能正好读到 `{"type":"assis`。期望跳过该行、保留到下次，不抛异常、不丢已有状态。（Task 3 集成测试）
- **文件以元数据结尾**：`cost-state` / `last-prompt` / `<command-name>` 之类的尾巴不能被当成「正在运行」。（Task 1 单测）
- **`continued-in` 继任文件**：`/clear` 或压缩后旧文件必须消失，不能和继任文件同时出现、token 翻倍。（Task 1 单测 + Task 3 集成测试）
- **会话目录不存在或不可读**：`CLAUDE_CONFIG_DIR` 缺失、项目目录被删，都不影响其他 adapter，也不抛错。（Task 3 集成测试）
- **跨过本地零点**：watcher 持续运行跨天时，今日 token 必须清零重算，不能把昨天的累积带进来。（Task 1 单测）

---

### Task 1: 纯函数：记录归约与会话报告

**Files:**
- Modify: `tools/lib/adapter-logic.mjs`（文件末尾追加 Claude 段）
- Test: `tests/adapter-logic.test.mjs`（追加 import 与用例）

**Interfaces:**
- Consumes: 无。
- Produces:
  - `CLAUDE_ACTIVE_MS = 15 * 60 * 1000`
  - `CLAUDE_BACKFILL_BYTES = 16 * 1024 * 1024`
  - `CLAUDE_READ_BYTES = 256 * 1024`
  - `claudeTodayKey(now: number): string` — 本地时区 `YYYY-MM-DD`
  - `claudeRecordUpdate(record: object): ClaudeUpdate | null`
    - assistant → `{ kind:'assistant', ts:number, messageId:string|null, model, cwd, branch, stopReason, thinking, text, toolUse:{name,input}|null, tokens:number }`
    - user → `{ kind:'user', ts, toolResult:boolean, prompt:boolean }`
    - continued-in → `{ kind:'continued', ts, successorId }`
    - 元数据 / 无法解析 → `null`
  - `claudeToolSummary(toolUse: {name?:string, input?:object}): string | null` — `Bash: <首行>`、`Edit: <文件名>`、`Grep: <pattern>` 等
  - `createClaudeState(): ClaudeState`
  - `mergeClaudeState(state: ClaudeState, update: ClaudeUpdate, now: number): ClaudeState` — 返回新对象；`messages` 只在变化时复制
  - `claudeReport(state: ClaudeState, now: number, startedAt: number): Report | null`

  `ClaudeState` 字段：`{ sessionId, cwd, branch, model, lastActivity, thinking, text, tool, pendingTool, status, dayKey, messages, continued }`。`messages` 是 `{ [messageId]: tokens }`。

  `Report` 字段：`{ id, name:'Claude Code', status:'running'|'done', project, tool, detail, thought, tokens, startedAt, lastActivity }`。

- [ ] **Step 1: 写失败测试**

在 `tests/adapter-logic.test.mjs` 的 import 中加入：

```js
claudeRecordUpdate, claudeReport, claudeTodayKey, claudeToolSummary,
createClaudeState, mergeClaudeState,
```

追加用例（`localTime` 已存在；用本地时间构造 ISO 字符串，避免时区漂移）：

```js
const CLAUDE_DAY = localTime(2026, 11, 19, 9);
const claudeTs = (offsetMs = 0) => new Date(CLAUDE_DAY + offsetMs).toISOString();

function assistantRecord(message, extra = {}) {
  return {
    type: 'assistant',
    sessionId: 'sess-1234',
    cwd: '/Volumes/XC1_DATA/Claude/agent-bar',
    gitBranch: 'feat/claude',
    timestamp: claudeTs(),
    message: { id: 'msg-1', model: 'claude-x', stop_reason: 'tool_use', usage: {
      input_tokens: 10, output_tokens: 5, cache_creation_input_tokens: 2, cache_read_input_tokens: 999
    }, content: message },
    ...extra
  };
}

test('claude metadata records are ignored', () => {
  for (const type of ['cost-state', 'last-prompt', 'system', 'api-request', 'file-history-snapshot']) {
    assert.equal(claudeRecordUpdate({ type, timestamp: claudeTs() }), null);
  }
});

test('assistant tool_use is running, deduped by message id, and excludes cache reads', () => {
  let state = createClaudeState();
  const tool = assistantRecord([{ type: 'tool_use', name: 'Edit', input: { file_path: '/x/agent-bar/Views.swift' } }]);
  state = mergeClaudeState(state, claudeRecordUpdate(tool), CLAUDE_DAY);
  const text = assistantRecord([{ type: 'text', text: '正在改界面' }]);
  state = mergeClaudeState(state, claudeRecordUpdate(text), CLAUDE_DAY);
  const report = claudeReport(state, CLAUDE_DAY, CLAUDE_DAY);
  assert.equal(report.status, 'running');
  assert.equal(report.tokens, 17);
  assert.equal(report.tool, 'Edit: Views.swift');
  assert.equal(report.project, 'agent-bar');
});

test('assistant end_turn without tool_use reports done', () => {
  let state = createClaudeState();
  const record = assistantRecord([{ type: 'text', text: '完成' }], {
    message: { id: 'msg-2', model: 'claude-x', stop_reason: 'end_turn', usage: { output_tokens: 3 }, content: [{ type: 'text', text: '完成' }] }
  });
  state = mergeClaudeState(state, claudeRecordUpdate(record), CLAUDE_DAY);
  assert.equal(claudeReport(state, CLAUDE_DAY, CLAUDE_DAY).status, 'done');
});

test('user tool_result keeps running; command wrappers are not prompts', () => {
  let state = createClaudeState();
  state = mergeClaudeState(state, claudeRecordUpdate(assistantRecord([{ type: 'tool_use', name: 'Bash', input: { command: 'npm test\nrm -rf /' } }])), CLAUDE_DAY);
  state = mergeClaudeState(state, claudeRecordUpdate({
    type: 'user', timestamp: claudeTs(1000), message: { content: [{ type: 'tool_result', tool_use_id: 't1' }] }
  }), CLAUDE_DAY);
  assert.equal(claudeReport(state, CLAUDE_DAY, CLAUDE_DAY).status, 'running');
  assert.equal(claudeToolSummary({ name: 'Bash', input: { command: 'npm test\nrm -rf /' } }), 'Bash: npm test');

  for (const text of ['<command-name>/plugin</command-name>', '<local-command-stdout>ok</local-command-stdout>']) {
    assert.equal(claudeRecordUpdate({ type: 'user', timestamp: claudeTs(), message: { content: text } }), null);
  }
  assert.equal(claudeRecordUpdate({ type: 'user', isMeta: true, timestamp: claudeTs(), message: { content: 'meta' } }), null);
  assert.equal(claudeRecordUpdate({ type: 'user', timestamp: claudeTs(), message: { content: '真的新指令' } }).prompt, true);
});

test('continued-in sessions are suppressed', () => {
  let state = createClaudeState();
  state = mergeClaudeState(state, claudeRecordUpdate({
    type: 'continued-in', timestamp: claudeTs(), sessionId: 'sess-old', continuedInSessionId: 'sess-new'
  }), CLAUDE_DAY);
  assert.equal(claudeReport(state, CLAUDE_DAY, CLAUDE_DAY), null);
});

test('today tokens reset after local midnight', () => {
  let state = createClaudeState();
  const late = localTime(2026, 11, 19, 23, 58);
  const afterMidnight = localTime(2026, 11, 20, 0, 2);
  const record = assistantRecord([{ type: 'text', text: 'x' }], { timestamp: new Date(late).toISOString() });
  state = mergeClaudeState(state, claudeRecordUpdate(record), late);
  assert.equal(claudeReport(state, late, late).tokens, 17);
  assert.equal(claudeReport(state, afterMidnight, late).tokens, 0);
  assert.equal(claudeTodayKey(afterMidnight), '2026-11-20');
});

test('a session older than the active window is dropped', () => {
  let state = createClaudeState();
  state = mergeClaudeState(state, claudeRecordUpdate(assistantRecord([{ type: 'text', text: 'x' }])), CLAUDE_DAY);
  assert.equal(claudeReport(state, CLAUDE_DAY + 16 * 60 * 1000, CLAUDE_DAY), null);
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `node --test tests/adapter-logic.test.mjs`
Expected: FAIL — `claudeRecordUpdate is not a function`。

- [ ] **Step 3: 在 `tools/lib/adapter-logic.mjs` 末尾实现**

按上面的接口实现。规则：

- 元数据类型名单同时覆盖 spec §5.3；未知类型返回 `null`，不要抛错。
- assistant 记录：`ts` 用记录级 `timestamp`（`Date.parse`，无效则 `null`）；tokens 用 `message.usage` 的 `input_tokens + output_tokens + cache_creation_input_tokens`，非数字按 0；`thinking` / `text` 取 content 中对应块的文本；`toolUse` 取最后一个 `tool_use` 块；`stopReason` 取 `message.stop_reason`。
- `mergeClaudeState`：日期从 `claudeTodayKey(now)` 取；`dayKey` 变化时清空 `messages`。assistant 的 token 只有 `claudeTodayKey(update.ts)` 等于当前 dayKey 时才记入 `messages[messageId]`（同一 id 覆盖而不是相加）。assistant 带 toolUse → `status='running'`、`pendingTool=toolUse`；不带 toolUse 且 `stopReason==='end_turn'` → `status='done'`、`pendingTool=null`；其余 assistant 保持 `running` 且不清 pending。`kind:'user'` 且 `toolResult` → `status='running'`、`pendingTool=null`；`prompt` → `status='running'`。`kind:'continued'` → `continued=true`。
- `claudeReport`：`continued`、无 `sessionId`、无 `lastActivity`、或 `now - lastActivity > CLAUDE_ACTIVE_MS` 时返回 `null`。`tokens` 为 `messages` 求和，但 `state.dayKey !== claudeTodayKey(now)` 时返回 0（跨零点没有新记录也不带出昨天的量）；`project = path.basename(cwd) || sessionId.slice(0,8)`；`detail = branch ? 'branch: ' + branch : null`；`thought` 取 `thinking || text`，压成单行并截断 600；`tool` 在无工具时用 `status === 'running' ? '运行中' : '空闲'`；`id = 'claude-' + sessionId.slice(0,8)`。
- `claudeToolSummary`：`Bash` 取 `input.command` 第一行；`Edit`/`Write`/`Read`/`NotebookEdit` 取 `input.file_path` 的 basename；`Grep`/`Glob` 取 `input.pattern`；`Task` 取 `input.description`；其他取工具名。统一压成单行并截断 160，空值返回 `null`。

- [ ] **Step 4: 运行测试确认通过**

Run: `node --test tests/adapter-logic.test.mjs`
Expected: 全部 PASS（含原有用例）。

- [ ] **Step 5: 提交**

```bash
git add tools/lib/adapter-logic.mjs tests/adapter-logic.test.mjs
git commit -m "Add pure Claude transcript reducers and report mapping"
```

---

### Task 2: 父行按最后活动排序

**Files:**
- Modify: `tools/lib/adapter-logic.mjs`（`aggregateApp` 的排序）
- Test: `tests/adapter-logic.test.mjs`

**Interfaces:**
- Consumes: Task 1 的 `lastActivity` 字段。
- Produces: `aggregateApp` 在排序和父行摘要时优先使用 `report.lastActivity`，缺失时退回 `report.startedAt`；其他 adapter 不传该字段，行为不变。

- [ ] **Step 1: 写失败测试**

```js
test('aggregateApp prefers lastActivity for the parent summary', () => {
  const parent = aggregateApp({ group: 'claude', name: 'Claude Code', bundleID: null }, [
    { id: 'claude-old', status: 'running', project: 'old', tool: 'old', startedAt: 200, lastActivity: 300 },
    { id: 'claude-new', status: 'running', project: 'new', tool: 'new', startedAt: 100, lastActivity: 400 }
  ]);
  assert.equal(parent.project, 'new');
  assert.equal(parent.tool, 'new');
  assert.equal(parent.sessions[0].id, 'claude-new');
});
```

- [ ] **Step 2: 运行确认失败**

Run: `node --test tests/adapter-logic.test.mjs`
Expected: FAIL — `parent.project` 是 `old`。

- [ ] **Step 3: 修改 `aggregateApp` 排序**

把 active 的排序比较键改为 `(b.lastActivity || b.startedAt || 0) - (a.lastActivity || a.startedAt || 0)`；`aggregateApp` 其余逻辑与子会话字段不动。

- [ ] **Step 4: 运行确认通过**

Run: `node --test tests/adapter-logic.test.mjs`
Expected: 全部 PASS，原有 `aggregateApp keeps one parent…` 仍然通过。

- [ ] **Step 5: 提交**

```bash
git add tools/lib/adapter-logic.mjs tests/adapter-logic.test.mjs
git commit -m "Order aggregated sessions by last activity"
```

---

### Task 3: 接入 watcher 与集成测试

**Files:**
- Modify: `tools/agentbar-app-adapters.mjs`
- Create: `tests/claude-adapter.test.mjs`
- Modify: `tests/run.sh`（追加测试文件）

**Interfaces:**
- Consumes: Task 1 的全部导出；Task 2 的排序。
- Produces: `claudeReports(): Report[]`（内部函数），`tick()` 的 adapters 列表新增 `{ group: 'claude', name: 'Claude Code', bundleID: null, reports: claudeReports }`。

- [ ] **Step 1: 写失败的集成测试**

`tests/claude-adapter.test.mjs` 结构：

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const ADAPTER = path.join(ROOT, 'tools', 'agentbar-app-adapters.mjs');

function fixtureHome() {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'ab-claude-'));
  fs.mkdirSync(path.join(home, '.claude', 'projects'), { recursive: true });
  return home;
}

function writeSession(home, project, id, lines) {
  const dir = path.join(home, '.claude', 'projects', project);
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, id + '.jsonl');
  fs.writeFileSync(file, lines.map((line) => JSON.stringify(line)).join('\n') + '\n');
  return file;
}

function runOnce(home) {
  const result = spawnSync(process.execPath, [ADAPTER, '--once'], {
    encoding: 'utf8',
    env: { ...process.env, HOME: home, CLAUDE_CONFIG_DIR: path.join(home, '.claude') }
  });
  assert.equal(result.status, 0, result.stderr);
  return JSON.parse(result.stdout);
}
```

用例：

```js
test('three newest Claude sessions are reported, continued-in is skipped', () => {
  const home = fixtureHome();
  const now = Date.now();
  const assistant = (id, text, offset = 0) => ({
    type: 'assistant', sessionId: id, cwd: '/work/' + id, gitBranch: 'main',
    timestamp: new Date(now - offset).toISOString(),
    message: { id: 'msg-' + id, model: 'claude-x', stop_reason: 'tool_use', usage: { input_tokens: 1, output_tokens: 2 },
      content: [{ type: 'tool_use', name: 'Bash', input: { command: 'npm test' } }] }
  });
  writeSession(home, '-work-one', 'one', [assistant('one', 'a', 3000), { type: 'cost-state', sessionId: 'one' }]);
  writeSession(home, '-work-two', 'two', [assistant('two', 'b', 2000)]);
  writeSession(home, '-work-three', 'three', [assistant('three', 'c', 1000)]);
  writeSession(home, '-work-ghost', 'ghost', [
    { type: 'user', sessionId: 'ghost', timestamp: new Date(now - 500).toISOString(), message: { content: [{ type: 'tool_result' }] } },
    { type: 'continued-in', sessionId: 'ghost', timestamp: new Date(now).toISOString(), continuedInSessionId: 'three' }
  ]);
  fs.mkdirSync(path.join(home, '.claude', 'projects', '-work-one', 'tool-results'), { recursive: true });
  fs.writeFileSync(path.join(home, '.claude', 'projects', '-work-one', 'tool-results', 'ignored.jsonl'), '{}\n');

  const claude = runOnce(home).find((report) => report.id === 'claude');
  assert.ok(claude, 'claude parent report missing');
  assert.equal(claude.sessions.length, 3);
  assert.deepEqual(claude.sessions.map((s) => s.project).sort(), ['one', 'three', 'two']);
  assert.equal(claude.sessions[0].tool, 'Bash: npm test');
});

test('partial trailing line and missing directory do not break the watcher', () => {
  const home = fixtureHome();
  const file = writeSession(home, '-work-partial', 'partial', [{
    type: 'assistant', sessionId: 'partial', cwd: '/work/partial', timestamp: new Date().toISOString(),
    message: { id: 'm', model: 'claude-x', stop_reason: 'end_turn', usage: { output_tokens: 1 }, content: [{ type: 'text', text: 'done' }] }
  }]);
  fs.appendFileSync(file, '{"type":"assis');
  const claude = runOnce(home).find((report) => report.id === 'claude');
  assert.ok(claude);
  assert.equal(claude.status, 'done');

  const empty = fs.mkdtempSync(path.join(os.tmpdir(), 'ab-claude-empty-'));
  const output = runOnce(empty);
  assert.equal(output.some((report) => report.id === 'claude'), false);
});
```

注意：`--once` 模式下 tick 不会写 agents 目录，也不需要 Agent Bar 在跑。

- [ ] **Step 2: 运行确认失败**

先把新文件加进 `tests/run.sh` 的 `node --test` 列表，然后：

Run: `node --test tests/claude-adapter.test.mjs`
Expected: FAIL — 找不到 `id === 'claude'` 的报告。

- [ ] **Step 3: 在 `tools/agentbar-app-adapters.mjs` 实现**

1. import Task 1 的导出。
2. 顶部加：
   - `const CLAUDE_PROJECTS = path.join(process.env.CLAUDE_CONFIG_DIR || path.join(HOME, '.claude'), 'projects');`
   - `const claudeFiles = new Map();`（`filePath -> { state, startedAt, offset, partial, warned }`）
3. `function claudeReports()`：
   - `readdirSync(CLAUDE_PROJECTS, { withFileTypes: true })`，失败返回 `[]`。
   - 只进入目录；每个目录只取第一层 `*.jsonl` 文件。
   - 对每个文件 `statSync`；跳过 0 字节。
   - 首次：`start = Math.max(0, size - CLAUDE_BACKFILL_BYTES)`，读 `[start, size)`；`start > 0` 时丢掉第一行（可能是半行）；`offset = size`。
   - 已见：`size < offset` → 重置 state 和 offset，按首次处理；否则读 `[offset, size)`，若待读超过 `CLAUDE_READ_BYTES`，只读最后 `CLAUDE_READ_BYTES` 并丢掉第一行，log 一次（`console.error`，只带文件名）。
   - 把新内容拼到 `partial`，按 `\n` 切；最后一段留作 `partial`；其余逐行 `JSON.parse`，解析失败就跳过该行。
   - 每行 `claudeRecordUpdate` → `mergeClaudeState(state, update, Date.now())`；`startedAt` 首次记录为 `Date.now()`。
   - `claudeReport(state, now, entry.startedAt)` 为 `null` 的跳过。
   - 清理 `claudeFiles` 中本次未出现的文件。
   - 按 `lastActivity` 降序，取前 3。
   - 整个函数用 try/catch 包住：任何异常 `console.error('<file-tail> claude error:', error.message)` 后返回已收集的报告，绝不让其他 adapter 挂掉。
4. 在 `tick()` 的 adapters 列表中加 Claude 项（放在 Hermes 之后）。

- [ ] **Step 4: 运行确认通过**

Run: `node --test tests/claude-adapter.test.mjs && node --test tests/adapter-logic.test.mjs`
Expected: 全部 PASS。

- [ ] **Step 5: 用真实数据手动验证**

Run: `node tools/agentbar-app-adapters.mjs --once | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{const r=JSON.parse(d).find(x=>x.id==="claude");console.log(JSON.stringify(r,null,2))})'`
Expected: 输出一个 `id: "claude"` 的报告；`sessions` 里每个会话的 `project` 是真实项目目录名，`tool` 是当前工具，`tokens` 为当天数字；没有 `continued-in` 的重复会话。

- [ ] **Step 6: 提交**

```bash
git add tools/agentbar-app-adapters.mjs tests/claude-adapter.test.mjs tests/run.sh
git commit -m "Read Claude Code sessions from local transcripts"
```

---

### Task 4: 停用 Claude hooks、更新文档

**Files:**
- Modify: `tools/agentbar-install-adapter.mjs`
- Modify: `tests/adapter-install.test.mjs`
- Modify: `README.md`（一键接入段、支持矩阵）
- Modify: `bridge/README.md`（§11.4 / 新增 Claude 小节）
- Modify: `docs/ROADMAP.md`（外部 agent 接入一行）
- Test: `tests/adapter-install.test.mjs`

**Interfaces:**
- Consumes: 无。
- Produces: `node tools/agentbar-install-adapter.mjs claude` 只打印迁移提示，不创建/修改 `~/.claude/settings.json`；`uninstall-claude` 仍然清理旧 hook。

- [ ] **Step 1: 改写失败测试**

把 `tests/adapter-install.test.mjs` 的用例替换为：

```js
test('claude install only prints guidance and leaves settings untouched', () => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'ab-install-'));
  const settings = path.join(home, '.claude', 'settings.json');
  fs.mkdirSync(path.dirname(settings), { recursive: true });
  fs.writeFileSync(settings, JSON.stringify({ permissions: { allow: [] } }, null, 2) + '\n');
  const before = fs.readFileSync(settings, 'utf8');

  const installed = run(home, 'claude');
  assert.equal(installed.status, 0, installed.stderr);
  assert.match(installed.stdout, /transcript/i);
  assert.equal(fs.readFileSync(settings, 'utf8'), before);
});

test('uninstall-claude still removes hooks installed by older versions', () => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'ab-install-'));
  const settings = path.join(home, '.claude', 'settings.json');
  fs.mkdirSync(path.dirname(settings), { recursive: true });
  fs.writeFileSync(settings, JSON.stringify({
    hooks: {
      PreToolUse: [{ matcher: '*', hooks: [{ type: 'command', timeout: 5, command: 'node /x/tools/agentbar-report.mjs --id claude-code' }] }],
      Stop: [{ hooks: [{ type: 'command', timeout: 5, command: 'node /x/tools/agentbar-report.mjs --id claude-code --status done' }] }]
    }
  }, null, 2) + '\n');

  const removed = run(home, 'uninstall-claude');
  assert.equal(removed.status, 0, removed.stderr);
  assert.equal(JSON.parse(fs.readFileSync(settings, 'utf8')).hooks, undefined);
});
```

- [ ] **Step 2: 运行确认失败**

Run: `node --test tests/adapter-install.test.mjs`
Expected: 第一个用例 FAIL（当前会写入 hooks）。

- [ ] **Step 3: 修改安装器**

`installClaude()` 改为只打印：

```
Claude Code sessions are read directly from <CLAUDE_PROJECTS>; no hooks are needed.
If an older version installed hooks, run: node tools/agentbar-install-adapter.mjs uninstall-claude
```

不再 `mkdir`/`writeFileSync`，不再调用 `backupFile`、`hookCommand`、`removeOurHooks`；`hookCommand` 与 `MARKER` 只保留 `uninstall` 需要的部分（`MARKER` 仍用于匹配）。`uninstallClaude()` 不动。

- [ ] **Step 4: 更新文档**

- `README.md` 支持矩阵 Claude Code 行改为：实时状态「✅ 自动读取本地会话（无需安装）」、思考「✅ 工具 / 思考」、审批不变（只读，并写明原因）；「一键接入」段落把 Claude 的可选安装说明换成「无需安装；旧版 hook 用 `uninstall-claude` 清理」，并写明 token 口径（今日、不含缓存读取）。
- `bridge/README.md`：在 §11.4 之后新增「Claude Code transcripts」小节，说明目录、活跃窗口、token 口径、只读与非目标；把「Claude Code (hooks)」示例标注为旧版并指向迁移命令。
- `docs/ROADMAP.md`：在「外部 agent 一键接入」一行补「Claude Code 改为直接读 transcript」。

- [ ] **Step 5: 运行全部检查**

Run: `./tests/run.sh && ./build.sh`
Expected: Swift 259/259、Node 全部 PASS、构建成功。

- [ ] **Step 6: 提交**

```bash
git add tools/agentbar-install-adapter.mjs tests/adapter-install.test.mjs README.md bridge/README.md docs/ROADMAP.md
git commit -m "Retire Claude hooks in favor of transcript reading"
```

---

## 收尾验证

- `./tests/run.sh` 全绿。
- `./build.sh` 成功。
- `./start.sh` 后栏上出现 Claude Code 行；起一个新 Claude 会话，工具/思考/项目随之更新；结束后 15 分钟内变 done 后消失。
- `git status` 干净；分支 `feat/claude-transcript-support`。
