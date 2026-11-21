import AppKit
import SwiftUI
import QuartzCore
import Carbon
import Combine
import IOKit.ps
import CoreWLAN
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let store = DemoStore()
    let geom = Geometry()
    let ui = UIModel()
    let system = SystemStatus()
    let net = NetSpeed()
    let updates = UpdateCenter()
    let notificationAuth = NotificationAuthCenter()

    private var barPanel: NSPanel?
    private var panel: NSPanel?
    private var pollTimer: Timer?
    private var rotateTimer: Timer?
    private var feedTimer: Timer?
    private var feedURL: URL?
    private var lastFeedSuccess = Date.distantPast
    /// Last time status.json decoded and was fresh. The bridge rewrites it every
    /// 5 s even while DSH is unreachable, so this says "bridge is alive", not
    /// "DSH is connected".
    private var lastFeedRead = Date.distantPast
    private var lastDecodeErrorLog = Date.distantPast
    private var bridgeProcess: Process?
    private var bridgeStartedAt = Date.distantPast
    private var bridgeRestartDelay: TimeInterval = 2
    private var isTerminating = false
    private var bridgeLogHandle: FileHandle?
    private var bridgeWatchdog: Timer?
    private var appAdapterProcess: Process?
    private var isYielding = false
    private var isExpanded = false
    private var forceYield = false
    private var lastUserInteraction = Date.distantPast
    private var autoHideMode = false
    private var lastHeartbeat = Date()
    private var lastAutoHideCheck = Date.distantPast
    private var lastRailDumpAt = Date.distantPast
    private var mouseMoveGlobal: Any?
    private var mouseMoveLocal: Any?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyRef2: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var panelKeyMonitor: Any?
    private var workspaceObserver: NSObjectProtocol?
    private var lastNotifiedWaiting: Set<String> = []
    private var lastClaudeApprovalID: String?
    private var lastClaudeHeartbeatAt: Date?
    private var lastNotifiedFinished: Set<String> = []
    private var previousStatuses: [String: AgentStatus] = [:]
    private var liveSeenOnce = false
    private var didSurfaceNotificationGuide = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        autoHideMode = UserDefaults.standard.bool(forKey: "_HIHideMenuBar")
        buildBar()
        buildPanel()
        startPolling()
        installQuitHotKey()
        startWatchdog()

        if let waiting = store.agents.first(where: { $0.status == .waiting }) {
            ui.selectedID = waiting.id
        } else {
            ui.selectedID = store.agents.first?.id
        }
        startAgentRotation()

        syncBundledBridgeToAppSupport()
        store.claudeApprovalDirectory = appSupportClaudeApprovalDir()
        feedURL = resolveFeedURL()
        if let feedURL = feedURL {
            dlog("[agentbar] live feed path: \(feedURL.path)")
        }
        startFeedPolling()
        scheduleBridgeAutostart()
        scheduleAppAdaptersAutostart()
        startBridgeWatchdog()
        installPanelBehavior()
        setupNotifications()
        updates.start()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(forName: .agentBarRestartBridge, object: nil, queue: .main) { [weak self] _ in
            self?.restartBridgeForSettingsChange()
        }

        dlog("[agentbar] launched. autoHideMode=\(autoHideMode) screen=\(screenDescription())")
        dlog("[agentbar] controls: click top bar = expand/collapse, push cursor to top edge = yield to system menu bar, ⌃⌥⌘Q = quit")

        let args = CommandLine.arguments

        if args.contains("--yield") {
            // debug/demo: hold the "system menu bar visible" state
            forceYield = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.setYielding(true)
            }
        } else if args.contains("--test-notification") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.postNotification(title: "测试通知 · Agent Bar", body: "审批提醒 / 完成提醒样式预览", agentID: "test")
            }
        } else if args.contains("--expanded") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.setExpanded(true)
            }
        } else if !args.contains("--quiet") {
            // soft onboarding: open the panel briefly, collapse unless the user interacts
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                self?.setExpanded(true)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 11.0) { [weak self] in
                guard let self = self else { return }
                if self.isExpanded && Date().timeIntervalSince(self.lastUserInteraction) > 9 {
                    self.setExpanded(false)
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        isTerminating = true
        pollTimer?.invalidate()
        feedTimer?.invalidate()
        bridgeWatchdog?.invalidate()
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        if let ref = hotKeyRef2 { UnregisterEventHotKey(ref) }
        if let h = hotKeyHandler { RemoveEventHandler(h) }
        if let monitor = panelKeyMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = mouseMoveGlobal { NSEvent.removeMonitor(monitor) }
        if let monitor = mouseMoveLocal { NSEvent.removeMonitor(monitor) }
        if let observer = workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        if let bridge = bridgeProcess, bridge.isRunning {
            bridge.terminate()
        }
        if let adapter = appAdapterProcess, adapter.isRunning {
            adapter.terminate()
        }
    }

    // MARK: Screens & geometry

    private func primaryScreen() -> NSScreen? {
        let saved = UserDefaults.standard.string(forKey: "AgentBarScreenName") ?? ""
        if !saved.isEmpty, let match = NSScreen.screens.first(where: { $0.localizedName == saved }) {
            return match
        }
        return NSScreen.screens.first ?? NSScreen.main
    }

    /// Re-apply geometry after the user picks another display or the screen set changes.
    private func applyScreenSelection() {
        computeGeometry()
        if let bar = barPanel, let shown = barFrame() {
            bar.setFrame(isYielding ? (hiddenBarFrame() ?? shown) : shown, display: true)
            bar.contentView?.layoutSubtreeIfNeeded()
        }
        if isExpanded, let panel = panel, let frame = panelFrame() {
            panel.setFrame(frame, display: true)
        }
        dlog("[agentbar] screen selected: \(screenDescription())")
    }

    private func screenDescription() -> String {
        guard let s = primaryScreen() else { return "none" }
        return "frame=\(s.frame) safeTop=\(s.safeAreaInsets.top) auxL=\(String(describing: s.auxiliaryTopLeftArea)) auxR=\(String(describing: s.auxiliaryTopRightArea))"
    }

    private func barLevel(autoHide: Bool) -> NSWindow.Level {
        if autoHide {
            // real mode: sit just below the (auto-hidden) system menu bar
            return NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1)
        } else {
            // demo mode: cover the always-visible menu bar so the top strip looks "freed"
            return NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        }
    }

    private func computeGeometry() {
        guard let screen = primaryScreen() else { return }
        let menuInset = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
        let safeTop = screen.safeAreaInsets.top
        let h = max(menuInset, safeTop, 30)
        let notchWidth: CGFloat
        if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            notchWidth = max(120, screen.frame.width - l.width - r.width)
        } else {
            // notch-less display (e.g. external monitor): simulate a proportional camera housing
            notchWidth = min(340, max(200, (screen.frame.width * 0.118).rounded()))
        }
        geom.barHeight = h
        geom.notchWidth = notchWidth
        geom.hasNotch = (screen.auxiliaryTopLeftArea != nil)
    }

    private func barFrame() -> NSRect? {
        guard let screen = primaryScreen() else { return nil }
        let h = geom.barHeight
        return NSRect(x: screen.frame.minX, y: screen.frame.maxY - h, width: screen.frame.width, height: h)
    }

    private func hiddenBarFrame() -> NSRect? {
        guard let screen = primaryScreen() else { return nil }
        let h = geom.barHeight
        return NSRect(x: screen.frame.minX, y: screen.frame.maxY + 8, width: screen.frame.width, height: h)
    }

    private func panelSize() -> NSSize {
        // Exactly the card: the window shadow is composited outside this rect, so
        // no transparent margin is needed (and none of it swallows clicks).
        return NSSize(width: 560, height: 500)
    }

    private func panelFrame() -> NSRect? {
        guard let screen = primaryScreen() else { return nil }
        let size = panelSize()
        let x = screen.frame.midX - size.width / 2
        // 1pt below the bar: the visible card top is the window top here, so the
        // panel reads as unfolding out of the notch instead of floating under it.
        let y = screen.frame.maxY - geom.barHeight - 1 - size.height
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    // MARK: Build UI

    private func buildBar() {
        computeGeometry()
        guard let frame = barFrame() else { return }

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = barLevel(autoHide: autoHideMode)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.animationBehavior = .none

        let container = BarContainerView(frame: NSRect(origin: .zero, size: frame.size))
        container.onClick = { [weak self] point, clickCount in self?.handleBarClick(at: point, clickCount: clickCount) }
        container.onRightClick = { [weak self] event in self?.showBarContextMenu(event) }
        let host = NSHostingView(rootView: IconAnimationGate(ui: ui) {
            BarView(store: store, geom: geom, ui: ui, sys: system, net: net, updates: updates)
        })
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        panel.contentView = container

        panel.orderFrontRegardless()
        barPanel = panel
        dlog("[agentbar] bar frame=\(frame) level=\(panel.level.rawValue) barHeight=\(geom.barHeight) notchWidth=\(geom.notchWidth)")
    }

    private func buildPanel() {
        let size = panelSize()
        let panel = IslandPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.onEscape = { [weak self] in self?.setExpanded(false) }
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: barLevel(autoHide: autoHideMode).rawValue + 1)
        // .fullScreenAuxiliary lets the panel appear over a full-screen Space too.
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.animationBehavior = .none
        panel.alphaValue = 0

        let host = NSHostingView(rootView: IconAnimationGate(ui: ui) {
            PanelView(
                store: store,
                ui: ui,
                realMode: autoHideMode,
                onSelect: { [weak self] id in
                    self?.ui.select(id)
                    dlog("[agentbar] panel: select \(id)")
                },
                onClose: { [weak self] in self?.setExpanded(false) },
                onQuit: { NSApp.terminate(nil) },
                onWeatherChanged: { [weak self] in self?.system.refreshWeather() },
                onScreenChanged: { [weak self] in self?.applyScreenSelection() },
                onOpenApp: { [weak self] bundle in self?.openExternalApp(bundle) },
                onOpenAdapterLog: { [weak self] in self?.openAdapterLog() },
                onRestartAdapters: { [weak self] in self?.restartAppAdapters() },
                updates: updates,
                notificationAuth: notificationAuth
            )
        })
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host

        self.panel = panel
    }

    // MARK: Bar clicks & agent carousel

    /// Single source of truth for hit testing. SwiftUI publishes the real rail
    /// frames through RailFramePreferenceKey into ui.railLayout, so AppKit never
    /// recomputes the layout and can never drift from what is actually drawn.
    private func railFrames() -> [String: CGRect] {
        ui.railLayout.frames
    }

    private func handleBarClick(at point: NSPoint, clickCount: Int = 1) {
        // Clicks are ignored while the rail is animating (avoids hitting the wrong agent).
        guard Date() >= ui.animationLockUntil else {
            dlog("[agentbar] bar click ignored (rail animating)")
            return
        }
        let local = CGPoint(x: point.x - railLeading, y: geom.barHeight - point.y)
        let frames = railFrames()
        if CommandLine.arguments.contains("--debug-layout") {
            let summary = frames.sorted { $0.value.minX < $1.value.minX }
                .map { "\($0.key)=\(Int($0.value.minX))-\(Int($0.value.maxX))" }
                .joined(separator: " | ")
            dlog("[rail] \(summary)")
        }
        for (key, rect) in frames where rect.contains(local) {
            if key == "overflow" {
                dlog("[agentbar] bar click: overflow -> panel")
                toggleExpanded()
                return
            }
            if key.hasPrefix("pill:") {
                dlog("[agentbar] bar click: selected pill -> panel")
                toggleExpanded()
                return
            }
            if key.hasPrefix("icon:") {
                let id = String(key.dropFirst(5))
                if clickCount >= 2, let agent = store.agents.first(where: { $0.id == id }), let bundle = agent.appBundleID {
                    dlog("[agentbar] bar double-click: open (agent.name) ((bundle))")
                    openExternalApp(bundle)
                    return
                }
                if id == ui.selectedID {
                    dlog("[agentbar] bar click: selected icon -> panel")
                    toggleExpanded()
                } else {
                    dlog("[agentbar] bar click: select \(id)")
                    ui.select(id)
                }
                return
            }
        }
        dlog("[agentbar] bar click: background -> panel")
        toggleExpanded()
    }

    private func startAgentRotation() {
        let timer = Timer(timeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.rotateAgent()
        }
        RunLoop.main.add(timer, forMode: .common)
        rotateTimer = timer
    }

    private func rotateAgent() {
        guard !isExpanded else { return }
        guard Date().timeIntervalSince(ui.lastManualInteraction) > 45.0 else { return }

        // Carousel only cycles agents that currently have active work (running or waiting).
        let visible = Array(store.agents.prefix(5))
        let active = visible.filter { $0.status == .running || $0.status == .waiting }
        guard !active.isEmpty else { return }
        guard active.count > 1 else {
            if ui.selectedID != active[0].id {
                ui.animationLockUntil = Date().addingTimeInterval(0.55)
                ui.selectedID = active[0].id
            }
            return
        }
        if let current = ui.selectedID, let index = active.firstIndex(where: { $0.id == current }) {
            let next = active[(index + 1) % active.count]
            ui.animationLockUntil = Date().addingTimeInterval(0.55)
            ui.selectedID = next.id
            dlog("[agentbar] rotate: \(next.name)")
        } else {
            ui.animationLockUntil = Date().addingTimeInterval(0.55)
            ui.selectedID = active[0].id
        }
    }

    // MARK: Live feed (DSH bridge status.json)

    private func appSupportBridgeDir() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent("AgentBar/bridge", isDirectory: true)
    }

    private func appSupportClaudeApprovalDir() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent("AgentBar/claude-approvals", isDirectory: true)
    }

    private func resolveFeedURL() -> URL? {
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--feed"), idx + 1 < args.count {
            return URL(fileURLWithPath: args[idx + 1])
        }
        // Runtime files live in Application Support so the app never needs
        // macOS Documents-folder permission. Launch syncs the bundled bridge
        // here; start.sh syncs the same directory from a repo checkout.
        if let dir = appSupportBridgeDir() {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return dir.appendingPathComponent("status.json")
            }
        }
        let bundle = Bundle.main.bundleURL
        let dir: URL
        if bundle.pathExtension == "app" {
            dir = bundle.deletingLastPathComponent()
        } else if let exe = Bundle.main.executableURL {
            dir = exe.deletingLastPathComponent()
        } else {
            return nil
        }
        return dir.appendingPathComponent("bridge/status.json")
    }

    private func startFeedPolling() {
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.loadLiveFeed()
            // Approvals are read from local files, so they must survive the
            // feed replacing store.agents and keep working without the bridge.
            self?.syncClaudeApprovals()
        }
        RunLoop.main.add(timer, forMode: .common)
        feedTimer = timer
    }

    private func loadLiveFeed() {
        guard let url = feedURL, let data = try? Data(contentsOf: url) else { return }
        let feed: LiveFeed
        do {
            feed = try JSONDecoder().decode(LiveFeed.self, from: data)
        } catch {
            // A silent decode failure used to freeze the bar on stale data with
            // no clue in the log. Keep it throttled so a bad bridge build does
            // not flood the log at 1 Hz.
            if Date().timeIntervalSince(lastDecodeErrorLog) > 60 {
                lastDecodeErrorLog = Date()
                dlog("[agentbar] status.json decode failed: \(error)")
            }
            return
        }
        store.controlDirectory = url.deletingLastPathComponent().appendingPathComponent("control", isDirectory: true)
        let nowMs = Date().timeIntervalSince1970 * 1000.0
        let ageMs = nowMs - (feed.ts ?? 0)
        let fresh = ageMs >= 0 && ageMs < 15000
        // Track the snapshot's own timestamp, not the read time: the feed stays
        // "fresh" for 15 s after the bridge dies, and that would delay recovery.
        if fresh { lastFeedRead = Date(timeIntervalSince1970: (feed.ts ?? nowMs) / 1000.0) }
        let connected = feed.dsh?.connected == true
        let bridgeAlive: Bool = {
            guard let pid = feed.bridge?.pid else { return false }
            return kill(pid_t(pid), 0) == 0
        }()
        let presentation = barFeedMode(
            protocolStatus: feed.dsh?.protocolStatus,
            isLive: store.isLive,
            bridgeFresh: fresh,
            bridgeAlive: bridgeAlive,
            bridgeNote: store.bridgeNote
        )
        if presentation == .protocolMismatch {
            let external = (feed.agents ?? []).filter { $0.external == true }.map { mapLiveAgent($0) }
            let note = feed.dsh?.protocolError ?? feed.dsh?.error ?? "DSH 的 session/list 与当前桥不一致"
            store.showProtocolMismatch(note, agents: external)
            return
        }
        if store.feedMode == .protocolMismatch {
            store.leaveProtocolMismatch()
        }

        if fresh && connected && bridgeAlive, let liveAgents = feed.agents, !liveAgents.isEmpty {
            let mapped = liveAgents.map { mapLiveAgent($0) }
            store.applyLiveFeed(mapped, total: feed.counts?.agents ?? mapped.count)
            if mapped.allSatisfy({ $0.status != .waiting }) {
                store.approvalNotice = nil
            }
            if let dshURL = feed.dsh?.url, !dshURL.isEmpty { store.dshURL = dshURL }
            store.usageTokensToday = feed.usage?.tokensToday
            store.usageHistory = (feed.usage?.history ?? [])
                .compactMap { $0.tokens }
                .filter { $0 > 0 }
            if let account = feed.account, account.status == "ready" {
                store.balanceText = formatMoney(currency: account.currency, balance: account.balance) ?? "--"
            } else {
                store.balanceText = "--"
            }
            handleAgentTransitions(mapped)
            checkBudgetAlert(tokens: feed.usage?.tokensToday)
            syncSelection(with: mapped)
            lastFeedSuccess = Date()
        } else if store.isLive {
            if !bridgeAlive {
                store.markBridgeOffline("bridge 已退出")
            } else if !fresh {
                store.markBridgeOffline("数据过期 \(Int(max(0, ageMs) / 1000))s")
            } else if !connected {
                store.markBridgeOffline("bridge 未连接")
            } else {
                store.markBridgeOffline("暂无活跃任务")
            }
        }
    }

    // MARK: Claude approval handshake (PermissionRequest hook)

    private func syncClaudeApprovals() {
        guard let dir = store.claudeApprovalDirectory else { return }
        let fm = FileManager.default
        let pendingDir = dir.appendingPathComponent("pending", isDirectory: true)
        let decisionsDir = dir.appendingPathComponent("decisions", isDirectory: true)
        let now = Date()

        touchClaudeHeartbeat(dir: dir)
        pruneClaudeFiles(pendingDir, olderThan: 120, now: now)
        pruneClaudeFiles(decisionsDir, olderThan: 600, now: now)

        let loaded: [ClaudePendingApproval] = (try? fm.contentsOfDirectory(at: pendingDir, includingPropertiesForKeys: nil))?
            .compactMap { url in
                guard url.pathExtension == "json",
                      let data = try? Data(contentsOf: url),
                      let approval = parseClaudePendingApproval(data) else { return nil }
                let age = now.timeIntervalSince1970 - approval.createdAt / 1000.0
                return age < 120 ? approval : nil
            } ?? []

        if let picked = selectClaudePendingApproval(loaded) {
            let rowID = applyClaudeApproval(picked.approval, extra: picked.extra)
            announceClaudeApproval(picked.approval, rowID: rowID)
        } else {
            lastClaudeApprovalID = nil
            clearClaudeApproval()
        }
    }

    private func announceClaudeApproval(_ approval: ClaudePendingApproval, rowID: String) {
        let plan = claudeApprovalAnnouncement(
            id: approval.id,
            lastAnnounced: lastClaudeApprovalID,
            rowID: rowID,
            selectedID: ui.selectedID
        )
        guard plan.announce else { return }
        lastClaudeApprovalID = approval.id
        // Claude approvals bypass handleAgentTransitions (that path needs a live
        // DSH feed and runs before the merge), so notify here.
        if notificationsEnabled() {
            postNotification(
                title: "等待审批 · Claude Code",
                body: approval.command,
                agentID: rowID
            )
        }
        guard plan.select else { return }
        ui.animationLockUntil = Date().addingTimeInterval(0.45)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.80)) {
            ui.selectedID = rowID
        }
    }

    private func touchClaudeHeartbeat(dir: URL) {
        // The hook treats 10 s as stale; writing four times per second was
        // unnecessary disk metadata churn. 5 s keeps a safe margin.
        if let last = lastClaudeHeartbeatAt, Date().timeIntervalSince(last) < 4 { return }
        lastClaudeHeartbeatAt = Date()
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = dir.appendingPathComponent("heartbeat")
        if fm.fileExists(atPath: url.path) {
            try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        } else {
            fm.createFile(atPath: url.path, contents: Data(), attributes: [.posixPermissions: 0o600])
        }
    }

    private func pruneClaudeFiles(_ dir: URL, olderThan seconds: TimeInterval, now: Date) {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        for url in urls {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? now
            if now.timeIntervalSince(modified) > seconds {
                try? fm.removeItem(at: url)
            }
        }
    }

    private func applyClaudeApproval(_ approval: ClaudePendingApproval, extra: Int) -> String {
        let project = (approval.cwd as NSString).lastPathComponent
        let displayProject = project.isEmpty ? "Claude Code" : project
        let note = claudeApprovalNotice(project: displayProject, extra: extra)
        let approvalId = claudeApprovalId(approval.id)

        if let index = store.agents.firstIndex(where: { $0.id == "claude" }) {
            // Mutate only on a real change: assigning every tick published
            // objectWillChange and re-laid out the whole bar every second.
            let current = store.agents[index]
            if current.status != .waiting || current.approvalId != approvalId ||
                current.approvalCommand != approval.command || current.note != note ||
                !current.isClaudeApproval {
                store.agents[index].status = .waiting
                store.agents[index].approvalId = approvalId
                store.agents[index].approvalCommand = approval.command
                store.agents[index].note = note
                store.agents[index].isClaudeApproval = true
            }
            return "claude"
        }
        if let index = store.agents.firstIndex(where: { $0.id == "claude-approval" }) {
            let current = store.agents[index]
            if current.project != displayProject || current.approvalId != approvalId ||
                current.approvalCommand != approval.command || current.note != note ||
                !current.isClaudeApproval {
                store.agents[index].project = displayProject
                store.agents[index].approvalId = approvalId
                store.agents[index].approvalCommand = approval.command
                store.agents[index].note = note
                store.agents[index].isClaudeApproval = true
            }
            return "claude-approval"
        }
        store.agents.append(Agent(
            id: "claude-approval",
            name: "Claude Code",
            project: displayProject,
            tool: "Bash",
            status: .waiting,
            startedAt: Date(),
            approvalCommand: approval.command,
            approvalId: approvalId,
            note: note,
            isExternal: true,
            isClaudeApproval: true
        ))
        return "claude-approval"
    }

    private func clearClaudeApproval() {
        if let index = store.agents.firstIndex(where: { $0.id == "claude-approval" }) {
            store.agents.remove(at: index)
        }
        if let index = store.agents.firstIndex(where: { $0.id == "claude" }),
           claudeApprovalCanAnswer(store.agents[index].approvalId) {
            store.agents[index].approvalId = nil
            store.agents[index].approvalCommand = nil
            store.agents[index].note = nil
            store.agents[index].isClaudeApproval = false
            if store.agents[index].status == .waiting {
                store.agents[index].status = .running
            }
        }
    }

    private func syncSelection(with agents: [Agent]) {
        guard !agents.isEmpty else { return }
        if let selected = ui.selectedID, agents.contains(where: { $0.id == selected }) {
            return
        }
        if let waiting = agents.first(where: { $0.status == .waiting }) {
            ui.animationLockUntil = Date().addingTimeInterval(0.45)
            withAnimation(.spring(response: 0.45, dampingFraction: 0.80)) {
                ui.selectedID = waiting.id
            }
        } else if let first = agents.first {
            ui.animationLockUntil = Date().addingTimeInterval(0.45)
            withAnimation(.spring(response: 0.45, dampingFraction: 0.80)) {
                ui.selectedID = first.id
            }
        }
    }

    private func mapLiveAgent(_ live: LiveFeed.LiveAgent) -> Agent {
        let status = AgentStatus.external(live.status)
        let firstApproval = live.approvals?.first
        let questions = mapQuestions(firstApproval?.questions)
        let tool: String
        if let t = live.tool, !t.isEmpty {
            tool = t
        } else if status == .waiting {
            tool = "等待处理"
        } else if status == .running {
            tool = (live.busy == true) ? "思考中" : "空闲"
        } else if let detail = live.detail, !detail.isEmpty {
            tool = detail
        } else {
            tool = "空闲"
        }
        var note: String?
        if let count = live.approvals?.count, count > 1 {
            note = "\(count) 个待处理"
        } else if live.origin == "subagent" {
            note = "子代理"
        }
        let startedAt = live.lastActivity.map { Date(timeIntervalSince1970: $0 / 1000.0) } ?? Date()
        let steps: [AgentStep] = (live.process ?? []).map { step in
            AgentStep(
                kind: step.kind ?? "step",
                label: step.label,
                detail: step.detail,
                at: step.at.map { Date(timeIntervalSince1970: $0 / 1000.0) }
            )
        }
        let sessions: [AgentSession] = (live.sessions ?? []).map { session in
            AgentSession(
                id: session.id,
                project: session.project ?? "会话",
                tool: session.tool,
                detail: session.detail,
                status: AgentStatus.external(session.status),
                startedAt: Date(timeIntervalSince1970: (session.startedAt ?? live.lastActivity ?? 0) / 1000.0),
                tokens: session.tokens
            )
        }
        return Agent(
            id: live.id,
            name: live.name,
            project: live.project ?? (live.origin == "subagent" ? "subagent" : (live.origin == "external" ? "外部 agent" : "DSH")),
            tool: tool,
            status: status,
            startedAt: startedAt,
            approvalCommand: firstApproval?.command ?? firstApproval?.reason,
            approvalId: firstApproval?.id,
            note: note,
            thought: live.thought,
            thoughtZh: live.thoughtZh,
            steps: steps,
            tokens: live.tokens,
            tokensToday: live.tokensToday,
            isExternal: live.external == true,
            sessions: sessions,
            appBundleID: live.appBundleID,
            approvalKind: firstApproval?.kind,
            questions: questions,
            questionAnswerable: firstApproval?.kind == "question" && firstApproval?.answerable == true && !questions.isEmpty
        )
    }

    private func mapQuestions(_ dtos: [LiveFeed.QuestionDTO]?) -> [AgentQuestion] {
        guard let dtos else { return [] }
        return dtos.compactMap { dto in
            guard let id = dto.id, let prompt = dto.question, !id.isEmpty, !prompt.isEmpty else { return nil }
            let options = (dto.options ?? []).enumerated().compactMap { index, option -> AgentQuestionOption? in
                guard let label = option.label, !label.isEmpty else { return nil }
                return AgentQuestionOption(id: "\(id)#\(index)", label: label, detail: option.description, display: option.display)
            }
            return AgentQuestion(
                id: id,
                prompt: prompt,
                header: dto.header,
                detail: dto.detail,
                multiSelect: dto.multiSelect == true,
                allowCustom: dto.allowCustom == true,
                intent: dto.intent,
                options: options
            )
        }
    }

    // MARK: Bridge autostart (optional; disabled with --no-bridge)

    private func startBridgeWatchdog() {
        guard !CommandLine.arguments.contains("--no-bridge") else { return }
        lastFeedRead = Date()
        let timer = Timer(timeInterval: 20.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if let process = self.bridgeProcess, !process.isRunning {
                self.bridgeProcess = nil
            }
            // A fresh status.json means some bridge is alive (ours, or one that
            // start.sh launched). The bridge heartbeats every 5 s, so 12 s
            // without an update is already stale. Leave a live bridge alone
            // instead of re-logging it.
            if Date().timeIntervalSince(self.lastFeedRead) <= 12 { return }
            guard let process = self.bridgeProcess else {
                self.ensureBridgeRunning()
                return
            }
            // Our bridge is alive but has not published a snapshot for 90 s:
            // it wedged before or during its first tick (for example when its
            // status socket could not bind). Recycle it instead of staying
            // offline until the app is restarted.
            if Date().timeIntervalSince(self.lastFeedRead) > 90 {
                dlog("[agentbar] bridge unresponsive; restarting")
                process.terminate()
                self.bridgeProcess = nil
                self.ensureBridgeRunning()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        bridgeWatchdog = timer
    }

    private func scheduleBridgeAutostart() {
        guard !CommandLine.arguments.contains("--no-bridge") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.ensureBridgeRunning()
        }
    }

    /// Copy the bridge program shipped inside the app into Application Support.
    /// The packaged app has no repo beside it, so this is what puts
    /// dsh-bridge.mjs on disk for a DMG-only install. The sync leaves
    /// status.json, control/, audit.log, and usage-state.json alone.
    private func syncBundledBridgeToAppSupport() {
        guard let source = bundledBridgeDirectory() else {
            if Bundle.main.bundleURL.pathExtension == "app" {
                dlog("[agentbar] bundled bridge missing")
            }
            return
        }
        guard let destination = appSupportBridgeDir() else {
            dlog("[agentbar] application support directory unavailable")
            return
        }
        guard let script = bundledBridgeSyncScript() else {
            dlog("[agentbar] bridge sync script missing")
            return
        }
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentbar-bridge-sync-\(ProcessInfo.processInfo.processIdentifier).log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: logURL) }
        do {
            let handle = try FileHandle(forWritingTo: logURL)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [script.path, source.path, destination.path]
            process.standardOutput = handle
            process.standardError = handle
            process.standardInput = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            handle.closeFile()
            let output = (try? String(contentsOf: logURL, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if process.terminationStatus == 0 {
                dlog("[agentbar] bridge synced to \(destination.path)")
            } else {
                let detail = output.isEmpty ? "no output" : output
                dlog("[agentbar] bridge sync failed (\(process.terminationStatus)): \(detail)")
            }
        } catch {
            dlog("[agentbar] bridge sync failed to start: \(error.localizedDescription)")
        }
    }

    private func bundledBridgeDirectory() -> URL? {
        for url in bundledResourceCandidates(["bridge"], isDirectory: true) {
            let script = url.appendingPathComponent("dsh-bridge.mjs", isDirectory: false)
            if FileManager.default.fileExists(atPath: script.path) {
                return url
            }
        }
        return nil
    }

    private func bundledBridgeSyncScript() -> URL? {
        for url in bundledResourceCandidates(["tools", "sync-bundled-bridge.sh"], isDirectory: false) {
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    /// One path component at a time. A slash inside a single component is
    /// percent-encoded by URL and would miss the file in the bundle.
    private func bundledResourceCandidates(_ components: [String], isDirectory: Bool) -> [URL] {
        func append(_ base: URL) -> URL {
            var url = base
            for (index, component) in components.enumerated() {
                let directory = isDirectory || index < components.count - 1
                url = url.appendingPathComponent(component, isDirectory: directory)
            }
            return url
        }
        var urls: [URL] = []
        if let resources = Bundle.main.resourceURL {
            urls.append(append(resources))
        }
        let bundle = Bundle.main.bundleURL
        if bundle.pathExtension == "app" {
            let resources = append(bundle
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true))
            urls.append(resources)
        }
        return urls
    }

    /// The bridge reads some settings only at launch (for example whether
    /// external thoughts may be translated). Recycle the app-managed process
    /// so a toggle takes effect immediately.
    private func restartBridgeForSettingsChange() {
        guard let process = bridgeProcess, process.isRunning else { return }
        dlog("[agentbar] settings changed; restarting bridge")
        process.terminate()
        bridgeProcess = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.ensureBridgeRunning()
        }
    }

    private func ensureBridgeRunning() {
        guard bridgeProcess == nil, let feedURL = feedURL else { return }
        if let data = try? Data(contentsOf: feedURL),
           let feed = try? JSONDecoder().decode(LiveFeed.self, from: data),
           let pid = feed.bridge?.pid, kill(pid_t(pid), 0) == 0 {
            dlog("[agentbar] bridge already running (pid \(pid))")
            return
        }
        let bridgeDir = feedURL.deletingLastPathComponent()
        let script = bridgeDir.appendingPathComponent("dsh-bridge.mjs")
        guard FileManager.default.fileExists(atPath: script.path) else {
            dlog("[agentbar] bridge script missing: \(script.path)")
            return
        }
        guard let node = findNodeExecutable() else {
            dlog("[agentbar] node not found; staying in demo mode")
            return
        }
        let process = Process()
        let logPath = "/tmp/agentbar-bridge.log"
        rotateLogIfNeeded(logPath)
        // Launch through /bin/sh with real shell redirection: this avoids inheriting
        // the GUI app's stdio setup, which can leave a Node child with no visible output.
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        var bridgeArgs = [node.url.path] + node.prefixArgs + [script.path]
        // External thoughts (Codex reasoning, WorkBuddy spans) stay local unless
        // the user opts in from Settings.
        if UserDefaults.standard.bool(forKey: "AgentBarTranslateExternalThoughts") {
            bridgeArgs.append("--translate-external")
        }
        let nodeCommand = bridgeArgs
            .map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
            .joined(separator: " ")
        process.arguments = ["-c", "exec " + nodeCommand + " >> " + "'" + logPath + "' 2>&1"]
        process.currentDirectoryURL = bridgeDir
        process.standardInput = FileHandle.nullDevice

        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self = self else { return }
                dlog("[agentbar] bridge exited: status=\(proc.terminationStatus)")
                // A stale handler for a replaced process must not clear the new one.
                if self.bridgeProcess === proc { self.bridgeProcess = nil }
                guard !self.isTerminating, self.bridgeProcess == nil else { return }
                // Restart without waiting for the 20 s watchdog. Back off when
                // the bridge dies immediately (missing Node, bad script, ...)
                // so a permanent failure does not become a spawn loop.
                if Date().timeIntervalSince(self.bridgeStartedAt) < 20 {
                    self.bridgeRestartDelay = min(self.bridgeRestartDelay * 2, 60)
                } else {
                    self.bridgeRestartDelay = 2
                }
                let delay = self.bridgeRestartDelay
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.ensureBridgeRunning()
                }
            }
        }
        do {
            try process.run()
            bridgeProcess = process
            bridgeStartedAt = Date()
            dlog("[agentbar] bridge started: \(script.path) pid=\(process.processIdentifier)")
        } catch {
            dlog("[agentbar] bridge failed to start: \(error)")
        }
    }

    private func findNodeExecutable() -> (url: URL, prefixArgs: [String])? {
        let candidates = [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            NSHomeDirectory() + "/.npm-global/bin/node",
            NSHomeDirectory() + "/.dsh/dsh-runtimes/dsh-primary-runtime/dependencies/node/bin/node"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return (URL(fileURLWithPath: path), [])
        }
        let env = URL(fileURLWithPath: "/usr/bin/env")
        if FileManager.default.isExecutableFile(atPath: env.path) {
            return (env, ["node"])
        }
        return nil
    }

    // MARK: Local desktop app adapters

    private func scheduleAppAdaptersAutostart() {
        guard !CommandLine.arguments.contains("--no-bridge"),
              !CommandLine.arguments.contains("--no-adapters") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.ensureAppAdaptersRunning()
        }
    }

    private func ensureAppAdaptersRunning() {
        guard appAdapterProcess == nil else { return }
        guard let resourceURL = Bundle.main.resourceURL else { return }
        let script = resourceURL.appendingPathComponent("tools/agentbar-app-adapters.mjs")
        guard FileManager.default.fileExists(atPath: script.path) else {
            dlog("[agentbar] app adapter script missing: \(script.path)")
            return
        }
        guard let node = findNodeExecutable() else {
            dlog("[agentbar] node not found; app adapters disabled")
            return
        }
        let process = Process()
        let logPath = "/tmp/agentbar-adapters.log"
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        let nodeCommand = ([node.url.path] + node.prefixArgs + [script.path])
            .map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
            .joined(separator: " ")
        process.arguments = ["-c", "exec " + nodeCommand + " >> " + "'" + logPath + "' 2>&1"]
        process.currentDirectoryURL = script.deletingLastPathComponent()
        process.standardInput = FileHandle.nullDevice
        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                dlog("[agentbar] app adapters exited: status=\(proc.terminationStatus)")
                self?.appAdapterProcess = nil
            }
        }
        do {
            try process.run()
            appAdapterProcess = process
            dlog("[agentbar] app adapters started: \(script.path) pid=\(process.processIdentifier)")
        } catch {
            dlog("[agentbar] app adapters failed to start: \(error)")
        }
    }

    private func openExternalApp(_ bundleIdentifier: String) {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
            running.activate(options: [.activateAllWindows])
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            dlog("[agentbar] cannot locate app \(bundleIdentifier)")
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error = error {
                    dlog("[agentbar] open app \(bundleIdentifier) failed: \(error.localizedDescription)")
                } else {
                    dlog("[agentbar] opened app \(bundleIdentifier)")
                }
                _ = self
            }
        }
    }

    private func openAdapterLog() {
        let url = URL(fileURLWithPath: "/tmp/agentbar-adapters.log")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        NSWorkspace.shared.open(url)
    }

    private func restartAppAdapters() {
        dlog("[agentbar] restart app adapters requested")
        if let adapter = appAdapterProcess, adapter.isRunning { adapter.terminate() }
        appAdapterProcess = nil
        let lock = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/AgentBar/agentbar-app-adapters.lock")
        if let text = try? String(contentsOf: lock, encoding: .utf8),
           let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            kill(pid, SIGTERM)
        }
        try? FileManager.default.removeItem(at: lock)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.ensureAppAdaptersRunning()
        }
    }

    // MARK: Context menu on the agent bar

    private func showBarContextMenu(_ event: NSEvent) {
        guard let view = barPanel?.contentView else { return }
        let menu = NSMenu()
        let openItem = NSMenuItem(title: "打开状态面板", action: #selector(openPanelFromMenu), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "退出 Agent Bar", action: #selector(quitFromMenu), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    @objc private func openPanelFromMenu() {
        lastUserInteraction = Date()
        setExpanded(true)
    }

    @objc private func quitFromMenu() {
        NSApp.terminate(nil)
    }

    // MARK: Expanded panel

    private func toggleExpanded() {
        lastUserInteraction = Date()
        setExpanded(!isExpanded)
    }

    private func collapsedPanelFrame(from frame: NSRect) -> NSRect {
        let h: CGFloat = 10
        return NSRect(x: frame.minX, y: frame.maxY - h, width: frame.width, height: h)
    }

    private func setExpanded(_ on: Bool) {
        guard let panel = panel, let frame = panelFrame() else { return }
        lastUserInteraction = Date()
        if on {
            let start = collapsedPanelFrame(from: frame)
            panel.setFrame(start, display: false)
            panel.alphaValue = 0
            // Non-activating panel: can become key for Esc without stealing the menu bar.
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
            isExpanded = true
            ui.animationsActive = true
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
                panel.animator().alphaValue = 1
            }
            dlog("[agentbar] expanded (unfold down)")
        } else {
            isExpanded = false
            ui.animationsActive = ui.hoveredIndex != nil
            let collapsed = collapsedPanelFrame(from: frame)
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.16
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().setFrame(collapsed, display: true)
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
            })
            dlog("[agentbar] collapsed")
        }
    }

    // MARK: Yield to the system menu bar

    private func setYielding(_ yielding: Bool) {
        guard yielding != isYielding else { return }
        isYielding = yielding
        guard let panel = barPanel else { return }

        if yielding {
            if isExpanded { setExpanded(false) }
            panel.ignoresMouseEvents = true
            if let hidden = hiddenBarFrame() {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.14
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    panel.animator().setFrame(hidden, display: true)
                }, completionHandler: { [weak self] in
                    if self?.isYielding == true { panel.orderOut(nil) }
                })
            }
            dlog("[agentbar] state=yield (system menu bar visible)")
        } else {
            guard let shown = barFrame(), let hidden = hiddenBarFrame() else { return }
            panel.setFrame(hidden, display: false)
            panel.ignoresMouseEvents = false
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.20
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(shown, display: true)
            }
            dlog("[agentbar] state=rest (agent bar visible)")
        }
    }

    // MARK: Mouse polling

    // The 20 Hz busy loop is gone: hover/yield now react to NSEvent mouse-moved
    // monitors, and this 1 Hz timer is only a fallback plus the network sampler.
    private func startPolling() {
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.poll(sampleNetwork: true) }
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t

        // Throttled: a fast trackpad can emit >120 moves/s and each one costs a
        // hit-test pass. 8ms keeps it visually instant without spinning.
        mouseMoveGlobal = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            self?.pollOnMouseMove()
        }
        mouseMoveLocal = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.pollOnMouseMove()
            return event
        }
    }

    private var lastMousePollAt = Date.distantPast

    private func pollOnMouseMove() {
        let now = Date()
        guard now.timeIntervalSince(lastMousePollAt) > 0.008 else { return }
        lastMousePollAt = now
        poll()
    }

    private func poll(sampleNetwork: Bool = false) {
        lastHeartbeat = Date()
        if sampleNetwork { net.sample() }
        guard let screen = primaryScreen() else { return }
        let mouse = NSEvent.mouseLocation
        let top = screen.frame.maxY
        let barH = geom.barHeight
        let atTop = mouse.y >= top - 2.0

        if forceYield {
            if !isYielding {
                setYielding(true)
            }
            return
        }

        if atTop && !isYielding {
            dlog("[agentbar] poll: mouse.y=\(mouse.y) top=\(top) -> top edge")
            setYielding(true)
        } else if !atTop && isYielding && mouse.y <= top - barH - 4 {
            dlog("[agentbar] poll: mouse.y=\(mouse.y) -> left top zone")
            setYielding(false)
        }

        updateHover(mouseLocation: mouse, screen: screen)

        if CommandLine.arguments.contains("--debug-layout"),
           Date().timeIntervalSince(lastRailDumpAt) > 3 {
            lastRailDumpAt = Date()
            let frames = ui.railLayout.frames
            let summary = frames.keys.sorted().map { key -> String in
                let rect = frames[key] ?? .zero
                return "\(key.prefix(9))…=\(Int(rect.minX))-\(Int(rect.maxX))"
            }.joined(separator: " | ")
            dlog("[rail/live] n=\(frames.count) selected=\(ui.selectedID?.prefix(12) ?? "nil") \(summary)")
        }

        if Date().timeIntervalSince(lastAutoHideCheck) > 15 {
            lastAutoHideCheck = Date()
            checkAutoHideMode()
        }
    }

    private func updateHover(mouseLocation: NSPoint, screen: NSScreen) {
        guard !isYielding, !isExpanded, forceYield == false else {
            if ui.hoveredIndex != nil { ui.hoveredIndex = nil }
            return
        }
        let localX = mouseLocation.x - screen.frame.minX
        let fromTop = screen.frame.maxY - mouseLocation.y
        guard fromTop >= 0, fromTop <= geom.barHeight else {
            if ui.hoveredIndex != nil { ui.hoveredIndex = nil }
            return
        }
        let local = CGPoint(x: localX - railLeading, y: fromTop)
        let frames = railFrames()
        let overflowHover = frames["overflow"]?.contains(local) ?? false
        var hover: Int?
        if !overflowHover,
           let hit = frames.first(where: { $0.key.hasPrefix("icon:") && $0.value.contains(local) }) {
            let id = String(hit.key.dropFirst(5))
            if id != ui.selectedID, let index = store.agents.firstIndex(where: { $0.id == id }) {
                hover = index
            }
        }
        if ui.hoveredIndex != hover { ui.hoveredIndex = hover }
        let animationsActive = hover != nil || isExpanded
        if ui.animationsActive != animationsActive { ui.animationsActive = animationsActive }
        if ui.hoveredOverflow != overflowHover { ui.hoveredOverflow = overflowHover }
    }

    private func checkAutoHideMode() {
        let newMode = UserDefaults.standard.bool(forKey: "_HIHideMenuBar")
        guard newMode != autoHideMode else { return }
        autoHideMode = newMode
        barPanel?.level = barLevel(autoHide: newMode)
        panel?.level = NSWindow.Level(rawValue: barLevel(autoHide: newMode).rawValue + 1)
        dlog("[agentbar] auto-hide menu bar changed: realMode=\(newMode)")
    }

    // MARK: Screen changes

    @objc private func screenParametersChanged() {
        applyScreenSelection()
        dlog("[agentbar] screen changed: \(screenDescription())")
    }

    // MARK: Watchdog: if the main thread hangs, quit so the menu bar is never left covered

    private func startWatchdog() {
        let thread = Thread { [weak self] in
            while true {
                Thread.sleep(forTimeInterval: 4.0)
                guard let self = self else { return }
                if Date().timeIntervalSince(self.lastHeartbeat) > 20.0 {
                    fputs("agentbar: main thread stalled for >20s, exiting to restore the menu bar\n", stderr)
                    // Kill the bridge first: exit(0) skips applicationWillTerminate, and a
                    // stray bridge would keep polling DSH with no UI behind it.
                    if let bridge = self.bridgeProcess, bridge.isRunning { bridge.terminate() }
                    if let adapter = self.appAdapterProcess, adapter.isRunning { adapter.terminate() }
                    exit(0)
                }
            }
        }
        thread.name = "agentbar-watchdog"
        thread.start()
    }

    // MARK: Panel behavior (Esc / outside click / pin)

    private func installPanelBehavior() {
        panelKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if self.isExpanded && event.keyCode == 53 {
                self.setExpanded(false)
                return nil
            }
            return event
        }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self, self.isExpanded, !self.ui.isPinned else { return }
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
                return
            }
            self.setExpanded(false)
        }
    }

    @objc private func togglePanelFromHotkey() {
        if isYielding { setYielding(false) }
        setExpanded(!isExpanded)
    }

    // MARK: Notifications

    private func checkBudgetAlert(tokens: Int?) {
        guard notificationsEnabled() else { return }
        let budget = UserDefaults.standard.double(forKey: "AgentBarDailyTokenBudget")
        guard budget > 0, let tokens = tokens, Double(tokens) > budget else { return }
        let day = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        guard UserDefaults.standard.string(forKey: "AgentBarBudgetAlertDay") != day else { return }
        UserDefaults.standard.set(day, forKey: "AgentBarBudgetAlertDay")
        postNotification(
            title: "用量预算提醒",
            body: "今日已用 \(shortTokenText(tokens)) / 预算 \(shortTokenText(Int(budget)))",
            agentID: "budget"
        )
    }

    private func notificationsEnabled() -> Bool {
        if UserDefaults.standard.object(forKey: "AgentBarNotificationsEnabled") == nil { return true }
        return UserDefaults.standard.bool(forKey: "AgentBarNotificationsEnabled")
    }

    private var canUseNotifications: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    private func setupNotifications() {
        guard canUseNotifications else {
            notificationAuth.markUnavailable()
            dlog("[agentbar] notifications unavailable (unbundled binary)")
            return
        }
        UNUserNotificationCenter.current().delegate = self
        notificationAuth.refresh()
    }

    private func currentNotificationGuide() -> NotificationGuide {
        let enabled: Bool
        if UserDefaults.standard.object(forKey: "AgentBarNotificationsEnabled") == nil {
            enabled = true
        } else {
            enabled = UserDefaults.standard.bool(forKey: "AgentBarNotificationsEnabled")
        }
        return notificationGuide(
            permission: notificationAuth.permission,
            inAppEnabled: enabled,
            promptDismissed: UserDefaults.standard.bool(forKey: "AgentBarNotificationPromptDismissed"),
            settingsHintDismissed: UserDefaults.standard.bool(forKey: "AgentBarNotificationSettingsHintDismissed")
        )
    }

    /// Open the panel once per launch when a notice needs permission the user has not dismissed.
    private func maybeShowNotificationGuide() {
        guard currentNotificationGuide() != .none else { return }
        guard !didSurfaceNotificationGuide else { return }
        didSurfaceNotificationGuide = true
        if !isExpanded { setExpanded(true) }
        dlog("[agentbar] notification guide surfaced")
    }

    private func postNotification(title: String, body: String, agentID: String) {
        NSSound(named: "Glass")?.play()
        guard canUseNotifications else {
            maybeShowNotificationGuide()
            return
        }
        // `.unknown` means the authorization read has not returned yet. Still try
        // the system banner so a previously authorized app does not drop alerts
        // during launch. A known denial or an undecided state stays sound-only.
        switch notificationAuth.permission {
        case .denied, .notDetermined, .unavailable:
            dlog("[agentbar] notification sound only (\(notificationAuth.permission.rawValue))")
            maybeShowNotificationGuide()
            return
        case .authorized, .unknown:
            break
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["agentID": agentID]
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func handleAgentTransitions(_ agents: [Agent]) {
        guard store.isLive else { return }
        if !liveSeenOnce {
            previousStatuses = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0.status) })
            lastNotifiedWaiting = Set(agents.filter { $0.status == .waiting }.map { $0.id })
            liveSeenOnce = true
            return
        }
        if notificationsEnabled() {
            for agent in agents where agent.status == .waiting {
                if !lastNotifiedWaiting.contains(agent.id) {
                    lastNotifiedWaiting.insert(agent.id)
                    postNotification(
                        title: "等待审批 · " + agent.name,
                        body: agent.approvalCommand ?? "有一个任务需要你确认",
                        agentID: agent.id
                    )
                }
            }
            for agent in agents where agent.status != .waiting {
                lastNotifiedWaiting.remove(agent.id)
            }
            for agent in agents {
                guard let previous = previousStatuses[agent.id] else { continue }
                guard previous == .running || previous == .waiting else { continue }
                guard agent.status == .done || agent.status == .failed else { continue }
                let key = agent.id + ":" + String(Int(agent.startedAt.timeIntervalSince1970))
                if !lastNotifiedFinished.contains(key) {
                    lastNotifiedFinished.insert(key)
                    postNotification(
                        title: agent.name + " · " + agent.status.label,
                        body: agent.note ?? (agent.status == .failed ? "任务失败" : "任务已完成"),
                        agentID: agent.id
                    )
                }
            }
        }
        previousStatuses = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0.status) })
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        DispatchQueue.main.async {
            if let id = response.notification.request.content.userInfo["agentID"] as? String {
                self.ui.selectedID = id
            }
            if !self.isExpanded { self.setExpanded(true) }
        }
        completionHandler()
    }

    // MARK: Global quit hotkey (no Accessibility permission needed)

    private func installQuitHotKey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            if let event = event {
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
            }
            DispatchQueue.main.async {
                if hotKeyID.id == 1 {
                    NSApp.terminate(nil)
                } else if hotKeyID.id == 2 {
                    (NSApp.delegate as? AppDelegate)?.togglePanelFromHotkey()
                }
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            nil,
            &hotKeyHandler
        )

        var quitRef: EventHotKeyRef?
        let quitStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_Q),
            UInt32(cmdKey | optionKey | controlKey),
            EventHotKeyID(signature: OSType(0x4E544348), id: 1),
            GetApplicationEventTarget(),
            0,
            &quitRef
        )
        hotKeyRef = quitRef

        var panelRef: EventHotKeyRef?
        let panelStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_A),
            UInt32(cmdKey | optionKey | controlKey),
            EventHotKeyID(signature: OSType(0x4E544348), id: 2),
            GetApplicationEventTarget(),
            0,
            &panelRef
        )
        hotKeyRef2 = panelRef
        dlog("[agentbar] hotkeys ⌃⌥⌘Q quit status=\(quitStatus) · ⌃⌥⌘A panel status=\(panelStatus)")
    }
}

// MARK: - Entry point

