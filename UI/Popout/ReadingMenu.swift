//
//  ReadingMenu.swift
//  Luna
//
//  The Reading pop-out behind the Aa glyph on the URL pill: how a Markdown
//  document or a Reader page is set. It is `SiteSettingsPanel`, row for row;
//  this is what goes in it and what each control does.
//
//  Every control writes `ReadingPreferences` and restyles the tab at once.
//  Other reading tabs, and other Macs through `SyncedDefaults`, follow the
//  stored defaults (`TabController.followReadingPreferences`).
//

import AppKit
import BrowserKit
import UniformTypeIdentifiers

@MainActor
enum ReadingMenu {

    static let controller: SiteSettingsController = {
        let controller = SiteSettingsController()
        controller.label = String(localized: "Reading")
        return controller
    }()

    /// Opens the pop-out on `anchor`, or closes it. Site settings stand on the
    /// same pill and answer a different question, so only one is ever up.
    static func present(from anchor: NSView, alignedTo aligned: NSView? = nil) {
        guard let session, let tab = session.activeController, tab.state.isReading || tab.state.isArticle else { return }
        let showReader: (() -> Void)? = tab.state.isReading ? nil : { [weak session] in session?.toggleReader() }
        let content = content(document: tab.markdownDocument, view: tab.readingView, showReader: showReader) { [weak tab] preferences in
            tab?.applyReadingPreferences(preferences)
        } setView: { [weak tab] view in
            tab?.setReadingView(view)
        }
        show(content, from: anchor, alignedTo: aligned)
    }

    static func show(_ content: SiteSettingsContent, from anchor: NSView, alignedTo aligned: NSView? = nil) {
        guard let window = anchor.window else { return }
        SiteMenu.controller.dismiss()
        controller.alignsLeadingEdgeTo = aligned
        let edge: PopoutEdge = anchor.convert(anchor.bounds, to: nil).midY > window.contentLayoutRect.midY
            ? .below
            : .above
        controller.toggle(in: window, from: anchor, edge: edge, content: content)
    }

    private static var session: BrowserSession? { (NSApp.delegate as? AppDelegate)?.session }

    /// What the pop-out shows. `document` is nil on a Reader page, which has
    /// no source to show and nothing of its own to save. `showReader` is set on
    /// an article page with Reader still off; the typography rows are there
    /// too, so the choice is made before the page changes.
    static func content(
        document: MarkdownDocument?,
        view: ReadingView,
        showReader: (() -> Void)? = nil,
        defaults: UserDefaults = .standard,
        apply: @escaping (ReadingPreferences) -> Void,
        setView: @escaping (ReadingView) -> Void
    ) -> SiteSettingsContent {
        let preferences = ReadingPreferences.stored(in: defaults)
        let change: Change = { edit in
            var next = ReadingPreferences.stored(in: defaults)
            edit(&next)
            next.store(in: defaults)
            apply(next)
        }
        var content = SiteSettingsContent(heading: String(localized: "Reading"))
        content.symbol = Glyph.header
        let style: [SiteSettingsContent.Control] = [
            typeface(preferences, change),
            size(preferences, change),
            width(preferences, change),
            page(preferences, change)
        ]
        guard let document else {
            content.controls = [style]
            if let showReader {
                content.actions = [[.init(title: String(localized: "Show Reader"), symbol: Glyph.reader, run: showReader)]]
            }
            return content
        }
        content.controls = [[viewRow(view, editable: document.isEditable, setView)], style]
        content.toggles = [
            .init(title: String(localized: "Outline"), symbol: Glyph.outline, isOn: preferences.outline) { on in
                change { $0.outline = on }
            },
            .init(title: String(localized: "Wrap Long Lines"), symbol: Glyph.wrap, isOn: preferences.wrap) { on in
                change { $0.wrap = on }
            }
        ]
        content.actions = [document.url.isFileURL ? localActions(document.url) : webActions(document)]
        return content
    }

    // MARK: - Controls

    typealias Change = (_ edit: (inout ReadingPreferences) -> Void) -> Void

