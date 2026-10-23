//
//  CommentMode.swift
//  Luna
//
//  ⇧⌘M's comment mode, one per window: point at an element or drag over an
//  area, write a note on it, and export the notes as a bundle an agent can read. Made when it is
//  entered and dropped when it ends, so nothing is resident while the mode is
//  off. `docs/plans/COMMENT-MODE.md` is the brief; this is its Flow 1–4.
//
//  The mode belongs to the tab it was entered on. Escape, ⇧⌘M, a new
//  document or a tab switch ends it; the draft stays for the next time.
//

import AppKit
import BrowserKit
import LunaControl
import WebKit

@MainActor
final class CommentMode: WindowScoped {

    let session: BrowserSession
    let windowID: UUID
    let set: CommentSet
    /// Whether a page gets the viewport picture as well as the crop: a live
    /// site's screen may hold customer data, so only a page on this Mac does.
    var isLocal: (URL) -> Bool = NavigationPolicy.isLocalDevelopment
    /// The viewport picture, taken after the crop is written; tests swap it to fail or to type mid-capture.
    var frame: (WKWebView, [CGPoint]) async throws -> CGImage = { try await ControlCapture.frame(of: $0, marks: $1) }
    /// The note field on screen, or nil while none is open.
    private(set) var note: CommentNoteView?

    private weak var window: BrowserWindow?
    private let surface: ControlSurfaceView
    private var tabID: UUID?
    /// The comment the open field writes to.
    private var editing: UUID?
    /// Picks are captured one at a time, in the order they were made.
    private var capturing: Task<Void, Never>?
    private var observation: ObservationToken?
    private var ended = false

    /// Padding around the element in its crop, CSS pixels a side.
    private static let cropPadding = 16.0
    /// The crop's long side at most, in pixels: a choice that keeps a picked
    /// page section legible without a full-resolution screen in every bundle.
    private static let cropLongSide = 1600.0

    init(window: BrowserWindow, set: CommentSet) {
        self.window = window
        self.set = set
        session = window.session
        windowID = window.id
        surface = window.controller.controlSurface
    }

    /// Starts the picker on the tab in front, ending Hide's if it is on.
    /// - Returns: whether it started.
    func enter() -> Bool {
        guard let tab = activeTabID, let controller = session.controller(for: tab) else { return false }
        tabID = tab
        controller.stopPickingElements()
        controller.startDescribingElements { [weak self] element in
            self?.picked(element)
        } onRegion: { [weak self] region, container in
            self?.picked(container, region: region)
        } onEnd: { [weak self] in
            self?.leave()
        }
        guard controller.isDescribingElements else { return false }
        observation = session.addChangeObserver { [weak self] in self?.followSelection() }
        (surface.window as? LunaWindow)?.keyDownFilter = { [weak self] in self?.walk(by: $0) ?? false }
        focusPage()
        return true
    }

    /// Every way out comes here, the picker's own Escape included, once.
    func leave() {
        guard !ended else { return }
        ended = true
        capturing?.cancel()
        observation = nil
        (surface.window as? LunaWindow)?.keyDownFilter = nil
        closeNote(focusingPage: false)
        tabID.flatMap { session.controller(for: $0) }?.stopDescribingElements()
        if window?.comments === self { window?.comments = nil }
    }

    private func followSelection() {
        if activeTabID != tabID { leave() }
    }

    // MARK: - Keys

