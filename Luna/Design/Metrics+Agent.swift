//
//  Metrics+Agent.swift
//  Luna
//
//  The agent panel (`Luna/Features/Agent`): the column beside the page, its
//  rover, its conversation and the field the user writes in. Kept with the
//  other surfaces' own files rather than in Metrics.swift.
//

import Foundation

extension Tokens.Metric {

    /// The panel's width: room for a sentence of 13 pt text at a comfortable
    /// measure (about 45 characters) inside `agentPanelInset` either side —
    /// the reference's column, a little narrower than the default sidebar.
    static let agentPanelWidth: CGFloat = 340
    /// Everything in the panel stands this far in from its edges, the
    /// sidebar's own `rowInset` plus a gap, so the panel's text lines up with
    /// the margin the page bar's controls keep.
    static let agentPanelInset: CGFloat = 16
    /// The rover in the header, a circle the size of §3.1's sidebar buttons
    /// beside it plus a ring's worth; and in the empty panel, where it is the
    /// whole of what there is to look at.
    static let agentRover: CGFloat = 40
    static let agentRoverHero: CGFloat = 96
    /// The task's name under the rover: a capsule the height of the URL pill.
    static let agentTitleCapsule = RoundedMetric(width: 220, height: 40, cornerRadius: 20)
    /// The user's messages: a bubble with the URL pill's corner, at most this
    /// share of the column so it reads as a reply from the side.
    static let agentBubbleRadius: CGFloat = 14
    static let agentBubbleShare: CGFloat = 0.82
    /// The field the user writes in, and the gap between conversation items:
    /// at 10 a reply's paragraphs and the card beside them ran together.
    static let agentComposerHeight: CGFloat = 44
    /// The most lines the field grows to before it scrolls: room for a task
    /// written as a paragraph, while the conversation keeps most of the panel.
    static let agentComposerLines = 6
    static let agentItemGap: CGFloat = 14
    /// Above each of the user's messages after the first, so a turn reads
    /// as a turn: about two lines of the conversation's type.
    static let agentTurnGap: CGFloat = 28
    /// Astro beside what it is doing (`AgentThinkingLine`), a size up from
    /// the steps' glyphs so its face still reads while it moves.
    static let agentActivityFace: CGFloat = 22
    /// The steps' glyphs, set a size under the text beside them.
    static let agentStepGlyph: CGFloat = 12
}
