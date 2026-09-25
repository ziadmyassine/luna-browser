//
//  TopBarView+Extensions.swift
//  Luna
//
//  §16.4 on §4's bar: the extensions button at the end of the action capsule,
//  after Downloads, and the pinned extensions at the capsule's other end,
//  before New Tab.
//
//  How many pins stand there is the tab strip's to give: the strip is the one
//  elastic thing on the bar, and it keeps two tabs' worth of room
//  (`pinnedExtensionsStripFloor`). The rest are in the pop-out.
//

import AppKit
import BrowserKit

extension TopBarView {

    static let extensionsItem = "extensions"
    private static let pinPrefix = "extension."

    private var center: ExtensionsCenter { .shared }

    func watchExtensions() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(extensionsDidChange),
            name: ExtensionsCenter.didChange,
            object: nil
        )
    }

    @objc private func extensionsDidChange() { refreshExtensions() }

    /// The button itself, or nothing in a window whose session runs no
    /// extensions — a private one.
    var extensionsButton: [TopBarActionItem] {
        guard center.serves(session) else { return [] }
        return [TopBarActionItem(
            id: Self.extensionsItem,
            symbolName: ExtensionsSymbol.name,
            label: ExtensionsSymbol.label
        ) { [weak self] in
            guard let self, let anchor = capsule.view(for: Self.extensionsItem) else { return }
            ExtensionsPopout.present(from: anchor, session: session, windowID: windowID)
        }]
    }

    /// Where a pinned extension's popup opens.
    func extensionAnchor(_ id: String) -> NSView? {
        capsule.view(for: Self.pinPrefix + id)
    }

    /// Re-reads the pins for the tab on screen: their icons and badges are
    /// per tab, and which of them run is per Space.
    func refreshExtensions() {
        let pinned = center.pinnedItems(in: session, window: windowID)
        let shown = pinned.prefix(fittingPins(of: pinned.count))
        let actions = shown.map { item in
            TopBarActionItem(
                id: Self.pinPrefix + item.id,
                symbolName: ExtensionsSymbol.name,
                image: ExtensionBadge.composite(item.icon ?? ExtensionsSymbol.image, badge: item.badge),
                label: item.badge.isEmpty ? item.name : "\(item.name), \(item.badge)"
            ) { [weak self] in
                guard let self, let anchor = extensionAnchor(item.id) else { return }
                ExtensionsCenter.shared.perform(item.id, in: session, window: windowID, from: anchor)
            }
        }
        // Assigned every time: the capsule keeps its buttons and re-dresses
        // them when the count has not changed, so a badge is cheap.
        extensionActions = actions
        center.addShelfAnchor(capsule.view(for: Self.extensionsItem), forWindow: windowID)
    }

    /// Called after every layout: a window made narrower may have less room
    /// for pins than it had, and a wider one more.
    func fitExtensions() {
        let pinned = center.pinnedItems(in: session, window: windowID).count
        guard pinned > 0, fittingPins(of: pinned) != extensionActions.count else { return }
        refreshExtensions()
    }

    /// The strip's width now, plus what the pins already take out of the
    /// capsule, less the two tabs the strip keeps: that room does not depend
    /// on how many pins are showing, so fitting them settles in one pass.
    private func fittingPins(of pinned: Int) -> Int {
        guard pinned > 0, strip.frame.width > 0 else { return 0 }
        let showing = CGFloat(extensionActions.count) * capsule.itemPitch
        let room = strip.frame.width + showing - Tokens.Metric.pinnedExtensionsStripFloor
        return ExtensionShelfFit.count(pinned, room: room, pitch: capsule.itemPitch)
    }
}
