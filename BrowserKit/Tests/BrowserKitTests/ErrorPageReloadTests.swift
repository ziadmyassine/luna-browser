@testable import BrowserKit
import Foundation
import Network
import Testing
import WebKit

/// An error page stands in for the address that failed: the bar shows that
/// address, Reload tries it again, and the attempt takes the error page's place
/// in the back list rather than stacking behind it.
@Suite("Reloading an error page")
@MainActor
struct ErrorPageReloadTests {

    /// Answers every request on `port` with one small page.
    private final class Server {
        let listener: NWListener

        init(port: NWEndpoint.Port) throws {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            listener = try NWListener(using: parameters, on: port)
            listener.newConnectionHandler = { connection in
                connection.start(queue: .main)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { _, _, _, _ in
                    let body = "<title>up</title><p>up</p>"
                    let reply = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n"
                        + "Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                    connection.send(content: Data(reply.utf8), completion: .contentProcessed { _ in connection.cancel() })
                }
            }
            listener.start(queue: .main)
        }
    }

    @MainActor private final class Failures: TabControllerDelegate {
        var count = 0
        func tabController(_ controller: TabController, didChange state: TabState) {}
        func tabController(
            _ controller: TabController,
            wantsNewTabFor url: URL?,
            configuration: WKWebViewConfiguration
        ) -> WKWebView? { nil }
        func tabController(_ controller: TabController, didStartDownload download: WKDownload) {}
        func tabController(_ controller: TabController, didFailWith error: Error) { count += 1 }
    }

    /// A port nothing is listening on: one the system handed out and took back.
    private func closedPort() async throws -> NWEndpoint.Port {
        let probe = try NWListener(using: .tcp, on: .any)
        // A listener with no connection handler never starts.
        probe.newConnectionHandler = { $0.cancel() }
        probe.start(queue: .main)
        for _ in 0 ..< 250 where probe.state != .ready { try await Task.sleep(for: .milliseconds(20)) }
        let port = try #require(probe.port)
        probe.cancel()
        return port
    }

    private func until(_ condition: () -> Bool) async throws {
        for _ in 0 ..< 500 where !condition() { try await Task.sleep(for: .milliseconds(20)) }
    }

    private func isErrorPage(_ webView: WKWebView) -> Bool {
        webView.url?.scheme == InternalPages.scheme && !webView.isLoading
    }

    @Test func reloadRetriesTheAddressThatFailedInItsPlace() async throws {
        let port = try await closedPort()
        let failing = try #require(URL(string: "http://localhost:\(port)/login"))
        let controller = TabController(id: UUID(), dataStore: .nonPersistent())
        controller.activate()
        let webView = try #require(controller.webView)

        controller.load(failing)
        try await until { isErrorPage(webView) }
        #expect(webView.url?.host() == "error", "the load did not fail to an error page")
        #expect(controller.state.url == failing, "the bar shows the error page's own address")

        let server = try Server(port: port)
        defer { server.listener.cancel() }
        try await until { server.listener.state == .ready }

        controller.reload()
        try await until { webView.url == failing && !webView.isLoading }

        #expect(webView.url == failing, "Reload reloaded the error page")
        #expect(webView.backForwardList.backList.isEmpty, "the error page stayed behind in history")
    }

    @Test func aRetryThatFailsAgainLeavesOneErrorPage() async throws {
        let port = try await closedPort()
        let failing = try #require(URL(string: "http://localhost:\(port)/login"))
        let controller = TabController(id: UUID(), dataStore: .nonPersistent())
        let failures = Failures()
        controller.delegate = failures
        controller.activate()
        let webView = try #require(controller.webView)

        controller.load(failing)
        try await until { isErrorPage(webView) }

        controller.reload()
        try await until { failures.count == 2 && isErrorPage(webView) }

        #expect(failures.count == 2, "Reload did not try again")
        #expect(webView.url?.host() == "error")
        #expect(webView.backForwardList.backList.isEmpty, "a second error page stacked behind the first")
    }
}
