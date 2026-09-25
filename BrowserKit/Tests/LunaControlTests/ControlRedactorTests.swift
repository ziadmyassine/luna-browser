import Foundation
import LunaControl
import Testing

/// The last pass over every text result: secrets that reached the text by any
/// route come out, and look-alikes a task needs stay in.
@Suite("Luna Control redactor")
struct ControlRedactorTests {

    @Test func testLuhnCardRedactedButOrderNumberKept() {
        let text = "Paid with 4111 1111 1111 1111 and 5555-5555-5555-4444, card 378282246310005. Order 2024091512345678."
        let scrubbed = ControlRedactor.scrub(text)
        #expect(!scrubbed.contains("4111"))
        #expect(!scrubbed.contains("5555"))
        #expect(!scrubbed.contains("378282246310005"))
        #expect(scrubbed.contains("Order 2024091512345678."))
        #expect(scrubbed.contains(ControlRedactor.hidden))
        // Too short to be a card, whatever its checksum.
        #expect(ControlRedactor.scrub("Call 4242 4242 42 now") == "Call 4242 4242 42 now")
    }

    @Test func testJWTAndBearerScrubbed() {
        let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U"
        let scrubbed = ControlRedactor.scrub("token=\(jwt)\nAuthorization: Bearer abc.def-123_XYZ\nsaw bearer sk_live_51Habc")
        #expect(!scrubbed.contains("eyJ"))
        #expect(!scrubbed.contains("abc.def-123_XYZ"))
        #expect(!scrubbed.contains("sk_live_51Habc"))
        #expect(ControlRedactor.scrub("A bearer bond is paper.").contains("bearer bond"))
    }

    @Test func testCookieHeaderValueScrubbed() {
        let text = """
        Cookie: sid=31d4d96e407aad42; theme=dark
        set-cookie: session=abc123; Path=/; HttpOnly
        {"x-api-key": "k-9f8e7d6c", "Content-Type": "text/html"}
        """
        let scrubbed = ControlRedactor.scrub(text)
        #expect(!scrubbed.contains("31d4d96e407aad42"))
        #expect(!scrubbed.contains("abc123"))
        #expect(!scrubbed.contains("k-9f8e7d6c"))
        #expect(scrubbed.contains("Cookie: \(ControlRedactor.hidden)"))
        #expect(scrubbed.contains("text/html"))
        // A cookie string read out of document.cookie has no header name in front of it.
        let jar = ControlRedactor.scrub("theme=dark; sessionid=f00dface; csrftoken=beefcafe")
        #expect(jar.contains("theme=dark"))
        #expect(!jar.contains("f00dface") && !jar.contains("beefcafe"))
    }

    @Test func testQueryTokenScrubbed() {
        let text = "href=\"https://example.com/reset?user=ann&token=s3cr3t&page=2\" https://x.io/cb?code=4/0Ad&state=ok"
            + " https://a.b/?access_token=zz9&api_key=AKIA1&client_secret=shh&q=shoes&keyword=red"
        let scrubbed = ControlRedactor.scrub(text)
        for secret in ["s3cr3t", "4/0Ad", "zz9", "AKIA1", "shh"] {
            #expect(!scrubbed.contains(secret), "\(secret)")
        }
        for kept in ["user=ann", "page=2", "state=ok", "q=shoes", "keyword=red"] {
            #expect(scrubbed.contains(kept), "\(kept)")
        }
    }

    @Test func plainProseIsUntouched() {
        let prose = "Top stories: 1. Swift 7 ships (432 points) 2. A 1,000,000-row benchmark, 2025-09-21."
        #expect(ControlRedactor.scrub(prose) == prose)
    }
}
