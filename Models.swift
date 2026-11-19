import AppKit
import SwiftUI
import QuartzCore
import Carbon
import Combine
import IOKit.ps
import CoreWLAN
import UserNotifications

enum AgentStatus {
    case idle, running, waiting, done, failed

    var label: String {
        switch self {
        case .idle: return "待命"
        case .running: return "运行中"
        case .waiting: return "待审批"
        case .done: return "已完成"
        case .failed: return "失败"
        }
    }

    /// Shared with the bottom-trailing dot. 待命 is gray, 运行 is blue, 完成 is green.
    var color: Color {
        switch self {
        case .idle: return agentStatusPaint("idle").color
        case .running: return agentStatusPaint("running").color
        case .waiting: return agentStatusPaint("waiting").color
        case .done: return agentStatusPaint("done").color
        case .failed: return agentStatusPaint("failed").color
        }
    }
}

struct AgentStep: Identifiable {
    let id = UUID()
    let kind: String      // think | tool | result | reply
    let label: String?
    let detail: String?
    let at: Date?
}

struct AgentSession: Identifiable {
    let id: String
    let project: String
    let tool: String?
    let detail: String?
    let status: AgentStatus
    let startedAt: Date
    let tokens: Int?
}

extension AgentStatus {
    /// Map a live-feed or child-session status.
    /// An explicit `done` is a finished round. Idle and unknown values are 待命.
    static func external(_ raw: String?) -> AgentStatus {
        switch canonicalAgentFeedStatus(raw) {
        case "running": return .running
        case "waiting": return .waiting
        case "failed": return .failed
        case "done": return .done
        default: return .idle
        }
    }
}

struct Agent: Identifiable {
    let id: String
    var name: String
    var project: String
    var tool: String
    var status: AgentStatus
    var startedAt: Date
    var approvalCommand: String?
    var approvalId: String? = nil
    var note: String?
    var thought: String? = nil
    var thoughtZh: String? = nil
    var steps: [AgentStep] = []
    var tokens: Int? = nil
    var tokensToday: Int? = nil
    var isExternal: Bool = false
    var sessions: [AgentSession] = []
    var appBundleID: String? = nil
    var approvalKind: String? = nil
    var questions: [AgentQuestion] = []
    var questionAnswerable: Bool = false
}

// MARK: - Live feed from bridge/status.json (dsh-bridge)

struct LiveFeed: Decodable {
    struct DSHInfo: Decodable {
        let connected: Bool?
        let eventsConnected: Bool?
        let error: String?
        let url: String?
        let sessionsKnown: Int?
        let protocolStatus: String?
        let protocolError: String?

        enum CodingKeys: String, CodingKey {
            case connected, eventsConnected, error, url, sessionsKnown
            case protocolStatus = "protocol"
            case protocolError
        }
    }

    struct BridgeInfo: Decodable {
        let pid: Int?
        let startedAt: Double?
    }

    struct UsageHistoryPoint: Decodable {
        let day: String?
        let tokens: Int?
    }

    struct UsageInfo: Decodable {
        let tokensToday: Int?
        let sessionsToday: Int?
        let history: [UsageHistoryPoint]?
    }

    struct AccountInfo: Decodable {
        let status: String?
        let currency: String?
        let balance: String?
        let bonusBalance: String?
        let usageUrl: String?
        let topUpUrl: String?
        let error: String?

        private enum CodingKeys: String, CodingKey {
            case status, currency, balance, bonusBalance, usageUrl, topUpUrl, error
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // DSH has returned balance as a JSON string so far, but a single
            // number would fail `String` decoding and discard the entire feed.
            func text(_ key: CodingKeys) -> String? {
                if let value = try? container.decode(String.self, forKey: key) { return value }
                if let value = try? container.decode(Double.self, forKey: key) { return String(value) }
                return nil
            }
            status = text(.status)
            currency = text(.currency)
            balance = text(.balance)
            bonusBalance = text(.bonusBalance)
            usageUrl = text(.usageUrl)
            topUpUrl = text(.topUpUrl)
            error = text(.error)
        }
    }

    struct StepDTO: Decodable {
        let kind: String?
        let label: String?
        let detail: String?
        let at: Double?
    }

    struct Counts: Decodable {
        let agents: Int?
        let running: Int?
        let approvals: Int?
    }

