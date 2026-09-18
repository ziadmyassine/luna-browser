@testable import BrowserKit
import Foundation
import Testing

/// Renumber-on-load (§6.2). Reordering is the biggest hole in the prior art — nobody
/// researched for the spec implements it — and this self-heal is what makes it cheap:
/// `reorderSpace` writes indices and reloads, and the reload fixes whatever it got wrong.
@Suite("Space order self-heal (§6.2)")
struct SpaceOrderTests {

    /// Goal 5, exactly: persist `[0, 3, 7]`, read, get `[0, 1, 2]`.
    @Test func renumbersDriftedOrdersToZeroThroughN() async throws {
        let store = try makeTemporaryStore()
        let profile = Profile(name: "Personal")
        try await store.upsert(profile)
        for (index, order) in [0, 3, 7].enumerated() {
            try await store.upsert(
                Space(name: "Space \(index)", symbolName: "circle", gradient: .defaultSpace, profileID: profile.id, order: order)
            )
        }

        let spaces = try await store.spaces()

        #expect(spaces.map(\.order) == [0, 1, 2])
        #expect(spaces.map(\.name) == ["Space 0", "Space 1", "Space 2"], "the relative order is preserved")
        // A repair that is not written down is a repair that runs again on every read, and
        // is invisible to anything that reads the column directly.
        #expect(try await store.persistedSpaceOrders() == [0, 1, 2])
    }

    /// The gap every delete leaves. `delete(spaceID:)` does not renumber, and it does not
    /// have to — this does.
    @Test func closesTheGapADeleteLeaves() async throws {
        let store = try makeTemporaryStore()
        let profile = Profile(name: "Personal")
        try await store.upsert(profile)
        let names = ["A", "B", "C"]
        var ids: [UUID] = []
        for (order, name) in names.enumerated() {
            let space = Space(name: name, symbolName: "circle", gradient: .defaultSpace, profileID: profile.id, order: order)
            ids.append(space.id)
            try await store.upsert(space)
        }

        try await store.delete(spaceID: ids[1])
        let spaces = try await store.spaces()

        #expect(spaces.map(\.name) == ["A", "C"])
        #expect(spaces.map(\.order) == [0, 1])
    }

    /// Two Spaces sharing an `order` must renumber the same way on every launch, or the
    /// sidebar swaps them at random. Name is the tiebreak.
    @Test func breaksOrderTiesDeterministically() async throws {
        let store = try makeTemporaryStore()
        let profile = Profile(name: "Personal")
        try await store.upsert(profile)
        for name in ["Zebra", "Apple"] {
            try await store.upsert(
                Space(name: name, symbolName: "circle", gradient: .defaultSpace, profileID: profile.id, order: 4)
            )
        }

        #expect(try await store.spaces().map(\.name) == ["Apple", "Zebra"])
        #expect(try await store.spaces().map(\.order) == [0, 1])
    }

    /// The steady state is a pure read: an already-correct order writes nothing.
    @Test func leavesACorrectOrderAlone() async throws {
        let store = try makeTemporaryStore()
        try await store.seedIfEmpty()

        let first = try await store.spaces()
        let second = try await store.spaces()

        #expect(first == second)
        #expect(first.map(\.order) == [0])
    }

    @Test func handlesAnEmptyDatabase() async throws {
        let store = try makeTemporaryStore()
        #expect(try await store.spaces().isEmpty)
    }
}
