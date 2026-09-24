//
//  CredentialPopover.swift
//  Luna
//
//  §14.3's credential picker: a native popover anchored to the field.
//
//  The word "native" in §14.3 is a security requirement, not a style note. An
//  injected DOM overlay lives in the page's own document, so the page can read
//  the usernames out of it, restyle it, move it over a different field, or draw
//  a convincing copy and harvest whatever the user picks. None of that is
//  possible for an `NSPanel`: the page cannot see it, script it, or find out
//  what is in it. All a page learns is that it has a password field.
//
//  So this is a panel — a child window of the browser window — positioned from
//  a rect the page reported. The rect is the only thing that crosses over, and
//  the worst a lying page can do with it is put the popover somewhere silly.
//
//  Accessibility (§21.1): the panel is a real list of real buttons, so
//  VoiceOver reads each username; Escape dismisses from anywhere; and the
//  pointer never has to travel to a corner, because the panel comes to the
//  field.
//

import AppKit
import WebKit
import BrowserKit

@MainActor
final class CredentialPopover {

    /// What the picker is offering.
    ///
    /// Two cases rather than one, because they are genuinely different
    /// offers: picking a saved credential fills a username Luna already knows,
    /// and taking a generated password commits the user to one they have never
    /// seen. Collapsing them would have meant dressing the generated password
    /// up as a `Credential` whose username is the password — which reads
    /// correctly on screen and disastrously to VoiceOver.
    enum Content {
        case saved(PasswordOffer)
        case generated(PasswordSuggestion)

        /// Where to point, whichever kind of offer this is.
        var fieldRect: CGRect {
            switch self {
            case let .saved(offer): offer.fieldRect
            case let .generated(suggestion): suggestion.fieldRect
            }
        }
    }

    /// The user picked a saved credential. The caller fills — this view never
    /// touches a password, and never asks for one.
    var onPick: ((Credential) -> Void)?

    /// The user accepted §14.5's generated password.
    var onAcceptGenerated: ((String) -> Void)?

    private var panel: NSPanel?
    private var escapeMonitor: Any?

    // MARK: - Presenting

    /// Shows the picker under the field `content` describes.
    ///
    /// - Parameters:
    ///   - content: the engine's offer, including §14.8's redirect and
    ///     insecure-origin flags.
    ///   - webView: the view the field rect is measured in. Passed rather than
    ///     looked up so this cannot drift onto a different tab's page.
    func present(_ offered: Content, over webView: NSView) {
        dismiss()
        guard let host = webView.window else { return }
        if case let .saved(offer) = offered, offer.credentials.isEmpty { return }

        let content = CredentialPopoverView(
            content: offered,
            onPick: { [weak self] credential in
                self?.dismiss()
                self?.onPick?(credential)
            },
            onAcceptGenerated: { [weak self] password in
                self?.dismiss()
                self?.onAcceptGenerated?(password)
            }
        )
        let size = content.fittingPopoverSize()
        let panel = makePanel(size: size)

        // The rect arrives in CSS pixels from the top-left of the viewport;
        // AppKit wants the bottom-left of the screen. Converting through the
        // web view rather than assuming a flipped coordinate space is what
        // keeps this correct when the page is magnified or the window is on a
        // second display with a different scale.
        let onScreen = host.convertToScreen(webView.convert(Self.viewRect(for: offered.fieldRect, in: webView), to: nil))

        panel.setFrame(Self.frame(under: onScreen, size: size, on: host.screen), display: false)
        content.frame = CGRect(origin: .zero, size: size)
        panel.contentView = content

        // A child window travels with the browser window and dies with it, so
        // the picker can never be left floating over the desktop pointing at a
        // field that is no longer there.
        host.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
        self.panel = panel

        installEscapeMonitor()
        content.animateIn()
    }

    /// Repositions a picker that is already up, because the field it points at
    /// has moved under it.
    ///
    /// Moved, not rebuilt. The page re-reports its form on every frame of a
    /// scroll; tearing the panel down and building a new one at each report
    /// would flicker, lose the pointer's hover, and re-read the Keychain sixty
    /// times a second. Nothing about the offer has changed — only where it
    /// points.
    func move(to fieldRect: CGRect, over webView: NSView) {
        guard let panel, let host = webView.window else { return }
        let onScreen = host.convertToScreen(webView.convert(Self.viewRect(for: fieldRect, in: webView), to: nil))
        // Placed with animation off: this is tracking a scroll, and an animated
        // frame change would lag a finger by its own duration.
        Tokens.Motion.immediately {
            panel.setFrame(Self.frame(under: onScreen, size: panel.frame.size, on: host.screen), display: true)
        }
    }

    /// A field's rect, which the page measures from the top-left of its own
    /// viewport, in the web view's coordinates. The viewport starts below
    /// whatever covers the web view's top — §3.2b's bar runs over the page
    /// and says so in `obscuredContentInsets` — so the rect is moved down by
    /// that much, or the picker points one bar's height above the field.
    static func viewRect(for field: CGRect, in webView: NSView) -> CGRect {
        let covered = (webView as? WKWebView)?.obscuredContentInsets ?? NSEdgeInsetsZero
        return CGRect(
            x: field.minX + covered.left,
            y: webView.bounds.height - covered.top - field.maxY,
            width: field.width,
            height: field.height
        )
    }

    func dismiss() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        guard let panel else { return }
        self.panel = nil
        // Out the way it came in — see `Motion.fadePanelOut`.
        Tokens.Motion.fadePanelOut(panel)
    }

    // MARK: - Geometry

    /// Below the field, left edges aligned, flipped above it when there is no
    /// room below.
    ///
    /// Flipping matters more here than for most popovers: a login form at the
    /// bottom of a short page is the normal case, not the edge case, and a
    /// picker clipped by the screen edge is a picker the user cannot use.
    static func frame(under field: CGRect, size: CGSize, on screen: NSScreen?) -> CGRect {
        let gap = Tokens.Metric.passwordPopoverOffset
        var origin = CGPoint(x: field.minX, y: field.minY - size.height - gap)

        if let visible = screen?.visibleFrame {
            if origin.y < visible.minY {
                origin.y = field.maxY + gap
            }
            // Clamp horizontally after the flip: a field near the right edge
            // would otherwise push the panel off-screen whichever way it went.
            origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        }
        return CGRect(origin: origin, size: size)
    }

    private func makePanel(size: CGSize) -> NSPanel {
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        // Non-activating and non-key: the user is typing into the page, and a
        // picker that stole first responder would eat the next keystroke and
        // move the caret out of the field it is offering to fill.
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.transient, .ignoresCycle]
        panel.animationBehavior = .utilityWindow
        return panel
    }

    /// Escape dismisses from anywhere — including while focus is in the page,
    /// which is where it always is when this panel is up. A local monitor,
    /// because the panel deliberately never becomes key and so never sees a
    /// `keyDown` of its own.
    private func installEscapeMonitor() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.dismiss()
            return nil
        }
    }
}
