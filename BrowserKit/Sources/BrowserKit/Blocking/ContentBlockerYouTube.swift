import Foundation
import WebKit

/// YouTube's in-player ads (§17.2), which are the one thing a rule list cannot reach.
///
/// Why this is a documented exception to D6. D6 chose `WKContentRuleList` over a
/// JS blocker and §17.3 chose `css-display-none` over runtime CSS, both for good
/// reasons that still hold everywhere else. They do not hold here, and the reason was
/// measured against the live site on 2026-09-20 rather than assumed:
///
/// - The ad and the video come down the same pipe. Every media segment on a watch
///   page is fetched from a session-specific `rr2---sn-q4fzene7.googlevideo.com`-style
///   host and appended into one `MediaSource` behind a single `blob:` URL on a
///   single `<video>` element. The ad's bytes and the video's bytes are the same
///   origin, the same host, the same element. A `url-filter` that matches the ad
///   matches the video; there is no rule that blocks one and not the other.
/// - The ad schedule is metadata, not a request. On a monetised watch page
///   `ytInitialPlayerResponse` carried `adPlacements` (1 × `adPlacementRenderer`),
///   `adSlots` (2 × `adSlotRenderer`) and `playerAds` (1 ×
///   `playerLegacyDesktopWatchAdsRenderer`) — inside the same JSON object as
///   `streamingData` and `videoDetails`. Nothing is fetched to schedule an ad. There is
///   no load to block, so `block` has nothing to act on.
///
/// So the only seam left is the one the page itself reads the schedule through, and
/// that is JavaScript. This is a narrow exception — the static ads (mastheads, in-feed
/// slots, the panel beside the player) stay on the native path in ``youTubeRules``,
/// where D6 and §17.3 still apply and there is still no flicker.
///
/// Why ``youTubeScript`` must be injected at `documentStart`, and why that is not a
/// preference. Measured the same day, by patching a live page from the console:
/// `JSON.parse` and `Response.prototype.text` replaced after YouTube's bundle has run
/// are never called — the bundle caches its own references on the way up, so a hook
/// installed late sees nothing (`parses: 0`, `rewrites: 0` against a response that
/// demonstrably carried `adPlacements`). At `documentStart` nothing of YouTube's has
/// run, so the reference it caches is ours. Late injection here does not degrade; it
/// does nothing at all.
extension ContentBlocker {

    // MARK: - The hosts

    /// The YouTube properties this covers, as `if-domain` entries.
    ///
    /// Each carries the `*` prefix §17.1's corrections call for: a bare `youtube.com`
    /// matches that host only, and the site the user is on is `www.youtube.com`.
    static let youTubeDomains = [
        "*youtube.com", "*youtube-nocookie.com", "*youtubekids.com", "*youtubeeducation.com"
    ]

    /// True when `host` is one of ``youTubeDomains`` — the suffix test the `*` prefix
    /// above means, spelled for Swift.
    ///
    /// Pure and `static` so the gate can be asserted without a web view.
    public static func isYouTube(host: String?) -> Bool {
        guard let host = normalise(host) else { return false }
        return youTubeDomains.contains { domain in
            let bare = String(domain.dropFirst())
            return host == bare || host.hasSuffix(".\(bare)")
        }
    }

    /// Whether YouTube's ads should be blocked on a page whose top-level host is `host`.
    ///
    /// Not its own setting. §3.3 offers "Block ads" and the site menu offers "not on
    /// this site"; a third switch meaning "…but also on YouTube" would be a question the
    /// user has already answered. So this is the `ads` category's answer, scoped to the
    /// site, and nothing more.
    ///
    /// It deliberately does not ask whether `host` is YouTube. A `youtube-nocookie`
    /// embed on someone else's page plays the same pre-roll out of the same player, and
    /// the top-level host there is the someone else. ``youTubeScript`` tests
    /// `location.hostname` in its own first two lines and returns from any frame that is
    /// not YouTube's, so the embed is covered and every other site pays one regular
    /// expression against a string it already has. ``apply(to:host:)`` is the caller
    /// that does add the `isYouTube` test, because a rule list is per-page and has no
    /// second chance to check.
    public func blocksYouTubeAds(forHost host: String?) -> Bool {
        isEnabled(.ads) && !isDisabled(forHost: host)
    }

    // MARK: - The static ads, on the native path (§17.3)

    public static let youTubeIdentifier = "\(prefix)youtube-1"

