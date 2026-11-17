import Foundation

var failures = 0
var checks = 0

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() {
        failures += 1
        print("FAIL: \(message)")
    }
}

// Battery tier boundaries.
check(batterySymbol(100) == "battery.100", "battery 100")
check(batterySymbol(88) == "battery.100", "battery 88 boundary")
check(batterySymbol(87) == "battery.75", "battery 87")
check(batterySymbol(63) == "battery.75", "battery 63 boundary")
check(batterySymbol(62) == "battery.50", "battery 62")
check(batterySymbol(38) == "battery.50", "battery 38 boundary")
check(batterySymbol(37) == "battery.25", "battery 37")
check(batterySymbol(13) == "battery.25", "battery 13 boundary")
check(batterySymbol(12) == "battery.0", "battery 12")
check(batterySymbol(0) == "battery.0", "battery 0")

// Weather code mapping: WMO direct + wttr.in WWO conversion.
check(weatherSymbol(nil) == "cloud", "weather nil")
check(weatherSymbol(0) == "sun.max.fill", "weather clear")
check(weatherSymbol(2) == "cloud.sun.fill", "weather partly cloudy")
check(weatherSymbol(3) == "cloud.fill", "weather overcast")
check(weatherSymbol(45) == "cloud.fog.fill", "weather fog")
check(weatherSymbol(61) == "cloud.rain.fill", "weather rain")
check(weatherSymbol(71) == "cloud.snow.fill", "weather snow")
check(weatherSymbol(95) == "cloud.bolt.rain.fill", "weather thunder")
check(weatherSymbol(999) == "cloud.fill", "weather unknown")
check(wmoCode(fromWWO: 113) == 0, "WWO clear")
check(wmoCode(fromWWO: 116) == 2, "WWO partly cloudy")
check(wmoCode(fromWWO: 122) == 3, "WWO overcast")
check(wmoCode(fromWWO: 143) == 45, "WWO fog")
check(wmoCode(fromWWO: 296) == 61, "WWO rain")
check(wmoCode(fromWWO: 326) == 71, "WWO snow")
check(wmoCode(fromWWO: 389) == 95, "WWO thunder")
check(wmoCode(fromWWO: 9999) == 3, "WWO unknown fallback")

// Token formatting.
check(shortTokenText(0) == "0", "tokens 0")
check(shortTokenText(999) == "999", "tokens 999")
check(shortTokenText(1_000) == "1.0k", "tokens 1k")
check(shortTokenText(1_500) == "1.5k", "tokens 1.5k")
check(shortTokenText(999_999) == "1000.0k", "tokens below million")
check(shortTokenText(1_000_000) == "1.00M", "tokens 1M")
check(shortTokenText(1_234_567) == "1.23M", "tokens 1.23M")

// Speed formatting and sanitising.
check(speedText(0) == "0B", "speed 0")
check(speedText(512) == "512B", "speed bytes")
check(speedText(1023) == "1023B", "speed 1023")
check(speedText(1024) == "1K", "speed 1K")
check(speedText(1536) == "2K", "speed rounds to 2K")
check(speedText(1_048_576) == "1.0M", "speed 1M")
check(speedText(1_572_864) == "1.5M", "speed 1.5M")
check(speedText(-10) == "0B", "speed negative")
check(speedText(.infinity) == "0B", "speed infinite")
check(speedText(.nan) == "0B", "speed NaN")

// CJK detection used by translation / labels.
check(containsCJK("你好"), "CJK Chinese")
check(containsCJK("hello 世界"), "CJK mixed")
check(!containsCJK("hello world"), "CJK ASCII")

// Elapsed time is at least zero and follows mm:ss.
let elapsed = elapsedString(since: Date().addingTimeInterval(-65))
check(elapsed == "01:05" || elapsed == "01:04", "elapsed mm:ss (\(elapsed))")
check(elapsedString(since: Date().addingTimeInterval(30)) == "00:00", "elapsed future clamp")

