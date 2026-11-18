# Agent Bar · 交接与下一步

> 状态快照：**v0.3.6**，2026-11-17。当前 `main` 已从公开初始提交 `9186deb` 起步，并合并 PR #1（协议不匹配、问题答复、文档对齐）。v0.3.5 加了 GitHub Release 更新检查和通知授权引导。v0.3.6 加了 Hermes 本机读取，并确认外部审批保持只读。v0.3.6 已打 tag，安装包是 `Agent-Bar-0.3.6.dmg`；没有单独的 v0.3.5 tag 或安装包，更新检查和通知授权引导随 v0.3.6 发布。
> bundle 版本见 `build.sh` 的 `CFBundleShortVersionString` / `CFBundleVersion`：`0.3.6`。
> 本机 `~/Documents` 的 File Provider 扩展属性会让本地 `codesign --verify` 失败（CI 不受影响）。
> 这份文档按当前公开树校对，不沿用已删除仓库里的 v0.4.1-dev 说法。看完这一页就能接手。

---

## 0. 新机器上手（5 步）

```bash
git clone https://github.com/lzyxczw-cyber/agent-bar.git && cd agent-bar
xcrun swiftc --version    # 需要 Xcode CLT，macOS >= 14
node --version            # 需要 >= 20
ls ~/.dsh/.credentials.yaml   # 需要本机装过 DSH 并登录过（bridge 用它自签只读 Cookie）
./build.sh && ./start.sh  # 编译 + 打包 + 启动
./status.sh               # 期望看到 connected: True
```

日志：`/tmp/agentbar.log`、`/tmp/agentbar-bridge.log`；
运行数据：`~/Library/Application Support/AgentBar/{bridge,agents}/`（**机器本地，不随仓库走**，`start.sh` 每次重新同步）。

**不要**绕过 `build.sh` 里的两处（见 §3）：`-target arm64-apple-macosx14.0` 和签名前的 `xattr -cr`。

---

## 1. 待办（按优先级）

### P0 · 审批双向（已完成 2026-11-17）

- **现状**：面板内长按 0.4s 允许/拒绝；危险操作（`danger-full-access` 提权、`rm -rf`、`sudo` 等）
  第一次长按只进入「再次长按允许」确认。
- **实现**：
  - App 写 `~/Library/Application Support/AgentBar/bridge/control/request-*.json`（目录 0700、
    token 0600），bridge 校验 token / pending approval id / session 后调用
    `$events/result`（`events.answer`）。
  - `approval/request` 回答 `allowed-once` / `rejected`。
  - 能校验的 `user-questions/request` 也走同一通道：`answered` 的 value 是 `{answers:[{id, selected, custom?}]}`，`selected` 是选项 label；`cancelled` 发送 `UserQuestionError / ASK_CANCELLED`。未知 intent、重复 label 等无法校验的题保持只读。
  - 每条决定追加到 `bridge/audit.log`（0600）：时间、approvalId、sessionId、tool、command、decision、result。
  - `--no-control` 可关闭整条控制通道。
- **已验收**：真实 Bash 提权审批 → 面板危险二次长按 → DSH 审批消失 → agent 继续执行 → 文件创建成功；
  拒绝路径同样验证通过。
- **仍需 review / 后续**：
  - 控制目录与 bridge 同用户信任域；token 可被同用户进程读取，不要跨用户共享 AppSupport。
  - 危险命令判定是启发式，不是完整安全边界。
  - 答复结果异步，UI 以审批卡片消失为准；失败看 `audit.log`。
  - 可校验的 `ask_user_question` 已能在面板回答；无法校验的题型仍打开 DSH。
  - 提问答案校验、布局帧、用量增量和 adapter 推断已有确定性单测。控制通道的 token、审计和竞态还没有集成测试。

### P1 · 小项（已完成 2026-11-17）

| # | 事项 | 结果 |
|---|---|---|
| 1.1 | 天气位置设置 | ✅ 城市名搜索（Open-Meteo geocoding，中文候选）+ 常用城市快捷菜单；选择后立即刷新，不再需要手填经纬度 |
| 1.2 | 多显示器 | ✅ 设置里可选主屏或任意 `NSScreen`；实测从 P32A6V-PRO 切到外接 Wokyis（1280×720），顶部条与面板跟随；屏幕变化会重新应用 geometry |
| 1.3 | 全屏 Space | ✅ 用独立全屏测试 App 验证：顶部条可见，热键呼出的面板也可见（`.fullScreenAuxiliary` 已同时加到 bar + panel） |
| 1.4 | `+N` 点击 | ✅ 注册 overflow 命中区，点击日志 `overflow -> panel` 并展开面板；hover 有高亮 |
| 1.5 | 网速空闲淡出 | ✅ 30s 无流量自动淡出并从右栏收掉宽度，有流量重新出现 |

