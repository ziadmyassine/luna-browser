//
//  OnboardingView.swift
//  Luna — §30.17
//
//  First run, in two panes: what is being asked on the left, what is being
//  chosen on the right.
//
//  The split is the reference's and it earns itself — prose on an opaque plane
//  stays readable while the right side carries the Space gradient Luna is
//  actually about, and the two buttons stay in one place from the first page
//  to the last instead of moving under the pointer between steps.
//

import AppKit
import BrowserKit

@MainActor
final class OnboardingView: NSView {

    /// The last page's Continue, or the window being closed.
    var onFinished: (() -> Void)?
    /// Continue on the transfer page, with what was ticked. The host runs the
    /// import and reports back through `mark(_:as:)` and `importFinished()`.
    var onImportRequested: ((Set<ImportSource>) -> Void)?

    private let left = NSView()
    private let right = OnboardingGradientView()
    private let title = NSTextField(labelWithString: "")
    private let body = NSTextField(labelWithString: "")
    private let proceed = OnboardingButton(title: "", isPreferred: true)
    private let back = OnboardingButton(title: String(localized: "Back"), isPreferred: false)
    private let badge = NSImageView()
    private let empty = NSTextField(labelWithString: "")
    /// The theme page's answer: Settings ▸ Appearance's own control, writing
    /// the same setting, under the mark — which is drawn for the appearance it
    /// is on, so the choice shows itself as it is made.
    let themeChoice = SettingsChoice(labels: AppearanceSection.Theme.allCases.map(\.title))
    private let list: OnboardingImportList
    private var page: OnboardingPage = .welcome
    private var isImporting = false
    /// §23.2's mapping step, per source that offers one. The transfer page
    /// shows it between the tick and the import.
    private var mappings: [ImportSource: ImportMapping] = [:]
    private var mappingView: OnboardingMappingView?

