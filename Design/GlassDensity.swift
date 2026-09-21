//
//  GlassDensity.swift
//  Luna
//
//  §2a's how-much-of-the-desktop-comes-through: the setting, the two frost
//  planes it chooses between, and the pass that re-skins every live surface.
//  Glass.swift owns the material; this file only decides how much is painted
//  behind it.
//
//  DisplayScale.swift's shape on purpose — the setting, the storage, the
//  reapply pass, and the tokens declared beside the measurement that justifies
//  them. That file's header explains why §7's two tints are not in Tokens.swift
//  and the same argument holds here. No hex is written below, only alphas, and
//  every colour is built from a plane Tokens.swift already owns.
//
//  WHY FROST IS THE LEVER, AND NOT THE TINT. `tintColor` on a `.regular` glass
//  view brightens flatly — measured at ≈ +25 luminance units per unit alpha,
//  hue-independent (DisplayScale.swift) — so "more tint" is a lighter surface
//  rather than a denser one, and in dark mode, where the tint is black, a
//  dimmer one. Frost is a plane behind the glass: more of it transmits less of
//  the desktop, which is what "more opaque" means.
//
//  THE NUMBER IS MEASURED FROM MARTIN'S REFERENCE, and the first measurement
//  was wrong in a way worth writing down. Comparing means said the panel keeps
//  ~45 % of the backdrop's red, which gave 0.86 and read on screen as a dark
//  plate with the colour coming through and none of the shape. Look at the
//  image rather than its average and the wallpaper's shape is plainly still
//  there: the dark lobe, the bands, the lighter corner. A mean cannot see that.
//  Contrast can.
//
//  A flat plane over a blurred backdrop compresses contrast by exactly the
//  amount of plane there is, linear in the alpha and independent of how the
//  blur moved the mean:
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
//  which is where the blurred wallpaper beside the panel sits. Two estimates
//  from different statistics landing on the same answer is the reason to trust
//  it. Hence 0.66 dark — a step above `Ink.frost`'s 0.50 rather than a
//  different kind of surface, which is what Martin asked for when he saw 0.86:
//  "start at the clear and decrease the translucency just a bit more". 0.62 in
//  light, where a light plane reads as covering at a lower alpha, for the same
//  reason `Ink.well` is 0.06 light against 0.22 dark.
//
//  AND IT STAYS SHORT OF 1.0. `TokenCheck` asserts that frost is translucent in
//  every appearance, and the assertion is the design: at full strength the
//  frost is the Reduce Transparency fallback plane, there is no glass left
//  above it, and the setting would not be "more opaque" but "off".
//

import AppKit

// MARK: - The setting

/// §2a's pair, stored in `appearance.glassDensity`.
public enum GlassDensity: String, Sendable, CaseIterable {
    /// Today's chrome, and the default: the desktop refracts through a surface.
    case clear
    /// The reference above: a step denser, with the desktop still legibly
    /// there — softened and pushed back, not replaced.
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
    /// Rare and cheap, and cheaper than §7's: the density changes a plane, not
    /// the material, so nothing is rebuilt — every backing redraws its own layer
    /// with the other frost. That also means no rebuild flash, which is what
    /// `GlassBackingView.layout()` goes to such lengths to avoid.
    @MainActor
    static func reapplyDensity() {
        for window in NSApplication.shared.windows {
            guard let root = window.contentView else { continue }
            refreshDensity(in: root)
        }
    }

    @MainActor
    private static func refreshDensity(in view: NSView) {
        // Every glass surface in the app is a `GlassBackingView`, so this is the
        // whole pass. §9.1's Command Bar backdrop used to be the exception — it
        // carried the same frost from a different class and moved with the
        // setting, which is what made it wrong: at `.opaque` the bar sat on a
        // 0.66 sheet. There is no backdrop now (`CommandBarPanel`).
        (view as? GlassBackingView)?.refreshMaterial()
        for subview in view.subviews { refreshDensity(in: subview) }
    }
}

// MARK: - Storage

/// §2a's storage. Not part of the published API — everything outside `Design/`
/// goes through `Glass`, as it does for §7's `DisplayScale`.
@MainActor
enum GlassDefaults {

    /// §6's persistence table. Not renamed, ever: it is the key §3.2's
    /// Appearance row reads back.
    static let densityKey = "appearance.glassDensity"

    /// Lazily read from `UserDefaults` on first access, so this works whether or
    /// not `SettingsDefaults.register()` has run. An unknown or absent value is
    /// `.clear`, which is §2a's default anyway.
    static var density: GlassDensity = GlassDensity(
        rawValue: UserDefaults.standard.string(forKey: densityKey) ?? ""
    ) ?? .clear
}

// MARK: - §2a's tokens

extension Tokens.Ink {

    /// §2a's opaque frost. See the file header for where 0.62 / 0.66 come from,
    /// why they are a step above `frost` rather than a different kind of
    /// surface, and why they are not 1.0.
    ///
    /// Increase Contrast thickens it toward the opaque plane, for the same
    /// reason `frost` thickens, and keeps the same headroom over `frost` there
    /// that it has at rest, so the setting means the same thing in both.
    static let frostOpaque = InkAlphas(light: 0.62, dark: 0.66, contrastLight: 0.80, contrastDark: 0.84)
}

extension Tokens.Surface {

    /// §2a's opaque chrome plane: `glassFallback` at `Ink.frostOpaque`, painted
    /// behind `.sidebar` and `.topBar` glass in place of `frost`.
    static var frostOpaque: NSColor {
        frostColor("luna.surface.frostOpaque", over: glassFallback, Tokens.Ink.frostOpaque)
    }

    /// §2a's opaque popover plane, for the Command Bar, the History pop-out and
    /// the downloads list.
    ///
    /// The same alpha over a different plane, and the plane is the whole
    /// difference: a popover's Reduce Transparency fallback is `Surface.raised`,
    /// because §2 has it read as raised above the chrome rather than as more of
    /// it. Frosting it against `glassFallback` would have made a panel floating
    /// over the page the same colour as the sidebar behind it.
    ///
    /// There is no clear counterpart: at `.clear` density a popover takes the
    /// material neat, which is what §2 has always said it does.
    static var popoverFrostOpaque: NSColor {
        frostColor("luna.surface.popoverFrostOpaque", over: raised, Tokens.Ink.frostOpaque)
    }
}
