# Agent Bar · 交接与下一步

> 状态快照：**v0.4.1-dev**，2026-11-17，`main` 已含 CI、P0/P1/P2、桌面 adapter、拆分源文件和纯函数测试。
> 本机 `~/Documents` 的 File Provider 扩展属性会让本地 `codesign --verify` 失败（CI 不受影响）。
> 这份文档就是换台电脑继续用的入口：看完这一页就能接手，不用翻聊天记录。

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
  - 只支持 `approval/request`；`user-questions/request` 仍只读。
  - 每条决定追加到 `bridge/audit.log`（0600）：时间、approvalId、sessionId、tool、command、decision、result。
  - `--no-control` 可关闭整条控制通道。
- **已验收**：真实 Bash 提权审批 → 面板危险二次长按 → DSH 审批消失 → agent 继续执行 → 文件创建成功；
  拒绝路径同样验证通过。
- **仍需 review / 后续**：
  - 控制目录与 bridge 同用户信任域；token 可被同用户进程读取，不要跨用户共享 AppSupport。
  - 危险命令判定是启发式，不是完整安全边界。
  - 答复结果异步，UI 以审批卡片消失为准；失败看 `audit.log`。
  - 仍缺 `ask_user_question` 的答复支持（当前打开 DSH 回答）。
  - 需要补更系统的单测/集成测试（审批校验、token、审计、race）。

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
| 重拍截图 | ✅ settings（含预算/趋势）、panel-demo、bar-demo 已更新；其余截图在改版时按需重拍 |
| 签名 / 公证 | ✅ 已用 Developer ID 签名并通过 Apple 公证（Accepted + stapled）；签名凭据不入库，流程见 `docs/SIGNING.md` |
| 用量拆分 / 趋势 / 预算 | ✅ 每个 agent 今日 tokens 显示在面板行；设置里 7 天 sparkline；每日 token 预算超限后右栏变橙并当天提醒 |
| 外部 agent 一键接入 | ✅ Claude Code hooks 一键安装、Codex wrapper；✅ 本机桌面 adapter 已接 Codex（SQLite）、WorkBuddy（trace）、Grok Bot（persistence），App 自身和 `start.sh` 都会自动启动；支持同一 App 最多 3 个活跃会话；Hermes 仍为演示 |
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
- 零测试 → 纯函数测试 49 条（电池/天气/WWO 映射/token/网速/CJK/耗时）；CI 会跑 `./tests/run.sh`

**仍欠**：

| 项 | 说明 | 建议 |
|---|---|---|
| 测试覆盖仍偏纯函数 | 布局帧计算、用量累加、adapter 状态推断还没单测 | 抽纯函数后补；布局用固定 CGRect 输入断言输出 |
| `status.sh` 只匹配 bundle 路径 | 直接 `./AgentBar` 启动时会误报 not running | 改成按 `pgrep -f AgentBar` 匹配 |
| bridge 与 DSH 内部协议硬耦合 | 自签 Cookie、mux 协议都是逆向来的，DSH 升级即失效 | 加版本探针，检测不到就在栏上显示「协议不匹配」而不是静默变演示模式 |
| 面板 0.985 不透明度 | 亮背景下有 4/255 的透字 | 可接受；要纯净改 1.0 |

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

## 5. 最近完成（时间线）

| 日期 | 内容 |
|---|---|
| 11-17 | **P0 审批双向落地**：本机控制通道 + token + 审计 + 400ms 长按 + 危险命令二次确认；真实允许/拒绝验收通过 |
| 11-17 | **P1 完成**：天气城市设置、多显示器选择、全屏 Space 实测、+N 点击、网速空闲淡出 |
| 11-17 | **P2 大部分完成**：按 agent 用量/趋势/预算、Claude/Codex 一键 adapter、`package.sh` staging 签名 + DMG；Developer ID/公证待凭据 |
| 11-17 | **本机桌面 adapter**：Codex（ChatGPT SQLite）、WorkBuddy（trace）、Grok Bot（sand persistence）接入，start.sh 自动启动 |
| 11-17 | **adapter v2**：同一 App 最多 3 个活跃会话；脚本打包进 App，双击启动也会自动起 adapter；单例锁 + 退出清理 |
| 11-17 | **工程化**：`main.swift` 拆成 Support/Models/Views/Chrome/AppDelegate；49 个纯函数测试；Homebrew cask + release workflow + 可选公证 |
| 11-17 | **签名/公证完成**：Developer ID 证书通过网页端创建（绕过 Xcode/API 的 Account Holder 误报）；API Key 公证 Accepted + staple；Gatekeeper 已接受 |
| 11-17 | **adapter v3**：同一 App 多会话收成一个父行，选中展开子会话；↗/双击图标聚焦 App；设置里可看 adapter 日志、重启 watcher |
| 11-17 | **天气城市搜索**：设置里输入城市名，经 Open-Meteo geocoding 选候选，自动写回经纬度并刷新；常用城市保留 |
| 11-17 | 产权落地：MIT LICENSE + THIRD-PARTY-NOTICES（含与 CodeIsland 的逐行比对结论）+ 版权写入 bundle |
| 11-17 | 修两个启动致命 bug：deployment target、ad-hoc 签名；通知授权随之修好 |
| 11-17 | 天气双源、上下行网速、面板贴栏、系统阴影、`+N` 徽标 |
| 11-17 | 技术债：轮询 / 布局 / 用量口径；CI 上线 |
