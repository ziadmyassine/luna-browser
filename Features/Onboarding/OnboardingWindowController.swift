//
//  OnboardingWindowController.swift
//  Luna — §30.17
//
//  The window first run happens in, and the import it starts.
//
//  A window rather than a sheet over the browser: the browser window is
//  restoring a session behind it, and a sheet would pin the user to a form
//  before they have seen the thing the form is about. Closing it is an answer
//  — "not now" — and it never asks again.
//

import AppKit
import BrowserKit

@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {

    private let view: OnboardingView
    private let importer: BrowserImporter
    private let sources: [DetectedSource]
    private var onClose: (() -> Void)?
    /// The import has run — whatever it wrote is in the store and the live
    /// session has not heard about it.
    var onImportFinished: (() -> Void)?

    init(store: BrowserStore, sources: [DetectedSource]) {
        // Filtered once, here, so the screen and the import agree about what
        // this Mac has on it.
        let installed = sources.filter { OnboardingImportList.isInstalled($0.source) }
        self.sources = installed
        importer = BrowserImporter(store: store)
        view = OnboardingView(sources: installed)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: OnboardingMetrics.size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.contentView = view
        window.center()
        super.init(window: window)
        window.delegate = self
        view.onFinished = { [weak self] in self?.finish() }
        view.onImportRequested = { [weak self] chosen in self?.runImport(chosen) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// Whether this Mac has anything to show. A first run with no other
    /// browser installed still gets the welcome; it just has nothing to offer
    /// on the middle page, which the copy handles.
    static func shouldPresent() -> Bool { !OnboardingState.hasRun }

    func present(over host: NSWindow?, onClose: @escaping () -> Void) {
        self.onClose = onClose
        if let host { window?.setFrameOrigin(centred(over: host)) }
        // It arrives rather than appears: the browser window is already up
        // behind it, and a second window cutting in at full strength on the
        // same frame reads as a dialog the app has thrown.
        window?.alphaValue = 0
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        Tokens.Motion.animate(Tokens.Motion.popoverIn) { context in
            context.allowsImplicitAnimation = true
            window?.animator().alphaValue = 1
        }
    }

    private func centred(over host: NSWindow) -> NSPoint {
        let frame = host.frame
        let size = OnboardingMetrics.size
        return NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2)
    }

    private func finish() {
        OnboardingState.hasRun = true
        close()
    }

    func windowWillClose(_ notification: Notification) {
        OnboardingState.hasRun = true
        onClose?()
        onClose = nil
    }

    // MARK: - The import

    /// One source at a time, in the order they were listed, with the row
    /// carrying its own progress. A failure marks its row and the rest still
    /// run — §23.2's rule, and the reason `ImportSummary` counts failures
    /// rather than throwing.
    private func runImport(_ chosen: Set<ImportSource>) {
        let requests = sources
            .filter { chosen.contains($0.source) }
            .compactMap { detected -> ImportRequest? in
                guard let profile = detected.profiles.first(where: \.isLastUsed) ?? detected.profiles.first else {
                    return nil
                }
                return ImportRequest(source: detected.source, profile: profile)
            }
        Task { [weak self] in
            guard let self else { return }
            for request in requests {
                view.mark(request.source, as: .running)
                do {
                    let summary = try await importer.run(request)
                    view.mark(request.source, as: summary.failed > 0 ? .failed : .done)
                } catch {
                    view.mark(request.source, as: .failed)
                }
            }
            view.importFinished()
            onImportFinished?()
        }
    }
}

/// Whether first run has happened. Its own type rather than a `Settings`
/// member: nothing about it is a preference, and it is read once.
enum OnboardingState {

    private static let key = "luna.onboarding.hasRun"

    static var hasRun: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