    /// The renderers YouTube wraps a static ad in. Element names, because that is how
    /// Polymer builds the page — `ytd-ad-slot-renderer` is the ad, not a class on it.
    ///
    /// `ytd-rich-item-renderer:has(ytd-ad-slot-renderer)` takes the grid cell with it;
    /// without it the home feed keeps a cell-shaped hole where the ad was. `:has()` is
    /// real CSS and WebKit ships it — see `FilterListConverter.unsupportedSelectorTokens`,
    /// which deliberately does not list it.
    static let youTubeAdSelectors = [
        "ytd-ad-slot-renderer",
        "ytd-in-feed-ad-layout-renderer",
        "ytd-display-ad-renderer",
        "ytd-promoted-sparkles-web-renderer",
        "ytd-promoted-sparkles-text-search-renderer",
        "ytd-promoted-video-renderer",
        "ytd-compact-promoted-video-renderer",
        "ytd-search-pyv-renderer",
        "ytd-video-masthead-ad-v3-renderer",
        "ytd-video-masthead-ad-advertiser-info-renderer",
        "ytd-primetime-promo-renderer",
        "ytd-statement-banner-renderer",
        "ytd-banner-promo-renderer",
        "ytd-brand-video-shelf-renderer",
        "ytd-brand-video-singleton-renderer",
        // Observed on a live watch page on 2026-09-20 at `flex`/0px — it renders
        // nothing today, and it is named for what it is, so it is listed before it
        // starts to.
        "ytd-ads-engagement-panel-content-renderer",
        "ytm-promoted-video-renderer",
        "ytm-promoted-sparkles-web-renderer",
        "ytd-rich-item-renderer:has(ytd-ad-slot-renderer)",
        "ytd-rich-section-renderer:has(ytd-statement-banner-renderer)",
        "#masthead-ad",
        "#player-ads",
        "#panels-full-bleed-container ytd-engagement-panel-section-list-renderer[target-id='engagement-panel-ads']"
    ]

    /// The rule list, as WebKit's JSON. One `css-display-none` per selector, each scoped
    /// to ``youTubeDomains`` so nothing here can affect another site.
    ///
    /// `public` for the same reason ``localNetworkRules`` is: the compile is a
    /// fire-and-forget `Task`, so a selector WebKit refuses would leave the list nil and
    /// fail in complete silence. A test hands this to `compileContentRuleList` and finds
    /// out instead.
    public static var youTubeRules: String {
        let rules = youTubeAdSelectors.map { selector in
            ContentRule(
                trigger: .init(urlFilter: ".*", ifDomain: youTubeDomains),
                action: .hide(selector)
            )
        }
        guard let data = try? JSONEncoder().encode(rules),
              let json = String(bytes: data, encoding: .utf8) else { return "[]" }
        return json
    }

    /// Compiles the list, or finds the one already compiled. Called from ``start``.
    ///
    /// Twenty-odd rules, so it is compiled on the spot rather than cached against a
    /// content hash — the same call ``prepareLocalNetworkList()`` makes, and for the
    /// same reason: §17.1's 2.9 s belongs to the 80,000-rule filter lists, not to this.
    func prepareYouTubeList() async {
        if let existing = try? await ruleListStore.contentRuleList(forIdentifier: Self.youTubeIdentifier) {
            youTubeList = existing
            return
        }
        youTubeList = try? await ruleListStore.compileContentRuleList(
            forIdentifier: Self.youTubeIdentifier,
            encodedContentRuleList: Self.youTubeRules
        )
    }

    // MARK: - The in-player ads, on the only seam there is

    /// The name the page posts through when it has burnt an ad, so §17.4's badge counts
    /// one. Separate from ``blockedMessageName`` because that count is a heuristic over
    /// failed sub-resource loads and this one is not a load at all.
    public static let youTubeMessageName = "lunaYouTube"

