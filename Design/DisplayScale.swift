//
//  DisplayScale.swift
//  Luna
//
//  §7's 1× glass adaptation: the setting, the detection, and the one pass that
//  re-skins every live glass view. Glass.swift owns the material; this file
//  decides which column of §7's table it renders.
//
//  MEASURED on two Philips 1920 × 1080 panels, `backingScaleFactor == 1.0`,
//  60 Hz, every accessibility reducer off. Liquid Glass is not disabled there;
//  it is drawn at a quarter of the pixel density it was designed against.
//
//  WHAT IT BUYS AND WHAT IT COSTS. One window, one backdrop, dark, 1×,
//  luminance of each element against the bar behind it — and it is not a clean
//  win:
//
//                         2× rendering   1× optimised
//      URL pill               +6.07          −8.19
//      control circle         +7.12          −3.24
//      row backing            +0.79         −16.03
//      the bar itself         66.21          70.11
//
//  · The row backing is the real gain: +0.8 is invisible, −16.0 is not. §7 is
//    right that `.clear` fails there.
//  · The control circle is a regression: 7.1 units of separation become 3.2.
//  · Every control flips polarity. §2's language is "`.clear` glass over an
//    already-tinted bar is what makes them read as raised"; on `.regular` they
//    read as inset, and no public knob turns that back (`Ink.glassTintControl`).
//  · The bar's tint bump is +3.9 luminance units and changes nothing else.
//
//  So this is a preference, not a fix, and `.auto` turning it on below 2× is a
//  judgement the setting exists to let the user overrule.
//
//  WHAT CAN BE CHANGED. `NSGlassEffectView` exposes four properties and no more
//  — `contentView`, `cornerRadius`, `tintColor`, `style` — verified against
//  MacOSX26.5.sdk and reproduced in Glass.swift's header. There is no blur
//  radius, no sample count, no rim width and no third style, so §7's adaptation
//  is two of those four knobs:
//
//                       2× (Retina)          1× optimised
//      .control style   .clear               .regular
//      .control tint    none                 glassTintControl
//      .sidebar/.topBar glassTint            glassTintDense
//
//  Anything more would be a hand-drawn imitation of a material, which is what
//  §0.3 exists to keep out.
//
//  THE PART THAT IS EASY TO GET WRONG. `backingScaleFactor` belongs to the
//  window's current screen, not to the app, so a window dragged from a 1×
//  display to a 2× one has to re-resolve. `NSScreen.main` is the wrong question
//  and is never asked here. Three signals cover it, deliberately overlapping
//  because each has a hole the others fill:
//
//    · `NSWindow.didChangeBackingPropertiesNotification` — the window changed
//      backing store. Posted per window; observed with `object: nil` so one
//      observer covers every window Luna will open.
//    · `NSApplication.didChangeScreenParametersNotification` — the screen
//      changed under a window that did not move.
//    · `NSView.viewDidChangeBackingProperties()` — AppKit's per-view hook, in
//      `GlassBackingView`. It never fires for a view that is not in a window,
//      which is why the two notifications exist.
//
//  All three land on `refreshForDisplay()`, which is idempotent and rebuilds
//  only when the answer changed, so the overlap costs nothing.
//
//  §7's two tints are declared here rather than in Tokens.swift because that
//  file is at the 400-line limit, and because these two carry the measurement
//  above as their justification. No hex is written below, only alphas derived
//  from `Ink.glassTint`, and `TokenCheck` re-derives both. §7's one length,
//  `Metric.glassPreviewTile`, stays in Metrics.swift with the other window
//  sizes.
//

import AppKit

// MARK: - The setting

/// §7's tri-state, stored in `appearance.glassOptimisation`.
public enum GlassOptimisation: String, Sendable {
    /// Optimised when the window's screen is below 2×, plain otherwise. The
    /// default, and the only value that varies per display.
    case auto
    /// The user's override, respected on every display.
    case on
    /// The user's override, respected on every display.
    case off
}

extension Glass {

    /// §7's setting.
    ///
    /// Assigning re-skins every glass view in every open window in one pass —
    /// no relaunch, no window reopen — and persists to
    /// `appearance.glassOptimisation`. Reading it costs a dictionary lookup once
    /// per launch and nothing after.
    @MainActor
    static var optimisation: GlassOptimisation {
        get { DisplayScale.optimisation }
        set {
            guard newValue != DisplayScale.optimisation else { return }
            DisplayScale.optimisation = newValue
            UserDefaults.standard.set(newValue.rawValue, forKey: DisplayScale.defaultsKey)
            reapplyOptimisation()
        }
    }

