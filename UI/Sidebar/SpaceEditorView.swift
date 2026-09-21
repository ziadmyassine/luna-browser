//
//  SpaceEditorView.swift
//  Luna
//
//  The Space you have just made, while you are still looking at where it
//  appeared.
//
//  **A Space is three decisions and they are all made in the first ten
//  seconds**: what it is called, what colour it is, and what mark it carries.
//  Creating one from §30.9's swipe used to hand back `Space 3` in the chrome's
//  default grey and leave all three to a Settings window the user had no reason
//  to open — so the Space that was supposed to be *theirs* was the one that
//  looked like nobody's. Arc's own flow puts the name, the profile and the
//  theme in the sidebar at the moment of creation, and it is right about that.
//
//  **It edits; it does not gate.** The Space already exists by the time this is
//  on screen — the swipe made it — so there is no Create button, no Cancel that
//  could undo one, and closing this leaves a Space behind exactly as it would
//  have done anyway. That is the difference between this and the dialog Arc
//  shows: a form you have to finish is a form you can fail, and there is
//  nothing here worth failing.
//
//  The two grids are the ones §3.7's corner button opens (`SpaceAppearanceView`
//  and its chips) — one picker, two hosts. They are laid out by hand rather
//  than by the popover's fixed seven columns, because a sidebar is a width the
//  user drags.
//

import AppKit
import BrowserKit

/// §6.2's three settings, in the column the Space just arrived in.
@MainActor
final class SpaceEditorView: NSView {

    /// The name was committed — Return, or the field losing focus.
    var onRename: ((String) -> Void)?
    var onGradient: ((GradientPair) -> Void)?
    var onIcon: ((String) -> Void)?
    /// Done, or Escape.
    var onClose: (() -> Void)?

    private let heading = NSTextField(labelWithString: "")
    private let caption = NSTextField(labelWithString: "")
    private let field = NSTextField()
    private let colourLabel = NSTextField(labelWithString: "")
    private let iconLabel = NSTextField(labelWithString: "")
    private var swatches: [SpaceSwatchChip] = []
    private var symbols: [SpaceSymbolChip] = []
    private let done: GlassButton
    private var action: SettingsAction?

