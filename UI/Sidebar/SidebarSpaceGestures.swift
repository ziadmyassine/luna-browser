//
//  SidebarSpaceGestures.swift
//  Luna
//
//  Everything the foot of the sidebar does to Spaces: §30.9's two-finger
//  swipe and the page turn it drives, §6.1's create and the editor that follows
//  it, and §6.2's one way into the Settings section that holds the rest.
//
//  Its own object rather than more of `SidebarViewController` because it is the
//  only part of the column that is a gesture: it has a beginning, a middle in
//  which nothing has happened yet, and an end that may or may not change the
//  window. Laying views out and re-reading the session have no middle.
//
//  The swipe is a page turn, not a hint. The column used to lean 40 pt and dim,
//  which says "something is happening" and nothing else — the Space being
//  reached for stayed invisible until the gesture had committed, so the choice
//  was made blind. The live column now translates a full width out while
//  `SpacePreviewView` translates the neighbour in behind the fingers, and on
//  release it settles to one side or the other. There is no resting position
//  between two Spaces, so letting go half way is a decision.
//
//  It holds no Spaces. Every frame asks the session afresh, so a Space created,
//  deleted or reordered while a finger is down cannot leave the gesture
//  pointing at one that is no longer there.
//

import AppKit
import BrowserKit

@MainActor
final class SidebarSpaceGestures: WindowScoped {

    /// Not private: `+Editor.swift` is the other half of this class, and
    /// Swift's `private` is file-scoped.
    let session: BrowserSession
    let windowID: UUID
    let utility: SidebarUtilityBar
    private let wash: SpaceWashView
    /// The part of the column that rides along with the swipe — §3.3's tiles
    /// and §3.4's list. Not the control row or the pill: those belong to the
    /// window, not to the Space.
    let content: [NSView]
    /// The Space arriving, and the `+` that stands in for the one that does not
    /// exist yet. Both are owned by the column and handed here, because both
    /// are only ever driven by this gesture.
    private let preview: SpacePreviewView
    private let creation: SpaceCreationView
    let host: NSView
    private let swipe = SpaceSwipeController()
    /// The release, run home a frame at a time — see `SpaceSwipeSettle`.
    private lazy var settling = SpaceSwipeSettle(host: host)
    /// What the still is currently showing, so it is rebuilt when the swipe
    /// changes direction and not on every frame.
    ///
    /// Three answers rather than an optional id, and the third is the point:
    /// `blank` is the Space past the last one, which has no id and is not the
    /// same thing as "nothing has been built yet". With one nil standing for
    /// both, the blank still was never built — the rebuild was guarded on the
    /// answer changing, and nil to nil is not a change — so the swipe off the
    /// end of the strip kept drawing whichever Space the still had been left
    /// holding, tiles and rows included.
    private enum Showing: Equatable {
        case nothing
        /// The Space that does not exist yet.
        case blank
        case space(UUID)
    }

    private var previewing: Showing = .nothing
    var editor: SpaceEditorView?
    /// True from the moment a create commits until the editor it opens is
    /// closed.
    ///
    /// The new Space's column is not shown while its editor is up. The editor
    /// is a form on the column's own plane rather than a sheet over it, and the
    /// column behind it is three decisions from being anything — so a `New Tab`
    /// row and whatever the Profile pinned into it showed through the form
    /// asking what the Space is called. The column arrives when the form is
    /// done, which is the first moment it says anything true.
    ///
    /// `SidebarViewController.refresh` reads it: creating a Space is a Space
    /// switch, and a switch cross-fades the column back in.
    /// Written by `+Editor.swift` alone; everything else only reads it.
    var isMakingSpace = false
    /// Whether §30.9's ring has already ticked in this gesture — see
    /// `Tokens.Haptics.latch`.
    private var ringHasClosed = false

    init(
        session: BrowserSession,
        windowID: UUID,
        utility: SidebarUtilityBar,
        wash: SpaceWashView,
        content: [NSView],
        preview: SpacePreviewView,
        creation: SpaceCreationView,
        host: NSView
    ) {
        self.session = session
        self.windowID = windowID
        self.utility = utility
        self.wash = wash
        self.content = content
        self.preview = preview
        self.creation = creation
        self.host = host
        swipe.spaces = { [weak self] in
            guard let self else { return ([], nil) }
            return (self.session.spaces.map(\.id), self.activeSpaceID)
        }
        swipe.span = { [weak self] in self?.contentRect.width ?? 0 }
        swipe.onUpdate = { [weak self] state in self?.show(state) }
        swipe.onFinish = { [weak self] state, speed, committing in
            self?.settle(state, speed: speed, committing: committing)
        }
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
        settling.stop()
        swipe.cancel()
    }

