//
//  AppDelegate+Onboarding.swift
//  Luna — §30.17
//
//  First run: detect what else is on this Mac, put the window up, and let the
//  live session pick up whatever the import wrote. Help ▸ Welcome to Luna puts
//  the same window up again whenever the user asks.
//

import AppKit
import BrowserKit

extension AppDelegate {

    func presentOnboardingIfNeeded(store: BrowserStore, session: BrowserSession) {
        guard OnboardingWindowController.shouldPresent() else { return }
        presentOnboarding(store: store, session: session)
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

    /// - Parameter detect: what is installed on this Mac. A seam so a test
    ///   does not walk the real `~/Library`.
    func presentOnboarding(
        store: BrowserStore,
        session: BrowserSession,
        detect: @escaping @Sendable () -> [DetectedSource] = { ImportSourceDetector.detect() }
    ) {
        Task { [weak self, weak session] in
            // Detection walks `~/Library/Application Support` for eleven
            // browsers, so it is off the main thread even once.
            let sources = await Task.detached(priority: .userInitiated) { detect() }.value
            guard let self, let session, onboarding == nil else { return }
            let onboarding = OnboardingWindowController(store: store, sources: sources)
            self.onboarding = onboarding
            onboarding.onImportFinished = { [weak session] in
                // The importer writes straight to the store; the session is
                // already restored and has never heard of what landed.
                Task { try? await session?.adoptSpacesWrittenElsewhere() }
            }
            onboarding.present(over: browserWindow?.window) { [weak self] in self?.onboarding = nil }
        }
    }
}
