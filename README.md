# Agent Bar — 刘海上的 AI Agent 状态条（macOS）

把 MacBook 刘海两侧（或顶栏）变成 AI agent 的实时状态区：像素风 app 图标 + 选中后展开的长胶囊，胶囊里显示**中文思考摘要**；点开面板可以看到**完整思考 + 执行过程时间线**。右侧靠刘海处是审批、实时 agent 数、**用量/余额**，最右侧是电量、Wi-Fi、天气、日期时间。设置与退出收进面板底部，点刘海向下展开。

> **非官方。** Agent Bar 与 DeepSeek Harness（DSH）、Codex、Claude、Grok、WorkBuddy 没有隶属、合作或背书关系。对 DSH 的接入是读取本机凭据的非官方桥，随 DSH 版本可能失效。

## 安装

这棵源码的 bundle 版本是 **v0.3.6**。已经打过 tag 的安装包仍是 [GitHub Release v0.3.4](https://github.com/lzyxczw-cyber/agent-bar/releases/tag/v0.3.4)；更新的 DMG 要等下次打 `v*` tag 才会出现在 Releases 里。应用内更新检查看的是这个 Release，不会提前假设还没发布的包。

- DMG：上面的 v0.3.4 Release（当前已发布的安装包）
- Homebrew：仓库里的 cask 没有单独的 tap，它直接下载已发布 Release 里的 DMG。在克隆下来的 `agent-bar` 目录执行：

```bash
brew install --cask ./Casks/agent-bar.rb
```

日常使用建议装这个已签名公证的 DMG。下面的 `./build.sh` 是从源码构建。

> 公开仓库不附带带本机桌面背景的截图，避免泄露私人窗口内容。这台云环境也不能运行 macOS App，所以这里没有补产品截图。

## 左栏

- Agent 图标按固定顺序排列；选中图标后，**状态胶囊从它后面展开**，宽度吃掉刘海左侧剩余的全部长度，后面的图标顺次让位。
- 胶囊内容：图标 + 名称 + 状态 + 项目 + 当前工具 + **💭 中文思考摘要** + 耗时。
- 点选/自动轮播共用「图标弹一下 + 粒子 + 胶囊展开」动效；**轮播只轮 running / waiting 的 agent**。
- 动效期间 0.55s 命中锁；胶囊可点击打开面板。
- 超过 5 个 agent 时，图标行末尾显示 `+N`；点击 `+N` 直接展开面板查看全部 agent。

## 图标

栏上 **18 pt**，面板列表 **26 pt**。源文件是确认过的 **128×128** 透明 PNG（`Resources/agents/<id>/idle_00.png` … `idle_03.png`），按比例交给系统高质量缩小，不再把旧的 16×16 字符稿拉大。`idle_strip.png` 只是横向预览，不参与播放。

这批素材只有 idle 四帧，运行、等待、完成、失败都播这一套。换帧间隔优先用 manifest 里的 `suggestedIntervalSec`（目前是 0.70 秒）；某个套装没写间隔时，才沿用原来的状态间隔（运行 0.45、等待 0.70、完成 1.70、失败 1.20）。失败状态仍是 0.75 透明度。`phase` 会错开多个图标，避免同时眨眼。对应 PNG 缺失时回退到 `PixelSprite` 字符稿。

名称匹配不区分大小写，顺序如下：

1. 含 `codex` / `chatgpt` / `openai` → codex
2. 含 `grok` → grok
3. 含 `workbuddy` 或 `work buddy` → workbuddy
4. 含 `claude` → claude（排在 live 默认 DSH 之前，避免 Claude 会话被画成 DSH）
5. `live` → dsh
6. 含 `dsh` / `deepseek` / `harness` → dsh
7. 含 `codeisland` 或 `island` → island
8. 含 `hermes` → bolt
9. 含 `review` 或 `doc` → magnifier
10. 含 `test` / `build` / `bash` → flask
11. 其余 → `generic`。未知名称不再哈希到 Codex、Grok、WorkBuddy、DSH 或 Claude 上。

## 右栏

- AI 信息靠刘海：待审批（最靠近刘海）→ 实时/演示 chip → agent 数 → 运行数 → **用量（今日 token）** → **余额（CNY）**。
- 系统状态靠最右：电量（无电池显示 AC）、Wi-Fi、**上下行网速**、天气、日期 + 时间；用量/余额 60s 刷新。
- 网速只有约 76pt 宽：`↓ 323K ↑ 34K`，1s 采样 + 指数平滑，只在取整后的文字变化时才重绘；**30 秒无流量会自动淡出，有流量再出现**。

## 思考与过程

- bridge 会把每个 agent 的最新英文 reasoning 通过 **DeepSeek API** 翻译成简体中文，写入 `thoughtZh`；胶囊和面板优先显示中文，原文 `thought` 保留。
- 面板「思考与过程」：完整中文思考（最多 8 行）+ 最近 8 个步骤（思考/工具/结果/回复 + 时间）。思考正文渲染行内 Markdown（加粗、斜体、行内代码、系统支持的链接），不解析 HTML。胶囊摘要仍是单行纯文本。
- 设置里可关闭「思考自动中文化」，关闭后显示英文原文。
- 翻译 key 来自 `~/.dsh/.credentials.yaml` 的 `DEEPSEEK_API_KEY`（或环境变量），只用于请求头；不会打印/写入 status.json。翻译失败时回退原文。

## 通知与审批

- 审批到达、任务完成、失败时播放提示音；获得系统通知授权时还会发 macOS 通知（点击通知打开面板并选中该 agent）。
- 面板顶部展示待审批队列（最多 3 条 + 剩余数量）；可以直接在面板里答复：
  - **长按 0.4 秒「允许」或「拒绝」**，松开取消，避免误触
  - 危险操作（`danger-full-access` 提权、`rm -rf`、`sudo` 等）第一次长按只进入「再次长按允许」确认
  - 点「打开 DSH 处理」仍可跳回 GUI；「复制会话 ID」便于排查
- 答复走本机控制通道：App 写 `~/Library/Application Support/AgentBar/bridge/control/request-*.json`
  （目录 0700、token 文件 0600），bridge 校验 token + 仍在 pending 的 approval ID 后调用 DSH `$events/result`。
  只对**已存在的 approval** 作答，不会发 prompt、不会改命令。
- 每次决定写入 `bridge/audit.log`（0600）：时间、approvalId、sessionId、tool、command、decision、result。
- 问题（`ask_user_question` / `user-questions/request`）可以在面板里回答：选项按 DSH 给出的 label 提交，允许自填的题可以写自定义文本，取消会发送 `ASK_CANCELLED`。无法安全校验的题型（未知 intent、重复选项等）保持只读，请用「打开 DSH 处理」。
- 关闭控制通道：bridge `--no-control`。
- 系统通知需要在「系统设置 → 通知 → Agent Bar」授权；未授权时仍会有提示音。
- 还没有授权时，面板里会出现一次说明：可以点「允许通知」拉起系统对话框，或点「以后再说」关掉这张卡片。系统已经拒绝时，卡片改为引导打开「系统设置 → 通知 → Agent Bar」，点「知道了」后不再反复出现。设置页始终可以再请求授权或打开系统设置。应用不会在每次启动时自己弹出系统授权框。
- 正式 DMG 已 Developer ID 签名并公证；repo 内直接构建的 App 仍可能是 ad-hoc，建议安装 DMG 版本。

## 自动更新

应用启动约 20 秒后，以及之后每 6 小时，会请求一次
`https://api.github.com/repos/lzyxczw-cyber/agent-bar/releases/latest`，
把稳定版 tag 和本机 `CFBundleShortVersionString` 比较。

- 已是最新、或本机版本更高：设置里显示已是最新，栏上不提示。
- 有更新：栏上出现「有更新」，面板和设置里可以**下载官方 DMG** 或打开 GitHub 发布页。DMG 地址必须与 cask 使用的
  `Agent-Bar-<version>.dmg` 完全一致，否则只给发布页。安装由用户自己完成，**不会覆盖正在运行的 App**。
- 检查失败（网络、限流、无法解析）：只写在设置里，不在栏上反复提示。
- 「稍后」把这个版本静音 24 小时；「忽略」不再提示这一个版本。下一个更高版本仍会再提示。
- 预发布和 draft 不当作可安装更新。没有接 Sparkle，也没有另外做一个 Homebrew tap。

## 用量、预算与趋势

- bridge 按 agent 记录**今日增量 tokens**（不是会话累计），面板每行会显示该 agent 今天的 token 数。
- 右栏显示今日总用量；设置里的「每日 token 预算」> 0 时，超过预算右栏用量会变橙，并当天提醒一次。
- 设置里的「用量趋势」用 sparkline 显示近 7 天（今天已计入）；历史持久化在
  `~/Library/Application Support/AgentBar/bridge/usage-state.json`。
- 历史天数从 bridge 运行后开始积累；首次使用只有今天一个点。

## 设置与退出

- **点击刘海区域 → 面板从刘海向下展开**；再点刘海/按 Esc/点击其他 App 会收起。
- 面板底部是 **设置** 按钮；设置页包含：
  - 固定面板（切换到其他 App 不收起）
  - 通知开关
  - 思考自动中文化开关
  - **天气位置**（输入城市名搜索，选择候选后立即刷新；常用城市作为离线快捷入口）
  - **每日 token 预算**（超过后右栏用量变橙并当天提醒一次；0 = 关闭）
  - **用量趋势**（近 7 天 sparkline）
  - **本机 App 接入**（Codex / WorkBuddy / Grok Bot / Hermes 在线状态与运行数）
  - **显示屏幕**（主屏或任意外接屏，切换后顶部条和面板跟随）
  - 打开 DSH
  - **退出 Agent Bar**
- 面板标题栏有固定/关闭按钮；固定后切 App 不收起。

## 快捷键

- `⌃⌥⌘A`：呼出/收起面板
- `⌃⌥⌘Q`：退出
- `Esc`：收起面板
- 光标顶到屏幕上边缘：让位显示系统菜单栏；移开恢复

## 实时数据（DSH bridge + 外部 agent）

`bridge/` 是本地 Node 桥（Node ≥20，无第三方依赖）。实时 feed 默认只读；另有一个**本机控制通道**，
只允许回答已经 pending 的 `approval/request`（`allowed-once` / `rejected`）和能校验的 `user-questions/request`。App 启动时同步到：

`~/Library/Application Support/AgentBar/bridge/`

（避免 `~/Documents` 的 TCC 权限弹窗；仓库 `bridge/` 是源目录，`start.sh` 每次同步。）

- 读取 `~/.dsh/.credentials.yaml` 的 browser-session secret，在内存中自签 DSH Web 会话 Cookie（不写 DSH 配置）；
- session/list + session/page + WebSocket remote 事件流；
- 输出 `status.json`（原子写 0600、变更即写 + 5s 心跳）；新增 `thoughtZh`、`external agents`、`bridge.translate` 等字段，详见 [bridge/README.md](bridge/README.md)；
- 能看到审批和提问。审批、以及能校验的提问，可通过本机 control 通道答复（见上方「通知与审批」）。不会发 prompt、不会改命令；事件不离开本机（翻译请求除外，只发往 DeepSeek API 的 reasoning 文本）。

### 一键接入（Claude Code / Codex）

```bash
node tools/agentbar-install-adapter.mjs claude   # 合并 PreToolUse/Stop hooks
node tools/agentbar-install-adapter.mjs codex    # 生成 codex-agentbar wrapper
node tools/agentbar-install-adapter.mjs status  # 查看安装状态
node tools/agentbar-install-adapter.mjs uninstall-claude
```

- Claude Code：备份 `~/.claude/settings.json` 后合并 hooks，不覆盖已有 hooks；重启 Claude Code 生效。
- Codex：生成 `~/Library/Application Support/AgentBar/adapters/codex-agentbar`，按输出提示加 alias。
- 两者都只是状态上报。审批仍在各自的工具里处理：面板不会为它们显示「允许」。

### 外部 agent 接入（Codex / Claude Code / 任意 CLI）


任何进程每 30–60s 往 `~/Library/Application Support/AgentBar/agents/<id>.json` 写一份 JSON 心跳，即可出现在状态条：

```bash
node tools/agentbar-report.mjs --id codex --name Codex --status running \
  --project agent-notch --tool "Bash: swift build" --thought "正在编译发布版..."
# 结束
node tools/agentbar-report.mjs --id codex --status done
# 移除
node tools/agentbar-report.mjs --id codex --remove
```

bridge 每 tick 扫描一次；120s 无心跳隐藏，文件删除即移除。完整 schema、Codex wrapper 和 Claude Code hooks 示例见 [bridge/README.md](bridge/README.md) §11。

### 本机桌面 App adapter（Codex / Grok Bot / WorkBuddy / Hermes）

直接双击 App 或走 `start.sh` 都会自动启动 `tools/agentbar-app-adapters.mjs`（脚本打包在 App 的 Resources 里），只读取本机 App 的本地状态，不修改 App。

**同一 App 只占一个图标/一个父行**，最多 3 个活跃会话收进 `sessions` 数组；选中父行后在面板里展开子会话。父行右侧的 ↗ 按钮、或在栏上双击该 App 的图标，会切到对应 App。设置 → Adapter 控制 可打开 adapter 日志或重启 watcher。

| App | 数据源 | 上报内容 |
|---|---|---|
| **Codex**（ChatGPT.app） | `~/.codex/thread_history_1.sqlite` | 进行中的 turn、当前 Bash 命令 / 编辑文件、cwd、reasoning 摘要 |
| **WorkBuddy** | `~/.workbuddy/traces/<worker>/trace-*.jsonl` | 运行中的 trace、当前 span（generation/Bash/…）；多条 trace 收成一个父行 |
| **Grok Bot** | `.../Grok Bot/sand-client-persistence/*.blob` | 流式/未返回的请求、最近对话 agent、最后一条用户消息 |
| **Hermes** | `$HERMES_HOME/state.db`，默认 `~/.hermes/state.db` | 进程在跑且最近 90 秒有消息的会话；没有数据库或进程时不编造，仍走演示数据 |

```bash
node tools/agentbar-app-adapters.mjs --once   # 打印一次解析结果
node tools/agentbar-app-adapters.mjs          # 前台 watch（start.sh 会后台启动）
tail -f /tmp/agentbar-adapters.log
```

限制：每个 App 最多显示 3 个活跃会话，没有官方 API，状态是从本地数据推断的。Hermes 只读 `sessions` / `messages` 里白名单列，不写 `state.db`，也不把累计 token 当成今日用量。命名 profile 只有在 `HERMES_HOME` 指向该目录时才会被读到。外部 App 的审批仍是只读，子会话只能看、不能单独跳转到 App 内的任务。
App 退出后 adapter 会自动移除对应图标。

### 目前各 App 的支持程度（2026-11-17）

| App / Agent | 实时状态 | 思考 / 过程 | 审批 |
|---|---|---|---|
| **DeepSeek Harness（DSH）** | ✅ 原生 bridge（非官方） | ✅ | ✅ 审批双向；可校验的提问可在面板回答 |
| **Codex**（ChatGPT.app / CLI） | ✅ 桌面 App adapter（本地 SQLite）；CLI 另有 wrapper | ✅ 命令 / 文件 / reasoning | ❌ 只读。审批协议是当前 `codex app-server` 连接上的 `item/commandExecution/requestApproval`，Agent Bar 不是那条连接 |
| **Claude Code** | ✅ hooks 一键安装 | ⚠️ 可上报 | ❌ 只读。允许/拒绝只能由当次 `PreToolUse` hook 输出；现有 hook 只上报状态，不阻塞、不另发 prompt |
| **WorkBuddy** | ✅ 本机 trace adapter | ✅ 当前 span（无自然语言 thought） | ❌ 只读。trace 不是带 token 和 pending id 的控制接口 |
| **Grok Bot** | ✅ 本机 persistence adapter | ⚠️ 最近对话，无 reasoning 细分 | ❌ 只读。本地 blob 不是控制通道 |
| **Hermes** | ✅ 本机 `state.db`（进程在跑且库可读时）；否则仍是演示 | ⚠️ 最近一条消息，推断状态 | ❌ 只读。`state.db` 没有审批回调 |
| **任意 CLI** | ⚠️ `tools/agentbar-report.mjs` 心跳 | ⚠️ 可上报 | ❌ 只读。上报里的 `approvals` 没有可校验的控制通道 |

这些只读项不会显示「允许」按钮。面板写明原因。双向审批仍然只对 DSH 里已经 pending、并能校验 token 的事件生效。没有为某个 App 发明一条写命令。

## App 运行

```bash
cd agent-bar
./build.sh        # 编译 + 打包 Agent Bar.app
./start.sh        # 同步 bridge 到 Application Support 并启动
# 直接双击 Agent Bar.app 也可以：bridge 和本机 App adapter 都会自动启动
./status.sh       # 进程 + feed 摘要
./stop.sh         # 停止 App 与 bridge
```

不修改系统设置；退出后原生菜单栏立即恢复。演示模式只在确实没有实时数据时使用（bridge 没连上、或还没发现 DSH），内置 5 个 agent 和一条演示审批。右栏 chip 显示 `演示` / `实时` / `离线`。若已经发现 DSH，但 `session/list` 的协议对不上，chip 和面板显示 **协议不匹配**，不会改回演示数据。

## 实现要点

- AppKit `NSPanel` + SwiftUI；演示模式盖在菜单栏上方，真实模式（系统自动隐藏菜单栏）放在菜单栏下方。
- 刘海几何：真机用 `NSScreen.safeAreaInsets.top` / `auxiliaryTopLeftArea/RightArea`；无刘海屏按 11.8% 宽度模拟。
- 命中测试：SwiftUI 通过 `RailFramePreferenceKey` 把**真实渲染出来的**图标/胶囊 frame 写进 `ui.railLayout`，
  AppKit 侧只读这份数据，不再各算一遍（以前两套公式会漂移）+ 0.55s 动画锁。`--debug-layout` 可打印实时区间。
- 光标跟随：全局/本地 `mouseMoved` 监听即时响应，只保留 1Hz 定时器兜底（原来 20Hz 常驻轮询，空闲时约 8% CPU → 现在 ~2.5%）。
- 面板：560×500，**顶边紧贴栏底（1pt）**，展开时像从刘海里长出来；阴影交给窗口（`hasShadow`）
  由系统按圆角 alpha 形状合成，不再手动画、也不再需要透明的阴影留白（留白会吞掉点击）。
- bridge 子进程通过 `/bin/sh` + shell 重定向启动；20s 看门狗。
- 主线程卡死 >20s 自动退出，避免菜单栏一直被盖住（退出前先杀掉 bridge，否则 `exit(0)` 绕过
  `applicationWillTerminate` 会留下一个空转的 bridge）。
- 光标监听做 8ms 节流；日志超过 2MB 时启动轮转到 `/tmp/agentbar.log.1`。
- 选中图标时仍会撒一小圈粒子（`BurstOverlay`）。系统开启「减弱动态效果」后不再撒粒子，只保留淡入/淡出。应用内没有单独的粒子开关。

## 已知限制

- 审批控制通道支持 `approval/request`（`allowed-once` / `rejected`），以及能校验的 `user-questions/request`（`answers[].selected` 为选项 label，可选 `custom`；取消为 `ASK_CANCELLED`）。答复异步，以卡片消失为准，
  失败可在 `bridge/audit.log` 查看；控制通道与 bridge 同属当前用户信任域，token 文件 0600，不要跨用户共享 AppSupport。
- 危险命令判定是启发式（`danger-full-access`、`rm -rf`、`sudo` 等），不是完整安全边界。
- 余额只取主钱包；不显示按模型拆分消耗。
- **今日用量按「桥接观测到的当日增量」计**：DSH 的 `tokenUsage` 只给会话累计值且按回合刷新，
  所以不再把整个会话累计当成今日（以前会明显高估），代价是桥接启动前已发生的部分不计入；
  基线存 `bridge/usage-state.json`，跨重启/跨零点不会重复累加。
- 天气有两个源：open-meteo 优先，失败自动回落 wttr.in（wetter 代码已映射到 WMO）；都失败时按退避重试并显示 `--°`。
- 思考翻译依赖 DeepSeek API key 与网络；失败回退英文原文。
- 系统通知需在系统设置授权。未授权时面板会提示一次，之后只在设置里保留入口；提示音一直保留。本机 `~/Documents` 的 File Provider 仍可能让 repo 内 App 的本地签名校验失败，建议安装已公证的 DMG 内 App。
- 实时数据按 DSH 0.2.2-rc.3 的 `session/list` 与 `$events` 实现。探针发现协议对不上时，栏上显示「协议不匹配」，而不是静默回到演示数据。其他 agent 走外部上报协议。
- 本机桌面 adapter 读 App 的本地数据，状态是推断：Codex 取最近的 `inProgress` turn，WorkBuddy 取未结束 trace，Grok Bot 取 streaming/未返回请求；每个 App 最多显示 3 个活跃会话；App 关闭后 adapter 会自动清掉对应图标。
- 外部 agent 图标见上文「图标」：128×128 PNG 由系统缩小到栏 18 pt、面板 26 pt。Claude 有专用图标；未知名称用 generic，不再占用 Codex / Grok / WorkBuddy / DSH / Claude。
- 多显示器已验证：设置里可选主屏或任意 `NSScreen`，外接 1280×720 屏切换正常；全屏 Space 下顶部条和面板均可见（测试 App 验证）；真机刘海仍需 MacBook 验证。
- 覆盖菜单栏类工具通常无法上 App Store，建议 DMG/Homebrew 分发。

## 打包与签名

```bash
./package.sh                                  # ad-hoc DMG: Agent-Bar-<bundle version>.dmg
CODESIGN_IDENTITY="Developer ID Application: ..." ./package.sh   # Developer ID 签名
# 推荐：App Store Connect API Key（本机已配置）
CODESIGN_IDENTITY="..." CODESIGN_KEYCHAIN="$HOME/Library/Keychains/agentbar-signing.keychain-db" \
  NOTARIZE=1 NOTARY_KEY="$HOME/.appstoreconnect/private_keys/AuthKey_*.p8" \
  NOTARY_KEY_ID="..." NOTARY_ISSUER="..." ./package.sh

# 也支持 keychain profile / Apple ID + app-specific password
NOTARIZE=1 NOTARY_PROFILE="agentbar-notary" ./package.sh
```

- `package.sh` 会在 `/tmp` 里的 staging 目录重新签名再打 DMG，绕开 `~/Documents` 的 File Provider
  扩展属性问题，DMG 内的 App 签名是有效的。
- **Developer ID / 公证（已完成）**：已发布的 `Agent-Bar-0.3.4.dmg` 已用
  Developer ID 签名并公证（Accepted + stapled），
  Gatekeeper 显示 `source=Notarized Developer ID`。签名/公证流水线见
  [docs/SIGNING.md](docs/SIGNING.md)。源码版本升到 0.3.5 之后，新的 DMG 要等下一次 `v*` tag。
- **Homebrew**：`Casks/agent-bar.rb` 仍指向已发布的 0.3.4 DMG；`v*` tag 的 release workflow 会构建 DMG、
  用 `tools/update-cask.sh` 自动回写 cask 校验和并上传 release。公开仓库后：
  ```bash
  brew install --cask ./Casks/agent-bar.rb
  ```
- 本机直接在 `~/Documents` 运行 `Agent Bar.app` 时，File Provider 仍可能让本地签名校验/通知授权失败；
  分发/日常使用请安装 DMG 里的 App。
- `CODESIGN_KEYCHAIN` 指向专用签名钥匙串，避免 codesign 卡在登录钥匙串授权弹窗；密码文件在本机
  `~/.agentbar-signing-keychain-password`（0600），不提交仓库。

## 构建注意（2026-11-17 实测踩坑）

`build.sh` 里有两处非改不可的地方，否则 App 双击 / `open` 起不来：

1. **必须钉 deployment target**：`swiftc` 不带 `-target` 时继承 SDK 默认（本机编出 `minos 28.0`），
   而系统是 macOS 27.0 —— LaunchServices 会以 `-10825` 拒绝启动；直接 `./AgentBar` 却又能跑，极易误判。
   现在固定为 `-target arm64-apple-macosx14.0`。
2. **签名前必须清扩展属性**：bundle 带着 `com.apple.FinderInfo` 时 `codesign` 会报
   `resource fork, Finder information, or similar detritus not allowed` 而失败，旧版
   `--deep ... || true` 把错误吞掉了，结果 `_CodeSignature` 缺失、签名无效，连带通知授权也拿不到。
   现在先 `xattr -cr` 再 `codesign --force --sign -`，并校验签名。

修好这两处后：`open` 正常、日志里 `notifications authorized=true`。

## 目录

```
agent-bar/
├── Resources/agents/      确认稿 128×128 PNG 与 manifest.json
├── main.swift             入口（NSApplication 启动）
├── Support.swift          纯工具 / 格式化 / 布局 FramePreferenceKey
├── Models.swift           Agent 模型、DemoStore、SystemStatus、NetSpeed、UIModel
├── Views.swift            SwiftUI 顶部栏、面板、审批、设置
├── Chrome.swift           BarContainerView / IslandPanel
├── AppDelegate.swift      窗口、feed、审批、adapter 自启动
├── ReleaseUpdate.swift    GitHub Release 检查与通知授权状态
├── bridge/                DSH 桥（feed 只读 + 审批控制）+ translate + 外部 agent 合并
├── tools/                 agentbar-report.mjs、adapter 安装/本机 App watcher、鼠标/键盘自动化
├── tests/                 纯函数测试（./tests/run.sh）
├── docs/                  ROADMAP.md（交接与下一步）+ SIGNING.md（签名/公证排查）；公开树里没有产品截图
├── Casks/                 Homebrew cask
├── .github/workflows/     CI + tag release（DMG + cask checksum）
├── build.sh / start.sh / stop.sh / status.sh / package.sh
└── icon/                  App 图标
```

运行数据：`~/Library/Application Support/AgentBar/{bridge,agents}/`；审批审计：`.../bridge/audit.log`；
日志：`/tmp/agentbar.log`、`/tmp/agentbar-bridge.log`。

## 接下来

v0.3.4 有双向审批、一键接入、桌面 adapter、多显示器、用量趋势和签名公证。v0.3.5 加上 GitHub Release 更新检查和通知授权引导。v0.3.6 加上 Hermes 的本机 `state.db` 读取、把外部审批明确保持只读，并补了布局、用量累加、提问校验和 adapter 推断的测试。还没做的是：

- 新的 App 图标

## 许可与权利声明

**MIT** —— 见 [LICENSE](LICENSE)。版权人 `lzyxczw-cyber`。

第三方代码、与 CodeIsland 的关系、商标使用与 DSH 非官方集成方式的完整说明见
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)。要点：

- 仓库内**没有**第三方源码副本，Node 桥零 npm 依赖，Swift 侧无 SwiftPM 依赖；
- 与 CodeIsland（MIT）**无代码关系**，是独立实现；
- 界面中的 `Codex` / `Grok` / `WorkBuddy` / `DeepSeek Harness` / `Claude` 等名称与对应像素图标归各自权利人，
  本项目与其**无隶属或背书关系**。图标是示意性像素再创作（`Resources/agents/` 的 128×128 PNG，缺失时回退 `PixelSprite`）。对外分发前请按第三方声明第 5 节处理商标风险；
- 对 DSH 的接入是读取本机凭据自签 Cookie 的**非官方**方式，随 DSH 版本可能失效；审批答复依赖 `$events/result` 协议。 

