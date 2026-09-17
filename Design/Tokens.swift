//
//  Tokens.swift
//  Luna
//
//  THE ONLY FILE IN LUNA PERMITTED TO CONTAIN A COLOUR VALUE (§0.3, §8.1).
//  Everything visual references a semantic token from here. No hex, no
//  `NSColor.white`, no `.systemBlue` anywhere else. If a view needs a colour
//  that isn't here yet, add a named token here first.
//
//  Two rules for anything added below:
//    1. Semantic names only. `Surface.base`, never `gray900`.
//    2. Every colour resolves for light *and* dark (§8.1), live. Prefer a
//       semantic system colour — it already handles Increase Contrast and
//       Reduce Transparency (§21.2), which a hex value silently does not.
//       Only go custom where the system has no right answer, and say why.
//       Never sample `NSApp.effectiveAppearance` once at startup; a browser
//       window changes appearance while running and a stale colour is a bug.
//
//  Concurrency: `NSColor` is `NS_SWIFT_SENDABLE`, its semantic class
//  properties are nonisolated, and every token here is a *computed* static
//  with no storage — so there is no shared mutable state and no isolation is
//  required. Do not "fix" this file with `@MainActor` or `nonisolated(unsafe)`.
//
//  System-backed vs custom, at a glance:
//    system  Surface.base, Text.primary, Accent.tint, Accent.danger
//    custom  Surface.raised, Surface.glassFallback, Surface.hover,
//            Surface.selected, Surface.chromeFill, Surface.glassTint,
//            Text.secondary,
//            Text.tertiary, Text.disabled, Line.border, Shadow.popover,
//            Bloom.*
//    hybrid  Line.hairline (`.separatorColor` normally, promoted by hand
//            under Increase Contrast — see the comment there)
//
//  Opaque planes vs translucent washes: `Surface.base`/`raised`/`glassFallback`
//  are planes and are opaque. `Surface.hover`/`selected`/`chromeFill` are
//  washes that sit *over* Liquid Glass and must stay translucent or the glass
//  they cover stops being glass. `TokenCheck` asserts both halves.
//
//  MEASURED, and it changes how every one of these is written: on macOS 26.5
//  **Increase Contrast is not an appearance.** `NSAppearance(named:)` maps
//  `.accessibilityHighContrastAqua` onto the *identical object* as `.aqua`
//  (verified: `===`), and the same for the dark and vibrant pairs. So a
//  dynamic provider cannot see the setting, and `NSColor` gets no appearance
//  change to invalidate against. The live signal is
//  `NSWorkspace.accessibilityDisplayShouldIncreaseContrast`, which is why the
//  tokens below are computed statics that branch on `A11y` *before* building
//  their dynamic colour.
//
//  **UI agents: that means a view must redraw itself when the setting flips.**
//  Observe `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` on
//  `NSWorkspace.shared.notificationCenter` and invalidate — `Glass` does.
//
//  Ratios below are measured, not estimated: every one is re-derived by
//  `TokenCheck` against the live SDK, in both themes and both contrast modes.
//

import AppKit

enum Tokens {

    // MARK: - Surfaces

    /// Background planes (§8.1 `surface/0..3`), listed in the order they stack
    /// on screen rather than by brightness — light mode recedes by getting
    /// darker, dark mode by getting *lighter*, which is how AppKit's own
    /// sidebars behave.
    enum Surface {
        /// The opaque content plane: the §3.6 content card, and the deepest
        /// plane behind everything else. System-backed.
        /// #FFFFFF light / #1E1E1E dark.
        static var base: NSColor { .windowBackgroundColor }

        /// One visible step above `base`: control fills, Essentials tiles and
        /// the §5 downloads popover. Also the Reduce Transparency fallback for
        /// `Glass.Style.control` and `.popover`.
        ///
        /// Custom, because on macOS 26 every candidate system colour
        /// (`controlBackgroundColor`, `textBackgroundColor`) resolves to
        /// *exactly* `windowBackgroundColor` — #FFFFFF light / #1E1E1E dark —
        /// so a system-backed `raised` would be indistinguishable from `base`.
        /// These give a 1.14:1 (light) / 1.18:1 (dark) step: visible, not loud.
        static var raised: NSColor {
            dynamicColor(light: 0xF0_F0_F0, dark: 0x2B_2B_2B)
        }

