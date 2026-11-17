# 第三方代码与权利声明 / Third-Party Notices

本仓库（Agent Bar）的**全部源码由本项目作者独立实现**，不含任何第三方源码副本。
This repository contains no third-party source code. Everything under version
control is original work by the project author, except as noted below.

- 项目许可 / Project license: **MIT** — 见 [LICENSE](LICENSE)
- 版权人 / Copyright holder: `lzyxczw-cyber`

---

## 1. 第三方依赖：无

- Swift App：只用 Apple 系统框架（AppKit / SwiftUI / CoreWLAN / IOKit / UserNotifications），无 SwiftPM 依赖，无 CocoaPods/Carthage。
- Node 桥接（`bridge/`）：**零 npm 依赖**，只用 Node 内置模块（fs / net / http / crypto / child_process）。
- 仓库内没有 vendored 的第三方库。

## 2. 关于 `bridge/vendor/ws-mux.mjs`

这是**作者自己**的代码，不是第三方库。它是同一作者在另一个自有项目（DSH_iOS）里实现的零依赖 RFC6455 +
DSH Gateway mux 客户端，原样复制过来并保持同步。该文件归本项目作者所有，适用本仓库的 MIT 许可，
不附带任何外部版权声明。文件头的 NOTICE 已注明来源关系，并已去掉外部磁盘路径。

## 3. 与 CodeIsland 的关系

本项目在**概念上**参考了 macOS 刘海 / 菜单栏 AI agent 状态面板这一产品形态，同类产品包括 MIT 许可的
[wxtsky/CodeIsland](https://github.com/wxtsky/CodeIsland)。本项目与该项目的**代码没有任何关系，
也未经其授权或背书**。

为确认这一点，发布前对当时的 Swift 实现与 CodeIsland 全部 465 个 Swift 源文件按
『归一化后的 8 行滑窗』做过重合度计算，结果只有 **1 处重合片段**，即 Apple 官方文档给出的
`RegisterEventHotKey` / `InstallEventHandler` 标准调用样板——属于使用系统 API 的必然写法，
不具备可版权性。顶层类型名无实质重合（仅 `AppDelegate` / `AgentStatus` 这类通用命名）。

公开的 v0.3.3 树已经把界面拆开：`main.swift` 只负责启动，其余在 `Support.swift`、
`Models.swift`、`Views.swift`、`Chrome.swift`、`AppDelegate.swift`。上面的比对针对的是拆分前的实现，不是「现在仍有一份 3675 行的 `main.swift`」。

结论：**独立实现**。产品概念、信息架构、交互思路本身不受著作权保护。若后续从任何 MIT 项目
借鉴了具体代码，必须在该文件保留其原始版权声明，并在此处登记。

## 4. Apple SDK 样板

`RegisterEventHotKey`、`CWWiFiClient`、`NSStatusBar` 等调用形如 Apple 文档示例，
属于对公开 API 的常规使用，不是被复制的受版权保护的代码。

## 5. 商标 / 名称（重要）

本项目**不是**任何第三方产品的官方客户端，与其权利人**无隶属、合作或背书关系**：

- 界面中出现的 `Codex`、`Grok`、`WorkBuddy`、`DeepSeek Harness`、`Claude Code` 等名称归各自权利人所有，
  仅用于标识被监控的本地工具；
- `Resources/agents/` 里对应这些名称的 128×128 像素 PNG，以及 PNG 缺失时回退的 `Views.swift` 字符稿（`PixelSprite`），是对其品牌标识的**示意性再创作**，不是官方素材。
  涵盖 Codex、Grok、WorkBuddy、DeepSeek Harness、Claude，以及中性的 generic 与吉祥物。未知 agent 使用 generic，不再套用上述品牌图标。
  这是商标使用风险，不是版权风险。对外分发（尤其上架或商业使用）前建议二选一：
  1. 换成中性几何图标 + 文字标签；或
  2. 保留但明确标注『非官方』并附本声明，且不上架 Mac App Store。

## 6. 运行时数据不入库

`status.json`、`status.sock`、`agents/*.json`、日志、构建产物、开发期截图均由 [`.gitignore`](.gitignore) 排除。
这个公开树的 `docs/` 里**没有** `docs/*.png`。不要把带本机桌面、私人窗口、余额或凭据的截图提交进仓库。

## 7. DSH 集成声明

`bridge/` 通过读取本机 `$DSH_HOME/.credentials.yaml` 中的 browser-session 密钥，在内存中自签本机回环
地址的会话 Cookie，访问 DeepSeek Harness 的本地接口。这是一种**非官方、未公开的集成方式**，
随 DSH 版本变化可能失效；本项目与 DeepSeek Harness 官方无关。它不创建会话、不发送 prompt。
已经 pending 的审批，以及能校验的 `ask_user_question`，会通过 `$events/result` 回答。
使用者应知悉这一点。
