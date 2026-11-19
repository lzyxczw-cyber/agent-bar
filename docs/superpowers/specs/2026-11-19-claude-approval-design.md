# Claude Code 面板审批 · 设计

> 日期：2026-11-19 · 状态：待批准 · 路线：`PermissionRequest` hook + App 直接读写本地文件

## 1. 意图与原因

Claude Code 现在以只读 transcript 出现在状态条里：看得到项目、工具和思考，但 Claude 在
终端里弹出的 Bash 确认框，栏和面板都无能为力。这次要做的「功能升级」是：**Claude Code
本来要弹 Bash 确认框的那一刻，Agent Bar 面板也出现同一张审批卡片**，允许/拒绝都可以在
栏上点，和现有 DSH 审批卡片用同一套手势。

Claude Code 从 v2.0.45 起提供 `PermissionRequest` hook：它**只在原生确认框即将出现时**
触发，hook 可以返回 `allow` / `deny` 代替用户作答。这与 `PreToolUse` 的「每次 Bash 都
触发」有本质区别：自动允许的命令、`bypassPermissions` 模式、被 `deny` 规则挡下的命令
都不会经过我们，既不增加噪音，也不改变原有安全语义。

## 2. 目标与非目标

**目标**

- Claude Code 即将弹出 Bash 确认框时，Agent Bar 面板出现同一条命令的审批卡片。
- 面板点「允许」→ Claude 继续执行并收起确认框；点「拒绝」→ 工具调用被拦下。
- 复用现有审批卡片、危险命令二次确认、通知、`waiting` 状态与自动选中。
- App 不在、hook 出错、轮询超时：hook 静默退出，原生确认框照常工作。
- 只走本机文件；不依赖 DSH 连接、不依赖 bridge 是否连着 DeepSeek。

**非目标**

- 不接管「本来就不会弹框」的命令（自动允许、`bypassPermissions`、`plan` 模式）。
- 不接管非 Bash 工具；安装器保留 `--tools` 覆盖项。
- 不做 Claude 的问答审批（`ask_user_question`）。
- 不写 `permissions`、不改 `defaultMode`、不自动添加允许规则。
- 不做跨用户/远程审批。

**反目标（做出来也算失败）**

- App 没开时 Claude 的 Bash 变慢或被拦。
- hook 的 bug 让本该弹框的命令被自动放行。
- 面板出现重复的 Claude 行，或审批卡片找不到 agent。
- 原生确认框已在终端被回答后，面板卡片还长期挂着。
- 把命令以外的对话内容写进日志或审批文件。

## 3. 约束

- `PermissionRequest` hook 需要 Claude Code ≥ v2.0.45；本机 2.1.328 已核对存在该事件，
  输出形如 `hookSpecificOutput.decision = {behavior:"allow"} | {behavior:"deny", message}`。
- hook 输入是 `tool_name`、`tool_input`、`permission_suggestions` 加基础字段
  （`session_id`、`transcript_path`、`cwd`、`permission_mode`、`hook_event_name`）。
- `matcher` 是**未锚定的正则**，默认值写成 `^Bash$`，避免误匹配别的工具名。
- hook 触发时**原生确认框仍然显示**，两边可以同时作答；谁先给出决定，谁生效。
- hook 生命周期短，只能通过本地文件与 App 通信。
- hook 超时在 settings 里按条目配置（`timeout`，秒）；超时后 hook 被杀，原生确认框保留。
- App 的 feed 定时器 1 Hz；审批卡片最迟约 1 秒出现。
- 运行时文件目录 0700、文件 0600；审批文件只含工具名与参数。
- Claude 配置目录可被 `CLAUDE_CONFIG_DIR` 重定位；安装器必须跟随。

## 4. 方案取舍

| 方案 | 做法 | 优点 | 缺点 |
|---|---|---|---|
| **A（选中）** | `PermissionRequest` hook + App 直接扫描/写本地文件 | 只在真正要确认时出现；不动 bridge；App 不在时零影响 | 卡片与原生框并存的竞态需要清理策略 |
| B | `PreToolUse` hook 拦每一条 Bash | 能覆盖自动允许的命令 | 每条 `ls` 都进面板；会覆盖 `bypassPermissions` 语义；噪音大 |
| C | 复用 bridge 的 `control/` token 通道 | 审计统一 | bridge 的审批表绑定 DSH 会话；Claude 审批要另建表，职责耦合 |

选 A。B 与「只在需要确认时出现」的目标相反；C 把外部审批塞进 DSH bridge 不划算。

## 5. 设计

### 5.1 目录与文件（`$APP_SUPPORT/claude-approvals/`，0700）

