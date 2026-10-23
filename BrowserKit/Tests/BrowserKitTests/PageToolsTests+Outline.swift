@testable import BrowserKit
import XCTest

/// The picker's outline and label, read as computed on a light and a dark page.
/// Apart from `PageToolsTests+Picker.swift` only for SwiftLint's length limits.
extension PageToolsTests {

    /// The palette's ink as the app measured it in a dark and a light Luna: the
    /// outline once took its colours from these, and drew white on a white page.
    private static let palettes = [
        ":root{--luna-text-primary:rgba(255,255,255,0.847);--luna-surface-base:rgb(30,30,30);"
            + "--luna-surface-selected:rgba(255,255,255,0.12)}",
        ":root{--luna-text-primary:rgba(0,0,0,0.847);--luna-surface-base:rgb(255,255,255);"
            + "--luna-surface-selected:rgba(0,0,0,0.12)}"
    ]

    func testTheOutlineAndItsLabelReadOnALightAndADarkPage() async throws {
        let saved = InternalPages.palette
        defer { InternalPages.palette = saved }
        for palette in Self.palettes {
            InternalPages.palette = palette
            for page in ["#fff", "#111"] {
                let look = try await outlineLook(on: page)
                let behind = try XCTUnwrap(Self.rgba(page == "#fff" ? "rgb(255, 255, 255)" : "rgb(17, 17, 17)"))
                let rings = [look["border"], look["shadow"]].compactMap { $0.flatMap(Self.rgba) }
                let best = rings.map { Self.contrast(Self.over($0, behind), behind) }.max() ?? 0
                XCTAssertGreaterThanOrEqual(best, 3, "outline on \(page) under \(palette.prefix(40)): \(look)")

                let fill = try XCTUnwrap(look["tagFill"].flatMap(Self.rgba))
                let tagRings = [look["tagFill"], look["tagShadow"]].compactMap { $0.flatMap(Self.rgba) }
                let tagBest = tagRings.map { Self.contrast(Self.over($0, behind), behind) }.max() ?? 0
                XCTAssertGreaterThanOrEqual(tagBest, 3, "label's pill on \(page): \(look)")
                let ink = try XCTUnwrap(look["tagInk"].flatMap(Self.rgba))
                let plate = Self.over(fill, behind)
                XCTAssertGreaterThanOrEqual(Self.contrast(Self.over(ink, plate), plate), 4.5, "label's words on \(page): \(look)")
                controller.stopPickingElements()
            }
        }
    }

    private func outlineLook(on background: String) async throws -> [String: String] {
        try await load("""
        <body style="margin:0;background:\(background)"><nav style="padding:20px"><a href="/a">Alpha</a></nav></body>
        """)
        controller.startDescribingElements { _ in } onEnd: {}
        try await Task.sleep(for: .milliseconds(100))
        _ = try await page("dispatchEvent(new MouseEvent('mousemove', { clientX: 30, clientY: 28 })); 1")
        let look = try await controller.webView?.evaluateJavaScript("window.__lunaPicker.look()", contentWorld: .defaultClient)
        return try XCTUnwrap(look as? [String: String])
    }

    /// The first `rgb()` or `rgba()` in a computed value, as 0–1 components.
    private static func rgba(_ css: String) -> [Double]? {
        guard let match = css.firstMatch(of: /rgba?\(([^)]*)\)/) else { return nil }
        let parts = match.1.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count >= 3 else { return nil }
        return [parts[0] / 255, parts[1] / 255, parts[2] / 255, parts.count > 3 ? parts[3] : 1]
    }

    private static func over(_ top: [Double], _ bottom: [Double]) -> [Double] {
        (0 ..< 3).map { top[$0] * top[3] + bottom[$0] * (1 - top[3]) } + [1]
    }

    /// WCAG 2's contrast ratio between two opaque sRGB colours.
    private static func contrast(_ a: [Double], _ b: [Double]) -> Double {
        func luminance(_ c: [Double]) -> Double {
            let linear = c.prefix(3).map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
        }
        let (l1, l2) = (luminance(a), luminance(b))
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }
}
