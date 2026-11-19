# Claude Code 只读会话支持 · 设计

> 日期：2026-11-19 · 状态：待批准 · 路线：方案 A（读 transcript）

## 1. 意图与原因

状态条目前对 Claude Code 只有 hook 上报：每个 `PreToolUse` 写一次「正在跑 + 工具名」，`Stop` 写 done。信息量比 DSH 和桌面 adapter 少，多个 Claude 会话也共用一个 `claude-code` 状态。

目标是让 Claude Code 在栏上像 Codex / WorkBuddy 一样被**直接读懂**：项目、分支、当前工具、最新思考、token、并发会话，全部来自 Claude 自己写的会话文件，不要求用户装 hook，也不接管审批。

## 2. 目标与非目标

**目标**

- 从 `~/.claude/projects/**/*.jsonl` 读取最近会话，无需安装 hook。
- 单会话显示：项目、当前工具与目标、最新思考、token、状态。
- 同时最多 3 个运行中的会话，各自独立一行。
- 只做只读，不向 Claude 发送任何输入。
- 失败时安静降级：读不到、解析不了、目录不存在，都不影响其他 adapter。

**非目标**

- 双向审批（方案 C，后续单独设计）。
- 实时事件流（方案 B）。
- 读取 subagent / sidechain 的内部会话作为独立行。
- 修改 Claude 的任何配置。

**反目标（即使做出来也算失败）**

- 让 Claude 的响应变慢或被阻塞。
- 把完整对话、工具输出或思考原文写进日志。
- 与旧的 `claude-code.json` hook 报告重复显示同一个会话。
- 同一个对话因为 `continued-in` 出现两行、token 翻倍。

## 3. 约束

- `tools/agentbar-app-adapters.mjs` 由 App 启动，每 3 秒 tick 一次；适配器必须在 tick 内完成，不能阻塞。
- 会话文件可能很大（本机单个文件数十 MB），不能每次全量读取。
- 一条 assistant **消息**会被写成多条 JSONL 记录（thinking / text / tool_use 各一条），它们共享 `message.id` 并重复同一个 `usage` 对象。按记录累加会虚高 2–3 倍。
- 每个 assistant 记录带时间戳；`cost-state` 只有会话累计，没有按天拆分。
- 记录末尾经常是元数据（`cost-state`、`continued-in`、`last-prompt`、`system`、`api-request*` 等），不能当成最后活动。
- 一个会话被 `/clear` 或压缩后，旧文件末尾会写 `continued-in`，字段 `continuedInSessionId` 指向继任文件；继任文件会复制此前的消息。
- bridge 对超过 120 秒没有更新的报告会隐藏，适配器需要持续刷新仍然活跃的会话。
- 报告写入沿用现有 `writeReport`（原子写、0600、`source` 标记）。
- Claude Code 配置目录可通过 `CLAUDE_CONFIG_DIR` 重定位；测试用它指向临时目录。

## 4. 方案取舍

| 方案 | 做法 | 优点 | 缺点 |
|---|---|---|---|
| **A（选中）** | 轮询 transcript JSONL | 不改配置、信息最全、历史会话也能读、天然支持多会话 | 延迟 0–3 秒；无法知道「在等审批」 |
| B | 扩展 Pre/PostToolUse hook | 事件驱动、延迟低 | 信息少（没有思考）、要用户装 hook、仍不能审批 |
| C | PreToolUse 阻塞等待栏上决定 | 与 DSH 一致的审批体验 | 会卡住 Claude、超时/崩溃/安全边界复杂 |

选 A：用户要的是「看得清」，不是「接管」。C 留作下一阶段。

## 5. 设计

### 5.1 放置位置

- 扫描与提取：`tools/agentbar-app-adapters.mjs` 新增 `claudeReports()` 适配器，加入 `tick()` 的 adapters 列表，group 名 `claude`。
- 纯函数（解析、状态推断、工具摘要、token）放进 `tools/lib/adapter-logic.mjs`，供单测直接引用。
- 增量读取状态只保存在 watcher 进程内存里，不落盘。

### 5.2 发现会话

