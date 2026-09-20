//
//  SidebarSpaceGestures.swift
//  Luna
//
//  Everything the foot of the sidebar does *to* Spaces: §30.9's two-finger
//  swipe and the page turn it drives, §6.1's create and the editor that follows
//  it, and §6.2's one way into the Settings section that holds the rest.
//
//  Its own object rather than more of `SidebarViewController` because it is the
//  only part of the column that is a **gesture** — it has a beginning, a middle
//  in which nothing has happened yet, and an end that may or may not change the
//  window. The controller around it lays views out and re-reads the session;
//  neither of those has a middle.
//
//  **The swipe is a page turn, not a hint.** The column used to lean 40 pt and
//  dim, which says "something is happening" and nothing else — the Space being
//  reached for stayed invisible until the gesture had already committed, so the
//  choice was made blind. The live column now translates a full width out while
//  `SpacePreviewView` translates the neighbouring Space in behind the fingers,
//  and on release it **settles to one side or the other**: there is no resting
//  position between two Spaces, so letting go half way is a decision, not a
//  place to stop.
//
//  **It holds no Spaces.** Every frame asks the session afresh, so a Space
//  created, deleted or reordered while a finger is down — by a menu, by another
//  window, by the Settings pane — cannot leave the gesture pointing at one that
//  is no longer there.
//

import AppKit
import BrowserKit

@MainActor
final class SidebarSpaceGestures {

    private let session: BrowserSession
    private let utility: SidebarUtilityBar
    private let wash: SpaceWashView
    /// The part of the column that rides along with the swipe — §3.3's tiles
    /// and §3.4's list. Not the control row or the pill: those belong to the
    /// window, not to the Space.
    private let content: [NSView]
    /// The Space arriving, and the `+` that stands in for the one that does not
    /// exist yet. Both are owned by the column and handed here, because both
    /// are only ever driven by this gesture.
    private let preview: SpacePreviewView
    private let creation: SpaceCreationView
    private let host: NSView
    private let swipe = SpaceSwipeController()
    /// Which Space the still is currently showing, so it is rebuilt when the
    /// swipe changes direction and not on every frame.
    private var previewing: UUID?
    private var editor: SpaceEditorView?

    init(
        session: BrowserSession,
        utility: SidebarUtilityBar,
        wash: SpaceWashView,
        content: [NSView],
        preview: SpacePreviewView,
        creation: SpaceCreationView,
        host: NSView
    ) {
        self.session = session
        self.utility = utility
        self.wash = wash
        self.content = content
        self.preview = preview
        self.creation = creation
        self.host = host
        swipe.spaces = { [weak self] in
            guard let self else { return ([], nil) }
            return (self.session.spaces.map(\.id), self.session.activeSpaceID)
        }
        swipe.onUpdate = { [weak self] state in self?.show(state) }
        swipe.onFinish = { [weak self] state, committing in self?.settle(state, committing: committing) }
    }

    /// True when the swipe took the event; false leaves it to the list.
    func scrollWheel(with event: NSEvent) -> Bool {
        // The editor is a surface, not a page: swiping over it would slide a
        // Space out from under a form that is still being filled in.
        guard editor == nil else { return false }
        return swipe.scrollWheel(with: event)
    }

    /// A swipe whose fingers left while the column was off screen has no
    /// release to wait for. Silent — nothing is committed by a gesture nobody
    /// finished.
    func cancel() {
        swipe.cancel()
    }

    // MARK: - The page turn

    /// §30.9 in the four places a Space is visible: the strip says which one
    /// you are about to get, the wash blends toward its colour, the live column
    /// translates out and the next one translates in behind it.
    private func show(_ state: SpaceSwipe, animated: Bool = false) {
        utility.spaceTravel = state.travel
        utility.spaceCreation = state.creation
        creation.progress = state.creation
        previewWash(travel: state.travel)
        updatePreview(for: state)
        turn(to: state.travel, animated: animated)
    }

