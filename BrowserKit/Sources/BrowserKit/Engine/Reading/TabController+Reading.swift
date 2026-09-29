import Foundation
import WebKit

/// Which of a Markdown page's renderings is showing. Edit joins in Phase 6
/// of docs/READING-PLAN.md.
public enum ReadingView: String, CaseIterable, Sendable {
    case read, source
}

extension TabController {

    /// Switches a Markdown page between its renderings without a reload: both
    /// are in the document, and `data-view` picks one (`ReadingStyle`).
    public func setReadingView(_ view: ReadingView) {
        guard markdownDocument != nil else { return }
        readingView = view
        webView?.callAsyncJavaScript(
            "document.body.setAttribute('data-view', view);",
            arguments: ["view": view.rawValue],
            in: nil,
            in: .defaultClient
        )
    }

    /// Restyles this tab's reading page whenever the stored preferences change,
    /// including a change that arrives from another Mac through `SyncedDefaults`.
    func followReadingPreferences() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(readingDefaultsDidChange),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    /// Posted on whichever thread wrote the default, and for every default
    /// there is, so it hops to the main actor and compares before touching the page.
    @objc nonisolated private func readingDefaultsDidChange(_ note: Notification) {
        Task { @MainActor [weak self] in
            guard let self, state.isReading else { return }
            let preferences = ReadingPreferences.stored()
            guard preferences != appliedReading else { return }
            applyReadingPreferences(preferences)
        }
    }

    /// Hands `preferences` to the reading page in this tab, if it is showing
    /// one. In `.defaultClient`, Reader's own world, so the page's scripts can
    /// neither read nor undo it.
    public func applyReadingPreferences(_ preferences: ReadingPreferences = .stored()) {
        appliedReading = preferences
        webView?.callAsyncJavaScript(
            Self.readingPreferencesScript + "return applyReadingPreferences(preferences);",
            arguments: ["preferences": preferences.script],
            in: nil,
            in: .defaultClient
        )
    }

    /// A declaration rather than a script, so Reader can apply the first
    /// preferences in the same call that builds its page. A page with no
    /// `.luna-reading` is left alone: its root is the site's.
    static let readingPreferencesScript = """
    function applyReadingPreferences(preferences) {
      if (!document.querySelector('.luna-reading')) { return false; }
      var root = document.documentElement;
      root.style.setProperty('--luna-reading-size', preferences.size + 'px');
      ['typeface', 'width', 'page', 'outline', 'wrap'].forEach(function (name) {
        root.setAttribute('data-luna-' + name, String(preferences[name]));
      });
      return true;
    }

    """
}
