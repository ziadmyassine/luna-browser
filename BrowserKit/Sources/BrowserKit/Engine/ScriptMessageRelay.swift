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
        case TabController.popupMessageName: owner?.handlePopupMessage(message)
        // §14. The coordinator re-checks the frame's origin before it acts on
        // anything here — the relay only routes.
        case PasswordForms.messageName: owner?.passwords.handle(message)
        case TabController.pickMessageName: owner?.handlePickMessage(message)
        case TabController.readingMessageName: owner?.handleReadingMessage(message)
        case TabController.pictureInPictureMessageName: owner?.handlePictureInPictureMessage(message)
        case TabController.webStoreMessageName: owner?.handleWebStoreMessage(message)
        default: break
        }
    }
}

/// The one handler a page waits on an answer from (§18.8's clipboard), registered with
/// `addScriptMessageHandler(_:contentWorld:name:)`.
extension ScriptMessageRelay: WKScriptMessageHandlerWithReply {

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) async -> (Any?, String?) {
        guard message.name == TabController.clipboardMessageName, let owner else { return (nil, nil) }
        return (await owner.handleClipboardMessage(message), nil)
    }
}