    /// ↑ and ↓ walk the outline and Return picks it, wherever the keyboard
    /// is, except in a note with words in it, where they move the caret and
    /// commit the note, and in any other field of Luna's. A key the picker
    /// had no outline for goes on to whoever had the keyboard.
    /// - Returns: whether the key was taken.
    private func walk(by event: NSEvent) -> Bool {
        guard event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift]),
              let window = surface.window, let webView = tabID.flatMap({ session.controller(for: $0)?.webView })
        else { return false }
        let call: String
        switch event.keyCode {
        case 126: call = "walk(true)"
        case 125: call = "walk(false)"
        case 36, 76: call = "commit()"
        default: return false
        }
        let responder = window.firstResponder
        if let text = responder as? NSTextView, text !== note?.textView || !text.string.isEmpty { return false }
        Task { [weak responder] in
            let used = try? await webView.callAsyncJavaScript(
                "return window.__lunaPicker ? window.__lunaPicker.\(call) : false",
                arguments: [:], in: nil, contentWorld: .defaultClient
            ) as? Bool
            if used != true, let responder, window.firstResponder === responder { responder.keyDown(with: event) }
        }
        return true
    }

    // MARK: - A pick

    /// - Parameter region: a drag's area, of which `element` is the container.
    private func picked(_ element: PageElement, region: PageRegion? = nil) {
        commitNote()
        let previous = capturing
        capturing = Task { [weak self] in
            await previous?.value
            await self?.capture(element, region: region)
        }
    }

    /// The crop, the viewport picture on a local page, and the page's state,
    /// then the comment and its field. A pick that cannot be pictured is not
    /// kept, since a comment without its crop would point the agent at
    /// nothing; the toast says so, and no picture of it is left behind.
    /// A region is cropped exactly as drawn, an element with room around it.
    private func capture(_ element: PageElement, region: PageRegion?) async {
        guard !ended, let tabID, let webView = session.controller(for: tabID)?.webView, let url = webView.url,
              let origin = CommentBundle.slug(for: url) else { return }
        let id = UUID()
        let image = "\(id.uuidString).png"
        let box = region?.box ?? element.box
        let cropped = Self.crop(box, padding: region == nil ? Self.cropPadding : 0)
        var context: String?
        let page: PageState
        do {
            try FileManager.default.createDirectory(at: set.folder, withIntermediateDirectories: true)
            let crop = try await ControlCapture.image(of: webView, scale: scale(for: cropped, in: webView), region: cropped)
            try write(crop, to: image)
            if isLocal(url) {
                let centre = CGPoint(x: box.x + box.width / 2, y: box.y + box.height / 2)
                let name = "\(id.uuidString)-context.png"
                try write(await frame(webView, [centre]), to: name)
                context = name
            }
            page = try await state(of: webView, at: url)
        } catch {
            for name in [image, context].compactMap(\.self) {
                try? FileManager.default.removeItem(at: set.folder.appending(path: name))
            }
            if !ended { (region == nil ? PageToast.commentNotCaptured : .areaNotCaptured).show(in: surface.window) }
            return
        }
        guard !ended else { return }
        set.add(Comment(
            id: id, note: "", created: .now, origin: origin, page: page, element: element.cleaned,
            image: image, context: context, region: region?.cleaned
        ))
        showNote(for: id, beside: box, in: webView)
    }

    private static func crop(_ box: PageElement.Box, padding: Double) -> ControlCommand.Region {
        ControlCommand.Region(
            x: box.x - padding, y: box.y - padding, width: box.width + 2 * padding, height: box.height + 2 * padding
        )
    }

    /// The display's pixels per CSS pixel, unless that makes the long side too long.
    private func scale(for region: ControlCommand.Region, in webView: WKWebView) -> Double {
        let display = Double(webView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1)
        return min(display, Self.cropLongSide / max(region.width, region.height, 1))
    }

    private func write(_ image: CGImage, to name: String) throws {
        guard let data = ControlCapture.png(image) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: set.folder.appending(path: name), options: .atomic)
    }

    /// `dark` is `prefers-color-scheme`, which is what the page's CSS answered to.
    private func state(of webView: WKWebView, at url: URL) async throws -> PageState {
        guard let read = try await webView.callAsyncJavaScript(
            "return [innerWidth, matchMedia('(prefers-color-scheme: dark)').matches ? 1 : 0, scrollX, scrollY]",
            arguments: [:], in: nil, contentWorld: .defaultClient
        ) as? [Double], read.count == 4 else { throw CocoaError(.coderReadCorrupt) }
        return PageState(url: Self.scrubbed(url), viewportWidth: read[0], dark: read[1] == 1, scrollX: read[2], scrollY: read[3])
    }

    /// A fragment holding `=` is an OAuth or magic-link answer, never an anchor.
    private static func scrubbed(_ url: URL) -> String {
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if parts?.fragment?.contains("=") == true { parts?.fragment = nil }
        return CommentBundle.clean(parts?.string ?? url.absoluteString)
    }

    // MARK: - The note field

    private func showNote(for id: UUID, beside box: PageElement.Box, in webView: WKWebView) {
        let target = surface.convert(Self.rect(box, in: webView), from: webView)
        let arriving = note == nil
        let field = note ?? makeNote()
        if !arriving {
            // Words typed while this pick was captured are still the last comment's.
            commitNote()
            field.startNote()
        }
        editing = id
        if let controller = tabID.flatMap({ session.controller(for: $0) }) {
            field.setPageColour(FindController.colourUnder(controller))
        }
        let frame = Self.frame(field.frame.size, beside: target, in: surface.bounds, below: surface.topInset)
        if arriving {
            field.alphaValue = 0
            Tokens.Motion.immediately { field.frame = frame }
            surface.addSubview(field)
            note = field
        }
        Tokens.Motion.animate(Tokens.Motion.agentSheet) { _ in
            field.animator().frame = frame
            field.animator().alphaValue = 1
        }
        field.focus()
        // Only now: both pictures are taken, and the marker would be in them.
        tellPicker("mark(box)", ["box": ["x": box.x, "y": box.y, "width": box.width, "height": box.height]])
    }

    /// A call on the page's picker, if it is still there.
    private func tellPicker(_ call: String, _ arguments: [String: Any] = [:]) {
        tabID.flatMap { session.controller(for: $0)?.webView }?.callAsyncJavaScript(
            "if (window.__lunaPicker) { window.__lunaPicker.\(call); }", arguments: arguments, in: nil, in: .defaultClient
        )
    }

    /// Beside the element on its trailing side, and on its leading side when
    /// the page has no room there; never off the surface or under the bar.
    private static func frame(_ size: CGSize, beside box: CGRect, in bounds: CGRect, below top: CGFloat) -> CGRect {
        let gap = Tokens.Metric.chromeGap
        let inset = Tokens.Metric.pageBarInset
        let trailing = box.maxX + gap
        let x = trailing + size.width <= bounds.maxX - inset ? trailing : box.minX - gap - size.width
        let y = min(max(box.minY, top + gap), bounds.maxY - inset - size.height)
        return CGRect(x: min(max(x, bounds.minX + inset), bounds.maxX - inset - size.width), y: y,
                      width: size.width, height: size.height)
    }

    /// `box` is CSS pixels from the viewport's top left, in the web view's own points.
    private static func rect(_ box: PageElement.Box, in webView: WKWebView) -> CGRect {
        let zoom = webView.pageZoom * webView.magnification
        let height = box.height * zoom
        let y = webView.isFlipped ? box.y * zoom : webView.bounds.height - box.y * zoom - height
        return CGRect(x: box.x * zoom, y: y, width: box.width * zoom, height: height)
    }

    private func makeNote() -> CommentNoteView {
        let field = CommentNoteView(undoManager: set.undoManager)
        field.onSave = { [weak self] in self?.commitNote() }
        field.onDone = { [weak self] in self?.closeNote(focusingPage: true) }
        return field
    }

    /// An empty note deletes its comment, as `CommentSet.setNote` does.
    private func commitNote(undoable: Bool = true) {
        guard let editing, let note else { return }
        set.setNote(note.text, of: editing, undoable: undoable)
    }

    /// - Parameter undoable: as `CommentSet.setNote`'s.
    func closeNote(focusingPage: Bool, undoable: Bool = true) {
        guard let field = note else { return }
        commitNote(undoable: undoable)
        tellPicker("unmark()")
        let hadFocus = field.hasFocus
        note = nil
        editing = nil
        Tokens.Motion.animate(Tokens.Motion.agentSheet) { _ in
            field.animator().alphaValue = 0
        } completion: {
            MainActor.assumeIsolated { field.removeFromSuperview() }
        }
        if focusingPage, hadFocus { focusPage() }
    }

    private func focusPage() {
        guard let webView = tabID.flatMap({ session.controller(for: $0)?.webView }), webView.window === surface.window
        else { return }
        if let page = webView as? LunaWebView { page.takeFocus() } else { surface.window?.makeFirstResponder(webView) }
    }
}
