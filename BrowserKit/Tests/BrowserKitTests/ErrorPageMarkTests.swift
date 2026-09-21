//
//  ErrorPageMarkTests.swift
//  BrowserKitTests
//
//  §4.5's six pages are one layout wearing six faces. These are the ways that
//  can quietly stop being true: a kind that shares its mark with another one,
//  a page that recommends the thing Luna just stopped, and a glyph that went
//  back to carrying a colour of its own.
//

import Foundation
import Testing
@testable import BrowserKit

@MainActor
@Suite("Error page marks (§4.5)")
struct ErrorPageMarkTests {

    private func html(_ kind: InternalPageError.Kind) -> String {
        InternalPages.errorHTML(InternalPageError(kind: kind, url: URL(string: "https://a.test/")!))
    }

    /// The whole point of six glyphs. Before this every kind wore the same
    /// exclamation in a circle, which says "something went wrong" six times
    /// and distinguishes nothing.
    @Test func everyKindWearsItsOwnMark() {
        var seen: [String: InternalPageError.Kind] = [:]
        for kind in InternalPageError.Kind.allCases {
            let page = html(kind)
            guard let start = page.range(of: "<svg"), let end = page.range(of: "</svg>") else {
                Issue.record("\(kind) rendered no mark")
                continue
            }
            let mark = String(page[start.lowerBound ..< end.upperBound])
            if let twin = seen[mark] {
                Issue.record("\(kind) and \(twin) draw the same mark")
            }
            seen[mark] = kind
        }
        #expect(seen.count == InternalPageError.Kind.allCases.count)
    }

    /// The mark is drawn in `currentColor` so the stylesheet decides whether it
    /// is ink or §8.1's danger. A fill or a stroke value here would be a second
    /// palette, in the one file that is allowed no palette at all.
    @Test func marksCarryNoColourOfTheirOwn() {
        for kind in InternalPageError.Kind.allCases {
            let page = html(kind)
            #expect(!page.contains("stroke=\"#"), "\(kind) names a colour")
            #expect(page.contains("stroke=\"currentColor\""), "\(kind) does not inherit its colour")
        }
    }

    /// **Luna never recommends going round itself.** The two kinds that offer a
    /// bypass are the two Luna stopped on purpose, so the emphasis belongs on
    /// the way out; every other kind is a failure nobody chose, and trying
    /// again is the answer.
    @Test func theKeyActionIsNeverTheBypass() {
        for kind in InternalPageError.Kind.allCases {
            let page = html(kind)
            let error = InternalPageError(kind: kind, url: URL(string: "https://a.test/")!)
            // One recommendation per page, whichever it is.
            #expect(page.components(separatedBy: "button key").count == 2, "\(kind) has no single key action")
            guard error.offersBypass else { continue }
            let bypass = page.range(of: "luna://proceed")
            let key = page.range(of: "button key")
            if let bypass, let key {
                // The key class is written on the *other* anchor, so the two
                // never land inside the same tag.
                let between = page[min(bypass.lowerBound, key.lowerBound) ..< max(bypass.upperBound, key.upperBound)]
                #expect(between.contains("</a>"), "\(kind) recommends continuing anyway")
            }
        }
    }

    /// The address that failed is evidence, and it goes in §3.3's well — the
    /// same recess the chrome shows a value in. A detail line is a second
    /// voice and must not be dressed as the address.
    @Test func theAddressSitsInAWellAndTheDetailDoesNot() {
        let page = InternalPages.errorHTML(InternalPageError(
            kind: .tls,
            url: URL(string: "https://a.test/")!,
            detail: "The certificate expired."
        ))
        #expect(page.contains("class=\"target well\""))
        #expect(page.contains("class=\"note\""))
    }
}