### P2 · 发布相关（2026-11-17，大部分完成）

| 事项 | 结果 |
|---|---|
| 重拍截图 | 公开树的 `docs/` 里没有 `docs/*.png`。带本机桌面的截图不入库；这台环境不能运行 macOS App，所以没有补产品图 |
| 签名 / 公证 | ✅ 已用 Developer ID 签名并通过 Apple 公证（Accepted + stapled）；签名凭据不入库，流程见 `docs/SIGNING.md` |
| 用量拆分 / 趋势 / 预算 | ✅ 每个 agent 今日 tokens 显示在面板行；设置里 7 天 sparkline；每日 token 预算超限后右栏变橙并当天提醒 |
| 外部 agent 一键接入 | ✅ Claude Code hooks、Codex wrapper；✅ 桌面 adapter：Codex（SQLite）、WorkBuddy（trace）、Grok Bot（persistence）、Hermes（`state.db`，没有库或进程时仍用演示）。同一 App 最多 3 个活跃会话。外部审批只读 |
| Homebrew / 发布 | ✅ `Casks/agent-bar.rb` + `v*` tag release workflow，上传 `Agent-Bar-<version>.dmg`；✅ DMG 已公证，cask 校验和已同步 |

---

## 2. 技术债

**已还（2026-11-17）**：

- 20Hz 主线程轮询 → `mouseMoved` 事件驱动 + 1Hz 兜底（空闲 CPU 8.3% → 2.5%）
- 布局双份计算 → SwiftUI `PreferenceKey` 单一数据源（点哪和画哪不会再漂移）
- 「今日用量」口径 → 当日增量 + 基线持久化（`bridge/usage-state.json`）
- 天气单源 → open-meteo + wttr.in 双源 + 退避重试 + 全链路日志
- 阴影被窗口裁切 → 改用系统窗口阴影
- `main.swift` 3675 行单文件 → 拆成 Support / Models / Views / Chrome / AppDelegate + 5 行入口，多文件 `swiftc`
- 零测试 → `tests/main.swift` 的 Swift `check`，外加 `node --test tests/bridge-logic.test.mjs tests/adapter-logic.test.mjs`。CI 跑 `./tests/run.sh`

**仍欠**：

| 项 | 说明 | 建议 |
|---|---|---|
| 面板 0.985 不透明度 | 亮背景下有 4/255 的透字 | 可接受；要纯净改 1.0 |
| 新 App 图标 | 确认稿还没替换现有 PNG | 确认稿到达后再换，不要改 `Resources/agents/` 里已经确认的帧 |

已还掉的两项：`status.sh` 用 `pgrep -x AgentBar` / `pgrep -x agentbar` 识别进程，不再只匹配 bundle 路径；`session/list` 探针失败时 `dsh.protocol` 为 `mismatch`，栏上显示「协议不匹配」，不把演示数据当成实时数据。

---

## 3. 已知坑（踩过的，别再踩）

1. **`minos` 比系统新 → `open` 报 `-10825`**：`swiftc` 不带 `-target` 会继承 SDK 默认（本机编出 28.0），而系统是 27.0。直接用 `./AgentBar` 又能跑，极易误判。已固定在 `build.sh`。
2. **`com.apple.FinderInfo` 扩展属性让 `codesign` 静默失败**：报 `resource fork, Finder information, or similar detritus not allowed`，旧版 `--deep ... || true` 把错误吞了 → `_CodeSignature` 缺失 → LaunchServices 拒绝启动 **且** 通知授权失败。现在先 `xattr -cr`。
3. **同一个 bundle id 存在多份副本**会让 `open` 失败。调试时用 `lsregister -dump | grep com.lzy.agentbar` 查，`lsregister -u <path>` 清。
4. **不要在 `~/Documents` 下放两份工作副本**：这台机器上 `~/Documents` 走 File Provider，git 写 `.git/index.lock` 会偶发超时。
5. **DSH 的 `tokenUsage` 是投影值、按回合刷新**，不是实时。所以「今日用量」只能是保守下界，别指望它逐秒跳。
6. **天气码有两套**：open-meteo 用 WMO，wttr.in 用 WWO，混用会让图标永远是一朵云（已加 `wmoCode(fromWWO:)`）。
7. **`api.open-meteo.com` 在这台机器上间歇性 20s 超时**，不是代码问题；所以有 wttr.in 兜底和退避。

---

## 4. 提交前自检

