import AppKit
import Combine
import Foundation
import UserNotifications

/// Checks the latest GitHub Release for this repo and remembers dismiss / snooze.
/// It never downloads over the running app.
final class UpdateCenter: ObservableObject {
    @Published private(set) var phase: UpdatePhase = .idle
    @Published private(set) var dismissedVersion: String = ""
    @Published private(set) var snoozedVersion: String = ""
    @Published private(set) var snoozedUntil: Date?
    @Published private(set) var checkedAt: Date?

    var currentVersion: String

    private var timer: Timer?
    private var task: URLSessionDataTask?
    private var generation = 0
    private let defaults: UserDefaults
    private let session: URLSession

    init(defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.defaults = defaults
        self.session = session
        currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        dismissedVersion = defaults.string(forKey: Keys.dismissed) ?? ""
        snoozedVersion = defaults.string(forKey: Keys.snoozedVersion) ?? ""
        snoozedUntil = defaults.object(forKey: Keys.snoozedUntil) as? Date
        checkedAt = defaults.object(forKey: Keys.checkedAt) as? Date
    }

    func start() {
        if let restored = restoredPhase() {
            phase = restored
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            self?.checkIfDue()
        }
        let timer = Timer(timeInterval: updatePollInterval, repeats: true) { [weak self] _ in
            self?.checkIfDue()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func checkIfDue() {
        guard updatePollDue(lastCheckedAt: checkedAt, now: Date(), minimumInterval: updatePollInterval) else { return }
        check(manual: false)
    }

    func checkNow() {
        check(manual: true)
    }

    func banner(now: Date = Date()) -> UpdateBanner {
        updateBanner(
            phase: phase,
            dismissedVersion: dismissedVersion,
            snoozedVersion: snoozedVersion,
            snoozedUntil: snoozedUntil,
            now: now
        )
    }

    func dismissCurrent() {
        guard case .available(let latest, _, _) = phase else { return }
        dismissedVersion = latest
        defaults.set(latest, forKey: Keys.dismissed)
    }

    func snoozeCurrent() {
        guard case .available(let latest, _, _) = phase else { return }
        let until = Date().addingTimeInterval(updateSnoozeInterval)
        snoozedVersion = latest
        snoozedUntil = until
        defaults.set(latest, forKey: Keys.snoozedVersion)
        defaults.set(until, forKey: Keys.snoozedUntil)
    }

    func openReleasePage() {
        guard case .available(_, let pageURL, _) = phase else { return }
        openTrustedReleaseURL(pageURL)
    }

    func downloadDMG() {
        guard case .available(_, _, let dmgURL) = phase, let dmgURL else { return }
        openTrustedReleaseURL(dmgURL)
    }

    private func check(manual: Bool) {
        generation += 1
        let token = generation
        task?.cancel()
        switch phase {
        case .available:
            break
        default:
            phase = .checking
        }
        guard let url = URL(string: gitHubLatestReleaseURL()) else {
            phase = .failed(message: "更新地址不可用")
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("AgentBar/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let manualCheck = manual
        task = session.dataTask(with: request) { [weak self] data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard self.generation == token else { return }
                self.finishCheck(data: data, status: status, transportFailed: error != nil, manual: manualCheck)
            }
        }
        task?.resume()
    }

    private func finishCheck(data: Data?, status: Int?, transportFailed: Bool, manual: Bool) {
        let now = Date()
        checkedAt = now
        defaults.set(now, forKey: Keys.checkedAt)
        if transportFailed || data == nil {
            phase = .failed(message: updateFailureMessage(statusCode: nil))
            dlog("[agentbar] update check failed: network")
            return
        }
        if status == 404 {
            phase = .noRelease
            dlog("[agentbar] update check: no public release")
            return
        }
        guard status == 200, let data, let release = parseGitHubLatestRelease(data) else {
            phase = .failed(message: updateFailureMessage(statusCode: status))
            dlog("[agentbar] update check failed: http \(status ?? 0)")
            return
        }
        let next = evaluateReleaseUpdate(current: currentVersion, release: release)
        phase = next
        if case .available(let latest, let pageURL, let dmgURL) = next {
            defaults.set(latest, forKey: Keys.cachedLatest)
            defaults.set(pageURL, forKey: Keys.cachedPage)
            defaults.set(dmgURL ?? "", forKey: Keys.cachedDMG)
            dlog("[agentbar] update available \(latest) manual=\(manualCheckLabel(manual))")
        } else if case .upToDate(let latest) = next {
            defaults.set(latest, forKey: Keys.cachedLatest)
            dlog("[agentbar] update up to date \(latest)")
        } else {
            dlog("[agentbar] update check finished \(String(describing: next))")
        }
    }

    private func restoredPhase() -> UpdatePhase? {
        guard let cached = defaults.string(forKey: Keys.cachedLatest),
              let latest = parseReleaseVersion(cached),
              let current = parseReleaseVersion(currentVersion) else { return nil }
        if latest > current {
            let page = defaults.string(forKey: Keys.cachedPage) ?? officialReleasePageURL(latest)
            guard isTrustedGitHubReleaseURL(page) else { return nil }
            let storedDMG = defaults.string(forKey: Keys.cachedDMG) ?? ""
            let dmg = storedDMG == officialDMGURL(latest) ? storedDMG : nil
            return .available(latest: latest.label, pageURL: officialReleasePageURL(latest), dmgURL: dmg)
        }
        return .upToDate(latest: latest.label)
    }

    private func manualCheckLabel(_ manual: Bool) -> String {
        manual ? "yes" : "no"
    }

    private enum Keys {
        static let checkedAt = "AgentBarUpdateLastChecked"
        static let dismissed = "AgentBarUpdateDismissedVersion"
        static let snoozedVersion = "AgentBarUpdateSnoozedVersion"
        static let snoozedUntil = "AgentBarUpdateSnoozedUntil"
        static let cachedLatest = "AgentBarUpdateCachedLatest"
        static let cachedPage = "AgentBarUpdateCachedPage"
        static let cachedDMG = "AgentBarUpdateCachedDMG"
    }
}

final class NotificationAuthCenter: ObservableObject {
    @Published private(set) var permission: NotificationPermission = .unknown

    func markUnavailable() {
        permission = .unavailable
    }

    func refresh() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let mapped = notificationPermission(from: settings.authorizationStatus)
            DispatchQueue.main.async {
                self.permission = mapped
            }
        }
    }

    func requestPermission() {
        NSApp.activate(ignoringOtherApps: true)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            let failed = error == nil ? "" : " error"
            dlog("[agentbar] notifications authorized=" + String(granted) + failed)
            DispatchQueue.main.async {
                self.refresh()
            }
        }
    }

    func openSystemSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.notifications"
        ]
        for raw in candidates {
            guard let url = URL(string: raw) else { continue }
            if NSWorkspace.shared.open(url) {
                dlog("[agentbar] opened notification settings")
                return
            }
        }
        dlog("[agentbar] could not open notification settings")
    }
}

func openTrustedReleaseURL(_ raw: String) {
    guard isTrustedGitHubReleaseURL(raw), let url = URL(string: raw) else { return }
    NSWorkspace.shared.open(url)
}