    /// The frames of the two borrowed views, and the transforms of everything
    /// that moves. **Frames never animate and transforms always may** — a frame
    /// here is a consequence of the column's layout, which is not this
    /// gesture's to animate (see `Motion.immediately`).
    private func turn(to travel: CGFloat, animated: Bool) {
        let page = contentRect
        Tokens.Motion.immediately {
            preview.frame = page
            creation.frame = page
        }
        let shift = -travel * page.width
        let apply: () -> Void = {
            for view in self.content {
                view.wantsLayer = true
                view.layer?.setAffineTransform(CGAffineTransform(translationX: shift, y: 0))
            }
            self.preview.wantsLayer = true
            // The still starts one page off, on the side the fingers came from,
            // and lands exactly as the live column leaves.
            let offset = travel >= 0 ? page.width : -page.width
            self.preview.layer?.setAffineTransform(CGAffineTransform(translationX: shift + offset, y: 0))
            self.preview.isHidden = travel == 0
        }
        guard animated else { return Tokens.Motion.immediately(apply) }
        Tokens.Motion.animate(Tokens.Motion.spaceSwitchCrossfade) { context in
            context.allowsImplicitAnimation = true
            apply()
        }
    }

    /// Re-frames the three views this gesture owns but does not lay out.
    ///
    /// Called from the column's own layout pass, because their frame is the
    /// column's answer rather than the gesture's: the §3.7 handle can be
    /// dragged, and a page whose width was fixed when the gesture started would
    /// be the wrong width by the end of it.
    func layoutPages() {
        let page = contentRect
        Tokens.Motion.immediately {
            preview.frame = page
            creation.frame = page
            editor?.frame = page
        }
    }

    /// The region the Space owns: §3.3's tiles and §3.4's list, as one page.
    private var contentRect: NSRect {
        content.reduce(NSRect.zero) { $0 == .zero ? $1.frame : $0.union($1.frame) }
    }

    /// The Space the still is showing. Rebuilt only when the answer changes —
    /// once per direction, not once per frame.
    private func updatePreview(for state: SpaceSwipe) {
        guard state.travel != 0 else {
            previewing = nil
            return
        }
        // Past the last Space there is no Space to show. The still goes blank
        // and the `+` stands on it, which is the honest picture of what is
        // about to be made.
        let target = state.creation > 0 ? nil : neighbour(towards: state.travel)
        guard target?.id != previewing else { return }
        previewing = target?.id
        // **The same split §3 makes, made here too.** `SidebarList` is what the
        // real column divides a Space's tabs with, so the still is built from
        // it rather than from a flat `session.list[…]` — which is what used to
        // draw the §3.3 tiles as ordinary rows and let the pinned tabs arrive
        // unpinned and then correct themselves.
        let column = SidebarList(tabs: target.map { session.list[$0.id] } ?? [])
        preview.show(
            essentials: column.essentials,
            listed: column.listed,
            gradient: target?.gradient ?? Tokens.Gradient.neutral,
            icon: { [weak session] tab in
                if let image = session?.favicon(for: tab.id) { return image }
                guard let host = tab.url.host(), let data = FaviconService.shared.favicon(forHost: host)
                else { return nil }
                return NSImage(data: data)
            }
        )
    }

    private func neighbour(towards travel: CGFloat) -> Space? {
        guard let active = session.spaces.firstIndex(where: { $0.id == session.activeSpaceID }) else { return nil }
        let index = active + (travel > 0 ? 1 : -1)
        return session.spaces.indices.contains(index) ? session.spaces[index] : nil
    }

    /// The wash shows the Space the indicator is standing between, whichever
    /// two those are — not "the active one blended toward its neighbour". The
    /// still carries its own wash, so this is the one the *outgoing* page is
    /// leaving behind.
    private func previewWash(travel: CGFloat) {
        guard travel != 0, let active = session.spaces.firstIndex(where: { $0.id == session.activeSpaceID })
        else { return wash.endPreview() }
        let index = CGFloat(active) + travel
        let lower = Int(index.rounded(.down))
        wash.preview(between: gradient(at: lower), and: gradient(at: lower + 1), mix: index - CGFloat(lower))
    }

    /// **Past the Spaces that exist there is no wash**, because there is no
    /// Space: neutral paints nothing at all (`SpaceWashView.washColors`), so
    /// the colour drains as the swipe runs off the end and the sidebar has
    /// already said the next slot is empty before the `+` finishes saying it.
    private func gradient(at index: Int) -> GradientPair {
        session.spaces.indices.contains(index) ? session.spaces[index].gradient : Tokens.Gradient.neutral
    }

    // MARK: - The release

