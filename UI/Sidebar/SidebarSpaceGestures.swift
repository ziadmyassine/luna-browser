//
//  SidebarSpaceGestures.swift
//  Luna
//
//  Everything the foot of the sidebar does *to* Spaces: §30.9's two-finger
//  swipe and its live read-out, §6.1's create, and §6.2's one way into the
//  Settings section that holds the rest.
//
//  Its own object rather than more of `SidebarViewController` because it is the
//  only part of the column that is a **gesture** — it has a beginning, a middle
//  in which nothing has happened yet, and an end that may or may not change the
//  window. The controller around it lays views out and re-reads the session;
//  neither of those has a middle.
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
    private let swipe = SpaceSwipeController()

    init(session: BrowserSession, utility: SidebarUtilityBar, wash: SpaceWashView, content: [NSView]) {
        self.session = session
        self.utility = utility
        self.wash = wash
        self.content = content
        swipe.spaces = { [weak self] in
            guard let self else { return ([], nil) }
            return (self.session.spaces.map(\.id), self.session.activeSpaceID)
        }
        swipe.onSwitch = { [weak self] id in self?.session.switchSpace(id) }
        swipe.onNewSpace = { [weak self] in self?.createSpace() }
        swipe.onUpdate = { [weak self] state in self?.show(state) }
    }

    /// True when the swipe took the event; false leaves it to the list.
    func scrollWheel(with event: NSEvent) -> Bool {
        swipe.scrollWheel(with: event)
    }

    /// A swipe whose fingers left while the column was off screen has no
    /// release to wait for. Silent — nothing is committed by a gesture nobody
    /// finished.
    func cancel() {
        swipe.cancel()
    }

    // MARK: - The read-out

    /// §30.9 in the three places a Space is visible: the strip says which one
    /// you are about to get, the wash blends toward its colour, and the content
    /// leans the way the fingers are going.
    private func show(_ state: SpaceSwipe) {
        utility.spaceTravel = state.travel
        utility.spaceCreation = state.creation
        previewWash(travel: state.travel)
        // Clamped to one Space of lean whatever the travel: past that the
        // gesture is crossing several, and a column sliding further and further
        // out of the window says something the switch is not going to do.
        let lean = max(-1, min(state.travel, 1))
        Tokens.Motion.immediately {
            for view in content {
                view.wantsLayer = true
                view.layer?.setAffineTransform(
                    CGAffineTransform(translationX: -lean * Tokens.Metric.spaceSwipeParallax, y: 0)
                )
                view.alphaValue = 1 - Self.fade * abs(lean)
            }
        }
    }

    /// How much of the sidebar's content the swipe takes away at a full Space
    /// of travel. Enough to read as leaving, and not so much that an abandoned
    /// swipe looks like a window that went blank.
    private static let fade: CGFloat = 0.35

    /// The wash shows the Space the indicator is standing between, whichever
    /// two those are — not "the active one blended toward its neighbour". One
    /// gesture can cross several Spaces, and the sidebar has to be showing the
    /// pair either side of where the finger actually is.
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

    // MARK: - The two verbs

    /// §6.1, from §30.9's swipe and from the footer's menu.
    ///
    /// **It is created named, not named and then created.** The gesture that
    /// asks for it ends with the fingers coming off the trackpad, and a modal
    /// asking for a name at that moment turns a fluid motion into a form.
    /// `createSpace` switches to the new Space, and §6.2's card has the name
    /// field at its head — which is where a name that was going to be typed
    /// gets typed.
    func createSpace() {
        let name = String(localized: "Space \(session.spaces.count + 1)")
        Task { [weak self] in
            guard let self else { return }
            do { _ = try await session.createSpace(name: name) } catch { NSApp.presentError(error) }
        }
    }

    /// §6.2's rows, in the one window that holds them — the same route §3.2's
    /// site menu takes to the Privacy section.
    func editSpaces() {
        (NSApp.delegate as? AppDelegate)?.showSettings(section: SpacesSection.id)
    }
}
