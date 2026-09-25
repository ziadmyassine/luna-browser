//
//  ExtensionsCenter.swift
//  Luna
//
//  §16.4: the one object between `ExtensionManager` and the chrome. It answers
//  WebKit's questions for the host (`ExtensionUI`), keeps which extensions are
//  pinned, and tells every window when what it shows has changed.
//
//  App-wide rather than per window because the manager is: it holds one weak
//  `ui`, and a popup has to open on whichever window's button was pressed.
//  Every change the UI makes goes through here, so one notification is enough
//  to keep the three surfaces and the popout agreeing.
//

import AppKit
import BrowserKit
import WebKit

/// One extension as a button shows it, in one window's Space and tab.
struct ExtensionShelfItem: Equatable {
    let id: String
    let name: String
    let icon: NSImage?
    /// The action's badge for the tab on screen — a count, a word, or empty.
    let badge: String
    let isPinned: Bool
    /// Running in the window's Space. Only the pop-out lists one that is not.
    var isOn = true
}

@MainActor
final class ExtensionsCenter: ExtensionUI {

    static let shared = ExtensionsCenter()

    /// Posted on the main thread whenever something a surface draws may have
    /// changed: an install, a removal, a pin, a Space switched on or off, or an
    /// action's icon or badge.
    static let didChange = Notification.Name("luna.extensions.didChange")

    private static let pinnedKey = "luna.extensions.pinned"

    /// The session whose extensions these are. A private session has none, as
    /// in Chrome's incognito by default, and its windows show no extension UI.
    private(set) weak var session: BrowserSession?
    var manager: ExtensionManager? { session?.extensions }

    /// The button the last action was started from, which is where its popup
    /// opens. Weak: a surface rebuilt since is a button that no longer exists.
    private weak var pressedAnchor: NSView?
    /// Each window's extensions buttons — one per surface, of which one is on
    /// screen — for a popup nobody pressed a button for: an extension opening
    /// its own.
    private var shelfAnchors: [UUID: [WeakView]] = [:]
    private var isChangePending = false

    private struct WeakView { weak var view: NSView? }

    func attach(_ session: BrowserSession) {
        guard let manager = session.extensions else { return }
        self.session = session
        manager.ui = self
        announce()
    }

    /// Whether `session` is the one extensions run in.
    func serves(_ session: BrowserSession) -> Bool {
        self.session === session && manager != nil
    }

    // MARK: - Pins

    /// Pinned extension ids, in the order they stand on a surface. One list for
    /// every Space: a pin is a choice about the extension, and a Space where it
    /// does not run simply does not show it.
    var pinned: [String] {
        UserDefaults.standard.stringArray(forKey: Self.pinnedKey) ?? []
    }

    func isPinned(_ id: String) -> Bool { pinned.contains(id) }

    /// Pins at the end of the row, nearest the extensions button — where the
    /// eye already is when it pinned it.
    func setPinned(_ isPinned: Bool, _ id: String) {
        var list = pinned.filter { $0 != id }
        if isPinned { list.append(id) }
        guard list != pinned else { return }
        UserDefaults.standard.set(list, forKey: Self.pinnedKey)
        announce()
    }

    // MARK: - What a window shows

    /// Every extension running in the window's Space, in install order.
    func items(in session: BrowserSession, window: UUID) -> [ExtensionShelfItem] {
        guard serves(session), let manager else { return [] }
        let space = session.activeSpaceID(inWindow: window)
        let tab = session.activeTabID(inWindow: window)
        let pins = Set(pinned)
        return manager.extensions.filter { $0.enabledSpaces.contains(space) }.map { info in
            let action = manager.action(for: info.id, tab: tab, inSpace: space)
            return ExtensionShelfItem(
                id: info.id,
                name: info.details?.name ?? action?.label ?? info.id,
                icon: Self.icon(action: action, details: info.details),
                badge: action?.badgeText ?? "",
                isPinned: pins.contains(info.id)
            )
        }
    }

    /// Every installed extension, running here or not, for the pop-out's
    /// switches. In install order either way: a row that moved when its switch
    /// was flipped would leave the pointer on a different extension.
    func allItems(in session: BrowserSession, window: UUID) -> [ExtensionShelfItem] {
        guard serves(session), let manager else { return [] }
        let running = Dictionary(items(in: session, window: window).map { ($0.id, $0) }) { first, _ in first }
        let pins = Set(pinned)
        return manager.extensions.map { info in
            running[info.id] ?? ExtensionShelfItem(
                id: info.id,
                name: info.details?.name ?? info.id,
                icon: Self.icon(action: nil, details: info.details),
                badge: "",
                isPinned: pins.contains(info.id),
                isOn: false
            )
        }
    }

    /// The pinned ones among `items`, in pin order.
    func pinnedItems(in session: BrowserSession, window: UUID) -> [ExtensionShelfItem] {
        let running = Dictionary(items(in: session, window: window).map { ($0.id, $0) }) { first, _ in first }
        return pinned.compactMap { running[$0] }
    }

