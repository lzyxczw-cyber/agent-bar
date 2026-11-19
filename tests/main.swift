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

// Plugged-in is separate from the level glyph. A full pack on AC is not charging,
// and macOS 14 has no partial battery.N.bolt symbol (only battery.100.bolt).
check(
    batteryIndicator(percent: 100, acPower: true, charging: false)
        == BatteryIndicator(levelSymbol: "battery.100", powerSymbol: "bolt.fill"),
    "full, plugged in, not charging"
)
check(
    batteryIndicator(percent: 100, acPower: false, charging: false)
        == BatteryIndicator(levelSymbol: "battery.100", powerSymbol: nil),
    "full on battery"
)
check(
    batteryIndicator(percent: 64, acPower: true, charging: true)
        == BatteryIndicator(levelSymbol: "battery.75", powerSymbol: "bolt.fill"),
    "charging keeps the level glyph"
)
check(
    batteryIndicator(percent: 87, acPower: true, charging: false).levelSymbol == "battery.75",
    "plugged-in still uses the 87 boundary"
)
check(
    batteryIndicator(percent: 40, acPower: false, charging: true)
        == BatteryIndicator(levelSymbol: "battery.50", powerSymbol: "bolt.fill"),
    "charging implies external power"
)
check(
    batteryIndicator(percent: 10, acPower: false, charging: false)
        == BatteryIndicator(levelSymbol: "battery.0", powerSymbol: nil),
    "low on battery"
)
check(
    batteryIndicator(percent: 50, acPower: true, charging: true).powerSymbol == "bolt.fill",
    "plugged-in mark is bolt.fill"
)

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
check(agentIconInterval(forStatus: "idle", suggestedIntervalSec: nil) == 0.70, "idle cadence")
check(agentIconInterval(forStatus: "other", suggestedIntervalSec: nil) == 0.70, "unknown status fallback")

// Idle is its own feed state. Unknown values must not become a finished round.
check(canonicalAgentFeedStatus(nil) == "idle", "nil feed is idle")
check(canonicalAgentFeedStatus("") == "idle", "blank feed is idle")
check(canonicalAgentFeedStatus("  idle ") == "idle", "idle token")
check(canonicalAgentFeedStatus("IDLE") == "idle", "idle case")
check(canonicalAgentFeedStatus("unknown") == "idle", "unknown feed is idle")
check(canonicalAgentFeedStatus("completed") == "idle", "completed is not the done token")
check(canonicalAgentFeedStatus("done") == "done", "explicit done")
check(canonicalAgentFeedStatus(" DONE ") == "done", "done case")
check(canonicalAgentFeedStatus("running") == "running", "running token")
check(canonicalAgentFeedStatus("approval") == "waiting", "approval token")
check(canonicalAgentFeedStatus("waiting") == "waiting", "waiting token")
check(canonicalAgentFeedStatus("failed") == "failed", "failed token")
check(canonicalAgentFeedStatus("idle") != "done", "idle is not completed")

let idlePaint = agentStatusPaint("idle")
let runningPaint = agentStatusPaint("running")
let donePaint = agentStatusPaint("done")
let waitingPaint = agentStatusPaint("waiting")
let failedPaint = agentStatusPaint("failed")
let idleSpread = max(idlePaint.red, idlePaint.green, idlePaint.blue) - min(idlePaint.red, idlePaint.green, idlePaint.blue)
check(idlePaint != runningPaint && idlePaint != donePaint && runningPaint != donePaint, "three main paints differ")
check(idleSpread < 0.08, "idle reads as gray")
check(idlePaint.red > 0.5 && idlePaint.green > 0.5 && idlePaint.blue > 0.5, "idle gray is visible")
check(runningPaint.blue > runningPaint.red && runningPaint.blue > runningPaint.green, "running is blue")
check(donePaint.green > donePaint.red && donePaint.green > donePaint.blue, "done is green")
check(waitingPaint == AgentStatusPaint(red: 1.00, green: 0.72, blue: 0.28), "waiting stays orange")
check(failedPaint == AgentStatusPaint(red: 1.00, green: 0.44, blue: 0.44), "failed stays red")
check(runningPaint == AgentStatusPaint(red: 0.36, green: 0.78, blue: 1.00), "running blue unchanged")
check(donePaint == AgentStatusPaint(red: 0.36, green: 0.86, blue: 0.60), "done green unchanged")

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
case .failure(let error):
    check(false, "single select should succeed (\(error.message))")
}
switch buildQuestionAnswers(questions: [single], selections: [:], customText: ["q1": " 面板 "]) {
case .success(let answers):
    check(answers == [QuestionAnswer(id: "q1", selected: [], custom: "面板")], "custom answer")
case .failure(let error):
    check(false, "custom should succeed (\(error.message))")
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
case .failure(let error):
    check(false, "approval option should succeed (\(error.message))")
}
switch buildQuestionAnswers(questions: [single], selections: [:], customText: [:]) {
case .success:
    check(false, "empty answer must fail")
case .failure(let error):
    check(error.message == "请回答所有问题", "empty answer message (\(error.message))")
}