    /// **There is no resting position between two Spaces.** Whatever the
    /// fingers were holding when they left, the column travels the rest of the
    /// way to one side or springs back to none of it — and the Space changes at
    /// the end of that journey rather than at the start, so the page that
    /// arrives is the page you watched arrive.
    private func settle(_ state: SpaceSwipe, committing: Bool) {
        guard committing else { return settle(to: 0, creation: 0, then: nil) }
        if state.createsSpace {
            return settle(to: 1, creation: 1) { [weak self] in self?.createSpace() }
        }
        guard let landing = state.landing, session.spaces.indices.contains(landing) else {
            return settle(to: 0, creation: 0, then: nil)
        }
        let id = session.spaces[landing].id
        settle(to: state.travel > 0 ? 1 : -1, creation: 0) { [weak self] in self?.session.switchSpace(id) }
    }

    /// Runs the column the rest of the way, then commits.
    ///
    /// **The Space changes while the still is standing in for it**, which is
    /// the whole of why the seam does not show. At the end of the journey the
    /// live column is a full width off screen and `SpacePreviewView` is exactly
    /// where it used to be, showing the Space that is about to become the real
    /// one — so the column is put back in place *invisible*, the switch
    /// happens behind it, and the still cross-fades out over §6's
    /// `spaceSwitchCrossfade` as the real list fades in underneath. Nobody sees
    /// the swap, because for 180 ms both pictures are the same picture.
    ///
    /// Snapping back is the same journey with no commit at the end of it.
    private func settle(to travel: CGFloat, creation: CGFloat, then commit: (() -> Void)?) {
        show(SpaceSwipe(travel: travel, creation: creation, landing: nil, createsSpace: false), animated: true)
        let settled = Tokens.Motion.reduceMotion ? 0 : Tokens.Motion.spaceSwitchCrossfade.duration
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(settled))
            guard let self else { return }
            guard let commit else { return show(.rest) }
            handOff()
            commit()
        }
    }

    /// The column back where it belongs and out of sight, the read-out back to
    /// rest, and the still left holding the picture until the real one is ready.
    private func handOff() {
        Tokens.Motion.immediately {
            for view in content {
                view.layer?.setAffineTransform(.identity)
                view.alphaValue = 0
            }
            preview.layer?.setAffineTransform(.identity)
            utility.spaceTravel = 0
            utility.spaceCreation = 0
            creation.progress = 0
            wash.endPreview()
            previewing = nil
        }
        // Both ends of the cross-fade, stated here rather than left to
        // `SidebarViewController.refresh` — it animates the column's alpha on a
        // Space *switch*, and creating a Space is not one until the write lands.
        Tokens.Motion.animate(Tokens.Motion.spaceSwitchCrossfade) { context in
            context.allowsImplicitAnimation = true
            for view in content { view.animator().alphaValue = 1 }
            preview.animator().alphaValue = 0
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Tokens.Motion.spaceSwitchCrossfade.duration))
            guard let self else { return }
            preview.isHidden = true
            preview.alphaValue = 1
        }
    }

    // MARK: - The two verbs

    /// §6.1, from §30.9's swipe and from the footer's menu.
    ///
    /// **It is created named, not named and then created.** The gesture that
    /// asks for it ends with the fingers coming off the trackpad, and a modal
    /// asking for a name at that moment turns a fluid motion into a form. What
    /// follows is an editor rather than a dialog — see `SpaceEditorView`.
    func createSpace() {
        let name = String(localized: "Space \(session.spaces.count + 1)")
        Task { [weak self] in
            guard let self else { return }
            do {
                let space = try await session.createSpace(name: name)
                present(space)
            } catch {
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
    private func present(_ space: Space) {
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

    private func dismissEditor() {
        guard let editor else { return }
        self.editor = nil
        Tokens.Motion.animate(Tokens.Motion.spaceSwitchCrossfade) { context in
            context.allowsImplicitAnimation = true
            editor.animator().alphaValue = 0
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Tokens.Motion.spaceSwitchCrossfade.duration))
            editor.removeFromSuperview()
        }
    }

    /// One shape for the editor's three writes. **The failure is presented, not
    /// swallowed**: a user renaming the Space they just made is owed the reason
    /// it did not take, unlike a colour chosen in passing from a §3.5 dot.
    private func write(_ change: @escaping (BrowserSession) async throws -> Void) {
        Task { [weak self] in
            guard let self else { return }
            do { try await change(session) } catch { NSApp.presentError(error) }
        }
    }
}
