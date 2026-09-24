import Foundation
import LunaControl
import Testing

/// Who may do what without asking: the three modes, per-site grants, and the
/// escalation a page earns by addressing the agent.
@Suite("Luna Control policy")
struct ControlPolicyTests {

    private let client = "Claude Code"
    private let site = "example.com"
    private let url = URL(string: "https://example.com/pay")!

    private var acting: [ControlCommand] {
        [
            .openTab(url), .navigate(.url(url)), .navigate(.back), .navigate(.reload),
            .click(.ref("e1"), clickCount: 1), .click(.point(x: 1, y: 2), clickCount: 2),
            .type("hello", ref: nil), .key("Enter"), .fill(ref: "e2", value: "x"), .javascript("1"),
            .dialog(accept: true, text: nil)
        ]
    }

    private var reading: [ControlCommand] {
        [
            .listTabs, .openTab(nil), .readPage(interactiveOnly: false, ref: nil, maxDepth: 30), .pageText,
            .find("pay"), .scroll(.down, amount: 3, target: nil), .screenshot,
            .console(pattern: nil, onlyErrors: false, clear: true), .wait(seconds: 1), .closeTab,
            .requestUser("Sign in"), .dialog(accept: false, text: nil)
        ]
    }

    private func decide(
        _ command: ControlCommand,
        site: String? = "example.com",
        client: String = "Claude Code",
        facts: ControlFacts = ControlFacts(),
        mode: ControlMode,
        grants: Set<ControlGrant> = []
    ) -> ControlDecision {
        ControlPolicy.decide(
            command, site: site, client: client, facts: facts,
            permissions: ControlPermissions(mode: mode, grants: grants)
        )
    }

    @Test func testAskModeAsksForEveryActingCall() {
        let granted: Set = [ControlGrant(client: client, site: site)]
        for command in acting {
            #expect(decide(command, mode: .ask).asks, "\(command)")
            // A grant made under another mode does not quiet this one.
            #expect(decide(command, mode: .ask, grants: granted).asks, "\(command)")
        }
    }

