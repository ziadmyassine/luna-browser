//
//  SavePasswordChip.swift
//  Luna
//
//  §14.4: after a successful submit, a non-modal chip offering Save /
//  Update / Never for this site.
//
//  Non-modal is the requirement that shapes everything here. The user has just
//  pressed Sign In and is watching for the page to change; a sheet would block
//  that, steal the keyboard, and get dismissed unread by someone trying to get
//  on with what they were doing. So the chip floats at the top-right of the
//  content area, takes no focus, and goes away on its own — and choosing
//  nothing is a real, supported answer that saves nothing.
//
//  It shares §5's panel shape rather than inventing a second one: same glass,
//  same shadow, same child-window relationship to the browser window.
//

import AppKit
import BrowserKit

@MainActor
final class SavePasswordChip {

    /// The user pressed Save / Update.
    var onSave: ((PasswordSaveRequest) -> Void)?
    /// "Never for this site" — §14.4 persists this in `siteSettings`.
    var onNever: ((PasswordSaveRequest) -> Void)?
    /// Dismissed without answering. Saves nothing, and is not remembered:
    /// ignoring the chip once must not mean never being asked again.
    var onDismiss: ((PasswordSaveRequest) -> Void)?

    private var panel: NSPanel?
    private var request: PasswordSaveRequest?
    private var dismissTimer: Timer?

    /// §5's downloads list takes itself down after 4 s. This one does not use
    /// that interval: a chip asking a question the user has to read and answer
    /// needs longer than one reporting a finished download, and 4 s is enough
    /// to notice it appearing and not enough to decide.
    private static let autoDismiss: TimeInterval = 12

    func present(_ request: PasswordSaveRequest, in host: NSWindow, over content: NSView) {
        dismiss(answering: false)
        self.request = request

        let view = SavePasswordChipView(
            request: request,
            onSave: { [weak self] in
                guard let self, let request = self.request else { return }
                self.dismiss(answering: true)
                self.onSave?(request)
            },
            onNever: { [weak self] in
                guard let self, let request = self.request else { return }
                self.dismiss(answering: true)
                self.onNever?(request)
            },
            onClose: { [weak self] in self?.dismiss(answering: false) },
            onHoverChanged: { [weak self] hovering in
                hovering ? self?.cancelTimer() : self?.startTimer()
            }
        )

        let size = view.fittingChipSize()
        let panel = makePanel(size: size)
        view.frame = CGRect(origin: .zero, size: size)
        panel.contentView = view

        let area = host.convertToScreen(content.convert(content.bounds, to: nil))
        let inset = Tokens.Metric.chromeGapWide
        panel.setFrame(
            CGRect(
                x: area.maxX - size.width - inset,
                y: area.maxY - size.height - inset,
                width: size.width,
                height: size.height
            ),
            display: false
        )

        host.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
        self.panel = panel
        view.animateIn()
        startTimer()

        // §21.1: an offer that exists only as something that appeared in a
        // corner is an offer a VoiceOver user is never told about.
        NSAccessibility.post(element: view, notification: .announcementRequested, userInfo: [
            .announcement: String(localized: "Save the password for \(request.site)?"),
            .priority: NSAccessibilityPriorityLevel.medium.rawValue
        ])
    }

    /// - Parameter answering: true when a button was pressed, so the caller has
    ///   already been told. False means the chip timed out or was closed, and
    ///   `onDismiss` fires — which saves nothing.
    func dismiss(answering: Bool) {
        cancelTimer()
        guard let panel else { return }
        self.panel = nil
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        if !answering, let request { onDismiss?(request) }
        request = nil
    }

    private func startTimer() {
        cancelTimer()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: Self.autoDismiss, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss(answering: false) }
        }
    }

    private func cancelTimer() {
        dismissTimer?.invalidate()
        dismissTimer = nil
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
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.transient, .ignoresCycle]
        panel.animationBehavior = .utilityWindow
        return panel
    }
}