// Release versions. Only stable x.y.z counts.
check(parseReleaseVersion("v0.3.5") == ReleaseVersion(major: 0, minor: 3, patch: 5), "parse v0.3.5")
check(parseReleaseVersion("0.3.4") == ReleaseVersion(major: 0, minor: 3, patch: 4), "parse bare version")
check(parseReleaseVersion("0.3.5-beta") == nil, "reject prerelease suffix")
check(parseReleaseVersion("0.3") == nil, "reject short version")
check(parseReleaseVersion("v0.3.5 ") == ReleaseVersion(major: 0, minor: 3, patch: 5), "trim version")
check(ReleaseVersion(major: 0, minor: 3, patch: 5) > ReleaseVersion(major: 0, minor: 3, patch: 4), "0.3.5 is newer")
check(!(ReleaseVersion(major: 0, minor: 3, patch: 4) > ReleaseVersion(major: 0, minor: 3, patch: 4)), "equal is not newer")
check(gitHubLatestReleaseURL() == "https://api.github.com/repos/lzyxczw-cyber/agent-bar/releases/latest", "latest release endpoint")

let releaseFixture = """
{"tag_name":"v0.3.6","draft":false,"prerelease":false,"html_url":"https://evil.example/release","assets":[{"name":"Agent-Bar-0.3.6.dmg","browser_download_url":"https://github.com/lzyxczw-cyber/agent-bar/releases/download/v0.3.6/Agent-Bar-0.3.6.dmg"},{"name":"Agent-Bar-0.3.6.dmg.sha256","browser_download_url":"https://github.com/lzyxczw-cyber/agent-bar/releases/download/v0.3.6/Agent-Bar-0.3.6.dmg.sha256"}]}
""".data(using: .utf8)!
let parsedRelease = parseGitHubLatestRelease(releaseFixture)
check(parsedRelease?.tagName == "v0.3.6", "parse tag")
check(parsedRelease?.assets.count == 2, "parse both assets")
let newer = evaluateReleaseUpdate(current: "0.3.5", release: parsedRelease!)
if case .available(let latest, let page, let dmg) = newer {
    check(latest == "0.3.6", "available version")
    check(page == "https://github.com/lzyxczw-cyber/agent-bar/releases/tag/v0.3.6", "page is the official tag, not html_url")
    check(dmg == "https://github.com/lzyxczw-cyber/agent-bar/releases/download/v0.3.6/Agent-Bar-0.3.6.dmg", "official dmg")
    check(isTrustedGitHubReleaseURL(page), "page is trusted")
    check(isTrustedGitHubReleaseURL(dmg!), "dmg is trusted")
} else {
    check(false, "newer release should be available")
}
check(!isTrustedGitHubReleaseURL("https://evil.example/Agent-Bar-0.3.6.dmg"), "reject foreign host")
check(!isTrustedGitHubReleaseURL("http://github.com/lzyxczw-cyber/agent-bar/releases/tag/v0.3.6"), "reject http")

let same = evaluateReleaseUpdate(current: "0.3.6", release: parsedRelease!)
if case .upToDate(let latest) = same {
    check(latest == "0.3.6", "same version is up to date")
} else {
    check(false, "same version should be up to date")
}
let older = evaluateReleaseUpdate(current: "0.4.0", release: parsedRelease!)
if case .upToDate = older {
    check(true, "newer local build is up to date")
} else {
    check(false, "local build ahead of GitHub is up to date")
}

