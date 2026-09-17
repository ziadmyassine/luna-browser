import AppKit
import BrowserKit
import WebKit

/// The browser window: one standard-titlebar `NSWindow` hosting one `WKWebView`.
///
/// M0 deliberately stops here — no custom titlebar, no traffic-light insets, no sidebar.
/// Those land in M2 (§7.7, §30) and need their own layout manager, not frame nudging here.
@MainActor
final class BrowserWindowController: NSWindowController {
    convenience init(url: URL) {
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: Tokens.Metric.windowDefaultWidth,
                height: Tokens.Metric.windowDefaultHeight
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Luna"
        window.center()

        let contentView = NSView()
        window.contentView = contentView

        let webView = WebViewFactory.makeWebView()
        webView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: contentView.topAnchor),
            webView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            // NSWindow.minSize is documented as ignored once the content view uses
            // Auto Layout, so the floor lives in the constraint system instead.
            contentView.widthAnchor.constraint(
                greaterThanOrEqualToConstant: Tokens.Metric.windowMinWidth
            ),
            contentView.heightAnchor.constraint(
                greaterThanOrEqualToConstant: Tokens.Metric.windowMinHeight
            )
        ])

        self.init(window: window)

        // Set after `center()` so a remembered frame wins over the default placement.
        windowFrameAutosaveName = "LunaBrowserWindow"

        webView.load(URLRequest(url: url))
    }
}
