//
//  QuitSheetView.swift
//  Luna
//
//  §3.1's "are you sure?", as a surface rather than as an `NSAlert`.
//
//  ⌘Q is next to ⌘W on every keyboard, and the two do wildly different things
//  to a window full of tabs. Luna did not guard the one that closes
//  everything, so a slipped finger took the whole session out with no way back.
//
//  Luna's own surface, not AppKit's. An `NSAlert` is four lines of code and it
//  is a different application answering: a grey titled panel with a blue
//  default button, in a window whose chrome is glass and whose accent colour
//  does not exist. So this is §5's material and §3.4's fills, with the three
//  answers laid out as the reference lays them — the likely one on the trailing
//  edge under Return, the way out beside it under Escape, and the one that also
//  changes a setting held apart at the other end, because "and don't ask again"
//  is a decision about every future quit.
//
//  No backdrop; `CommandBarPanel`'s header has the measurements. A veil over
//  the page separates the panel from the window it belongs to, and the material
//  has an edge and a shadow of its own. What makes this modal is that it takes
//  the keyboard and eats the clicks.
//

import AppKit

/// What the sheet was answered with.
enum QuitAnswer: Equatable, Sendable {
    case quit
    /// Quit, and never put this sheet up again — `GeneralSection.confirmQuit`.
    case quitAndStopAsking
    case stay
}

/// The sheet's geometry. Every value is an existing `Tokens.Metric`: `Design/`
/// has no quit-sheet entry, and contract rule 2 forbids inlining one — the
/// same reason `CommandBarMetrics` and `PopoutMetrics` read the way they do.
enum QuitSheetMetrics {
    /// The floor, not the width. Three quarters of the narrowest window
    /// Luna allows: narrow enough that the sheet is plainly a question rather
    /// than a pane, and wide enough that a one-line caption is not set in a
    /// column.
    ///
    /// The sheet is as wide as its answers are, and it has to be. A fixed
    /// width was the first build and both numbers tried were short of the
    /// three buttons — "Cancel" came out as "Can", then "Quit" came out as
    /// "Qu", because a row that does not fit does not say so: Auto Layout
    /// simply shaves the lowest-priority thing in it, which is a word. The
    /// titles are localised, so no number chosen here is safe in every
    /// language anyway. The row is measured and the panel takes that width,
    /// with this as the minimum.
    static var minimumWidth: CGFloat { (Tokens.Metric.windowMinWidth * 3 / 4).rounded() }
    static var cornerRadius: CGFloat { Tokens.Metric.contentCardRadius }
    static var padding: CGFloat { Tokens.Metric.chromeGapWide * 2 }
    /// §4's bar height. It is the tallest single thing the chrome measures,
    /// which is the right size for a mark you are meant to recognise rather
    /// than read.
    static var icon: CGFloat { Tokens.Metric.topBarHeight }
}

/// The full-window overlay and the panel standing on it.
@MainActor
final class QuitSheetView: NSView {

    /// Called once, with whatever the user answered. Cleared as it fires, so a
    /// second answer — a click racing the keyboard — cannot arrive.
    var onAnswer: ((QuitAnswer) -> Void)?

    private let body = NSView()
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let caption = NSTextField(labelWithString: "")
    private let stay: QuitSheetButton
    private let quit: QuitSheetButton
    private let quitForGood: QuitSheetButton

    /// - Parameter caption: the sentence under the question. It is the whole
    ///   reason this is not a bare "Are you sure?": what is actually at stake
    ///   is how many tabs there are and whether they come back, and only the
    ///   caller knows that.
    init(caption line: String) {
        stay = QuitSheetButton(title: String(localized: "Cancel"), keyHint: "esc", isKey: false)
        quit = QuitSheetButton(title: String(localized: "Quit"), keyHint: "\u{21A9}", isKey: true)
        quitForGood = QuitSheetButton(
            title: String(localized: "Quit, and don't ask again"),
            keyHint: nil,
            isKey: false
        )
        super.init(frame: .zero)
        autoresizingMask = [.width, .height]

        body.wantsLayer = true
        Glass.apply(.popover, to: body, cornerRadius: QuitSheetMetrics.cornerRadius)
        body.layer.map { Tokens.Shadow.popover.apply(to: $0, in: effectiveAppearance) }
        body.translatesAutoresizingMaskIntoConstraints = false
        addSubview(body)

        // Luna's own icon, at the size the Dock hands back. It is the one thing
        // on the sheet that says which app is about to go away — which is the
        // question, and "Quit Luna?" set in type is only half of it.
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        title.stringValue = String(localized: "Quit Luna?")
        title.font = Tokens.TypeScale.pageTitle
        caption.stringValue = line
        caption.font = Tokens.TypeScale.pageBody
        caption.alignment = .center
        caption.maximumNumberOfLines = 0
        caption.lineBreakMode = .byWordWrapping
        // Wrapped against the floor rather than the final width: the caption
        // must not be what makes the panel wide, or a Space with a lot of tabs
        // would stretch the sheet into a banner.
        caption.preferredMaxLayoutWidth = QuitSheetMetrics.minimumWidth - 2 * QuitSheetMetrics.padding
        // The answers keep their words. A row that does not fit is a bug
        // in the width above, and it has to look like one: at the default
        // resistance the stack simply shaved the two short buttons until
        // "Cancel" read "Can", which is a sheet that is wrong and does not say
        // so. `SheetTests` measures the row against the panel for the same
        // reason.
        for button in [stay, quit, quitForGood] {
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            button.setContentHuggingPriority(.required, for: .horizontal)
        }

        stay.onActivate = { [weak self] in self?.answer(.stay) }
        quit.onActivate = { [weak self] in self?.answer(.quit) }
        quitForGood.onActivate = { [weak self] in self?.answer(.quitAndStopAsking) }

        layOut()
        applyTokens()
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "Quit Luna?"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Luna builds its chrome in code; there is no nib to decode.")
    }