var prerelease = parsedRelease!
prerelease.prerelease = true
if case .upToDate = evaluateReleaseUpdate(current: "0.3.5", release: prerelease) {
    check(true, "prerelease is not offered")
} else {
    check(false, "prerelease must not be offered")
}
var mismatched = parsedRelease!
mismatched.assets = [GitHubReleaseAsset(name: "Agent-Bar-0.3.6.dmg", browserDownloadURL: "https://example.com/Agent-Bar-0.3.6.dmg")]
if case .available(_, let page, let dmg) = evaluateReleaseUpdate(current: "0.3.5", release: mismatched) {
    check(page.hasPrefix("https://github.com/lzyxczw-cyber/agent-bar/releases/tag/"), "mismatched asset still has a release page")
    check(dmg == nil, "mismatched asset does not become a download")
} else {
    check(false, "mismatched asset still announces the release")
}
check(parseGitHubLatestRelease(Data("{\"message\":\"not found\"}".utf8)) == nil, "error payload is not a release")

let now = Date(timeIntervalSince1970: 1_700_000_000)
check(updatePollDue(lastCheckedAt: nil, now: now, minimumInterval: updatePollInterval), "first check is due")
check(!updatePollDue(lastCheckedAt: now.addingTimeInterval(-3600), now: now, minimumInterval: updatePollInterval), "one hour is not due")
check(updatePollDue(lastCheckedAt: now.addingTimeInterval(-updatePollInterval), now: now, minimumInterval: updatePollInterval), "interval boundary is due")

let available = UpdatePhase.available(
    latest: "0.3.6",
    pageURL: "https://github.com/lzyxczw-cyber/agent-bar/releases/tag/v0.3.6",
    dmgURL: "https://github.com/lzyxczw-cyber/agent-bar/releases/download/v0.3.6/Agent-Bar-0.3.6.dmg"
)
if case .available(let version, _, _) = updateBanner(phase: available, dismissedVersion: "", snoozedVersion: "", snoozedUntil: nil, now: now) {
    check(version == "0.3.6", "banner shows the new version")
} else {
    check(false, "banner should show")
}
check(
    updateBanner(phase: available, dismissedVersion: "0.3.6", snoozedVersion: "", snoozedUntil: nil, now: now) == .hidden,
    "dismissed version stays hidden"
)
check(
    updateBanner(phase: available, dismissedVersion: "0.3.5", snoozedVersion: "0.3.6", snoozedUntil: now.addingTimeInterval(60), now: now) == .hidden,
    "snoozed version stays hidden"
)
if case .available = updateBanner(phase: available, dismissedVersion: "", snoozedVersion: "0.3.6", snoozedUntil: now.addingTimeInterval(-1), now: now) {
    check(true, "expired snooze shows again")
} else {
    check(false, "expired snooze should show")
}
if case .available = updateBanner(phase: available, dismissedVersion: "", snoozedVersion: "0.3.5", snoozedUntil: now.addingTimeInterval(3600), now: now) {
    check(true, "snooze for another version does not hide this one")
} else {
    check(false, "other snooze should not hide")
}
check(updateBanner(phase: .failed(message: "网络不可用，没有连上 GitHub"), dismissedVersion: "", snoozedVersion: "", snoozedUntil: nil, now: now) == .hidden, "failure is not a bar notice")
check(updateBanner(phase: .upToDate(latest: "0.3.5"), dismissedVersion: "", snoozedVersion: "", snoozedUntil: nil, now: now) == .hidden, "up to date has no banner")
check(updateFailureMessage(statusCode: nil) == "网络不可用，没有连上 GitHub", "network failure copy")
check(updateFailureMessage(statusCode: 403) == "GitHub 暂时限制了请求，请稍后再试", "rate limit copy")
check(updateFailureMessage(statusCode: 500) == "GitHub 返回 HTTP 500", "http failure copy")
check(updateSettingsDetail(.noRelease).contains("还没有公开的 Release"), "no release copy")

