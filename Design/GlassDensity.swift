//
//  GlassDensity.swift
//  Luna
//
//  §2a's **how much of the desktop comes through**: the setting, the two frost
//  planes it chooses between, and the pass that re-skins every live surface.
//  `Glass.swift` still owns the material; this file only decides how much is
//  painted behind it.
//
//  It is `DisplayScale.swift`'s shape on purpose — the setting, the storage,
//  the reapply pass, and the tokens declared beside the measurement that
//  justifies them. That file's header explains why §7's two tints are not in
//  `Tokens.swift`; the same argument holds here, and `Tokens.swift` is at 394
//  lines against SwiftLint's 400 with `make check` running `--strict`, so it
//  has no room for these either. No hex is written below, only alphas, and
//  every colour is built from a plane `Tokens.swift` already owns.
//
//  WHY FROST IS THE LEVER, AND NOT THE TINT. This is the same finding
//  `Surface.frost` was introduced for, and it is worth repeating because the
//  wrong knob is the obvious one. `tintColor` on a `.regular` glass view
//  brightens flatly — measured at ≈ +25 luminance units per unit alpha, and
//  hue-independent (`DisplayScale.swift`) — so "more tint" is a *lighter*
//  surface, not a denser one, and in dark mode where the tint is black it is a
//  dimmer one. Frost is a plane behind the glass: more of it transmits less of
//  the desktop, which is what "more opaque" means.
//
//  THE NUMBER IS MEASURED FROM MARTIN'S REFERENCE, not chosen — and the *first*
//  measurement of it was wrong, in a way worth writing down because it is the
//  easy mistake. Comparing means said the panel keeps ~45 % of the backdrop's
//  red, which read as "a dark plate with the colour coming through and none of
//  the shape", and gave 0.86. Look at the image instead of at its average and
//  the wallpaper's *shape* is plainly still there: the dark lobe, the bands,
//  the lighter corner. A mean cannot see that. Contrast can.
//
//  A flat plane over a blurred backdrop compresses contrast by exactly the
//  amount of plane there is, and that is linear in the alpha and independent of
//  how the blur moved the mean:
//
//      composite  =  a · plate  +  (1 − a) · blurred backdrop
//      sd(composite)            =  (1 − a) · sd(blurred backdrop)
//
//  Red channel, sampled off the reference, with the surrounding wallpaper box-
//  blurred to stand in for what the panel is sampling:
//
//      panel interior                  mean 52.0   sd 10.3   range 38–82
//      wallpaper, blur r=40            mean 85–109  sd 28.6–35.3
//      wallpaper, blur r=60            mean 85–107  sd 24.7–31.2
//      wallpaper, blur r=80            mean 84–106  sd 18.8–28.0
//
//      1 − a  =  10.3 / 28  ≈  0.37     →   a ≈ 0.63
//
//  The mean agrees independently: 0.66 × 35 + 0.34 × X = 52 solves to X = 85,
//  which is exactly where the blurred wallpaper beside the panel sits. Two
//  estimates from different statistics landing on the same answer is the
//  reason to trust it. Hence **0.66 dark** — a step above `Ink.frost`'s 0.50
//  rather than a different kind of surface, which is what Martin said when he
//  saw 0.86 on screen: *"start at the clear and decrease the translucency just
//  a bit more"*. 0.62 in light mode, where a light plane reads as covering at a
//  lower alpha for the same reason `Ink.well` is 0.06 light against 0.22 dark.
//
//  AND IT STAYS SHORT OF 1.0. `TokenCheck` asserts that frost is translucent in
//  every appearance, and the assertion is the design: at full strength the
//  frost *is* the Reduce Transparency fallback plane, there is no glass left
//  above it, and the setting would not be "more opaque" but "off".
//

import AppKit

// MARK: - The setting

/// §2a's pair, stored in `appearance.glassDensity`.
public enum GlassDensity: String, Sendable, CaseIterable {
    /// Today's chrome, and the default: the desktop refracts through a surface.
    case clear
    /// The reference above: a step denser, with the desktop still legibly
    /// *there* — softened and pushed back, not replaced.
    case opaque

