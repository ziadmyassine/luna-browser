//
//  BrowserSession+Passwords.swift
//  Luna
//
//  Where §14's engine meets §14's chrome.
//
//  `TabController` finds the form, matches the site and holds the secrets;
//  `CredentialPopover` and `SavePasswordChip` are AppKit and cannot live in
//  `BrowserKit` (§25.5). This is the four delegate methods that join them, and
//  it is deliberately thin: which credentials match, whether the frame may be
//  filled and whether anything is written were all decided in
//  `PasswordCoordinator`, under test.
//
//  The one rule this file does own: password UI belongs to the active tab
//  only. A background tab finishing a load and putting a popover over the
//  page the user is reading would be a bug in the obvious direction, and a
//  save chip from a tab the user has left is a chip they cannot place.
//

import AppKit
import BrowserKit

/// The two panels, together, so `BrowserSession` grows one stored property
/// rather than two and neither can be presented without the other being
/// dismissible.
@MainActor
final class PasswordUI {
    let popover = CredentialPopover()
    let chip = SavePasswordChip()

    func dismissAll() {
        popover.dismiss()
        chip.dismiss(answering: false)
    }
}

extension BrowserSession {

    // MARK: - §14.3

    func tabController(_ controller: TabController, wantsToOfferCredentials offer: PasswordOffer) {
        guard controller.id == activeTabID, let webView = controller.webView else { return }
        passwordUI.popover.onPick = { [weak controller] credential in
            // The fill re-checks the site at the moment it runs, so a page that
            // navigated between the offer and this click cannot collect the
            // credential (§14.8).
            Task { await controller?.passwords.fill(credential) }
        }
        passwordUI.popover.present(.saved(offer), over: webView)
    }

    // MARK: - §14.5

    /// A signup form. Luna offers the generated password through the same
    /// picker shape as a saved one, so there is one place on the page where
    /// Luna ever puts a password and the user learns it once.
    func tabController(_ controller: TabController, wantsToSuggestPassword suggestion: PasswordSuggestion) {
        guard controller.id == activeTabID, let webView = controller.webView else { return }
        passwordUI.popover.onAcceptGenerated = { [weak controller] password in
            Task { await controller?.passwords.fillGenerated(password) }
        }
        passwordUI.popover.present(.generated(suggestion), over: webView)
    }

    // MARK: - §14.4

    func tabController(_ controller: TabController, wantsToSavePassword request: PasswordSaveRequest) {
        guard controller.id == activeTabID, let window = hostWindow, let webView = controller.webView else { return }
        passwordUI.chip.onSave = { [weak controller] request in
            Task { await controller?.passwords.confirmSave(request) }
        }
        passwordUI.chip.onNever = { [weak controller] request in
            controller?.passwords.declineForever(request)
        }
        passwordUI.chip.onDismiss = { [weak controller] _ in
            // Nothing is written and nothing is remembered: "not now" is not
            // "never", and the next sign-in asks again (§14.4).
            controller?.passwords.dismissSave()
        }
        passwordUI.chip.present(request, in: window, over: webView)
    }

    /// §14.3's anchor, following the page.
    func tabController(_ controller: TabController, wantsToMovePasswordUITo fieldRect: CGRect) {
        guard controller.id == activeTabID, let webView = controller.webView else { return }
        passwordUI.popover.move(to: fieldRect, over: webView)
    }

    // MARK: - Teardown

    /// The field went away, the document changed, or the tab did. The popover
    /// points at a rect in a page that no longer exists, so it goes.
    ///
    /// The chip deliberately survives a document change: §14.4 fires it on
    /// submit, and a successful sign-in navigates immediately afterwards. A
    /// chip that died with the document would be a chip nobody ever saw.
    func tabControllerDidDismissPasswordUI(_ controller: TabController) {
        guard controller.id == activeTabID else { return }
        passwordUI.popover.dismiss()
    }
}
