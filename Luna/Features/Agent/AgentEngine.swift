//
//  AgentEngine.swift
//  Luna
//
//  Which model runs the agent: Claude, through Claude Code, or ChatGPT,
//  through Codex. Either runs on the user's own plan — they sign in once in
//  the browser through the tool's own sign-in, and Luna starts the tool as
//  them from then on, so the agent spends their plan's limits, not a key.
//
//  What differs between the two is here: the tool's name, how to ask whether
//  it is signed in, how to sign it in, and how to install it.
//

import Foundation
import LunaControl

enum AgentEngine: String, CaseIterable, Sendable {
    case claude
    case codex

    static let defaultsKey = "agent.engine"

    /// The one the user picked, Claude until they pick another.
    static var chosen: AgentEngine {
        get { UserDefaults.standard.string(forKey: defaultsKey).flatMap(AgentEngine.init(rawValue:)) ?? .claude }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    /// The model's name, as the user knows it.
    var name: String {
        switch self {
        case .claude: "Claude"
        case .codex: "ChatGPT"
        }
    }

    /// The tool that runs it.
    var toolName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }

    var command: String {
        switch self {
        case .claude: "claude"
        case .codex: "codex"
        }
    }

    var executable: URL? {
        ControlCLI.locate(command, home: FileManager.default.homeDirectoryForCurrentUser)
    }

    /// How to install the tool, for the panel to say when it is missing.
    var installHint: String {
        switch self {
        case .claude: String(localized: "Get it at claude.com/code, then come back.")
        case .codex:
            String(localized: "Install it with Homebrew (brew install --cask codex) or npm (npm i -g @openai/codex), then come back.")
        }
    }

    /// Signs in through the browser: the tool opens its sign-in page and
    /// waits on a local port for the page to hand the account back.
    var signInArguments: [String] {
        switch self {
        case .claude: ["auth", "login", "--claudeai"]
        case .codex: ["login"]
        }
    }

    /// Signs the tool out on this Mac — in a terminal as well, since it is
    /// the same tool and the same account.
    var signOutArguments: [String] {
        switch self {
        case .claude: ["auth", "logout"]
        case .codex: ["logout"]
        }
    }

    var statusArguments: [String] {
        switch self {
        case .claude: ["auth", "status"]
        case .codex: ["login", "status"]
        }
    }

    /// Whether the status command's answer says signed in. Claude Code
    /// prints JSON with `loggedIn`; Codex says it in words, and exits 1 when
    /// it is not.
    func isSignedIn(status: Int32, output: String) -> Bool {
        switch self {
        case .claude:
            guard let value = JSONValue.parse(Data(output.utf8)) else { return false }
            return value["loggedIn"]?.bool ?? false
        case .codex:
            return status == 0 && output.localizedCaseInsensitiveContains("logged in")
                && !output.localizedCaseInsensitiveContains("not logged in")
        }
    }

    /// Whether what the tool said when a task failed means it needs signing in again.
    static func meansSignedOut(_ message: String) -> Bool {
        let needles = [
            "authenticate", "log in", "login", "logged in", "oauth", "unauthorized", "401", "token expired",
            "token has expired", "sign in"
        ]
        return needles.contains { message.localizedCaseInsensitiveContains($0) }
    }
}
