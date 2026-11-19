# Claude Code 面板审批 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Claude Code 弹出 Bash 确认框时，Agent Bar 面板出现同一条命令的审批卡片，允许/拒绝都能在栏上完成。

**Architecture:** 在 `~/.claude/settings.json` 安装 `PermissionRequest` hook。hook 把请求写成 `Application Support/AgentBar/claude-approvals/pending/<id>.json`，App 每秒扫描目录并把审批挂到 `claude` 行（不存在时合成一行），用户决定写 `decisions/<id>.json`，hook 轮询到决定后输出 `decision.behavior`。hook 与 App 之间只通过本地文件通信，不经过 bridge/DSH；任何异常都静默退出，原生确认框照常工作。

**Tech Stack:** Node ≥ 20（ESM，零依赖）、Swift 5 / SwiftUI / AppKit、`node --test`、`xcrun swiftc`。

**Spec:** `docs/superpowers/specs/2026-11-19-claude-approval-design.md`

## Global Constraints

- Claude Code ≥ v2.0.45（本机 2.1.328 已核对 `PermissionRequest` 存在）；hook 输出必须是 `hookSpecificOutput.decision.behavior = allow | deny`。
- 默认 matcher 精确为 `^Bash$`（matcher 是未锚定正则，必须自己锚定）。
- hook 配置 `timeout: 45`；脚本内部等待上限 40 秒；轮询 150 ms。
- heartbeat 超过 10 秒未更新 → hook 立即退出；pending 超过 2 分钟、decision 超过 10 分钟由 App 清理。
- `command` 保留完整命令，上限 4000 字符；只存工具参数，不存对话/思考/transcript。
- 运行时目录 0700、文件 0600；所有写入用临时文件 + rename。
- 任何失败路径都**不得**阻断工具调用、也**不得**自动允许；只能静默退出让原生权限流程接手。
- 不读取/修改 `permissions`、不写 `defaultMode`、不发网络请求。
- Node 侧零依赖；Swift 侧不改现有 `barFeedMode` 行为。

## Review Focus

1. 用户在终端原生确认框先作答：hook 必须等到超时后自行退出并删除 pending，面板卡片随后消失（Task 2 超时测试、Task 5 清理）。
2. App 未运行/刚退出：hook 在 100 ms 内退出，不产生审批文件（Task 2 heartbeat 测试）。
3. 非 `PermissionRequest` 事件或非 Bash 工具：不写 pending（Task 1 事件/正则测试、Task 2 事件测试）。
4. 伪造或过期决定（错 nonce、错 id、未知 behavior）：hook 不接受，继续等待到超时（Task 1 决定校验、Task 2 wrong-nonce 测试）。
5. 非 `claude:` 的审批 id：Swift 必须继续走 DSH/bridge 路径，不能被写进 Claude 目录（Task 4 `claudeApprovalRequestId` 返回 nil 的测试）。

---

### Task 1: Node 审批纯函数

**Files:**
- Create: `tools/lib/claude-approval-logic.mjs`
- Test: `tests/claude-approval.test.mjs`
- Modify: `tests/run.sh:12`

**Interfaces:**
- Produces:
  - `CLAUDE_APPROVAL_HEARTBEAT_MS = 10_000`
  - `CLAUDE_APPROVAL_PENDING_MS = 120_000`
  - `CLAUDE_APPROVAL_DECISION_MS = 600_000`
  - `CLAUDE_APPROVAL_WAIT_MS = 40_000`
  - `CLAUDE_APPROVAL_POLL_MS = 150`
  - `claudeApprovalCommand(toolName: string, toolInput: object): string`
  - `claudeApprovalToolAllowed(toolName: string, pattern?: string): boolean`（默认 `'^Bash$'`；pattern 非法返回 false）
  - `claudeApprovalOutput(behavior: 'allow'|'deny', message?: string): object`
  - `claudeApprovalDecision(payload: any, expected: {id: string, nonce: string}): 'allow'|'deny'|null`
  - `claudeHeartbeatFresh(mtimeMs: number, now: number): boolean`
  - `claudePendingExpired(createdAt: number, now: number): boolean`
  - `claudeDecisionExpired(decidedAt: number, now: number): boolean`
  - `claudeApprovalRequest(input: any, options: {now: number, id: string, nonce: string}): object | null`

- [ ] **Step 1: Write the failing tests**

