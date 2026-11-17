import AppKit
import SwiftUI
import QuartzCore
import Carbon
import Combine
import IOKit.ps
import CoreWLAN
import UserNotifications

// MARK: - Utilities

let clockFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return f
}()

let stepTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    return f
}()

func containsCJK(_ text: String) -> Bool {
    text.unicodeScalars.contains { scalar in
        (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
    }
}

func formatMoney(currency: String?, balance: String?) -> String? {
    guard let balance = balance, let value = Double(balance) else { return nil }
    let symbol = currency == "USD" ? "$" : "¥"
    let truncated = (value * 100).rounded(.towardZero) / 100
    return String(format: "%@%.2f", symbol, truncated)
}

func stepIcon(_ kind: String) -> String {
    switch kind {
    case "tool": return "wrench.and.screwdriver.fill"
    case "result": return "checkmark.circle.fill"
    case "reply": return "text.bubble.fill"
    default: return "brain"
    }
}

func stepColor(_ kind: String) -> Color {
    switch kind {
    case "tool": return Color(red: 0.40, green: 0.78, blue: 1.0)
    case "result": return Color(red: 0.40, green: 0.88, blue: 0.60)
    case "reply": return Color(red: 0.85, green: 0.85, blue: 0.9)
    default: return Color(red: 0.85, green: 0.72, blue: 1.0)
    }
}

let dayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "zh_CN")
    f.dateFormat = "M月d日 EEE"
    return f
}()

func batterySymbol(_ percent: Int) -> String {
    if percent >= 88 { return "battery.100" }
    if percent >= 63 { return "battery.75" }
    if percent >= 38 { return "battery.50" }
    if percent >= 13 { return "battery.25" }
    return "battery.0"
}

func weatherSymbol(_ code: Int?) -> String {
    guard let code = code else { return "cloud" }
    switch code {
    case 0: return "sun.max.fill"
    case 1, 2: return "cloud.sun.fill"
    case 3: return "cloud.fill"
    case 45, 48: return "cloud.fog.fill"
    case 51...57, 61...67, 80...82: return "cloud.rain.fill"
    case 71...77, 85, 86: return "cloud.snow.fill"
    case 95...99: return "cloud.bolt.rain.fill"
    default: return "cloud.fill"
    }
}


/// Map a WWO weather code (wttr.in) onto the WMO code space used by weatherSymbol(_:).
func wmoCode(fromWWO code: Int) -> Int {
    switch code {
    case 113: return 0
    case 116: return 2
    case 119, 122: return 3
    case 143, 248, 260: return 45
    case 176, 263, 266, 281, 284, 293, 296, 299, 302, 305, 308, 311, 314, 353, 356, 359: return 61
    case 179, 182, 185, 227, 230, 320, 323, 326, 329, 332, 335, 338, 368, 371, 374, 377: return 71
    case 200, 386, 389, 392, 395: return 95
    default: return 3
    }
}

/// Compact transfer-rate label: 812B / 34K / 1.2M. Kept tiny on purpose - it sits in the bar.
func shortTokenText(_ value: Int) -> String {
    let v = Double(value)
    if v >= 1_000_000 { return String(format: "%.2fM", v / 1_000_000) }
    if v >= 1_000 { return String(format: "%.1fk", v / 1_000) }
    return "\(value)"
}

func speedText(_ bytesPerSecond: Double) -> String {
    let value = bytesPerSecond.isFinite ? max(0, bytesPerSecond) : 0
    if value < 1024 { return "\(Int(value.rounded()))B" }
    if value < 1024 * 1024 { return String(format: "%.0fK", value / 1024) }
    return String(format: "%.1fM", value / (1024 * 1024))
}
func elapsedString(since date: Date) -> String {
    let s = max(0, Int(Date().timeIntervalSince(date)))
    return String(format: "%02d:%02d", s / 60, s % 60)
}

// MARK: - Agent icon identity