// Agent icon identity. Order is part of the contract.
check(agentIconID(for: "Codex") == "codex", "codex name")
check(agentIconID(for: "CHATGPT") == "codex", "chatgpt name")
check(agentIconID(for: "OpenAI") == "codex", "openai name")
check(agentIconID(for: "Codex", live: true) == "codex", "codex claimed before live")
check(agentIconID(for: "openai documentation") == "codex", "openai before doc")
check(agentIconID(for: "Grok Bot") == "grok", "grok name")
check(agentIconID(for: "WorkBuddy") == "workbuddy", "workbuddy name")
check(agentIconID(for: "work buddy") == "workbuddy", "work buddy phrase")
check(agentIconID(for: "WORK BUDDY") == "workbuddy", "work buddy case")
check(agentIconID(for: "Claude Code", live: true) == "claude", "claude before live DSH")
check(agentIconID(for: "claude harness") == "claude", "claude before harness")
check(agentIconID(for: "Cursor", live: true) == "dsh", "live default is dsh")
check(agentIconID(for: "", live: true) == "dsh", "empty live is dsh")
check(agentIconID(for: "DeepSeek Harness") == "dsh", "deepseek name")
check(agentIconID(for: "my-dsh-session") == "dsh", "dsh substring")
check(agentIconID(for: "harness") == "dsh", "harness name")
check(agentIconID(for: "CodeIsland") == "island", "codeisland name")
check(agentIconID(for: "Island") == "island", "island name")
check(agentIconID(for: "island review") == "island", "island before review")
check(agentIconID(for: "Hermes") == "bolt", "hermes name")
check(agentIconID(for: "hermes test") == "bolt", "hermes before test")
check(agentIconID(for: "code review") == "magnifier", "review name")
check(agentIconID(for: "docs") == "magnifier", "doc name")
check(agentIconID(for: "test doc") == "magnifier", "doc before test")
check(agentIconID(for: "swift test") == "flask", "test name")
check(agentIconID(for: "swift build") == "flask", "build name")
check(agentIconID(for: "bash") == "flask", "bash name")
check(agentIconID(for: "Cursor") == "generic", "unknown cursor")
check(agentIconID(for: "Gemini", seed: "abc") == "generic", "unknown gemini")
check(agentIconID(for: "Whale") == "generic", "whale is not a name match")
check(agentIconID(for: "") == "generic", "empty name")
check(agentIconID(for: "Cursor", seed: "a") == agentIconID(for: "Cursor", seed: "b"), "seed does not retarget")

let brandIDs: Set<String> = ["codex", "grok", "workbuddy", "dsh", "claude"]
for name in ["Cursor", "Gemini", "Kimi", "Agent", "Whale", "???", ""] {
    let id = agentIconID(for: name, seed: "seed-\(name)", live: false)
    check(id == "generic", "unknown \(name) stays generic (\(id))")
    check(!brandIDs.contains(id), "unknown \(name) avoids brand icons")
}

// Manifest cadence wins; the status table is only the fallback.
check(agentIconInterval(forStatus: "running", suggestedIntervalSec: 0.70) == 0.70, "suggested overrides running")
check(agentIconInterval(forStatus: "done", suggestedIntervalSec: 0.70) == 0.70, "suggested overrides done")
check(agentIconInterval(forStatus: "failed", suggestedIntervalSec: 0.70) == 0.70, "suggested overrides failed")
check(agentIconInterval(forStatus: "waiting", suggestedIntervalSec: 0.70) == 0.70, "suggested waiting")
check(agentIconInterval(forStatus: "running", suggestedIntervalSec: nil) == 0.45, "running fallback")
check(agentIconInterval(forStatus: "waiting", suggestedIntervalSec: nil) == 0.70, "waiting fallback")
check(agentIconInterval(forStatus: "done", suggestedIntervalSec: nil) == 1.70, "done fallback")
check(agentIconInterval(forStatus: "failed", suggestedIntervalSec: nil) == 1.20, "failed fallback")
check(agentIconInterval(forStatus: "running", suggestedIntervalSec: 0) == 0.45, "zero suggestion ignored")
check(agentIconInterval(forStatus: "running", suggestedIntervalSec: -1) == 0.45, "negative suggestion ignored")
check(agentIconInterval(forStatus: "done", suggestedIntervalSec: .infinity) == 1.70, "infinite suggestion ignored")
check(agentIconInterval(forStatus: "done", suggestedIntervalSec: .nan) == 1.70, "nan suggestion ignored")
check(agentIconInterval(forStatus: "other", suggestedIntervalSec: nil) == 0.70, "unknown status fallback")

check(agentIconFrameIndex(time: 0, interval: 0.70, frameCount: 4, phase: 0) == 0, "frame 0")
check(agentIconFrameIndex(time: 0.70, interval: 0.70, frameCount: 4, phase: 0) == 1, "frame 1")
check(agentIconFrameIndex(time: 2.10, interval: 0.70, frameCount: 4, phase: 0) == 3, "frame 3")
check(agentIconFrameIndex(time: 2.80, interval: 0.70, frameCount: 4, phase: 0) == 0, "frame wrap")
check(
    agentIconFrameIndex(time: 0.60, interval: 0.70, frameCount: 4, phase: 0)
        != agentIconFrameIndex(time: 0.60, interval: 0.70, frameCount: 4, phase: 1),
    "phase offsets frames"
)
check(agentIconFrameIndex(time: 1, interval: 0, frameCount: 4, phase: 0) == 0, "zero interval")
check(agentIconFrameIndex(time: 1, interval: 0.70, frameCount: 0, phase: 0) == 0, "zero frames")

