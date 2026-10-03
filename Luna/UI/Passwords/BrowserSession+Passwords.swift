//
//  BrowserSession+Passwords.swift
//  Luna
//
//  Where §14's engine meets §14's chrome.
//
//  `TabController` finds the form, matches the site and holds the secrets;
//  `CredentialPopover` and the save toast are AppKit and cannot live in
//  `BrowserKit` (§25.5). This is the four delegate methods that join them, and
//  it is deliberately thin: which credentials match, whether the frame may be
//  filled and whether anything is written were all decided in
//  `PasswordCoordinator`, under test.
//
//  The one rule this file does own: password UI belongs to the active tab
//  only. A background tab finishing a load and putting a popover over the
//  page the user is reading would be a bug in the obvious direction, and a
//  save offer from a tab the user has left is one they cannot place.
//

import AppKit
import BrowserKit

/// The picker, held where the session can take it down when the tab changes.
/// The save offer is a `PageToast`, which the window's toast surface owns.
@MainActor
final class PasswordUI {
    let popover = CredentialPopover()

    func dismissAll() {
        popover.dismiss()
    }
}

extension BrowserSession {

    // MARK: - §14.3

    func tabController(_ controller: TabController, wantsToOfferCredentials offer: PasswordOffer) {
        guard controller.id == activeTabID, let webView = controller.webView else { return }
        passwordUI.popover.onPick = { [weak controller] credential, authenticated in
            // The fill re-checks the site at the moment it runs, so a page that
            // navigated between the offer and this click cannot collect the
            // credential (§14.8).
            Task { await controller?.passwords.fill(credential, authenticated: authenticated) }
        }
        passwordUI.popover.onClose = { [weak controller] in controller?.passwords.pickerClosed() }
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
        passwordUI.popover.onClose = { [weak controller] in controller?.passwords.pickerClosed() }
        passwordUI.popover.present(.generated(suggestion), over: webView)
    }

    // MARK: - §14.4

    func tabController(_ controller: TabController, wantsToSavePassword request: PasswordSaveRequest) {
        guard controller.id == activeTabID, let window = hostWindow else { return }
        PageToast.savePassword(
            request,
            save: { [weak controller] in Task { await controller?.passwords.confirmSave(request) } },
            never: { [weak controller] in controller?.passwords.declineForever(request) },
            // Nothing is written and nothing is remembered: "not now" is not
            // "never", and the next sign-in asks again (§14.4).
            unanswered: { [weak controller] in controller?.passwords.dismissSave() }
        ).show(in: window)
    }

    /// §14.3's anchor, following the page.
    func tabController(_ controller: TabController, wantsToMovePasswordUITo fieldRect: CGRect) {
        guard controller.id == activeTabID, let webView = controller.webView else { return }
        passwordUI.popover.move(to: fieldRect, over: webView)
    }

    // MARK: - Teardown

    /// The field went away, the document changed, or the tab did. The popover
    /// points at a rect in a page that no longer exists, so it goes. The save
    /// toast stays: it comes up on the page a sign-in led to.
    func tabControllerDidDismissPasswordUI(_ controller: TabController) {
        guard controller.id == activeTabID else { return }
        passwordUI.popover.dismiss()
    }
}

// MARK: - §14.4's offer

extension PageToast {

    /// "Save password?" with the account and the site beside it, and Save and
    /// Never. Not Now is the toast leaving unanswered, which saves nothing.
    ///
    /// The site is in the detail because it is what the user checks: the
    /// password is filed under it, and a lookalike page names a different one.
    static func savePassword(
        _ request: PasswordSaveRequest,
        save: @escaping @MainActor () -> Void,
        never: @escaping @MainActor () -> Void,
        unanswered: @escaping @MainActor () -> Void
    ) -> PageToast {
        let updating = request.kind == .update
        var detail = request.username.isEmpty ? request.site : "\(request.username) · \(request.site)"
        if request.isInsecure { detail += String(localized: " · not encrypted") }
        var toast = PageToast(
            symbol: "key",
            text: updating ? String(localized: "Update password?") : String(localized: "Save password?"),
            detail: detail,
            actions: [
                Action(
                    title: updating ? String(localized: "Update") : String(localized: "Save"),
                    label: String(localized: "Save the password for \(request.site)"),
                    run: save
                ),
                Action(
                    title: String(localized: "Never"),
                    label: String(localized: "Never save passwords for \(request.site)"),
                    toolTip: String(localized: "Don’t offer to save passwords on this site again"),
                    run: never
                )
            ]
        )
        toast.onUnanswered = unanswered
        return toast
    }
}