    /// Whether §7's 1× column applies to `window`.
    ///
    /// Reads `window.backingScaleFactor` and never `NSScreen.main`: the scale
    /// factor belongs to the screen the window is currently on, and a browser
    /// window gets dragged between displays.
    ///
    /// A nil window has no screen and therefore no scale, so `.auto` answers
    /// `false` — today's Retina rendering. A view built before it joins a window
    /// starts unoptimised, and `GlassBackingView.viewDidMoveToWindow()` re-asks
    /// once it has a real screen.
    @MainActor
    static func isOptimised(for window: NSWindow?) -> Bool {
        switch optimisation {
        case .on: true
        case .off: false
        case .auto: (window?.backingScaleFactor ?? DisplayScale.retinaScale) < DisplayScale.retinaScale
        }
    }

    /// A standalone sample of the real material for §3.2's Settings row — real
    /// glass, not a mock-up: the same `.sidebar` plane and `.control` pill the
    /// browser window uses, pinned to one column of §7's table so both can be
    /// shown at once on the same screen.
    ///
    /// Decorative (§8): the segmented control beside it carries the meaning.
    @MainActor
    static func previewTile(size: NSSize, optimised: Bool) -> NSView {
        let tile = NSView(frame: NSRect(origin: .zero, size: size))

        // The plane, rounded by the glass itself rather than by a layer mask —
        // `cornerRadius` is one of the four knobs it has.
        let plane = GlassBackingView(
            style: .sidebar,
            cornerRadius: Tokens.Metric.glassPreviewTile.cornerRadius,
            cornerCurve: .continuous,
            maskedCorners: Glass.allCorners,
            pinned: optimised
        )
        plane.frame = tile.bounds
        plane.autoresizingMask = [.width, .height]
        tile.addSubview(plane)

        // The control on top of it: the pair §7 changes, and the pair whose
        // difference is the point of the setting.
        let pill = GlassBackingView(
            style: .control,
            cornerRadius: Tokens.Metric.urlPill.cornerRadius,
            cornerCurve: .continuous,
            maskedCorners: Glass.allCorners,
            pinned: optimised
        )
        pill.frame = tile.bounds.insetBy(
            dx: Tokens.Metric.chromeGapWide,
            dy: (size.height - Tokens.Metric.urlPill.height) / 2
        )
        pill.autoresizingMask = [.width, .height]
        tile.addSubview(pill)

        tile.setAccessibilityElement(false)
        return tile
    }

    /// One pass over every live glass view in the app.
    ///
    /// Rare and cheap: it runs on a display change and on a settings change,
    /// never on layout. A tree walk rather than a registry of live views — there
    /// is no weak table to leak, nothing to unregister, and a view that is not
    /// in a window has no screen to resolve against.
    @MainActor
    static func reapplyOptimisation() {
        for window in NSApplication.shared.windows {
            guard let root = window.contentView else { continue }
            refreshGlass(in: root)
        }
    }

    @MainActor
    private static func refreshGlass(in view: NSView) {
        (view as? GlassBackingView)?.refreshForDisplay()
        for subview in view.subviews { refreshGlass(in: subview) }
    }

    /// Idempotent, and called from every `GlassBackingView`'s initialiser, so
    /// the observers come up with the first piece of glass and no launch-time
    /// wiring has to remember to do it.
    @MainActor
    static func beginObservingDisplayChanges() {
        DisplayScale.beginObserving()
    }
}

// MARK: - Detection

/// §7's storage and its two notification observers. Not part of the published
/// API — everything outside `Design/` goes through `Glass`.
@MainActor
enum DisplayScale {

    /// §6's persistence table. Not renamed, ever: it is the key §3.2's
    /// Appearance row reads back.
    static let defaultsKey = "appearance.glassOptimisation"

    /// The density Liquid Glass was designed against. Below it, §7 applies.
    static let retinaScale: CGFloat = 2

    /// Lazily read from `UserDefaults` on first access, so this works whether or
    /// not `SettingsDefaults.register()` has run. An unknown or absent value is
    /// `.auto`, which is §7's default anyway.
    static var optimisation: GlassOptimisation = GlassOptimisation(
        rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? ""
    ) ?? .auto

    static func beginObserving() {
        _ = observer
    }

