//
//  AccessibilityTree.swift
//  LunaTests
//
//  Reads a window the way VoiceOver is handed it: `accessibilityChildren`,
//  from the window down. In-process rather than through `AXUIElement`, which
//  needs the Accessibility permission CI's runner does not have.
//
//  AppKit hands a control's cell over as the element, and the label set on
//  the control is read from the control, so a cell is read through its
//  `controlView` — what the AX API reports, measured with a probe app.
//

import AppKit

@MainActor
struct AccessibilityNode {
    let element: Any
    let children: [AccessibilityNode]

    init(_ element: Any, depth: Int = 0) {
        self.element = element
        let kids = depth < 40 ? (element as? NSAccessibilityProtocol)?.accessibilityChildren() ?? [] : []
        children = kids.map { AccessibilityNode($0, depth: depth + 1) }
    }

    private var source: NSAccessibilityProtocol? {
        (element as? NSCell)?.controlView ?? element as? NSAccessibilityProtocol
    }

    var role: NSAccessibility.Role? { (element as? NSAccessibilityProtocol)?.accessibilityRole() }

    /// What VoiceOver says first: the label, or a button's own title.
    var name: String {
        [source?.accessibilityLabel(), source?.accessibilityTitle()]
            .compactMap { $0 }
            .first { !$0.isEmpty } ?? ""
    }

    var value: String { source?.accessibilityValue() as? String ?? "" }

    /// The titlebar's own buttons, which AppKit labels for itself.
    var isWindowWidget: Bool {
        ((element as? NSCell)?.controlView?.superview).map { "\(type(of: $0))".contains("Titlebar") } ?? false
    }

    var all: [AccessibilityNode] { [self] + children.flatMap(\.all) }

    /// The first node, in reading order, named `name`.
    func first(named name: String) -> AccessibilityNode? { all.first { $0.name == name } }

    /// Where in reading order the first node named `name` stands.
    func position(of name: String) -> Int? { all.firstIndex { $0.name == name } }
}
