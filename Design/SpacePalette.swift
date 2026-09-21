//
//  SpacePalette.swift
//  Luna
//
//  §8.2's twelve curated Space gradients, the three intensities §8.2a uses them
//  at, and the luminance-derived ink that keeps text on them readable.
//
//  The second and only other file holding colour values. §8.1's "no literal hex
//  outside Tokens.swift" is about the chrome token system, and §8.2 asks for
//  something that file cannot hold: the pairs are `GradientPair`, a BrowserKit
//  value type that crosses the SQLite boundary, and they are data a user owns
//  rather than a token. The rule is kept by the same mechanism — the hex entry
//  point below is private and can only produce a `GradientPair`.
//
//  THE MEASURED CONSTRAINT THAT SHAPED THE PALETTE, and the whole of §13.6. A
//  two-stop gradient can only carry one ink: white clears 4.5:1 only below
//  relative luminance 0.183, black only above 0.175. A pair whose stops
//  straddle that line has no legible ink for at least one stop. Every pair
//  below is therefore a hue sweep at near-constant luminance, in one of three
//  bands:
//
//      deep   L ≈ 0.115  → white ink, 6.3:1 worst
//      mid    L ≈ 0.300  → black ink, 7.0:1 worst
//      light  L ≈ 0.560  → black ink, 10.2:1 worst
//
//  The bands rotate deep → mid → light so consecutive Spaces differ in weight
//  as well as hue, and `next(after:)` hands them out in that order.
//
//  Every ratio quoted here is re-derived from the live SDK by
//  `SpaceGradientTests`, in both themes, for all twelve pairs. Do not round
//  them.
//

import AppKit
import BrowserKit

/// §8.2a's three intensities, and the only three. A gradient painted at any
/// other strength has not been measured and may not carry text.
///
/// Top-level rather than nested in `Tokens.Gradient` for the same reason
/// `InkAlphas` and `SRGB` are: SwiftLint's nesting rule stops at one level and
/// `Tokens` has already spent it.
enum GradientIntensity: Sendable, Hashable, CaseIterable {
    /// The Space badge and the §3.5 dots — the pair at full strength, opaque,
    /// and the only intensity whose ink has to be derived.
    case full
    /// §8.2a's 12–18 % sidebar wash. See `Tokens.Gradient.washAlpha`.
    case wash
    /// §8.2a's 3–4 px bar at the head of the content pane. Full strength, but
    /// nothing is ever drawn on top of it.
    case edge
}

extension Tokens {
    /// §8.2's Space gradients: the palette, the assignment rule, the three
    /// intensities, and the ink that survives them.
    enum Gradient {
        /// §8.2a's wash, at the middle of its 12–18 % range.
        ///
        /// Measured. `Text.primary` and `Text.secondary` clear §21.4 over all
        /// twenty-four stops in both themes at this value (worst 9.96:1 and
        /// 4.82:1 at 18 %). `Text.tertiary` does not, at any alpha in the range
        /// — 4.38:1 at 12 %, 3.92:1 at 18 % — so it is excluded from washed
        /// chrome. Do not raise this past 0.18: the headroom belongs to the
        /// text.
        static let washAlpha = 0.16

        /// §21.4's floor, repeated here so `foreground` has no hidden constant.
        static let textFloor = 4.5

        /// §8.2's twelve, in assignment order (contract: agent D publishes).
        ///
        /// Adding a thirteenth is safe — `next(after:)` reads the count — but it
        /// must be measured into one of the three bands first.
        static let spacePalette: [GradientPair] = [
            pair(0x6A30F1, 0x1A5CBD), // 1  Indigo   deep   violet → blue
            pair(0xF16E22, 0xBC8E0F), // 2  Ember    mid    orange → amber
            pair(0x79D8AE, 0x7ED3D9), // 3  Mint     light  green  → aqua
            pair(0xB0236A, 0x9F25A8), // 4  Mulberry deep   rose   → purple
            pair(0x1CA3B8, 0x5897E8), // 5  Tide     mid    cyan   → blue
            pair(0xE9C27E, 0xC8CE73), // 6  Sand     light  gold   → olive
            pair(0x396B13, 0x126E2A), // 7  Moss     deep   olive  → pine
            pair(0xDB5FF9, 0xF558BB), // 8  Orchid   mid    violet → pink
            pair(0xFF99B4, 0xFFAB9E), // 9  Blush    light  pink   → peach
            pair(0xB22D19, 0x8C510E), // 10 Rust     deep   red    → bronze
            pair(0x18AB53, 0x17A798), // 11 Jade     mid    green  → teal
            pair(0x8ECEED, 0xA8AEFF) // 12 Frost    light  sky    → periwinkle
        ]

