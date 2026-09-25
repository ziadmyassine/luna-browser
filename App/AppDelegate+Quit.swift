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

/// Whether ⌘Q asks first, as a rule rather than as a state of the app.
///
/// Every term is a reason not to ask, and the one that is easy to get wrong is
/// the last: the sheet is only an answer if there is somewhere to put it. The
/// `.cancel` this decides is a quit that has already been asked for, so a false
/// yes is not a question — it is an app that will not quit.
enum QuitConfirmation {

    /// - Parameters:
    ///   - setting: §23.1's "Ask before quitting".
    ///   - alreadyConfirmed: the sheet has been answered with "quit", and this
    ///     is the second pass — see the file header.
    ///   - hasSession: there are tabs to lose. Before the session exists there
    ///     is nothing the question protects.
    ///   - hasVisibleWindow: there is a browser window on screen to put the
    ///     sheet on.
    ///   - isLogOut: the quit was not started by the user. Logging out or
    ///     shutting down gives the app a few seconds and no keyboard, and a
    ///     modal nobody can answer is a machine that will not shut down.
    static func isNeeded(
        setting: Bool,
        alreadyConfirmed: Bool,
        hasSession: Bool,
        hasVisibleWindow: Bool,
        isLogOut: Bool
    ) -> Bool {
        guard setting, !alreadyConfirmed, hasSession, hasVisibleWindow else { return false }
        return !isLogOut
    }

    /// Whether the sheet goes on §23.1's Settings window rather than on the
    /// browser window.
    ///
    /// Settings is a child of the browser window it was opened over, so it
    /// always stands in front of that one, centred on it — where the sheet
    /// would also be centred. Put on the browser window, the question came up
    /// behind Settings, half hidden, taking the keyboard from a window that
    /// did not have it. So it goes on Settings whenever Settings is the window
    /// in use or is covering the one that would have held the sheet.
    static func asksOverSettings(settingsIsVisible: Bool, settingsIsKey: Bool, settingsCoversBrowser: Bool) -> Bool {
        settingsIsVisible && (settingsIsKey || settingsCoversBrowser)
    }
}

extension AppDelegate {

    /// Whether the sheet should go up now.
    func wantsQuitConfirmation(_ sender: NSApplication) -> Bool {
        QuitConfirmation.isNeeded(
            setting: GeneralSection.confirmQuit,
            alreadyConfirmed: isQuitConfirmed,
            hasSession: session != nil,
            hasVisibleWindow: quitSheetHost != nil,
            isLogOut: isQuitFromLogOut
        )
    }

    /// The window the sheet goes up on: the browser window, while it is one
    /// the user can see.
    ///
    /// A closed window is still the window controller's window — `NSWindowController`
    /// owns it whether or not it is on screen — so "there is a browser window"
    /// and "there is a browser window to ask in" are different questions.
    /// Asking the first one meant that with the browser window closed and
    /// §23.1's Settings window still open, ⌘Q put the sheet on a window nobody
    /// could see and cancelled the quit that was waiting for it: an app that
    /// would not quit, with nothing on screen to say why. Miniaturised counts
    /// as not visible for the same reason, and a quit with no window to ask in
    /// goes straight through — the tabs it would be protecting were put away
    /// when the window closed.
    ///
    /// Whether to ask is still the browser window's question; where to ask is
    /// `QuitConfirmation.asksOverSettings`.
    var quitSheetHost: NSWindow? {
        guard let window = browserWindow?.window, window.isVisible else { return nil }
        if let settings = settingsWindow?.window, QuitConfirmation.asksOverSettings(
            settingsIsVisible: settings.isVisible && !settings.isMiniaturized,
            settingsIsKey: settings.isKeyWindow,
            settingsCoversBrowser: settings.parent === window
        ) {
            return settings
        }
        return window
    }

    /// Puts the sheet up over `quitSheetHost` and wires its answer back to
    /// `NSApp`.
    func presentQuitSheet() {
        guard let window = quitSheetHost, let host = window.contentView else { return }
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
