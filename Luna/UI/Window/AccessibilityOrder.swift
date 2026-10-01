//
//  AccessibilityOrder.swift
//  Luna
//
//  The order VoiceOver walks a browser window in (§21.1). AppKit hands a
//  view's children over in subview order, which is drawing order rather than
//  reading order: the page card is under the chrome so the sidebar can peek
//  over it, so the page was read before the sidebar, and the sidebar's foot
//  read the Space, then Downloads and History, then the dots between them.
//

import AppKit

@MainActor
enum AccessibilityOrder {

    /// Top to bottom, and leading to trailing along a line. `last` are read
    /// after everything else whatever their frame — the sidebar's resize
    /// handle runs the column's full height and would otherwise be first.
    static func reading(_ children: [Any], last: [NSView] = []) -> [Any] {
        let (trailing, rest) = children.reduce(into: ([Any](), [Any]())) { split, child in
            if let view = view(of: child), last.contains(where: { view.isDescendant(of: $0) }) {
                split.0.append(child)
            } else {
                split.1.append(child)
            }
        }
        let framed = rest.enumerated().map { (index: $0.offset, child: $0.element, frame: frame(of: $0.element)) }
        let downward = framed.sorted { lhs, rhs in
            lhs.frame.maxY == rhs.frame.maxY ? lhs.index < rhs.index : lhs.frame.maxY > rhs.frame.maxY
        }
        var lines: [[(index: Int, child: Any, frame: NSRect)]] = []
        for item in downward {
            if let head = lines.last?.first, sharesLine(head.frame, item.frame) {
                lines[lines.count - 1].append(item)
            } else {
                lines.append([item])
            }
        }
        let ordered = lines.flatMap { line in
            line.sorted { lhs, rhs in lhs.frame.minX == rhs.frame.minX ? lhs.index < rhs.index : lhs.frame.minX < rhs.frame.minX }
        }
        return ordered.map(\.child) + trailing
    }

    /// The children inside each of `leads` first, in that order, and the rest
    /// after them where they were.
    static func led(_ children: [Any], by leads: [NSView]) -> [Any] {
        let ranked = children.enumerated().map { index, child in
            let rank = view(of: child).flatMap { view in leads.firstIndex { view.isDescendant(of: $0) } } ?? leads.count
            return (rank: rank, index: index, child: child)
        }
        return ranked.sorted { ($0.rank, $0.index) < ($1.rank, $1.index) }.map(\.child)
    }

    /// The view an element stands for: itself, a cell's control, or the
    /// nearest view among its accessibility parents.
    static func view(of element: Any) -> NSView? {
        var current: Any? = element
        for _ in 0 ..< 32 {
            switch current {
            case let view as NSView: return view
            case let cell as NSCell: return cell.controlView
            case let other as NSAccessibilityProtocol: current = other.accessibilityParent()
            default: return nil
            }
        }
        return nil
    }

    private static func frame(of element: Any) -> NSRect {
        (element as? NSAccessibilityProtocol)?.accessibilityFrame() ?? .zero
    }

    /// Each one's middle is inside the other's height. A full-height element
    /// shares no line with a button beside its top, and a 22 pt strip of dots
    /// shares one with the 34 pt buttons it stands between.
    private static func sharesLine(_ lhs: NSRect, _ rhs: NSRect) -> Bool {
        (lhs.minY ... lhs.maxY).contains(rhs.midY) && (rhs.minY ... rhs.maxY).contains(lhs.midY)
    }
}
