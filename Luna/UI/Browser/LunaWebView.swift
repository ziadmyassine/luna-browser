//
//  LunaWebView.swift
//  Luna
//
//  Every page's web view, for what `WKWebView` leaves to AppKit: the page's
//  right-click menu, and ⌘Z and ⌘S in a Markdown editor. BrowserKit builds
//  the views through `WebViewFactory.makeView`, which launch points here.
//

import AppKit
import BrowserKit
import WebKit

@MainActor
final class LunaWebView: WKWebView {

    /// Set for the length of `takeFocus`, Luna's own hand-over of the keyboard.
    var isTakingFocusDeliberately = false

    /// WebKit's own item. There is no public way to learn which link was
    /// right-clicked, so Open Link in New Tab sends this one and marks the tab
    /// it makes as a background one (`TabController.nextNewTabIsBackground`).
    static let newWindowItem = "WKMenuItemIdentifierOpenLinkInNewWindow"

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        guard let newWindow = menu.items.first(where: { $0.identifier?.rawValue == Self.newWindowItem }),
              newWindow.action != nil else { return }
        let item = NSMenuItem(
            title: String(localized: "Open Link in New Tab"), action: #selector(openLinkInNewTab(_:)), keyEquivalent: ""
        )
        item.target = self
        item.representedObject = newWindow
        menu.insertItem(item, at: menu.index(of: newWindow))
    }

    @objc private func openLinkInNewTab(_ sender: NSMenuItem) {
        guard let newWindow = sender.representedObject as? NSMenuItem, let action = newWindow.action else { return }
        tab?.nextNewTabIsBackground = true
        NSApp.sendAction(action, to: newWindow.target, from: newWindow)
    }

    private var tab: TabController? { uiDelegate as? TabController }

    // MARK: - Unpainted edge (#218)

    // Widened in one step (`ContentCardView.beginGeometryTransition`), the view's
    // own layer grows at once and the web process's layers catch up a few frames
    // later. The strip between them is this layer, which WebKit fills from the
    // view's appearance: `#1e1e1e` under dark chrome on a white page, a black
    // band down the trailing edge while the sidebar hid. The page's colour fills
    // it instead. `underPageBackgroundColor` alone does not reach it — that
    // paints a web-process layer, which is as stale as the rest.
    //
    // Set where the colour changes, not on the next display pass: the page can
    // report its colour and be widened before that pass runs. `updateLayer`
    // sets it again because WebKit's own `updateLayer` writes the appearance
    // fill back. And set on every resize, which is when the strip shows: the
    // colour can change without the KVO firing — on a light system under a
    // dark window, a white page read white and no change was ever observed.

    private var pageColourObservation: NSKeyValueObservation?

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        pageColourObservation = observe(\.underPageBackgroundColor) { view, _ in
            MainActor.assumeIsolated { view.fillWithPageColour() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its views in code")
    }

    override func updateLayer() {
        super.updateLayer()
        fillWithPageColour()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        fillWithPageColour()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        fillWithPageColour()
    }

    private func fillWithPageColour() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = underPageBackgroundColor.cgColor
        }
    }

    // MARK: - Markdown Edit

    // While Edit shows, WebKit files the typing on the document's own undo
    // list and ⌘Z is answered here, ahead of the window. The window's list
    // (`windowWillReturnUndoManager`) also holds closed tabs, and once it runs
    // dry it restores hidden elements; neither may answer ⌘Z in the editor.
    // Outside Edit the web view does not respond to `undo:` at all, so the
    // window answers exactly as it did.

    override var undoManager: UndoManager? {
        tab?.editorUndoManager ?? super.undoManager
    }

    override func responds(to selector: Selector!) -> Bool {
        if selector == #selector(undo(_:)) || selector == #selector(redo(_:)) {
            return tab?.editorUndoManager != nil
        }
        return super.responds(to: selector)
    }

    @objc func undo(_ sender: Any?) {
        tab?.editorUndoManager?.undo()
    }

    @objc func redo(_ sender: Any?) {
        tab?.editorUndoManager?.redo()
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if let list = tab?.editorUndoManager {
            if item.action == #selector(undo(_:)) { return list.canUndo }
            if item.action == #selector(redo(_:)) { return list.canRedo }
        }
        return super.validateUserInterfaceItem(item)
    }

    /// ⌘S saves in Edit whatever it is bound to elsewhere: the sidebar toggle
    /// defaults to it and can be rebound. A view's key equivalent is asked
    /// before the main menu's, so this wins in Edit and passes everywhere else.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let tab, tab.readingView == .edit, !isHiddenOrHasHiddenAncestor,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "s" {
            if tab.saveEdits(explicit: true) { PageToast.saved.show(in: window) }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
