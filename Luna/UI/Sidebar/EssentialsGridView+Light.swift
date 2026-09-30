//
//  EssentialsGridView+Light.swift
//  Luna
//
//  §3.3's glow: the soft light under the pinned tile that is the tab you are
//  on, in that site's own colour.
//
//  One view for the whole grid, not one per tile. Only one tile can be the tab
//  you are on, so a backing view per tile is a dozen surfaces keeping a single
//  light on. One view that is moved also makes the rule below expressible: the
//  light goes out where it was and appears where it now is, and a thing that
//  cannot travel cannot be animated across the grid by accident.
//
//  Split out of `EssentialsGridView.swift` for that file's length limit.
//  `glow`, `litID`, `activeTabID` and `tabs` are internal rather than private
//  only because Swift's `private` is file-scoped.
//

import AppKit

extension EssentialsGridView {

    /// Lights the pinned tile that is the tab you are on, and puts out the one
    /// that was.
    ///
    /// - Parameter blooming: whether this pass could have come from a click.
    ///   §3.3's glow appears, and the appear belongs to the press that caused
    ///   it: the pass that builds the sidebar has to arrive with the light
    ///   already on, and a refresh that leaves the same tile lit must not
    ///   replay it — which is why the tile has to have changed as well.
    /// - Parameter replacing: this is a different grid, not an edit to this
    ///   one — §6's Space switch. The light is placed, never faded: see
    ///   `EssentialGlowView.show(_:blooming:animated:)`.
    func relight(blooming: Bool, replacing: Bool = false) {
        let lit = activeTabID.flatMap { settled.contains($0) ? $0 : nil }
        let moved = lit != litID
        litID = lit
        // Stood in the right place before it is lit, or the pop plays at
        // the tile you came from and the light teleports afterwards: the
        // layout pass that would otherwise place it does not run until later
        // in the loop, and the appear starts here.
        placeGlow()
        glow.show(
            lit.flatMap(tint(for:)),
            blooming: blooming && moved && lit != nil,
            animated: !replacing
        )
    }

    /// Where the light stands: its tile's slot, or nowhere.
    var litSlot: NSRect? {
        guard let litID, let index = settled.firstIndex(of: litID) else { return nil }
        // A live drag holds a slot open, exactly as it does for the tiles.
        let slot = dropIndex.map { index >= $0 ? index + 1 : index } ?? index
        return slotRect(at: slot)
    }

    /// The light never travels. It is one view moved between tiles, so an
    /// animated pass — a pin, an unpin, a reorder — would slide it across the
    /// grid from the tile you left to the tile you clicked, and that slide is
    /// the thing this is not: the glow goes out where it was and appears where
    /// it now is. Always immediate, inside an animated pass or out of one.
    func placeGlow() {
        guard let frame = litSlot else { return }
        Tokens.Motion.immediately { glow.frame = frame }
    }

    /// The colour a tile glows in: the site's own, out of its favicon.
    private func tint(for id: UUID) -> NSColor? {
        tabs.first { $0.id == id }.map(FaviconTint.glow(for:))
    }
}
