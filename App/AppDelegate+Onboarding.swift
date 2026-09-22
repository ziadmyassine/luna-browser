//
//  AppDelegate+Onboarding.swift
//  Luna — §30.17
//
//  First run: detect what else is on this Mac, put the window up, and let the
//  live session pick up whatever the import wrote.
//

import AppKit
import BrowserKit

extension AppDelegate {

    func presentOnboardingIfNeeded(store: BrowserStore, session: BrowserSession) {
        guard OnboardingWindowController.shouldPresent() else { return }
        Task { [weak self] in
            // Detection walks `~/Library/Application Support` for eleven
            // browsers, so it is off the main thread even once.
            let sources = await Task.detached(priority: .userInitiated) {
                ImportSourceDetector.detect()
            }.value
            guard let self else { return }
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