    struct QuestionOptionDTO: Decodable {
        let label: String?
        let description: String?
        let display: String?
    }

    struct QuestionDTO: Decodable {
        let id: String?
        let question: String?
        let header: String?
        let detail: String?
        let multiSelect: Bool?
        let allowCustom: Bool?
        let intent: String?
        let options: [QuestionOptionDTO]?
    }

    struct Approval: Decodable {
        let id: String?
        let kind: String?
        let tool: String?
        let command: String?
        let reason: String?
        let createdAt: Double?
        let questions: [QuestionDTO]?
        let answerable: Bool?
    }

    struct LiveSession: Decodable {
        let id: String
        let project: String?
        let tool: String?
        let detail: String?
        let status: String?
        let startedAt: Double?
        let updatedAt: Double?
        let tokens: Int?
        let thought: String?
    }

    struct LiveAgent: Decodable {
        let id: String
        let name: String
        let status: String
        let busy: Bool?
        let tool: String?
        let detail: String?
        let project: String?
        let cwd: String?
        let model: String?
        let preset: String?
        let origin: String?
        let parentId: String?
        let focus: Bool?
        let lastActivity: Double?
        let tokens: Int?
        let tokensToday: Int?
        let external: Bool?
        let appBundleID: String?
        let sessions: [LiveSession]?
        let thought: String?
        let thoughtZh: String?
        let process: [StepDTO]?
        let approvals: [Approval]?
    }

    let schema: Int?
    let ts: Double?
    let bridge: BridgeInfo?
    let dsh: DSHInfo?
    let counts: Counts?
    let usage: UsageInfo?
    let account: AccountInfo?
    let agents: [LiveAgent]?
}

final class DemoStore: ObservableObject {
    @Published var agents: [Agent] = []
    @Published var completedToday: Int = 9
    @Published var tick: Int = 0
    @Published var isLive = false
    @Published var liveTotal = 0
    @Published var bridgeNote: String?
    @Published var usageTokensToday: Int? = 7_333_366
    @Published var usageHistory: [Int] = [5_410_000, 6_120_000, 5_880_000, 7_010_000, 6_430_000, 7_002_000]
    @Published var balanceText: String? = "¥89.94"
    @Published var dshURL: String? = "http://127.0.0.1:49469"
    @Published var controlDirectory: URL?
    @Published var claudeApprovalDirectory: URL?
    @Published var approvalNotice: String?
    @Published var feedMode: BarFeedMode = .demo
    @Published var protocolNote: String?

    private let demoSnapshot: [Agent]
    private let demoUsageTokens = 7_333_366
    private let demoBalance = "¥89.94"
    private let demoHistory = [5_410_000, 6_120_000, 5_880_000, 7_010_000, 6_430_000, 7_002_000]

    private var timer: Timer?
    private let toolPool = ["tools.run_code", "Edit App.swift", "Read README.md", "WebSearch: agent notch", "subagent: reviewer", "Bash: swift test"]
    private let waitPool = ["Bash: swift build --configuration release", "Edit Sources/NotchDemo.swift", "Bash: clean build artifacts"]

