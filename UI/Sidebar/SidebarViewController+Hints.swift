//
//  SidebarViewController+Hints.swift
//  Luna
//
//  §3.3a: the column's half of the two wells a Space with nothing pinned draws.
//
//  The block well belongs to the §3.3 grid and is drawn by it — an empty grid
//  is the only thing that knows it has the room. The row well is this file's,
//  because the tier it describes is §3.4b's and §3.4b has no rows to draw it
//  on: that is the state it exists for.
//
//  Separate from `+Layout.swift` for the controller's type-body limit, and
//  because this is the one question in the column whose answer comes out of
//  `Settings` rather than out of the session.
//

import AppKit

extension SidebarViewController {

    /// The row well, and the margin under it that stands in for the grid's own.
    /// Zero when there is a folder pinned, or when the advice has been taken —
    /// and zero is a height, so the list simply starts higher.
    var folderHintHeight: CGFloat {
        folderHint.isHidden ? 0 : Tokens.Metric.pinHintRow + 2 * Tokens.Metric.essentialsVerticalInset
    }

    func wirePinHints() {
        // The flag posts `Settings.didChange`, which is what takes the well out
        // of this column and every other one.
        essentials.onDismissHint = { Settings.showsPinnedTabHint = false }
        folderHint.onDismiss = { Settings.showsPinnedFolderHint = false }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsDidChange),
            name: Settings.didChange,
            object: nil
        )
    }

    /// - Parameters:
    ///   - tiles: whether §3.3's grid is empty.
    ///   - folders: whether §3.4b's tier is.
    func showPinHints(tiles: Bool, folders: Bool) {
        // Advice taken is advice finished. A tier with something in it has had
        // the thing done to it, so the flag is put away for good — a well that
        // came back when the last tile was unpinned would be the app teaching a
        // user what that user has just taught it. The cross is the other way to
        // finish a piece of advice, and there is no third: nothing sets either
        // of these back to true.
        //
        // Next tick, not here. Writing a setting posts `didChange`, which comes
        // straight back through `refresh()` — and this is called from inside
        // one. Each is worth scheduling once, which is what the two flags being
        // read first is for.
        let tabTaken = !tiles && Settings.showsPinnedTabHint
        let folderTaken = !folders && Settings.showsPinnedFolderHint
        if tabTaken || folderTaken {
            DispatchQueue.main.async {
                if tabTaken { Settings.showsPinnedTabHint = false }
                if folderTaken { Settings.showsPinnedFolderHint = false }
            }
        }
        essentials.showsHint = tiles && Settings.showsPinnedTabHint
        folderHint.isHidden = !folders || !Settings.showsPinnedFolderHint
    }

    /// - Parameter top: the top edge of the band the well and its margins
    ///   occupy, which is where §3.4b's first folder row will start.
    func placeFolderHint(topAt top: CGFloat, in bounds: NSRect) {
        // Zero-sized rather than merely hidden when it has nothing to say: the
        // §30.9 swipe measures the column by the union of the views it carries,
        // and a hidden view keeps whatever frame it was last given.
        let inset = Tokens.Metric.rowInset
        folderHint.frame = folderHint.isHidden ? .zero : NSRect(
            x: inset,
            y: top + Tokens.Metric.essentialsVerticalInset,
            width: max(bounds.width - 2 * inset, 0),
            height: Tokens.Metric.pinHintRow
        ).integral
    }

    @objc func settingsDidChange() {
        refresh()
    }
}
