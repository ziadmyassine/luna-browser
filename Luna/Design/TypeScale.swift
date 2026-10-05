//
//  TypeScale.swift
//  Luna
//
//  §1's type scale. Split out of Metrics.swift at the 400-line limit.
//
//  It owns SF Symbol weight as well as font weight: this is the only file in
//  Luna permitted to name an `NSFont.Weight`, and a symbol is a face like any
//  other. The size those symbols are set at is a metric and stays in
//  `Metrics.glyphSize`.
//

import AppKit

extension Tokens {

    /// §1's type scale. System font throughout (§8.6/§8.7).
    ///
    /// The numeric faces are the monospaced-digit system font: §1 asks for
    /// tabular digits wherever a number is shown. The letterforms are identical
    /// to the plain system font, so it costs nothing.
    ///
    /// `var`, not `let`: `NSFont` is not `NS_SWIFT_SENDABLE` in the macOS 26.5
    /// SDK (verified in NSFont.h), so a `static let NSFont` is a Swift 6 strict
    /// concurrency error. Computed statics have no storage and are safe.
    enum TypeScale {
        /// 13 pt — sidebar rows.
        ///
        /// Re-measured, and it overturns §1's 15 pt. In
        /// `inspiration/main-tab-bar-and-ui.png` the row titles have a 20 px
        /// x-height and a 25 px cap height, which at the capture's 2.848 px/pt
        /// is a 13 pt system font. The 15 pt was inferred from a scale that
        /// assumed the reference's sidebar was 280 pt; it is 268.
        ///
        /// Plain, not `monospacedDigit`: a page title is not a number, and
        /// monospaced digits visibly widen a title like "iPhone 18 Pro".
        static var sidebarRow: NSFont { .systemFont(ofSize: 13, weight: .regular) }
        // §3.3a's two wells read this one too, directly: a token whose whole
        // body is another token's name is a way for the two to drift, and a
        // semibold hint was a section label's weight on a sentence.

        /// 13 pt — the sidebar URL pill, at the same x-height as the rows.
        /// §1's 17 pt came from the same bad scale as the 15 pt above.
        static var urlPill: NSFont { .systemFont(ofSize: 13, weight: .regular) }
        /// 13 pt — the same pill in top-bar layout, where it shares the bar.
        static var topBarURL: NSFont { .systemFont(ofSize: 13, weight: .regular) }
        /// 12 pt — the Space's name at the head of §4's plate. A step under
        /// the tabs' 13: at the rows' size it read as the first tab on the bar
        /// rather than as the label on the shelf.
        static var topBarSpaceName: NSFont { .systemFont(ofSize: 12, weight: .regular) }
        /// 15 pt — §9.1's Command Bar query.
        ///
        /// One step above the chrome, because the bar is not chrome. The
        /// sidebar's 13 pt is right for a column of two dozen rows you scan;
        /// the Command Bar is a modal surface you look at while typing into it,
        /// and at the sidebar's size it read as a chrome field that had floated
        /// loose. It is also the one field where what you typed is the whole
        /// content.
        static var commandBarQuery: NSFont { .systemFont(ofSize: 15, weight: .regular) }
        /// 14 pt — a §9.1 result row's title and subtitle, one step under the
        /// query so the list reads as an answer to it rather than as more of
        /// it. §3.4's 38 pt row has the room.
        static var commandBarRow: NSFont { .systemFont(ofSize: 14, weight: .regular) }
        /// 12 pt semibold — section labels.
        static var sectionLabel: NSFont { .monospacedDigitSystemFont(ofSize: 12, weight: .semibold) }
        /// 13 pt, tabular — §18.1's "3 of 12", beside a field at `urlPill`'s
        /// size. Tabular so the figures do not shift as the match moves on.
        static var findCount: NSFont { .monospacedDigitSystemFont(ofSize: 13, weight: .regular) }
        /// 14 pt — the §5 downloads filename.
        static var downloadFilename: NSFont { .monospacedDigitSystemFont(ofSize: 14, weight: .regular) }
        /// 7 pt bold, tabular — §16.4's badge on a pinned extension's icon.
        /// At 8 a two-digit count covered two thirds of the 16 pt icon and the
        /// icon stopped reading as the extension; 7 still reads at 2×.
        static var extensionBadge: NSFont { .monospacedDigitSystemFont(ofSize: 7, weight: .bold) }
        /// 15 pt semibold — a Settings group's title. One step above the body,
        /// and the only place in Luna a heading appears over chrome.
        static var settingsHeading: NSFont { .systemFont(ofSize: 15, weight: .semibold) }
        /// 13 pt — a Settings control row's label, and a section name in the
        /// window's own column. The sidebar's face deliberately: Settings is
        /// the same app, and a form set two points larger than the window
        /// behind it reads as a different one.
        static var settingsRow: NSFont { sidebarRow }
        /// 11 pt — the explanatory line under a Settings control. Plain, not
        /// `sectionLabel`: this is prose, and semibold tabular prose is a label
        /// pretending to be a sentence.
        static var settingsCaption: NSFont { .systemFont(ofSize: 11, weight: .regular) }
        /// 26 pt semibold — the title on one of Luna's own pages (§4.4):
        /// §4.5's failures, and nothing else yet.
        ///
        /// A page is not chrome. Set in `urlPill` and `sectionLabel`, an
        /// internal page read as a sidebar loose in the window: type sized for
        /// a 268 pt column, centred in a thousand points of content.
        ///
        /// Plain, not `monospacedDigit`, for the same reason `sidebarRow` is.
        static var pageTitle: NSFont { .systemFont(ofSize: 26, weight: .semibold) }
        /// 15 pt — the sentence under a `pageTitle`. `commandBarQuery`'s size,
        /// for the same reason: a surface you look at rather than past. The
        /// page's small print stays on `sectionLabel`.
        static var pageBody: NSFont { .systemFont(ofSize: 15, weight: .regular) }

