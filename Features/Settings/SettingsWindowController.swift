//
//  SettingsWindowController.swift
//  Luna
//
//  `⌘,`. **Shaped like the browser**: a glass sidebar listing the sections and
//  a plain content plane beside it holding the one that is selected — the same
//  two surfaces §3 and §3.6 give the browser window, in the same materials.
//
//  It started as a 420 × 160 box with a segmented control in it, on the theory
//  that Settings is the app talking about itself and should look like a system
//  dialog. That reads as a different app. Settings is where a user goes to
//  change the thing they are looking at, and the shortest path between the two
//  is for it to look like the thing they are looking at.
//
//  **Sections live in `SettingsPane.all`, not here.** This file owns the
//  window, the list and which pane is on screen; it knows nothing about what
//  any pane contains. Adding one is a `SettingsPane` and a view.
//

import AppKit

@MainActor
final class SettingsWindowController: NSWindowController {

    private let list = SettingsSidebarView()
    private let paneHost = SettingsPaneHostView()
    private var pane: NSView?

    convenience init() {
        let size = Tokens.Metric.settingsWindow
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Settings")
        window.titlebarAppearsTransparent = true
        // **The same window Luna's own is.** The sidebar column here is
        // `.sidebar` glass, and glass composites what is behind the *window* —
        // so on an opaque window it had nothing to sample and came out as a
        // flat plate beside a browser sidebar that is a pane of the desktop.
        // Clearing the window's own drawing is what lets the material through;
        // the pane on the right is opaque in its own right, exactly as §3.6's
        // content card is.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
        window.contentView = buildContent()
        list.select(SettingsPane.all.first?.id, notify: true)
    }

    /// Brings the window up and focuses it, creating nothing new on the second
    /// `⌘,` — `AppDelegate` keeps the one instance.
    func present() {
        showWindow(self)
        window?.makeKeyAndOrderFront(self)
        NSApp.activate()
    }

    // MARK: - Build

    private func buildContent() -> NSView {
        let root = NSView()
        // The same plane the browser window is made of, so the sidebar column
        // below is a window onto it.
        Glass.apply(.sidebar, to: root)

        for view in [list, paneHost] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        list.onSelect = { [weak self] id in self?.show(id) }

        NSLayoutConstraint.activate([
            list.topAnchor.constraint(equalTo: root.topAnchor),
            list.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            list.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            list.widthAnchor.constraint(equalToConstant: Tokens.Metric.settingsSidebarWidth),

            paneHost.topAnchor.constraint(equalTo: root.topAnchor),
            paneHost.leadingAnchor.constraint(equalTo: list.trailingAnchor),
            paneHost.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            paneHost.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        return root
    }

    // MARK: - Panes

    private func show(_ id: String?) {
        pane?.removeFromSuperview()
        pane = nil
        guard let id, let entry = SettingsPane.all.first(where: { $0.id == id }) else { return }
        let view = entry.build()
        view.translatesAutoresizingMaskIntoConstraints = false
        paneHost.addSubview(view)
        let inset = Tokens.Metric.settingsPaneInset
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: paneHost.topAnchor, constant: inset),
            view.leadingAnchor.constraint(equalTo: paneHost.leadingAnchor, constant: inset),
            view.trailingAnchor.constraint(lessThanOrEqualTo: paneHost.trailingAnchor, constant: -inset),
            view.bottomAnchor.constraint(lessThanOrEqualTo: paneHost.bottomAnchor, constant: -inset)
        ])
        pane = view
    }
}

/// The browser's content pane, in miniature: opaque `Surface.base`, rounded on
/// the one edge that is not a window edge, with the same hairline the page
/// carries against the sidebar (§3.6). It is what makes the glass column beside
/// it read as a sidebar rather than as a tinted margin.
@MainActor
final class SettingsPaneHostView: NSView {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = Tokens.Metric.contentCardRadius
        layer?.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.backgroundColor = Tokens.Surface.base.cgColor
        layer.borderWidth = Tokens.Metric.hairline
        layer.borderColor = Tokens.Line.border.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

// MARK: - The section list

/// The Settings sidebar: `SettingsPane.all`, one row each, the selected one
/// carrying glass. Selection is the material here for the same reason it is in
/// §3.4's tab list — Luna has no blue highlight.
@MainActor
final class SettingsSidebarView: NSView {

