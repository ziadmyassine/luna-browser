//
//  BrowserSession+PageTools.swift
//  Luna
//
//  Reader, and hiding parts of a page for good, on the tab in front. The
//  mechanisms are `TabController`'s; what belongs here is which tab, which
//  site's list, the undo step, and the toast that says what happened — each of
//  these changes the page in a way the user has to be able to name and undo.
//

import AppKit
import BrowserKit

extension BrowserSession {

    /// A web page or a file. Nothing Luna draws itself has an article to read
    /// or a banner to hide, and a cold tab has no page to act on yet.
    var canUsePageTools: Bool {
        guard let url = activeURL, activeController?.webView != nil else { return false }
        return ["http", "https", "file"].contains(url.scheme?.lowercased() ?? "")
    }

    var isReaderOn: Bool { activeController?.isReaderOn ?? false }
    var isPickingElements: Bool { activeController?.isPickingElements ?? false }

    // MARK: - Reader

    func toggleReader() {
        guard canUsePageTools, let controller = activeController else { return }
        controller.stopPickingElements()
        controller.toggleReader { [weak self] answer in
            PageToast.reader(answer).show(in: self?.hostWindow)
        }
    }

    // MARK: - Hiding

    /// `⇧⌘H` starts the picker, and pressed again puts it away. Not on a reader
    /// page: what is there is Luna's, and hiding it would file a rule against
    /// the site that matches nothing the site draws.
    func toggleHidingElements() {
        guard let controller = activeController else { return }
        guard !controller.isPickingElements else { return controller.stopPickingElements() }
        guard canUsePageTools, !controller.isReaderOn else { return }
        let host = activeURL?.host(percentEncoded: false)
        controller.startPickingElements { [weak self] element in
            self?.hide(element, onHost: host)
        } onEnd: { [weak self] in
            PageToast.hidingStarted.putAway(in: self?.hostWindow)
        }
        // Down for as long as the picker is on, or until the first thing is
        // hidden: finding what to click takes longer than a toast's dwell.
        PageToast.hidingStarted.show(in: hostWindow, untilPutAway: true)
    }

    func hide(_ element: HiddenElements.Element, onHost host: String?) {
        hiddenElements.hide(element, onHost: host)
        redress(host)
        registerUndo(String(localized: "Hide \(element.label)")) { $0.showAgain(element, onHost: host) }
        PageToast.hidden(element.label).show(in: hostWindow)
    }

    func showAgain(_ element: HiddenElements.Element, onHost host: String?) {
        hiddenElements.restore(selector: element.selector, onHost: host)
        redress(host)
        registerUndo(String(localized: "Show \(element.label)")) { $0.hide(element, onHost: host) }
        PageToast.shownAgain(element.label).show(in: hostWindow)
    }

    /// ⌘Z once the undo list is empty — see `SessionUndoManager`. Nothing is
    /// registered: outside an undo a registration lands on the undo side, and
    /// the next ⌘Z would hide the thing again rather than bring back the next.
    func showLastHiddenOnActivePage() -> Bool {
        let host = activeURL?.host(percentEncoded: false)
        guard canUsePageTools, let last = hiddenElements.elements(onHost: host).last else { return false }
        hiddenElements.restore(selector: last.selector, onHost: host)
        redress(host)
        PageToast.shownAgain(last.label).show(in: hostWindow)
        return true
    }

    var canShowLastHiddenOnActivePage: Bool {
        canUsePageTools && !hiddenElements.elements(onHost: activeURL?.host(percentEncoded: false)).isEmpty
    }

    /// Once per session; every window on it shares the list.
    func bringBackHiddenWhenUndoRunsOut() {
        undoManager.whenEmpty = { [weak self] in
            MainActor.assumeIsolated { self?.showLastHiddenOnActivePage() ?? false }
        }
        undoManager.canUndoWhenEmpty = { [weak self] in
            MainActor.assumeIsolated { self?.canShowLastHiddenOnActivePage ?? false }
        }
    }

    /// Every live tab on the site, not only the one in front: a second tab on
    /// it would otherwise go on showing what was just hidden until it reloads.
    private func redress(_ host: String?) {
        let site = HiddenElements.site(of: host)
        for controller in controllers.values where HiddenElements.site(of: controller.state.url?.host()) == site {
            controller.applyHiddenElements()
        }
    }
}