        /// 11 pt tabular — the caption's twin, for the one place it holds a
        /// number. §6.4 stamps each archived tab with the time it was closed,
        /// and a column of times in proportional digits walks left and right as
        /// the minutes change under it.
        /// The agent panel (`Luna/Features/Agent`): the task's name, its state
        /// under it, the conversation, and its steps — the sidebar's row type
        /// for the words and a size down for what is said about them.
        static var agentTitle: NSFont { .systemFont(ofSize: 13, weight: .semibold) }
        static var agentStatus: NSFont { .systemFont(ofSize: 11, weight: .regular) }
        static var agentBody: NSFont { .systemFont(ofSize: 13, weight: .regular) }
        static var agentStep: NSFont { .systemFont(ofSize: 12, weight: .regular) }
        static var rowTimestamp: NSFont { .monospacedDigitSystemFont(ofSize: 11, weight: .regular) }

        /// The weight an SF Symbol has to be set at to draw the same stroke as
        /// the glyphs beside it.
        ///
        /// SF Symbols share a cap height, and a mark small for its height is
        /// drawn heavier to stay legible. Median stroke at `glyphSize`, all at
        /// `.regular`: `sidebar.leading` 1.25 pt, `plus` and
        /// `arrow.down.to.line` 1.38, `arrow.clockwise` and
        /// `clock.arrow.circlepath` 1.62, `chevron.backward` 2.00. The chevron
        /// sits in a box 7.5 pt wide against its neighbours' 12 to 18.5, so at
        /// their weight it is the heaviest line in the chrome; `.light` draws
        /// it at 1.50, level with the top bar's median.
        ///
        /// Measure stroke, not total ink. Total ink calls the chevron the
        /// faintest mark because it is the smallest, and `.semibold` from that
        /// took it to 3.00, twice the reload arrow. Nothing else here is small
        /// for its height, so nothing else is corrected.
        static func glyphWeight(for symbolName: String) -> NSFont.Weight {
            symbolName.hasPrefix("chevron.") ? .light : .regular
        }
    }
}
