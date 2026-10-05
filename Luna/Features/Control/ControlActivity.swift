//
//  ControlActivity.swift
//  Luna
//
//  What the agents have asked Luna to do since launch, as the activity pill
//  and its list show it. `ControlAudit` is the file on disk and speaks in
//  tool names and element refs; this says the same calls in words, and knows
//  which one is still running.
//

import AppKit
import LunaControl

enum ControlActivity {

    enum State: Equatable {
        case running, done, failed, declined, stopped
    }

    struct Entry: Identifiable, Equatable {
        let id = UUID()
        /// The session that made the call (`ControlClient.session`).
        let agent: String
        let client: String
        let appID: String?
        let title: String
        let symbol: String
        let started = Date()
        var site: String?
        var state = State.running
    }

    /// Enough for a long session to scroll back through, and no more: the
    /// list is rebuilt whole on every change.
    static let kept = 200

    /// One session's pill: its newest call, the folder it works in, and
    /// whether it is at work now.
    struct Shown: Equatable {
        var entry: Entry
        var name: String
        var working: Bool
        var agent: String { entry.agent }
    }

    static func entry(for command: ControlCommand, agent: String, client: String, appID: String?) -> Entry {
        Entry(agent: agent, client: client, appID: appID, title: title(of: command), symbol: symbol(of: command))
    }

    /// The call as a person would say it. Element refs are left out: `e12`
    /// means nothing to anyone who is not the agent.
    static func title(of command: ControlCommand) -> String { // swiftlint:disable:this cyclomatic_complexity
        switch command {
        case .listTabs: String(localized: "Look at the open tabs")
        case let .nameTask(title, _): String(localized: "Call the task “\(title)”")
        case let .labelTab(title): String(localized: "Call a tab “\(title)”")
        case let .showDocument(title, _): String(localized: "Write up “\(title)”")
        case let .searchHistory(query, _):
            if query.isEmpty {
                String(localized: "Look at your history")
            } else {
                String(localized: "Look for “\(clip(query))” in your history")
            }
        case .listFolders: String(localized: "Look at your folders")
        case let .readPDF(url): String(localized: "Read \(url.flatMap(host) ?? String(localized: "a PDF"))")
        case let .addToCalendar(title, _, _, _, _): String(localized: "Add “\(clip(title))” to your calendar")
        case let .askUser(question, _): String(localized: "Ask you: \(clip(question))")
        case let .openTab(url): url.flatMap(host).map { String(localized: "Open \($0)") } ?? String(localized: "Open a tab")
        case let .navigate(.url(url)): host(url).map { String(localized: "Go to \($0)") } ?? String(localized: "Go to a page")
        case .navigate(.back): String(localized: "Go back")
        case .navigate(.forward): String(localized: "Go forward")
        case .navigate(.reload): String(localized: "Reload the page")
        case .readPage, .pageText: String(localized: "Read the page")
        case let .find(query): String(localized: "Look for “\(clip(query))”")
        case let .click(_, count, _, _, _) where count > 1: String(localized: "Double-click")
        case .click: String(localized: "Click")
        case let .type(text, _, _): String(localized: "Type \(text.count) characters")
        case let .key(keys, _, _): String(localized: "Press \(clip(keys))")
        case .hover: String(localized: "Point at something")
        case .drag: String(localized: "Drag")
        case let .scroll(direction, _, _): String(localized: "Scroll \(direction.rawValue)")
        case .fill: String(localized: "Fill in a field")
        case .screenshot: String(localized: "Take a screenshot")
        case .gif: String(localized: "Record the page")
        case .viewport: String(localized: "Resize the page")
        case .javascript: String(localized: "Run a script")
        case .console: String(localized: "Read the console")
        case .network: String(localized: "Read the network log")
        case .closeTab: String(localized: "Close a tab")
        case let .wait(seconds): String(localized: "Wait \(seconds.formatted()) s")
        case .requestUser: String(localized: "Ask you for help")
        case .dialog(true, _): String(localized: "Accept a dialog")
        case .dialog(false, _): String(localized: "Dismiss a dialog")
        case let .upload(_, files): String(localized: "Upload \(files.count) files")
        }
    }

    static func symbol(of command: ControlCommand) -> String {
        symbols[ControlAudit.tool(of: command)] ?? "sparkle"
    }

    private static let symbols: [String: String] = [
        "tabs_list": "square.stack", "tab_open": "plus.square", "navigate": "arrow.right.circle",
        "read_page": "doc.text", "page_text": "doc.text", "find": "magnifyingglass",
        "click": "cursorarrow.click", "type": "keyboard", "key": "command", "hover": "cursorarrow",
        "drag": "hand.draw", "scroll": "arrow.up.and.down", "form_input": "list.bullet.rectangle",
        "screenshot": "camera", "gif": "record.circle", "viewport": "rectangle.expand.vertical",
        "javascript": "curlybraces", "console_read": "terminal", "network_read": "network",
        "tab_close": "xmark.square", "wait": "hourglass", "request_user": "person.fill.questionmark",
        "dialog": "exclamationmark.bubble", "file_upload": "arrow.up.doc",
        "name_task": "character.cursor.ibeam", "ask_user": "hand.raised", "label_tab": "tag",
        "show_document": "doc.richtext", "history_search": "clock.arrow.circlepath", "folders_list": "folder",
        "pdf_text": "doc.text.magnifyingglass", "add_to_calendar": "calendar.badge.plus"
    ]

    /// How an entry ended, from the audit record's two words.
    static func state(decision: String, outcome: String) -> State {
        switch decision {
        case "declined", "refused": .declined
        case "stopped": .stopped
        default: outcome == "error" ? .failed : .done
        }
    }

    private static func host(_ url: URL) -> String? {
        url.host(percentEncoded: false).map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 }
    }

    private static func clip(_ text: String) -> String {
        text.count > 40 ? text.prefix(40) + "…" : text
    }
}