/// Case-insensitive icon id for an agent title.
///
/// Brand rules stay in their original order. `claude` is matched before the
/// live-DSH default so a Claude session is not drawn as DSH. Unknown names
/// return `generic` and are not hashed onto brand icons.
func agentIconID(for agentName: String, seed: String = "", live: Bool = false) -> String {
    // Callers still pass a stable seed. It must not retarget an unknown name
    // onto Codex, Grok, WorkBuddy, DSH, or Claude.
    _ = seed
    let name = agentName.lowercased()
    if name.contains("codex") || name.contains("chatgpt") || name.contains("openai") { return "codex" }
    if name.contains("grok") { return "grok" }
    if name.contains("workbuddy") || name.contains("work buddy") { return "workbuddy" }
    if name.contains("claude") { return "claude" }
    if live { return "dsh" }
    if name.contains("dsh") || name.contains("deepseek") || name.contains("harness") { return "dsh" }
    if name.contains("codeisland") || name.contains("island") { return "island" }
    if name.contains("hermes") { return "bolt" }
    if name.contains("review") || name.contains("doc") { return "magnifier" }
    if name.contains("test") || name.contains("build") || name.contains("bash") { return "flask" }
    return "generic"
}

/// Playback interval for the frame set currently on screen.
///
/// A manifest `suggestedIntervalSec` wins when that set provides one, so an
/// idle-only delivery shares the idle cadence for every status. Otherwise the
/// historical per-status intervals remain: running 0.45, waiting 0.70,
/// done 1.70, failed 1.20.
func agentIconInterval(forStatus status: String, suggestedIntervalSec: Double?) -> Double {
    if let suggested = suggestedIntervalSec, suggested.isFinite, suggested > 0 {
        return suggested
    }
    switch status {
    case "running": return 0.45
    case "waiting": return 0.70
    case "done": return 1.70
    case "failed": return 1.20
    default: return 0.70
    }
}

/// Phase offset used by both PNG and character-grid avatars so neighbouring
/// icons do not advance on the same tick.
func agentIconFrameIndex(time: Double, interval: Double, frameCount: Int, phase: Int) -> Int {
    guard frameCount > 0, interval > 0, time.isFinite, interval.isFinite else { return 0 }
    let shifted = time + Double(phase) * 0.31
    guard shifted.isFinite else { return 0 }
    return abs(Int(shifted / interval)) % frameCount
}

let logHandle: FileHandle? = {
    let path = "/tmp/agentbar.log"
    // Keep the log bounded: rotate once at startup when it grows past 2 MB.
    if let size = try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int,
       size > 2 * 1024 * 1024 {
        try? FileManager.default.removeItem(atPath: path + ".1")
        try? FileManager.default.moveItem(atPath: path, toPath: path + ".1")
    }
    FileManager.default.createFile(atPath: path, contents: nil)
    return FileHandle(forWritingAtPath: path)
}()

let logFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f
}()

func dlog(_ message: String) {
    let line = "[\(logFormatter.string(from: Date()))] " + message
    print(line)
    fflush(stdout)
    if let handle = logHandle, let data = (line + "\n").data(using: .utf8) {
        handle.seekToEndOfFile()
        handle.write(data)
    }
}

// MARK: - Rail layout constants (shared by SwiftUI and mouse hit-testing)

let railLeading: CGFloat = 18
let railAvatarSize: CGFloat = 23
let railSpacing: CGFloat = 6
/// Width of the "+N" badge shown when more than 5 agents are active.
let railOverflowWidth: CGFloat = 24
var lastRailLogAt = Date.distantPast

final class RailLayout {
    var frames: [String: CGRect] = [:]
}

struct RailFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

func railFrameReader(_ key: String) -> some View {
    GeometryReader { proxy in
        Color.clear.preference(key: RailFramePreferenceKey.self, value: [key: proxy.frame(in: .named("rail"))])
    }
}

// MARK: - Demo model

