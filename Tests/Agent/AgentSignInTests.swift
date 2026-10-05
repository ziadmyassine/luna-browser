//
//  AgentSignInTests.swift
//  LunaTests
//
//  The agent's engines: reading whether each tool is signed in, finding the
//  sign-in page in what the tool printed, Codex's command line, a Codex task
//  remembering its thread, and what the panel says in each state.
//

import AppKit
import LunaControl
import XCTest
@testable import Luna

@MainActor
final class AgentSignInTests: XCTestCase {

    func testClaudeCodesStatusIsJSON() {
        XCTAssertTrue(AgentEngine.claude.isSignedIn(status: 0, output: #"{"loggedIn": true, "authMethod": "claude.ai"}"#))
        XCTAssertFalse(AgentEngine.claude.isSignedIn(status: 0, output: #"{"loggedIn": false, "authMethod": "none"}"#))
        XCTAssertFalse(AgentEngine.claude.isSignedIn(status: 1, output: "error"))
    }

    func testCodexsStatusIsWords() {
        XCTAssertTrue(AgentEngine.codex.isSignedIn(status: 0, output: "Logged in using ChatGPT\n"))
        XCTAssertFalse(AgentEngine.codex.isSignedIn(status: 1, output: "Not logged in\n"))
    }

    func testTheSignInPageIsFoundInWhatTheToolPrinted() {
        let claude = "Opening browser to sign in…\nIf the browser didn't open, visit: https://claude.ai/oauth/authorize?code=true&x=1\n"
        XCTAssertEqual(AgentAccount.page(in: claude)?.host(), "claude.ai")
        let codex = "Starting local login server on http://localhost:1455.\nIf your browser did not open, navigate to this URL "
            + "to authenticate:\n\nhttps://auth.openai.com/oauth/authorize?a=b\n"
        XCTAssertEqual(AgentAccount.page(in: codex)?.host(), "auth.openai.com", "the local server is not the page")
        XCTAssertNil(AgentAccount.page(in: "Paste code here if prompted > "))
    }

    func testCodexsCommandLine() {
        let task = UUID()
        let fresh = AgentCodexRunner.arguments(task: task, thread: nil)
        XCTAssertEqual(Array(fresh.prefix(2)), ["exec", "--json"])
        XCTAssertEqual(fresh.last, "-", "the message goes in on standard input")
        XCTAssertFalse(fresh.contains("resume"))
        XCTAssertTrue(fresh.contains("mcp_servers.luna.env={CLAUDE_CODE_SESSION_ID=\"\(task.uuidString.lowercased())\"}"))
        XCTAssertTrue(fresh.contains("mcp_servers.luna.default_tools_approval_mode=\"approve\""))
        let resumed = AgentCodexRunner.arguments(task: task, thread: "th-1")
        XCTAssertEqual(Array(resumed.suffix(3)), ["resume", "th-1", "-"])
        XCTAssertEqual(AgentCodexRunner.toml("say \"hi\"\nC:\\"), #""say \"hi\"\nC:\\""#)
    }

    func testACodexTaskRemembersItsThread() {
        let task = AgentTask(id: UUID(), prompt: "x", engine: .codex)
        task.began(thread: "th-9")
        XCTAssertEqual(task.thread, "th-9")
        let claude = AgentTask(id: UUID(), prompt: "x")
        claude.began(thread: "s")
        XCTAssertNil(claude.thread, "Claude Code resumes by Luna's own id")
    }

    func testSignedOutReadsAsSignedOut() {
        XCTAssertTrue(AgentEngine.meansSignedOut("Failed to authenticate. API Error: 401"))
        XCTAssertTrue(AgentEngine.meansSignedOut("Not logged in · Please run /login"))
        XCTAssertFalse(AgentEngine.meansSignedOut("The page did not load."))
        XCTAssertTrue(AgentSteps.explain("OAuth token expired", engine: .codex).hasPrefix("ChatGPT"))
    }

    func testWhatThePanelSaysInEachState() {
        let signedOut = AgentEmptyView.page(for: .signedOut(.claude), engine: .claude)
        XCTAssertEqual(signedOut.primary?.action, .signIn)
        XCTAssertEqual(signedOut.primary?.title, "Sign In with Claude")
        XCTAssertEqual(signedOut.secondary?.action, .use(.codex))
        let waiting = AgentEmptyView.page(for: .signingIn(.codex, page: nil), engine: .codex)
        XCTAssertNil(waiting.primary, "no page to open again until the tool has printed one")
        XCTAssertEqual(waiting.secondary?.action, .cancelSignIn)
        let page = AgentEmptyView.page(for: .signingIn(.codex, page: URL(string: "https://auth.openai.com")), engine: .codex)
        XCTAssertEqual(page.primary?.action, .reopenSignInPage)
        XCTAssertEqual(AgentEmptyView.page(for: .notInstalled(.codex), engine: .codex).secondary?.action, .use(.claude))
        XCTAssertNil(AgentEmptyView.page(for: nil, engine: .claude).primary)
    }
}
