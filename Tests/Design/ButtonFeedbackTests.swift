//
//  ButtonFeedbackTests.swift
//  LunaTests
//
//  Every button in Luna answers a press, and this is the register of them: a
//  new button type that does not swell fails here. See CLAUDE.md, "Buttons
//  answer".
//
//  The swell is asserted, not the wash. The wash lands in different places per
//  control — a plate, a subview, a gradient's ring — while `Motion.swell`
//  writes one transform to the control, or to the capsule that owns its
//  material, in every case.
//
//  Absent on purpose: list rows (`CredentialRowView`, `PopoverActionRowView`,
//  `SettingsAccountRow`), which answer with a hover wash only, and the
//  approval card and §14.4's chip, which are `SettingsPushButton`s. Also
//  absent: the bare `NSPopUpButton`s of Settings and the site pop-out's user
//  agent row (`ChoicePopUp`), which AppKit draws and highlights itself.
//

import XCTest
@testable import Luna
@testable import BrowserKit

@MainActor
final class ButtonFeedbackTests: XCTestCase {

    /// `Motion.swell` writes the scale to the model layer, so it can be read
    /// back the moment the press lands — no animation to wait for.
    private func scale(of view: NSView) -> CGFloat {
        view.layer?.transform.m11 ?? 1
    }

