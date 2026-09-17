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

/// `n` days before `reference`. Frecency is entirely about how old a visit is (§9.3),
/// so every history test states its dates this way.
func daysAgo(_ days: Double, from reference: Date = Date()) -> Date {
    reference.addingTimeInterval(-days * 24 * 60 * 60)
}
