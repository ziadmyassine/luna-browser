import Foundation
import WebKit

/// A detached web view on its way out, held until WebKit has finished with it.
///
/// Element fullscreen ends in several IPC round trips after it is asked to, and
/// WebKit's exit path does not keep its page alive across them. Closing a tab with
/// ⌘W while a video was fullscreen let the last reference go from inside one of
/// WebKit's own completions, partway through that exit: the page was freed, the
/// exit resumed on it, and WebKit stopped the app on an assertion.
///
/// So the view is kept until every completion handed to WebKit has come back and
/// it has left fullscreen, and is then let go from a turn of the main loop of its
/// own, never from inside a WebKit callback.
@MainActor
final class WebViewRetirement {

    private static var retiring: [ObjectIdentifier: WebViewRetirement] = [:]

    /// After fullscreen has ended. On the crash, WebKit's last exit reply came
    /// 85 ms after its fullscreen window had finished, so a second is ample.
    private static let fullscreenGrace: Duration = .seconds(1)
    /// Fullscreen that never reports its end — a WebContent process that died
    /// mid-exit — must not keep a closed tab's view alive for good.
    private static let ceiling: Duration = .seconds(10)

    private var view: WKWebView?
    private var outstanding = 0
    private var wasFullscreen = false
    private var observation: NSKeyValueObservation?

    init(_ view: WKWebView) {
        self.view = view
        Self.retiring[ObjectIdentifier(self)] = self
    }

    /// A completion for WebKit to call. Whatever releases the closure, the view
    /// stays in `retiring` until `finish` lets it go.
    func completion() -> @MainActor () -> Void {
        outstanding += 1
        return { [self] in
            outstanding -= 1
            finishIfDone()
        }
    }

    /// Called once every completion has been handed out.
    func start() {
        guard let view else { return }
        if view.fullscreenState != .notInFullscreen {
            wasFullscreen = true
            observation = view.observe(\.fullscreenState) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.finishIfDone() }
            }
        }
        Task { [self] in
            try? await Task.sleep(for: Self.ceiling)
            finish()
        }
        finishIfDone()
    }

    private func finishIfDone() {
        guard let view, outstanding == 0, view.fullscreenState == .notInFullscreen else { return }
        let grace: Duration = wasFullscreen ? Self.fullscreenGrace : .zero
        Task { [self] in
            try? await Task.sleep(for: grace)
            finish()
        }
    }

    private func finish() {
        guard view != nil else { return }
        observation?.invalidate()
        observation = nil
        view = nil
        Self.retiring[ObjectIdentifier(self)] = nil
    }
}