        /// What sidebar / top-bar glass becomes under Reduce Transparency
        /// (§2, §21.2). Custom, and deliberately *not* `base`: §2 says glass
        /// falls back to `base`, but the §3.6 content card is `base` too, so
        /// obeying that literally makes the card vanish into the chrome and
        /// kills the whole floating read. This is the chrome plane instead —
        /// 1.25:1 from `base` in light, 1.09:1 in dark, and on the far side of
        /// `raised` in both, so controls still sit above the bar.
        static var glassFallback: NSColor {
            dynamicColor(light: 0xE4_E4_E4, dark: 0x23_23_23)
        }

        // The three below are **washes, not planes**: translucent by
        // construction, because everything they cover is Liquid Glass and an
        // opaque plate over glass is just a plate. They are ink — black on
        // light, white on dark — rather than a fixed white, since a 6 % white
        // over light-mode glass is not a hover state, it is nothing.
        //
        // A wash sits under text and therefore spends §21.4 headroom. Measured
        // over every plane, in both themes and both contrast modes:
        // `Text.primary` stays above 6.9:1 and `Text.secondary` above 4.68:1
        // through all three. `Text.tertiary` does **not** — see its comment.

        /// §3.1 and §3.4's "hover **lifts the fill**", at §3.4's 6 %.
        ///
        /// Custom: AppKit has no translucent hover fill to borrow —
        /// `selectedContentBackgroundColor` is an opaque accent rectangle,
        /// which §8.4 rules out ("never a hard blue rect"). Until this existed
        /// the sidebar and the top bar could only brighten their glyphs on
        /// hover, which is the half of the rule that shows least.
        static var hover: NSColor { inkColor("luna.surface.hover", Ink.hover) }

        /// §3.4's selected-row pill: the same wash at twice the lift, so a
        /// selected row still reads as selected while the pointer sits on it.
        /// §3.4 also asks for a visible border on it — that is `Line.border`.
        ///
        /// **Unselected rows get no fill at all** (§30.7); this is not a
        /// default row background.
        static var selected: NSColor { inkColor("luna.surface.selected", Ink.selected) }

        /// §2's URL-pill fill — the pill is `.control` glass **plus** a
        /// page-derived wash, and the only page-tinted surface in the app.
        ///
        /// It exists because `wash(_:over:upTo:keeping:)` returns a *fill*, and
        /// a fill built on an opaque plane (`raised`) put an opaque plate over
        /// the pill's glass and stopped it being glass. Blending on top of this
        /// instead keeps the result translucent: `blended` is alpha-correct, so
        /// §2's 12–18 % stays 12–18 % of what reaches the eye through the
        /// glass. Pass it as `over:`; it is not a plane and nothing should
        /// paint text directly against it without flattening first.
        static var chromeFill: NSColor { inkColor("luna.surface.chromeFill", Ink.chromeFill) }

        /// A **well**: the resting fill of a dormant chrome control — §3.2's
        /// URL pill and §3.3's pinned tiles.
        ///
        /// **Darker than the surface it is cut into, in both themes.** It was
        /// `hover`, which is ink — white on dark — so a dormant tile came out
        /// *lighter* than the sidebar and read as a raised plate, the opposite
        /// of `inspiration/main-tab-bar-and-ui.png`, where the field and the
        /// tiles are recessed wells with a lighter hairline on the edge. This
        /// is black in both themes (`recessInkColor`); the hairline is
        /// `Line.border` as before, and it is what catches the edge.
        static var well: NSColor { recessInkColor("luna.surface.well", Ink.well) }

        /// §2's chrome tint: what `Glass.Style.sidebar` / `.topBar` hand to
        /// `NSGlassEffectView.tintColor`.
        ///
        /// **Untinted glass is too thin.** `.regular` on its own samples the
        /// desktop so faithfully that the sidebar reads as a pane of the
        /// wallpaper rather than as a surface, and the reference's chrome is
        /// visibly denser and more saturated than what is behind it. The tint
        /// is what buys that density back, and it is a *plane* tint rather than
        /// ink (`surfaceTintColor`): deeper over a dark desktop, milkier over a
        /// light one.
        ///
        /// It does not apply under Reduce Transparency — there is no glass left
        /// to tint, `Surface.glassFallback` is already opaque, and a tint on
        /// top of it would just be a second, dimmer plane.
        static var glassTint: NSColor { surfaceTintColor("luna.surface.glassTint", Ink.glassTint) }
    }

    // MARK: - Text

