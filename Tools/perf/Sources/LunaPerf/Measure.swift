//
//  Measure.swift
//  luna-perf
//
//  The measuring instruments. Everything reads the system's numbers — `ps`,
//  `footprint`, the window server — rather than anything Luna reports about
//  itself, because a browser's real cost is spread across processes the app
//  does not own: WebKit's WebContent, Networking and GPU services are children
//  of launchd (`ppid == 1`).
//
//  That is also why helper processes are found by diffing the set of live
//  WebKit XPC services before and after the run: there is no public way to ask
//  "which WebContent process belongs to this app". `responsibility_get_pid_…`
//  would answer it and is banned (D10), and `launchctl procinfo` needs root.
//

import CoreGraphics
import Foundation

struct ProcMemory: Sendable {
    var pid: Int32
    var name: String
    /// Resident set size. The unit §19.1's budget is stated in.
    var rssKB: Int
    /// `phys_footprint` — what the kernel charges the process, and what Activity
    /// Monitor calls "Memory". Excludes the shared dyld cache that RSS counts
    /// once per process, so for 10 WebKit processes it is the fairer number.
    var footprintKB: Int
}

enum Measure {

    @discardableResult
    static func shell(_ launchPath: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// pid → executable path for every live process.
    static func processTable() -> [Int32: String] {
        var table: [Int32: String] = [:]
        for line in shell("/bin/ps", ["-axo", "pid=,comm="]).split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let space = trimmed.firstIndex(of: " "),
                  let pid = Int32(trimmed[trimmed.startIndex..<space]) else { continue }
            table[pid] = String(trimmed[space...].trimmingCharacters(in: .whitespaces))
        }
        return table
    }

    /// Every live WebKit XPC service on the machine. Matched on the framework
    /// path, so an Electron app's renderers never land in the total.
    static func webKitHelpers() -> Set<Int32> {
        Set(processTable().filter { $0.value.contains("WebKit.framework") }.keys)
    }

    static func memory(of pids: [Int32]) -> [ProcMemory] {
        guard !pids.isEmpty else { return [] }
        let table = processTable()
        var rss: [Int32: Int] = [:]
        let list = pids.map(String.init).joined(separator: ",")
        for line in shell("/bin/ps", ["-o", "pid=,rss=", "-p", list]).split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count == 2, let pid = Int32(parts[0]), let kb = Int(parts[1]) else { continue }
            rss[pid] = kb
        }
        return pids.compactMap { pid in
            guard let kb = rss[pid] else { return nil }  // died between samples
            return ProcMemory(
                pid: pid,
                name: (table[pid] as NSString?)?.lastPathComponent ?? "?",
                rssKB: kb,
                footprintKB: footprintKB(pid)
            )
        }
    }

    /// `footprint(1)` prints `Footprint: 1.2 GB` / `... 900 MB` / `... 1632 KB`.
    private static func footprintKB(_ pid: Int32) -> Int {
        let output = shell("/usr/bin/footprint", ["-p", "\(pid)"])
        guard let range = output.range(of: #"Footprint:\s+([0-9.,]+)\s*(KB|MB|GB)"#, options: .regularExpression)
        else { return 0 }
        let fields = output[range].split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count >= 3,
              let value = Double(fields[1].replacingOccurrences(of: ",", with: ""))
        else { return 0 }
        switch fields[2] {
        case "GB": return Int(value * 1024 * 1024)
        case "MB": return Int(value * 1024)
        default: return Int(value)
        }
    }

    /// Milliseconds from now until `pid` owns an on-screen window big enough to
    /// be the browser window, or nil on timeout.
    ///
    /// This is the honest external definition of "launched": the first frame the
    /// user can see. It is a lower bound on §19.1's "to interactive" —
    /// Luna shows its window before it touches SQLite on purpose (`AppDelegate`),
    /// so the session restore lands after this point. ``waitForReady(at:since:timeout:)``
    /// is the other end of that gap.
    static func waitForWindow(pid: Int32, since start: DispatchTime, timeout: TimeInterval) -> Double? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if hasWindow(pid: pid) {
                return Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            }
            // 1 ms: the poll cost is the measurement error, and it is well under
            // a frame at 120 Hz.
            usleep(1000)
        }
        return nil
    }

    /// Milliseconds from now until Luna writes its launch tape to `path`, or nil
    /// on timeout.
    ///
    /// This is "to interactive", and it is the app's own answer. `App/LaunchTrace`
    /// writes the file once the window has the restored session in it; the elapsed
    /// times inside it are measured from `exec`, so they include dyld and the Swift
    /// runtime, which a stopwatch started in `main()` cannot see. The file is written
    /// atomically, so polling can never catch it half-built.
    static func waitForReady(at path: String, since start: DispatchTime, timeout: TimeInterval) -> Double? {
        waitForLaunch(pid: nil, readyPath: path, since: start, timeout: timeout).ready
    }

    /// Both ends of a launch in one poll: the first on-screen window, and the
    /// moment Luna says it is interactive. Returns as soon as the ready file
    /// lands, whether or not a window was ever reported.
    ///
    /// The window half is allowed to come back nil, and often does. It asks
    /// the window server for windows that are on screen, and a background app
    /// spawned by a harness may have none: under Stage Manager a window that is
    /// not the frontmost app's is off to the side, and this poll cannot see it.
    /// Measured — Luna wrote its tape at 316 ms in a run where the same window
    /// was still unreported 20 s later. The ready file is the number to trust;
    /// the window time is the one to compare it against when it is there.
    static func waitForLaunch(
        pid: Int32?,
        readyPath: String,
        since start: DispatchTime,
        timeout: TimeInterval
    ) -> (window: Double?, ready: Double?) {
        let deadline = Date().addingTimeInterval(timeout)
        var window: Double?
        while Date() < deadline {
            // The window server call is the expensive half of this loop, so it
            // stops being made once it has answered.
            if window == nil, let pid, hasWindow(pid: pid) { window = elapsed(since: start) }
            if FileManager.default.fileExists(atPath: readyPath) { return (window, elapsed(since: start)) }
            usleep(1000)
        }
        return (window, nil)
    }

    private static func elapsed(since start: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    }

    /// The milestone lines Luna wrote, `name<TAB>ms` each.
    static func readTape(at path: String) -> [(name: String, ms: Double)] {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t")
            guard parts.count == 2, let ms = Double(parts[1]) else { return nil }
            return (String(parts[0]), ms)
        }
    }

    private static func hasWindow(pid: Int32) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        return windows.contains { window in
            guard let owner = window[kCGWindowOwnerPID as String] as? Int32, owner == pid,
                  let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let height = bounds["Height"] as? Double
            else { return false }
            return height > 200
        }
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    static func mb(_ kilobytes: Int) -> String {
        String(format: "%.0f MB", Double(kilobytes) / 1024)
    }
}
