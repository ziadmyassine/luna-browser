//
//  CredentialPopover.swift
//  Luna
//
//  §14.3's credential picker: a native popover anchored to the field.
//
//  "Native" in §14.3 is a security requirement, not a style note. An injected
//  DOM overlay lives in the page's own document, so the page can read the
//  usernames out of it, restyle it, move it, or draw a convincing copy and
//  harvest whatever the user picks. An `NSPanel` it can neither see nor script.
//
//  So this is a child window of the browser window, positioned from a rect the
//  page reported. The rect is the only thing that crosses over, and the worst a
//  lying page can do with it is put the popover somewhere silly.
//
//  Accessibility (§21.1): a real list of real buttons that VoiceOver reads,
//  and the panel comes to the field. While the caret is in the page, ↓ and ↑
//  choose a row, Return takes it and Escape puts the panel away, as in Safari.
//

import AppKit
import BrowserKit
import LocalAuthentication
import LocalAuthenticationEmbeddedUI
import WebKit

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
    ///
    /// `authenticated` is true when a finger on the sensor picked it through
    /// the live Touch ID view, which was the prompt; the fill asks no other.
    var onPick: ((_ credential: Credential, _ authenticated: Bool) -> Void)?

    /// The user accepted §14.5's generated password.
    var onAcceptGenerated: ((String) -> Void)?

    /// The user put the picker away with Escape. The engine hears it so a
    /// click back into the field raises a fresh one.
    var onClose: (() -> Void)?

    /// How long after appearing the picker refuses a click. A page can move
    /// its field, and so the picker, to wherever the pointer is about to
    /// click; a row taken within this window was never aimed at. The same
    /// half second Search measured as unnoticeable to someone who means it.
    static let pointerGrace: TimeInterval = 0.5

    private var panel: NSPanel?
    private var view: CredentialPopoverView?
    private var keyMonitor: Any?
    private var shownAt = Date.distantPast
    private var pickingByKeyboard = false

    /// The live Touch ID request behind the chosen row's fingerprint. Called
    /// off the moment the picker goes, a row is clicked, or Luna stops being
    /// the app in front: a request outliving its view is one macOS may
    /// answer with a dialog of its own, over whatever the user went to.
    private var touchContext: LAContext?
    /// The system's Touch ID view for that request, standing in the browser
    /// window under the picker. See `awaitTouch`.
    private var touchStand: NSView?
    private var resignObserver: (any NSObjectProtocol)?

    /// Set once a finger has picked: the tick is showing and the fill is on
    /// its way, and nothing else may be taken in the moment before it goes.
    private var isFinishing = false

    /// How long the tick stays before the picker goes: the length of the
    /// symbol's replace transition, so it lands before the fade starts.
    static let tickLinger: TimeInterval = 0.35

    /// How many refused fingers the sensor listens again after. Touch ID locks
    /// itself after five; three refusals here is the user's cue to click.
    static let touchRetries = 3

    private var touchesLeft = 0

    private var acceptsPick: Bool {
        !isFinishing && (pickingByKeyboard || Date().timeIntervalSince(shownAt) >= Self.pointerGrace)
    }

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

        let inline: Bool = if case .saved = offered { Self.canTouchInline } else { false }
        let content = CredentialPopoverView(
            content: offered,
            inlineTouchID: inline,
            onPick: { [weak self] credential in
                guard let self, acceptsPick else { return }
                dismiss()
                onPick?(credential, false)
            },
            onAcceptGenerated: { [weak self] password in
                guard let self, acceptsPick else { return }
                dismiss()
                onAcceptGenerated?(password)
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

        let frame = Self.frame(under: onScreen, size: size, on: host.screen)
        panel.setFrame(frame, display: false)
        // In a plain container, so the picker's own layer can be scaled about
        // a corner: a window's content view is AppKit's to place.
        let container = NSView(frame: CGRect(origin: .zero, size: size))
        content.frame = container.bounds
        content.autoresizingMask = [.width, .height]
        container.addSubview(content)
        panel.contentView = container
        // Transparent before it is on screen. Faded after, the panel and its
        // shadow were drawn whole for a frame first — a flash, then the fade.
        panel.alphaValue = Tokens.A11y.reduceMotion ? 1 : 0

        // A child window travels with the browser window and dies with it, so
        // the picker can never be left floating over the desktop pointing at a
        // field that is no longer there.
        host.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
        self.panel = panel
        view = content
        shownAt = Date()

        installKeyMonitor(typingInto: webView)
        // The panel hides with the app (`hidesOnDeactivate`); the offer goes
        // with it rather than waiting, hidden, with a request open.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
        if case let .saved(offer) = offered, content.touchCredential != nil,
           CredentialPopoverView.fingerprint(for: offer, inline: inline) == .inline {
            awaitTouch(on: content, site: offer.site, in: host)
        }
        // Grows out of the field: from the corner nearest it, which is the top
        // when the picker hangs below and the bottom when it had to go above.
        content.animateIn(growingDown: frame.maxY <= onScreen.minY + 0.5)
        Tokens.Motion.animate(Tokens.Motion.popoverIn) { _ in
            panel.animator().alphaValue = 1
        } completion: {
            MainActor.assumeIsolated { panel.invalidateShadow() }
        }
    }

    // MARK: - Touch ID on the row

    /// Whether a finger can answer here: Touch ID set up and in reach. A Mac
    /// without it, or with its lid shut, keeps the symbol and the dialog.
    private static var canTouchInline: Bool {
        NSApp.isActive && LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    /// Asks the sensor while the list is up, as Safari's autofill does: a
    /// finger on Touch ID fills the account the red fingerprint sits on, with
    /// no dialog.
    ///
    /// The request is tied to an `LAAuthenticationView`, which keeps the
    /// system's dialog away only while it is visible — and it counts as
    /// visible only in the key window. The picker is a panel that never
    /// becomes key, so the view could not live there: in it the request sat
    /// paused ("is not visible to user because NSPanel is not key") and a
    /// finger did nothing. It stands instead in the browser window, which
    /// is key while the user types into the page, under the picker's middle
    /// where the picker covers it; the fingerprint the user sees is the
    /// picker's own `TouchIDBadge`.
    private func awaitTouch(on content: CredentialPopoverView, site: String, in host: NSWindow) {
        content.showTouchID()
        touchesLeft = Self.touchRetries
        armTouch(site: site, in: host)
    }

    /// One request to the sensor, and what its answer does to the picker.
    private func armTouch(site: String, in host: NSWindow) {
        touchStand?.removeFromSuperview()
        let context = LAContext()
        let stand = LAAuthenticationView(context: context, controlSize: .small)
        stand.setAccessibilityElement(false)
        host.contentView?.addSubview(stand)
        touchStand = stand
        placeTouchStand()
        touchContext = context
        let reason = String(localized: "fill your saved password for \(site)")
        let request = ObjectIdentifier(context)
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { granted, error in
            let refused = (error as? LAError)?.code == .authenticationFailed
            Task { @MainActor [weak self] in
                guard let self, let current = touchContext, ObjectIdentifier(current) == request else { return }
                if granted {
                    touched()
                } else if refused, touchesLeft > 0, let host = touchStand?.window {
                    touchesLeft -= 1
                    view?.touchRefused()
                    armTouch(site: site, in: host)
                }
            }
        }
    }

    /// A finger was accepted: the tick, the fill, and then the picker goes.
    private func touched() {
        guard let credential = view?.touchCredential, let shown = panel else { return }
        touchContext = nil
        isFinishing = true
        view?.touchSucceeded()
        onPick?(credential, true)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.tickLinger) { [weak self] in
            guard let self, panel === shown else { return }
            dismiss()
        }
    }

    /// Under the middle of the picker, kept inside the browser window's
    /// content so the view is never clipped out of sight.
    private func placeTouchStand() {
        guard let stand = touchStand, let panel, let content = stand.superview, let host = content.window else { return }
        let side = CredentialRowView.fingerprintSide
        let middle = content.convert(host.convertPoint(fromScreen: CGPoint(x: panel.frame.midX, y: panel.frame.midY)), from: nil)
        let x = min(max(middle.x, side / 2), content.bounds.width - side / 2)
        let y = min(max(middle.y, side / 2), content.bounds.height - side / 2)
        stand.frame = CGRect(x: x - side / 2, y: y - side / 2, width: side, height: side)
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
        placeTouchStand()
    }

    /// A field's rect, which the page measures in CSS pixels from the
    /// top-left of its own viewport, in the web view's coordinates.
    ///
    /// Three things stand between the two. The viewport starts below whatever
    /// covers the web view's top — §3.2b's bar runs over the page and says so
    /// in `obscuredContentInsets`. A CSS pixel is `pageZoom × magnification`
    /// points, and §18.2 keeps a zoom per site. And `WKWebView` is flipped:
    /// measuring from the bottom put the picker at the field's mirror image,
    /// which on a sign-in centred on the page is a little above the field and
    /// over it.
    static func viewRect(for field: CGRect, in webView: NSView) -> CGRect {
        let web = webView as? WKWebView
        let covered = web?.obscuredContentInsets ?? NSEdgeInsetsZero
        let scale = (web?.pageZoom ?? 1) * (web?.magnification ?? 1)
        let height = field.height * scale
        let top = covered.top + field.minY * scale
        return CGRect(
            x: covered.left + field.minX * scale,
            y: webView.isFlipped ? top : webView.bounds.height - top - height,
            width: field.width * scale,
            height: height
        )
    }

    func dismiss() {
        isFinishing = false
        touchContext?.invalidate()
        touchContext = nil
        touchStand?.removeFromSuperview()
        touchStand = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        view = nil
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
        // None of AppKit's own: `animateIn` is the entrance, and a system
        // window animation on top of it doubled it.
        panel.animationBehavior = .none
        return panel
    }

    /// The picker's keys, read while the caret is in the page — which is
    /// where it always is when this panel is up. A local monitor, because the
    /// panel deliberately never becomes key and so never sees a `keyDown` of
    /// its own.
    ///
    /// Only while the web view is first responder: with the Command Bar or
    /// Find open over the page, Escape and the arrows are theirs, and taking
    /// them would leave those unable to close.
    private func installKeyMonitor(typingInto webView: NSView) {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak webView] event in
            guard let self, let view, let webView, Self.isTyping(in: webView, event) else { return event }
            guard event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift]) else { return event }
            switch event.keyCode {
            case 53:
                dismiss()
                onClose?()
            case 125:
                view.moveSelection(by: 1)
            case 126:
                view.moveSelection(by: -1)
            case 36, 76:
                pickingByKeyboard = true
                defer { pickingByKeyboard = false }
                return view.activateKeyboardSelection() ? nil : event
            default:
                return event
            }
            return nil
        }
    }

    private static func isTyping(in webView: NSView, _ event: NSEvent) -> Bool {
        guard let window = webView.window, event.window === window,
              let responder = window.firstResponder as? NSView
        else { return false }
        return responder === webView || responder.isDescendant(of: webView)
    }
}
