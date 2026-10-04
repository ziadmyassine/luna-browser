//
//  ContentCardView+EmptyPane.swift
//  Luna
//
//  The card with no page in it shows `EmptyPaneView`'s painting rather than
//  its plain plane. A separate file because it is the one thing the card shows
//  that is not a page or the chrome over one.
//

import AppKit

extension ContentCardView {

    /// How long the pane has to stay empty before the painting comes in. A
    /// window is on screen before its first page is (§19.1), and a painting
    /// showing for that moment and then cut away was a flash at every launch.
    static let emptyPaneDelay: Duration = .milliseconds(250)

    /// Under everything the card holds, so a page arriving covers it before
    /// it has been told to go.
    func installEmptyPane() {
        emptyPane.translatesAutoresizingMaskIntoConstraints = false
        emptyPane.isHidden = true
        emptyPane.alphaValue = 0
        addSubview(emptyPane, positioned: .below, relativeTo: nil)
        NSLayoutConstraint.activate([
            emptyPane.topAnchor.constraint(equalTo: topAnchor),
            emptyPane.leadingAnchor.constraint(equalTo: leadingAnchor),
            emptyPane.trailingAnchor.constraint(equalTo: trailingAnchor),
            emptyPane.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        showEmptyPane(true)
    }

    /// Out at once when a page arrives; in, faded, only once the pane has
    /// stayed empty for `emptyPaneDelay`.
    func showEmptyPane(_ shown: Bool) {
        emptyPaneReveal?.cancel()
        emptyPaneReveal = nil
        guard shown else {
            emptyPane.isHidden = true
            emptyPane.alphaValue = 0
            return
        }
        guard emptyPane.isHidden else { return }
        emptyPaneReveal = Task { [weak self] in
            do { try await Task.sleep(for: Self.emptyPaneDelay) } catch { return }
            guard let self, !hasContent else { return }
            emptyPane.isHidden = false
            Tokens.Motion.animate(Tokens.Motion.themeWash) { _ in
                self.emptyPane.animator().alphaValue = 1
            }
        }
    }
}