    init(sources: [DetectedSource], preferring: ImportSource? = nil) {
        list = OnboardingImportList(sources: sources, preferring: preferring)
        super.init(frame: .zero)
        wantsLayer = true

        left.wantsLayer = true
        for label in [title, body] { label.wantsLayer = true }
        title.font = Tokens.TypeScale.pageTitle
        title.lineBreakMode = .byWordWrapping
        title.maximumNumberOfLines = 3
        body.font = Tokens.TypeScale.pageBody
        body.lineBreakMode = .byWordWrapping
        body.maximumNumberOfLines = 5
        badge.image = Self.appIcon
        badge.imageScaling = .scaleProportionallyUpOrDown
        badge.wantsLayer = true
        badge.setAccessibilityElement(false)
        empty.stringValue = String(localized: "No other browsers on this Mac.")
        empty.font = Tokens.TypeScale.pageBody
        empty.alignment = .center
        empty.isHidden = !list.isEmpty

        proceed.onActivate = { [weak self] in self?.advance() }
        back.onActivate = { [weak self] in self?.retreat() }
        list.onChoiceChanged = { [weak self] in self?.refreshButtons() }
        themeChoice.onSelect = { index in AppearanceSection.setTheme(AppearanceSection.Theme.allCases[index]) }

        for view in [left, right] as [NSView] { addSubview(view) }
        for view in [title, body, back, proceed] as [NSView] { left.addSubview(view) }
        for view in [badge, empty, list, themeChoice] as [NSView] { right.content.addSubview(view) }
        show(.welcome, animated: false)
        applyTokens()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// Luna's mark, from `Mark.xcassets` rather than from the app icon.
    ///
    /// The `.icon` document carries an Aqua rendition and a DarkAqua one, and
    /// both `NSApp.applicationIconImage` and `NSImage(named: CFBundleIconName)`
    /// hand back one flattened rendering of the pair — measured: the same
    /// pixels under either appearance, so the white tile stayed on a dark
    /// page. An imageset with a dark variant is the thing AppKit resolves.
    private static var appIcon: NSImage? {
        NSImage(named: "LunaMark") ?? NSApp.applicationIconImage
    }

    // MARK: - Pages

    private func advance() {
        if page == .transfer, !list.chosen.isEmpty, !isImporting {
            if mappingView == nil, let source = list.chosen.first(where: { mappings[$0] != nil }) {
                showMapping(for: source)
                return
            }
            beginImport()
            return
        }
        guard let next = page.next else {
            onFinished?()
            return
        }
        show(next, animated: true)
    }

    private func retreat() {
        if mappingView != nil, !isImporting {
            hideMapping()
            return
        }
        guard !isImporting, let previous = page.previous else { return }
        show(previous, animated: true)
    }

    var currentPage: OnboardingPage { page }

    private func show(_ page: OnboardingPage, animated: Bool) {
        self.page = page
        title.stringValue = page.title
        body.stringValue = page.body
        refreshButtons()
        if page == .theme {
            themeChoice.selectedIndex = AppearanceSection.Theme.allCases.firstIndex(of: AppearanceSection.theme) ?? 0
            themeChoice.isHidden = false
        }
        needsLayout = true
        layoutSubtreeIfNeeded()
        guard animated else {
            badge.alphaValue = page == .transfer ? 0 : 1
            list.alphaValue = page == .transfer ? 1 : 0
            empty.alphaValue = list.alphaValue
            themeChoice.alphaValue = page == .theme ? 1 : 0
            themeChoice.isHidden = page != .theme
            return
        }
        crossFade()
        if page == .transfer { list.playEntrance() }
    }

    /// The pane's two halves change together: the words slide up a little as
    /// they arrive, and whichever side of the right pane belongs to this page
    /// fades in over the other.
    private func crossFade() {
        let lift = Tokens.Metric.chromeGapWide
        for view in [title, body] as [NSView] {
            Tokens.Motion.immediately {
                view.alphaValue = 0
                view.layer?.setAffineTransform(CGAffineTransform(translationX: 0, y: -lift))
            }
        }
        Tokens.Motion.animate(Tokens.Motion.layoutSwitch, { context in
            context.allowsImplicitAnimation = true
            for view in [title, body] as [NSView] {
                view.animator().alphaValue = 1
                view.layer?.setAffineTransform(.identity)
            }
            badge.animator().alphaValue = page == .transfer ? 0 : 1
            list.animator().alphaValue = page == .transfer && mappingView == nil ? 1 : 0
            empty.animator().alphaValue = page == .transfer && mappingView == nil ? 1 : 0
            mappingView?.animator().alphaValue = 1
            themeChoice.animator().alphaValue = page == .theme ? 1 : 0
        }, completion: { [weak self] in
            // Out of the way once faded, or its segments would still take a
            // press on a page that does not show them.
            MainActor.assumeIsolated {
                guard let self else { return }
                self.themeChoice.isHidden = self.page != .theme
            }
        })
    }

    private func refreshButtons() {
        back.isEnabled = page.previous != nil && !isImporting
        back.alphaValue = page.previous == nil ? 0 : (back.isEnabled ? 1 : 0.4)
        guard page == .transfer, !isImporting else {
            proceed.title = page.continueTitle
            return
        }
        guard !list.isEmpty else {
            proceed.title = page.continueTitle
            return
        }
        proceed.title = list.chosen.isEmpty
            ? String(localized: "Not now")
            : String(localized: "Bring it across")
    }

    // MARK: - The mapping step

    /// Offered by the host once it has read what the source has.
    func offerMapping(_ mapping: ImportMapping, for source: ImportSource) {
        guard !mapping.categories.isEmpty else { return }
        mappings[source] = mapping
    }

    /// The answers, edited or not. Nil for a source that offered none.
    func mapping(for source: ImportSource) -> ImportMapping? {
        mappings[source]
    }

    var isShowingMapping: Bool { mappingView != nil }

    private func showMapping(for source: ImportSource) {
        guard let mapping = mappings[source] else { return }
        let step = OnboardingMappingView(mapping: mapping)
        step.onChange = { [weak self] in self?.mappings[source] = $0 }
        step.alphaValue = 0
        right.content.addSubview(step)
        mappingView = step
        title.stringValue = String(localized: "Choose where things go")
        body.stringValue = String(localized: "Pick where each part of \(source.displayName) lands in Luna, or skip it.")
        needsLayout = true
        layoutSubtreeIfNeeded()
        crossFade()
    }

    private func hideMapping() {
        mappingView?.removeFromSuperview()
        mappingView = nil
        show(.transfer, animated: true)
    }

    // MARK: - The import

    private func beginImport() {
        // Back to the list, which is where each browser shows its progress.
        if mappingView != nil {
            mappingView?.removeFromSuperview()
            mappingView = nil
            show(.transfer, animated: true)
        }
        isImporting = true
        list.setRunning(true)
        refreshButtons()
        proceed.title = String(localized: "Bringing it across…")
        proceed.isEnabled = false
        onImportRequested?(list.chosen)
    }

    func mark(_ source: ImportSource, as state: OnboardingImportRow.State) {
        list.row(for: source)?.state = state
    }

    func importFinished() {
        isImporting = false
        list.setRunning(false)
        proceed.isEnabled = true
        show(.finish, animated: true)
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        Tokens.Motion.immediately { place() }
    }

    private func place() {
        let pane = OnboardingMetrics.leftPane
        left.frame = NSRect(x: 0, y: 0, width: pane, height: bounds.height)
        right.frame = NSRect(x: pane, y: 0, width: max(bounds.width - pane, 0), height: bounds.height)

        let margin = OnboardingMetrics.margin
        let width = max(left.bounds.width - 2 * margin, 0)
        let pill = Tokens.Metric.capsuleHeight
        let gap = Tokens.Metric.chromeGap
        proceed.frame = NSRect(x: margin, y: margin, width: width, height: pill).pixelAligned
        back.frame = NSRect(x: margin, y: margin + pill + gap, width: width, height: pill).pixelAligned

        // The words start at the top of the column and the answers stay at the
        // foot of it, so three pages of different lengths open on one line.
        let bodyHeight = ceil(body.sizeThatFits(NSSize(width: width, height: .greatestFiniteMagnitude)).height)
        let titleHeight = ceil(title.sizeThatFits(NSSize(width: width, height: .greatestFiniteMagnitude)).height)
        // Clear of the traffic lights by the same drop §3.1's headless
        // sidebar uses, and then the page's own margin again: a 26 pt line
        // one `chromeGapWide` under three circles reads as their caption.
        let top = left.bounds.maxY - Tokens.Metric.sidebarHeadlessRow - margin
        title.frame = NSRect(x: margin, y: top - titleHeight, width: width, height: titleHeight).integral
        body.frame = NSRect(x: margin, y: title.frame.minY - gap - bodyHeight, width: width, height: bodyHeight).integral

        let inner = CGRect(origin: .zero, size: right.frame.size)
        let side = min(OnboardingMetrics.badge, inner.width - 2 * margin)
        badge.frame = NSRect(
            x: inner.midX - side / 2,
            y: inner.midY - side / 2,
            width: side,
            height: side
        ).integral
        // Under the mark by the page's margin, centred on it.
        let choice = themeChoice.fittingSize
        themeChoice.frame = NSRect(
            x: inner.midX - choice.width / 2,
            y: badge.frame.minY - margin - choice.height,
            width: choice.width,
            height: choice.height
        ).integral
        // The full pane, not an inset one: `OnboardingImportList` stands its
        // own cards in from the sides, and a scroll view that stops short of
        // the edge clips the card nearest it the moment one is pressed.
        list.frame = inner
        if let mappingView {
            let width = max(inner.width - 2 * margin, 0)
            let height = min(mappingView.height(forWidth: width), max(inner.height - 2 * margin, 0))
            mappingView.frame = NSRect(x: margin, y: inner.midY - height / 2, width: width, height: height).integral
        }
        let emptyHeight = ceil(empty.fittingSize.height)
        empty.frame = NSRect(
            x: margin,
            y: inner.midY - emptyHeight / 2,
            width: max(inner.width - 2 * margin, 0),
            height: emptyHeight
        ).integral
        badge.layer.map { Tokens.Shadow.popover.apply(to: $0, in: effectiveAppearance) }
    }

    private func applyTokens() {
        // Resolved against this view's own appearance. `cgColor` answers for
        // whatever appearance is current, and inside an appearance change that
        // is still the old one: the plate stayed dark under Light's black ink.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            left.layer?.backgroundColor = Tokens.Surface.base.cgColor
        }
        title.textColor = Tokens.Text.primary
        body.textColor = Tokens.Text.secondary
        empty.textColor = Tokens.Text.secondary
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTokens()
        // The mark's shadow is resolved in `place()`.
        needsLayout = true
    }
}

/// The right pane: the sidebar's own material — §2's glass under §8.2a's
/// Space wash — with whatever the page puts on it.
///
/// Not a colour of its own. It was a flattened gradient blended a quarter of
/// the way toward the content plane, which is a hand-mixed plate that happens
/// to resemble Luna rather than a piece of Luna, and it drifts the moment
/// either end of the pair moves. The sidebar is two views, a material and a
/// tint; this is the same two.
@MainActor
final class OnboardingGradientView: NSView {

    let content = NSView()
    private let plane = Glass.backing(.sidebar)
    private let wash = SpaceWashView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        for view in [plane, wash, content] { addSubview(view) }
        // Neutral, which `SpaceWashView` paints as nothing at all: the
        // material is the colour. A Space's own pair on this pane is a tint
        // over a browser the user has not seen yet, claiming a Space they
        // have not picked.
        wash.show(Tokens.Gradient.neutral)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override func layout() {
        super.layout()
        Tokens.Motion.immediately {
            for view in [plane, wash, content] { view.frame = bounds }
        }
    }
}
