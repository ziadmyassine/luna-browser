import Foundation
import WebKit

/// `WKUserContentController` retains its message handlers strongly. Registering the
/// controller itself would close a cycle — controller → web view → configuration →
/// content controller → controller — that never releases, so a tab dropped without
/// `hibernate()` would keep its whole WebContent process alive and its `deinit` would
/// never run to notice. The relay holds the controller weakly, so forgetting is
/// survivable rather than a leaked process.
///
/// One relay for every injected script rather than one per script: the cycle above is
/// the only thing that makes this class exist, and it does not get better by having two.
@MainActor
final class ScriptMessageRelay: NSObject, WKScriptMessageHandler {
    weak var owner: TabController?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        switch message.name {
        case TabController.mediaMessageName: owner?.handleMediaMessage(message)
        case ContentBlocker.blockedMessageName: owner?.handleBlockedMessage(message)
        case ContentBlocker.youTubeMessageName: owner?.handleYouTubeMessage(message)
        case TabController.scrollMessageName: owner?.handleScrollMessage(message)
        // §14. The coordinator re-checks the frame's origin before it acts on
        // anything here — the relay only routes.
        case PasswordForms.messageName: owner?.passwords.handle(message)
        default: break
        }
    }
}
