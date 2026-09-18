//
//  TypeScale.swift
//  Luna
//
//  §1's type scale. Split out of `Metrics.swift` when that file crossed
//  SwiftLint's 400-line limit; nothing changed on the way across.
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
    }
}
