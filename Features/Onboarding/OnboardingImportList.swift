//
//  OnboardingImportList.swift
//  Luna — §30.17, §30.18
//
//  The browsers on this Mac, as cards you can pick more than one of.
//
//  Only the ones that are actually installed. §30.18 asked for the rest to be
//  listed greyed out, and on a real Mac that is eight rows of "isn't installed
//  on this Mac" around the two that are — a wall with the answer hidden in it.
//  An installed browser Luna cannot yet read keeps its place and says why
//  (Safari, which needs Full Disk Access), because that one is a thing the
//  user can fix.
//

import AppKit

@MainActor
final class OnboardingImportList: NSView {

    /// What the Continue button reads to know whether there is anything to do.
    private(set) var chosen: Set<ImportSource> = []

    var onChoiceChanged: (() -> Void)?

    private let scroll = NSScrollView()
    /// `FlippedView` (§23.1's, reused): an unflipped document view puts
    /// `NSScrollView` at the bottom of its content on the first frame, which
    /// showed the last four browsers and none of the installed ones.
    private let content = FlippedView()
    private var rows: [OnboardingImportRow] = []

    /// - Parameters:
    ///   - sources: already filtered to what is on this Mac — see
    ///     `OnboardingWindowController`, which does it once for the list and
    ///     the import both.
    ///   - preferring: the browser to start ticked. The caller supplies the
    ///     machine's answer rather than this view reading it, so the rule can
    ///     be proved without the test depending on which browser opens a link
    ///     on the Mac the suite is running on.
    init(sources: [DetectedSource], preferring: ImportSource? = nil) {
        super.init(frame: .zero)
        rows = sources.map { source in
            let row = OnboardingImportRow(source: source)
            row.onToggle = { [weak self] in self?.toggle(source.source) }
            if let url = source.remedy?.settingsURL {
                row.onRemedy = { NSWorkspace.shared.open(url) }
            }
            return row
        }
        if let start = Self.opening(of: sources, preferring: preferring) {
            chosen.insert(start)
            rows.first { $0.source.source == start }?.isChosen = true
        }
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        scroll.documentView = content
        content.translatesAutoresizingMaskIntoConstraints = true
        for row in rows { content.addSubview(row) }
        addSubview(scroll)
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "Browsers to bring across"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// Which card the screen opens on: the browser the user already browses
    /// in, or the first one Luna can read. A tick has to be there from the
    /// start — bringing your things across is the expected answer, and a list
    /// of empty circles asks the user to work that out from the button — and
    /// the one they would pick is the one they are switching from.
    ///
    /// It is a tick, not a commitment: the row it lands on unticks like any
    /// other, which is the whole reason the page has circles rather than a
    /// list it acts on wholesale.
    static func opening(of sources: [DetectedSource], preferring: ImportSource?) -> ImportSource? {
        if let preferring, sources.contains(where: { $0.source == preferring && $0.isAvailable }) {
            return preferring
        }
        return sources.first(where: \.isAvailable)?.source
    }

    /// The browser macOS hands a link to, when it is one Luna knows.
    static func systemDefault() -> ImportSource? {
        guard let web = URL(string: "https://example.com"),
              let app = NSWorkspace.shared.urlForApplication(toOpen: web),
              let identifier = Bundle(url: app)?.bundleIdentifier
        else { return nil }
        return ImportSource.allCases.first {
            $0.bundleIdentifier.caseInsensitiveCompare(identifier) == .orderedSame
        }
    }

    /// On disk, which is not the same question as `DetectedSource.isAvailable`:
    /// that one asks whether there is a profile to read, and a browser
    /// installed but never opened has none.
    static func isInstalled(_ source: ImportSource) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleIdentifier) != nil
    }

    /// Nothing to offer, which is a sentence rather than an empty box.
    var isEmpty: Bool { rows.isEmpty }

    private func toggle(_ source: ImportSource) {
        if chosen.contains(source) { chosen.remove(source) } else { chosen.insert(source) }
        rows.first { $0.source.source == source }?.isChosen = chosen.contains(source)
        onChoiceChanged?()
    }

    func row(for source: ImportSource) -> OnboardingImportRow? {
        rows.first { $0.source.source == source }
    }

    /// Locks the list while the import runs: a row that changed its mind
    /// halfway would be a request nobody made.
    func setRunning(_ running: Bool) {
        for row in rows where running && !chosen.contains(row.source.source) {
            row.alphaValue = 0.35
        }
        guard !running else { return }
        for row in rows { row.alphaValue = 1 }
    }

    override func layout() {
        super.layout()
        Tokens.Motion.immediately {
            scroll.frame = bounds
            let inset = OnboardingMetrics.cardInset
            let gap = OnboardingMetrics.rowGap
            let height = CGFloat(rows.count) * OnboardingMetrics.rowHeight
                + CGFloat(max(rows.count - 1, 0)) * gap
            // A gap above and below, for the same reason the cards stand in
            // from the sides: `pressSwell` grows a card, and the scroll view
            // clips whatever grows past it.
            content.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(height + 2 * gap, bounds.height))
            // Centred while they fit, which is most Macs: three cards pinned
            // to the top of a tall pane read as a list that has been cut off.
            var top = max((content.frame.height - height) / 2, gap).rounded()
            for row in rows {
                row.frame = NSRect(
                    x: inset,
                    y: top,
                    width: max(bounds.width - 2 * inset, 0),
                    height: OnboardingMetrics.rowHeight
                ).integral
                top = row.frame.maxY + gap
            }
        }
    }

    /// The rows arrive one after another rather than all at once — §6's tab
    /// insert, staggered by the same 20 ms a layout switch staggers its
    /// contents by. Under Reduce Motion `animate` runs at zero duration and
    /// they are simply there.
    func playEntrance() {
        guard !Tokens.Motion.reduceMotion else { return }
        for (index, row) in rows.enumerated() {
            Tokens.Motion.immediately {
                row.alphaValue = 0
                row.layer?.setAffineTransform(CGAffineTransform(translationX: 0, y: -OnboardingMetrics.rowGap * 4))
            }
            let delay = Double(index) * OnboardingMetrics.stagger
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainActor.assumeIsolated {
                    Tokens.Motion.animate(Tokens.Motion.tabInsert) { context in
                        context.allowsImplicitAnimation = true
                        row.animator().alphaValue = 1
                        row.layer?.setAffineTransform(.identity)
                    }
                }
            }
        }
    }
}

extension OnboardingMetrics {
    /// §6's layout switch staggers its contents by 20 ms; a list of rows
    /// arriving is the same idea one surface down.
    static var stagger: TimeInterval { 0.02 }
}
