//
//  LaunchTrace.swift
//  Luna
//
//  §19.1's launch budget, measured from inside the process — the half
//  `Tools/perf` cannot reach.
//
//  The harness times `posix_spawn` → first on-screen window, which
//  `docs/PERF.md` is careful to call a **lower bound**: `AppDelegate` shows the
//  window before it touches SQLite on purpose, so the session restore, the
//  sidebar and the first page all land after the number stops. "To interactive"
//  is the budget §19.1 actually states, and nothing was measuring it.
//
//  This is the missing end of the tape. `LUNA_PERF_READY` names a file; the
//  milestones are written to it at the moment the window has content in it, and
//  the harness polls for the file exactly as it polls for the window. Two
//  processes, one clock each, no clock shared between them — the elapsed time
//  is computed here from the kernel's own record of when this process was
//  `exec`ed, so it counts dyld and the Swift runtime as well, which a stopwatch
//  started in `main()` would miss.
//
//  **Off costs one environment lookup, once.** With `LUNA_PERF_READY` unset
//  every `mark` is a load and a branch, and nothing is stored.
//

import Darwin
import Foundation

enum LaunchTrace {

    /// Set by `Tools/perf`. Names the file the milestones are written to — its
    /// appearance on disk is what the harness is waiting for.
    static let readyPathKey = "LUNA_PERF_READY"

    private nonisolated(unsafe) static var milestones: [(name: String, ms: Double)] = []

    /// Tracing is off unless the harness asked for it, and asking is the only
    /// way to turn it on: a launch measurement that a stray default could
    /// switch on is a launch measurement nobody can trust.
    static let isEnabled = ProcessInfo.processInfo.environment[readyPathKey] != nil

    /// Milliseconds since this process was `exec`ed, from `kinfo_proc` rather
    /// than from a stopwatch we start ourselves.
    ///
    /// **Everything before `main()` is on the budget too.** dyld resolving
    /// WebKit and AppKit, the Swift runtime standing up, the ObjC class
    /// registry — a clock started in `applicationWillFinishLaunching` cannot
    /// see any of it, and on a cold cache that half is not small.
    static var sinceExec: Double {
        guard let start = execDate else { return 0 }
        return Date().timeIntervalSince(start) * 1000
    }

    private static let execDate: Date? = {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0 else { return nil }
        let started = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: Double(started.tv_sec) + Double(started.tv_usec) / 1_000_000)
    }()

    /// Records that launch reached `milestone`. Cheap enough to call from the
    /// launch path, because when tracing is off it does not run.
    static func mark(_ milestone: String) {
        guard isEnabled else { return }
        milestones.append((milestone, sinceExec))
    }

    /// The window has content in it. Writes the tape and stops.
    ///
    /// The file is written whole, with `.atomic`, so the harness can never poll
    /// its way into a half-written one: the path either does not exist or holds
    /// every milestone.
    static func ready() {
        guard isEnabled,
              let path = ProcessInfo.processInfo.environment[readyPathKey]
        else { return }
        mark("ready")
        let tape = milestones.map { String(format: "%@\t%.1f", $0.name, $0.ms) }.joined(separator: "\n")
        try? Data((tape + "\n").utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
        FileHandle.standardError.write(Data(("LAUNCH TRACE\n" + tape + "\n").utf8))
    }
}
