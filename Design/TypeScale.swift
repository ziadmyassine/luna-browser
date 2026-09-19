//
//  TypeScale.swift
//  Luna
//
//  §1's type scale. Split out of `Metrics.swift` when that file crossed
//  SwiftLint's 400-line limit; nothing changed on the way across.
//
//  It owns SF Symbol weight as well as font weight, and for the same reason:
//  this is the only file in Luna permitted to name an `NSFont.Weight`, and a
//  symbol is a face like any other. The size those symbols are set at is a
//  metric and stays in `Metrics.glyphSize`.
//

import AppKit

extension Tokens {

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
        /// 13 pt — sidebar rows.
        ///
        /// **Re-measured, and it overturns §1's 15 pt.** In
        /// `inspiration/main-tab-bar-and-ui.png` the row titles have a 20 px
        /// x-height and a 25 px cap height, which at the capture's 2.848 px/pt
        /// scale is a 13 pt system font — §8.6's original number. 15 pt was
        /// inferred from a scale that assumed the reference's sidebar was
        /// 280 pt; the sidebar is 268 pt and the type is 13.
        ///
        /// **Plain, not `monospacedDigit`.** §1 asks for tabular digits
        /// "wherever a number is shown"; a page title is not a number, and
        /// monospaced digits visibly widen a title like "iPhone 18 Pro". The
        /// numeric faces below keep them.
        static var sidebarRow: NSFont { .systemFont(ofSize: 13, weight: .regular) }
        /// 13 pt — the sidebar URL pill, measured at the **same** x-height as
        /// the rows. §1's 17 pt came from the same bad scale as the 15 pt above.
        static var urlPill: NSFont { .systemFont(ofSize: 13, weight: .regular) }
        /// 13 pt — the same pill in top-bar layout, where it shares the bar.
        static var topBarURL: NSFont { .systemFont(ofSize: 13, weight: .regular) }
        /// 15 pt — §9.1's Command Bar query.
        ///
        /// **One step above the chrome, because the bar is not chrome.** The
        /// sidebar's 13 pt is measured off the reference and is right for a
        /// column of two dozen rows you scan; the Command Bar is a single
        /// modal surface in the middle of the window that you look *at* while
        /// you type into it, and set at the sidebar's size it read as a chrome
        /// field that had floated loose. It is also the one field in Luna where
        /// what you typed is the whole content.
        static var commandBarQuery: NSFont { .systemFont(ofSize: 15, weight: .regular) }
        /// 14 pt — a §9.1 result row's title and its subtitle, held one step
        /// under the query so the list still reads as an answer to it rather
        /// than as more of it. §3.4's 38 pt row has the room.
        static var commandBarRow: NSFont { .systemFont(ofSize: 14, weight: .regular) }
        /// 12 pt semibold — section labels.
        static var sectionLabel: NSFont { .monospacedDigitSystemFont(ofSize: 12, weight: .semibold) }
        /// 14 pt — the §5 downloads filename.
        static var downloadFilename: NSFont { .monospacedDigitSystemFont(ofSize: 14, weight: .regular) }
        /// 15 pt semibold — a Settings group's title. One step above the body
        /// and the only place in Luna a heading appears over chrome.
        static var settingsHeading: NSFont { .systemFont(ofSize: 15, weight: .semibold) }
        /// 13 pt — a Settings control row's label, and a section name in the
        /// window's own column. **The sidebar's face, deliberately**: Settings
        /// is the same app, and a form set two points larger than the window
        /// behind it reads as a different one.
        static var settingsRow: NSFont { sidebarRow }
        /// 11 pt — the explanatory line under a Settings control. Plain, not
        /// `sectionLabel`: this is prose, and semibold tabular prose is a label
        /// pretending to be a sentence.
        static var settingsCaption: NSFont { .systemFont(ofSize: 11, weight: .regular) }
        /// 11 pt tabular — the caption's twin, for the one place it is holding
        /// a number: §6.4's row stamps each archived tab with the time it was
        /// closed, and a column of times set in proportional digits walks left
        /// and right as the minutes change under it.
        static var rowTimestamp: NSFont { .monospacedDigitSystemFont(ofSize: 11, weight: .regular) }

        /// The weight an SF Symbol has to be set at to draw the same *stroke*
        /// as the glyphs beside it.
        ///
        /// **One nominal weight is not one apparent weight.** SF Symbols are
        /// set to a shared cap height, and a mark that is small for its height
        /// is drawn heavier to stay legible at it. Measured at `glyphSize`, as
        /// the median run of ink across the mark — which is what the eye
        /// compares when it calls one icon thicker than another:
        ///
        ///     sidebar.leading         1.25 pt
        ///     plus                    1.38
        ///     arrow.down.to.line      1.38
        ///     arrow.clockwise         1.62
        ///     clock.arrow.circlepath  1.62
        ///     chevron.backward        2.00   ← at the same `.regular`
        ///
        /// Back is two short diagonals in a box 7.5 pt wide against its
        /// neighbours' 12 to 18.5, and SF Symbols pays for that smallness in
        /// stroke: at the weight everything else is set at, it is the heaviest
        /// line in the chrome — visibly thicker than the reload arrow it stands
        /// next to in §3.1 and §3.2b. `.light` draws it at 1.50, between the
        /// sidebar toggle and reload, and level with the top bar's median.
        ///
        /// **This used to read `.semibold`, and it was measuring the wrong
        /// thing.** Total ink said the chevron was the faintest mark on the bar
        /// — it is, because it is the smallest — and the correction made from
        /// that took its stroke to 3.00, twice the reload arrow's. Small is not
        /// the same as light, and only one of the two is a defect.
        ///
        /// Nothing else here is small for its height, so nothing else is
        /// corrected; a chevron is the rule's whole subject.
        static func glyphWeight(for symbolName: String) -> NSFont.Weight {
            symbolName.hasPrefix("chevron.") ? .light : .regular
        }
    }
}
