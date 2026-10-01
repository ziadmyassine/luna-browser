//
//  ButtonLabelTests.swift
//  LunaTests
//
//  §21.1: every button in Luna is an element VoiceOver can reach, with a
//  control's role and a name. The same register as `ButtonFeedbackTests` —
//  a button added there belongs here too.
//

import XCTest
@testable import Luna
@testable import BrowserKit

@MainActor
final class ButtonLabelTests: XCTestCase {

    private static let controlRoles: Set<NSAccessibility.Role> = [
        .button, .radioButton, .checkBox, .popUpButton, .menuButton
    ]

    private func assertLabelled(_ buttons: [(String, NSView)], file: StaticString = #filePath, line: UInt = #line) {
        for (name, button) in buttons {
            // An `NSButton` is handed to VoiceOver as its cell; see `AccessibilityTree`.
            let element: NSAccessibilityProtocol = (button as? NSControl)?.cell.flatMap { $0.isAccessibilityElement() ? $0 : nil } ?? button
            let node = AccessibilityNode(element)
            XCTAssertTrue(element.isAccessibilityElement(), "\(name) is not an accessibility element", file: file, line: line)
            XCTAssertTrue(
                node.role.map(Self.controlRoles.contains) ?? false,
                "\(name) is read as \(node.role?.rawValue ?? "nothing"), not a control",
                file: file, line: line
            )
            XCTAssertFalse(node.name.isEmpty, "\(name) has no name", file: file, line: line)
        }
    }

    private func descendants<T: NSView>(of root: NSView, ofType type: T.Type) -> [T] {
        root.subviews.flatMap { child in (child as? T).map { [$0] } ?? [] + descendants(of: child, ofType: type) }
    }

    func testTheControlsThatCarryTheirOwnMaterialAreLabelled() {
        let glyph = RowGlyphView()
        glyph.configure(symbolName: "xmark", label: "Close Tab")
        let pin = RowGlyphView()
        pin.configure(image: ExtensionsSymbol.image, label: "Extension")
        let reading = RowGlyphView()
        reading.configure(symbolName: ReadingMenu.Glyph.header, label: "Reading")
        let stepper = ReadingSizeStepper(size: 19)
        assertLabelled([
            ("GlassButton", GlassButton(
                shape: Tokens.Metric.bottomCircle, symbolName: "star", pointSize: Tokens.Metric.glyphSize, label: "Star"
            )),
            ("SpaceEditorButton", SpaceEditorButton(title: "Cancel")),
            ("SpaceEditorButton preferred", SpaceEditorButton(title: "Create Space", isPreferred: true)),
            ("SpaceSwatchChip", SpaceSwatchChip(gradient: .defaultSpace, label: "Blue")),
            ("SpaceSymbolChip", SpaceSymbolChip(symbolName: "moon.stars", label: "Moon")),
            ("RowGlyphView", glyph),
            ("RowGlyphView (extension)", pin),
            ("RowGlyphView (reading)", reading),
            ("SettingsChoiceButton", SettingsChoiceButton(title: "Light")),
            ("SettingsChoiceButton (symbol)", SettingsChoiceButton(title: "Wide", symbol: ReadingMenu.Glyph.widths[2])),
            ("ExtensionCardButton", ExtensionCardButton(symbol: "pin", label: "Pin to the Bar")),
            ("SpaceAppearanceButton", SpaceAppearanceButton()),
            ("TabSwitcherCard", TabSwitcherCard(item: TabSwitcherItem(id: UUID(), title: "Example", favicon: nil))),
            ("OnboardingButton", OnboardingButton(title: "Back", isPreferred: false)),
            ("OnboardingImportRow", OnboardingImportRow(source: DetectedSource(
                source: .arc, profiles: [ChromiumProfile(directoryName: "Default")], isAvailable: true
            ))),
            ("ReadingSizeStepper A−", stepper.smaller),
            ("ReadingSizeStepper A+", stepper.larger),
            ("SyncZoneCheckRow", SyncZoneCheckRow(title: "Site settings", detail: "", isOn: false)),
            ("SettingsLayoutOption", SettingsLayoutOption(layout: .topBar))
        ])
    }

