//
//  Spaces+Picture.swift
//  Luna
//
//  §9's picture, on the Space's card and on §3.5's avatar.
//
//  It was a Profile's until `v7` took the Profile row away. A Space owns its
//  cookie jar and its name and its colour; the picture is the fourth thing that
//  says which Space you are in, and the only one that says it with a face.
//

import AppKit
import BrowserKit

@MainActor
extension SpacesSection {

    // MARK: The picture

    /// The picture §3.5's avatar wears, chosen and taken off from the same row.
    ///
    /// The thumbnail is in the row rather than only on the avatar because this
    /// is a list of cards: a column of identical rows saying "Picture" cannot
    /// tell you which Space has one. Remove appears only when there is
    /// something to remove — a permanently dimmed button beside every Space
    /// that has never had a picture is a control that mostly means nothing.
    func pictureRow(
        _ space: Space,
        session: BrowserSession?
    ) -> (view: NSView, terms: [String]) {
        let title = String(localized: "Picture")
        let picture = ProfilePicture.image(from: space.imageData)
        let choose = SettingsPushButton(
            title: picture == nil ? String(localized: "Choose…") : String(localized: "Replace…"),
            isDestructive: false
        )
        choose.onActivate = { [weak self] in self?.choosePicture(for: space, session: session) }

        var controls: [NSView] = [choose]
        if picture != nil {
            let clear = SettingsPushButton(title: String(localized: "Remove"), isDestructive: true)
            clear.onActivate = { [weak self] in self?.setPicture(nil, on: space, session: session) }
            controls.append(clear)
        }
        if let picture { controls.insert(Self.thumbnail(picture), at: 0) }

        let row = SettingsRow.accessory(title, subtitle: nil, accessory: Self.side(controls))
        return (row, [title, space.name, "picture", "photo", "image", "avatar", "profile picture"])
    }

    /// The row's trailing cluster. `chromeGap` between the controls, which is
    /// what two controls take between them everywhere else in the app.
    private static func side(_ views: [NSView]) -> NSView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = Tokens.Metric.chromeGap
        return stack
    }

    /// The picture at a control's height, round like the avatar that wears it.
    private static func thumbnail(_ image: NSImage) -> NSView {
        let side = Tokens.Metric.settingsControl
        let view = NSImageView(image: image)
        view.imageScaling = .scaleProportionallyUpOrDown
        view.wantsLayer = true
        view.layer?.cornerRadius = side / 2
        view.layer?.masksToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: side),
            view.heightAnchor.constraint(equalToConstant: side)
        ])
        return view
    }

    /// One image file, cropped and downsampled on the way in — see
    /// `ProfilePicture` for why the original is not what gets kept.
    private func choosePicture(for space: Space, session: BrowserSession?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = String(localized: "Choose a picture for \(space.name)")
        panel.prompt = String(localized: "Choose")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = ProfilePicture.bytes(ofFileAt: url) else {
            // The panel filters by type and the file can still be unreadable —
            // a damaged download, or a format this Mac has no decoder for.
            let alert = NSAlert()
            alert.messageText = String(localized: "That file could not be read as a picture.")
            alert.informativeText = String(localized: "Try a PNG, JPEG or HEIC.")
            alert.runModal()
            return
        }
        setPicture(data, on: space, session: session)
    }

    private func setPicture(_ data: Data?, on space: Space, session: BrowserSession?) {
        guard let session else { return }
        Task { [weak self] in
            do { try await session.setImage(data, forSpace: space.id) } catch { NSApp.presentError(error) }
            self?.build()
        }
    }

}