// Notification guide: one card until dismissed, sound-only when not authorized.
check(notificationGuide(permission: .notDetermined, inAppEnabled: true, promptDismissed: false, settingsHintDismissed: false) == .offerSystemPrompt, "first prompt")
check(notificationGuide(permission: .notDetermined, inAppEnabled: true, promptDismissed: true, settingsHintDismissed: false) == .none, "dismissed prompt stays quiet")
check(notificationGuide(permission: .denied, inAppEnabled: true, promptDismissed: true, settingsHintDismissed: false) == .offerSystemSettings, "denied explains settings")
check(notificationGuide(permission: .denied, inAppEnabled: true, promptDismissed: false, settingsHintDismissed: true) == .none, "dismissed settings hint stays quiet")
check(notificationGuide(permission: .authorized, inAppEnabled: true, promptDismissed: false, settingsHintDismissed: false) == .none, "authorized does not nag")
check(notificationGuide(permission: .notDetermined, inAppEnabled: false, promptDismissed: false, settingsHintDismissed: false) == .none, "toggle off does not nag")
check(notificationGuide(permission: .unavailable, inAppEnabled: true, promptDismissed: false, settingsHintDismissed: false) == .none, "unbundled does not nag")
check(!notificationDeliversBanner(permission: .denied, inAppEnabled: true), "denied is sound only")
check(!notificationDeliversBanner(permission: .notDetermined, inAppEnabled: true), "undecided is sound only")
check(notificationDeliversBanner(permission: .authorized, inAppEnabled: true), "authorized delivers a banner")
check(!notificationDeliversBanner(permission: .authorized, inAppEnabled: false), "toggle off skips the banner")
check(notificationSettingsDetail(.denied).contains("提示音"), "denied copy keeps the sound fallback")
check(notificationPermission(from: .denied) == .denied, "map denied")
check(notificationPermission(from: .authorized) == .authorized, "map authorized")
check(notificationPermission(from: .provisional) == .authorized, "provisional counts as authorized")
check(notificationPermission(from: .notDetermined) == .notDetermined, "map not determined")

let multi = AgentQuestion(
    id: "m", prompt: "哪些？", header: nil, detail: nil,
    multiSelect: true, allowCustom: true, intent: nil,
    options: [
        AgentQuestionOption(id: "m#0", label: "左", detail: nil, display: nil),
        AgentQuestionOption(id: "m#1", label: "右", detail: nil, display: nil)
    ]
)
switch buildQuestionAnswers(questions: [multi], selections: ["m": ["右", "左"]], customText: [:]) {
case .success(let answers):
    check(answers == [QuestionAnswer(id: "m", selected: ["左", "右"], custom: nil)], "multi select keeps option order")
case .failure(let error):
    check(false, "multi select should succeed (\(error.message))")
}
switch buildQuestionAnswers(questions: [single], selections: ["q1": ["不存在"]], customText: [:]) {
case .success:
    check(false, "unknown option must fail")
case .failure(let error):
    check(error.message == "选项已变化，请重新选择", "unknown option message (\(error.message))")
}
let tooLong = String(repeating: "啊", count: 2001)
switch buildQuestionAnswers(questions: [single], selections: [:], customText: ["q1": tooLong]) {
case .success:
    check(false, "long custom must fail")
case .failure(let error):
    check(error.message == "回答太长", "long custom message (\(error.message))")
}
switch buildQuestionAnswers(questions: [], selections: [:], customText: [:]) {
case .success:
    check(false, "empty question list must fail")
case .failure(let error):
    check(error.message == "没有可回答的问题", "empty question message (\(error.message))")
}

for name in ["Codex", "Claude Code", "WorkBuddy", "work buddy", "Grok Bot", "Hermes", "my-cli"] {
    check(!canAnswerExternalApproval(agentName: name), "\(name) stays read-only")
    check(!externalApprovalReadOnlyReason(agentName: name).isEmpty, "\(name) explains why it is read-only")
}
check(externalApprovalReadOnlyReason(agentName: "Codex").contains("app-server"), "codex names the real protocol")
check(externalApprovalReadOnlyReason(agentName: "Claude Code").contains("PreToolUse"), "claude names the hook")
check(externalApprovalReadOnlyReason(agentName: "WorkBuddy").contains("trace"), "workbuddy names traces")
check(externalApprovalReadOnlyReason(agentName: "Grok Bot").contains("不能代答"), "grok stays explicit")
check(externalApprovalReadOnlyReason(agentName: "Hermes").contains("state.db"), "hermes names state.db")
check(externalApprovalReadOnlyReason(agentName: "my-cli").contains("不代答"), "generic report stays explicit")