`tests/claude-approval.test.mjs`：

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  claudeApprovalCommand, claudeApprovalToolAllowed, claudeApprovalOutput,
  claudeApprovalDecision, claudeHeartbeatFresh, claudePendingExpired,
  claudeDecisionExpired, claudeApprovalRequest
} from '../tools/lib/claude-approval-logic.mjs';

test('Bash keeps the command and caps it at 4000 characters', () => {
  assert.equal(claudeApprovalCommand('Bash', { command: 'rm -rf build' }), 'rm -rf build');
  const long = 'x'.repeat(5000);
  assert.equal(claudeApprovalCommand('Bash', { command: long }).length, 4001); // 4000 + '…'
});

test('Edit falls back to file_path, unknown tools serialize the input', () => {
  assert.equal(claudeApprovalCommand('Edit', { file_path: '/tmp/a.txt', old_string: 'a' }), '/tmp/a.txt');
  assert.match(claudeApprovalCommand('WebFetch', { url: 'https://example.com' }), /example\.com/);
});

test('tool regex is anchored by the caller', () => {
  assert.equal(claudeApprovalToolAllowed('Bash'), true);
  assert.equal(claudeApprovalToolAllowed('BashFoo'), false);
  assert.equal(claudeApprovalToolAllowed('Edit'), false);
  assert.equal(claudeApprovalToolAllowed('Edit', '^Bash$|^Edit$'), true);
  assert.equal(claudeApprovalToolAllowed('Edit', '('), false);
});

test('allow output uses the PermissionRequest shape', () => {
  assert.deepEqual(claudeApprovalOutput('allow'), {
    hookSpecificOutput: { hookEventName: 'PermissionRequest', decision: { behavior: 'allow' } }
  });
});

test('deny output carries the message', () => {
  assert.deepEqual(claudeApprovalOutput('deny', 'no'), {
    hookSpecificOutput: { hookEventName: 'PermissionRequest', decision: { behavior: 'deny', message: 'no' } }
  });
});

test('decision requires matching id and nonce', () => {
  const expected = { id: 'a', nonce: 'n' };
  assert.equal(claudeApprovalDecision({ schema: 1, id: 'a', nonce: 'n', decision: 'allow' }, expected), 'allow');
  assert.equal(claudeApprovalDecision({ schema: 1, id: 'a', nonce: 'n', decision: 'deny' }, expected), 'deny');
  assert.equal(claudeApprovalDecision({ schema: 1, id: 'b', nonce: 'n', decision: 'allow' }, expected), null);
  assert.equal(claudeApprovalDecision({ schema: 1, id: 'a', nonce: 'x', decision: 'allow' }, expected), null);
  assert.equal(claudeApprovalDecision({ schema: 1, id: 'a', nonce: 'n', decision: 'maybe' }, expected), null);
  assert.equal(claudeApprovalDecision(null, expected), null);
});

test('heartbeat and expiry bounds', () => {
  assert.equal(claudeHeartbeatFresh(1000, 10_000), true);
  assert.equal(claudeHeartbeatFresh(1000, 11_001), false);
  assert.equal(claudePendingExpired(0, 119_999), false);
  assert.equal(claudePendingExpired(0, 120_001), true);
  assert.equal(claudeDecisionExpired(0, 599_999), false);
  assert.equal(claudeDecisionExpired(0, 600_001), true);
});

