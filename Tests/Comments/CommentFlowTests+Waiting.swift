//
//  CommentFlowTests+Waiting.swift
//  LunaTests
//
//  How comment-mode tests wait on the page, and what a wait that runs out
//  says about it. Apart from `CommentFlowTests.swift` for its length limit.
//

import WebKit
import XCTest
@testable import Luna

extension CommentFlowTests {

    func waitFor(
        _ condition: @escaping () async throws -> Bool, file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        if try await poll(condition) { return }
        XCTFail("timed out; the page \(await pageReport())", file: file, line: line)
    }

    /// Whether `condition` came to hold. The ceiling is the CI runner's: a pick
    /// and its capture there have taken more than the two seconds a local run
    /// never comes near, and a local run returns on the first pass that holds.
    func poll(
        within ceiling: Duration = .seconds(15), _ condition: @escaping () async throws -> Bool
    ) async throws -> Bool {
        let deadline = ContinuousClock.now + ceiling
        while ContinuousClock.now < deadline {
            if try await condition() { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return try await condition()
    }

    /// Whether the page is hidden, and whether its process answers at all: a
    /// process WebKit has suspended never calls back, so the question is
    /// given two seconds rather than awaited.
    private func pageReport() async -> String {
        guard let webView = tab.webView else { return "has no web view" }
        final class Answer { var text: String? }
        let answer = Answer()
        webView.evaluateJavaScript("document.visibilityState") { result, error in
            answer.text = (result as? String).map { "is \($0)" } ?? "answered with \(String(describing: error))"
        }
        _ = try? await poll(within: .seconds(2)) { answer.text != nil }
        return answer.text ?? "did not answer in 2 s"
    }
}
