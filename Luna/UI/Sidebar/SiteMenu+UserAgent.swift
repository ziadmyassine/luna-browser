//
//  SiteMenu+UserAgent.swift
//  Luna
//
//  §4.6's per-site user agent, as a row of the site pop-out: the site's own
//  choice of the modes Settings ▸ Advanced offers, or Default, which is
//  whatever Settings says. For the site that only lets Chrome in.
//

import AppKit
import BrowserKit

extension SiteMenu {

    /// The row's choices in order. Nil is Default; Settings' own Default, which is
    /// Luna's user agent, is called Luna here so the two do not share a name.
    static let userAgentChoices: [(mode: WebViewFactory.UserAgentMode?, title: String)] = [
        (nil, String(localized: "Default")),
        (.default, String(localized: "Luna")),
        (.safari, String(localized: "Safari")),
        (.chrome, String(localized: "Chrome")),
        (.custom, String(localized: "Custom"))
    ]

    /// Settings' popup, bare at the end of the row, as Settings ▸ Advanced draws it.
    /// The user agent goes with the request, so the page is fetched again to use it.
    static func userAgent(host: String, scope: SitePermissions? = nil, reload: (() -> Void)? = nil) -> SiteSettingsContent.Control {
        let scope = scope ?? session?.sitePermissions ?? .shared
        let popup = ChoicePopUp(titles: userAgentChoices.map(\.title))
        let current = scope.userAgentMode(forHost: host)
        popup.selectItem(at: userAgentChoices.firstIndex { $0.mode == current } ?? 0)
        popup.setAccessibilityLabel(String(localized: "User Agent"))
        popup.onChoose = { index in
            guard userAgentChoices.indices.contains(index) else { return }
            scope.setUserAgentMode(userAgentChoices[index].mode, forHost: host)
            (reload ?? reloadWithNewUserAgent)()
        }
        return .init(title: String(localized: "User Agent"), symbol: Glyph.userAgent, view: popup)
    }

    private static func reloadWithNewUserAgent() {
        guard let session, let id = session.activeTabID, let webView = session.controller(for: id)?.webView else { return }
        WebViewFactory.applyAdvancedSettings(to: webView)
        webView.reload()
    }
}

/// A bare popup that is its own target: a row of the pop-out has nowhere else to keep
/// one, and `NSControl` holds its target weakly.
final class ChoicePopUp: NSPopUpButton {

    var onChoose: ((Int) -> Void)?

    init(titles: [String]) {
        super.init(frame: .zero, pullsDown: false)
        addItems(withTitles: titles)
        isBordered = false
        font = Tokens.TypeScale.settingsRow
        contentTintColor = Tokens.Text.secondary
        target = self
        action = #selector(chose(_:))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    @objc private func chose(_ sender: NSPopUpButton) {
        onChoose?(indexOfSelectedItem)
    }
}