check(railPillWidth(available: 400, visibleCount: 2, totalCount: 2) == CGFloat(340), "pill uses the free width")
check(railPillWidth(available: 200, visibleCount: 5, totalCount: 6) == CGFloat(160), "pill does not shrink below 160")
check(railPillWidth(available: 100, visibleCount: 1, totalCount: 1) == CGFloat(160), "narrow wing still floors at 160")
let frames = predictedRailFrames(agentIDs: ["a", "b"], selectedID: "a", totalCount: 2, availableWidth: 400, barHeight: 30)
check(frames["icon:a"] == CGRect(x: 0, y: 3.5, width: 23, height: 23), "first icon frame")
check(frames["pill:a"] == CGRect(x: 29, y: 3.5, width: 340, height: 23), "pill follows its icon")
check(frames["icon:b"] == CGRect(x: 375, y: 3.5, width: 23, height: 23), "next icon follows the pill")
check(frames["overflow"] == nil, "no overflow chip for two agents")
let crowded = predictedRailFrames(agentIDs: ["a", "b", "c", "d", "e", "f"], selectedID: "a", totalCount: 6, availableWidth: 200, barHeight: 30)
check(crowded["overflow"] != nil, "sixth agent adds an overflow frame")
check(crowded["icon:f"] == nil, "the sixth icon is not on the rail")
check(crowded["pill:a"]?.width == CGFloat(160), "crowded pill uses the floor")

// Claude approval helpers.
let pendingJSON = #"{"schema":1,"id":"abc","nonce":"n1","sessionId":"s1","cwd":"/Users/x/proj","tool":"Bash","command":"rm -rf build","createdAt":1763000000000}"#
let pending = parseClaudePendingApproval(Data(pendingJSON.utf8))
check(pending?.id == "abc", "parse pending id")
check(pending?.command == "rm -rf build", "parse pending command")
check(parseClaudePendingApproval(Data("{}".utf8)) == nil, "reject incomplete pending")
check(claudeApprovalId("abc") == "claude:abc", "approval id prefix")
check(claudeApprovalRequestId("claude:abc") == "abc", "strip approval prefix")
check(claudeApprovalRequestId("bridge-123") == nil, "non-claude id is not routed")
check(claudeApprovalRequestId(nil) == nil, "nil id is not routed")
check(claudeApprovalDecision("allowed-once") == "allow", "allow mapping")
check(claudeApprovalDecision("rejected") == "deny", "deny mapping")
check(claudeApprovalDecision("maybe") == nil, "unknown decision is rejected")
check(claudeApprovalCanAnswer("claude:abc"), "claude approval is answerable")
check(!claudeApprovalCanAnswer("bridge-123"), "other approvals stay read-only")

let pendingOlder = ClaudePendingApproval(id: "1", nonce: "a", sessionId: "s1", cwd: "/p", tool: "Bash", command: "ls", createdAt: 1)
let pendingNewer = ClaudePendingApproval(id: "2", nonce: "b", sessionId: "s2", cwd: "/q", tool: "Bash", command: "pwd", createdAt: 2)
let picked = selectClaudePendingApproval([pendingOlder, pendingNewer])
check(picked?.approval.id == "2", "newest pending wins")
check(picked?.extra == 1, "extra pending count")
check(selectClaudePendingApproval([]) == nil, "empty selection")
check(claudeApprovalNotice(project: "proj", extra: 2) == "proj · 还有 2 个待审批", "approval notice")
let decisionData = claudeApprovalDecisionJSON(pendingNewer, decision: "deny", at: Date(timeIntervalSince1970: 10))
let decisionObject = decisionData.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
check(decisionObject?["id"] as? String == "2", "decision payload id")
check(decisionObject?["nonce"] as? String == "b", "decision payload nonce")
check(decisionObject?["decision"] as? String == "deny", "decision payload decision")

print("\(checks - failures)/\(checks) checks passed")
exit(failures == 0 ? 0 : 1)
