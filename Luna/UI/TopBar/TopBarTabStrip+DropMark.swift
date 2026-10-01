//
//  TopBarTabStrip+DropMark.swift
//  Luna
//
//  §6.6's mark for a file or a link dragged over the window, on §4's bar:
//  the run opens a row's room where it will open and outlines it, dashed, as
//  the bar outlines every landing. Over the run the room follows the pointer
//  and the page lands there; anywhere else it stands at the end of today's
//  tabs, where the bar opens a new tab anyway.
//

import AppKit
import BrowserKit

extension TopBarTabStrip {

    /// Shows where pages dropped at `point` would open, and answers it.
    /// - Parameter point: the pointer, in the window's coordinates, or nil
    ///   for anywhere off the bar.
    /// - Returns: the landing, or nil for the end of today's tabs.
    @discardableResult
    func markDrop(at point: NSPoint?) -> SidebarDestination? {
        // A lift is up, and the room is the lift's.
        guard liftedID == nil else { return nil }
        let (block, destination) = dropLanding(at: point)
        dropGap = DropGap(
            block: block,
            width: TopBarTabRow.pillWidth,
            destination: destination ?? run.destination(forBlock: run.blocks.count, isPastMidpoint: false)
        )
        dropFolder = destination?.groupID
        layoutSubtreeIfNeeded()
        if let gapFrame {
            Tokens.Motion.immediately { dropMark.frame = box(gapFrame, height: TopBarMetrics.lineHeight) }
            dropMark.needsDisplay = true
        }
        dropMark.isHidden = gapFrame == nil
        return destination
    }

    /// Takes the mark and its room away.
    func clearDropMark() {
        guard dropGap != nil, liftedID == nil else { return }
        dropGap = nil
        dropFolder = nil
        dropMark.isHidden = true
    }

    /// The block the room opens in front of, and the landing — nil for the
    /// end of today's tabs. Only today's tier and §3.4b's take a page: a kept
    /// tile is a place the user pins, not one a drop fills.
    private func dropLanding(at point: NSPoint?) -> (Int, SidebarDestination?) {
        let end = (run.blocks.count, SidebarDestination?.none)
        guard let point, bounds.contains(convert(point, from: nil)) else { return end }
        let x = content.convert(point, from: nil).x
        var block = run.blocks.count
        var past = false
        for (index, frame) in blockFrames.enumerated() where x < frame.maxX {
            (block, past) = (index, x > frame.midX)
            break
        }
        if run.blocks.indices.contains(block), case .landing = run.blocks[block] { return end }
        let destination = run.destination(forBlock: block, isPastMidpoint: past)
        let allowed: Set<TabKind> = session.allowsPinning ? [.today, .pinned] : [.today]
        guard allowed.contains(destination.kind) else { return end }
        return (run.gap(forBlock: block, isPastMidpoint: past), destination)
    }
}
