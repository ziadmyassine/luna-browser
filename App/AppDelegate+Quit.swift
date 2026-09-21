//
//  AppDelegate+Quit.swift
//  Luna
//
//  §3.1's guard on ⌘Q: what the sheet says, and the two-pass dance AppKit
//  makes you do to put one up at all.
//
//  `applicationShouldTerminate` cannot wait for an answer: it is synchronous
//  and has three replies. `.terminateLater` looks right and is not — it parks
//  the app in a nested modal run loop, where the sheet's animation and tracking
//  areas run inside a loop AppKit is holding open for a different purpose, and
//  nothing else in Luna may happen until it is answered, including the
//  `flush()` this file's neighbour still owes the store. So the first pass
//  answers `.cancel`, puts the sheet up and returns; the answer calls
//  `NSApp.terminate` again, and the second pass sees `isQuitConfirmed` and goes
//  through to the flush.
//
//  The one thing that must not happen is asking twice, which is why the flag
//  is set before the second `terminate` rather than after it.
//

import AppKit

extension AppDelegate {

    /// Whether the sheet should go up now — and false once it has been
    /// answered with "quit", so the second pass does not ask again.
    ///
    /// A quit the user did not start also goes straight through: logging out
    /// or shutting down gives the app a few seconds and no keyboard, and a
    /// modal nobody can answer is a machine that will not shut down.
    func wantsQuitConfirmation(_ sender: NSApplication) -> Bool {
        guard !isQuitConfirmed, GeneralSection.confirmQuit else { return false }
        guard session != nil, browserWindow?.window != nil else { return false }
        return !isQuitFromLogOut
    }

    /// Puts the sheet up over the browser window and wires its answer back to
    /// `NSApp`.
    func presentQuitSheet() {
        guard let window = browserWindow?.window, let host = window.contentView else { return }
        // Already up — ⌘Q pressed twice is one question, not two sheets.
        guard host.subviews.compactMap({ $0 as? QuitSheetView }).isEmpty else { return }

        let previousResponder = window.firstResponder
        let sheet = QuitSheetView(caption: quitCaption)
        sheet.frame = host.bounds
        host.addSubview(sheet)
        window.makeFirstResponder(sheet)
        sheet.reveal()

        sheet.onAnswer = { [weak self, weak window] answer in
            sheet.dismiss { MainActor.assumeIsolated { sheet.removeFromSuperview() } }
            guard let self else { return }
            switch answer {
            case .stay:
                // The keyboard goes back where it was, or the window comes out
                // of this with nothing focused and the next keystroke lost.
                window?.makeFirstResponder(previousResponder)
            case .quitAndStopAsking:
                UserDefaults.standard.set(false, forKey: GeneralSection.confirmQuitKey)
                confirmAndTerminate()
            case .quit:
                confirmAndTerminate()
            }
        }
    }

    private func confirmAndTerminate() {
        isQuitConfirmed = true
        NSApp.terminate(nil)
    }

    /// What is actually at stake, which is the whole reason this is a sentence
    /// and not "Are you sure?".
    ///
    /// Tabs are not at stake and the sheet says so. Luna restores the
    /// session, so the honest line is the count plus the promise — and a
    /// warning that overstates what it is guarding is one the user learns to
    /// click through. A download is at stake: it is the one thing in the app
    /// that quitting destroys rather than parks, so when one is running it is
    /// the sentence, and the tab count is not.
    private var quitCaption: String {
        if let running = downloadsInFlight, running > 0 {
            return running == 1
                ? String(localized: "A download is still going. Quitting stops it.")
                : String(localized: "\(running) downloads are still going. Quitting stops them.")
        }
        guard let session else { return String(localized: "Luna will put everything back next time.") }
        let tabs = session.spaces.reduce(0) { $0 + session.list[$1.id].count }
        let spaces = session.spaces.count
        let open = spaces == 1
            ? String(localized: "\(tabs) tabs open")
            : String(localized: "\(tabs) tabs open across \(spaces) Spaces")
        return String(localized: "\(open). Luna will put them all back next time.")
    }
}