    var onSelect: ((String) -> Void)?

    private var rows: [SettingsRowButton] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityRole(.list)
        setAccessibilityLabel(String(localized: "Settings sections"))
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    private func build() {
        rows = SettingsPane.all.map { pane in
            let row = SettingsRowButton(pane: pane)
            row.onActivate = { [weak self] in self?.select(pane.id, notify: true) }
            return row
        }
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Tokens.Metric.rowGap
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        // Clear of the titlebar, so the first row is not under the close
        // button — the window has no title bar of its own to push it down.
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: Tokens.Metric.topBarHeight),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Tokens.Metric.rowInset),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Tokens.Metric.rowInset)
        ])
        for row in rows {
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    func select(_ id: String?, notify: Bool = false) {
        for row in rows { row.isSelected = row.pane.id == id }
        if notify, let id { onSelect?(id) }
    }

    /// Dragging the Settings sidebar's background moves the window, the same
    /// way the browser's does.
    override var mouseDownCanMoveWindow: Bool { true }
}

/// One section row: `[glyph] Title` in a §3.4-shaped pill.
@MainActor
final class SettingsRowButton: NSView {

    let pane: SettingsPane
    var onActivate: (() -> Void)?

    var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            refresh()
        }
    }

    private let fill = NSView()
    /// The selected row's material, built the first time it is selected — the
    /// same "glass is the highlight" rule the browser's own rows follow.
    private var glass: NSView?
    private let glyph = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var isHovering = false

    init(pane: SettingsPane) {
        self.pane = pane
        super.init(frame: .zero)
        wantsLayer = true
        buildContents()
        refresh()
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(pane.title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    private func buildContents() {
        fill.wantsLayer = true
        fill.layer?.cornerCurve = .continuous
        fill.layer?.cornerRadius = Tokens.Metric.rowCornerRadius
        glyph.image = NSImage(systemSymbolName: pane.symbolName, accessibilityDescription: nil)
        glyph.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: Tokens.Metric.faviconSize,
            weight: .regular
        )
        label.stringValue = pane.title
        label.font = Tokens.TypeScale.sidebarRow

        for view in [fill, glyph, label] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Tokens.Metric.rowPillHeight),
            fill.topAnchor.constraint(equalTo: topAnchor),
            fill.leadingAnchor.constraint(equalTo: leadingAnchor),
            fill.trailingAnchor.constraint(equalTo: trailingAnchor),
            fill.bottomAnchor.constraint(equalTo: bottomAnchor),
            glyph.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Tokens.Metric.rowFaviconInset),
            glyph.centerYAnchor.constraint(equalTo: centerYAnchor),
            glyph.widthAnchor.constraint(equalToConstant: Tokens.Metric.faviconSize),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Tokens.Metric.rowTitleInset),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Tokens.Metric.rowInset)
        ])
    }

    private func refresh() {
        let lit = isSelected || isHovering
        if isSelected, glass == nil {
            glass = Glass.apply(.control, to: fill, cornerRadius: Tokens.Metric.rowCornerRadius)
        }
        glass?.alphaValue = isSelected ? 1 : 0
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.fill.layer?.backgroundColor = self.isSelected
                ? Tokens.Surface.selected.cgColor
                : (self.isHovering ? Tokens.Surface.hover.cgColor : nil)
        }
        glyph.contentTintColor = lit ? Tokens.Text.primary : Tokens.Text.secondary
        label.textColor = lit ? Tokens.Text.primary : Tokens.Text.secondary
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        refresh()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        refresh()
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onActivate?()
    }

    override func accessibilityPerformPress() -> Bool {
        onActivate?()
        return true
    }
}