    // MARK: - The page turn

    /// §30.9 in the four places a Space is visible: the strip says which one
    /// you are about to get, the wash blends toward its colour, the live column
    /// translates out and the next one translates in behind it.
    private func show(_ state: SpaceSwipe) {
        utility.spaceTravel = state.travel
        utility.spaceCreation = state.creation
        creation.progress = state.creation
        latchRing(at: state.creation)
        previewWash(travel: state.travel)
        updatePreview(for: state)
        turn(to: state.travel)
    }

    /// One tick as §30.9's ring closes — the moment the gesture starts being
    /// a create — and one more if the hand backs off far enough to undo it
    /// and pushes out again.
    ///
    /// It answers a threshold rather than announcing one. The ring used to
    /// close two thirds of a page before the release could act on it, which
    /// made this a warning; the ring is the threshold now, so it is a detent.
    /// The retreat is worth feeling too: panning back empties the ring and
    /// calls the create off, and a hand that only feels the arming has been
    /// told half of it.
    ///
    /// It re-arms low rather than at the threshold, because the column has all
    /// but stopped moving out there (`spaceCreateGive`) and a hand holding a
    /// stiff stop wobbles across it. Crossing at the same point in both
    /// directions would buzz.
    private static let ringReArm: CGFloat = 0.9

    private func latchRing(at creation: CGFloat) {
        guard creation >= 1 else {
            if creation < Self.ringReArm { ringHasClosed = false }
            return
        }
        guard !ringHasClosed else { return }
        ringHasClosed = true
        Tokens.Haptics.latch()
    }

