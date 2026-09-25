import CoreGraphics
import Foundation
import WebKit

/// The live view of one tab, published to the UI through `TabControllerDelegate` (§4.3).
///
/// Everything here is a value type: a hibernated tab keeps its `TabState` after its
/// `WKWebView` is gone, which is what lets the sidebar still show a title and a tint
/// for a tab that costs no process (§19.2).
public struct TabState: Sendable, Equatable {
    public var url: URL?
    public var title: String
    public var isLoading: Bool
    public var progress: Double
    public var canGoBack: Bool
    public var canGoForward: Bool
    public var themeColor: RGBA?
    /// What is behind the page, as WebKit computes it — the colour an
    /// over-scroll shows, and the one the top of the document is painted on.
    ///
    /// Not `themeColor`, and the difference is the point: a `<meta
    /// name="theme-color">` is a decoration the site offers to browser chrome
    /// and most sites do not offer one, while this is measured from the
    /// document and is always there. Chrome that has to match the page — see
    /// §3.2b's bar — needs the second question answered, not the first.
    public var pageBackground: RGBA?
    public var hasOnlySecureContent: Bool
    public var isPlayingAudio: Bool

    public init(
        url: URL? = nil,
        title: String = "",
        isLoading: Bool = false,
        progress: Double = 0,
        canGoBack: Bool = false,
        canGoForward: Bool = false,
        themeColor: RGBA? = nil,
        pageBackground: RGBA? = nil,
        hasOnlySecureContent: Bool = false,
        isPlayingAudio: Bool = false
    ) {
        self.url = url
        self.title = title
        self.isLoading = isLoading
        self.progress = progress
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.themeColor = themeColor
        self.pageBackground = pageBackground
        self.hasOnlySecureContent = hasOnlySecureContent
        self.isPlayingAudio = isPlayingAudio
    }
}

/// `WKWebView.themeColor` is an AppKit colour on macOS. This is the one place it is
/// allowed to exist, and it never escapes: `RGBA` is what crosses the module boundary
/// (contract rule 2). Deliberately never names the AppKit type — the colour arrives as
/// a `CGColor` and leaves as four Doubles.
enum ColorBridge {

    /// sRGB components, or `nil` for a colour that cannot be converted (a catalog or
    /// pattern colour). `themeColor` comes from a page's `<meta name="theme-color">`,
    /// so in practice it is always a plain device colour.
    static func rgba(from cgColor: CGColor) -> RGBA? {
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = cgColor.converted(to: srgb, intent: .defaultIntent, options: nil),
              let components = converted.components, components.count >= 3
        else { return nil }
        return RGBA(
            r: Double(components[0]),
            g: Double(components[1]),
            b: Double(components[2]),
            a: Double(converted.alpha)
        )
    }
}

/// The pure half of the delegate hub: decisions that depend only on the response, so
/// they can be tested without a window.
enum NavigationPolicy {

    /// Schemes a `WKWebView` renders itself. Anything else is another app's job (§4.2).
    ///
    /// `luna` is ours (§4.4) and stays in-process even before the scheme handler lands,
    /// so a stray internal link never bounces out to the Finder.
    /// `webkit-extension` is an extension's own pages: an options page opened
    /// as a tab, or a welcome page the extension opens itself (§16.1).
    static let internalSchemes: Set<String> = [
        "http", "https", "about", "data", "blob", "file", "luna", "webkit-extension"
    ]

    enum Disposition: Equatable {
        case display
        /// Hand to the OS: `mailto:`, `tel:`, another app's scheme.
        case external
        /// Cancel outright, with no handoff — a `javascript:` URL in the address bar or
        /// a link is an XSS vector, not a navigation.
        case block
    }

    static func disposition(for url: URL) -> Disposition {
        // An empty scheme is a relative URL WebKit will resolve itself.
        guard let scheme = url.scheme?.lowercased() else { return .display }
        if scheme == "javascript" { return .block }
        return internalSchemes.contains(scheme) ? .display : .external
    }

    /// §15.2 — a response becomes a download when WebKit cannot render it, or when the
    /// server explicitly asked for one.
    ///
    /// Only the disposition type is inspected: `Content-Disposition: inline;
    /// filename="attachment.pdf"` is an inline PDF, and a `contains("attachment")`
    /// check would hijack it. WebKit renders PDFs itself and §15.5 says not to take
    /// that away.
    ///
    /// A subframe only downloads on an explicit `attachment` — the hidden-iframe trick
    /// is how plenty of sites start a download, but an unrenderable MIME type in some
    /// background ad frame is not a file the user asked for (§15.4).
    static func shouldDownload(
        canShowMIMEType: Bool,
        contentDisposition: String?,
        isForMainFrame: Bool
    ) -> Bool {
        if isAttachment(contentDisposition) { return true }
        return isForMainFrame && !canShowMIMEType
    }

    static func isAttachment(_ contentDisposition: String?) -> Bool {
        guard let contentDisposition else { return false }
        let type = contentDisposition.split(separator: ";", maxSplits: 1).first ?? ""
        return type.trimmingCharacters(in: .whitespaces).lowercased() == "attachment"
    }

    // ponytail: host minus `www.`, not eTLD+1 — costs one cache entry per subdomain,
    // never a wrong icon. Swap in a public-suffix list if the entry count ever matters.
    /// Cache and favicon key. No public-suffix list ships with Foundation, so a real
    /// eTLD+1 would need one; collapsing to the last two labels instead would hand
    /// `a.github.io` the icon of `b.github.io`.
    static func faviconKey(forHost host: String) -> String {
        let lowercased = host.lowercased()
        return lowercased.hasPrefix("www.") ? String(lowercased.dropFirst(4)) : lowercased
    }
}