    init() {
        let seeded: [Agent] = [
            Agent(id: UUID().uuidString, name: "DeepSeek Harness", project: "deepseek-harness", tool: "tools.run_code",
                  status: .running, startedAt: Date().addingTimeInterval(-42), approvalCommand: nil, note: nil,
                  thought: "正在把思考详情与用量余额接入胶囊：先解析 bridge 的最新事件，再把 reasoning 摘要显示到胶囊尾部。",
                  steps: [
                    AgentStep(kind: "think", label: "思考", detail: "先确认 bridge 已经开始上报 thought/process 字段。", at: Date().addingTimeInterval(-64)),
                    AgentStep(kind: "tool", label: "run_code", detail: "node dsh-bridge.mjs --once", at: Date().addingTimeInterval(-52)),
                    AgentStep(kind: "result", label: "工具完成", detail: "拿到 2 个活跃会话与 ¥89.94 余额", at: Date().addingTimeInterval(-49)),
                    AgentStep(kind: "reply", label: "回复", detail: "状态面板已更新，继续加上胶囊里的思考摘要。", at: Date().addingTimeInterval(-30))
                  ],
                  tokens: 737_131, tokensToday: 128_400),
            Agent(id: UUID().uuidString, name: "Codex", project: "agent-notch", tool: "Bash: swift build",
                  status: .waiting, startedAt: Date().addingTimeInterval(-96),
                  approvalCommand: "Bash: swift build --configuration release", approvalId: "demo-approval", note: nil,
                  thought: "发布构建需要写 .build 目录，等待你授权后执行；构建成功再跑一次冷启动检查。",
                  steps: [
                    AgentStep(kind: "think", label: "思考", detail: "先检查 Package.swift 与 build.sh 的发布参数。", at: Date().addingTimeInterval(-85)),
                    AgentStep(kind: "tool", label: "Bash: swift build", detail: "swift build --configuration release", at: Date().addingTimeInterval(-70))
                  ],
                  tokens: 120_540, tokensToday: 54_200),
            Agent(id: UUID().uuidString, name: "Grok Bot", project: "web-brief", tool: "WebSearch: agent notch",
                  status: .running, startedAt: Date().addingTimeInterval(-18), approvalCommand: nil, note: nil,
                  thought: "在搜集最近 24 小时的 agent notch / Dynamic Island 新实现，准备整理成一份对比清单。",
                  steps: [
                    AgentStep(kind: "think", label: "思考", detail: "先按 star 数筛出近一周内活跃的项目。", at: Date().addingTimeInterval(-15)),
                    AgentStep(kind: "tool", label: "WebSearch", detail: "agent notch dynamic island 2026", at: Date().addingTimeInterval(-8))
                  ],
                  tokens: 88_200, tokensToday: 22_800),
            Agent(id: UUID().uuidString, name: "WorkBuddy", project: "feishu-bot", tool: "Read CHANGELOG.md",
                  status: .done, startedAt: Date().addingTimeInterval(-300), approvalCommand: nil, note: "已提交评审意见",
                  thought: "评审意见已提交，等待下一次任务；重点风险是审批卡片与胶囊的点击命中冲突。",
                  steps: [
                    AgentStep(kind: "tool", label: "Read CHANGELOG.md", detail: "CHANGELOG.md", at: Date().addingTimeInterval(-290)),
                    AgentStep(kind: "reply", label: "回复", detail: "已提交 3 条评审意见。", at: Date().addingTimeInterval(-260))
                  ],
                  tokens: 45_600, tokensToday: 0),
            Agent(id: UUID().uuidString, name: "Hermes", project: "web-brief", tool: "swift test",
                  status: .failed, startedAt: Date().addingTimeInterval(-420), approvalCommand: nil, note: "2 tests failed",
                  thought: "测试有两个用例失败，先定位是布局命中区间还是动画锁的边界问题。",
                  steps: [
                    AgentStep(kind: "tool", label: "swift test", detail: "swift test --filter RailHitTests", at: Date().addingTimeInterval(-410)),
                    AgentStep(kind: "result", label: "工具失败", detail: "2 tests failed", at: Date().addingTimeInterval(-400)),
                    AgentStep(kind: "reply", label: "回复", detail: "正在重试并检查动画锁。", at: Date().addingTimeInterval(-380))
                  ],
                  tokens: 32_100, tokensToday: 8_400),
        ]
        agents = seeded
        demoSnapshot = seeded

        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.step() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    var runningCount: Int { agents.filter { $0.status == .running }.count }
    var waitingAgents: [Agent] { agents.filter { $0.status == .waiting } }
    var waitingCount: Int { waitingAgents.count }
    var firstRunning: Agent? { agents.first { $0.status == .running } }

    private func step() {
        tick += 1
        if isLive || feedMode == .protocolMismatch { return }
        let now = Date()
        for i in agents.indices {
            switch agents[i].status {
            case .running:
                if tick % 7 == 0 {
                    agents[i].tool = toolPool[Int.random(in: 0..<toolPool.count)]
                }
                if tick % 29 == 0 {
                    agents[i].status = .done
                    agents[i].note = "本轮完成"
                    completedToday += 1
                }
            case .done:
                if tick % 17 == 0 {
                    agents[i].status = .running
                    agents[i].tool = toolPool[Int.random(in: 0..<toolPool.count)]
                    agents[i].startedAt = now
                    agents[i].note = nil
                }
            case .failed:
                if tick % 23 == 0 {
                    agents[i].status = .running
                    agents[i].tool = "Bash: retry"
                    agents[i].startedAt = now
                    agents[i].note = nil
                }
            case .waiting:
                if tick % 37 == 0 {
                    agents[i].tool = toolPool[Int.random(in: 0..<toolPool.count)]
                }
            case .idle:
                if tick % 17 == 0 {
                    agents[i].status = .running
                    agents[i].tool = toolPool[Int.random(in: 0..<toolPool.count)]
                    agents[i].startedAt = now
                    agents[i].note = nil
                }
            }
        }

        if waitingCount == 0 && tick % 19 == 0 {
            if let idx = agents.indices.first(where: { agents[$0].status == .done || agents[$0].status == .running }) {
                agents[idx].status = .waiting
                agents[idx].approvalCommand = waitPool[Int.random(in: 0..<waitPool.count)]
                agents[idx].tool = "等待授权"
                agents[idx].startedAt = now
                agents[idx].note = nil
            }
        }

        if runningCount == 0 {
            let idx = Int.random(in: 0..<agents.count)
            agents[idx].status = .running
            agents[idx].tool = toolPool[Int.random(in: 0..<toolPool.count)]
            agents[idx].startedAt = now
            agents[idx].note = nil
        }
    }

    func approve(_ id: String) {
        guard let i = agents.firstIndex(where: { $0.id == id }) else { return }
        let command = agents[i].approvalCommand ?? "Bash"
        agents[i].status = .running
        agents[i].tool = command.replacingOccurrences(of: "Bash: ", with: "")
        agents[i].approvalCommand = nil
        agents[i].startedAt = Date()
        agents[i].note = "已授权"
        dlog("[agentbar] demo approve: \(agents[i].name) (\(command))")
    }

    func deny(_ id: String) {
        guard let i = agents.firstIndex(where: { $0.id == id }) else { return }
        agents[i].status = .failed
        agents[i].approvalCommand = nil
        agents[i].note = "已拒绝"
        dlog("[agentbar] demo deny: \(agents[i].name)")
    }

    // MARK: Live bridge feed

    func submitApproval(approvalId: String, sessionId: String, tool: String, command: String?, decision: String) -> Bool {
        submitControl(
            approvalId: approvalId,
            sessionId: sessionId,
            tool: tool,
            command: command,
            decision: decision,
            answers: nil,
            notice: "已发送，等待 DSH 处理…"
        )
    }

    func submitQuestion(approvalId: String, sessionId: String, answers: [QuestionAnswer], cancelled: Bool) -> Bool {
        let rows: [[String: Any]]? = cancelled ? nil : answers.map { answer in
            var row: [String: Any] = ["id": answer.id, "selected": answer.selected]
            if let custom = answer.custom { row["custom"] = custom }
            return row
        }
        return submitControl(
            approvalId: approvalId,
            sessionId: sessionId,
            tool: "ask_user_question",
            command: nil,
            decision: cancelled ? "cancelled" : "answered",
            answers: rows,
            notice: cancelled ? "已取消，等待 DSH 处理…" : "已提交回答，等待 DSH 处理…"
        )
    }

    private func submitControl(
        approvalId: String,
        sessionId: String,
        tool: String,
        command: String?,
        decision: String,
        answers: [[String: Any]]?,
        notice: String
    ) -> Bool {
        if let requestId = claudeApprovalRequestId(approvalId) {
            return submitClaudeApproval(requestId: requestId, decision: decision, notice: notice)
        }
        guard let dir = controlDirectory else { return false }
        let tokenURL = dir.appendingPathComponent("token")
        guard let token = try? String(contentsOf: tokenURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
            approvalNotice = "审批控制未就绪（bridge 未连接）"
            return false
        }
        var payload: [String: Any] = [
            "schema": 1,
            "approvalId": approvalId,
            "sessionId": sessionId,
            "tool": tool,
            "command": command ?? "",
            "decision": decision,
            "requestedAt": Int(Date().timeIntervalSince1970 * 1000),
            "token": token
        ]
        if let answers { payload["answers"] = answers }
        do {
            try FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let name = "request-\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(8)).json"
            let temporary = dir.appendingPathComponent("." + name + ".tmp")
            let final = dir.appendingPathComponent(name)
            let data = try JSONSerialization.data(withJSONObject: payload, options: [])
            try data.write(to: temporary, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
            try FileManager.default.moveItem(at: temporary, to: final)
            approvalNotice = notice
            return true
        } catch {
            approvalNotice = "发送失败：\(error.localizedDescription)"
            return false
        }
    }

    private func submitClaudeApproval(requestId: String, decision: String, notice: String) -> Bool {
        guard let dir = claudeApprovalDirectory else {
            approvalNotice = "审批目录未就绪"
            return false
        }
        let pending = dir.appendingPathComponent("pending/\(requestId).json")
        guard let data = try? Data(contentsOf: pending),
              let approval = parseClaudePendingApproval(data) else {
            approvalNotice = "审批已过期（hook 已超时）"
            return false
        }
        guard let mapped = claudeApprovalDecision(decision),
              let payload = claudeApprovalDecisionJSON(approval, decision: mapped, at: Date()) else {
            approvalNotice = "不支持的审批决定"
            return false
        }
        let decisions = dir.appendingPathComponent("decisions", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: decisions,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let final = decisions.appendingPathComponent("\(requestId).json")
            try payload.write(to: final, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: final.path)
            appendClaudeAudit(approval, decision: mapped)
            approvalNotice = notice
            return true
        } catch {
            approvalNotice = "发送失败：\(error.localizedDescription)"
            return false
        }
    }

    private func appendClaudeAudit(_ approval: ClaudePendingApproval, decision: String) {
        guard let dir = claudeApprovalDirectory else { return }
        let row: [String: Any] = [
            "at": Int(Date().timeIntervalSince1970 * 1000),
            "id": approval.id,
            "sessionId": approval.sessionId,
            "tool": approval.tool,
            "command": approval.command,
            "decision": decision,
            "source": "panel"
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) else { return }
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let url = dir.appendingPathComponent("audit.log")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        handle.write(data)
        handle.write(Data([0x0A]))
    }

    func applyLiveFeed(_ newAgents: [Agent], total: Int) {
        agents = newAgents
        liveTotal = max(total, newAgents.count)
        feedMode = .live
        protocolNote = nil
        if !isLive {
            isLive = true
            dlog("[agentbar] live feed attached: \(newAgents.count) agents")
        }
        if bridgeNote != nil { bridgeNote = nil }
    }

    func showProtocolMismatch(_ note: String, agents externalAgents: [Agent]) {
        let changed = feedMode != .protocolMismatch || protocolNote != note
        feedMode = .protocolMismatch
        protocolNote = note
        isLive = false
        bridgeNote = nil
        agents = externalAgents
        usageTokensToday = nil
        balanceText = nil
        usageHistory = []
        approvalNotice = nil
        if changed { dlog("[agentbar] protocol mismatch: \(note)") }
    }

    func leaveProtocolMismatch() {
        guard feedMode == .protocolMismatch else { return }
        feedMode = .demo
        protocolNote = nil
        isLive = false
        agents = demoSnapshot
        usageTokensToday = demoUsageTokens
        balanceText = demoBalance
        usageHistory = demoHistory
    }

    func markBridgeOffline(_ note: String) {
        feedMode = .offline
        protocolNote = nil
        if bridgeNote != note {
            bridgeNote = note
            dlog("[agentbar] bridge offline: \(note)")
        }
    }
}

final class Geometry: ObservableObject {
    @Published var barHeight: CGFloat = 30
    @Published var notchWidth: CGFloat = 200
    @Published var hasNotch: Bool = false
}

final class SystemStatus: ObservableObject {
    @Published var batteryPercent: Int?
    @Published var batteryCharging = false
    @Published var hasBattery = false
    @Published var acPower = false
    @Published var wifiOn = true
    @Published var wifiSSID: String?
    @Published var weatherTemp: Double?
    @Published var weatherCode: Int?

    private var batteryTimer: Timer?
    private var wifiTimer: Timer?
    private var weatherTimer: Timer?
    private var weatherInFlight = false
    private var weatherRetryDelay: TimeInterval = 60

    init() {
        refreshBattery()
        refreshWiFi()
        startTimers()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.refreshWeather()
        }
    }

    private func startTimers() {
        let b = Timer(timeInterval: 20.0, repeats: true) { [weak self] _ in self?.refreshBattery() }
        RunLoop.main.add(b, forMode: .common)
        batteryTimer = b

        let w = Timer(timeInterval: 20.0, repeats: true) { [weak self] _ in self?.refreshWiFi() }
        RunLoop.main.add(w, forMode: .common)
        wifiTimer = w

        let weather = Timer(timeInterval: 900.0, repeats: true) { [weak self] _ in self?.refreshWeather() }
        RunLoop.main.add(weather, forMode: .common)
        weatherTimer = weather
    }

    private func refreshBattery() {
        var percent: Int?
        var charging = false
        var hasBattery = false
        var acPower = false

        if let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                guard let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else { continue }
                let state = info[kIOPSPowerSourceStateKey as String] as? String
                if state == (kIOPSACPowerValue as String) { acPower = true }
                let type = info[kIOPSTypeKey as String] as? String
                if type == (kIOPSInternalBatteryType as String) {
                    hasBattery = true
                    let current = info[kIOPSCurrentCapacityKey as String] as? Int ?? 0
                    let maxCapacity = info[kIOPSMaxCapacityKey as String] as? Int ?? 100
                    if maxCapacity > 0 {
                        percent = Int((Double(current) / Double(maxCapacity) * 100.0).rounded())
                    } else {
                        percent = current
                    }
                    charging = info[kIOPSIsChargingKey as String] as? Bool ?? false
                }
            }
        }