- 根目录：`$CLAUDE_CONFIG_DIR/projects`（未设置时 `~/.claude/projects`）。
- 每个项目目录只取**第一层** `*.jsonl`；跳过目录（如 `<session>/tool-results`、`memory`）。
- 只看最后一条**有效记录**（跳过元数据）时间在最近 15 分钟内的文件；每次 tick 重新 `readdir`，文件消失即移除报告。
- 末尾带 `continued-in` 的文件直接跳过（继任文件已经包含全部历史）。
- 并发上限：按最后活动时间倒序取前 3 个。

### 5.3 增量解析

每个文件维护 `{ offset, size, sessionId, startedAt, lastEventAt, seenMessageIds, ... }`：

- **首次看到**文件时，从尾部读取最多 16 MB（按行切齐，丢弃半行），用来建立当天 token 基线和最后状态；offset 直接置为文件大小。
- 之后每 tick 只读取 `offset` 之后新增的字节，单次上限 256 KB；超过上限时跳到最新一屏，丢一行日志。
- 按行拆分；最后一行不完整时保留到下次（不消费）。
- 文件变短（被截断或替换）时重置 offset 与当天 token 基线。
- 跳过类型：`cost-state`、`continued-in`、`last-prompt`、`system`、`api-request*`、`api-request-shape`、`api-request-blob`、`attachment`、`file-history-*`、`ai-title`、`custom-title`、`mode`、`permission-mode`、`agent-name`、`agent-setting`、`queue-operation`、`pr-link`、`tools-used`、`atis-latch` 等元数据。

### 5.4 提取字段

从最近的有效记录回溯：

- `sessionId`、`cwd`、`gitBranch`、`message.model`（取最新 assistant）。
- **project**：`basename(cwd)`；cwd 缺失时退回编码后的项目目录名。`slug` 是会话昵称（如 `floating-sleeping-pnueli`），不当作项目名。
- **thought**：最近一个 assistant `thinking` 块，没有则退回最近 `text` 块；压成单行，截断 600 字符。
- **当前工具**：最近 assistant 的 `tool_use` 块：
  - `Bash` → 命令第一行（截断 160）
  - `Edit` / `Write` / `Read` / `NotebookEdit` → `file_path` 的 basename 或相对 cwd 的路径
  - `Grep` / `Glob` → pattern
  - `Task` → description
  - 其他 → 工具名
- **detail**：工具目标 + 分支（`branch: xxx`），截断 300。
- **tokens（口径：今天）**：只累加时间戳在**本地当天零点之后**的 assistant 记录，按 `message.id` 去重（同一个 id 只取最后一次的 `usage`）；数值为 `input_tokens + output_tokens + cache_creation_input_tokens`，**不含 `cache_read_input_tokens`**。
  - 文件首次出现时从尾部 16 MB 建立基线；超过 16 MB 的当天历史会少算，日志记一次，不报错。
  - 与既有 `tokens` 字段含义一致（bridge 把它当作「今日 tokens」）。

### 5.5 状态推断

只看最后一条有效记录（跳过元数据）：

| 最后记录 | 状态 |
|---|---|
| assistant，含未配对的 `tool_use` | `running` |
| user，含 `tool_result`（模型还在处理） | `running` |
| user 真正的新指令（见下） | `running` |
| assistant，`stop_reason = end_turn` 且无 tool_use | `done` |
| 其他 / 无法判断 | 沿用上次状态 |

**真正的 user 指令**：`isMeta` 不为真，且正文不以 `<command-`、`<local-command-`、`<system-reminder` 开头。`<command-name>/plugin</command-name>`、`<local-command-stdout>…</local-command-stdout>` 这类记录按元数据处理，不算新指令。

- 新鲜度用最后一条**有效记录**的时间戳，不用文件 mtime（元数据写入会更新 mtime，把早就结束的会话拖活）。
- 超过 15 分钟没有任何有效记录：停止上报，让 bridge 自然隐藏。
- 不区分「执行中」和「等待用户批准」：没有 hook 就看不到审批；文案统一写运行中，不谎称等待。
- 结束的会话若仍在 15 分钟内，会以 `done` 的父行（id `claude`）留在栏上，15 分钟后消失。

### 5.6 报告映射