    /// Foreground text (§8.1 `textPrimary/Secondary/Tertiary`).
    ///
    /// §21.4 floor is 4.5:1 on *every* surface in *both* themes. Worst case for
    /// each token, measured over `base`/`raised`/`glassFallback`:
    ///   primary    12.2:1   secondary  5.3:1   tertiary  4.6:1
    ///
    /// That floor is what compresses the ramp: `tertiary` can only drop to
    /// ~0.56 alpha before it fails, which is barely a step below `secondary`.
    /// **Do not lean on alpha alone to separate the two** — use size and weight
    /// (`TypeScale`) for hierarchy and treat these as "meets contrast" tiers.
    enum Text {
        /// System-backed. Increase Contrast drives it to full opacity for free.
        static var primary: NSColor { .labelColor }

        /// Custom, because `.secondaryLabelColor` **fails §21.4**: it is
        /// black at 50 %, which measures 3.95:1 on a white window — under the
        /// 4.5:1 floor. 60 % is the smallest round alpha that clears it.
        /// 5.74 / 5.52 / 5.32 light, 6.77 / 6.11 / 6.53 dark.
        static var secondary: NSColor { inkColor("luna.text.secondary", Ink.secondary) }

        /// Custom for the same reason, worse: `.tertiaryLabelColor` is black at
        /// 26 % — **1.88:1**, less than half the floor. These are the lowest
        /// alphas that still clear 4.5:1 on the worst surface:
        /// 4.94 / 4.77 / 4.63 light, 5.12 / 4.73 / 4.99 dark.
        ///
        /// **Not for text on a washed row.** Those ratios are on the bare
        /// planes and they are the floor — 4.63:1 worst — so any fill *under*
        /// the text spends headroom this tier does not have. Measured with
        /// `Surface.selected` beneath it, tertiary drops to 3.78:1 (`raised`,
        /// dark). `primary` and `secondary` survive every wash with room to
        /// spare and `TokenCheck` proves it; this one does not, and §3.4 asks
        /// for *brighter* text on a selected row anyway.
        static var tertiary: NSColor { inkColor("luna.text.tertiary", Ink.tertiary) }

        /// §3.1's disabled dim — the back button at **35 %** when `canGoBack`
        /// is false, and any other control that is showing but inert.
        ///
        /// **Exempt from §21.4's 4.5:1 floor, and the only token here that
        /// is.** WCAG 2.1 SC 1.4.3 exempts incidental text and names *inactive
        /// user-interface components* in the exemption: a disabled control is
        /// deliberately de-emphasised and cannot be operated, so a ratio that
        /// says "do not read this, you cannot use it" is the correct outcome
        /// rather than a regression. It measures ~2.4:1 on `base` in light.
        ///
        /// That exemption is exactly why this token may sit below the floor
        /// where `Text.tertiary` may not. **Do not reach for it to dim live
        /// text** — a tab title, a subtitle, a hint — no matter how quiet the
        /// design wants that text to be. `Text.tertiary` is the floor for
        /// anything a user is meant to read.
        static var disabled: NSColor { inkColor("luna.text.disabled", Ink.disabled) }
    }

    // MARK: - Lines

    /// Rules, dividers and control outlines (§8.1 `separator`, §1 `hairline`).
    enum Line {
        /// `.separatorColor` is the right *value* — it resolves to 9.8 % black /
        /// 9.8 % white, which is §1's "10 % white / 8 % black" hairline, and
        /// nothing hand-rolled beats it.
        ///
        /// **Qualified from M0:** whether it tracks Increase Contrast could
        /// not be verified — see the file header, the high-contrast
        /// appearances do not exist as separate objects on macOS 26.5, so
        /// there is no way to resolve the colour "under Increase Contrast"
        /// without toggling the real system setting. §2's "promote every
        /// hairline to 20 %" is therefore done here by hand. If AppKit already
        /// promotes it, this is redundant rather than wrong.
        static var hairline: NSColor {
            guard Tokens.A11y.increaseContrast else { return .separatorColor }
            return NSColor(name: "luna.line.hairline.contrast") { appearance in
                NSColor(white: appearance.isDark ? 1 : 0, alpha: Ink.hairlineContrast)
            }
        }

        /// The visible edge on a control or a selected row (§3.1, §3.4) — one
        /// step stronger than `hairline` so a glass button reads as a button.
        /// Custom: no system colour sits between `separatorColor` and
        /// `labelColor`.
        ///
        /// Under Increase Contrast this is §2's "adds a visible border to each
        /// control", so it jumps to 50 % — the lowest alpha that clears WCAG
        /// 1.4.11's 3:1 for a UI boundary on every surface (3.78:1 worst).
        static var border: NSColor { inkColor("luna.line.border", Ink.border) }
    }