| 文件 | 写入者 | 内容 |
|---|---|---|
| `pending/<id>.json` | hook | `{schema:1, id, nonce, sessionId, cwd, tool, command, createdAt}` |
| `decisions/<id>.json` | App | `{schema:1, id, nonce, decision:"allow"\|"deny", decidedAt}` |
| `heartbeat` | App 每次 feed tick 触碰 | 空文件；hook 判断 App 是否在运行 |
| `audit.log` | App 写完决定后追加 | `{ts, id, sessionId, tool, command, decision, source:"panel"}` |

- 原子写（临时文件 + rename），权限 0600；目录 0700。
- `id` 用 `randomUUID()`；`nonce` 用 16 字节随机 hex，App 原样回写。
- `command` 存完整命令（上限 4000 字符）；App 的卡片显示前 6 行，悬停可看全文，
  危险命令判定基于全文而不是截断后的第一行。
- 审批在 App 内的 id 是 `claude:<id>`，用于分流决定。
- 清理：hook 退出时删自己的 pending/decision；App 每 tick 删超过 2 分钟的 pending 和
  超过 10 分钟的 decision（hook 被 Claude 超时杀掉的兜底）。

### 5.2 hook 流程（`tools/agentbar-claude-approve.mjs`）

1. 读 stdin JSON（上限 1 MB）；失败 → 退出 0，无输出。
2. `hook_event_name !== "PermissionRequest"` 或 `tool_name` 不在允许集合（默认 `Bash`）
   → 退出 0，无输出。
3. `heartbeat` 缺失或 mtime 超过 10 秒 → 退出 0，无输出（App 没开，原生框照常）。
4. 生成 id/nonce，原子写 `pending/<id>.json`。
5. 每 150 ms 轮询 `decisions/<id>.json`，最长 40 秒（settings 里 hook `timeout` 设 45）；
   期间 heartbeat 失效立即退出。
6. 合法决定（id 与 nonce 都匹配）：
   ```json
   {"hookSpecificOutput":{"hookEventName":"PermissionRequest",
     "decision":{"behavior":"allow","message":"Agent Bar 面板已允许"}}}
   ```
   `deny` 时 `behavior:"deny"`，`message:"Agent Bar 面板已拒绝"`。
7. 超时 / 异常 / App 中途退出：退出 0，无输出 → 原生确认框保留，用户照常作答。
8. 离开前删除自己的 pending/decision。

命令摘要：`tool_input.command`；非 Bash（若用 `--tools` 放宽）取 `file_path`，否则取
`tool_input` JSON 的前 1000 字符。只存工具参数。

### 5.3 App 侧（Swift）——审批不经过 adapter/bridge

- `AppDelegate` 的 feed 定时器每次 tick 先调用 `syncClaudeApprovals()`，再读 `status.json`：
  扫描 `claude-approvals/pending/` 并把结果合并进当前 `store.agents`。审批不依赖
  `status.json` 能否解码，bridge 没起也能工作。
- 合并规则：
  - 找到 id 为 `claude` 的聚合行（adapter 的 group id）→ 设 `status = .waiting`、
    `approvalId = "claude:<id>"`、`approvalCommand = command`、`note = "<项目> · 还有 N 个待审批"`。
  - 找不到（DSH 没连、bridge 没起、transcript 还没落盘）→ 合成一行 id `claude-approval`、
    name `Claude Code`、`isExternal = true`、项目取 `basename(cwd)`、状态 `waiting`。
    用独立 id 是为了不和真实聚合行 `claude` 冲突，真实行出现后合成行自动移除。
  - 每条会话只展示最新一条；其余在 `note` 里计数。解决一条后下一条自然补位。
  - `pending` 清空后，合成的行与等待状态一起消失。
- `DemoStore.submitControl()`：`approvalId` 以 `claude:` 开头时走新分支：
  1. 读 `pending/<id>.json` 拿 `nonce` 与 `sessionId`；文件已不在 → 「审批已过期（hook 已超时）」。
  2. 原子写 `decisions/<id>.json`（decision `allowed-once`→`allow`、`rejected`→`deny`）。
  3. 追加 `audit.log`。
  4. 提示「已发送，等待 Claude 处理…」。
  非 `claude:` 维持现有 bridge/DSH 路径。
- 面板的离线门：`claude:` 审批不受 `feedMode == .offline` 限制（它不需要 bridge）。
  其它外部审批继续保持只读提示。

### 5.4 安装器（`tools/agentbar-install-adapter.mjs`）

- 目标 settings：`$CLAUDE_CONFIG_DIR/settings.json`（未设置时 `~/.claude/settings.json`），
  写前备份（现有 `backupFile`）。