        DispatchQueue.main.async {
            self.hasBattery = hasBattery
            self.batteryPercent = percent
            self.batteryCharging = charging
            self.acPower = acPower
        }
    }

    private func refreshWiFi() {
        guard let interface = CWWiFiClient.shared().interface() else { return }
        let on = interface.powerOn()
        let ssid = on ? interface.ssid() : nil
        DispatchQueue.main.async {
            self.wifiOn = on
            self.wifiSSID = (ssid?.isEmpty == false) ? ssid : nil
        }
    }

    // Two providers: open-meteo first (WMO codes, matches weatherSymbol), wttr.in as
    // fallback because api.open-meteo.com is not reachable from every network.
    func refreshWeather() {
        guard !weatherInFlight else { return }
        weatherInFlight = true
        let defaults = UserDefaults.standard
        let latitude = defaults.object(forKey: "AgentBarLatitude") as? Double ?? 31.2304
        let longitude = defaults.object(forKey: "AgentBarLongitude") as? Double ?? 121.4737

        fetchOpenMeteo(latitude: latitude, longitude: longitude) { [weak self] primary in
            guard let self = self else { return }
            if let primary = primary {
                self.weatherInFlight = false
                self.applyWeather(temp: primary.0, code: primary.1, source: "open-meteo")
                return
            }
            self.fetchWttr(latitude: latitude, longitude: longitude) { [weak self] fallback in
                guard let self = self else { return }
                self.weatherInFlight = false
                if let fallback = fallback {
                    self.applyWeather(temp: fallback.0, code: fallback.1, source: "wttr.in")
                } else {
                    self.applyWeather(temp: nil, code: nil, source: "none")
                    self.scheduleWeatherRetry()
                }
            }
        }
    }

    private func applyWeather(temp: Double?, code: Int?, source: String) {
        DispatchQueue.main.async {
            if let temp = temp { self.weatherTemp = temp }
            if let code = code { self.weatherCode = code }
        }
        if let temp = temp {
            weatherRetryDelay = 60
            dlog("[agentbar] weather: \(String(format: "%.1f", temp))° code=\(code.map(String.init) ?? "-") via \(source)")
        } else {
            dlog("[agentbar] weather: both providers failed, retry in \(Int(weatherRetryDelay))s")
        }
    }

    private func scheduleWeatherRetry() {
        let delay = weatherRetryDelay
        weatherRetryDelay = min(weatherRetryDelay * 2, 600)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.refreshWeather()
        }
    }

    private func fetchOpenMeteo(latitude: Double, longitude: Double,
                                completion: @escaping ((Double, Int?)?) -> Void) {
        guard let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&current=temperature_2m,weather_code&timezone=auto") else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                dlog("[agentbar] weather: open-meteo failed: \(error.localizedDescription)")
                completion(nil)
                return
            }
            guard let data = data,
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let current = object["current"] as? [String: Any],
                  let temp = current["temperature_2m"] as? Double else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                dlog("[agentbar] weather: open-meteo unusable response (http \(status), \(data?.count ?? 0) bytes)")
                completion(nil)
                return
            }
            completion((temp, current["weather_code"] as? Int))
        }.resume()
    }

    private func fetchWttr(latitude: Double, longitude: Double,
                           completion: @escaping ((Double, Int?)?) -> Void) {
        let location = String(format: "%.4f,%.4f", latitude, longitude)
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        guard !location.isEmpty, let url = URL(string: "https://wttr.in/\(location)?format=j1") else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("AgentBar/0.1", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                dlog("[agentbar] weather: wttr.in failed: \(error.localizedDescription)")
                completion(nil)
                return
            }
            guard let data = data,
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let conditions = object["current_condition"] as? [[String: Any]],
                  let first = conditions.first,
                  let temp = Double(first["temp_C"] as? String ?? "") else {
                completion(nil)
                return
            }
            let wwo = Int(first["weatherCode"] as? String ?? "") ?? 113
            completion((temp, wmoCode(fromWWO: wwo)))
        }.resume()
    }
}