    // MARK: - Accent

    /// **Fills, rings and glyphs only — never text.** Both are system-backed
    /// and both measure *under* 4.5:1 as text on Luna's surfaces: the user's
    /// accent at 4.02:1 on `base` light / 3.52:1 on `raised`, `systemRed` at
    /// 3.57:1 on `base` light. A view that needs coloured *text* must ask for
    /// a token here rather than tinting `Text.primary` itself.
    enum Accent {
        /// The user's System Settings accent. System-backed on purpose: a
        /// browser that ignores the accent choice looks foreign on macOS.
        static var tint: NSColor { .controlAccentColor }

        /// Destructive affordances — close, delete, stop. System-backed.
        static var danger: NSColor { .systemRed }
    }

    // MARK: - Reload bloom (§7)

    /// The §7 reload arc's gradient bands, **inner edge to outer**:
    /// `core` → `amber` → `mint` → `lavender`, white through to violet.
    ///
    /// **Measured, not chosen.** Sampled from
    /// `inspiration/refresh-animation-ui.mov` by ridge-tracking hue and chroma
    /// across three frames (t ≈ 1.40 / 1.55 / 1.70 s), then tuned until a real
    /// `CAGradientLayer` composite matched the clip to within ~1.2×
    /// saturation per band. Do not round them, and do not "correct" them from
    /// the `#EEECCA` / `#E1EBEF` / `#E2D0EE` triple §7 quotes — those are these
    /// bands *already composited* over the clip's paper-white page, so
    /// adopting them would apply the page twice. §7's prose also had mint and
    /// lavender transposed; the order below is the corrected one.
    ///
    /// **Theme-independent on purpose — this is not an oversight, do not add a
    /// dark variant.** These are *light emitted over page content*, not
    /// chrome: the arc is additive bloom over a blurred snapshot of whatever
    /// the page happens to be, so it has no surface to contrast against and
    /// nothing to re-tune per theme. A dark-mode set would make the same page
    /// bloom a different colour depending on a system setting, which is the
    /// one thing the reference never does. `TokenCheck` asserts every band
    /// resolves *identically* in light and dark, so that "fix" fails the check
    /// instead of shipping.
    ///
    /// Increase Contrast is not consulted either: there is nothing here to
    /// read, and §21.2's handle on this animation is Reduce Motion — which §7
    /// turns into "no blur, no arc" via `Motion.reduceMotion`, not into a
    /// louder arc.
    enum Bloom {
        /// #FFFFFF at 22 %. The flat inner core of the crescent.
        static var core: NSColor { NSColor(srgb: 0xFF_FF_FF, alpha: 0.22) }

        /// #F7F0A8 at 23 % — hue 56°.
        static var amber: NSColor { NSColor(srgb: 0xF7_F0_A8, alpha: 0.23) }

        /// #BBE9F5 at 24 % — hue 194°.
        static var mint: NSColor { NSColor(srgb: 0xBB_E9_F5, alpha: 0.24) }

        /// #D3ADF0 at 44 % — hue 277°, and the outermost band. It carries the
        /// whole visible edge of the arc as it fades out, which is why its
        /// alpha nearly doubles rather than continuing the gentle ramp.
        static var lavender: NSColor { NSColor(srgb: 0xD3_AD_F0, alpha: 0.44) }
    }

    // MARK: - Shadow (§5)

    /// The chrome's only drop shadow.
    enum Shadow {
        /// §2/§5's "heavier panel shadow" under the downloads popover.
        ///
        /// **This shadow is standing in for a material that does not exist.**
        /// §2 asks for "Liquid Glass, heavier"; `NSGlassEffectView.Style` ships
        /// `.regular` and `.clear` and nothing else (verified against
        /// MacOSX26.5.sdk — see `Glass.swift`), so the popover's extra visual
        /// weight has to come from the shadow or from nowhere. Do not delete
        /// it in favour of a heavier glass style; there isn't one.
        ///
        /// Black in both themes — a shadow is absent light, not a colour — but
        /// roughly twice the alpha in dark mode, where a soft edge against a
        /// dark desktop otherwise disappears. Increase Contrast pushes it
        /// further still: the popover renders *outside* the window, so its own
        /// edge is all that separates it from an arbitrary backdrop.
        static var popover: ShadowMetric {
            ShadowMetric(
                radius: 20,
                offset: CGSize(width: 0, height: -4),
                color: shadowInkColor("luna.shadow.popover", Ink.popoverShadow)
            )
        }
    }

