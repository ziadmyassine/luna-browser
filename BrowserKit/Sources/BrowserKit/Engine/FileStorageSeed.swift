//
//  FileStorageSeed.swift
//  BrowserKit
//
//  What pages opened from files on this Mac saved in another browser, handed
//  to the same pages in Luna once. Every `file:` page shares one origin, and
//  one `localStorage` with it, so a page that keeps its state there — a
//  checklist, a board of what has been posted — opened in Luna for the first
//  time looked as if it had forgotten everything the other browser knew.
//
//  Seeded, not synced: the script copies the keys Luna does not have, marks the
//  origin as done, and never runs again for it. A key the page changes or
//  removes in Luna afterwards stays changed. The app decides where the entries
//  come from (`provider`); this side only puts them in the page.
//

import Foundation
import WebKit

@MainActor
public enum FileStorageSeed {

    /// Supplies the entries the first time a file page loads. Unset, nothing
    /// is seeded.
    public static var provider: (() -> [String: String])?

    /// Set in the page's own `localStorage` once it has been seeded.
    public static let marker = "__lunaCarriedOver"

    /// Internal so a test can start over.
    static var cached: [String: String]?

    static var entries: [String: String] {
        if let cached { return cached }
        let read = provider?() ?? [:]
        cached = read
        return read
    }

    /// The document-start script for a `file:` page, or nil with nothing to
    /// carry over. Document start, because a page reads its storage as it
    /// builds itself, and a seed that lands after that is one reload late.
    static func userScript() -> WKUserScript? {
        guard let source = source(for: entries) else { return nil }
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }

    static func source(for entries: [String: String]) -> String? {
        guard !entries.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: entries, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8),
              let marker = String(data: (try? JSONSerialization.data(withJSONObject: [marker])) ?? Data(), encoding: .utf8)
        else { return nil }
        return """
        (() => {
          if (location.protocol !== 'file:') return;
          try {
            const marker = \(marker)[0];
            if (localStorage.getItem(marker) !== null) return;
            const entries = \(json);
            for (const key of Object.keys(entries)) {
              if (localStorage.getItem(key) === null) localStorage.setItem(key, entries[key]);
            }
            localStorage.setItem(marker, '1');
          } catch (_) {}
        })();
        """
    }
}
