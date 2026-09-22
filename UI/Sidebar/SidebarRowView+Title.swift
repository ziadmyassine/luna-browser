//
//  SidebarRowView+Title.swift
//  Luna
//
//  The one thing every §3.4 row has: its name, and what happens at the end of
//  it when the row is not wide enough for one.
//
//  Out of `SidebarRowView.swift` because that class is at SwiftLint's length
//  limit and this is the part of it with one subject — the title is laid out
//  at its natural width inside a clipping box, and a gradient mask ends the
//  line rather than an ellipsis, for the reason that file's header gives.
//

import AppKit

extension SidebarRowView {

    /// Takes the drawn title away while the field is up, and puts it back
    /// after (§3.4a, §3.4b). The field is transparent — it is a caret on the
    /// row rather than a box cut into it — so a title left underneath shows
    /// through the new name and reads as two words typed over each other.
    func setTitleHidden(_ hidden: Bool) {
        titleClip.isHidden = hidden
    }

    /// §3.4's fade. Nil mask when the title fits: a gradient that is opaque
    /// end to end still costs a masked composite on every row of every scroll.
    func applyFade(overflowing: Bool, width: CGFloat) {
        guard overflowing, width > Tokens.Metric.rowTitleFade else {
            titleClip.layer?.mask = nil
            return
        }
        let ink = Tokens.Text.primary
        fadeMask.frame = titleClip.bounds
        fadeMask.colors = [ink.cgColor, ink.cgColor, ink.withAlphaComponent(0).cgColor]
        fadeMask.locations = [0, NSNumber(value: Double(1 - Tokens.Metric.rowTitleFade / width)), 1]
        titleClip.layer?.mask = fadeMask
    }
}
