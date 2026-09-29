import Foundation
import WebKit

extension TabController {

    /// Hands `preferences` to the reading page in this tab, if it is showing
    /// one. In `.defaultClient`, Reader's own world, so the page's scripts can
    /// neither read nor undo it.
    public func applyReadingPreferences(_ preferences: ReadingPreferences = .stored()) {
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
