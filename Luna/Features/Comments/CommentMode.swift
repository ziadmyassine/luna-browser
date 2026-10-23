//
//  CommentMode.swift
//  Luna
//
//  ⇧⌘M's comment mode, one per window: point at an element, write a note on
//  it, and export the notes as a bundle an agent can read. Made when it is
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

    /// Starts the picker on the tab in front.
    /// - Returns: whether it started; Hide's picker already running stops it.
    func enter() -> Bool {
        guard let tab = activeTabID, let controller = session.controller(for: tab) else { return false }
        tabID = tab
        controller.startDescribingElements { [weak self] element in
            self?.picked(element)
        } onEnd: { [weak self] in
            self?.leave()
        }
        guard controller.isDescribingElements else { return false }
        observation = session.addChangeObserver { [weak self] in self?.followSelection() }
        return true
    }

    /// Every way out comes here, the picker's own Escape included, once.
    func leave() {
        guard !ended else { return }
        ended = true
        capturing?.cancel()
        observation = nil
        closeNote(focusingPage: false)
        tabID.flatMap { session.controller(for: $0) }?.stopDescribingElements()
        if window?.comments === self { window?.comments = nil }
    }

    private func followSelection() {
        if activeTabID != tabID { leave() }
    }

    // MARK: - A pick

    private func picked(_ element: PageElement) {
        commitNote()
        let previous = capturing
        capturing = Task { [weak self] in
            await previous?.value
            await self?.capture(element)
        }
    }

    /// The crop, the viewport picture on a local page, and the page's state,
    /// then the comment and its field. A pick that cannot be pictured is not
    /// kept: a comment without its crop would point the agent at nothing.
    private func capture(_ element: PageElement) async {
        guard !ended, let tabID, let webView = session.controller(for: tabID)?.webView, let url = webView.url,
              let origin = CommentBundle.slug(for: url) else { return }
        let id = UUID()
        let image = "\(id.uuidString).png"
        var context: String?
        let page: PageState
        do {
            try FileManager.default.createDirectory(at: set.folder, withIntermediateDirectories: true)
            let crop = try await ControlCapture.image(
                of: webView, scale: scale(for: element.box, in: webView), region: Self.cropRegion(element.box)
            )
            try write(crop, to: image)
            if isLocal(url) {
                let centre = CGPoint(x: element.box.x + element.box.width / 2, y: element.box.y + element.box.height / 2)
                let name = "\(id.uuidString)-context.png"
                try write(await ControlCapture.frame(of: webView, marks: [centre]), to: name)
                context = name
            }
            page = try await state(of: webView, at: url)
        } catch {
            return
        }
        guard !ended else { return }
        set.add(Comment(
            id: id, note: "", created: .now, origin: origin, page: page, element: element.cleaned,
            image: image, context: context
        ))
        showNote(for: id, beside: element.box, in: webView)
    }

    private static func cropRegion(_ box: PageElement.Box) -> ControlCommand.Region {
        ControlCommand.Region(
            x: box.x - cropPadding, y: box.y - cropPadding,
            width: box.width + 2 * cropPadding, height: box.height + 2 * cropPadding
        )
    }

    /// The display's pixels per CSS pixel, unless that makes the long side too long.
    private func scale(for box: PageElement.Box, in webView: WKWebView) -> Double {
        let display = Double(webView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1)
        let region = Self.cropRegion(box)
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
        if !arriving { field.startNote() }
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
    private func commitNote() {
        guard let editing, let note else { return }
        set.setNote(note.text, of: editing)
    }

    func closeNote(focusingPage: Bool) {
        guard let field = note else { return }
        commitNote()
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