    @Test func testSiteGrantAllowsOnlyThatDomain() {
        let granted: Set = [ControlGrant(client: client, site: site)]
        let click = ControlCommand.click(.ref("e1"), clickCount: 1)
        #expect(decide(click, mode: .allowPerSite, grants: granted) == .allow)
        #expect(decide(click, site: "example.org", mode: .allowPerSite, grants: granted).asks)
        #expect(decide(click, client: "Codex", mode: .allowPerSite, grants: granted).asks)
        #expect(decide(click, site: nil, mode: .allowPerSite, grants: granted).asks)
        // What is asked in this mode can be answered with a grant; with no site it cannot.
        #expect(decide(click, site: "example.org", mode: .allowPerSite, grants: granted)
            == .ask(reason: ControlPolicy.actingReason, grantable: true))
        #expect(decide(click, site: nil, mode: .allowPerSite)
            == .ask(reason: ControlPolicy.actingReason, grantable: false))
    }

    @Test func testRevokedGrantAsksAgain() {
        var grants: Set = [ControlGrant(client: client, site: site), ControlGrant(client: client, site: "b.com")]
        let type = ControlCommand.type("x", ref: "e3")
        #expect(decide(type, mode: .allowPerSite, grants: grants) == .allow)
        grants.remove(ControlGrant(client: client, site: site))
        #expect(decide(type, mode: .allowPerSite, grants: grants).asks)
    }

    @Test func testReadToolsNeverAsk() {
        for mode in ControlMode.allCases {
            for command in reading {
                #expect(decide(command, mode: mode) == .allow, "\(command) in \(mode)")
            }
        }
        #expect(decide(.pageText, facts: ControlFacts(escalated: true), mode: .ask) == .allow)
    }

    @Test func testInjectionFlagEscalatesAllowAll() {
        let escalated = ControlFacts(escalated: true)
        let granted: Set = [ControlGrant(client: client, site: site)]
        for command in acting {
            #expect(decide(command, mode: .allowAll) == .allow, "\(command)")
            #expect(decide(command, facts: escalated, mode: .allowAll)
                == .ask(reason: ControlPolicy.injectionReason, grantable: false), "\(command)")
            #expect(decide(command, facts: escalated, mode: .allowPerSite, grants: granted).asks, "\(command)")
        }
    }

    @Test func testPaymentSubmitAsks() {
        let granted: Set = [ControlGrant(client: client, site: site)]
        let submit = ControlCommand.click(.ref("e4"), clickCount: 1)
        for risk in ControlRisk.asking {
            for mode in ControlMode.allCases {
                // Not quieted by the mode or a grant, and not answerable with one.
                #expect(decide(submit, facts: ControlFacts(risks: [risk]), mode: mode, grants: granted)
                    == .ask(reason: risk.reason, grantable: false), "\(risk) in \(mode)")
            }
        }
        // Reading a checkout page is still only reading.
        #expect(decide(.pageText, facts: ControlFacts(risks: [.payment]), mode: .ask) == .allow)

        // A consent screen reached by address rather than by a link asks the same.
        let consent = URL(string:
            "https://accounts.example.com/o/oauth2/auth?client_id=abc&redirect_uri=https%3A%2F%2Fapp.test&response_type=code")!
        #expect(ControlPolicy.isAuthorization(consent))
        #expect(!ControlPolicy.isAuthorization(URL(string: "https://example.com/search?client_id=7")!))
        for command in [ControlCommand.navigate(.url(consent)), .openTab(consent)] {
            #expect(decide(command, mode: .allowAll, grants: granted)
                == .ask(reason: ControlRisk.authorization.reason, grantable: false))
        }
    }

    @Test func testCaptchaHandsOff() {
        let granted: Set = [ControlGrant(client: client, site: site)]
        let captcha = ControlFacts(escalated: true, risks: [.captcha, .payment])
        for command in [ControlCommand.click(.point(x: 5, y: 5), clickCount: 1), .type("x", ref: "e1"), .key("Enter"),
                        .fill(ref: "e1", value: "x")] {
            for mode in ControlMode.allCases {
                // Handing off beats asking: no answer from the user lets the agent do it.
                #expect(decide(command, facts: captcha, mode: mode, grants: granted)
                    == .handoff(ControlRisk.captcha.reason), "\(command) in \(mode)")
                #expect(decide(command, facts: ControlFacts(risks: [.secretField]), mode: mode, grants: granted)
                    == .handoff(ControlRisk.secretField.reason))
            }
        }
        #expect(Set(ControlRisk.allCases).subtracting(ControlRisk.asking) == [.captcha, .secretField])
        // An internal page is refused before anything is handed to the user.
        #expect(decide(.pageText, facts: ControlFacts(isInternalPage: true, risks: [.captcha]), mode: .ask).denies)
    }

    @Test func testJavaScriptAsksEvenWithSiteGrant() {
        let granted: Set = [ControlGrant(client: client, site: site)]
        let script = ControlCommand.javascript("document.cookie")
        for mode in [ControlMode.ask, .allowPerSite] {
            #expect(decide(script, mode: mode, grants: granted)
                == .ask(reason: ControlPolicy.scriptReason, grantable: false), "\(mode)")
        }
        // The card shows the script itself, cut short.
        let long = String(repeating: "a", count: 1000)
        let summary = ControlAudit.summary(of: .javascript(long))
        #expect(summary.hasPrefix("javascript aaa") && summary.count < 250)
    }

    @Test func testJavaScriptAllowedOnlyInAllowAll() {
        let script = ControlCommand.javascript("1")
        #expect(decide(script, mode: .allowAll) == .allow)
        #expect(decide(script, facts: ControlFacts(escalated: true), mode: .allowAll)
            == .ask(reason: ControlPolicy.injectionReason, grantable: false))
    }

    @Test func localFilesAlwaysAskAndLunasOwnPagesAreRefused() {
        let file = URL(fileURLWithPath: "/Users/someone/.ssh/id_ed25519")
        #expect(decide(.navigate(.url(file)), mode: .allowAll)
            == .ask(reason: ControlPolicy.fileReason, grantable: false))
        #expect(decide(.openTab(file), site: nil, mode: .allowAll)
            == .ask(reason: ControlPolicy.fileReason, grantable: false))
        let lunaPage = ControlFacts(isInternalPage: true)
        #expect(decide(.pageText, facts: lunaPage, mode: .allowAll).denies)
        #expect(decide(.click(.ref("e1"), clickCount: 1), facts: lunaPage, mode: .allowAll).denies)
    }
}

private extension ControlDecision {
    var asks: Bool { if case .ask = self { true } else { false } }
    var denies: Bool { if case .deny = self { true } else { false } }
}
