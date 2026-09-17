import Foundation

/// §6.8's snapshot cache: PNG bytes on disk, capped by an LRU.
///
/// An actor, so the sidebar's hover preview and the lifecycle sweep never do
/// file IO on the main thread. It takes `Data`, never an image type — the
/// conversion is AppKit's job and stays in the app (contract rule 2).
///
/// Recency is the file's modification date rather than a second index: the
/// filesystem already keeps one, and an index in a plist is one more thing that
/// can disagree with the directory it describes.
public actor SnapshotStore {

    private let directory: URL
    private let budget: Int
    /// id → (bytes, last use). Rebuilt from disk at init; the disk is the truth.
    private var entries: [UUID: (size: Int, used: Date)] = [:]

    /// - Parameter budget: bytes. §6.8 says "e.g. 200 MB".
    public init(directory: URL, budget: Int = 200 * 1024 * 1024) {
        self.directory = directory
        self.budget = budget
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for url in (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        )) ?? [] {
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                  let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            else { continue }
            entries[id] = (values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }
    }

    private func url(_ id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).png")
    }

    @discardableResult
    public func store(_ png: Data, for id: UUID) -> Bool {
        guard (try? png.write(to: url(id), options: .atomic)) != nil else { return false }
        entries[id] = (png.count, Date())
        evictIfNeeded()
        return true
    }

    /// The tab's snapshot, and a bump of its recency — a snapshot the sidebar
    /// keeps showing is a snapshot worth keeping.
    public func snapshot(for id: UUID) -> Data? {
        guard let data = try? Data(contentsOf: url(id)) else {
            entries[id] = nil
            return nil
        }
        entries[id]?.used = Date()
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url(id).path)
        return data
    }

    public func remove(_ id: UUID) {
        try? FileManager.default.removeItem(at: url(id))
        entries[id] = nil
    }

    /// Bytes currently held. The test's handle on the cap.
    public var usage: Int { entries.values.reduce(0) { $0 + $1.size } }

    public var count: Int { entries.count }

    /// Oldest-used first until the total is back inside the budget.
    private func evictIfNeeded() {
        var total = usage
        guard total > budget else { return }
        for (id, entry) in entries.sorted(by: { $0.value.used < $1.value.used }) {
            guard total > budget else { return }
            remove(id)
            total -= entry.size
        }
    }
}