    init(space: Space) {
        done = GlassButton(
            shape: Tokens.Metric.bottomCircle,
            symbolName: "checkmark",
            pointSize: Tokens.Metric.glyphSize,
            label: String(localized: "Done")
        )
        super.init(frame: .zero)
        wantsLayer = true

        heading.stringValue = String(localized: "New Space")
        heading.font = Tokens.TypeScale.settingsHeading
        caption.stringValue = String(localized: "Name it, colour it, and it is yours.")
        caption.font = Tokens.TypeScale.settingsCaption
        caption.lineBreakMode = .byTruncatingTail
        colourLabel.stringValue = String(localized: "Colour")
        iconLabel.stringValue = String(localized: "Icon")
        for label in [colourLabel, iconLabel] { label.font = Tokens.TypeScale.sectionLabel }

        field.stringValue = space.name
        field.placeholderString = space.name
        field.font = Tokens.TypeScale.urlPill
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.cell?.sendsActionOnEndEditing = true
        let commit = SettingsAction { [weak self] sender in
            let typed = (sender as? NSTextField)?.stringValue ?? ""
            let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name != space.name else { return }
            self?.onRename?(name)
        }
        field.target = commit
        field.action = #selector(SettingsAction.fire(_:))
        action = commit

        swatches = zip(SpaceAppearanceView.gradients, SpaceAppearanceView.gradientNames).map { gradient, label in
            let chip = SpaceSwatchChip(gradient: gradient, label: label)
            chip.isChosen = gradient == space.gradient
            chip.onActivate = { [weak self] in
                self?.choose(gradient: gradient)
                self?.onGradient?(gradient)
            }
            return chip
        }
        symbols = SpacesSection.symbols.map { symbol in
            let chip = SpaceSymbolChip(symbolName: symbol.name, label: symbol.label)
            chip.isChosen = symbol.name == space.symbolName
            chip.onActivate = { [weak self] in
                self?.choose(symbol: symbol.name)
                self?.onIcon?(symbol.name)
            }
            return chip
        }
        done.onActivate = { [weak self] in self?.onClose?() }

        for view in [heading, caption, fieldPlate, colourLabel, iconLabel, done] as [NSView] { addSubview(view) }
        fieldPlate.addSubview(field)
        for chip in swatches + symbols as [NSView] { addSubview(chip) }
        applyTokens()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// §3.2's pill shape, so the one field in the sidebar that is not the
    /// address bar still looks like it belongs to the same window.
    private let fieldPlate = NSView()

    /// The name is what you came here to type, so it is what has the caret.
    func focusName() {
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    private func choose(gradient: GradientPair) {
        for chip in swatches { chip.isChosen = chip.gradient == gradient }
    }

    private func choose(symbol: String) {
        for chip in symbols { chip.isChosen = chip.symbolName == symbol }
    }

    private func applyTokens() {
        heading.textColor = Tokens.Text.primary
        caption.textColor = Tokens.Text.secondary
        colourLabel.textColor = Tokens.Text.secondary
        iconLabel.textColor = Tokens.Text.secondary
        field.textColor = Tokens.Text.primary
        fieldPlate.wantsLayer = true
        fieldPlate.layer?.cornerCurve = .continuous
        fieldPlate.layer?.cornerRadius = Tokens.Metric.urlPill.cornerRadius
        fieldPlate.layer?.backgroundColor = Tokens.Surface.chromeFill.cgColor
        fieldPlate.layer?.borderWidth = Tokens.Metric.hairline
        fieldPlate.layer?.borderColor = Tokens.Line.border.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTokens()
    }

    /// Escape closes it. Nothing is lost: the Space exists, and the name in the
    /// field was committed when it was typed.
    override func cancelOperation(_ sender: Any?) {
        onClose?()
    }

    override var acceptsFirstResponder: Bool { true }

    // MARK: - Layout

    /// By hand, like the rest of §3's column: the chip grids wrap to whatever
    /// width the §3.7 handle has left them, and Auto Layout has no wrapping
    /// stack to do it with.
    override func layout() {
        super.layout()
        Tokens.Motion.immediately { placeContents() }
    }

    private func placeContents() {
        let inset = Tokens.Metric.rowInset
        let gap = Tokens.Metric.chromeGap
        let width = max(bounds.width - 2 * inset, 0)
        var top = bounds.maxY - Tokens.Metric.chromeGapWide

        top = place(heading, at: top, width: width, height: Tokens.Metric.rowHeight - gap)
        top = place(caption, at: top - 2, width: width, height: Tokens.Metric.sidebarProfileRow)
        top -= gap
        fieldPlate.frame = NSRect(x: inset, y: top - Tokens.Metric.urlPill.height,
                                  width: width, height: Tokens.Metric.urlPill.height).integral
        field.frame = fieldPlate.bounds.insetBy(dx: Tokens.Metric.pillTextInset, dy: 0)
        top = fieldPlate.frame.minY - Tokens.Metric.chromeGapWide

        top = place(colourLabel, at: top, width: width, height: Tokens.Metric.sidebarProfileRow)
        top = grid(swatches, at: top - gap / 2, width: width) - Tokens.Metric.chromeGapWide
        top = place(iconLabel, at: top, width: width, height: Tokens.Metric.sidebarProfileRow)
        top = grid(symbols, at: top - gap / 2, width: width)

        let circle = Tokens.Metric.bottomCircle
        done.frame = NSRect(
            x: bounds.midX - circle.width / 2,
            y: top - Tokens.Metric.chromeGapWide - circle.height,
            width: circle.width,
            height: circle.height
        ).pixelAligned
    }

    private func place(_ view: NSView, at top: CGFloat, width: CGFloat, height: CGFloat) -> CGFloat {
        view.frame = NSRect(x: Tokens.Metric.rowInset, y: top - height, width: width, height: height).integral
        return view.frame.minY
    }

    /// Chips left to right, wrapping. Returns the bottom of the last row.
    ///
    /// **Balanced, not greedy.** Filling each row before starting the next is
    /// what a paragraph does and it is wrong for a palette of a fixed length:
    /// thirteen colours six to a row leave one chip alone on a line of its own,
    /// and that orphan is the first thing the eye finds in the whole form. The
    /// rows are counted first and the chips are then spread over them — six to
    /// a row becomes five, five and three, which is a grid with a short last
    /// line instead of a grid with an accident at the bottom.
    ///
    /// **Justified, and by the same number in both directions.** The chips are
    /// a fixed 28 pt — `SpaceSwatchChip` pins its own width, because §6.2's
    /// popover lays the same chips out on a fixed grid — so the spare width in
    /// a column the user can drag has nowhere to go but between the columns.
    /// Spreading it sideways alone gives a block whose rows are 8 pt apart and
    /// whose columns are twenty: a palette combed out. The spacing the columns
    /// end up with is therefore the spacing the rows get as well, so the grid
    /// stays square at every width the §3.7 handle can leave it at, and it
    /// never closes below the chrome's own gap.
    private func grid(_ chips: [NSView], at top: CGFloat, width: CGFloat) -> CGFloat {
        let side = Tokens.Metric.settingsControl
        let gap = Tokens.Metric.chromeGap
        let fit = max(Int((width + gap) / (side + gap)), 1)
        let rows = max(Int((CGFloat(chips.count) / CGFloat(fit)).rounded(.up)), 1)
        let columns = max(Int((CGFloat(chips.count) / CGFloat(rows)).rounded(.up)), 1)
        let spacing = columns > 1
            ? max((width - CGFloat(columns) * side) / CGFloat(columns - 1), gap)
            : gap
        var bottom = top
        for (index, chip) in chips.enumerated() {
            let row = index / columns
            let column = index % columns
            bottom = top - CGFloat(row) * (side + spacing) - side
            chip.frame = NSRect(
                x: Tokens.Metric.rowInset + CGFloat(column) * (side + spacing),
                y: bottom,
                width: side,
                height: side
            ).pixelAligned
        }
        return bottom
    }
}