    public var title: String {
        switch self {
        case .clear: "Clear"
        case .opaque: "Opaque"
        }
    }
}

extension Glass {

    /// §2a's setting.
    ///
    /// Assigning re-skins every glass surface in every open window in one pass —
    /// no relaunch, no window reopen — and persists to `appearance.glassDensity`.
    /// Reading it costs a dictionary lookup once per launch and nothing after.
    @MainActor
    static var density: GlassDensity {
        get { GlassDefaults.density }
        set {
            guard newValue != GlassDefaults.density else { return }
            GlassDefaults.density = newValue
            UserDefaults.standard.set(newValue.rawValue, forKey: GlassDefaults.densityKey)
            reapplyDensity()
        }
    }

    /// One pass over every live glass view in the app.
    ///
    /// Rare and cheap, and cheaper than §7's: the density changes a *plane*, not
    /// the material, so nothing is rebuilt — every backing simply redraws its
    /// own layer with the other frost. That also means no rebuild flash, which
    /// is the thing `GlassBackingView.layout()` goes to such lengths to avoid.
    @MainActor
    static func reapplyDensity() {
        for window in NSApplication.shared.windows {
            guard let root = window.contentView else { continue }
            refreshDensity(in: root)
        }
    }

    @MainActor
    private static func refreshDensity(in view: NSView) {
        (view as? GlassBackingView)?.refreshMaterial()
        // §9.1's backdrop carries the same frost, so it moves with the setting.
        (view as? GlassScrimView)?.refreshMaterial()
        for subview in view.subviews { refreshDensity(in: subview) }
    }
}

// MARK: - Storage

/// §2a's storage. Not part of the published API — everything outside `Design/`
/// goes through `Glass`, exactly as it does for §7's `DisplayScale`.
@MainActor
enum GlassDefaults {

    /// §6's persistence table. Not renamed, ever: it is the key §3.2's
    /// Appearance row reads back.
    static let densityKey = "appearance.glassDensity"

    /// Lazily read from `UserDefaults` on first access, so this works whether or
    /// not `SettingsDefaults.register()` has run — an unknown or absent value is
    /// `.clear`, which is §2a's default anyway.
    static var density: GlassDensity = GlassDensity(
        rawValue: UserDefaults.standard.string(forKey: densityKey) ?? ""
    ) ?? .clear
}

// MARK: - §2a's tokens

extension Tokens.Ink {

    /// §2a's opaque frost — see this file's header for where 0.62 / 0.66 come
    /// from, why they are a *step* above `frost` rather than a different kind
    /// of surface, and why they are not 1.0.
    ///
    /// Increase Contrast thickens it toward the opaque plane, for the same
    /// reason `frost` thickens: a surface that is barely there is exactly what
    /// that setting exists to firm up. It keeps the same headroom over `frost`
    /// there that it has at rest, so the setting means the same thing in both.
    static let frostOpaque = InkAlphas(light: 0.62, dark: 0.66, contrastLight: 0.80, contrastDark: 0.84)
}

extension Tokens.Surface {

    /// §2a's opaque chrome plane: `glassFallback` at `Ink.frostOpaque`, painted
    /// behind `.sidebar` and `.topBar` glass in place of `frost`.
    static var frostOpaque: NSColor {
        frostColor("luna.surface.frostOpaque", over: glassFallback, Tokens.Ink.frostOpaque)
    }

    /// §2a's opaque **popover** plane, for the Command Bar, the History pop-out
    /// and the downloads list.
    ///
    /// The same alpha over a different plane, and the plane is the whole
    /// difference: a popover's own Reduce Transparency fallback is
    /// `Surface.raised`, because §2 has it read as raised *above* the chrome
    /// rather than as more of it. Frosting it against `glassFallback` would
    /// have made a panel floating over the page the same colour as the sidebar
    /// behind it.
    ///
    /// There is no clear counterpart: at `.clear` density a popover takes the
    /// material neat, which is what §2 has always said it does.
    static var popoverFrostOpaque: NSColor {
        frostColor("luna.surface.popoverFrostOpaque", over: raised, Tokens.Ink.frostOpaque)
    }
}
