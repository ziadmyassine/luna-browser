import Foundation
import WebKit

// Adapted from Search's ExtensionShims.swift (github.com/driceroland/Search),
// MIT License, Copyright (c) 2026 Office Commun; the full notice is at the top
// of Resources/ExtensionShim.js.

/// The shim's calls about tabs by their place in the row, and tab groups —
/// which are Luna's folders, shown to extensions as Chrome's groups.
extension ExtensionHost {

    /// A tab as the shim names it: `i`, its place in the row as extensions see
    /// it. Every tab of a Space is in its first window (`ExtensionSnapshot`),
    /// so the window's frame the shim also sends is not needed.
    private func located(_ place: Any?) -> UUID? {
        let index = (place as? NSNumber)?.intValue ?? ((place as? [String: Any])?["i"] as? NSNumber)?.intValue
        guard let index, snapshot.tabs.indices.contains(index) else { return nil }
        return snapshot.tabs[index]
    }

    func answerTabs(_ api: String, _ args: [Any], context: WKWebExtensionContext) throws -> ShimAnswer? {
        let first = args.first
        switch api {
        case "tabs.describe":
            return ShimAnswer((first as? [Any] ?? []).map { place -> Any in
                located(place).map { describe(tab: $0, for: context) } ?? NSNull()
            })
        case "tabs.activate":
            browser?.activateTab(try tab(at: first))
            return ShimAnswer(nil)
        case "tabs.move":
            let wanted = args.dropFirst().first as? Int ?? -1
            try services(for: api).extensionMoveTab(try tab(at: first), to: wanted < 0 ? snapshot.tabs.count - 1 : wanted)
            sync()
            return ShimAnswer(nil)
        case "tabs.discard":
            let id = try tab(at: first)
            if id != snapshot.activeTab { try services(for: api).extensionDiscardTab(id) }
            return ShimAnswer(nil)
        default:
            return nil
        }
    }

    /// Groups exist only while they hold a tab, as in Chrome.
    func answerTabGroups(_ api: String, _ args: [Any]) throws -> ShimAnswer? {
        let first = args.first
        switch api {
        case "tabs.groups":
            let services = self.services
            return ShimAnswer((first as? [Any] ?? []).map { place -> Int in
                located(place).flatMap { services?.extensionGroupID(ofTab: $0) }.map(groupNumber) ?? -1
            })
        case "tabs.group":
            let tabs = (first as? [Any] ?? []).compactMap(located)
            guard !tabs.isEmpty else { throw ExtensionShimRefusal(why: "No tabs to group") }
            let number = args.dropFirst().first as? Int ?? -1
            let target = number == -1 ? nil : try group(numbered: number).id
            guard let made = try services(for: api).extensionGroup(tabs, into: target, inSpace: spaceID) else {
                throw ExtensionShimRefusal(why: "These tabs can't be grouped")
            }
            sync()
            return ShimAnswer(groupNumber(made))
        case "tabs.ungroup":
            try services(for: api).extensionUngroup((first as? [Any] ?? []).compactMap(located))
            sync()
            return ShimAnswer(nil)
        case "tabGroups.query":
            return ShimAnswer(listedGroups().filter { Self.group($0, matches: first as? [String: Any] ?? [:]) }.map(chromeGroup))
        case "tabGroups.get":
            return ShimAnswer(chromeGroup(try group(numbered: first)))
        case "tabGroups.update":
            let group = try group(numbered: first)
            let props = args.dropFirst().first as? [String: Any] ?? [:]
            let title = props["title"] as? String, collapsed = props["collapsed"] as? Bool
            try services(for: api).extensionUpdateGroup(group.id, title: title, collapsed: collapsed)
            return ShimAnswer(chromeGroup(listedGroups().first { $0.id == group.id } ?? group))
        default:
            return nil
        }
    }

    private func tab(at place: Any?) throws -> UUID {
        guard let id = located(place) else { throw ExtensionShimRefusal(why: "No tab there") }
        return id
    }

    private static func group(_ group: TabGroup, matches spec: [String: Any]) -> Bool {
        (spec["title"] as? String).map { $0 == group.name } ?? true
            && (spec["collapsed"] as? Bool).map { $0 == group.isCollapsed } ?? true
            && (spec["color"] as? String).map { $0 == "grey" } ?? true
    }

    /// Another extension's page stays blank, as WebKit keeps it; its own are its own.
    private func describe(tab id: UUID, for context: WKWebExtensionContext) -> [String: Any] {
        let live = browser?.controller(for: id)
        let stored = browser?.extensionTabs(inSpace: spaceID).first { $0.id == id }
        let url = live?.state.url ?? stored?.url
        if let url, url.scheme == context.baseURL.scheme, url.host()?.lowercased() != context.uniqueIdentifier.lowercased() {
            return ["url": "", "title": ""]
        }
        let title = live.map(\.state.title).flatMap { $0.isEmpty ? nil : $0 } ?? stored?.title ?? ""
        return ["url": url?.absoluteString ?? "", "title": title]
    }

    func services(for api: String) throws -> any ExtensionServices {
        guard let services else { throw ExtensionShimRefusal.unavailable(api) }
        return services
    }

    /// Only groups with a tab in them, as Chrome has no empty group.
    private func listedGroups() -> [TabGroup] {
        guard let services else { return [] }
        let inUse = Set(snapshot.tabs.compactMap { services.extensionGroupID(ofTab: $0) })
        return services.extensionGroups(inSpace: spaceID).filter { inUse.contains($0.id) }
    }

    private func group(numbered number: Any?) throws -> TabGroup {
        guard let number = number as? Int, let group = listedGroups().first(where: { groupNumber($0.id) == number }) else {
            throw ExtensionShimRefusal(why: "No group with id: \(number.map { "\($0)" } ?? "none").")
        }
        return group
    }

    /// Chrome's group ids are numbers: one per group, given the first time an
    /// extension sees it and kept while Luna runs.
    private func groupNumber(_ id: UUID) -> Int {
        if let known = shim.groupNumbers[id] { return known }
        let number = shim.groupNumbers.count + 1
        shim.groupNumbers[id] = number
        return number
    }

    /// Luna's groups have a symbol, not a colour; grey is Chrome's first.
    private func chromeGroup(_ group: TabGroup) -> [String: Any] {
        ["id": groupNumber(group.id), "title": group.name, "collapsed": group.isCollapsed, "color": "grey",
         "windowId": 1, "shared": false]
    }
}