    /// Read and Source, and Edit for a file on this Mac that is UTF-8.
    private static func viewRow(
        _ view: ReadingView,
        editable: Bool,
        _ setView: @escaping (ReadingView) -> Void
    ) -> SiteSettingsContent.Control {
        let views: [ReadingView] = editable ? [.read, .source, .edit] : [.read, .source]
        let labels = [String(localized: "Read"), String(localized: "Source"), String(localized: "Edit")]
        let choice = SettingsChoice(labels: Array(labels.prefix(views.count)))
        choice.selectedIndex = views.firstIndex(of: view) ?? 0
        choice.onSelect = { setView(views[$0]) }
        return .init(title: String(localized: "View"), symbol: Glyph.view, view: choice)
    }

    /// Each face named in itself.
    private static func typeface(_ preferences: ReadingPreferences, _ change: @escaping Change) -> SiteSettingsContent.Control {
        let faces = ReadingPreferences.Typeface.allCases
        let base = Tokens.TypeScale.settingsRow
        let serif = base.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: base.pointSize) } ?? base
        let choice = SettingsChoice(
            labels: [String(localized: "Serif"), String(localized: "Sans"), String(localized: "Mono")],
            fonts: [serif, base, .monospacedSystemFont(ofSize: base.pointSize, weight: .regular)]
        )
        choice.selectedIndex = faces.firstIndex(of: preferences.typeface) ?? 0
        choice.onSelect = { index in change { $0.typeface = faces[index] } }
        return .init(title: String(localized: "Font"), symbol: Glyph.typeface, view: choice)
    }

    private static func size(_ preferences: ReadingPreferences, _ change: @escaping Change) -> SiteSettingsContent.Control {
        let stepper = ReadingSizeStepper(size: preferences.size)
        stepper.onStep = { step in
            var landed = 0
            change { $0.size += step; landed = $0.size }
            return landed
        }
        return .init(title: String(localized: "Text Size"), symbol: Glyph.size, view: stepper)
    }

    /// Pictures of the column rather than words: "Narrow · Medium · Wide"
    /// is wider than the room beside the row's title in a 280 pt pop-out.
    private static func width(_ preferences: ReadingPreferences, _ change: @escaping Change) -> SiteSettingsContent.Control {
        let widths = ReadingPreferences.Width.allCases
        let choice = SettingsChoice(
            labels: [String(localized: "Narrow"), String(localized: "Medium"), String(localized: "Wide")],
            symbols: Glyph.widths
        )
        choice.selectedIndex = widths.firstIndex(of: preferences.width) ?? 1
        choice.onSelect = { index in change { $0.width = widths[index] } }
        return .init(title: String(localized: "Width"), symbol: Glyph.width, view: choice)
    }

    private static func page(_ preferences: ReadingPreferences, _ change: @escaping Change) -> SiteSettingsContent.Control {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = SpacePanelMetrics.swatchGap
        var chips: [SpaceSwatchChip] = []
        for page in ReadingPreferences.Page.allCases {
            let chip = SpaceSwatchChip(gradient: swatch(page), label: name(page))
            chip.isChosen = page == preferences.page
            chip.onActivate = { [weak chip] in
                for other in chips { other.isChosen = other === chip }
                change { $0.page = page }
            }
            chips.append(chip)
            stack.addArrangedSubview(chip)
        }
        return .init(title: String(localized: "Page"), symbol: Glyph.page, view: stack)
    }

    /// A page's colour as a swatch: one colour at both ends, and Match as
    /// Paper running into Night, since it is whichever the system is.
    static func swatch(_ page: ReadingPreferences.Page) -> GradientPair {
        let light = NSAppearance(named: .aqua) ?? NSAppearance.currentDrawing()
        let dark = NSAppearance(named: .darkAqua) ?? NSAppearance.currentDrawing()
        func colour(_ face: Tokens.Reading.Page) -> RGBA {
            face.background.rgba(for: face.isDark ? dark : light)
        }
        switch page {
        case .match: return GradientPair(start: colour(.paper), end: colour(.night))
        case .paper: return GradientPair(start: colour(.paper), end: colour(.paper))
        case .sepia: return GradientPair(start: colour(.sepia), end: colour(.sepia))
        case .night: return GradientPair(start: colour(.night), end: colour(.night))
        }
    }

    private static func name(_ page: ReadingPreferences.Page) -> String {
        switch page {
        case .match: String(localized: "Match System")
        case .paper: String(localized: "Paper")
        case .sepia: String(localized: "Sepia")
        case .night: String(localized: "Night")
        }
    }

    // MARK: - Actions

    private static func localActions(_ url: URL) -> [SiteSettingsContent.Action] {
        [
            .init(title: String(localized: "Show in Finder"), symbol: Glyph.finder) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            },
            .init(title: String(localized: "Open With…"), symbol: Glyph.openWith) {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.application]
                panel.directoryURL = URL(filePath: "/Applications")
                panel.prompt = String(localized: "Open")
                panel.begin { answer in
                    guard answer == .OK, let app = panel.url else { return }
                    NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
                }
            }
        ]
    }

    private static func webActions(_ document: MarkdownDocument) -> [SiteSettingsContent.Action] {
        [
            .init(title: String(localized: "Save to Downloads"), symbol: Glyph.save) {
                guard let saved = try? saveToDownloads(document) else { return }
                PageToast.savedToDownloads(saved.lastPathComponent).show()
            },
            .init(title: String(localized: "Copy Markdown"), symbol: Glyph.copy) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(document.text, forType: .string)
                PageToast.markdownTextCopied.show()
            }
        ]
    }

    /// The text as it arrived, under its own name, numbered past any file
    /// already in the folder rather than over it.
    static func saveToDownloads(_ document: MarkdownDocument, in folder: URL? = nil) throws -> URL {
        let folder = try folder ?? FileManager.default.url(
            for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let name = document.url.lastPathComponent.isEmpty ? "Document.md" : document.url.lastPathComponent
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var target = folder.appending(path: name)
        var number = 2
        while FileManager.default.fileExists(atPath: target.path(percentEncoded: false)) {
            target = folder.appending(path: ext.isEmpty ? "\(stem) \(number)" : "\(stem) \(number).\(ext)")
            number += 1
        }
        try Data(document.text.utf8).write(to: target, options: .withoutOverwriting)
        return target
    }

    // MARK: - The glyphs

    /// Every symbol the pop-out and its pill glyph draw; `ReadingMenuTests`
    /// walks `all` so a name the system does not have fails a test.
    enum Glyph {
        static let header = "textformat.size"
        static let view = "eye"
        static let typeface = "textformat"
        static let size = "textformat.size"
        static let width = "arrow.left.and.right"
        static let page = "paintpalette"
        static let outline = "list.bullet.indent"
        static let wrap = "arrow.turn.down.left"
        static let finder = "folder"
        static let openWith = "arrow.up.forward.app"
        static let save = "square.and.arrow.down"
        static let copy = "doc.on.doc"
        static let reader = "doc.plaintext"
        static let widths = ["rectangle.portrait", "square", "rectangle"]

        static let all = [header, view, typeface, size, width, page, outline, wrap, finder, openWith, save, copy, reader] + widths
    }
}

