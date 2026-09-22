//
//  SpaceEditorView.swift
//  Luna
//
//  The Space you have just made, while you are still looking at where it
//  appeared.
//
//  A Space is three decisions, all made in the first ten seconds: what it is
//  called, what colour it is, and what mark it carries. Creating one from
//  §30.9's swipe used to hand back `Space 3` in the chrome's default grey and
//  leave all three to a Settings window the user had no reason to open. Arc
//  puts the name, the profile and the theme in the sidebar at the moment of
//  creation, and is right about that.
//
//  Three decisions, three cards. The form was six loose pieces on one sheet of
//  glass — label, field, label, grid, label, grid — separated by nothing but
//  vertical gaps, and a gap is the weakest boundary a layout has: a heading a
//  `chromeGapWide` above its own grid and a `chromeGap` below the grid before
//  it is closer to the wrong one. Each decision is a plate with its heading
//  inside it (`SpaceEditorCard`).
//
//  Two edges, both deliberate. The title and caption sit at `rowInset`, on the
//  cards' outer edge, because the form's heading belongs to the form and not to
//  the first plate in it; everything inside a card sits at
//  `settingsControlInset` within its plate.
//
//  Two answers at the foot, and they are not the same answer twice. The Space
//  already exists by the time this is on screen — the swipe made it — so
//  `Create Space` keeps what is already there and `Cancel` deletes it again,
//  which is what cancelling the making of a thing has to mean. Escape keeps
//  it: the form is an editor, and a keystroke that throws away a Space the
//  user has just named and coloured, by habit, is the worse of the two
//  surprises.
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
    /// The form is finished with — `Create Space`, or Escape. The Space stays.
    var onClose: (() -> Void)?
    /// `Cancel`: the Space the swipe made goes away again.
    var onCancel: (() -> Void)?

    private let heading = NSTextField(labelWithString: "")
    private let caption = NSTextField(labelWithString: "")
    private let field = NSTextField()
    private let nameCard = SpaceEditorCard()
    private let colourCard = SpaceEditorCard()
    private let iconCard = SpaceEditorCard()
    private let colourLabel = NSTextField(labelWithString: "")
    private let iconLabel = NSTextField(labelWithString: "")
    private var swatches: [SpaceSwatchChip] = []
    private var symbols: [SpaceSymbolChip] = []
    private let create: SpaceEditorButton
    private let cancel: SpaceEditorButton
    private var action: SettingsAction?
    /// The name the Space is known to carry — what `commitName` compares
    /// against, so the same name is never sent twice.
    private var committedName: String

    init(space: Space) {
        committedName = space.name
        create = SpaceEditorButton(title: String(localized: "Create Space"), isPreferred: true)
        cancel = SpaceEditorButton(title: String(localized: "Cancel"))
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
        field.formatter = SpaceNameFormatter()
        let commit = SettingsAction { [weak self] _ in self?.commitName() }
        field.target = commit
        field.action = #selector(SettingsAction.fire(_:))
        action = commit

        swatches = makeSwatches(chosen: space.gradient)
        symbols = makeSymbols(chosen: space.symbolName)
        create.onActivate = { [weak self] in
            // Belt and braces. The button takes the focus off the field first
            // (`SpaceEditorButton.mouseDown`), so by here the name has usually
            // committed itself already and this is a no-op — but the form is
            // also closed by Escape and by the column going away, and a name
            // the user typed must not depend on which of those happened.
            self?.commitName()
            self?.onClose?()
        }
        cancel.onActivate = { [weak self] in self?.onCancel?() }

        let views = [heading, caption, nameCard, colourCard, iconCard, create, cancel] as [NSView]
        for view in views { addSubview(view) }
        nameCard.addSubview(field)
        nameCard.setAccessibilityLabel(String(localized: "Name"))
        colourCard.addSubview(colourLabel)
        iconCard.addSubview(iconLabel)
        for chip in swatches { colourCard.addSubview(chip) }
        for chip in symbols { iconCard.addSubview(chip) }
        applyTokens()
    }

    /// §6.2's twelve gradients as chips, with the Space's own pair already
    /// ticked. Its own method for `makeSymbols`' reason.
    private func makeSwatches(chosen: GradientPair) -> [SpaceSwatchChip] {
        zip(SpaceAppearanceView.gradients, SpaceAppearanceView.gradientNames).map { gradient, label in
            let chip = SpaceSwatchChip(gradient: gradient, label: label)
            chip.isChosen = gradient == chosen
            chip.onActivate = { [weak self] in
                self?.choose(gradient: gradient)
                self?.onGradient?(gradient)
            }
            return chip
        }
    }

    /// The icon grid, same shape as `makeSwatches`. Both are out of `init`
    /// because a grid of chips that each close over `self` is a thing to read
    /// on its own, not part of assembling a form.
    private func makeSymbols(chosen: String) -> [SpaceSymbolChip] {
        SpacesSection.symbols.map { symbol in
            let chip = SpaceSymbolChip(symbolName: symbol.name, label: symbol.label)
            chip.isChosen = symbol.name == chosen
            chip.onActivate = { [weak self] in
                self?.choose(symbol: symbol.name)
                self?.onIcon?(symbol.name)
            }
            return chip
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

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
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTokens()
    }

    /// Escape closes it, keeping the Space and the name in the field. Escape
    /// is not `Cancel` — see the file header for why the two differ.
    override func cancelOperation(_ sender: Any?) {
        commitName()
        onClose?()
    }

    /// Hands the typed name up, once.
    ///
    /// `committedName` rather than `space.name`, which is the Space as it was
    /// when the form opened and is stale the moment the first rename lands:
    /// compared against that, every later commit looks like a change and the
    /// field would re-send the same name on every route out of the form.
    private func commitName() {
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != committedName else { return }
        committedName = name
        onRename?(name)
    }

    override var acceptsFirstResponder: Bool { true }

    /// A click on a card's empty space is a click on the field it holds — the
    /// plate is the control's whole target, the way a table row is.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard nameCard.frame.contains(point) else {
            super.mouseDown(with: event)
            return
        }
        focusName()
    }

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

        let pad = Tokens.Metric.settingsControlInset
        top = place(heading, at: top, width: width)
        top = place(caption, at: top - gap / 2, width: width) - Tokens.Metric.chromeGapWide

        let nameHeight = Tokens.Metric.urlPill.height
        nameCard.frame = NSRect(x: inset, y: top - nameHeight, width: width, height: nameHeight).integral
        let fieldHeight = ceil(field.fittingSize.height)
        field.frame = NSRect(
            x: pad,
            y: ((nameHeight - fieldHeight) / 2).rounded(),
            width: max(width - 2 * pad, 0),
            height: fieldHeight
        )
        top = nameCard.frame.minY - gap

        top = place(colourCard, label: colourLabel, chips: swatches, at: top, width: width) - gap
        top = place(iconCard, label: iconLabel, chips: symbols, at: top, width: width)

        let pill = Tokens.Metric.urlPill.height
        create.frame = NSRect(x: inset, y: top - Tokens.Metric.chromeGapWide - pill, width: width, height: pill)
            .pixelAligned
        cancel.frame = NSRect(x: inset, y: create.frame.minY - gap - pill, width: width, height: pill).pixelAligned
    }

    /// A label at its own height rather than at a row's: a 15 pt title and an
    /// 11 pt caption in boxes the same size are two lines that do not sit where
    /// the type says they should.
    private func place(_ label: NSTextField, at top: CGFloat, width: CGFloat) -> CGFloat {
        let height = ceil(label.fittingSize.height)
        label.frame = NSRect(x: Tokens.Metric.rowInset, y: top - height, width: width, height: height).integral
        return label.frame.minY
    }

    /// One card: its heading, then its chips, both on the plate's own inset.
    /// Returns the card's bottom edge.
    ///
    /// The grid is measured before the plate is placed, because a card is
    /// exactly as tall as what is in it — there is no fixed height to fit a
    /// wrapping grid into, and a plate sized by hand would be the one number in
    /// this file that has to be re-guessed every time the palette grows.
    private func place(
        _ card: NSView,
        label: NSTextField,
        chips: [NSView],
        at top: CGFloat,
        width: CGFloat
    ) -> CGFloat {
        let pad = Tokens.Metric.settingsControlInset
        let inner = max(width - 2 * pad, 0)
        let labelHeight = ceil(label.fittingSize.height)
        let grid = Grid(count: chips.count, width: inner)
        let height = pad + labelHeight + Tokens.Metric.chromeGap + grid.height + pad
        card.frame = NSRect(x: Tokens.Metric.rowInset, y: top - height, width: width, height: height).integral

        label.frame = NSRect(x: pad, y: height - pad - labelHeight, width: inner, height: labelHeight).integral
        let side = Tokens.Metric.settingsControl
        let chipsTop = label.frame.minY - Tokens.Metric.chromeGap
        for (index, chip) in chips.enumerated() {
            let row = index / grid.columns
            let column = index % grid.columns
            chip.frame = NSRect(
                x: pad + CGFloat(column) * (side + grid.spacing),
                y: chipsTop - CGFloat(row) * (side + grid.rowSpacing) - side,
                width: side,
                height: side
            ).pixelAligned
        }
        return card.frame.minY
    }

    /// How a run of fixed-size chips falls into the width a card has.
    ///
    /// Balanced, not greedy. Filling each row before starting the next is what
    /// a paragraph does and is wrong for a palette of fixed length: thirteen
    /// colours six to a row leave one chip alone on a line of its own, and that
    /// orphan is the first thing the eye finds. The rows are counted first and
    /// the chips spread over them — six to a row becomes five, five and three.
    ///
    /// Justified across, and no further than square down. The chips are a fixed
    /// 28 pt, so the spare width in a column the user can drag has nowhere to
    /// go but between the columns, and spending it there puts the row's ends on
    /// the card's own text edges. The rows follow that spacing rather than the
    /// chrome's gap, because a block 30 pt apart across and 8 pt down is a
    /// palette combed out — but only up to `chromeGapWide`. Past that, matching
    /// the columns exactly would push the last row of icons the better part of
    /// an inch clear of the first.
    private struct Grid {
        let columns: Int
        let rows: Int
        /// Between one chip and the next along a row.
        let spacing: CGFloat
        /// Between one row and the next. `spacing`, held at `chromeGapWide`.
        let rowSpacing: CGFloat

        init(count: Int, width: CGFloat) {
            let side = Tokens.Metric.settingsControl
            let gap = Tokens.Metric.chromeGap
            let fit = max(Int((width + gap) / (side + gap)), 1)
            rows = max(Int((CGFloat(count) / CGFloat(fit)).rounded(.up)), 1)
            columns = max(Int((CGFloat(count) / CGFloat(rows)).rounded(.up)), 1)
            spacing = columns > 1
                ? max((width - CGFloat(columns) * side) / CGFloat(columns - 1), gap)
                : gap
            rowSpacing = min(spacing, Tokens.Metric.chromeGapWide)
        }

        var height: CGFloat {
            let side = Tokens.Metric.settingsControl
            return CGFloat(rows) * side + CGFloat(rows - 1) * rowSpacing
        }
    }
}
