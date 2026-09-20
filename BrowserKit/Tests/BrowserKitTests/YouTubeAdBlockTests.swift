import Foundation
import JavaScriptCore
import Testing
import WebKit
@testable import BrowserKit

/// §17.2's YouTube ads — the one part of blocking that is not a rule list.
///
/// The script is the thing under test, so it is **run**, not string-matched: a
/// `JSContext` with the handful of globals WebKit would have provides the hooks, and
/// the assertions are what a page would see after YouTube's own code reads the value.
/// A `#expect(source.contains("adPlacements"))` would pass against a script that had
/// been broken for a year.
@Suite("YouTube ad blocking (§17.2)")
@MainActor
struct YouTubeAdBlockTests {

    // MARK: - Harness

    /// The globals ``ContentBlocker/youTubeScript`` touches, with `location.hostname`
    /// set to `hostname`. Everything here is the minimum the script reaches for; a
    /// global it needs and does not find is a failed `install`, which is what
    /// ``anInstallThatCannotHappenDoesNotTakeTheOthersDown`` is about.
    private static func context(hostname: String) throws -> JSContext {
        let context = try #require(JSContext())
        context.exceptionHandler = { _, value in
            Issue.record("JavaScript threw: \(value?.toString() ?? "?")")
        }
        context.evaluateScript("""
        var window = this;
        var location = { hostname: '\(hostname)' };
        var ticks = [];
        function setInterval(fn) { ticks.push(fn); return ticks.length; }
        var document = {
          getElementById: function () { return null; },
          querySelector: function () { return null; },
          querySelectorAll: function () { return []; }
        };
        function Response() {}
        Response.prototype.text = function () { return Promise.resolve(this.body); };
        Response.prototype.json = function () { return Promise.resolve(JSON.parse(this.body)); };
        function XMLHttpRequest() {}
        XMLHttpRequest.prototype.open = function () {};
        var posted = [];
        window.webkit = { messageHandlers: { lunaYouTube: { postMessage: function (m) { posted.push(m); } } } };
        var nativeParse = JSON.parse;
        """)
        context.evaluateScript(ContentBlocker.youTubeScript)
        return context
    }

    /// A watch response shaped like the one measured on 2026-09-20: the ad schedule
    /// sitting in the same object as `streamingData` and `videoDetails`.
    private static let watchResponse = """
    {
      "playabilityStatus": { "status": "OK" },
      "streamingData": { "formats": [{ "itag": 18 }] },
      "videoDetails": { "videoId": "kJQP7kiw5Fk" },
      "adPlacements": [{ "adPlacementRenderer": { "config": {} } }],
      "adSlots": [{ "adSlotRenderer": {} }, { "adSlotRenderer": {} }],
      "playerAds": [{ "playerLegacyDesktopWatchAdsRenderer": {} }],
      "adBreakHeartbeatParams": "Q2c9PQ%3D%3D"
    }
    """

    // MARK: - The schedule (§17.2 layer 1)