/// A−, the size, A+. Two segments that are never chosen, only pressed, so
/// they answer the pointer as every `SettingsChoiceButton` does. The clamp is
/// `ReadingPreferences.sizes`'.
@MainActor
final class ReadingSizeStepper: NSStackView {

    /// Returns the size the step landed on, which the clamp may have held.
    var onStep: ((Int) -> Int)?
    let smaller = SettingsChoiceButton(title: String(localized: "A−"))
    let larger = SettingsChoiceButton(title: String(localized: "A+"))
    let value = NSTextField(labelWithString: "")

    init(size: Int) {
        super.init(frame: .zero)
        orientation = .horizontal
        spacing = Tokens.Metric.settingsSegmentGap
        smaller.setAccessibilityLabel(String(localized: "Smaller Text"))
        larger.setAccessibilityLabel(String(localized: "Larger Text"))
        smaller.onActivate = { [weak self] in self?.step(-1) }
        larger.onActivate = { [weak self] in self?.step(1) }
        value.font = Tokens.TypeScale.settingsRow
        value.textColor = Tokens.Text.secondary
        value.alignment = .center
        show(size)
        for view in [smaller, value, larger] { addArrangedSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    private func step(_ by: Int) {
        guard let landed = onStep?(by) else { return }
        show(landed)
    }

    private func show(_ size: Int) {
        value.stringValue = "\(size)"
    }
}