test('request is built only for PermissionRequest events', () => {
  const base = {
    hook_event_name: 'PermissionRequest', session_id: 's1', cwd: '/Users/x/proj',
    tool_name: 'Bash', tool_input: { command: 'ls' }
  };
  const request = claudeApprovalRequest(base, { now: 123, id: 'id1', nonce: 'n1' });
  assert.deepEqual(request, {
    schema: 1, id: 'id1', nonce: 'n1', sessionId: 's1', cwd: '/Users/x/proj',
    tool: 'Bash', command: 'ls', createdAt: 123
  });
  assert.equal(claudeApprovalRequest({ ...base, hook_event_name: 'PreToolUse' }, { now: 1, id: 'i', nonce: 'n' }), null);
  assert.equal(claudeApprovalRequest({ ...base, session_id: '' }, { now: 1, id: 'i', nonce: 'n' }), null);
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `node --test tests/claude-approval.test.mjs`
Expected: FAIL `Cannot find module .../tools/lib/claude-approval-logic.mjs`.

- [ ] **Step 3: Implement `tools/lib/claude-approval-logic.mjs`**

Pure functions only, no file I/O. `claudeApprovalCommand` 规则：Bash 取 `tool_input.command`；其它工具取 `tool_input.file_path`；都没有时 `JSON.stringify(toolInput)`；`String` 后压成保留换行的文本，截到 4000 字符再加 `'…'`。`claudeApprovalToolAllowed` 用 `new RegExp(pattern)` 兜 `try/catch`。`claudeApprovalOutput` 与 `claudeApprovalDecision` 按上面测试的字段返回。

- [ ] **Step 4: Run tests to verify they pass**

Run: `node --test tests/claude-approval.test.mjs`
Expected: PASS，全部 8 个测试。

- [ ] **Step 5: Add the file to the suite and commit**

在 `tests/run.sh` 的 `node --test` 参数末尾追加 `tests/claude-approval.test.mjs`。

```bash
./tests/run.sh
git add tools/lib/claude-approval-logic.mjs tests/claude-approval.test.mjs tests/run.sh
git commit -m "feat(claude): add approval decision helpers"
```

---

### Task 2: 审批 hook 脚本

**Files:**
- Create: `tools/agentbar-claude-approve.mjs`
- Test: `tests/claude-approval-hook.test.mjs`
- Modify: `tests/run.sh:12`

**Interfaces:**
- Consumes: Task 1 的全部导出。
- Produces: 可执行脚本 `node tools/agentbar-claude-approve.mjs`。环境变量：
  - `AGENTBAR_CLAUDE_APPROVAL_DIR`（默认 `~/Library/Application Support/AgentBar/claude-approvals`）
  - `AGENTBAR_CLAUDE_APPROVAL_TOOLS`（默认 `^Bash$`）
  - `AGENTBAR_CLAUDE_APPROVAL_WAIT_MS`（默认 40000）
  - `AGENTBAR_CLAUDE_APPROVAL_POLL_MS`（默认 150）

- [ ] **Step 1: Write the failing integration tests**

`tests/claude-approval-hook.test.mjs`：

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const HOOK = path.join(ROOT, 'tools', 'agentbar-claude-approve.mjs');

function tempDir() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ab-approve-'));
  fs.mkdirSync(path.join(dir, 'pending'), { recursive: true });
  fs.mkdirSync(path.join(dir, 'decisions'), { recursive: true });
  fs.writeFileSync(path.join(dir, 'heartbeat'), '');
  return dir;
}

function startHook(dir, input, env = {}) {
  const child = spawn(process.execPath, [HOOK], {
    env: { ...process.env, AGENTBAR_CLAUDE_APPROVAL_DIR: dir, ...env }
  });
  child.stdin.end(JSON.stringify(input));
  let stdout = '';
  child.stdout.on('data', (chunk) => { stdout += chunk; });
  const done = new Promise((resolve) => child.on('close', (code) => resolve({ code, stdout })));
  return { child, done };
}

async function waitFor(fn, timeout = 5000) {
  const started = Date.now();
  for (;;) {
    const value = fn();
    if (value) return value;
    if (Date.now() - started > timeout) throw new Error('waitFor timed out');
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
}

async function respond(dir, decision, mutate = (payload) => payload) {
  const name = await waitFor(() => fs.readdirSync(path.join(dir, 'pending')).find((n) => n.endsWith('.json')));
  const request = JSON.parse(fs.readFileSync(path.join(dir, 'pending', name), 'utf8'));
  const payload = mutate({ schema: 1, id: request.id, nonce: request.nonce, decision, decidedAt: Date.now() });
  fs.writeFileSync(path.join(dir, 'decisions', request.id + '.json'), JSON.stringify(payload));
  return request;
}

const INPUT = {
  hook_event_name: 'PermissionRequest', session_id: 's1', cwd: '/tmp/p',
  tool_name: 'Bash', tool_input: { command: 'rm -rf build' }
};

test('allow is returned in the PermissionRequest shape and files are cleaned', async () => {
  const dir = tempDir();
  const { done } = startHook(dir, INPUT);
  const request = await respond(dir, 'allow');
  const result = await done;
  assert.equal(result.code, 0);
  assert.deepEqual(JSON.parse(result.stdout).hookSpecificOutput.decision, { behavior: 'allow' });
  assert.equal(request.command, 'rm -rf build');
  assert.equal(fs.readdirSync(path.join(dir, 'pending')).length, 0);
  assert.equal(fs.readdirSync(path.join(dir, 'decisions')).length, 0);
});

test('deny carries the rejection message', async () => {
  const dir = tempDir();
  const { done } = startHook(dir, INPUT);
  await respond(dir, 'deny');
  const result = await done;
  const decision = JSON.parse(result.stdout).hookSpecificOutput.decision;
  assert.equal(decision.behavior, 'deny');
  assert.match(decision.message, /拒绝/);
});

test('a wrong nonce is ignored and the hook times out silently', async () => {
  const dir = tempDir();
  const { done } = startHook(dir, INPUT, { AGENTBAR_CLAUDE_APPROVAL_WAIT_MS: '600', AGENTBAR_CLAUDE_APPROVAL_POLL_MS: '30' });
  await respond(dir, 'allow', (payload) => ({ ...payload, nonce: 'forged' }));
  const result = await done;
  assert.equal(result.code, 0);
  assert.equal(result.stdout, '');
  assert.equal(fs.readdirSync(path.join(dir, 'pending')).length, 0); // timeout cleans up
});

test('a stale heartbeat exits without asking', async () => {
  const dir = tempDir();
  const old = new Date(Date.now() - 60_000);
  fs.utimesSync(path.join(dir, 'heartbeat'), old, old);
  const started = Date.now();
  const { done } = startHook(dir, INPUT);
  const result = await done;
  assert.equal(result.code, 0);
  assert.equal(result.stdout, '');
  assert.ok(Date.now() - started < 2000);
  assert.equal(fs.readdirSync(path.join(dir, 'pending')).length, 0);
});

test('other hook events and non-matching tools do nothing', async () => {
  const dir = tempDir();
  for (const input of [
    { ...INPUT, hook_event_name: 'PreToolUse' },
    { ...INPUT, tool_name: 'Read', tool_input: { file_path: '/tmp/a' } }
  ]) {
    const { done } = startHook(dir, input);
    const result = await done;
    assert.equal(result.code, 0);
    assert.equal(result.stdout, '');
  }
  assert.equal(fs.readdirSync(path.join(dir, 'pending')).length, 0);
});

test('a missing approval directory exits silently', async () => {
  const dir = path.join(os.tmpdir(), 'ab-approve-missing-' + Date.now());
  const { done } = startHook(dir, INPUT);
  const result = await done;
  assert.equal(result.code, 0);
  assert.equal(result.stdout, '');
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `node --test tests/claude-approval-hook.test.mjs`
Expected: FAIL，spawn 的脚本不存在或相关错误。

- [ ] **Step 3: Implement `tools/agentbar-claude-approve.mjs`**

流程按 spec §5.2：读 stdin（`fs.readFileSync(0, 'utf8')`，>1 MB 直接退出）→ 解析 JSON → `claudeApprovalToolAllowed(tool_name, process.env.AGENTBAR_CLAUDE_APPROVAL_TOOLS)` → heartbeat mtime 检查 → 写 pending → 轮询 decisions → 校验 → `process.stdout.write(JSON.stringify(claudeApprovalOutput(...)))`。`finally` 删除 pending 与 decision。任何异常走 `exit(0)` 且不输出。用 `crypto.randomUUID()` 与 `crypto.randomBytes(16).toString('hex')`。

- [ ] **Step 4: Run tests to verify they pass**

Run: `node --test tests/claude-approval-hook.test.mjs`
Expected: PASS，6 个测试。

- [ ] **Step 5: Add to the suite and commit**

`tests/run.sh` 追加 `tests/claude-approval-hook.test.mjs`。

```bash
./tests/run.sh
git add tools/agentbar-claude-approve.mjs tests/claude-approval-hook.test.mjs tests/run.sh
git commit -m "feat(claude): add the PermissionRequest approval hook"
```

---

### Task 3: 安装器（安装/状态/卸载/旧 hook 清理）

**Files:**
- Modify: `tools/agentbar-install-adapter.mjs`（`CLAUDE_SETTINGS` 改成函数；`installClaude`、`uninstallClaude`、`status`、`main` 的参数解析）
- Modify: `tests/adapter-install.test.mjs`

**Interfaces:**
- Consumes: Task 2 的 `tools/agentbar-claude-approve.mjs` 与 `tools/lib/claude-approval-logic.mjs`。
- Produces: `node tools/agentbar-install-adapter.mjs claude [--tools <regex>] [--no-approvals]`；settings 路径为 `$CLAUDE_CONFIG_DIR/settings.json`（未设置时 `~/.claude/settings.json`）；hook 脚本复制到 `$APP_SUPPORT/hooks/`（`agentbar-claude-approve.mjs` + `lib/claude-approval-logic.mjs`）。

- [ ] **Step 1: Rewrite the installer tests (RED)**

把 `tests/adapter-install.test.mjs` 中第一个 claude 测试改成：

```js
test('claude install writes the approval hook and copies the scripts', () => {
  const home = tempHome();
  const settings = path.join(home, '.claude', 'settings.json');
  fs.writeFileSync(settings, JSON.stringify({ permissions: { allow: [] } }, null, 2) + '\n');

  const installed = run(home, 'claude');
  assert.equal(installed.status, 0, installed.stderr);
  const hooks = JSON.parse(fs.readFileSync(settings, 'utf8')).hooks;
  assert.equal(hooks.PermissionRequest.length, 1);
  assert.equal(hooks.PermissionRequest[0].matcher, '^Bash$');
  const hook = hooks.PermissionRequest[0].hooks[0];
  assert.equal(hook.timeout, 45);
  assert.match(hook.command, /agentbar-claude-approve\.mjs/);
  assert.ok(fs.existsSync(path.join(home, 'Library', 'Application Support', 'AgentBar', 'hooks', 'agentbar-claude-approve.mjs')));
  assert.ok(fs.existsSync(path.join(home, 'Library', 'Application Support', 'AgentBar', 'hooks', 'lib', 'claude-approval-logic.mjs')));
});

test('installing twice does not duplicate the hook and can override the matcher', () => {
  const home = tempHome();
  run(home, 'claude');
  run(home, 'claude', '--tools', '^Bash$|^Edit$');
  const hooks = JSON.parse(fs.readFileSync(path.join(home, '.claude', 'settings.json'), 'utf8')).hooks;
  assert.equal(hooks.PermissionRequest.length, 1);
  assert.match(hooks.PermissionRequest[0].matcher, /Edit/);
});

test('claude install honors CLAUDE_CONFIG_DIR and removes legacy report hooks', () => {
  const home = tempHome();
  const config = path.join(home, 'alt-claude');
  fs.mkdirSync(config, { recursive: true });
  const settings = path.join(config, 'settings.json');
  fs.writeFileSync(settings, JSON.stringify({
    hooks: { PreToolUse: [{ hooks: [{ type: 'command', command: 'node /x/tools/agentbar-report.mjs --id claude-code' }] }] }
  }, null, 2) + '\n');

  const result = spawnSync(process.execPath, [INSTALLER, 'claude'], {
    encoding: 'utf8',
    env: { ...process.env, HOME: home, CLAUDE_CONFIG_DIR: config }
  });
  assert.equal(result.status, 0, result.stderr);
  const node = JSON.parse(fs.readFileSync(settings, 'utf8'));
  assert.equal(node.hooks.PreToolUse, undefined);
  assert.equal(node.hooks.PermissionRequest.length, 1);
});

test('uninstall removes both hook generations and the copied scripts', () => {
  const home = tempHome();
  run(home, 'claude');
  const settings = path.join(home, '.claude', 'settings.json');
  const node = JSON.parse(fs.readFileSync(settings, 'utf8'));
  node.hooks.PreToolUse = [{ hooks: [{ type: 'command', command: 'node /x/tools/agentbar-report.mjs --id claude-code' }] }];
  fs.writeFileSync(settings, JSON.stringify(node, null, 2) + '\n');

  const removed = run(home, 'uninstall-claude');
  assert.equal(removed.status, 0, removed.stderr);
  assert.equal(JSON.parse(fs.readFileSync(settings, 'utf8')).hooks, undefined);
  assert.equal(fs.existsSync(path.join(home, 'Library', 'Application Support', 'AgentBar', 'hooks')), false);
});
```

再把 `status` 测试的期望改为：默认输出匹配 `/approval hook \(\^Bash\$\)/`；存在旧 hook 时仍匹配 `/legacy hook/`。

- [ ] **Step 2: Run tests and watch them fail**

Run: `node --test tests/adapter-install.test.mjs`
Expected: FAIL（`Cannot read properties of undefined (reading 'PermissionRequest')` 等）。

- [ ] **Step 3: Implement the installer changes**

- `claudeConfigDir()`：`process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude')`。
- `removeHooksByMarker(node, markers)`：现有 `removeOurHooks` 泛化为按 marker 列表过滤（保留 `agentbar-report.mjs` 清理能力）。
- `installClaude({tools = '^Bash$', approvals = true})`：复制脚本到 `$APP_SUPPORT/hooks/`（`fs.copyFileSync` + chmod 0700/0600）；用 marker `agentbar-claude-approve.mjs` 去重后 push 到 `hooks.PermissionRequest`；删除旧 marker 条目；`--no-approvals` 只打印指南。
- 安装时若 `agents/claude-code.json` 的 `id === "claude-code"`，删除它并打印迁移提示。
- 命令行形式：`AGENTBAR_CLAUDE_APPROVAL_TOOLS='<regex>' <node> <hooks>/agentbar-claude-approve.mjs`（shellQuote）。
- `status`：报告 `transcript mode + approval hook (<matcher>)`、旧 hook 数量、脚本是否齐全。
- `uninstallClaude()`：删除两种 marker，递归删除 `$APP_SUPPORT/hooks/`。

- [ ] **Step 4: Run tests to verify they pass**

Run: `node --test tests/adapter-install.test.mjs`
Expected: PASS（原有用例 + 新用例）。

- [ ] **Step 5: Commit**

```bash
./tests/run.sh
git add tools/agentbar-install-adapter.mjs tests/adapter-install.test.mjs
git commit -m "feat(claude): install the approval hook"
```

---

### Task 4: Swift 纯函数（解析 / 选择 / 决定 payload）

**Files:**
- Modify: `Support.swift`（追加审批辅助类型与函数）
- Test: `tests/main.swift`（末尾追加 check）

**Interfaces:**
- Produces（均为 internal，供 App 层使用）：
  - `struct ClaudePendingApproval: Equatable { let id, nonce, sessionId, cwd, tool, command: String; let createdAt: Double }`
  - `func parseClaudePendingApproval(_ data: Data) -> ClaudePendingApproval?`
  - `func selectClaudePendingApproval(_ approvals: [ClaudePendingApproval]) -> (approval: ClaudePendingApproval, extra: Int)?`（按 `createdAt` 取最新；`extra = count - 1`）
  - `func claudeApprovalId(_ requestId: String) -> String`（`"claude:" + id`）
  - `func claudeApprovalRequestId(_ approvalId: String?) -> String?`（非 `claude:` 前缀返回 nil）
  - `func claudeApprovalDecision(_ storeDecision: String) -> String?`（`allowed-once`→`allow`，`rejected`→`deny`，其它 nil）
  - `func claudeApprovalDecisionJSON(_ approval: ClaudePendingApproval, decision: String, at: Date) -> Data?`
  - `func claudeApprovalNotice(project: String, extra: Int) -> String`
  - `func claudeApprovalCanAnswer(_ approvalId: String?) -> Bool`

- [ ] **Step 1: Write the failing checks**

`tests/main.swift` 末尾追加：

```swift
// Claude approval helpers.
let pendingJSON = #"{"schema":1,"id":"abc","nonce":"n1","sessionId":"s1","cwd":"/Users/x/proj","tool":"Bash","command":"rm -rf build","createdAt":1763000000000}"#
let pending = parseClaudePendingApproval(Data(pendingJSON.utf8))
check(pending?.id == "abc", "parse pending id")
check(pending?.command == "rm -rf build", "parse pending command")
check(parseClaudePendingApproval(Data("{}".utf8)) == nil, "reject incomplete pending")
check(claudeApprovalId("abc") == "claude:abc", "approval id prefix")
check(claudeApprovalRequestId("claude:abc") == "abc", "strip approval prefix")
check(claudeApprovalRequestId("bridge-123") == nil, "non-claude id is not routed")
check(claudeApprovalRequestId(nil) == nil, "nil id is not routed")
check(claudeApprovalDecision("allowed-once") == "allow", "allow mapping")
check(claudeApprovalDecision("rejected") == "deny", "deny mapping")
check(claudeApprovalDecision("maybe") == nil, "unknown decision is rejected")
check(claudeApprovalCanAnswer("claude:abc"), "claude approval is answerable")
check(!claudeApprovalCanAnswer("bridge-123"), "other approvals stay read-only")

let older = ClaudePendingApproval(id: "1", nonce: "a", sessionId: "s1", cwd: "/p", tool: "Bash", command: "ls", createdAt: 1)
let newer = ClaudePendingApproval(id: "2", nonce: "b", sessionId: "s2", cwd: "/q", tool: "Bash", command: "pwd", createdAt: 2)
let picked = selectClaudePendingApproval([older, newer])
check(picked?.approval.id == "2", "newest pending wins")
check(picked?.extra == 1, "extra pending count")
check(selectClaudePendingApproval([]) == nil, "empty selection")
check(claudeApprovalNotice(project: "proj", extra: 2) == "proj · 还有 2 个待审批", "approval notice")
let decisionData = claudeApprovalDecisionJSON(newer, decision: "deny", at: Date(timeIntervalSince1970: 10))
let decisionObject = decisionData.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
check(decisionObject?["id"] as? String == "2", "decision payload id")
check(decisionObject?["nonce"] as? String == "b", "decision payload nonce")
check(decisionObject?["decision"] as? String == "deny", "decision payload decision")
```

- [ ] **Step 2: Run and watch them fail**

Run: `./tests/run.sh`
Expected: 编译失败 `cannot find 'parseClaudePendingApproval' in scope`。

- [ ] **Step 3: Implement the helpers in `Support.swift`**

`parseClaudePendingApproval` 用 `JSONSerialization`，要求 `schema == 1`，`id`/`nonce`/`sessionId` 为非空字符串，`createdAt` 为有限数字；任一不满足返回 nil。`selectClaudePendingApproval` 取 `max(by: createdAt)`，`extra = approvals.count - 1`。`claudeApprovalDecisionJSON` 用 `JSONSerialization.data(withJSONObject:)`，字段 `schema:1,id,nonce,decision,decidedAt`（毫秒整数）。

- [ ] **Step 4: Run to verify green**

Run: `./tests/run.sh`
Expected: `259/259` 变为 `2xx/2xx` 全部通过；Node 测试也通过。

- [ ] **Step 5: Commit**

```bash
git add Support.swift tests/main.swift
git commit -m "feat(claude): add approval parsing and decision helpers"
```

---

### Task 5: App 接线（扫描、合并、决定、界面）

**Files:**
- Modify: `Models.swift`（`claudeApprovalDirectory` 属性；`submitControl` 分流；`submitClaudeApproval`）
- Modify: `AppDelegate.swift`（启动时设置目录；`loadLiveFeed` 末尾调用 `syncClaudeApprovals()`；实现扫描/清理/合并/心跳）
- Modify: `Views.swift`（`claude:` 审批显示按钮；离线门放行；命令显示 6 行）
- Modify: `Support.swift`（`canAnswerExternalApproval` 对 Claude 返回 true，或改由 `claudeApprovalCanAnswer` 判断）

**Interfaces:**
- Consumes: Task 4 的全部 Swift 辅助函数；Task 2 的目录协议。
- Produces: 无新导出类型；行为契约见 spec §5.3。

- [ ] **Step 1: Wire the store and decision writing (`Models.swift`)**

- `DemoStore` 增加 `@Published var claudeApprovalDirectory: URL?`（放在 `controlDirectory` 后）。
- `submitControl(...)` 开头：
  ```swift
  if let requestId = claudeApprovalRequestId(approvalId) {
      return submitClaudeApproval(requestId: requestId, decision: decision, notice: notice)
  }
  ```
- `private func submitClaudeApproval(requestId: String, decision: String, notice: String) -> Bool`：
  读取 `<dir>/pending/<requestId>.json` → `parseClaudePendingApproval`；失败 → `approvalNotice = "审批已过期（hook 已超时）"`；用 `claudeApprovalDecision(decision)` 映射；`claudeApprovalDecisionJSON` 原子写到 `<dir>/decisions/<requestId>.json`（0700 目录、0600 文件）；追加 `<dir>/audit.log`（时间、id、sessionId、tool、command、decision、`source:"panel"`）；`approvalNotice = notice`。

- [ ] **Step 2: Wire the scan/merge (`AppDelegate.swift`)**

- `applicationDidFinishLaunching` 里在设置 `store.controlDirectory` 的同一层初始化：
  `store.claudeApprovalDirectory = appSupportBridgeDir()?.deletingLastPathComponent().appendingPathComponent("claude-approvals", isDirectory: true)`（bridge 目录不一定存在时也要设置，直接用 `FileManager...applicationSupportDirectory/AgentBar/claude-approvals`）。
- `private func startFeedPolling()` 的 timer 闭包改为先调用 `syncClaudeApprovals()` 再调用
  `loadLiveFeed()`；审批不依赖 `status.json` 能否解码，bridge 没起也能工作。
- `private func syncClaudeApprovals()`：
  1. `claudeApprovalDirectory` 下的 `pending/` 读文件、`parseClaudePendingApproval`、跳过超过 2 分钟的。
  2. `touchClaudeHeartbeat()`：写/更新 `heartbeat`（空文件，0600）。
  3. 删除超过 2 分钟的 pending 和超过 10 分钟的 decision。
  4. `selectClaudePendingApproval`；没有 pending 时：若 `store.agents` 里有 id `claude-approval` 的合成行则移除；若有 `claude` 行带 `claude:` 审批，清空 `approvalId/approvalCommand/note` 并把 `.waiting` 改回 `.running`。
  5. 有 pending 时：找 `store.agents` 里 id == `claude` 的行 → 设 `status = .waiting`、`approvalId = claudeApprovalId(approval.id)`、`approvalCommand = approval.command`、`note = claudeApprovalNotice(project: basename(cwd), extra: extra)`；找不到 → append 合成行（id `claude-approval`、name `Claude Code`、project `basename(cwd)`、tool `Bash`、`isExternal = true`、`startedAt = Date()`、同样字段）。
- 合成行的字段构造放在 `Support.swift` 会引入 Agent；保持 AppDelegate 内联（几十行胶水），其依赖的纯逻辑已在 Task 4 测过。

- [ ] **Step 3: Wire the UI (`Views.swift`)**

- 在 `approvalCard` 里先算 `let canAnswerClaude = claudeApprovalCanAnswer(agent.approvalId)`。
- 离线门：`if store.feedMode == .offline` → `if store.feedMode == .offline && !canAnswerClaude`。
- 按钮块：`else if store.isLive` → `else if store.isLive || canAnswerClaude`。
- 外部只读分支：`if agent.isExternal` → `if agent.isExternal, !canAnswerClaude`，让 Claude 审批落到
  现有的 `HoldToConfirmButton` 分支（含危险命令二次确认）。
- 底部说明：`agent.isExternal ? "只读 · 没有可代答的控制通道" : ...` 改为
  `canAnswerClaude ? (store.approvalNotice ?? "长按 0.4 秒确认 · 危险命令二次确认") : (agent.isExternal ? ... : ...)`；
  右下角审计文案对 Claude 显示 `"审计：claude-approvals/audit.log"`。
- 命令展示：`Text(agent.approvalCommand ?? "")` 的 `.lineLimit(2)` 改为 `.lineLimit(6)`，
  并加 `.textSelection(.enabled)` 与 `.help(agent.approvalCommand ?? "")`。

- [ ] **Step 4: Build and run the suites**

Run: `./tests/run.sh && ./build.sh`
Expected: Swift 全部通过，Node 全部通过，打包成功。

- [ ] **Step 5: Sanity-check the file protocol manually without a Claude prompt**

```bash
D="$HOME/Library/Application Support/AgentBar/claude-approvals"
mkdir -p "$D/pending" "$D/decisions"
printf '{"schema":1,"id":"manual-1","nonce":"n","sessionId":"s","cwd":"/tmp/proj","tool":"Bash","command":"echo hi","createdAt":%s}' "$(($(date +%s)*1000))" > "$D/pending/manual-1.json"
sleep 3
```
启动 App 后打开面板，确认出现「Claude Code · 待审批」卡片；点允许后检查
`$D/decisions/manual-1.json` 是否存在且 `decision == "allow"`，`audit.log` 是否追加一行。
最后删除 `manual-1` 的 pending/decision。

- [ ] **Step 6: Commit**

```bash
git add Models.swift AppDelegate.swift Views.swift Support.swift
git commit -m "feat(claude): surface panel approvals for Claude Bash prompts"
```

---

### Task 6: 文档与收尾

**Files:**
- Modify: `README.md`（外部 agent 审批说明；Claude 段改为「transcript + 可选审批 hook」）
- Modify: `docs/ROADMAP.md`（P2 外部一键接入的只读说法；技术债/待办）
- Modify: `bridge/README.md`（如果它声明外部审批只读）

- [ ] **Step 1: Update the docs**

写清：安装命令、默认 matcher、原生框与面板并存的竞态、Agent Bar 未运行时的行为、
已知限制（原生先答后卡片最多 40 秒消失）。

- [ ] **Step 2: Verify the whole suite and app**

Run: `./tests/run.sh && ./build.sh && codesign --verify --strict "Agent Bar.app"`
Expected: 全部通过；`codesign` 输出 `valid on disk` 与 `satisfies its Designated Requirement`。

- [ ] **Step 3: Commit**

```bash
git add README.md docs/ROADMAP.md bridge/README.md
git commit -m "docs: document Claude panel approvals"
```
