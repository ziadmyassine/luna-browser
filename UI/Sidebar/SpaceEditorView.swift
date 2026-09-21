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
//  One text grid, and everything is on it. The name used to start a
//  `pillTextInset` further in than the heading above it, because it was inside
//  a pill and the headings were not. The title and caption sit at `rowInset`
//  with the cards' outer edges; every card's heading and content sit at
//  `settingsControlInset` inside their plate. Two edges, both deliberate.
//
//  It edits; it does not gate. The Space already exists by the time this is on
//  screen — the swipe made it — so there is no Cancel that could undo one, and
//  closing this leaves a Space behind either way. A form you have to finish is
//  a form you can fail, and there is nothing here worth failing. The button at
//  the foot says `Create Space` regardless, because that is the sentence the
//  user is in the middle of; Escape does the same thing.
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
    /// The form is finished with — `Create Space`, or Escape. The Space is
    /// there either way; see the file header.
    var onClose: (() -> Void)?

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
    private var action: SettingsAction?

    init(space: Space) {
        create = SpaceEditorButton(title: String(localized: "Create Space"))
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
        create.onActivate = { [weak self] in self?.onClose?() }

        for view in [heading, caption, nameCard, colourCard, iconCard, create] as [NSView] { addSubview(view) }
        nameCard.addSubview(field)
        nameCard.setAccessibilityLabel(String(localized: "Name"))
        colourCard.addSubview(colourLabel)
        iconCard.addSubview(iconLabel)
        for chip in swatches { colourCard.addSubview(chip) }
        for chip in symbols { iconCard.addSubview(chip) }
        applyTokens()
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

    /// Escape closes it. Nothing is lost: the Space exists, and the name in the
    /// field was committed when it was typed.
    override func cancelOperation(_ sender: Any?) {
        onClose?()
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

        // The title block sits on the cards' text edge rather than on their
        // outer one, so there is one column of type down the whole form and the
        // plates are the only thing that reaches past it.
        let pad = Tokens.Metric.settingsControlInset
        let textWidth = max(width - 2 * pad, 0)
        top = place(heading, at: top, width: textWidth)
        top = place(caption, at: top - gap / 2, width: textWidth) - Tokens.Metric.chromeGapWide

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

        create.frame = NSRect(
            x: inset,
            y: top - Tokens.Metric.chromeGapWide - Tokens.Metric.urlPill.height,
            width: width,
            height: Tokens.Metric.urlPill.height
        ).pixelAligned
    }

    /// A label at its own height rather than at a row's: a 15 pt title and an
    /// 11 pt caption in boxes the same size are two lines that do not sit where
    /// the type says they should.
    private func place(_ label: NSTextField, at top: CGFloat, width: CGFloat) -> CGFloat {
        let x = Tokens.Metric.rowInset + Tokens.Metric.settingsControlInset
        let height = ceil(label.fittingSize.height)
        label.frame = NSRect(x: x, y: top - height, width: width, height: height).integral
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
