//
//  AgentSteps.swift
//  Luna
//
//  The agent's steps and failures as the panel words them. A Luna Control
//  call reads the way the activity log already reads it (`ControlActivity`),
//  so the panel and the log say the same thing about the same step.
//

import Foundation
import LunaControl

enum AgentSteps {

    /// A tool call as a person would say it, with its glyph.
    static func describe(name: String, input: [String: JSONValue]) -> (title: String, symbol: String) {
        if let tool = AgentStream.lunaTool(name),
           case let .success(call)? = ControlCall.parse(tool: tool, arguments: input) {
            return (ControlActivity.title(of: call.command), ControlActivity.symbol(of: call.command))
        }
        switch name {
        case "WebSearch":
            let query = input["query"]?.string.map { "“\(clip($0))”" } ?? ""
            return (String(localized: "Search the web for \(query)"), "magnifyingglass")
        case "WebFetch":
            let host = input["url"]?.string.flatMap { URL(string: $0)?.host() } ?? String(localized: "a page")
            return (String(localized: "Read \(host)"), "doc.text")
        case "TodoWrite":
            return (String(localized: "Plan the steps"), "list.bullet")
        default:
            return (String(localized: "Use \(AgentStream.lunaTool(name) ?? name)"), "sparkle")
        }
    }

    /// What the agent's own error means to the user, and what to do about it.
    static func explain(_ message: String?, engine: AgentEngine = .claude) -> String {
        let text = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if AgentEngine.meansSignedOut(text) {
            return String(localized: "\(engine.name) needs you to sign in again. Sign in, then tell me to carry on.")
        }
        if text.localizedCaseInsensitiveContains("usage limit") || text.localizedCaseInsensitiveContains("rate limit") {
            return String(localized: "Your \(engine.name) plan’s usage limit is reached for now. Try again later.")
        }
        return text.isEmpty ? String(localized: "Something went wrong, and the agent stopped.") : text
    }

    private static func clip(_ text: String) -> String {
        text.count > 40 ? String(text.prefix(39)) + "…" : text
    }
}
