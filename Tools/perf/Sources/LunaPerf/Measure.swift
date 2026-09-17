//
//  Measure.swift
//  luna-perf
//
//  The measuring instruments. Everything here reads the *system's* numbers —
//  `ps`, `footprint`, the window server — rather than anything Luna reports
//  about itself, because a browser's real cost is spread across processes the
//  app does not own: WebKit's WebContent, Networking and GPU services are
//  children of launchd (`ppid == 1`), not of us.
//
//  That is also why helper processes are found by **diffing** the set of live
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
    /// user can see. It is a **lower bound** on §19.1's "to interactive" —
    /// Luna shows its window before it touches SQLite on purpose (`AppDelegate`),
    /// so the session restore lands after this point. `LUNA_PERF_READY` (below)
    /// is what would close that gap; nothing writes it yet.
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