// MARK: - Network throughput

/// Samples the physical interface counters (getifaddrs) once a second and turns
/// them into a smoothed up/down rate. The interface counters are 32-bit, so the
/// deltas use wrapping arithmetic and stay correct across the 4 GB roll-over.
final class NetSpeed: ObservableObject {
    // Published as formatted strings: the label only redraws when the rounded
    // value actually changes, instead of on every raw sample.
    @Published private(set) var downText = "0B"
    @Published private(set) var upText = "0B"
    @Published private(set) var isIdle = false

    private var downRate: Double = 0
    private var upRate: Double = 0
    private var last: [String: (inB: UInt32, outB: UInt32)] = [:]
    private var lastAt = Date()
    private var lastTrafficAt = Date()

    func sample() {
        var current: [String: (inB: UInt32, outB: UInt32)] = [:]
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return }
        defer { freeifaddrs(addrs) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            let ifa = entry.pointee
            cursor = ifa.ifa_next
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                  let namePtr = ifa.ifa_name, let rawData = ifa.ifa_data else { continue }
            let name = String(cString: namePtr)
            // Physical interfaces only: counting utun/bridge too would double count
            // VPN traffic that still leaves the machine through en0.
            guard name.hasPrefix("en") else { continue }
            let counters = rawData.assumingMemoryBound(to: if_data.self).pointee
            current[name] = (counters.ifi_ibytes, counters.ifi_obytes)
        }

