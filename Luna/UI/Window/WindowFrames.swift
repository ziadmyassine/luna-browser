//
//  WindowFrames.swift
//  Luna
//
//  §22.6: where each browser window stood, per screen setup. A laptop on its
//  own and the same laptop at a desk with a second display are two layouts,
//  and the user arranges each once.
//
//  A window is remembered by its slot, the lowest number no other open window
//  holds: the first window is 0, a second opened beside it is 1. AppKit's
//  autosave name could not do this — it is one frame per name, so several
//  windows sharing it opened on top of each other and the last to close
//  overwrote the rest.
//

import AppKit

/// The two pure halves: which setup this is, and where a frame may stand on it.
enum WindowPlacement {

    /// One display: where it is in the arrangement, and the part of it a
    /// window may use (the menu bar and the Dock taken off).
    struct Screen: Equatable {
        var frame: NSRect
        var visibleFrame: NSRect
    }

    /// Names a screen setup by its displays' frames, in a fixed order.
    /// Frames rather than display IDs: the same monitor can come back under a
    /// new ID, and what decides where a window can go is the arrangement.
    /// The visible frames are left out, so the Dock appearing is not a new setup.
    static func setupKey(_ screens: [Screen]) -> String {
        screens.map(\.frame)
            .sorted { ($0.minX, $0.minY) < ($1.minX, $1.minY) }
            .map { frame in
                [frame.minX, frame.minY, frame.width, frame.height]
                    .map { String(Int($0.rounded())) }
                    .joined(separator: ",")
            }
            .joined(separator: ";")
    }

    /// `frame`, moved and if need be shrunk to stand wholly inside one screen's
    /// visible frame: the one it overlaps most, or the first (the one with the
    /// menu bar) when it overlaps none — its display is gone. Nil with no screens.
    static func fit(_ frame: NSRect, onto screens: [Screen]) -> NSRect? {
        guard let main = screens.first else { return nil }
        let overlap = { (screen: Screen) -> CGFloat in
            let shared = screen.visibleFrame.intersection(frame)
            return shared.isNull ? 0 : shared.width * shared.height
        }
        var fitted = frame
        let room: NSRect
        if let best = screens.max(by: { overlap($0) < overlap($1) }), overlap(best) > 0 {
            room = best.visibleFrame
        } else {
            // Its display is gone: the same size, centred on the main screen.
            room = main.visibleFrame
            fitted.origin = NSPoint(x: room.midX - frame.width / 2, y: room.midY - frame.height / 2)
        }
        fitted.size.width = min(frame.width, room.width)
        fitted.size.height = min(frame.height, room.height)
        fitted.origin.x = min(max(fitted.minX, room.minX), room.maxX - fitted.width)
        fitted.origin.y = min(max(fitted.minY, room.minY), room.maxY - fitted.height)
        // Whole points, rounded rather than `integral`, which grows a frame
        // centred on a half point by one.
        fitted.origin = NSPoint(x: fitted.minX.rounded(), y: fitted.minY.rounded())
        return fitted
    }
}

/// Remembers each browser window's frame for the screen setup it was arranged
/// on, and puts it back when that setup is in use again — at launch, at `⌘N`,
/// or when a display is plugged back in.
@MainActor
final class WindowFrameMemory {

    /// The app's. A test host writes to a throwaway domain: it shares the
    /// real app's defaults, and its windows would otherwise move the user's.
    static let shared = WindowFrameMemory(defaults: AppDelegate.isRunningTests ? scratch : .standard)

    /// Emptied at each test run, so no run opens where the last one left off.
    private static var scratch: UserDefaults {
        let name = "luna.tests.WindowFrames"
        UserDefaults.standard.removePersistentDomain(forName: name)
        return UserDefaults(suiteName: name) ?? .standard
    }

    /// [setup key: [slot: frame string]].
    static let framesKey = "LunaWindowFrames"
    /// Setup keys, most recently used first, so the list can be trimmed.
    static let setupsKey = "LunaWindowSetups"
    /// What `windowFrameAutosaveName` used to save, read once so the first
    /// launch after the change opens where the window last was.
    static let legacyKey = "NSWindow Frame LunaBrowserWindow"
    /// A Mac sees a handful of setups; one that has not come back in the last
    /// ten is a meeting-room projector, not a desk.
    private static let setupLimit = 10

    private struct Entry {
        weak var window: NSWindow?
        let slot: Int
        var tokens: [any NSObjectProtocol]
    }

    private let defaults: UserDefaults
    private let screens: () -> [WindowPlacement.Screen]
    private var entries: [ObjectIdentifier: Entry] = [:]
    /// The setup frames were last placed for. A move that arrives while the
    /// screens already say otherwise is AppKit rehousing a window from a
    /// display that has gone, and is not saved over the user's own frame for
    /// the new setup.
    private var knownSetup: String
    private var screenWatch: (any NSObjectProtocol)?