        /// The display names of `spacePalette`, index for index.
        static let spacePaletteNames = [
            "Indigo", "Ember", "Mint", "Mulberry", "Tide", "Sand",
            "Moss", "Orchid", "Blush", "Rust", "Jade", "Frost"
        ]

        /// §13.6's one click back to neutral, as a real pair rather than a nil.
        ///
        /// Modelling neutral as an absence would mean a nil-gradient branch in
        /// every surface that paints one, and the branch nobody writes is the
        /// one that ships Zen's bug — it has an open issue for being unable to
        /// unset a gradient at all. A desaturated grey pair instead: it washes
        /// to nothing, its dot is visible in both themes, and every path below
        /// treats it like any other pair.
        ///
        /// Deliberately not in `spacePalette`, so `next(after:)` never assigns
        /// it. Returning to neutral is something the user does.
        static let neutral = pair(0x8C9199, 0xA4A9B1)

        /// True for the pair `neutral` hands back — for a picker that wants to
        /// tick the row the Space is currently on.
        static func isNeutral(_ gradient: GradientPair) -> Bool {
            gradient == neutral
        }

        /// The next pair for a new Space, wrapping when all twelve are taken
        /// (contract: agent D publishes; agent B's `createSpace` calls it).
        ///
        /// Least-used wins, palette order breaks the tie, so deleting a Space
        /// frees its pair for reuse without anyone tracking a cursor. Pairs
        /// outside the palette (a custom one, `neutral`, or the legacy
        /// `GradientPair.defaultSpace`) are ignored rather than counted, so one
        /// Space on a custom colour does not push every later Space off by one.
        static func next(after used: [GradientPair]) -> GradientPair {
            var counts: [GradientPair: Int] = [:]
            for gradient in used where spacePalette.contains(gradient) {
                counts[gradient, default: 0] += 1
            }
            let choice = spacePalette.enumerated().min { lhs, rhs in
                let left = (counts[lhs.element] ?? 0, lhs.offset)
                let right = (counts[rhs.element] ?? 0, rhs.offset)
                return left < right
            }
            // `spacePalette` is a non-empty literal; the fallback is unreachable
            // and exists so this is not a force-unwrap.
            return choice?.element ?? neutral
        }

        // MARK: - Surfaces

        /// The pair's two stops as they actually land on screen at `intensity`,
        /// opaque and resolved for `appearance`.
        ///
        /// Opaque is the point: §21.4 is measured against what the eye receives,
        /// and a 16 % wash on its own is not that. The wash is flattened onto
        /// `Surface.glassFallback`, the system's own stand-in for what is behind
        /// the sidebar.
        static func planes(
            _ gradient: GradientPair,
            at intensity: GradientIntensity,
            in appearance: NSAppearance
        ) -> (start: NSColor, end: NSColor) {
            let stops = (NSColor(gradient.start), NSColor(gradient.end))
            guard intensity == .wash else { return stops }
            let plane = Tokens.Surface.glassFallback
            return (
                plane.blended(toward: stops.0, fraction: washAlpha, in: appearance),
                plane.blended(toward: stops.1, fraction: washAlpha, in: appearance)
            )
        }

        /// The wash's two stops as they are painted, which is not what `planes`
        /// returns and must not be confused with it.
        ///
        /// `planes` flattens the wash so §21.4 can be measured against what the
        /// eye receives. This is the layer that produces that result: the pair
        /// held at `washAlpha`, so the glass underneath is still glass. Painting
        /// `planes`' opaque answer over the sidebar would leave no glass at all.
        ///
        /// Under Reduce Transparency (§21.2) the two coincide: there is nothing
        /// to see through, and the opaque flattened pair is correct.
        static func washStops(_ gradient: GradientPair, in appearance: NSAppearance) -> (start: NSColor, end: NSColor) {
            guard !Tokens.A11y.reduceTransparency else {
                return planes(gradient, at: .wash, in: appearance)
            }
            return (
                NSColor(gradient.start).withAlphaComponent(washAlpha),
                NSColor(gradient.end).withAlphaComponent(washAlpha)
            )
        }