    /// `static let` is lazy in Swift, so this is built once, on the first
    /// `beginObserving()`, and lives for the process.
    private static let observer = Observer()

    /// One observer for the whole app rather than one per glass view: the
    /// handler re-applies to everything in one pass regardless of which window
    /// posted, so per-view observers would run the same pass N times.
    @MainActor
    private final class Observer {
        init() {
            let center = NotificationCenter.default
            // Posted per window, so `object: nil` — Luna opens more windows than
            // exist at the moment this observer is created.
            center.addObserver(
                self, selector: #selector(displayChanged),
                name: NSWindow.didChangeBackingPropertiesNotification, object: nil
            )
            // The screen changed under a window that never moved.
            center.addObserver(
                self, selector: #selector(displayChanged),
                name: NSApplication.didChangeScreenParametersNotification, object: nil
            )
        }

        @objc private func displayChanged(_ notification: Notification) {
            Glass.reapplyOptimisation()
        }
    }
}

// MARK: - §7's tokens

extension Tokens.Ink {

    /// §7's thickened chrome tint, for `.sidebar` and `.topBar` at 1×.
    ///
    /// +0.16 on `glassTint`, flat, in every variant, and the size of that step
    /// is measured. `tintColor` on a `.regular` glass view does not composite a
    /// colour over the backdrop the way §2's prose assumes. Swept on this
    /// machine (macOS 26.5, dark, 1×, over a blue desktop, mean luminance of a
    /// 600 × 200 plane):
    ///
    ///     alpha  0.00  0.20  0.34  0.44  0.70  1.00
    ///     lum   47.07 52.12 55.96 58.18 64.95 72.33
    ///
    /// Linear, ≈ +25.3 luminance units per unit alpha, and hue-independent: red,
    /// blue, yellow and white at alpha 1.0 all render byte-identically. So the
    /// knob buys a flat brightening and nothing else. +0.16 is ≈ +4 luminance
    /// units, the largest step available while still leaving the chrome
    /// transmitting a third of the desktop (§2). Reaching Luna's smallest
    /// deliberate surface step — `raised` over `base`, ~13 units — would need
    /// Δalpha ≈ 0.51 and put the chrome past 0.85, which is a plane, not glass.
    ///
    /// It does not suppress banding. Over the same sweep the standard deviation
    /// of the transmitted backdrop stayed at 6.85–7.20 (ratio 0.98–1.04 against
    /// no tint). §7 attributes the 1× banding fix to this tint; the measurement
    /// says it comes entirely from `style`, where `.regular` transmits sd ≈ 7.0
    /// against `.clear`'s ≈ 17.7. This row of §7's table is close to a no-op and
    /// is kept because the table is the published contract.
    static let glassTintDense = InkAlphas(light: 0.48, dark: 0.50, contrastLight: 0.64, contrastDark: 0.66)

    /// §7's control tint, for `.control` at 1× — the tint it does not have at
    /// 2×, where `.clear`'s refraction is what lifts a control off the bar.
    ///
    /// Exactly half of `glassTint` in every variant, and half rather than more
    /// because more does not buy what §2 wants. Measured by flipping this
    /// setting on one window over one backdrop, dark, 1×, control against the
    /// bar behind it:
    ///
    ///                    2× rendering   1× optimised
    ///     URL pill           +6.07          −8.19
    ///     control circle     +7.12          −3.24
    ///     row backing        +0.79         −16.03
    ///
    /// A control on `.regular` glass over a `.regular` bar comes out below it,
    /// and by the brightness law above, closing an 8-unit gap would take
    /// Δalpha ≈ 0.32 on top of what the bar already has — past the point where
    /// the control stops being glass. So the honest description is "a small lift
    /// on a control that now reads as inset", not "restores the raised read".
    /// `TokenCheck` re-derives the halving.
    static let glassTintControl = InkAlphas(light: 0.16, dark: 0.17, contrastLight: 0.24, contrastDark: 0.25)
}

extension Tokens.Surface {

    /// §7's 1× replacement for `glassTint` on `.sidebar` and `.topBar`. A plane
    /// tint like `glassTint`, not ink — see `surfaceTintColor`.
    static var glassTintDense: NSColor {
        surfaceTintColor("luna.surface.glassTintDense", Tokens.Ink.glassTintDense)
    }

    /// §7's 1× tint for `.control`, which is untinted at 2×.
    static var glassTintControl: NSColor {
        surfaceTintColor("luna.surface.glassTintControl", Tokens.Ink.glassTintControl)
    }
}