    /// The cold-load path. YouTube assigns `ytInitialPlayerResponse` from an inline
    /// script; what it reads back must be the video without the ad breaks.
    @Test func theInlinePlayerResponseLosesItsAdSchedule() throws {
        let context = try Self.context(hostname: "www.youtube.com")
        context.evaluateScript("window.ytInitialPlayerResponse = nativeParse(\(Self.watchResponse.debugDescription));")

        let keys = context.evaluateScript("Object.keys(window.ytInitialPlayerResponse).join(',')")?.toString()
        let present = keys?.split(separator: ",").map(String.init) ?? []
        #expect(!present.contains("adPlacements"))
        #expect(!present.contains("adSlots"))
        #expect(!present.contains("playerAds"))
        #expect(!present.contains("adBreakHeartbeatParams"))
        // The half that matters more: the video itself is untouched.
        #expect(present.contains("streamingData"))
        #expect(present.contains("videoDetails"))
        #expect(context.evaluateScript("window.ytInitialPlayerResponse.videoDetails.videoId")?.toString()
            == "kJQP7kiw5Fk")
        #expect(context.evaluateScript("window.ytInitialPlayerResponse.playabilityStatus.status")?.toString() == "OK")
    }

    /// The SPA path, at the shape measured from `/youtubei/v1/get_watch`: an array whose
    /// first element carries `playerResponse`. The scrub has to reach it, which is the
    /// whole reason it walks rather than deleting three known keys off the top.
    @Test func theSPAWatchResponseLosesItsAdScheduleTwoLevelsDown() throws {
        let context = try Self.context(hostname: "www.youtube.com")
        let body = "[{\"playerResponse\":\(Self.watchResponse)},{\"response\":{}}]"
        context.evaluateScript("var parsed = JSON.parse(\(body.debugDescription));")

        #expect(context.evaluateScript("typeof parsed[0].playerResponse.adPlacements")?.toString() == "undefined")
        #expect(context.evaluateScript("typeof parsed[0].playerResponse.adSlots")?.toString() == "undefined")
        #expect(context.evaluateScript("typeof parsed[0].playerResponse.playerAds")?.toString() == "undefined")
        #expect(context.evaluateScript("parsed[0].playerResponse.videoDetails.videoId")?.toString() == "kJQP7kiw5Fk")
    }

    /// `Response.prototype.text` is the transport measured on 2026-09-20 — YouTube reads
    /// the body as text and parses it itself, so the text is where the ads have to go.
    @Test func theResponseBodyIsRewrittenBeforeYouTubeParsesIt() async throws {
        let context = try Self.context(hostname: "www.youtube.com")
        let body = "{\"playerResponse\":\(Self.watchResponse)}"
        context.evaluateScript("""
        var response = new Response();
        response.body = \(body.debugDescription);
        response.url = 'https://www.youtube.com/youtubei/v1/get_watch?prettyPrint=false';
        var settled = null;
        response.text().then(function (text) { settled = nativeParse(text); });
        """)
        // JavaScriptCore drains its microtask queue when the context is next entered.
        context.evaluateScript(";")

        #expect(context.evaluateScript("settled !== null")?.toBool() == true)
        #expect(context.evaluateScript("typeof settled.playerResponse.adPlacements")?.toString() == "undefined")
        #expect(context.evaluateScript("settled.playerResponse.videoDetails.videoId")?.toString() == "kJQP7kiw5Fk")
    }

    /// Another site's JSON goes through the same patched `JSON.parse` on every page
    /// YouTube is not. It must come back **identical** — a blocker that quietly edits
    /// arbitrary responses is a worse bug than the ad.
    @Test func aResponseThatIsNotYouTubesIsNotTouched() throws {
        let context = try Self.context(hostname: "www.youtube.com")
        context.evaluateScript("""
        var payload = '{"items":[{"videoRenderer":{"id":1}}],"adPlacements":"a string, not a schedule"}';
        var untouched = JSON.parse('{"a":1,"b":[1,2,3]}');
        var scrubbed = JSON.parse(payload);
        """)
        #expect(context.evaluateScript("JSON.stringify(untouched)")?.toString() == "{\"a\":1,\"b\":[1,2,3]}")
        // The gate is a string search, so this one *is* walked — and the array of real
        // videos has to survive it.
        #expect(context.evaluateScript("scrubbed.items.length")?.toInt32() == 1)
        #expect(context.evaluateScript("scrubbed.items[0].videoRenderer.id")?.toInt32() == 1)
    }

    // MARK: - The feed (§17.2 layer 2)

    /// An ad in a feed is an item in a list, and hiding it with CSS leaves the gap.
    /// Dropping it closes the grid up — which is what ``ContentBlocker/youTubeRules``
    /// cannot do and is why both layers exist.
    @Test func adItemsAreDroppedOutOfTheListsTheyArriveIn() throws {
        let context = try Self.context(hostname: "www.youtube.com")
        context.evaluateScript("""
        var feed = JSON.parse(JSON.stringify({ contents: [
          { richItemRenderer: { content: { videoRenderer: { videoId: 'a' } } } },
          { adSlotRenderer: { adLayoutRenderer: {} } },
          { richItemRenderer: { content: { videoRenderer: { videoId: 'b' } } } },
          { promotedSparklesWebRenderer: {} },
          { displayAdRenderer: {} }
        ], adPlacements: [] }));
        """)
        #expect(context.evaluateScript("feed.contents.length")?.toInt32() == 2)
        #expect(context.evaluateScript("feed.contents.map(function (c) "
            + "{ return c.richItemRenderer.content.videoRenderer.videoId; }).join('')")?.toString() == "ab")
    }

    // MARK: - Where it runs, and where it does not

    /// The script goes into **every** frame of every page, so its own hostname test is
    /// the thing keeping it off the rest of the web. If that test ever stops holding,
    /// every site on the internet gets a patched `JSON.parse`.
    @Test func nothingIsHookedOnAnyOtherSite() throws {
        for hostname in ["example.com", "notyoutube.com", "youtube.com.evil.test", "myyoutube.com"] {
            let context = try Self.context(hostname: hostname)
            #expect(context.evaluateScript("JSON.parse === nativeParse")?.toBool() == true,
                    "hooked on \(hostname)")
            #expect(context.evaluateScript("ticks.length")?.toInt32() == 0, "watching the player on \(hostname)")
        }
    }

    @Test func itRunsOnEveryYouTubePropertyAndOnTheEmbedHost() throws {
        for hostname in ["www.youtube.com", "youtube.com", "m.youtube.com",
                         "www.youtube-nocookie.com", "www.youtubekids.com"] {
            let context = try Self.context(hostname: hostname)
            #expect(context.evaluateScript("JSON.parse !== nativeParse")?.toBool() == true,
                    "not hooked on \(hostname)")
        }
    }

    /// The hooks are independent paths and are installed independently. A WebKit that
    /// one day has no `XMLHttpRequest` in some context must not cost the page the
    /// player-response trap, which is the one that does the work.
    @Test func anInstallThatCannotHappenDoesNotTakeTheOthersDown() throws {
        let context = try #require(JSContext())
        context.exceptionHandler = { _, value in
            Issue.record("JavaScript threw: \(value?.toString() ?? "?")")
        }
        context.evaluateScript("""
        var window = this;
        var location = { hostname: 'www.youtube.com' };
        var ticks = [];
        function setInterval(fn) { ticks.push(fn); return ticks.length; }
        var document = { getElementById: function () { return null; } };
        var nativeParse = JSON.parse;
        """)
        // No `Response`, no `XMLHttpRequest` at all.
        context.evaluateScript(ContentBlocker.youTubeScript)

        context.evaluateScript("window.ytInitialPlayerResponse = nativeParse(\(Self.watchResponse.debugDescription));")
        #expect(context.evaluateScript("typeof window.ytInitialPlayerResponse.adPlacements")?.toString() == "undefined")
        #expect(context.evaluateScript("JSON.parse !== nativeParse")?.toBool() == true)
        #expect(context.evaluateScript("ticks.length")?.toInt32() == 1)
    }

    // MARK: - The player fallback (§17.2 layer 3)

    /// A fake player, at the shape measured on the live site: `ad-showing` on
    /// `#movie_player` for exactly the ad, and **one** `<video>` shared by the ad and
    /// the video — which is what makes the mute below a hazard rather than a detail.
    private static func player(hostname: String = "www.youtube.com", skipButton: Bool) throws -> JSContext {
        let context = try Self.context(hostname: hostname)
        context.evaluateScript("""
        var skip = { clicks: 0, click: function () { this.clicks++; } };
        var video = { currentTime: 0, duration: 15, muted: false, paused: false, play: function () {} };
        var player = {
          classes: ['html5-video-player', 'ad-showing'],
          classList: { contains: function (name) { return player.classes.indexOf(name) >= 0; } },
          querySelector: function (selector) {
            if (selector.indexOf('video') === 0) { return video; }
            if (selector.indexOf('.ytp-ad-skip') >= 0) { return \(skipButton ? "skip" : "null"); }
            return null;
          }
        };
        document.getElementById = function (id) { return id === 'movie_player' ? player : null; };
        document.querySelector = function () { return null; };
        document.querySelectorAll = function () { return []; };
        function tick() { ticks.forEach(function (fn) { fn(); }); }
        """)
        return context
    }

    /// A skippable ad is skipped by pressing the button the site already offers, not by
    /// seeking — the seek is the fallback's fallback.
    @Test func askippableAdIsSkippedWithItsOwnButton() throws {
        let context = try Self.player(skipButton: true)
        context.evaluateScript("tick();")
        #expect(context.evaluateScript("skip.clicks")?.toInt32() == 1)
        // Untouched: the button did the work, so nothing had to be muted or seeked.
        #expect(context.evaluateScript("video.currentTime")?.toDouble() == 0)
        #expect(context.evaluateScript("video.muted")?.toBool() == false)
    }

    /// An unskippable one is seeked past instead. Not to `duration` exactly: a seek
    /// clamped to the very end can leave the player waiting on an `ended` that never
    /// fires.
    @Test func anUnskippableAdIsSeekedPast() throws {
        let context = try Self.player(skipButton: false)
        context.evaluateScript("tick();")
        let time = try #require(context.evaluateScript("video.currentTime")?.toDouble())
        #expect(time > 14.5 && time < 15)
        #expect(context.evaluateScript("video.muted")?.toBool() == true)
    }

    /// **The hazard.** The ad and the video are the same `<video>`, so a mute taken for
    /// the seek and not given back is a silent video for the rest of the watch. It has
    /// to come back, and only if we were the ones who took it.
    @Test func theMuteIsGivenBackWhenTheAdEnds() throws {
        let context = try Self.player(skipButton: false)
        context.evaluateScript("tick();")
        #expect(context.evaluateScript("video.muted")?.toBool() == true)

        context.evaluateScript("player.classes = ['html5-video-player']; tick();")
        #expect(context.evaluateScript("video.muted")?.toBool() == false)
    }

    /// A user who muted the tab themselves before an ad started has not asked for it
    /// back. `mutedByUs` is the whole of the distinction.
    @Test func aMuteTheUserTookIsLeftAlone() throws {
        let context = try Self.player(skipButton: false)
        context.evaluateScript("video.muted = true; tick();")
        context.evaluateScript("player.classes = ['html5-video-player']; tick();")
        #expect(context.evaluateScript("video.muted")?.toBool() == true)
    }

    /// Nothing happens to a video that is not an ad — the class is the only signal, and
    /// acting without it would seek the user past the thing they came to watch.
    @Test func contentPlaybackIsNeverSeeked() throws {
        let context = try Self.player(skipButton: true)
        context.evaluateScript("player.classes = ['html5-video-player']; video.duration = 281; tick(); tick();")
        #expect(context.evaluateScript("video.currentTime")?.toDouble() == 0)
        #expect(context.evaluateScript("skip.clicks")?.toInt32() == 0)
    }

    // MARK: - The static ads, on the native path

    /// **The one failure here that is completely silent.** `prepareYouTubeList()` is a
    /// fire-and-forget `Task`, so a selector WebKit refuses leaves `youTubeList` nil,
    /// nothing hidden, and no error anywhere. Same reason `localNetworkRules` is public.
    @Test func webKitCompilesTheCosmeticRules() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "luna-rules/\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try #require(WKContentRuleListStore(url: directory))
        let list = try await store.compileContentRuleList(
            forIdentifier: "test-youtube", encodedContentRuleList: ContentBlocker.youTubeRules
        )
        #expect(list != nil)
    }

    /// §17.1's correction, applied here: a bare `youtube.com` in `if-domain` matches that
    /// host and nothing else, and the site the user is on is `www.youtube.com`.
    @Test func everyDomainCarriesTheSubdomainStar() throws {
        #expect(ContentBlocker.youTubeDomains.allSatisfy { $0.hasPrefix("*") })
        let rules = try JSONDecoder().decode(
            [ContentRule].self, from: #require(ContentBlocker.youTubeRules.data(using: .utf8))
        )
        #expect(rules.count == ContentBlocker.youTubeAdSelectors.count)
        #expect(rules.allSatisfy { $0.action.type == "css-display-none" })
        #expect(rules.allSatisfy { $0.trigger.ifDomain == ContentBlocker.youTubeDomains })
    }

    // MARK: - The gate

    @Test func theHostTestMatchesSubdomainsAndNothingElse() {
        #expect(ContentBlocker.isYouTube(host: "www.youtube.com"))
        #expect(ContentBlocker.isYouTube(host: "youtube.com"))
        #expect(ContentBlocker.isYouTube(host: "WWW.YouTube.com."))
        #expect(ContentBlocker.isYouTube(host: "www.youtube-nocookie.com"))
        #expect(!ContentBlocker.isYouTube(host: "youtube.com.evil.test"))
        #expect(!ContentBlocker.isYouTube(host: "myyoutube.com"))
        #expect(!ContentBlocker.isYouTube(host: nil))
    }

    /// §17.2's per-site switch has to mean YouTube too, and the `ads` toggle has to turn
    /// this off — it is that toggle's behaviour, not a fourth setting.
    @Test func itFollowsTheAdsToggleAndThePerSiteSwitch() {
        let defaults = UserDefaults(suiteName: "luna.youtube.tests.\(UUID().uuidString)")!
        let blocker = ContentBlocker(defaults: defaults)
        #expect(blocker.blocksYouTubeAds(forHost: "www.youtube.com"))

        blocker.setEnabled(false, for: .ads)
        #expect(!blocker.blocksYouTubeAds(forHost: "www.youtube.com"))

        blocker.setEnabled(true, for: .ads)
        blocker.setDisabled(true, forHost: "www.youtube.com")
        #expect(!blocker.blocksYouTubeAds(forHost: "www.youtube.com"))
        #expect(blocker.blocksYouTubeAds(forHost: "example.com"))
    }
}
