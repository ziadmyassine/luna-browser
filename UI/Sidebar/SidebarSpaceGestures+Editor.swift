//
//  SidebarSpaceGestures+Editor.swift
//  Luna
//
//  §6.1's two verbs, and the form the first of them opens.
//
//  Its own file because the gesture half of `SidebarSpaceGestures` and this
//  half fail differently and are read at different times: everything in the
//  other file happens while a finger is down, and everything in this one
//  happens after it has gone. The members it reaches for are internal rather
//  than private for the reason `EssentialsGridView`'s are — Swift's `private`
//  is file-scoped, and this class is two files.
//

import AppKit
import BrowserKit

extension SidebarSpaceGestures {
    // MARK: - The two verbs

    /// §6.1, from §30.9's swipe and from the footer's menu.
    ///
    /// It is created named, not named and then created. The gesture that
    /// asks for it ends with the fingers coming off the trackpad, and a modal
    /// asking for a name at that moment turns a fluid motion into a form. What
    /// follows is an editor rather than a dialog — see `SpaceEditorView`.
    func createSpace() {
        let name = String(localized: "Space \(session.spaces.count + 1)")
        // Set here rather than at the swipe's release, so the footer's menu —
        // which has no gesture behind it — hides the column too.
        isMakingSpace = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let space = try await session.createSpace(name: name)
                present(space)
            } catch {
                // Nothing was made, so nothing is being named: the column it
                // was hidden for is the one the window is still in.
                isMakingSpace = false
                revealColumn()
                NSApp.presentError(error)
            }
        }
    }

    /// §6.2's rows, in the one window that holds them — the same route §3.2's
    /// site menu takes to the Privacy section.
    func editSpaces() {
        (NSApp.delegate as? AppDelegate)?.showSettings(section: SpacesSection.id)
    }

    // MARK: - The editor

    /// The Space that has just arrived, with its three settings on it.
    func present(_ space: Space) {
        editor?.removeFromSuperview()
        let editor = SpaceEditorView(space: space)
        editor.frame = contentRect
        editor.onRename = { [weak self] name in self?.write { try await $0.renameSpace(space.id, to: name) } }
        editor.onGradient = { [weak self] pair in self?.write { try await $0.setGradient(pair, forSpace: space.id) } }
        editor.onIcon = { [weak self] name in self?.write { try await $0.setIcon(name, forSpace: space.id) } }
        editor.onClose = { [weak self] in self?.dismissEditor() }
        host.addSubview(editor, positioned: .below, relativeTo: utility)
        self.editor = editor
        editor.focusName()
        // The column goes if it is still there. After §30.9's swipe it already
        // is not — `handOff(revealingColumn:)` left it out of sight — but the
        // footer's menu opens this over a column that is very much on screen.
        Tokens.Motion.animate(Tokens.Motion.spaceSwitchCrossfade) { context in
            context.allowsImplicitAnimation = true
            for view in content { view.animator().alphaValue = 0 }
        }
        // It arrives the way the Space did: from the trailing edge, on §6's
        // Space-switch timing, so the editor reads as the last frame of the
        // gesture rather than as a panel that appeared afterwards.
        Tokens.Motion.immediately {
            editor.wantsLayer = true
            editor.alphaValue = 0
            let slide = editor.bounds.width / 4
            editor.layer?.setAffineTransform(CGAffineTransform(translationX: slide, y: 0))
        }
        Tokens.Motion.animate(Tokens.Motion.spaceSwitchCrossfade) { context in
            context.allowsImplicitAnimation = true
            editor.animator().alphaValue = 1
            editor.layer?.setAffineTransform(.identity)
        }
    }

    func dismissEditor() {
        guard let editor else { return }
        self.editor = nil
        isMakingSpace = false
        revealColumn()
        Tokens.Motion.animate(Tokens.Motion.spaceSwitchCrossfade) { context in
            context.allowsImplicitAnimation = true
            editor.animator().alphaValue = 0
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Tokens.Motion.spaceSwitchCrossfade.duration))
            editor.removeFromSuperview()
        }
    }

    /// The Space's own column, arriving as the form leaves it. Its first
    /// honest frame: by now the name, the colour and the mark are whatever the
    /// user made them.
    func revealColumn() {
        Tokens.Motion.animate(Tokens.Motion.spaceSwitchCrossfade) { context in
            context.allowsImplicitAnimation = true
            for view in content { view.animator().alphaValue = 1 }
        }
    }

    /// One shape for the editor's three writes. The failure is presented, not
    /// swallowed: a user renaming the Space they just made is owed the reason
    /// it did not take, unlike a colour chosen in passing from a §3.5 dot.
    func write(_ change: @escaping (BrowserSession) async throws -> Void) {
        Task { [weak self] in
            guard let self else { return }
            do { try await change(session) } catch { NSApp.presentError(error) }
        }
    }
}