        var deltaIn: Double = 0
        var deltaOut: Double = 0
        for (name, now) in current {
            guard let prev = last[name] else { continue }
            deltaIn += Double(now.inB &- prev.inB)
            deltaOut += Double(now.outB &- prev.outB)
        }
        last = current

        let stamp = Date()
        let elapsed = max(0.2, stamp.timeIntervalSince(lastAt))
        lastAt = stamp
        if deltaIn + deltaOut <= 0 {
            downRate *= 0.5
            upRate *= 0.5
        } else {
            // Exponential smoothing: raw per-second counters flicker too much to read.
            downRate = downRate * 0.55 + (deltaIn / elapsed) * 0.45
            upRate = upRate * 0.55 + (deltaOut / elapsed) * 0.45
        }
        if deltaIn + deltaOut > 0 {
            lastTrafficAt = stamp
            if isIdle { isIdle = false }
        } else if !isIdle, stamp.timeIntervalSince(lastTrafficAt) >= 30 {
            isIdle = true
        }
        let nextDown = speedText(downRate)
        let nextUp = speedText(upRate)
        if nextDown != downText { downText = nextDown }
        if nextUp != upText { upText = nextUp }
    }
}

// MARK: - Test display state

final class UIModel: ObservableObject {
    @Published var selectedID: String?
    @Published var hoveredIndex: Int?
    @Published var hoveredOverflow = false
    @Published var isPinned = false
    @Published var lastManualInteraction = Date.distantPast
    @Published var animationLockUntil = Date.distantPast
    let railLayout = RailLayout()

    func select(_ id: String) {
        lastManualInteraction = Date()
        animationLockUntil = Date().addingTimeInterval(0.55)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.80)) {
            selectedID = id
        }
    }
}

// MARK: - Pixel-art agent mascots

