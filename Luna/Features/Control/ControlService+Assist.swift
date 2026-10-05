//
//  ControlService+Assist.swift
//  Luna
//
//  The calls that reach past the page (`ControlTools+Assist`): the user's
//  history and folders, a PDF's text, and an event for the calendar.
//
//  History is Astro's alone: an app the user connected sees the browser it
//  is driving, not everywhere the user has been.
//

import AppKit
import BrowserKit
import LunaControl
import PDFKit
import WebKit

extension ControlService {

    func assist(_ command: ControlCommand, tab id: UUID?, for client: ControlClient, in session: BrowserSession) async throws
        -> ControlResult {
        switch command {
        case .labelTab, .showDocument:
            return try await present(command, tab: id, for: client, in: session)
        case let .searchHistory(query, limit):
            guard Self.astroTasks[client.session] != nil else {
                return .error("Only Luna's own agent may read the user's history.")
            }
            return .text(Self.historyText(await session.browsingHistory(matching: query, limit: limit), query: query))
        case .listFolders:
            return .text(foldersText(in: session))
        case let .readPDF(url):
            let page = id.flatMap { session.controller(for: $0)?.webView?.url ?? session.tab($0)?.url }
            return try await pdfText(url ?? page, in: session)
        case let .addToCalendar(title, start, end, allDay, notes):
            return try Self.addToCalendar(title: title, start: start, end: end, allDay: allDay, notes: notes)
        default:
            return .error("Luna cannot do that here.")
        }
    }

    static func historyText(_ hits: [HistoryHit], query: String) -> String {
        guard !hits.isEmpty else {
            return query.isEmpty ? "The history is empty." : "Nothing in the history matches “\(query)”."
        }
        return hits.map { hit in
            let when = hit.lastVisit.map { " (\($0.formatted(date: .abbreviated, time: .omitted)))" } ?? ""
            return "- \(hit.title.isEmpty ? hit.url.host() ?? "" : hit.title) — \(hit.url.absoluteString)\(when)"
        }.joined(separator: "\n")
    }

    /// What `tabs_list` says of a tab's folder: the agent's own, or the
    /// user's by its name — the name is what says what the tabs are for.
    func folderNote(for tab: Tab, yours: UUID?, in session: BrowserSession) -> String {
        guard let group = tab.groupID else { return "" }
        if group == yours { return " (yours)" }
        return session.group(group).map { " (in the user's folder “\($0.name)”)" } ?? ""
    }

    /// Every folder in every Space, with its tabs and their ids.
    func foldersText(in session: BrowserSession) -> String {
        var lines: [String] = []
        for space in session.spaces {
            let groups = session.list.groups(inSpace: space.id)
            guard !groups.isEmpty else { continue }
            lines.append("Space “\(space.name)”:")
            for group in groups {
                let tabs = session.members(ofGroup: group.id).filter { $0.archivedAt == nil }
                lines.append("  Folder “\(group.name)” — \(tabs.count) tab\(tabs.count == 1 ? "" : "s")")
                for tab in tabs {
                    lines.append("    [\(number(tab.id))] \(tab.customTitle ?? tab.title) — \(tab.url.absoluteString)")
                }
            }
        }
        return lines.isEmpty ? "The user has no folders." : lines.joined(separator: "\n")
    }

    // MARK: - PDFs

    /// A PDF's text. Fetched with the user's cookies for its site, so one
    /// behind a sign-in reads as it does in their tab; a file only from
    /// Downloads, so an agent cannot read the rest of the disk this way.
    private func pdfText(_ url: URL?, in session: BrowserSession) async throws -> ControlResult {
        guard let url else { return .error("Give the PDF's url, or open it in a tab first.") }
        let data: Data
        if url.isFileURL {
            let downloads = URL.downloadsDirectory.standardizedFileURL.path(percentEncoded: false)
            guard url.standardizedFileURL.path(percentEncoded: false).hasPrefix(downloads) else {
                return .error("Only files in Downloads can be read.")
            }
            data = try Data(contentsOf: url)
        } else {
            var request = URLRequest(url: url)
            let store = session.activeController?.webView?.configuration.websiteDataStore ?? .default()
            let host = url.host() ?? ""
            let cookies = await store.httpCookieStore.allCookies().filter { cookie in
                host.hasSuffix(cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
            }
            for (field, value) in HTTPCookie.requestHeaderFields(with: cookies) { request.setValue(value, forHTTPHeaderField: field) }
            (data, _) = try await URLSession.shared.data(for: request)
        }
        guard let document = PDFDocument(data: data) else { return .error("That is not a PDF Luna can read.") }
        let text = (document.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .error("The PDF has no text in it — it may be scanned pages.") }
        let limit = 60_000
        let clipped = text.count > limit ? String(text.prefix(limit)) + "\n[… the rest is cut]" : text
        return .text("\(document.pageCount) pages.\n\n\(clipped)")
    }

    // MARK: - The calendar

    /// An `.ics` file opened in Calendar, which asks the user to add it: the
    /// user confirms every event, and Luna needs no access to their calendars.
    static func addToCalendar(title: String, start: Date, end: Date?, allDay: Bool, notes: String?) throws -> ControlResult {
        let folder = AgentRunner.workingDirectory.appending(path: "Events", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "\(UUID().uuidString).ics")
        try Data(calendarEvent(title: title, start: start, end: end, allDay: allDay, notes: notes).utf8).write(to: file)
        NSWorkspace.shared.open(file)
        return .text("Calendar is asking the user to add “\(title)”.")
    }

    static func calendarEvent(title: String, start: Date, end: Date?, allDay: Bool, notes: String?) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = allDay ? .current : TimeZone(identifier: "UTC")
        formatter.dateFormat = allDay ? "yyyyMMdd" : "yyyyMMdd'T'HHmmss'Z'"
        func escaped(_ text: String) -> String {
            text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ";", with: "\\;")
                .replacingOccurrences(of: ",", with: "\\,").replacingOccurrences(of: "\n", with: "\\n")
        }
        let finish = end ?? (allDay ? Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start : start.addingTimeInterval(3600))
        let kind = allDay ? ";VALUE=DATE" : ""
        let stampFormatter = ISO8601DateFormatter()
        stampFormatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withTimeZone]
        var lines = [
            "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Luna//Astro//EN", "BEGIN:VEVENT",
            "UID:\(UUID().uuidString)@luna",
            "DTSTAMP:\(stampFormatter.string(from: Date()).replacingOccurrences(of: ":", with: ""))",
            "DTSTART\(kind):\(formatter.string(from: start))", "DTEND\(kind):\(formatter.string(from: finish))",
            "SUMMARY:\(escaped(title))"
        ]
        if let notes { lines.append("DESCRIPTION:\(escaped(notes))") }
        lines += ["END:VEVENT", "END:VCALENDAR"]
        return lines.joined(separator: "\r\n")
    }
}
