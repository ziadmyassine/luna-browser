//
//  SpaceNameFormatter.swift
//  Luna
//
//  §6.1/§6.2's name fields stopping at `BrowserSession.spaceNameCap`.
//
//  The cap itself is enforced where the name is stored, so nothing can get a
//  long one into the database. This is the half the user sees: without it a
//  name typed to fifty characters is accepted, committed, and comes back
//  shortened, which reads as the app having lost the end of it.
//
//  A `Formatter` rather than a `controlTextDidChange` in each host, because
//  there are three fields in two features and the rule is one rule. It
//  truncates a paste instead of rejecting it — dropping forty pasted
//  characters because two of them were over the line is the behaviour the cap
//  is supposed to prevent, not a smaller version of it.
//

import AppKit

final class SpaceNameFormatter: Formatter {

    override func string(for obj: Any?) -> String? { obj as? String }

    override func getObjectValue(
        _ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?,
        for string: String,
        errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        obj?.pointee = string as NSString
        return true
    }

    /// What a field keeps of `proposed`, or nil when all of it already fits.
    ///
    /// The rule, apart from the override that carries it. `isPartialStringValid`
    /// is four pointers deep and a test that drives it directly is testing
    /// AppKit's calling convention rather than the cap.
    static func kept(of proposed: String) -> String? {
        let cap = BrowserSession.spaceNameCap
        // `prefix` counts characters, so a flag or a combining accent costs
        // one and a cut never lands inside one.
        return proposed.count > cap ? String(proposed.prefix(cap)) : nil
    }

    /// The overload that can propose a replacement, rather than the short one
    /// that can only say no: returning false having rewritten the string is
    /// how AppKit is told to keep the first `spaceNameCap` characters of what
    /// arrived.
    override func isPartialStringValid(
        _ partialStringPtr: AutoreleasingUnsafeMutablePointer<NSString>,
        proposedSelectedRange proposedSelRangePtr: NSRangePointer?,
        originalString origString: String,
        originalSelectedRange origSelRange: NSRange,
        errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        guard let kept = Self.kept(of: partialStringPtr.pointee as String) else { return true }
        partialStringPtr.pointee = kept as NSString
        // The caret goes to the end of what was kept. Left where it was, a
        // paste that overflowed would put it back in the middle of the name.
        proposedSelRangePtr?.pointee = NSRange(location: (kept as NSString).length, length: 0)
        return false
    }
}