    /// The frames of the two borrowed views, and the transforms of everything
    /// that moves.
    ///
    /// Nothing here ever animates, including on release. A frame is a
    /// consequence of the column's layout and was never this gesture's to
    /// animate (`Motion.immediately`), but the transforms used to be handed to
    /// Core Animation on the way home while the rest of the read-out was not —
    /// so the strip and the wash arrived at the new Space while the column was
    /// still crossing to it. `SpaceSwipeSettle` tweens the travel instead and
    /// calls this every frame, which leaves one way a frame of this gesture is
    /// drawn.
    private func turn(to travel: CGFloat) {
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
        Tokens.Motion.immediately(apply)
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
    var contentRect: NSRect {
        content.reduce(NSRect.zero) { $0 == .zero ? $1.frame : $0.union($1.frame) }
    }

    /// The Space the still is showing. Rebuilt only when the answer changes —
    /// once per direction, not once per frame.
    private func updatePreview(for state: SpaceSwipe) {
        guard state.travel != 0 else {
            previewing = .nothing
            return
        }
        // Past the last Space there is no Space to show. The still goes blank
        // and the `+` stands on it, which is the honest picture of what is
        // about to be made.
        let target = state.creation > 0 ? nil : neighbour(towards: state.travel)
        let wanted: Showing = target.map { .space($0.id) } ?? .blank
        guard wanted != previewing else { return }
        previewing = wanted
        // Nothing at all for the Space that does not exist yet — not an empty
        // Space's column, which is a different picture. An empty Space still
        // has a `New Tab` row on it (§30.6), and drawing one here said the
        // swipe was arriving somewhere rather than making somewhere.
        guard let target else { return preview.showBlank() }
        // The same split §3 makes, made here too. `SidebarList` is what the
        // real column divides a Space's tabs with, so the still is built from
        // it rather than from a flat `session.list[…]` — which is what used to
        // draw the §3.3 tiles as ordinary rows and let the pinned tabs arrive
        // unpinned and then correct themselves.
        let column = SidebarList(
            saved: session.list.drawnSlots(inSpace: target.id, kind: .pinned),
            today: session.list.drawnSlots(inSpace: target.id, kind: .today),
            essentials: session.list[target.id].filter { $0.kind == .essential }
        )
        preview.show(
            column: column,
            gradient: target.gradient,
            icon: { [weak session] tab in
                if let image = session?.favicon(for: tab.id) { return image }
                guard let host = tab.url.host(), let data = FaviconService.shared.favicon(forHost: host)
                else { return nil }
                return NSImage(data: data)
            }
        )
    }

    private func neighbour(towards travel: CGFloat) -> Space? {
        guard let active = session.spaces.firstIndex(where: { $0.id == activeSpaceID }) else { return nil }
        let index = active + (travel > 0 ? 1 : -1)
        return session.spaces.indices.contains(index) ? session.spaces[index] : nil
    }

    /// The wash shows the Space the indicator is standing between, whichever
    /// two those are — not "the active one blended toward its neighbour". The
    /// still carries its own wash, so this is the one the outgoing page is
    /// leaving behind.
    private func previewWash(travel: CGFloat) {
        guard travel != 0, let active = session.spaces.firstIndex(where: { $0.id == activeSpaceID })
        else { return wash.endPreview() }
        let index = CGFloat(active) + travel
        let lower = Int(index.rounded(.down))
        wash.preview(between: gradient(at: lower), and: gradient(at: lower + 1), mix: index - CGFloat(lower))
    }

    /// Past the Spaces that exist there is no wash, because there is no
    /// Space: neutral paints nothing at all (`SpaceWashView.washColors`), so
    /// the colour drains as the swipe runs off the end and the sidebar has
    /// already said the next slot is empty before the `+` finishes saying it.
    private func gradient(at index: Int) -> GradientPair {
        session.spaces.indices.contains(index) ? session.spaces[index].gradient : Tokens.Gradient.neutral
    }

    // MARK: - The release

    /// There is no resting position between two Spaces. Whatever the
    /// fingers were holding when they left, the column travels the rest of the
    /// way to one side or springs back to none of it — and the Space changes at
    /// the end of that journey rather than at the start, so the page that
    /// arrives is the page you watched arrive.
    private func settle(_ state: SpaceSwipe, speed: CGFloat, committing: Bool) {
        guard committing else { return settle(state, to: 0, creation: 0, at: speed, then: nil) }
        if state.createsSpace {
            Tokens.Haptics.commit()
            // The column stays where the gesture left it — off screen. What
            // arrives in its place is the editor, not the Space's own tabs.
            return settle(state, to: 1, creation: 1, at: speed, revealingColumn: false) { [weak self] in
                self?.createSpace()
            }
        }
        guard let landing = state.landing, session.spaces.indices.contains(landing) else {
            return settle(state, to: 0, creation: 0, at: speed, then: nil)
        }
        let id = session.spaces[landing].id
        settle(state, to: state.travel > 0 ? 1 : -1, creation: 0, at: speed) { [weak self] in
            self?.switchSpace(id)
        }
    }

    /// Runs the column the rest of the way, then commits.
    ///
    /// The Space changes while the still is standing in for it, which is why
    /// the seam does not show. At the end of the journey the live column is a
    /// full width off screen and `SpacePreviewView` is where it used to be,
    /// showing the Space about to become the real one — so the column is put
    /// back in place invisible, the switch happens behind it, and the still
    /// cross-fades out over §6's `spaceSwitchCrossfade` as the real list fades
    /// in underneath. For 180 ms both pictures are the same picture.
    ///
    /// Snapping back is the same journey with no commit at the end of it.
    private func settle(
        _ state: SpaceSwipe,
        to travel: CGFloat,
        creation: CGFloat,
        at speed: CGFloat,
        revealingColumn: Bool = true,
        then commit: (() -> Void)?
    ) {
        let target = SpaceSwipe(travel: travel, creation: creation, landing: nil, createsSpace: false)
        let spec = Tokens.Motion.spaceSettle(
            across: abs(travel - state.travel) * contentRect.width,
            at: abs(speed)
        )
        settling.run(from: state, to: target, on: spec) { [weak self] frame in
            // Every frame, the one way a frame is applied — the release is a
            // hand that kept going. See `SpaceSwipeSettle`.
            self?.show(frame)
        } onArrival: { [weak self] in
            guard let self else { return }
            guard let commit else { return show(.rest) }
            handOff(revealingColumn: revealingColumn)
            commit()
        }
    }

    /// The column back where it belongs and out of sight, the read-out back to
    /// rest, and the still left holding the picture until the real one is ready.
    private func handOff(revealingColumn: Bool) {
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
            previewing = .nothing
        }
        // Both ends of the cross-fade, stated here rather than left to
        // `SidebarViewController.refresh` — it animates the column's alpha on a
        // Space switch, and creating a Space is not one until the write lands.
        Tokens.Motion.animate(Tokens.Motion.spaceSwitchCrossfade) { context in
            context.allowsImplicitAnimation = true
            // A create is the one journey that does not end in the column
            // coming back: `isMakingSpace` holds it out of sight until the
            // editor is done with it.
            if revealingColumn { for view in content { view.animator().alphaValue = 1 } }
            preview.animator().alphaValue = 0
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Tokens.Motion.spaceSwitchCrossfade.duration))
            guard let self else { return }
            preview.isHidden = true
            preview.alphaValue = 1
        }
    }
}