    // MARK: - Ink alphas

    /// The alpha table behind the translucent tokens, in one place so it has
    /// one source of truth — the tokens build their colours from it, and
    /// `TokenCheck` re-measures the Increase Contrast variants from it. That
    /// second reader is the reason this is not private: the contrast branch is
    /// unreachable through an `NSAppearance` on macOS 26 (file header), so a
    /// check that could not read these alphas could not verify §2 at all.
    enum Ink {
        /// 5.74 / 5.52 / 5.32 light, 6.77 / 6.11 / 6.53 dark over
        /// base / raised / glassFallback.
        static let secondary = InkAlphas(light: 0.60, dark: 0.60, contrastLight: 0.78, contrastDark: 0.78)
        /// The floor: 4.94 / 4.77 / 4.63 light, 5.12 / 4.73 / 4.99 dark.
        static let tertiary = InkAlphas(light: 0.56, dark: 0.50, contrastLight: 0.70, contrastDark: 0.70)
        /// Decorative at rest; 3.78:1 worst case once Increase Contrast lifts it.
        static let border = InkAlphas(light: 0.14, dark: 0.16, contrastLight: 0.50, contrastDark: 0.50)
        /// §2's hairline promotion. There is no rest value: below Increase
        /// Contrast the hairline *is* `.separatorColor`.
        static let hairlineContrast = 0.20

        /// §3.4's 6 %. Doubled under Increase Contrast: a 6 % wash is the first
        /// thing to vanish for the users who turn that setting on.
        static let hover = InkAlphas(light: 0.06, dark: 0.06, contrastLight: 0.12, contrastDark: 0.12)
        /// §3.4's selected pill, twice `hover` so the two stay separable.
        /// Capped by §21.4, not by taste — `TokenCheck.checkFills` re-derives
        /// what the row's text measures once this wash is under it.
        static let selected = InkAlphas(light: 0.12, dark: 0.12, contrastLight: 0.22, contrastDark: 0.22)
        /// §2's URL-pill fill. Low enough that the glass behind it still reads
        /// as glass, high enough to give the page wash something to blend into.
        static let chromeFill = InkAlphas(light: 0.08, dark: 0.10, contrastLight: 0.14, contrastDark: 0.16)
        /// §2's chrome tint — see `Surface.glassTint`. Well short of opaque:
        /// the whole point of §2 is that the chrome samples the desktop, and a
        /// tint heavy enough to hide that would be a coloured rectangle.
        /// Increase Contrast thickens it, because a surface that is barely
        /// there is exactly what that setting exists to firm up.
        static let glassTint = InkAlphas(light: 0.46, dark: 0.50, contrastLight: 0.60, contrastDark: 0.64)
        /// `Surface.well` — a dormant control's recess. Deep enough in dark
        /// mode to read as cut into the plane rather than drawn on it; light
        /// mode needs far less, because a light surface shows a darkening at a
        /// much lower alpha.
        static let well = InkAlphas(light: 0.06, dark: 0.22, contrastLight: 0.12, contrastDark: 0.32)
        /// §3.1's 35 % dim. Exempt from §21.4 — see `Text.disabled`. It still
        /// gains under Increase Contrast, because "disabled" has to remain
        /// *legible as a control* even when it is not readable as text.
        static let disabled = InkAlphas(light: 0.35, dark: 0.35, contrastLight: 0.50, contrastDark: 0.50)
        /// §5's panel shadow — black in both themes, see `Shadow.popover`.
        static let popoverShadow = InkAlphas(light: 0.24, dark: 0.46, contrastLight: 0.40, contrastDark: 0.62)
    }
}

/// An opaque surface that re-resolves every time the appearance changes.
private func dynamicColor(light: UInt32, dark: UInt32) -> NSColor {
    NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor(srgb: dark) : NSColor(srgb: light)
    }
}

private extension NSColor {
    /// 0xRRGGBB, sRGB. The only hex entry point in the codebase, and private on
    /// purpose: §8.1's "no literal hex outside this file" is then a matter of
    /// visibility rather than of review. `alpha` defaults to opaque, for the
    /// planes; `Bloom` passes its measured emission alphas.
    convenience init(srgb hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