    func testTheAppKitButtonsAreLabelled() {
        let pill = ControlActivityPill()
        pill.configure(ControlActivity.Shown(
            entry: ControlActivity.entry(for: .listTabs, agent: "a", client: "Claude Code", appID: nil),
            name: "Main 2", working: true
        ))
        let toast = PageToastView()
        toast.configure(.popupBlocked(count: 1, address: "ads.example.net", shortcut: "⌥⌘P", open: {}, allow: {}))
        assertLabelled([
            ("SettingsPushButton", SettingsPushButton(title: "Reset", isDestructive: false)),
            ("PopoutTextButton", PopoutTextButton(title: "Clear", label: "Clear finished downloads")),
            ("ControlActivityPill", pill)
        ] + toast.buttons.map { ("PageToastView \($0.title)", $0) })
    }

    /// The buttons that hand their press to a capsule still answer to
    /// VoiceOver themselves: the capsule is a group, the button is the control.
    func testTheButtonsInsideCapsulesAreLabelled() throws {
        let library = SidebarActionCapsule(items: [
            (symbolName: "arrow.down.circle", label: "Downloads", action: {}),
            (symbolName: "clock", label: "History", action: {})
        ])
        let bar = TopBarActionCapsule()
        bar.items = [TopBarActionItem(id: "one", symbolName: "clock", label: "History", action: {})]
        let nav = SettingsNavCapsule()
        let find = FindBarView()
        let shelf = PageBarExtensionShelf()
        shelf.show(pins: [ExtensionShelfItem(id: "a", name: "A", icon: nil, badge: "", isPinned: true)])
        let working = ControlWorkingCapsule()
        working.configure(.init(client: "Claude Code", appID: nil, isPaused: false, isActing: false)) {}
        let name = TopBarSpaceName()
        let spaces = (0 ..< 2).map { Space(name: "Space \($0)", symbolName: "square.grid.2x2", gradient: .defaultSpace) }
        name.show(spaces: spaces, activeSpaceID: spaces[0].id)
        let cluster = NavCluster()
        cluster.update(canGoBack: true, canGoForward: true)

        var buttons: [(String, NSView)] = []
        buttons += descendants(of: library, ofType: GlassButton.self).map { ("SidebarActionCapsule item", $0) }
        buttons += descendants(of: bar, ofType: TopBarButton.self).map { ("TopBarActionCapsule item", $0) }
        buttons += descendants(of: nav, ofType: SettingsNavChevron.self).map { ("SettingsNavChevron", $0) }
        buttons += [("FindBarView previous", find.previous), ("FindBarView next", find.next), ("FindBarView close", find.close)]
        buttons += [shelf.extensionsButton, shelf.pinButtons[0].button].map { ("PageBarExtensionShelf", $0) }
        buttons += [("ControlWorkingCapsule Take Over", try XCTUnwrap(working.button))]
        buttons += descendants(of: name, ofType: SpaceDotView.self).map { ("SpaceDotView", $0) }
        buttons += descendants(of: cluster, ofType: GlassButton.self).map { ("NavCluster half", $0) }
        XCTAssertGreaterThanOrEqual(buttons.count, 12, "a capsule lost its buttons: \(buttons.map(\.0))")
        assertLabelled(buttons)

        // The capsules are groups with names, so VoiceOver says what the
        // buttons inside belong to.
        let capsules: [(NSView, String)] = [(library, "Library"), (bar, "Actions"), (cluster, "Back and Forward"), (shelf, "Extensions")]
        for (capsule, label) in capsules {
            XCTAssertTrue(capsule.isAccessibilityElement(), "\(label) is not read as a group")
            XCTAssertEqual(capsule.accessibilityRole(), .group)
            XCTAssertEqual(AccessibilityNode(capsule).name, label)
        }
    }
}