        /// The drawable gradient at `intensity`. Nil only if AppKit rejects the
        /// stops, which sRGB components in 0...1 never do.
        static func nsGradient(
            _ gradient: GradientPair,
            at intensity: GradientIntensity,
            in appearance: NSAppearance
        ) -> NSGradient? {
            let stops = planes(gradient, at: intensity, in: appearance)
            return NSGradient(starting: stops.start, ending: stops.end)
        }

        // MARK: - §13.6 ink

        /// Ink for text drawn on `gradient` at `intensity`, derived from that
        /// gradient's own luminance rather than from a fixed token.
        ///
        /// Three candidates, in order of preference:
        ///
        ///   1. `Tokens.Text.primary` — the chrome's own ink, preferred wherever
        ///      it clears, so a washed sidebar still looks like the rest of the
        ///      app.
        ///   2. White, 3. Black — opaque, so they are the strongest ink
        ///      available and Increase Contrast has nothing left to add.
        ///
        /// Both stops must clear `textFloor`, not just the one under the label:
        /// a gradient moves under a row as the sidebar resizes.
        ///
        /// `appearance` is load-bearing. At `.full` the surface is opaque and
        /// theme-independent, but `Text.primary` is not — black in light, white
        /// in dark — so on a light pair (`Mint`, `Sand`, `Blush`, `Frost`)
        /// candidate 1 clears in light and fails in dark, and this returns black
        /// ink in dark mode. That is the case Zen ships unreadable.
        static func foreground(
            on gradient: GradientPair,
            at intensity: GradientIntensity = .full,
            in appearance: NSAppearance
        ) -> NSColor {
            let stops = planes(gradient, at: intensity, in: appearance)
            let white = NSColor(white: 1, alpha: 1)
            let black = NSColor(white: 0, alpha: 1)
            // `Text.primary` first, so a surface that can keep the chrome's own
            // ink does; only a gradient that defeats it falls through.
            let candidates = [Tokens.Text.primary, white, black]
            if let ink = candidates.first(where: { ratio($0, on: stops, in: appearance) >= textFloor }) {
                return ink
            }
            // Unreachable for any colour: white clears below L 0.183 and black
            // above 0.175, and the ranges overlap. A custom pair that straddles
            // the line still lands here, so answer with whichever is least bad.
            return ratio(white, on: stops, in: appearance) >= ratio(black, on: stops, in: appearance) ? white : black
        }

        /// The worst of `ink`'s two contrast ratios against a pair's stops.
        static func ratio(
            _ ink: NSColor,
            on stops: (start: NSColor, end: NSColor),
            in appearance: NSAppearance
        ) -> Double {
            min(
                ink.contrastRatio(over: stops.start, in: appearance),
                ink.contrastRatio(over: stops.end, in: appearance)
            )
        }
    }
}

/// The frozen free function from the Wave 1 contract — agents B and C compile
/// against this spelling. `Tokens.Gradient.foreground(on:at:in:)` is the same
/// answer with the intensity spelled out.
func foreground(on gradient: GradientPair, appearance: NSAppearance) -> NSColor {
    Tokens.Gradient.foreground(on: gradient, at: .full, in: appearance)
}

// MARK: - The only hex in this file, and it can only become a gradient

/// 0xRRGGBB → an opaque `RGBA`. Private, and only ever called by `pair`.
private func rgba(_ hex: UInt32) -> RGBA {
    RGBA(
        r: Double((hex >> 16) & 0xFF) / 255,
        g: Double((hex >> 8) & 0xFF) / 255,
        b: Double(hex & 0xFF) / 255,
        a: 1
    )
}

/// The file's whole colour vocabulary: two hex triples in, one `GradientPair`
/// out. There is no way to spell a chrome colour here, which keeps §8.1's rule
/// a matter of visibility rather than of review.
private func pair(_ start: UInt32, _ end: UInt32) -> GradientPair {
    GradientPair(start: rgba(start), end: rgba(end))
}
