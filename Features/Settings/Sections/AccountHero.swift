//
//  AccountHero.swift
//  Luna
//
//  The head of the iCloud page: the user's picture, centred, their name and
//  one line under it, the way account pages in macOS and Raycast open. It
//  stands in for `SettingsPageHeader`, whose tile-and-title says which pane
//  this is when the picture already does.
//

import AppKit

@MainActor
final class AccountHeroView: NSView {

    /// The picture, or the initials drawn in its place.
    private let avatar = NSView()
    /// The ring round the picture: the accent while sync is on, the border's
    /// ink while it is off, so the page says which before a word is read.
    private let ring = NSView()
    /// Cross-fades the ring when it changes: the page updates in place.
    var isOn: Bool {
        didSet { if isOn != oldValue { refresh(animated: true) } }
    }

    init(name: String = NSFullUserName(), picture: NSImage? = SettingsAccountRow.loginPicture(), isOn: Bool) {
        self.isOn = isOn
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        buildFace(name: name, picture: picture)

        let title = NSTextField(labelWithString: name)
        title.font = Tokens.TypeScale.settingsPageTitle
        title.textColor = Tokens.Text.primary
        // CloudKit does not say which Apple Account it is, so the line under
        // the name is the Mac's account and where the sync happens.
        let line = NSTextField(labelWithString: "\(NSUserName()) · " + String(localized: "iCloud on this Mac"))
        line.font = Tokens.TypeScale.settingsRow
        line.textColor = Tokens.Text.secondary

        let outer = Tokens.Metric.settingsHeroAvatar + 2 * Tokens.Metric.settingsHeroRing
        for view in [ring, avatar, title, line] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            ring.topAnchor.constraint(equalTo: topAnchor),
            ring.centerXAnchor.constraint(equalTo: centerXAnchor),
            ring.widthAnchor.constraint(equalToConstant: outer),
            ring.heightAnchor.constraint(equalToConstant: outer),
            avatar.centerXAnchor.constraint(equalTo: ring.centerXAnchor),
            avatar.centerYAnchor.constraint(equalTo: ring.centerYAnchor),
            avatar.widthAnchor.constraint(equalToConstant: Tokens.Metric.settingsHeroAvatar),
            avatar.heightAnchor.constraint(equalToConstant: Tokens.Metric.settingsHeroAvatar),
            title.topAnchor.constraint(equalTo: ring.bottomAnchor, constant: SettingsMetrics.controlRowGap),
            title.centerXAnchor.constraint(equalTo: centerXAnchor),
            title.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            line.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
            line.centerXAnchor.constraint(equalTo: centerXAnchor),
            line.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            line.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("\(name), \(line.stringValue)")
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    /// The login picture, or the name's initials on the accent when there is
    /// none — `SettingsAccountRow`'s two faces, at the page's size.
    private func buildFace(name: String, picture: NSImage?) {
        let side = Tokens.Metric.settingsHeroAvatar
        ring.wantsLayer = true
        ring.layer?.cornerRadius = side / 2 + Tokens.Metric.settingsHeroRing
        avatar.wantsLayer = true
        avatar.layer?.cornerRadius = side / 2
        avatar.layer?.masksToBounds = true
        if let picture {
            let image = NSImageView(image: picture)
            image.imageScaling = .scaleProportionallyUpOrDown
            // Pinned, not autoresized: the avatar starts at zero, and a mask
            // grows a subview by the whole of its first layout, which drew
            // the picture at twice its size.
            image.translatesAutoresizingMaskIntoConstraints = false
            avatar.addSubview(image)
            NSLayoutConstraint.activate([
                image.leadingAnchor.constraint(equalTo: avatar.leadingAnchor),
                image.trailingAnchor.constraint(equalTo: avatar.trailingAnchor),
                image.topAnchor.constraint(equalTo: avatar.topAnchor),
                image.bottomAnchor.constraint(equalTo: avatar.bottomAnchor)
            ])
            return
        }
        let initials = NSTextField(labelWithString: SettingsAccountRow.initials(of: name))
        initials.font = Tokens.TypeScale.settingsPageTitle
        initials.textColor = Tokens.Accent.onTint
        initials.alignment = .center
        initials.translatesAutoresizingMaskIntoConstraints = false
        avatar.addSubview(initials)
        NSLayoutConstraint.activate([
            initials.centerXAnchor.constraint(equalTo: avatar.centerXAnchor),
            initials.centerYAnchor.constraint(equalTo: avatar.centerYAnchor)
        ])
    }

    private func refresh(animated: Bool = false) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let ring = self.isOn ? Tokens.Accent.tint : Tokens.Line.border
            if animated {
                Tokens.Motion.wash(self.ring.layer, to: ring)
            } else {
                self.ring.layer?.backgroundColor = ring.cgColor
            }
            self.avatar.layer?.backgroundColor = Tokens.Accent.tint.cgColor
            // A gap of the pane's own colour between picture and ring, so the
            // ring reads as a ring and not as the picture's edge.
            self.avatar.layer?.borderWidth = Tokens.Metric.settingsHeroRing / 1.5
            self.avatar.layer?.borderColor = Tokens.Surface.base.cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }
}