    private func mouse(_ type: NSEvent.EventType, in view: NSView) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: NSPoint(x: view.bounds.midX, y: view.bounds.midY),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ) ?? NSEvent()
    }

    /// Down and up through the view's own handlers. Not `performClick`:
    /// that is the action, and what is being tested is the answer to the
    /// gesture, which happens on either side of it.
    private func press(_ view: NSView, then body: (CGFloat) -> Void) {
        view.mouseDown(with: mouse(.leftMouseDown, in: view))
        body(scale(of: view))
        view.mouseUp(with: mouse(.leftMouseUp, in: view))
    }

    private func sized(_ view: NSView, _ side: CGFloat = 28) -> NSView {
        view.frame = NSRect(x: 0, y: 0, width: side, height: side)
        view.layoutSubtreeIfNeeded()
        return view
    }

    // MARK: - The controls that carry their own material

    /// Each of these is a plate, a disc or a pill of its own, so each swells
    /// itself. A new one belongs in this list.
    func testEveryButtonThatOwnsItsMaterialSwellsUnderTheFinger() {
        let swell = Tokens.Motion.pressSwell
        let buttons: [(String, NSView)] = [
            ("GlassButton", GlassButton(
                shape: Tokens.Metric.bottomCircle,
                symbolName: "star",
                pointSize: Tokens.Metric.glyphSize,
                label: "Star"
            )),
            ("SpaceEditorButton", SpaceEditorButton(title: "Cancel")),
            ("SpaceEditorButton preferred", SpaceEditorButton(title: "Create Space", isPreferred: true)),
            ("SpaceSwatchChip", SpaceSwatchChip(gradient: .defaultSpace, label: "Blue")),
            ("SpaceSymbolChip", SpaceSymbolChip(symbolName: "moon.stars", label: "Moon")),
            // §3.4's close/mute chip. §3.4b's fold mark is not here and must
            // not be: it is a plain image view, because the header it sits on
            // is the control that folds the folder.
            ("RowGlyphView", {
                let glyph = RowGlyphView()
                glyph.configure(symbolName: "xmark", label: "Close Tab")
                return glyph
            }()),
            // §16.4: a pinned extension in the sidebar's pill, and the pin in
            // the pop-out's row — the same chip, dressed with an image.
            ("RowGlyphView (extension)", {
                let glyph = RowGlyphView()
                glyph.configure(image: ExtensionsSymbol.image, label: "Extension")
                glyph.isRound = true
                return glyph
            }()),
            ("SettingsChoiceButton", SettingsChoiceButton(title: "Light")),
            // Settings ▸ Extensions: a card's Spaces menu, its pin and its "more".
            ("ExtensionCardButton", ExtensionCardButton(symbol: "pin", label: "Pin to the Bar")),
            ("SpaceAppearanceButton", SpaceAppearanceButton()),
            ("TabSwitcherCard", TabSwitcherCard(item: TabSwitcherItem(id: UUID(), title: "Example", favicon: nil))),
            ("OnboardingButton", OnboardingButton(title: "Back", isPreferred: false)),
            ("OnboardingButton preferred", OnboardingButton(title: "Continue", isPreferred: true)),
            ("OnboardingImportRow", OnboardingImportRow(source: DetectedSource(
                source: .arc,
                profiles: [ChromiumProfile(directoryName: "Default")],
                isAvailable: true
            )))
        ]
        for (name, button) in buttons {
            press(sized(button)) { held in
                XCTAssertEqual(held, swell, accuracy: 0.001, "\(name) does not swell under a press")
            }
            XCTAssertEqual(scale(of: button), 1, accuracy: 0.001, "\(name) stays swollen after the release")
        }
    }

    /// The Reading pop-out: a face shown in itself, a width as a picture,
    /// the size stepper's two ends and the pill's Aa glyph.
    func testTheReadingPopOutsButtonsSwellUnderTheFinger() {
        let glyph = RowGlyphView()
        glyph.configure(symbolName: ReadingMenu.Glyph.header, label: "Reading")
        glyph.isRound = true
        let stepper = ReadingSizeStepper(size: 19)
        let buttons: [(String, NSView)] = [
            ("SettingsChoiceButton (font)", SettingsChoiceButton(title: "Mono", font: .monospacedSystemFont(ofSize: 13, weight: .regular))),
            ("SettingsChoiceButton (symbol)", SettingsChoiceButton(title: "Wide", symbol: ReadingMenu.Glyph.widths[2])),
            ("ReadingSizeStepper A−", stepper.smaller),
            ("ReadingSizeStepper A+", stepper.larger),
            ("RowGlyphView (reading)", glyph)
        ]
        for (name, button) in buttons {
            press(sized(button)) { held in
                XCTAssertEqual(held, Tokens.Motion.pressSwell, accuracy: 0.001, "\(name) does not swell under a press")
            }
            XCTAssertEqual(scale(of: button), 1, accuracy: 0.001, "\(name) stays swollen after the release")
        }
    }

    /// The iCloud page's zone checks: the plate is a row in a card, so it is
    /// the disc, the thing being set, that swells.
    func testASyncZoneCheckSwellsItsDisc() {
        let row = SyncZoneCheckRow(title: "Site settings", detail: "", isOn: false)
        row.frame = NSRect(x: 0, y: 0, width: 240, height: 36)
        row.layoutSubtreeIfNeeded()
        press(row) { held in
            XCTAssertEqual(held, 1, accuracy: 0.001, "the whole row swelled")
            XCTAssertEqual(scale(of: row.disc), Tokens.Motion.pressSwell, accuracy: 0.001, "the disc does not swell")
        }
        XCTAssertEqual(scale(of: row.disc), 1, accuracy: 0.001, "the disc stayed swollen")
        XCTAssertTrue(row.isOn, "the press did not tick it")
    }

    // MARK: - The controls whose material belongs to a capsule

    /// A button inside a capsule hands the gesture up rather than growing a
    /// fifth of a point inside a shape that is not moving. What must be true
    /// is that something answers — and that it is the capsule.
    func testACapsuleAnswersOnBehalfOfTheButtonInsideIt() {
        let swell = Tokens.Motion.pressSwell

        let library = sized(SidebarActionCapsule(items: [
            (symbolName: "arrow.down.circle", label: "Downloads", action: {}),
            (symbolName: "clock", label: "History", action: {})
        ]), 68)
        guard let glyph = descendants(of: library, ofType: GlassButton.self).first else {
            return XCTFail("the library capsule has no buttons")
        }
        press(sized(glyph)) { held in
            XCTAssertEqual(held, 1, accuracy: 0.001, "a glyph with no material of its own swelled")
            XCTAssertEqual(scale(of: library), swell, accuracy: 0.001, "the library capsule did not answer")
        }
        XCTAssertEqual(scale(of: library), 1, accuracy: 0.001, "the library capsule stayed swollen")

        let nav = sized(SettingsNavCapsule(), 56)
        guard let chevron = descendants(of: nav, ofType: SettingsNavChevron.self).first else {
            return XCTFail("the nav capsule has no chevrons")
        }
        press(sized(chevron)) { held in
            XCTAssertEqual(held, 1, accuracy: 0.001, "a chevron with no material of its own swelled")
            XCTAssertEqual(scale(of: nav), swell, accuracy: 0.001, "the nav capsule did not answer")
        }
        XCTAssertEqual(scale(of: nav), 1, accuracy: 0.001, "the nav capsule stayed swollen")
    }

    // MARK: - The `NSButton`s

    /// `TopBarButton`, `SettingsPushButton` and `PopoutTextButton` take their
    /// press around `NSControl`'s tracking loop, which does not return until
    /// the mouse comes back up — so `mouseDown` would hang a test.
    /// `highlight(_:)` is AppKit's own name for the same state and the same
    /// override answers it.
    func testTheAppKitButtonsSwellWhenAppKitSaysTheyAreDown() {
        let swell = Tokens.Motion.pressSwell

        // A button on §4's bar, taken out of its capsule — the capsule is
        // what swells in the app, and this is the button's own half of it.
        let item = TopBarButton(metric: TopBarMetrics.capsuleItem)
        _ = sized(item)
        item.highlight(true)
        XCTAssertEqual(scale(of: item), swell, accuracy: 0.001, "a bar button does not swell")
        item.highlight(false)
        XCTAssertEqual(scale(of: item), 1, accuracy: 0.001, "a bar button stays swollen")

        let push = SettingsPushButton(title: "Reset", isDestructive: false)
        _ = sized(push, 60)
        push.highlight(true)
        XCTAssertEqual(scale(of: push), swell, accuracy: 0.001, "the push button does not swell")
        push.highlight(false)
        XCTAssertEqual(scale(of: push), 1, accuracy: 0.001, "the push button stays swollen")

        // §15.3's "Clear": as a bare `NSButton` it would answer nothing at all.
        let word = PopoutTextButton(title: "Clear", label: "Clear finished downloads")
        _ = sized(word, 48)
        word.highlight(true)
        XCTAssertEqual(scale(of: word), swell, accuracy: 0.001, "a pop-out's text button does not swell")
        word.highlight(false)
        XCTAssertEqual(scale(of: word), 1, accuracy: 0.001, "a pop-out's text button stays swollen")
    }

    /// A page toast's words — §17's Open and Always Allow. Words on glass, so
    /// the pop-out's text button, and each one answers on its own.
    func testAToastsWordsSwell() {
        let swell = Tokens.Motion.pressSwell
        let toast = PageToastView()
        toast.configure(.popupBlocked(count: 1, address: "ads.example.net", shortcut: "⌥⌘P", open: {}, allow: {}))
        XCTAssertEqual(toast.buttons.count, 2, "the notice has lost a word, or grown one this test does not know")
        for button in toast.buttons {
            _ = sized(button, 60)
            button.highlight(true)
            XCTAssertEqual(scale(of: button), swell, accuracy: 0.001, "\(button.title) does not swell")
            button.highlight(false)
            XCTAssertEqual(scale(of: button), 1, accuracy: 0.001, "\(button.title) stays swollen")
        }
    }

    /// §4's action capsule applies one material for all of its items, so its
    /// items hand the press up exactly as the sidebar's do.
    func testATopBarCapsuleItemHandsItsPressToTheCylinder() {
        let capsule = TopBarActionCapsule()
        capsule.items = [TopBarActionItem(id: "one", symbolName: "clock", label: "History", action: {})]
        _ = sized(capsule, 40)
        guard let item = descendants(of: capsule, ofType: TopBarButton.self).first else {
            return XCTFail("the capsule has no items")
        }
        item.highlight(true)
        XCTAssertEqual(scale(of: item), 1, accuracy: 0.001, "a capsule item swelled inside its own cylinder")
        XCTAssertEqual(scale(of: capsule), Tokens.Motion.pressSwell, accuracy: 0.001, "the cylinder did not answer")
        item.highlight(false)
        XCTAssertEqual(scale(of: capsule), 1, accuracy: 0.001, "the cylinder stayed swollen")
    }

    /// Luna Control's working capsule: Take Over is a pill with no glass of
    /// its own, so the capsule round it swells.
    func testTheWorkingCapsuleSwellsForTakeOver() throws {
        let capsule = ControlWorkingCapsule()
        capsule.configure(.init(client: "Claude Code", appID: nil, isPaused: false, isActing: false)) {}
        capsule.frame = NSRect(origin: .zero, size: capsule.fittingSize)
        capsule.layoutSubtreeIfNeeded()
        let button = try XCTUnwrap(capsule.button, "the capsule has no Take Over")
        button.highlight(true)
        XCTAssertEqual(scale(of: button), 1, accuracy: 0.001, "Take Over swelled inside the capsule")
        XCTAssertEqual(scale(of: capsule), Tokens.Motion.pressSwell, accuracy: 0.001, "the capsule did not answer")
        button.highlight(false)
        XCTAssertEqual(scale(of: capsule), 1, accuracy: 0.001, "the capsule stayed swollen")
    }

    /// §3.2b's extensions cylinder: its buttons are the toggle's `GlassButton`
    /// with no glass of their own, so the press goes to the cylinder, as it
    /// does for `NavCluster`.
    func testThePageBarsExtensionsCylinderSwellsForItsButtons() {
        let shelf = PageBarExtensionShelf()
        shelf.show(pins: [ExtensionShelfItem(id: "a", name: "A", icon: nil, badge: "", isPinned: true)])
        shelf.frame = NSRect(origin: .zero, size: NSSize(width: PageBarExtensionShelf.width(pins: 1), height: 34))
        shelf.layoutSubtreeIfNeeded()
        for button in [shelf.extensionsButton, shelf.pinButtons[0].button] {
            button.mouseDown(with: mouse(.leftMouseDown, in: button))
            XCTAssertEqual(scale(of: button), 1, accuracy: 0.001, "a button swelled inside the cylinder")
            XCTAssertEqual(scale(of: shelf), Tokens.Motion.pressSwell, accuracy: 0.001, "the cylinder did not answer")
            button.mouseUp(with: mouse(.leftMouseUp, in: button))
            XCTAssertEqual(scale(of: shelf), 1, accuracy: 0.001, "the cylinder stayed swollen")
        }
    }

    /// §18.1's find field: previous, next and close are bare glyphs on the
    /// capsule's glass, so the capsule swells for each.
    func testTheFindFieldSwellsForItsButtons() {
        let bar = FindBarView()
        bar.frame = NSRect(origin: .zero, size: NSSize(width: Tokens.Metric.findBarWidth, height: Tokens.Metric.capsuleHeight))
        bar.layoutSubtreeIfNeeded()
        for button in [bar.previous, bar.next, bar.close] {
            button.isEnabled = true
            button.mouseDown(with: mouse(.leftMouseDown, in: button))
            XCTAssertEqual(scale(of: button), 1, accuracy: 0.001, "a find button swelled inside the capsule")
            XCTAssertEqual(scale(of: bar), Tokens.Motion.pressSwell, accuracy: 0.001, "the find capsule did not answer")
            button.mouseUp(with: mouse(.leftMouseUp, in: button))
            XCTAssertEqual(scale(of: bar), 1, accuracy: 0.001, "the find capsule stayed swollen")
        }
    }

    /// §4's Space dots stand under the name on the plate, without the
    /// column's pill — and still answer a press, on the strip that holds them.
    func testASpaceDotOnTheBarAnswersAPress() throws {
        let name = TopBarSpaceName()
        let spaces = (0 ..< 2).map {
            Space(name: "Space \($0)", symbolName: "square.grid.2x2", gradient: .defaultSpace)
        }
        name.show(spaces: spaces, activeSpaceID: spaces[0].id)
        _ = sized(name, 120)
        let dot = try XCTUnwrap(descendants(of: name, ofType: SpaceDotView.self).first, "the name has no dots")
        dot.mouseDown(with: mouse(.leftMouseDown, in: dot))
        XCTAssertEqual(scale(of: name.dots), Tokens.Motion.pressSwell, accuracy: 0.001, "the dots did not answer")
        XCTAssertEqual(scale(of: dot), 1, accuracy: 0.001, "a dot swelled on its own")
    }

    /// Settings' Layout pictures: the picture swells, not the label under
    /// it — the picture is the thing being chosen.
    func testALayoutPictureSwellsUnderAPress() {
        let option = SettingsLayoutOption(layout: .topBar)
        option.frame = NSRect(x: 0, y: 0, width: 120, height: 100)
        option.layoutSubtreeIfNeeded()
        option.mouseDown(with: mouse(.leftMouseDown, in: option))
        XCTAssertEqual(scale(of: option.picture), Tokens.Motion.pressSwell, accuracy: 0.001)
        option.mouseUp(with: mouse(.leftMouseUp, in: option))
        XCTAssertEqual(scale(of: option.picture), 1, accuracy: 0.001)
    }

    private func descendants<T: NSView>(of root: NSView, ofType type: T.Type) -> [T] {
        var found: [T] = []
        for child in root.subviews {
            if let match = child as? T { found.append(match) }
            found += descendants(of: child, ofType: type)
        }
        return found
    }
}

