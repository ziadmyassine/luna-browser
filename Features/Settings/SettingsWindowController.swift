//
//  SettingsWindowController.swift
//  Luna
//
//  `⌘,`. A plain, small, system-chrome window — deliberately *not* one of §3's
//  glass surfaces. Settings is not part of the browsing surface, it is the app
//  talking about itself, and a floating frameless glass panel here would read
//  as another piece of the browser.
//
//  Built in code like everything else (§0.3: there is no nib in Luna). One
//  section today; `sections` is where the next one goes.
//

import AppKit

@MainActor
final class SettingsWindowController: NSWindowController {

    private let layoutControl = NSSegmentedControl()
    private let layoutDetail = NSTextField(labelWithString: "")

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 160),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Settings")
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
        window.contentView = buildContent()
        readSettings()
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
        let heading = NSTextField(labelWithString: String(localized: "Tab layout"))
        heading.font = .preferredFont(forTextStyle: .headline)

        layoutControl.segmentCount = ChromeLayoutPreference.allCases.count
        layoutControl.segmentStyle = .automatic
        layoutControl.trackingMode = .selectOne
        for (index, layout) in ChromeLayoutPreference.allCases.enumerated() {
            layoutControl.setLabel(layout.title, forSegment: index)
            layoutControl.setWidth(140, forSegment: index)
        }
        layoutControl.target = self
        layoutControl.action = #selector(layoutChanged)

        layoutDetail.font = .preferredFont(forTextStyle: .caption1)
        layoutDetail.textColor = .secondaryLabelColor
        layoutDetail.lineBreakMode = .byWordWrapping
        layoutDetail.maximumNumberOfLines = 2

        // The one thing `⌘S` no longer does, said out loud: a user who used to
        // swap layouts with the keystroke needs to be told where it went.
        let note = NSTextField(labelWithString: String(
            localized: "⌘S hides and shows the sidebar. It no longer changes the layout."
        ))
        note.font = .preferredFont(forTextStyle: .caption1)
        note.textColor = .tertiaryLabelColor

        let stack = NSStackView(views: [heading, layoutControl, layoutDetail, note])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.setHuggingPriority(.defaultHigh, for: .vertical)

        let root = NSView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor)
        ])
        return root
    }

    // MARK: - State

    private func readSettings() {
        let current = Settings.chromeLayout
        let index = ChromeLayoutPreference.allCases.firstIndex(of: current) ?? 0
        layoutControl.selectedSegment = index
        layoutDetail.stringValue = current.detail
    }

    @objc private func layoutChanged() {
        let cases = ChromeLayoutPreference.allCases
        guard cases.indices.contains(layoutControl.selectedSegment) else { return }
        Settings.chromeLayout = cases[layoutControl.selectedSegment]
        layoutDetail.stringValue = cases[layoutControl.selectedSegment].detail
    }
}
