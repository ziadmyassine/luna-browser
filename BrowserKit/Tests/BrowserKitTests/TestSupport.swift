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