extension ButtonFeedbackTests {

    /// The activity pill is glass of its own, so it swells itself on a press
    /// and washes on the pointer.
    func testTheActivityPillAnswersThePointerAndThePress() {
        let pill = ControlActivityPill()
        pill.configure(ControlActivity.Shown(
            entry: ControlActivity.entry(for: .listTabs, agent: "a", client: "Claude Code", appID: nil),
            name: "Main 2", working: true
        ))
        pill.frame = NSRect(origin: .zero, size: pill.fittingSize)
        pill.layoutSubtreeIfNeeded()
        let before = pill.layer?.frame ?? .zero
        pill.highlight(true)
        XCTAssertEqual(scale(of: pill), Tokens.Motion.pressSwell, accuracy: 0.001, "the pill did not swell")
        let swollen = pill.layer?.frame ?? .zero
        XCTAssertEqual(swollen.midX, before.midX, accuracy: 0.5, "the pill swelled off its centre")
        XCTAssertEqual(swollen.midY, before.midY, accuracy: 0.5, "the pill swelled off its centre")
        if !Tokens.Motion.reduceMotion {
            XCTAssertNotNil(pill.layer?.animation(forKey: "controlPress"), "the press did not animate")
        }
        pill.highlight(false)
        XCTAssertEqual(scale(of: pill), 1, accuracy: 0.001, "the pill stayed swollen")
        pill.mouseEntered(with: mouse(.mouseMoved, in: pill))
        let wash = pill.subviews.first { type(of: $0) == NSView.self }
        XCTAssertNotEqual(wash?.layer?.backgroundColor?.alpha ?? 0, 0, "the pill did not answer the pointer")
        if !Tokens.Motion.reduceMotion {
            XCTAssertNotNil(wash?.layer?.animation(forKey: "backgroundColor"), "the hover did not cross-fade")
        }
    }
}