    /// Every extension installed, whether or not it runs in this Space.
    var installed: [ExtensionInfo] { manager?.extensions ?? [] }

    /// Where a popup with no button of its own opens: whichever of the
    /// window's surfaces is showing its extensions button.
    func addShelfAnchor(_ view: NSView?, forWindow window: UUID) {
        guard let view else { return }
        var anchors = (shelfAnchors[window] ?? []).filter { $0.view != nil }
        if !anchors.contains(where: { $0.view === view }) { anchors.append(WeakView(view: view)) }
        shelfAnchors[window] = anchors
    }

    // MARK: - Doing

    /// A pinned button, or a row in the popout, was pressed: WebKit runs the
    /// action, and a popup it has opens on `anchor`.
    func perform(_ id: String, in session: BrowserSession, window: UUID, from anchor: NSView) {
        guard serves(session), let manager else { return }
        pressedAnchor = anchor
        manager.performAction(
            for: id,
            tab: session.activeTabID(inWindow: window),
            inSpace: session.activeSpaceID(inWindow: window)
        )
    }

    func setEnabled(_ enabled: Bool, _ id: String, inSpace space: UUID) async throws {
        try await manager?.setEnabled(enabled, extension: id, inSpace: space)
        announce()
    }

    func setGrants(_ grants: ExtensionGrants, _ id: String, inSpace space: UUID) async throws {
        try await manager?.setGrants(grants, extension: id, inSpace: space)
        announce()
    }

    func uninstall(_ id: String) async throws {
        try await manager?.uninstall(id)
        setPinned(false, id)
        announce()
    }

    func install(_ request: ExtensionInstallRequest, granting: ExtensionGrants, inSpace space: UUID) async throws {
        try await manager?.install(request, granting: granting, inSpace: space)
        announce()
    }

    func reload(_ id: String) async {
        await manager?.reload(id)
        announce()
    }

    /// Coalesced to one post per turn of the run loop: a page load updates
    /// every action's badge, and each would otherwise rebuild three surfaces.
    func announce() {
        guard !isChangePending else { return }
        isChangePending = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.isChangePending = false
                NotificationCenter.default.post(name: Self.didChange, object: nil)
            }
        }
    }

    // MARK: - ExtensionUI

    func extensionActionDidUpdate(_ action: WKWebExtension.Action, extensionID: String, spaceID: UUID) {
        announce()
    }

    /// WebKit's own popover, on the button that was pressed — or, for a popup
    /// nobody pressed a button for, on the key window's extensions button.
    func presentPopup(for action: WKWebExtension.Action, extensionID: String, spaceID: UUID) throws {
        guard let popover = action.popupPopover else {
            throw ExtensionError.notAvailable("This extension's popup")
        }
        guard let anchor = popupAnchor() else {
            throw ExtensionError.notAvailable("A window to open this popup in")
        }
        ExtensionsPopout.closeAll()
        popover.behavior = .transient
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: anchor.isFlipped ? .maxY : .minY)
        pressedAnchor = nil
    }

    private func popupAnchor() -> NSView? {
        if let pressedAnchor, pressedAnchor.window?.isVisible == true, !pressedAnchor.isHiddenOrHasHiddenAncestor {
            return pressedAnchor
        }
        let visible = shelfAnchors.values.flatMap { $0 }.compactMap(\.view).filter {
            $0.window?.isVisible == true && !$0.isHiddenOrHasHiddenAncestor
        }
        return visible.first { $0.window?.isKeyWindow == true } ?? visible.first
    }

    func promptForAccess(_ prompt: ExtensionPermissionPrompt) async -> Set<String> {
        let name = installed.first { $0.id == prompt.extensionID }?.details?.name ?? prompt.extensionID
        return await ExtensionAccessPrompt.ask(prompt, extensionName: name)
    }

    // MARK: - Icons

    /// The action's own icon for the tab — it can change per page — then the
    /// manifest's, then the extensions symbol. Drawn at the favicon size every
    /// icon in Luna's chrome stands at.
    static func icon(action: WKWebExtension.Action?, details: ExtensionDetails?) -> NSImage? {
        let side = Tokens.Metric.faviconSize
        if let image = action?.icon(for: CGSize(width: side, height: side)) {
            return sized(image)
        }
        if let data = details?.iconData, let image = NSImage(data: data) {
            return sized(image)
        }
        return nil
    }

    /// Resized by its point size, not redrawn: a bitmap keeps every
    /// representation it came with, so a Retina screen still gets the 32 px one.
    private static func sized(_ image: NSImage) -> NSImage {
        let copy = image.copy() as? NSImage ?? image
        copy.size = NSSize(width: Tokens.Metric.faviconSize, height: Tokens.Metric.faviconSize)
        return copy
    }
}
