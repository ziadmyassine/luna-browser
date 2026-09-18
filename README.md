<div align="center">
  <img width="150" height="150" src="assets/icon/final/luna-icon-light.png" alt="Luna">
  <h1>Luna</h1>
  <p><strong>Browse the dark side.</strong></p>
  <p>A native WebKit browser for macOS.</p>
</div>
<br/>
<p align="center">
  <a href="https://www.apple.com/macos/"><img src="https://badgen.net/badge/macOS/26+/blue" alt="macOS 26+"></a>
  <a href="https://swift.org"><img src="https://badgen.net/badge/Swift/6.0/orange" alt="Swift 6.0"></a>
  <a href="https://developer.apple.com/documentation/webkit"><img src="https://badgen.net/badge/Engine/WebKit/purple" alt="WebKit"></a>
  <a href="TODO.md"><img src="https://badgen.net/badge/Status/in%20development/yellow" alt="Status: in development"></a>
</p>

## Overview

Luna is a macOS browser built on AppKit and WebKit. It favours a quiet, keyboard-driven
interface that stays out of the way over breadth of features, and it is built natively:
one `WKWebView` per tab, SQLite for history, and macOS 26's Liquid Glass for the chrome.

It builds and runs today. [`TODO.md`](TODO.md) remains the plan of record for everything
that is not built yet.

## Highlights

- **Native macOS chrome.** AppKit windows and sidebar, real Liquid Glass materials, and a
  `Clear` / `Opaque` setting for how much of the desktop comes through.
- **WebKit, one web view per tab.** Cold tabs hibernate and restore from their own
  session state, so a large window does not cost a large amount of memory.
- **Spaces and Profiles.** Named, coloured workspaces; a Profile is the real storage
  container behind them (`WKWebsiteDataStore(forIdentifier:)`), so logins can be kept
  genuinely separate rather than merely visually separate.
- **Pinned tiles and Today tabs.** Favourites are per Profile and go back to the link they
  were pinned at; Today tabs auto-archive and can be brought back with `⇧⌘T`.
- **Content blocking and privacy.** EasyList, EasyPrivacy and Fanboy Annoyance compiled to
  native `WKContentRuleList`s, plus HTTPS-Only mode, local-network blocking and per-site
  permissions.
- **Command Bar.** `⌘T` for URL, search, open tabs and ranked history in one input, with
  live suggestions.
- **Search you choose.** DuckDuckGo (default), Google, Bing, Kagi, or any custom `%s`
  template. Suggestions come only from engines that publish them — nothing is guessed.
- **Import from what you already use.** Safari, Arc, Dia, Chrome, Chromium, Brave, Edge,
  Vivaldi, Opera, Atlas and Helium.
- **Downloads, Picture in Picture, favicons, and `luna://` internal pages** that are
  themed like the rest of the app rather than dropped in from a template.
- **Accessibility is a first-class path.** Reduce Transparency, Increase Contrast and
  Reduce Motion each have a real design, not a degraded one.

## Quick start

```sh
git clone https://github.com/ziadmyassine/luna-browser.git
cd luna-browser
brew install xcodegen swiftlint swiftformat
make gen
make run
```

`make gen` writes `Luna.xcodeproj` from `project.yml`; `make run` builds Debug and
launches the app. To work in Xcode instead, `make gen && open Luna.xcodeproj`.

`swiftlint` and `swiftformat` are only needed for `make lint` / `make fmt`; `xcodegen` is
required for everything, because `Luna.xcodeproj` is generated and never committed.

## Development

| Command | |
|---|---|
| `make gen` | Regenerate `Luna.xcodeproj` from `project.yml` |
| `make build` | Debug build |
| `make run` | Build, re-register the bundle, and launch |
| `make test` | BrowserKit's suite, then the app's |
| `make lint` | SwiftLint, `--strict` |
| `make fmt` | SwiftFormat over the tree |
| `make check` | Lint plus the BrowserKit layering check |

- The app target is **`Luna`**; the unit-test target is **`LunaTests`**.
- **Project configuration lives in [`project.yml`](project.yml)** and is managed with
  XcodeGen. Run `make gen` after changing it — and after adding any file under `App/`,
  `UI/`, `Design/`, `Features/` or `Tests/`, since those paths are globbed. BrowserKit is
  an SPM package and needs no regeneration.
- Tests can also be run from Xcode with **Product ▸ Test**, or directly:

  ```sh
  swift test --package-path BrowserKit
  xcodebuild -project Luna.xcodeproj -scheme Luna -configuration Debug -derivedDataPath DerivedData test
  ```

### House rules

Four conventions carry more weight here than style preferences, because each one has
already prevented a class of bug:

1. **BrowserKit imports Foundation and WebKit, never AppKit.** It is the engine layer, and
   keeping it UI-free is what leaves an iOS companion possible. Enforced by
   `Tools/check-no-appkit.sh` (`make check`).
2. **No raw values in view code.** Metrics come from `Tokens.Metric`, type from
   `TypeScale`, motion from `Tokens.Motion`. `Design/Tokens.swift` is the only file that
   names a colour, and `Design/Glass*.swift` are the only files that touch
   `NSGlassEffectView`.
3. **Never invent an API.** Anything from WebKit or AppKit is verified against the
   installed SDK before it is designed around. A guessed API name spreading through the
   Design layer is the specific failure this rule exists to prevent.
4. **Files stay under 400 lines and 140 columns.** Long files get split along a real
   seam rather than truncated.

The design system checks itself: `Design/TokenCheck.swift` asserts contrast, resolution
and translucency invariants, and the test suite runs it.

## Repository

| Path | |
|---|---|
| `App/` | Delegate, main menu, commands |
| `UI/` | Window, sidebar, top bar, Command Bar, History |
| `Design/` | Tokens, type, motion, glass, and the token self-checks |
| `Features/` | Settings, Downloads, Import, Search, internal pages |
| `BrowserKit/` | The engine package — tabs, store, content blocking (no AppKit) |
| `Tests/`, `BrowserKit/Tests/` | The two suites |
| `Tools/` | Layering check and the performance harness |
| [`TODO.md`](TODO.md) | The full specification and plan of record |
| [`todo-board.html`](todo-board.html) | The same plan as a filterable board |
| `assets/icon/` | Icon sources and the exported `.icon` |
| `inspiration/` | Interface reference captures |

## Docs

- [UI specification](docs/UI-SPEC.md) — the build contract for the visual layer
- [Settings specification](docs/SETTINGS-SPEC.md) — the Settings window's contract
- [Spaces specification](docs/SPACES-SPEC.md) — Spaces, Profiles and the sidebar hierarchy
- [Performance](docs/PERF.md) — the budgets, measured rather than assumed, with the
  harness that re-measures them (`Tools/perf/run.sh`)

## Requirements

macOS 26+, Xcode 26+, Swift 6. Debug builds sign ad-hoc; no certificate is needed to run
locally. The App Sandbox is off on purpose — it blocks default-browser registration.

## License

Luna will be released under the **GNU General Public License v3.0 or later**.
The `LICENSE` file lands at publication.
