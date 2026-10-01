//
//  NavCluster.swift
//  Luna
//
//  §3.1's history control: back alone until there is a forward to go to. One
//  class for the sidebar's control row and §3.2b's page bar, because they are
//  the same control on two surfaces.
//
//  Forward is unreachable on most pages, and a permanently dimmed chevron beside
//  a live one spends its life saying no, so it is not there until it means
//  something. When it arrives the pair becomes one capsule split by a hairline.
//
//  One plate, two bare glyphs: the material is the cluster's, at the circle's
//  radius, so back alone is the circle and the capsule is that circle grown a
//  second half. A backing per chevron reads as separate discs. The glass can be
//  built once because its radius is fixed at construction and the height never
//  changes, so half of it is a capsule at either width.
//

import AppKit

@MainActor
final class NavCluster: NSView {

    var onBack: (() -> Void)?
    var onForward: (() -> Void)?

    /// The shape of one half — and of the whole thing while it is only back.
    static let half = Tokens.Metric.sidebarCircle

    /// `.none`: the cluster around them is the material. Both are `GlassButton`
    /// rather than a chevron of their own, so they ink, hover and dim exactly
    /// as the sidebar toggle beside them does.
    private let back = GlassButton(
        shape: NavCluster.half,
        symbolName: "chevron.backward",
        pointSize: Tokens.Metric.glyphSize,
        label: String(localized: "Back"),
        glassMode: .none
    )
    private let forward = GlassButton(
        shape: NavCluster.half,
        symbolName: "chevron.forward",
        pointSize: Tokens.Metric.glyphSize,
        label: String(localized: "Forward"),
        glassMode: .none
    )
    private let divider = NSView()

    /// Whether the capsule is carrying its second half right now.
    private(set) var showsForward = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = Self.half.cornerCurve
        Glass.apply(
            .control,
            to: self,
            cornerRadius: Self.half.cornerRadius,
            cornerCurve: Self.half.cornerCurve
        )
        divider.wantsLayer = true
        back.onActivate = { [weak self] in self?.onBack?() }
        forward.onActivate = { [weak self] in self?.onForward?() }
        // The capsule is what the press is against. Both halves are
        // `.none` buttons, so neither has a material to swell — this does, and
        // it is the shape the pointer is actually on. With back alone that is
        // the circle from the reference; with forward out it is the whole
        // capsule, which is right for the same reason the glass is one piece.
        for half in [back, forward] {
            half.onPressChange = { [weak self] pressed in self?.setPressed(pressed) }
        }
        for view in [back, divider, forward] { addSubview(view) }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "Back and Forward"))
        applyForward(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    // MARK: - State

    /// Back dims where it has always dimmed; forward appears.
    ///
    /// The two are not the same answer to the same question, and that is
    /// deliberate. Back is on every page and is dimmed on the first one, so the
    /// eye learns where it is; forward exists only after a back, so a dimmed
    /// one would be a control the user has never once been able to press.
    func update(canGoBack: Bool, canGoForward: Bool) {
        back.isEnabled = canGoBack
        guard canGoForward != showsForward else { return }
        showsForward = canGoForward
        invalidateIntrinsicContentSize()
        applyForward(animated: true)
    }

    private func applyForward(animated: Bool) {
        // Un-hidden before the fade in either direction: a view cannot fade
        // from `isHidden`, and `settle()` hides it again at the end.
        if showsForward { for view in [forward, divider] { view.isHidden = false } }
        let assign: () -> Void = {
            for view in [self.forward, self.divider] {
                view.alphaValue = self.showsForward ? 1 : 0
            }
        }
        guard animated else {
            Tokens.Motion.immediately(assign)
            settle()
            return
        }
        // The two directions are not the same length, and that is the point.
        //
        // Arriving, the chevron fades in over the 0.20 s the capsule takes to
        // grow past it: the edge is ahead of it the whole way, so the glyph is
        // never outside its own surface.
        //
        // Leaving, the edge is coming at it. A 0.20 s fade puts the chevron
        // at half opacity on the frame the edge sweeps through it and leaves
        // the rest of it hanging outside a capsule that has already passed —
        // which is the one thing in this morph that reads as a smear. At 0.10 s
        // it is gone before the edge is halfway, and what the eye sees is a
        // capsule closing over an empty half.
        let spec = showsForward ? Tokens.Motion.sidebarCollapse : Tokens.Motion.controlHover
        Tokens.Motion.animate(spec) { context in
            context.allowsImplicitAnimation = true
            assign()
        } completion: { [weak self] in
            MainActor.assumeIsolated { self?.settle() }
        }
    }

    /// §6 `controlPress`, on behalf of whichever half is down.
    private func setPressed(_ pressed: Bool) {
        Tokens.Motion.swell(self, to: pressed ? Tokens.Motion.pressSwell : 1)
    }

    /// A view at alpha 0 still hit-tests, so a faded chevron would go on eating
    /// clicks in a capsule it is no longer part of.
    private func settle() {
        for view in [forward, divider] { view.isHidden = view.alphaValue == 0 }
    }

    // MARK: - Layout

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: showsForward ? Self.half.width * 2 : Self.half.width,
            height: Self.half.height
        )
    }

    override func layout() {
        super.layout()
        // Bounds-derived frames never animate — see `Motion.immediately`.
        Tokens.Motion.immediately {
            // Nothing inside here is measured against the bounds, and that
            // is what keeps the morph clean in both directions. All three are
            // placed off the leading edge at fixed distances, so while the
            // capsule's trailing edge travels — the only thing that does — the
            // two glyphs and the rule between them stand still and the edge
            // moves past them.
            //
            // Measured against the bounds instead, a shrink re-reads them at
            // the final width on its first frame: back would be fine, but
            // the divider would jump into the middle of it and the forward
            // chevron would slide left across it while fading. That is the
            // morph going one way looking nothing like it going the other.
            let side = Self.half.width
            back.frame = NSRect(x: 0, y: 0, width: side, height: bounds.height).pixelAligned
            forward.frame = NSRect(x: side, y: 0, width: side, height: bounds.height).pixelAligned
            // Short of the ends: a rule that runs the full height cuts the
            // capsule in two rather than separating the glyphs.
            let inset = bounds.height / 4
            divider.frame = NSRect(
                x: side - Tokens.Metric.hairline / 2,
                y: inset,
                width: Tokens.Metric.hairline,
                height: bounds.height - 2 * inset
            ).pixelAligned
        }
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        // No background and no border: the glass is the whole surface, the same
        // way it is for a `.always` button.
        divider.layer?.backgroundColor = Tokens.Line.hairline.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    /// §30.1: the bar's plane moves the window; a control on it does not.
    override var mouseDownCanMoveWindow: Bool { false }
}