    init(
        defaults: UserDefaults,
        screens: @escaping () -> [WindowPlacement.Screen] = {
            NSScreen.screens.map { WindowPlacement.Screen(frame: $0.frame, visibleFrame: $0.visibleFrame) }
        }
    ) {
        self.defaults = defaults
        self.screens = screens
        knownSetup = WindowPlacement.setupKey(screens())
        screenWatch = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
    }

    // MARK: - Windows coming and going

    /// Takes `window` into the memory and puts it where its slot last stood on
    /// this setup. False when there is nothing to put back, and the caller
    /// places it some other way.
    @discardableResult
    func register(_ window: NSWindow) -> Bool {
        let id = ObjectIdentifier(window)
        if entries[id] != nil { return restore(window) }
        let taken = Set(entries.values.filter { $0.window != nil }.map(\.slot))
        let slot = (0...).first { !taken.contains($0) } ?? 0
        let center = NotificationCenter.default
        let save: @Sendable (Notification) -> Void = { [weak self, weak window] _ in
            MainActor.assumeIsolated {
                guard let self, let window else { return }
                self.save(window)
            }
        }
        var tokens = [NSWindow.didMoveNotification, NSWindow.didResizeNotification].map {
            center.addObserver(forName: $0, object: window, queue: .main, using: save)
        }
        let close: @Sendable (Notification) -> Void = { [weak self, weak window] _ in
            MainActor.assumeIsolated {
                guard let self, let window else { return }
                self.save(window)
                self.forget(window)
            }
        }
        tokens.append(center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main, using: close))
        entries[id] = Entry(window: window, slot: slot, tokens: tokens)
        return restore(window)
    }

    /// Puts `window` back where its slot stood on the current setup.
    @discardableResult
    func restore(_ window: NSWindow) -> Bool {
        guard let slot = entries[ObjectIdentifier(window)]?.slot,
              let stored = frame(slot: slot, setup: knownSetup) ?? legacyFrame(slot: slot),
              let fitted = WindowPlacement.fit(stored, onto: screens()) else { return false }
        window.setFrame(fitted, display: true)
        return true
    }

    func slot(of window: NSWindow) -> Int? { entries[ObjectIdentifier(window)]?.slot }

    private func forget(_ window: NSWindow) {
        guard let entry = entries.removeValue(forKey: ObjectIdentifier(window)) else { return }
        for token in entry.tokens { NotificationCenter.default.removeObserver(token) }
    }

    // MARK: - Saving

    private func save(_ window: NSWindow) {
        guard let slot = slot(of: window), !window.styleMask.contains(.fullScreen),
              WindowPlacement.setupKey(screens()) == knownSetup else { return }
        var all = defaults.dictionary(forKey: Self.framesKey) as? [String: [String: String]] ?? [:]
        all[knownSetup, default: [:]][String(slot)] = NSStringFromRect(window.frame)
        var setups = defaults.stringArray(forKey: Self.setupsKey) ?? []
        setups.removeAll { $0 == knownSetup }
        setups.insert(knownSetup, at: 0)
        for old in setups.dropFirst(Self.setupLimit) { all[old] = nil }
        defaults.set(all, forKey: Self.framesKey)
        defaults.set(Array(setups.prefix(Self.setupLimit)), forKey: Self.setupsKey)
    }

    func frame(slot: Int, setup: String) -> NSRect? {
        let all = defaults.dictionary(forKey: Self.framesKey) as? [String: [String: String]]
        guard let string = all?[setup]?[String(slot)] else { return nil }
        let rect = NSRectFromString(string)
        return rect.isEmpty ? nil : rect
    }

    /// The first window's frame from before frames were kept per setup: the
    /// first four numbers of AppKit's string are the window's own frame.
    private func legacyFrame(slot: Int) -> NSRect? {
        guard slot == 0, defaults.dictionary(forKey: Self.framesKey) == nil,
              let numbers = defaults.string(forKey: Self.legacyKey)?.split(separator: " ").compactMap({ Double($0) }),
              numbers.count >= 4 else { return nil }
        let rect = NSRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
        return rect.isEmpty ? nil : rect
    }

    // MARK: - A display coming or going

    /// Every window to its frame for the setup now in use, or, for a slot
    /// never arranged on it, to wherever AppKit left it, kept on screen.
    func screensChanged() {
        knownSetup = WindowPlacement.setupKey(screens())
        for entry in entries.values {
            guard let window = entry.window, !window.styleMask.contains(.fullScreen) else { continue }
            let stored = frame(slot: entry.slot, setup: knownSetup) ?? window.frame
            if let fitted = WindowPlacement.fit(stored, onto: screens()), fitted != window.frame {
                window.setFrame(fitted, display: true)
            }
            // Saved even when it did not move: where AppKit left it is now
            // this setup's frame for the slot.
            save(window)
        }
    }
}
