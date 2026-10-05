//
//  AgentMarkdown+Blocks.swift
//  Luna
//
//  The agent's Markdown cut into what the panel draws differently: prose,
//  which is one run of text; a table, which is a grid; and code, which is a
//  box of its own. A table set as text was every cell on a line of its own,
//  the headers and the prices a long column of one word each.
//

import AppKit

extension AgentMarkdown {

    enum Segment {
        case text(NSAttributedString)
        case table(Table)
        case code(String)
    }

    /// A table's cells as set text, the header row apart.
    struct Table {
        var header: [NSAttributedString] = []
        var rows: [[NSAttributedString]] = []
        var columns: Int { max(header.count, rows.map(\.count).max() ?? 0) }
    }

    static func segments(_ markdown: String) -> [Segment] {
        guard let parsed = parse(markdown) else { return [.text(plain(markdown))] }
        var reader = SegmentReader()
        for run in parsed.runs { reader.read(run, of: parsed) }
        reader.flush()
        return reader.segments
    }

    /// Reads runs in order, keeping the block being built until a run of
    /// another kind ends it.
    @MainActor
    private struct SegmentReader {
        var segments: [Segment] = []
        private var text = TextBuilder()
        private var table: (identity: Int, header: [Int: NSMutableAttributedString], rows: [Int: [Int: NSMutableAttributedString]])?
        private var code: (identity: Int, text: String)?

        mutating func read(_ run: AttributedString.Runs.Run, of parsed: AttributedString) {
            let components = run.presentationIntent?.components ?? []
            let string = String(parsed[run.range].characters)
            if let tableBlock = components.first(where: { if case .table = $0.kind { true } else { false } }) {
                flushText()
                flushCode()
                if table?.identity != tableBlock.identity {
                    flushTable()
                    table = (tableBlock.identity, [:], [:])
                }
                addCell(run, string, components)
            } else if let codeBlock = components.first(where: { AgentMarkdown.isCode($0.kind) }) {
                flushText()
                flushTable()
                if code?.identity != codeBlock.identity {
                    flushCode()
                    code = (codeBlock.identity, "")
                }
                code?.text += string
            } else {
                flushTable()
                flushCode()
                text.append(run, of: parsed)
            }
        }

        private mutating func addCell(_ run: AttributedString.Runs.Run, _ string: String, _ components: [PresentationIntent.IntentType]) {
            var column = 0
            var row: Int?
            for component in components {
                switch component.kind {
                case let .tableCell(index): column = index
                case let .tableRow(index): row = index
                default: break
                }
            }
            let header = row == nil
            let font = NSFont.systemFont(ofSize: Tokens.TypeScale.agentStep.pointSize, weight: header ? .semibold : .regular)
            var attributes = AgentMarkdown.attributes(of: run, intent: nil, base: font)
            attributes[.paragraphStyle] = nil
            if header { attributes[.foregroundColor] = Tokens.Text.secondary }
            let piece = NSAttributedString(string: string, attributes: attributes)
            // Stored, not only appended to: a dictionary's default is a new
            // object each time a class is only read through it.
            if let row {
                let cell = table?.rows[row]?[column] ?? NSMutableAttributedString()
                cell.append(piece)
                table?.rows[row, default: [:]][column] = cell
            } else {
                let cell = table?.header[column] ?? NSMutableAttributedString()
                cell.append(piece)
                table?.header[column] = cell
            }
        }

        mutating func flush() {
            flushText()
            flushTable()
            flushCode()
        }

        private mutating func flushText() {
            guard text.result.length > 0 else { return }
            segments.append(.text(text.result))
            text = TextBuilder()
        }

        private mutating func flushTable() {
            guard let table else { return }
            self.table = nil
            func line(_ cells: [Int: NSMutableAttributedString]) -> [NSAttributedString] {
                let count = (cells.keys.max() ?? -1) + 1
                return (0 ..< count).map { cells[$0] ?? NSAttributedString() }
            }
            let rows = table.rows.keys.sorted().map { line(table.rows[$0] ?? [:]) }
            segments.append(.table(Table(header: line(table.header), rows: rows)))
        }

        private mutating func flushCode() {
            guard let code else { return }
            self.code = nil
            segments.append(.code(code.text.hasSuffix("\n") ? String(code.text.dropLast()) : code.text))
        }
    }
}

/// A Markdown table: a card in the steps' style, the header row in quiet
/// ink over a hairline, and a hairline between rows. Columns share the
/// width; a cell's words wrap within its column.
@MainActor
final class AgentTableView: NSView {

    private let rows = NSStackView()

    init(_ table: AgentMarkdown.Table) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = Tokens.Metric.agentBubbleRadius - 2
        layer?.cornerCurve = .continuous
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 0
        rows.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rows)
        NSLayoutConstraint.activate([
            rows.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            rows.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            rows.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            rows.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10)
        ])
        let columns = table.columns
        let lines = (table.header.isEmpty ? [] : [table.header]) + table.rows
        for (index, line) in lines.enumerated() {
            if index > 0 { addRule() }
            let row = NSStackView(views: (0 ..< columns).map { cell(line[safe: $0]) })
            row.distribution = .fillEqually
            row.alignment = .top
            row.spacing = 8
            row.edgeInsets = NSEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
            rows.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }
        Glass.apply(.control, to: self, cornerRadius: Tokens.Metric.agentBubbleRadius - 2)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    private func cell(_ text: NSAttributedString?) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: "")
        label.attributedStringValue = text ?? NSAttributedString()
        label.isSelectable = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    private func addRule() {
        let line = AgentHairline()
        line.wantsLayer = true
        line.translatesAutoresizingMaskIntoConstraints = false
        rows.addArrangedSubview(line)
        NSLayoutConstraint.activate([
            line.heightAnchor.constraint(equalToConstant: Tokens.Metric.hairline),
            line.widthAnchor.constraint(equalTo: rows.widthAnchor)
        ])
    }

    override func layout() {
        super.layout()
        // Each cell wraps at its column's width.
        for case let row as NSStackView in rows.arrangedSubviews {
            let width = row.arrangedSubviews.isEmpty ? 0
                : (row.bounds.width - CGFloat(row.arrangedSubviews.count - 1) * row.spacing) / CGFloat(row.arrangedSubviews.count)
            for case let label as NSTextField in row.arrangedSubviews { label.preferredMaxLayoutWidth = max(width, 20) }
        }
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.borderColor = Tokens.Astro.from.withAlphaComponent(0.28).cgColor
        layer?.borderWidth = Tokens.Metric.hairline
    }
}

/// A block of code: monospaced, wrapping, on a recessed wash.
@MainActor
final class AgentCodeView: NSView {

    private let label = NSTextField(wrappingLabelWithString: "")

    init(_ code: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        label.font = .monospacedSystemFont(ofSize: Tokens.TypeScale.agentStep.pointSize - 0.5, weight: .regular)
        label.textColor = Tokens.Text.primary
        label.stringValue = code
        label.isSelectable = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override func layout() {
        super.layout()
        label.preferredMaxLayoutWidth = max(bounds.width - 20, 40)
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = Tokens.Surface.hover.cgColor
    }
}

/// A hairline in the line ink, which follows the appearance.
@MainActor
final class AgentHairline: NSView {
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        layer?.backgroundColor = Tokens.Line.hairline.cgColor
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
