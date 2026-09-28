import BrowserKit
import Foundation

/// A fresh database per test, on disk rather than in memory so the tests exercise the
/// same `DatabasePool`, WAL and file-creation path the app uses.
func temporaryDatabasePath() -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: "luna-tests", directoryHint: .isDirectory)
        .appending(path: "\(UUID().uuidString).sqlite")
}

func makeTemporaryStore() throws -> BrowserStore {
    try BrowserStore(path: temporaryDatabasePath())
}

/// A settings suite of the calling test's own, emptied before it is handed over.
///
/// Named after the test, not after a fresh UUID: a suite is a plist in
/// ~/Library/Preferences that `removePersistentDomain` empties but does not delete,
/// and deleting it by hand races cfprefsd, which writes it back. A UUID per run left
/// one file per run, over 500 of them from this target. A name per test rather than
/// per suite, because Swift Testing runs a suite's tests in parallel.
func scratchDefaults(file: String = #fileID, test: String = #function) -> UserDefaults {
    let type = file.split(separator: "/").last?.split(separator: ".").first ?? "tests"
    let name = "luna.tests.\(type).\(test.prefix { $0 != "(" })"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

/// A store with one seeded Space, and that Space's id.
///
/// History belongs to a Space since `v8`, and `visits.spaceID` is a foreign key, so
/// a history test cannot write into an invented id — it has to write into a Space
/// that exists.
func makeTemporaryStoreWithSpace() async throws -> (store: BrowserStore, space: UUID) {
    let store = try makeTemporaryStore()
    try await store.seedIfEmpty()
    return (store, try await store.spaces()[0].id)
}

/// `n` days before `reference`. Frecency is entirely about how old a visit is (§9.3),
/// so every history test states its dates this way.
func daysAgo(_ days: Double, from reference: Date = Date()) -> Date {
    reference.addingTimeInterval(-days * 24 * 60 * 60)
}