- 每个活跃会话：`id = "claude-" + sessionId 前 8 位`、`name = "Claude Code"`、`project = basename(cwd)`、`status = running | done`、`startedAt = 会话首次被看到的时刻`、`updatedAt` 每 tick 刷新、`lastActivity = 最后一条有效记录时间戳`。
- 运行中的会话交给 `aggregateApp` 折叠成一个 `claude` 父行，最多 3 个子会话；父行的 project / tool / thought 取**最后活动**的会话。
- 为支持这一点，`aggregateApp` 的排序从「只按 `startedAt`」改为「`lastActivity || startedAt`」；其他 adapter 不传 `lastActivity`，行为不变，现有测试保留并新增一条。
- 无运行会话但有最近结束的会话：写入一个 `id = "claude"` 的 idle/done 父行。
- 无任何近期会话：不写文件，`syncGroup` 会清掉旧报告。
- 图标：现有品牌规则把含 `claude` 的 id/name 映射到 Claude 图标，无需改动。

### 5.7 与旧 hook 的关系

- `agentbar-install-adapter.mjs claude` 改为提示「Claude Code 现在直接读会话文件，无需 hook」，不再写入 hooks；`uninstall-claude` 保留，用于清理老用户已装的 hook。
- 已安装 hook 的用户：继续工作的 `claude-code.json` 会和新的 `claude-*` 同时出现。适配器**不删除**其他写入者的文件；README 增加一行迁移说明（运行 `uninstall-claude`）。
- 本机当前 `~/.claude/settings.json` 没有我们的 hooks，不受影响。

### 5.8 隐私

- 只读本地文件；不联网；思考文本只截取最近一条的片段。
- 报告目录 0700、文件 0600，沿用现有写入器。
- 日志只记文件名尾部和错误类型，**不记**任何消息内容。
- 外部思考翻译默认关闭（上一版已实现）；开启了才会把 thought 发往 DeepSeek。

### 5.9 测试

- `tests/adapter-logic.test.mjs` 增加纯函数用例：
  - 从尾部跳过 `cost-state`、`last-prompt` 等元数据，找到真正的 assistant 记录。
  - 未配对的 tool_use → running；stop_reason end_turn → done；tool_result → running；`<command-name>` 记录不算新指令。
  - `continued-in` 文件被跳过。
  - 工具摘要：Bash 取首行、Edit 取路径、超长截断。
  - token 按 `message.id` 去重、只计当天、排除 cache read。
  - 不完整最后一行不消费。
- `tests/claude-adapter.test.mjs` 新增集成用例：
  - 用临时 `CLAUDE_CONFIG_DIR` 造两个项目、三个会话。
  - 以 `--once` 跑 watcher，断言输出里最多 3 个 `claude-*`，字段正确。
  - 不读取 `tool-results/` 之类的子目录。
  - `continued-in` 的旧会话不出现。
- 现有 27 项测试保持全绿；`./build.sh` 通过。

### 5.10 文档

- `README.md` 支持矩阵：Claude Code 从「hooks 一键安装 / 可上报 / 只读」改为「自动读取本地会话 / 无需安装 / 只读」，并保留审批限制说明；补一句 token 口径（今日、不含缓存读取）与旧 hook 迁移。
- `bridge/README.md` §11 增加 Claude transcript adapter 的字段口径与 token 口径。
- `docs/ROADMAP.md` 在「外部 agent 一键接入」处补一句。

## 6. reviewer 提问的处理（我的决定）

1. **token 重复计数**：按 `message.id` 去重；口径是「今天」；不用 `cost-state`（它没有按天拆分）。
2. **`continued-in` 幽灵会话**：末尾带 `continued-in` 的文件直接跳过；新鲜度改用最后有效记录时间戳，不用 mtime。
3. **伪 user 记录**：跳过 `isMeta` 与 `<command-*>` / `<local-command-*>` / `<system-reminder*>` 开头的正文。
4. **project 用错字段**：改用 `basename(cwd)`；`slug` 不进 project。
5. **「今日 tokens」语义**：适配器直接产出当天 token，不改 bridge/UI；文案注明不含缓存读取。
6. **父行排序**：`aggregateApp` 支持可选的 `lastActivity`，Claude 传它，其他 adapter 不受影响。

## 7. 留给实现者的决定

- 具体的元数据跳过名单与截断长度（以可读性和 tick 预算为准）。
- 每文件 offset / seen-message-id 状态的结构与日志节流方式。
- 工具目标的具体格式（例如相对路径的显示方式）。
- 集成测试的 fixture 大小与断言措辞。
