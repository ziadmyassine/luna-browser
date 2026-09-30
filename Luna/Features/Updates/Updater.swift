//
//  Updater.swift
//  Luna
//
//  Knowing when there is a newer Luna, and having it ready.
//
//  No framework and no background agent: the repo's latest GitHub release is
//  read once a day, and whenever Settings › About asks. If it is newer than
//  this build, its zip is fetched, checked and put where this bundle is
//  (`UpdateSwap`), so the next launch is the new one. Nothing relaunches on
//  its own — a page being read is not interrupted by a browser that wants to
//  be newer. Restart is a button.
//
//  Only a build the release workflow made installs anything. It stamps
//  `LunaReleaseBuild` into its Info.plist; a build made on this Mac has no
//  stamp, so it only ever says a newer one is out and links to it. Otherwise
//  a development build would replace itself with the last release the first
//  time it launched.
//

import AppKit

@MainActor
final class Updater {

    static let shared = Updater()

    enum Stage: Equatable {
        /// Not looked yet this launch.
        case idle
        case checking
        /// This is the latest.
        case current
        /// A newer one is out, and waiting for Install — or, on a build that
        /// cannot install, for Download.
        case available(UpdateRelease)
        case installing(UpdateRelease)
        /// Swapped in; it runs from the next launch.
        case ready(UpdateRelease)
        /// The last attempt failed, with what to say about it. The release is
        /// kept when there was one, so Install can be pressed again.
        case failed(UpdateRelease?, String)
    }

    /// Posted on the main queue whenever `stage` or `lastChecked` changes.
    static let didChange = Notification.Name("LunaUpdaterDidChange")

    private(set) var stage: Stage = .idle { didSet { announce() } }

    static let installKey = "updates.installOnItsOwn"
    private static let checkedKey = "updates.lastChecked"

    /// Settings › About's switch. On unless it has been turned off.
    var installsOnItsOwn: Bool {
        get { UserDefaults.standard.object(forKey: Self.installKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.installKey)
            if newValue, case let .available(release) = stage, canInstall { install(release) }
            announce()
        }
    }

    /// When the feed was last read, successfully. State, not a setting, so it
    /// is not in `SettingsDefaults`' table and "Restore all" leaves it alone.
    private(set) var lastChecked: Date? {
        get { UserDefaults.standard.object(forKey: Self.checkedKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Self.checkedKey) }
    }

    /// What this build is.
    static var version: UpdateVersion {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(UpdateVersion.init)
            ?? UpdateVersion("0")!
    }

    static var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "" }

    /// See the header.
    var canInstall: Bool { Bundle.main.object(forInfoDictionaryKey: "LunaReleaseBuild") as? Bool == true }

    private var clock: Timer?

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in UpdateSwap.sweep() }
    }

    // MARK: - When to look

    /// At launch: clears what a past swap left, looks if a day has gone by,
    /// and keeps looking every hour for as long as the app is up — a browser
    /// left open for a week would otherwise never look.
    func start() {
        UpdateSwap.sweep()
        if clock == nil {
            let timer = Timer(timeInterval: Self.hour, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkIfDue() }
            }
            timer.tolerance = Self.hour / 12
            RunLoop.main.add(timer, forMode: .common)
            clock = timer
        }
        checkIfDue()
    }

    private static let hour: TimeInterval = 60 * 60
    /// A little under a day, so a Mac opened at the same time every morning
    /// still looks every morning.
    private static let due: TimeInterval = 20 * hour

    private func checkIfDue() {
        guard Date().timeIntervalSince(lastChecked ?? .distantPast) > Self.due else { return }
        check()
    }

    // MARK: - Looking

    /// Reads the feed now. Does nothing while a look or an install is under way,
    /// or once a newer build is already in place.
    func check() {
        switch stage {
        case .checking, .installing, .ready: return
        case .idle, .current, .available, .failed: break
        }
        stage = .checking
        Task { [weak self] in
            let result = await Self.fetch()
            self?.checked(result)
        }
    }

    private static func fetch() async -> Result<UpdateRelease?, Error> {
        var request = URLRequest(url: UpdateRelease.feed)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            // No release published yet is an answer, not a failure.
            if status == 404 { return .success(nil) }
            guard (200..<300).contains(status) else { throw UpdateSwap.Refused.download }
            return .success(UpdateRelease.parse(data))
        } catch {
            return .failure(error)
        }
    }

    private func checked(_ result: Result<UpdateRelease?, Error>) {
        switch result {
        case .failure:
            stage = .failed(nil, String(localized: "Couldn’t reach GitHub. Luna will try again later."))
        case let .success(found):
            lastChecked = Date()
            guard let found, found.version > Self.version else {
                stage = .current
                return
            }
            stage = .available(found)
            if installsOnItsOwn, canInstall { install(found) }
        }
    }

    // MARK: - Installing

    func install(_ release: UpdateRelease) {
        guard canInstall else { return }
        switch stage {
        case .installing, .ready: return
        case .idle, .checking, .current, .available, .failed: break
        }
        stage = .installing(release)
        let current = Self.version
        Task.detached(priority: .utility) {
            let outcome: String?
            do {
                try await UpdateSwap.install(release, over: current)
                outcome = nil
            } catch UpdateSwap.Refused.readOnly {
                outcome = String(localized: "Luna can’t write to the folder it’s in. Download it instead.")
            } catch {
                outcome = String(localized: "The download didn’t check out, so nothing was changed.")
            }
            await MainActor.run { [weak self] in self?.installed(release, failure: outcome) }
        }
    }

    private func installed(_ release: UpdateRelease, failure: String?) {
        guard case let .installing(installing) = stage, installing == release else { return }
        stage = failure.map { .failed(release, $0) } ?? .ready(release)
    }

    /// The release's page, for a build that cannot install and for a failed
    /// install.
    func openReleasePage(_ release: UpdateRelease) {
        NSWorkspace.shared.open(release.page)
    }

    /// Quits and comes back as the new one. A shell waits for this process to
    /// be gone before asking macOS to open the bundle again — `open` on a
    /// running app only brings it forward. The quit goes through `NSApp`, so
    /// everything written on the way out is written, as with `⌘Q`.
    func relaunch() {
        let waiter = Process()
        waiter.executableURL = URL(filePath: "/bin/sh")
        waiter.arguments = [
            "-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$2\"",
            "sh", String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundleURL.path
        ]
        try? waiter.run()
        NSApp.terminate(nil)
    }

    private func announce() {
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}
