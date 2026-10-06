//
//  AppDelegate+Onboarding.swift
//  Luna — §30.17
//
//  First run: detect what else is on this Mac and put the window up, before
//  the browser on a fresh install. Help ▸ Welcome to Luna puts the same window
//  up again, over the browser, whenever the user asks.
//

import AppKit
import BrowserKit

extension AppDelegate {

    /// A fresh install's launch: the welcome window and nothing else, and the
    /// browser once it is gone — by its last page or its close button alike.
    ///
    /// First, because what it settles is what the browser opens with: the
    /// theme its first frame is drawn in, and the Spaces an import writes,
    /// which a session restored before the import never shows. A window behind
    /// it was a page loading under a question about it.
    ///
    /// - Parameter openBrowser: the rest of the launch, run once. Synchronously
    ///   inside the close, so there is a window up when AppKit asks whether the
    ///   last one just went (`applicationShouldTerminateAfterLastWindowClosed`).
    func presentFirstRun(
        opening: Task<BrowserStore, any Error>,
        detect: @escaping @Sendable () -> [DetectedSource] = { ImportSourceDetector.detect() },
        then openBrowser: @escaping () -> Void
    ) {
        Task { [weak self] in
            // A store that will not open has nothing to import into, and the
            // browser's launch is what says so (`presentStoreFailure`).
            guard let self, let store = try? await opening.value else {
                openBrowser()
                return
            }
            presentOnboarding(store: store, session: nil, onClose: openBrowser, detect: detect)
        }
    }

    /// Help ▸ Welcome to Luna: first run again, from the first page. The one
    /// already up is brought forward rather than doubled.
    @objc func showWelcome(_ sender: Any?) {
        if let window = onboarding?.window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        guard let store, let session else { return }
        presentOnboarding(store: store, session: session)
    }

    /// - Parameters:
    ///   - session: the live session an import has to be announced to, or nil
    ///     at first run, where the session is restored after the import.
    ///   - detect: what is installed on this Mac. A seam so a test does not
    ///     walk the real `~/Library`.
    func presentOnboarding(
        store: BrowserStore,
        session: BrowserSession?,
        onClose: @escaping () -> Void = {},
        detect: @escaping @Sendable () -> [DetectedSource] = { ImportSourceDetector.detect() }
    ) {
        Task { [weak self, weak session] in
            // Detection walks `~/Library/Application Support` for eleven
            // browsers, so it is off the main thread even once.
            let sources = await Task.detached(priority: .userInitiated) { detect() }.value
            guard let self, onboarding == nil else { return }
            let onboarding = OnboardingWindowController(store: store, sources: sources)
            self.onboarding = onboarding
            onboarding.onImportFinished = { [weak session] in
                // The importer writes straight to the store; a session that is
                // already restored has never heard of what landed.
                Task { try? await session?.adoptSpacesWrittenElsewhere() }
            }
            onboarding.present(over: browserWindow?.window) { [weak self] in
                self?.onboarding = nil
                onClose()
            }
        }
    }
}
