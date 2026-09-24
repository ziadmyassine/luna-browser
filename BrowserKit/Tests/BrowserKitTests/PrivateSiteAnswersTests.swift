@testable import BrowserKit
import Foundation
import Testing
import WebKit

/// §5.6: a per-site answer given in a private window stays in that window. It reads
/// the user's standing answers, and nothing it writes reaches them or the database.
@Suite("Private per-site answers (§5.6)")
@MainActor
struct PrivateSiteAnswersTests {

    private static func blocker() -> ContentBlocker {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "luna-rules/\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return ContentBlocker(
            store: WKContentRuleListStore(url: directory)!,
            defaults: UserDefaults(suiteName: "luna.private.tests.\(UUID().uuidString)")!
        )
    }

    @Test func permissionsReadThroughAndWriteOnlyToThePrivateScope() {
        let main = SitePermissions()
        main.setAllowed(true, .localNetwork, forHost: "printer.example")
        let scoped = SitePermissions(fallback: main)

        #expect(scoped.isAllowed(.localNetwork, forHost: "printer.example"))

        scoped.setAllowed(false, .localNetwork, forHost: "printer.example")
        scoped.setAllowed(false, .savePasswords, forHost: "bank.example")
        #expect(!scoped.isAllowed(.localNetwork, forHost: "printer.example"))
        #expect(!scoped.isAllowed(.savePasswords, forHost: "bank.example"))
        #expect(main.isAllowed(.localNetwork, forHost: "printer.example"))
        #expect(main.isAllowed(.savePasswords, forHost: "bank.example"))
        #expect(main.answeredHosts(.savePasswords).isEmpty)
    }

    @Test func aPrivateScopeLivesAndDiesWithItsDataStore() async throws {
        #expect(SitePermissions.scope(for: .default()) === SitePermissions.shared)

        weak var ended: SitePermissions?
        autoreleasepool {
            let store = WKWebsiteDataStore.nonPersistent()
            let scoped = SitePermissions.scope(for: store)
            #expect(scoped !== SitePermissions.shared)
            #expect(SitePermissions.scope(for: store) === scoped)
            scoped.setAllowed(false, .savePasswords, forHost: "bank.example")
            ended = scoped
        }
        // WebKit holds a new store for a turn of the run loop after its last owner
        // lets go (measured: alive straight after the pool drains, gone a beat later).
        for _ in 0 ..< 100 where ended != nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(ended == nil)
        #expect(SitePermissions.scope(for: .nonPersistent()).isAllowed(.savePasswords, forHost: "bank.example"))
        #expect(SitePermissions.shared.isAllowed(.savePasswords, forHost: "bank.example"))
    }

    @Test func blockingAndHTTPSAnswersStayOutOfTheSharedSetsAndTheDatabase() async throws {
        let store = try makeTemporaryStore()
        let blocker = Self.blocker()
        blocker.browserStore = store
        blocker.isHTTPSOnlyEnabled = true
        let scoped = SitePermissions(fallback: .shared)

        // A standing exemption still holds in private, and a private answer can override it.
        blocker.setDisabled(true, forHost: "news.example")
        #expect(blocker.isDisabled(forHost: "news.example", in: scoped))
        blocker.setDisabled(false, forHost: "news.example", in: scoped)
        #expect(!blocker.isDisabled(forHost: "news.example", in: scoped))
        #expect(blocker.isDisabled(forHost: "news.example"))

        blocker.setDisabled(true, forHost: "shop.example", in: scoped)
        blocker.allowInsecure(host: "legacy.example", in: scoped)
        #expect(blocker.isDisabled(forHost: "shop.example", in: scoped))
        #expect(!blocker.isDisabled(forHost: "shop.example"))
        let insecure = URL(string: "http://legacy.example/")!
        #expect(blocker.httpsDecision(for: insecure, in: scoped) == .proceed)
        #expect(blocker.httpsDecision(for: insecure) != .proceed)

        // The shared write is a detached save; once it has landed, the private ones
        // would have too if they were going to.
        var exemptions = try await store.blockingExemptions()
        for _ in 0 ..< 100 where exemptions.blockingDisabled.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
            exemptions = try await store.blockingExemptions()
        }
        #expect(exemptions.blockingDisabled == ["news.example"])
        #expect(exemptions.insecureAllowed.isEmpty)
    }
}