// HTML is removed; markdown autolinks stay so the panel parser can see them.
check(stripHTMLTags("<b>hi</b>") == "hi", "strip bold tag")
check(stripHTMLTags("a <b class=\"x\">hi</b> b") == "a hi b", "strip attributed tag")
check(stripHTMLTags("<script>alert(1)</script>") == "alert(1)", "strip script")
check(stripHTMLTags("a < b") == "a < b", "keep bare less-than")
check(stripHTMLTags("see <https://example.com>") == "see <https://example.com>", "keep autolink")
check(stripHTMLTags("<br/>next") == "next", "strip br")

let bold = inlineThoughtAttributed("see **bold** text")
check(String(bold.characters) == "see bold text", "bold markers removed (\(String(bold.characters)))")
check(bold.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }, "bold intent")
let italic = inlineThoughtAttributed("an *italic* word")
check(italic.runs.contains { $0.inlinePresentationIntent?.contains(.emphasized) == true }, "italic intent")
let code = inlineThoughtAttributed("run `swift test` now")
check(String(code.characters) == "run swift test now", "code markers removed")
check(code.runs.contains { $0.inlinePresentationIntent?.contains(.code) == true }, "code intent")
let link = inlineThoughtAttributed("[docs](https://example.com/agent)")
check(link.runs.contains { $0.link?.absoluteString == "https://example.com/agent" }, "link attribute")
let htmlThought = inlineThoughtAttributed("a <b>bold</b> tag")
check(String(htmlThought.characters) == "a bold tag", "html stripped before markdown")
check(!htmlThought.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }, "html is not bold")

check(barModeLabel(.protocolMismatch) == "协议不匹配", "mismatch label")
check(barModeLabel(.demo) == "演示", "demo label")
check(
    barFeedMode(protocolStatus: "mismatch", isLive: false, bridgeFresh: true, bridgeAlive: true, bridgeNote: nil) == .protocolMismatch,
    "fresh mismatch is not demo"
)
check(
    barFeedMode(protocolStatus: "mismatch", isLive: true, bridgeFresh: false, bridgeAlive: true, bridgeNote: nil) == .offline,
    "stale mismatch does not count as a fresh probe"
)
check(
    barFeedMode(protocolStatus: "unavailable", isLive: false, bridgeFresh: true, bridgeAlive: false, bridgeNote: nil) == .demo,
    "missing DSH stays demo"
)
check(
    barFeedMode(protocolStatus: "ok", isLive: true, bridgeFresh: true, bridgeAlive: true, bridgeNote: nil) == .live,
    "healthy feed is live"
)
check(
    barFeedMode(protocolStatus: "ok", isLive: true, bridgeFresh: true, bridgeAlive: true, bridgeNote: "暂无活跃任务") == .offline,
    "bridge note is offline"
)

let single = AgentQuestion(
    id: "q1", prompt: "放在哪里？", header: nil, detail: nil,
    multiSelect: false, allowCustom: true, intent: nil,
    options: [AgentQuestionOption(id: "q1#0", label: "刘海", detail: nil, display: nil)]
)
switch buildQuestionAnswers(questions: [single], selections: ["q1": ["刘海"]], customText: [:]) {
case .success(let answers):
    check(answers == [QuestionAnswer(id: "q1", selected: ["刘海"], custom: nil)], "single select answer")
case .failure(let message):
    check(false, "single select should succeed (\(message))")
}
switch buildQuestionAnswers(questions: [single], selections: [:], customText: ["q1": " 面板 "]) {
case .success(let answers):
    check(answers == [QuestionAnswer(id: "q1", selected: [], custom: "面板")], "custom answer")
case .failure(let message):
    check(false, "custom should succeed (\(message))")
}
switch buildQuestionAnswers(questions: [single], selections: ["q1": ["刘海"]], customText: ["q1": "面板"]) {
case .success:
    check(false, "single select plus custom must fail")
case .failure:
    check(true, "single select conflict")
}
let locked = AgentQuestion(
    id: "perm", prompt: "Allow?", header: nil, detail: nil,
    multiSelect: false, allowCustom: false, intent: "approval",
    options: [AgentQuestionOption(id: "perm#0", label: "Allow", detail: nil, display: "允许")]
)
switch buildQuestionAnswers(questions: [locked], selections: [:], customText: ["perm": "no"]) {
case .success:
    check(false, "approval custom must fail")
case .failure:
    check(true, "approval custom rejected")
}
switch buildQuestionAnswers(questions: [locked], selections: ["perm": ["Allow"]], customText: [:]) {
case .success(let answers):
    check(answers.first?.selected == ["Allow"], "approval submits the wire label")
case .failure(let message):
    check(false, "approval option should succeed (\(message))")
}
switch buildQuestionAnswers(questions: [single], selections: [:], customText: [:]) {
case .success:
    check(false, "empty answer must fail")
case .failure:
    check(true, "empty answer rejected")
}

print("\(checks - failures)/\(checks) checks passed")
exit(failures == 0 ? 0 : 1)