```bash
./build.sh
./tests/run.sh
codesign --verify --strict "Agent Bar.app"
otool -l agentbar | grep -A3 LC_BUILD_VERSION   # 期望 minos 14.0
```

这些 CI 会替你做（`.github/workflows/build.yml`）：编译、纯函数测试、校验签名、校验 `minos` 没有回退。

---

## 4b. v0.3.5 已完成

- **自动更新**：只读 GitHub `releases/latest`，和 bundle 短版本比较。有更新时栏上和面板提示，用户自己打开官方 DMG 或发布页。没有 Sparkle，没有新的 Homebrew tap，不会覆盖正在运行的 App。失败只出现在设置里。忽略针对单个版本，稍后是 24 小时。自动检查间隔 6 小时。
- **通知授权引导**：未决定时面板里一张卡片，用户点了才请求系统授权；已拒绝时引导到系统设置。两种卡片都可以关掉，之后不再反复出现。设置页保留入口。未授权时继续只播放提示音。

## 4c. v0.3.6 已完成

- **外部审批**：Codex、Claude Code、WorkBuddy、Grok Bot、Hermes 和任意心跳上报都保持只读，面板说明原因，不放一个不会生效的「允许」按钮。Codex 的真实协议是当前 app-server 连接上的 `item/commandExecution/requestApproval`；Claude 的决定只能由当次 `PreToolUse` hook 输出。这两边 Agent Bar 都不是那个应答方。WorkBuddy trace、Grok blob、Hermes `state.db` 都没有带 token 和 pending id 的写接口。
- **Hermes**：`hermes` 进程或 Hermes.app 在跑，并且 `HERMES_HOME/state.db`（默认 `~/.hermes/state.db`）能只读打开时，按最近 90 秒的消息推断最多 3 个会话。库不存在、进程不在、或表结构对不上时不编造数据，演示模式仍用原来的 Hermes 行。不写数据库，不把累计 token 显示成今日用量。
- **测试**：提问答案的多选顺序、未知选项、超长自定义；`railPillWidth` / `predictedRailFrames`；`applyUsageTick` 的首次基线、增量和跨日；Hermes 会话推断和每个 App 最多 3 个子会话。

## 5. 最近完成（时间线）

| 日期 | 内容 |
|---|---|
| 11-17 | **v0.3.6**：Hermes 只读 `state.db`；外部审批保持只读并写明原因；布局、用量、提问和 adapter 推断测试 |
| 11-17 | **v0.3.5**：GitHub Release 更新检查（不自动安装）+ 通知授权引导 |
| 11-17 | **P0 审批双向落地**：本机控制通道 + token + 审计 + 400ms 长按 + 危险命令二次确认；真实允许/拒绝验收通过 |
| 11-17 | **P1 完成**：天气城市设置、多显示器选择、全屏 Space 实测、+N 点击、网速空闲淡出 |
| 11-17 | **P2 大部分完成**：按 agent 用量/趋势/预算、Claude/Codex 一键 adapter、`package.sh` staging 签名 + DMG；Developer ID/公证待凭据 |
| 11-17 | **本机桌面 adapter**：Codex（ChatGPT SQLite）、WorkBuddy（trace）、Grok Bot（sand persistence）接入，start.sh 自动启动 |
| 11-17 | **adapter v2**：同一 App 最多 3 个活跃会话；脚本打包进 App，双击启动也会自动起 adapter；单例锁 + 退出清理 |
| 11-17 | **工程化**：Swift 源文件拆成 Support/Models/Views/Chrome/AppDelegate，`main.swift` 只负责启动；纯函数测试；Homebrew cask + release workflow + 可选公证 |
| 11-17 | **签名/公证完成**：Developer ID 证书通过网页端创建（绕过 Xcode/API 的 Account Holder 误报）；API Key 公证 Accepted + staple；Gatekeeper 已接受 |
| 11-17 | **adapter v3**：同一 App 多会话收成一个父行，选中展开子会话；↗/双击图标聚焦 App；设置里可看 adapter 日志、重启 watcher |
| 11-17 | **天气城市搜索**：设置里输入城市名，经 Open-Meteo geocoding 选候选，自动写回经纬度并刷新；常用城市保留 |
| 11-17 | 产权落地：MIT LICENSE + THIRD-PARTY-NOTICES（含与 CodeIsland 的逐行比对结论）+ 版权写入 bundle |
| 11-17 | 修两个启动致命 bug：deployment target、ad-hoc 签名；通知授权随之修好 |
| 11-17 | 天气双源、上下行网速、面板贴栏、系统阴影、`+N` 徽标 |
| 11-17 | 技术债：轮询 / 布局 / 用量口径；CI 上线 |
