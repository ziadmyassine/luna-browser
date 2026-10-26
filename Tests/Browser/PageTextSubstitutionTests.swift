//
//  PageTextSubstitutionTests.swift
//  LunaTests
//
//  Text a page inserts stays exactly as the page wrote it. Here rather than in
//  BrowserKit's suite because WebKit reads the substitution defaults once per
//  process, and only the app's launch registers them before every web view.
//

import BrowserKit
import WebKit
import XCTest
@testable import Luna

@MainActor
final class PageTextSubstitutionTests: XCTestCase {

    /// GitHub inserts `<!-- Uploading "image.png"... -->` for a pasted image and
    /// later replaces that exact string with the link. The system's "Use smart
    /// quotes and dashes" is on by default and turned its `-->` into `—>`.
    func testInsertedTextIsNotSubstituted() async throws {
        let webView = WebViewFactory.makeWebView(dataStore: .nonPersistent())
        webView.loadHTMLString("<textarea></textarea>", baseURL: nil)
        for _ in 0..<50 where webView.isLoading { try await Task.sleep(for: .milliseconds(100)) }
        let placeholder = "<!-- Uploading \"image.png\"... -->\n\"x\" -- y... (c)"
        let value = try await webView.evaluateJavaScript("""
        (function () {
          var field = document.querySelector('textarea');
          field.focus();
          document.execCommand('insertText', false, \(String(reflecting: placeholder)));
          return field.value;
        })();
        """) as? String
        XCTAssertEqual(value, placeholder)
    }
}