    // MARK: - Layout

    private func layOut() {
        // The row is not evenly spaced, and that is the point. "Quit, and
        // don't ask again" changes a setting; the other two answer this one
        // press. Held at the far end with the gap between them, the two groups
        // read as two different kinds of thing, which is what stops the
        // permanent one being picked by muscle memory aiming at the temporary.
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)
        let answers = NSStackView(views: [quitForGood, spacer, stay, quit])
        answers.orientation = .horizontal
        answers.spacing = Tokens.Metric.chromeGap
        answers.distribution = .fill
        answers.translatesAutoresizingMaskIntoConstraints = false

        let column = NSStackView(views: [icon, title, caption, answers])
        column.orientation = .vertical
        column.alignment = .centerX
        column.spacing = Tokens.Metric.chromeGap
        column.setCustomSpacing(Tokens.Metric.chromeGapWide, after: icon)
        column.setCustomSpacing(QuitSheetMetrics.padding, after: caption)
        column.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(column)

        let pad = QuitSheetMetrics.padding
        NSLayoutConstraint.activate([
            body.widthAnchor.constraint(greaterThanOrEqualToConstant: QuitSheetMetrics.minimumWidth),
            body.centerXAnchor.constraint(equalTo: centerXAnchor),
            // Half a chrome bar above centre, the way §9.1's own panel is held
            // high: a surface dropped exactly in the middle of a window reads
            // as heavier than one held slightly above it, and this one is not
            // heavy. Half a bar is also what the top bar takes out of the
            // content area, so the panel lands on the page's middle.
            body.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -Tokens.Metric.topBarHeight / 2),
            column.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: pad),
            column.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -pad),
            column.topAnchor.constraint(equalTo: body.topAnchor, constant: pad),
            column.bottomAnchor.constraint(equalTo: body.bottomAnchor, constant: -pad),
            answers.widthAnchor.constraint(equalTo: column.widthAnchor),
            icon.widthAnchor.constraint(equalToConstant: QuitSheetMetrics.icon),
            icon.heightAnchor.constraint(equalToConstant: QuitSheetMetrics.icon)
        ])
    }

    private func applyTokens() {
        title.textColor = Tokens.Text.primary
        caption.textColor = Tokens.Text.secondary
        body.layer.map { Tokens.Shadow.popover.apply(to: $0, in: effectiveAppearance) }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTokens()
    }

    // MARK: - Arriving

    /// §5's material arriving the way every other panel in Luna does: from
    /// just under full size, on `commandBarIn`, with the whole overlay fading
    /// with it.
    ///
    /// The spring is on the panel, not on this view. This one covers the
    /// window, so scaling it would scale the panel about the window's centre
    /// rather than about its own, and would take the click-catching area with
    /// it for the length of the animation.
    ///
    /// Under Reduce Motion `Motion.animate` zeroes the duration and the spring
    /// is skipped: the sheet is simply there, which is the right answer for a
    /// question.
    func reveal() {
        alphaValue = 0
        Tokens.Motion.animate(Tokens.Motion.commandBarIn) { context in
            context.allowsImplicitAnimation = true
            animator().alphaValue = 1
        }
        guard !Tokens.Motion.reduceMotion,
              let spring = Tokens.Motion.commandBarIn.springAnimation(keyPath: "transform.scale")
        else { return }
        // §9.1's own number, for §9.1's own reason: far enough under 1 to read
        // as arriving, near enough that nothing about the panel changes size.
        spring.fromValue = 0.96
        spring.toValue = 1.0
        body.layer?.add(spring, forKey: "quitSheet")
    }

    /// The reverse, with the panel left alone: an answer is not something to
    /// watch shrink.
    func dismiss(then done: @escaping @Sendable () -> Void) {
        Tokens.Motion.animate(Tokens.Motion.commandBarIn) { context in
            context.allowsImplicitAnimation = true
            animator().alphaValue = 0
        } completion: { done() }
    }

    // MARK: - Answering

    private func answer(_ answer: QuitAnswer) {
        guard let onAnswer else { return }
        self.onAnswer = nil
        onAnswer(answer)
    }

    /// A click that landed anywhere but the panel. It is the same answer
    /// Escape gives: staying is what every accidental gesture must mean.
    override func mouseDown(with event: NSEvent) {
        guard !body.frame.contains(convert(event.locationInWindow, from: nil)) else { return }
        answer(.stay)
    }

    /// Nothing under this reaches the page: the sheet is modal, and a click
    /// that fell through it would land on a tab that may be about to close.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit == nil ? self : hit
    }

    override var mouseDownCanMoveWindow: Bool { false }

    // MARK: - The keyboard

    override var acceptsFirstResponder: Bool { true }

    /// Escape stays. Not `cancelOperation` alone: ⌘. reaches that too, and
    /// so does an Escape a text field somewhere else in the window swallowed
    /// first — this view is made first responder while the sheet is up, so the
    /// key comes here and the two are the same answer anyway.
    override func cancelOperation(_ sender: Any?) {
        answer(.stay)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: answer(.quit)  // Return, and the keypad's Enter beside it.
        case 53: answer(.stay)
        default: super.keyDown(with: event)
        }
    }
}