    /// What every YouTube frame runs before YouTube does.
    ///
    /// Three layers, in the order they get a chance to act:
    ///
    /// 1. The schedule. `ytInitialPlayerResponse` is assigned by an inline script on
    ///    a cold load and is taken through a property trap; an SPA navigation fetches
    ///    `/youtubei/v1/get_watch` — measured, and note that it is no longer `/player` —
    ///    and is taken at every transport the body could be read through. Both end in
    ///    ``scrub``, which deletes `adPlacements`, `adSlots` and `playerAds` so the
    ///    player is never told there is an ad to play.
    /// 2. The feed. The same scrub drops `adSlotRenderer`-shaped items out of the
    ///    lists they arrive in, so the grid closes up rather than leaving the gap
    ///    ``youTubeRules`` would hide.
    /// 3. The fallback. A server-stitched ad that gets past both still lands in the
    ///    one `<video>` element, and YouTube marks it by putting `ad-showing` on
    ///    `#movie_player` (measured: the class is present for exactly the ad and absent
    ///    for the content). Skip it if there is a skip button, seek past it if there is
    ///    not.
    ///
    /// The mute is restored, and that is not a detail. The ad and the video are the
    /// same element, so muting for the seek and forgetting would hand the user a silent
    /// video. `mutedByUs` exists only to put it back, and only if we were the ones who
    /// took it.
    public static let youTubeScript = """
    (function () {
      'use strict';
      if (!/(^|\\.)(youtube\\.com|youtube-nocookie\\.com|youtubekids\\.com|youtubeeducation\\.com)$/
            .test(location.hostname)) { return; }

      var burnt = 0;
      function report() {
        var handler = window.webkit && window.webkit.messageHandlers
          && window.webkit.messageHandlers.lunaYouTube;
        if (handler) { handler.postMessage({ count: ++burnt }); }
      }

      // Keys whose whole value is an ad schedule, and renderers that are an ad item.
      var AD_KEYS = {
        adPlacements: 1, adSlots: 1, playerAds: 1, adBreakHeartbeatParams: 1,
        adEngagementPanels: 1, adServingDataEntity: 1, importantForAds: 1
      };
      var AD_RENDERERS = {
        adSlotRenderer: 1, displayAdRenderer: 1, promotedSparklesWebRenderer: 1,
        promotedSparklesTextSearchRenderer: 1, promotedVideoRenderer: 1,
        compactPromotedVideoRenderer: 1, searchPyvRenderer: 1, adVideoRenderer: 1,
        inFeedAdLayoutRenderer: 1, bannerPromoRenderer: 1, statementBannerRenderer: 1,
        playerLegacyDesktopWatchAdsRenderer: 1, adsEngagementPanelRenderer: 1,
        mealbarPromoRenderer: 1, videoMastheadAdV3Renderer: 1, brandVideoShelfRenderer: 1,
        brandVideoSingletonRenderer: 1
      };

      function isAdItem(value) {
        if (!value || typeof value !== 'object') { return false; }
        for (var key in value) {
          if (Object.prototype.hasOwnProperty.call(value, key) && AD_RENDERERS[key]) { return true; }
        }
        return false;
      }

      // Depth-capped rather than unbounded: these responses are megabytes of nesting and
      // a walk that runs away is a hang on the page's own critical path.
      function scrub(value, depth) {
        if (!value || typeof value !== 'object' || depth > 16) { return value; }
        if (Array.isArray(value)) {
          for (var i = value.length - 1; i >= 0; i--) {
            if (isAdItem(value[i])) { value.splice(i, 1); } else { scrub(value[i], depth + 1); }
          }
          return value;
        }
        for (var key in value) {
          if (!Object.prototype.hasOwnProperty.call(value, key)) { continue; }
          if (AD_KEYS[key]) { delete value[key]; } else { scrub(value[key], depth + 1); }
        }
        return value;
      }

      // The cheap gate. Walking a response that mentions no ad at all is pure cost, and
      // most of them do not — a string search over the raw text is orders of magnitude
      // less work than parsing and re-serialising it.
      var MENTIONS_AD = /"(adPlacements|adSlots|playerAds|adSlotRenderer|displayAdRenderer|promoted[A-Za-z]*Renderer)"/;

      function scrubText(text, url) {
        if (typeof text !== 'string') { return text; }
        if (!/youtubei\\/v1\\//.test(url || '') || !MENTIONS_AD.test(text)) { return text; }
        try {
          var rewritten = JSON.stringify(scrub(JSON.parse(text), 0));
          report();
          return rewritten;
        } catch (error) { return text; }
      }

      // Each hook goes in behind its own guard. They are independent — the inline
      // assignment and the SPA fetch are different paths — so one that cannot be
      // installed must not take the others down with it, exactly as
      // `TabController.isolated` keeps the document-end scripts apart.
      function install(name, apply) { try { apply(); } catch (error) {} }

      // 1a. The inline assignment on a cold load. `configurable: true` so YouTube's own
      // code can still redefine it if it ever wants to — we are first, not exclusive.
      ['ytInitialPlayerResponse', 'ytInitialData'].forEach(function (name) {
        install(name, function () {
          var stored = window[name];
          Object.defineProperty(window, name, {
            configurable: true,
            get: function () { return stored; },
            set: function (value) { stored = scrub(value, 0); if (value) { report(); } }
          });
        });
      });

      // 1b. Every transport the SPA body could be read through. Measured today it is
      // `fetch` + `Response.prototype.text`, and it was `/youtubei/v1/player` + XHR
      // before that, so all of them are taken: the cost of covering one too many is a
      // function call, and the cost of covering one too few is an ad.
      install('JSON.parse', function () {
        var nativeParse = JSON.parse;
        JSON.parse = function (text, reviver) {
          var parsed = nativeParse.call(this, text, reviver);
          return typeof text === 'string' && MENTIONS_AD.test(text) ? scrub(parsed, 0) : parsed;
        };
      });

      install('Response.text', function () {
        var nativeText = Response.prototype.text;
        Response.prototype.text = function () {
          var url = this.url;
          return nativeText.apply(this, arguments).then(function (text) { return scrubText(text, url); });
        };
      });

      install('Response.json', function () {
        var nativeJSON = Response.prototype.json;
        Response.prototype.json = function () {
          var url = this.url;
          return nativeJSON.apply(this, arguments).then(function (body) {
            return /youtubei\\/v1\\//.test(url || '') ? scrub(body, 0) : body;
          });
        };
      });

      install('XMLHttpRequest.open', function () {
        var nativeOpen = XMLHttpRequest.prototype.open;
        XMLHttpRequest.prototype.open = function (method, url) {
          if (/youtubei\\/v1\\//.test(String(url))) {
            this.addEventListener('readystatechange', function () {
              if (this.readyState !== 4 || this.responseType !== '' && this.responseType !== 'text') { return; }
              var scrubbed = scrubText(this.responseText, String(url));
              if (scrubbed === this.responseText) { return; }
              try {
                Object.defineProperty(this, 'responseText', { value: scrubbed, configurable: true });
                Object.defineProperty(this, 'response', { value: scrubbed, configurable: true });
              } catch (error) {}
            });
          }
          return nativeOpen.apply(this, arguments);
        };
      });

      // 3. The fallback, for an ad the player was handed anyway.
      var mutedByUs = false;

      function burnAd() {
        var player = document.getElementById('movie_player');
        if (!player) { return; }
        var video = player.querySelector('video.html5-main-video');
        if (!player.classList.contains('ad-showing')) {
          // Give the sound back the moment the ad is over — same element, same `muted`.
          if (mutedByUs && video) { video.muted = false; mutedByUs = false; }
          return;
        }
        var skip = player.querySelector(
          '.ytp-ad-skip-button-modern, .ytp-ad-skip-button, .ytp-skip-ad-button, ' +
          '.ytp-ad-skip-button-container button'
        );
        if (skip) { skip.click(); report(); return; }
        if (video && isFinite(video.duration) && video.duration > 0) {
          if (!video.muted) { video.muted = true; mutedByUs = true; }
          // Not `duration` exactly: seeking to the very end can leave the player waiting
          // on an `ended` that a clamped seek never fires.
          if (video.currentTime < video.duration - 0.1) {
            video.currentTime = video.duration - 0.1;
            report();
          }
          if (video.paused) { var played = video.play(); if (played) { played.catch(function () {}); } }
        }
        var close = player.querySelector('.ytp-ad-overlay-close-button, .ytp-ad-overlay-close-container');
        if (close) { close.click(); }
      }

      // The "Ad blockers violate YouTube's Terms of Service" modal stops playback
      // outright, so leaving it would ship a feature that makes the site *less* usable
      // than not having it.
      function dismissEnforcement() {
        var message = document.querySelector('ytd-enforcement-message-view-model');
        if (!message) { return; }
        var dialog = message.closest('tp-yt-paper-dialog, ytd-popup-container tp-yt-paper-dialog');
        if (dialog) { dialog.remove(); } else { message.remove(); }
        document.querySelectorAll('tp-yt-iron-overlay-backdrop').forEach(function (node) { node.remove(); });
        var video = document.querySelector('video.html5-main-video');
        if (video && video.paused) { var played = video.play(); if (played) { played.catch(function () {}); } }
      }

      // 250 ms: a `getElementById` and a `classList` test, which is nothing, against an
      // unskippable ad that is five seconds long. A `MutationObserver` on the player
      // fires hundreds of times a second during playback and would cost more.
      install('player watch', function () {
        setInterval(function () { try { burnAd(); dismissEnforcement(); } catch (error) {} }, 250);
      });
    })();
    """
}
