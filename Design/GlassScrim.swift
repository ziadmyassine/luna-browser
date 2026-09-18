//
//  GlassScrim.swift
//  Luna
//
//  §9.1's backdrop: what the Command Bar floats on. The one surface in Luna
//  that is deliberately **not** Liquid Glass, and the reason is in
//  `Glass.scrim()` — `NSGlassEffectView` composites what is behind the
//  *window*, so over a live page it replaces the page rather than blurring it,
//  and in fullscreen, with no desktop to sample, it goes very nearly black.
//
//  WHAT WAS WRONG WITH IT, MEASURED AND ALREADY WRITTEN DOWN. The scrim was
//  built at `alphaValue = 0.55`, and `CommandBarPanel` carried a comment saying
//  exactly why that cannot work: *"`alphaValue` on an `NSVisualEffectView` does
//  not thin the material: it cross-fades the blurred result back over the sharp
//  original, and the two together read as a flat grey veil laid on a page that
//  is still perfectly legible underneath."* The comment was right and the code
//  did the other thing — so the bar sat on a grey film rather than on a blur.
//  There was no bug to find, only two files disagreeing.
//
//  SO IT IS AT FULL STRENGTH, AND IT CARRIES §2'S FROST. That is the peeked
//  sidebar's recipe, which is what Martin asked this surface to look like: the
//  material does the blurring, and `Surface.frost` — the chrome's fallback
//  plane at part strength — is painted over it to give the blur a *surface* to
//  be, instead of a hole. `Glass.peekPlane` paints the same plane behind its
//  glass, and §2a's setting moves both together.
//
//  WHAT IT STILL CANNOT COPY. The peek is real glass, so it also refracts the
//  desktop and carries a rim. Neither is available here: no material samples an
//  out-of-process `WKWebView` layer, which is the whole finding `Glass.scrim()`
//  exists to record. The blur and the plane are the parts that can be the same,
//  and they are the parts that read.
//

import AppKit

/// §9.1's backdrop, as one view: the within-window blur with §2's frost over it.
@MainActor
final class GlassScrimView: NSVisualEffectView {

    private let plate = PlateView()

    init() {
        super.init(frame: .zero)
        blendingMode = .withinWindow
        // **The lightest in-window material that still genuinely blurs.**
        // `.hudWindow` and `.fullScreenUI` both blur beautifully and then
        // flatten everything above them into one dark plate — the Command
        // Bar's own Liquid Glass stopped looking like a material at all, and
        // the page behind it stopped being visible as context. `.sidebar` is
        // the most see-through of the in-window materials: the page is still
        // there, softened, and a glass surface on top of it still reads as
        // glass.
        material = .sidebar
        // Not `.followsWindowActiveState`: the bar is modal over this window
        // and a backdrop that thins out when the window loses focus is one that
        // stops hiding the page mid-interaction.
        state = .active
        plate.autoresizingMask = [.width, .height]
        addSubview(plate)
        // Reduce Transparency changes what the plate paints — see `PlateView`.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override func layout() {
        super.layout()
        plate.frame = bounds
    }

    /// §2a: re-reads the density. Called by `Glass.reapplyDensity()`, exactly as
    /// `GlassBackingView.refreshMaterial()` is.
    func refreshMaterial() {
        plate.needsDisplay = true
    }

    @objc private func accessibilityDisplayOptionsChanged() {
        plate.needsDisplay = true
    }

    /// The frost, as a plane over the blur.
    ///
    /// Its own view rather than this one's layer: an `NSVisualEffectView`'s
    /// backing layer belongs to the material, and a background colour set on it
    /// composites somewhere inside the effect rather than reliably over it.
    @MainActor
    private final class PlateView: NSView {

        override var wantsUpdateLayer: Bool { true }

        override func updateLayer() {
            wantsLayer = true
            // **Nothing under Reduce Transparency.** `NSVisualEffectView`
            // already goes opaque for that setting on its own, and a second
            // plane on top of an opaque one is a plane nobody can see past for
            // no gain (§21.2).
            layer?.backgroundColor = Tokens.A11y.reduceTransparency
                ? nil
                : Glass.Style.sidebar.frost(Glass.density)?.cgColor
        }

        /// Decoration takes no events — the press belongs to the panel above,
        /// which dismisses the bar with it (§9.1).
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