- `claude`：
  - 把 `agentbar-claude-approve.mjs` 与 `lib/claude-approval-logic.mjs` 复制到
    `$APP_SUPPORT/hooks/`（0700/0600），hook 指向这份稳定副本，不指向仓库。
  - 合并一条 `PermissionRequest` hook：
    `{matcher: "^Bash$", hooks: [{type:"command", timeout:45, command:"<node> <hooks>/agentbar-claude-approve.mjs"}]}`。
  - `--tools "Bash|Edit|Write"` 覆盖 matcher；`--no-approvals` 只打印说明。
  - 顺手移除旧版 `agentbar-report.mjs` 上报 hook，并删除残留的
    `agents/claude-code.json`（只在 `id === "claude-code"` 时删），输出一行迁移提示。
- `uninstall-claude`：删除 `agentbar-report.mjs` 与 `agentbar-claude-approve.mjs` 两种标记，
  并删除 `$APP_SUPPORT/hooks/` 下的副本。
- `status`：输出 `transcript mode + approval hook (Bash)`；缺 hook 或 settings 路径不对时
  给出安装命令。

### 5.5 延迟、竞态与失败矩阵

| 情况 | 结果 | 延迟 |
|---|---|---|
| 面板点允许/拒绝 | hook 收到决定，原生框收起 | ≤0.5 秒 |
| 用户在终端原生框作答 | hook 轮询到超时后退出 | 卡片 ≤40 秒后消失 |
| 40 秒无人操作 | hook 退出，原生框保留 | — |
| App 未运行 | hook 立即退出 | <100 ms |
| pending 写失败 | hook 立即退出（不阻断） | <100 ms |
| App 在等待中退出 | heartbeat 失效，hook 退出 | ≤10 秒 |
| hook 被 Claude 超时杀掉 | App 2 分钟后清理 pending | — |

## 6. 安全边界

- 只在 Claude 本来就要弹框时介入；自动允许、`deny` 规则、`bypassPermissions` 全都不受影响。
- 面板 `allow` 只是一次性决定，不写回 settings，不扩大长期权限。
- 文件 0700/0600；nonce 防复用；id 随机；同用户信任域与现有 DSH 审批一致。
- 审批文件只含工具名与参数（命令原文，用户本来就看得见）；不写 transcript/思考。
- 默认 matcher 只有 `^Bash$`；放宽是显式选项（例如 `--tools "^Bash$|^Edit$|^Write$"`）。
- 已知竞态：原生框与面板同时可见，两边都能作答；后到的决定会被 Claude 忽略。
  卡片最长 40 秒自动消失。

## 7. 测试计划

**Node 单测**（`tools/lib/claude-approval-logic.mjs` 纯函数）

- 工具筛选、命令摘要（长命令截断、多行保留）、决定校验（id/nonce/behavior）、
  heartbeat 判定、pending 过期阈值。
- hook 集成测试：spawn 脚本 + 临时 `AGENTBAR_CLAUDE_APPROVAL_DIR`：
  allow、deny、超时（短 deadline）、heartbeat 失效、非 `PermissionRequest` 事件直接退出。
- 安装器：写入 `PermissionRequest`（matcher/timeout/命令路径）、重复安装不叠加、
  `--tools` 生效、`CLAUDE_CONFIG_DIR` 生效、清理旧 `PreToolUse` 上报 hook、
  `uninstall-claude` 清理两代标记、`status` 文案。

**Swift 单测**

- `claude:` 前缀识别、决定 payload、pending 合并规则（attach/synthesize/多条计数）
  提炼为纯函数放进 `Support.swift`，在 `tests/main.swift` 覆盖。
- 现有 `barFeedMode` 行为不变。

**手工验收**

- 真 Claude 会话触发需要确认的 Bash → 面板出现卡片 → 允许 → 命令执行；拒绝 → Claude 收到拒绝。
- 终端原生框先作答 → 面板卡片在 ≤40 秒内消失，不会重复执行。
- 关闭 Agent Bar 再触发 → 立刻回到终端原生确认。
- 危险命令（`rm -rf`）→ 面板二次确认仍然生效。
- DSH 未连接时（`status.json` 的 `dsh.connected=false`）→ 面板审批仍可用。

## 8. 留给实现者的决定

- pending 文件名是否带时间戳前缀（只影响调试）。
- 轮询 150 ms / 等待 40 秒 / hook timeout 45 是否按实测调整。
- 卡片展示 6 行还是可折叠全文（不影响审批语义）。
- 审计字段是否增加 `toolInputDigest`（默认不加）。
