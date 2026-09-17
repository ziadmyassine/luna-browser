//
//  Metrics.swift
//  Luna
//
//  Every number in `docs/UI-SPEC.md` §1, under the names §1 gives them, plus
//  the §1 type scale. Split out of `Tokens.swift` only to keep that file under
//  SwiftLint's length limits — `Metric` and `TypeScale` are still `Tokens.*`.
//
//  §1 derives these as ratios against a 280 pt sidebar. **The ratios are not
//  here on purpose**: §1 says chrome metrics do not rescale when the sidebar is
//  resized, so shipping them as code would only invite someone to multiply by
//  them. They fixed the proportions once; these are the result.
//

import AppKit

/// A user-resizable span (§3.7: drag to resize, double-click resets).
struct SpanMetric: Sendable {
    var `default`: CGFloat
    var min: CGFloat
    var max: CGFloat

    /// Clamps a live drag into range.
    func clamp(_ value: CGFloat) -> CGFloat { Swift.min(Swift.max(value, min), max) }
}

/// A sized, rounded chrome element. A `cornerRadius` of exactly `height / 2`
/// is §1's "radius (full)" — a pill.
struct RoundedMetric: Sendable {
    var width: CGFloat
    var height: CGFloat
    var cornerRadius: CGFloat

    var size: CGSize { CGSize(width: width, height: height) }

    /// A circle: §1 quotes these as a single diameter.
    static func circle(_ diameter: CGFloat) -> RoundedMetric {
        RoundedMetric(width: diameter, height: diameter, cornerRadius: diameter / 2)
    }
}

extension Tokens {

    /// Non-colour constants. Sendable values, no isolation needed.
    enum Metric {

        // MARK: Sidebar (§1, §3)

        /// 280 / 180 / 420 pt. Everything else in §1 is proportioned to the default.
        static let sidebarWidth = SpanMetric(default: 280, min: 180, max: 420)
        /// 40 pt — tabs, `Archive` and `+ Add Tab` alike (§3.4, §30.6).
        static let rowHeight: CGFloat = 40
        /// 8 pt inset of the row pill from each sidebar edge (§3.4).
        static let rowInset: CGFloat = 8
        static let faviconSize: CGFloat = 18
        static let rowCornerRadius: CGFloat = 10

        // MARK: URL pill (§3.2)

        /// 266 × 32, full radius.
        static let urlPill = RoundedMetric(width: 266, height: 32, cornerRadius: 16)

        // MARK: Essentials (§3.3)

        /// 128 × 42, radius 12. Icon only — no label (§30.5).
        static let essentialsTile = RoundedMetric(width: 128, height: 42, cornerRadius: 12)
        static let essentialsTileGap: CGFloat = 10
        static let essentialsIcon: CGFloat = 22

        // MARK: Controls (§3.1, §3.5)

        /// Back and reload: 35 pt circles.
        static let controlCircle = RoundedMetric.circle(35)
        /// Sidebar toggle: 28 pt, radius 9.
        static let controlSquircle = RoundedMetric(width: 28, height: 28, cornerRadius: 9)
        /// Profile avatar and archive: 34 pt circles.
        static let bottomCircle = RoundedMetric.circle(34)
        /// The Space switcher (§3.5): 56 × 22, radius 11, widening 8 pt per
        /// Space beyond three.
        static let spaceDotsPill = RoundedMetric(width: 56, height: 22, cornerRadius: 11)
        /// Widening per Space past the third (§3.5).
        static let spaceDotsPillGrowth: CGFloat = 8
        static let spaceDot: CGFloat = 6

        // MARK: Window and content card (§1, §3.6, §4)

        static let windowCornerRadius: CGFloat = 18
        static let contentCardRadius: CGFloat = 16
        /// The 8 pt gap that shows the window's glass and makes the card float (§30.11).
        static let contentCardGap: CGFloat = 8
        /// Both the top-bar layout's bar and the sidebar's control / utility rows (§3.1, §3.5, §4).
        static let topBarHeight: CGFloat = 52
        /// 1 pt. The *colour* is `Tokens.Line.hairline`.
        static let hairline: CGFloat = 1
        /// §3.7: 8 pt hit area, 20 × 32 drawn handle.
        static let resizeHandleHitWidth: CGFloat = 8
        static let resizeHandle = RoundedMetric(width: 20, height: 32, cornerRadius: 10)

        // MARK: Downloads popover (§5)

        /// ~330 × 58, radius 14.
        static let downloadsPopover = RoundedMetric(width: 330, height: 58, cornerRadius: 14)
        static let downloadsFileIcon: CGFloat = 34
        static let downloadsConfirm = RoundedMetric(width: 30, height: 30, cornerRadius: 9)

        // MARK: Window (M0 — consumed by `BrowserWindowController`)

        static let windowMinWidth: CGFloat = 640
        static let windowMinHeight: CGFloat = 480
        static let windowDefaultWidth: CGFloat = 1200
        static let windowDefaultHeight: CGFloat = 800
    }

    /// §1's type scale. System font throughout (§8.6/§8.7).
    ///
    /// Every face here is the **monospaced-digit** system font: §1 asks for
    /// tabular digits "wherever a number is shown", and a badge, a download
    /// size and a row title are all drawn with these four. The letterforms are
    /// identical to the plain system font, so this costs nothing and removes
    /// the chance of someone forgetting it on the one label that jitters.
    ///
    /// `var`, not the `let` the contract sketched: `NSFont` is **not**
    /// `NS_SWIFT_SENDABLE` in the macOS 26.5 SDK (verified in `NSFont.h`), so a
    /// `static let NSFont` is a Swift 6 strict-concurrency error. Computed
    /// statics have no storage and are safe.
    enum TypeScale {
        /// 15 pt — sidebar rows (§1; deliberately roomier than §8.6's 13 pt).
        static var sidebarRow: NSFont { .monospacedDigitSystemFont(ofSize: 15, weight: .regular) }
        /// 17 pt — the sidebar URL pill.
        static var urlPill: NSFont { .monospacedDigitSystemFont(ofSize: 17, weight: .regular) }
        /// 15 pt — the same pill in top-bar layout, where it shares the bar.
        static var topBarURL: NSFont { .monospacedDigitSystemFont(ofSize: 15, weight: .regular) }
        /// 12 pt semibold — section labels.
        static var sectionLabel: NSFont { .monospacedDigitSystemFont(ofSize: 12, weight: .semibold) }
        /// 14 pt — the §5 downloads filename.
        static var downloadFilename: NSFont { .monospacedDigitSystemFont(ofSize: 14, weight: .regular) }
    }
}
