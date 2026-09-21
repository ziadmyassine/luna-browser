<div align="center">
  <img width="150" height="150" src="assets/icon/final/luna-icon-light.png" alt="Luna">
  <h1>Luna</h1>
  <p><strong>Browse the dark side.</strong></p>
</div>
<p align="center">
  <a href="https://www.apple.com/macos/"><img src="https://badgen.net/badge/macOS/26+/blue" alt="macOS 26+"></a>
  <a href="https://swift.org"><img src="https://badgen.net/badge/Swift/6.0/orange" alt="Swift 6.0"></a>
  <a href="https://developer.apple.com/documentation/webkit"><img src="https://badgen.net/badge/Engine/WebKit/purple" alt="WebKit"></a>
  <a href="TODO.md"><img src="https://badgen.net/badge/Status/in%20development/yellow" alt="Status: in development"></a>
  <a href="LICENSE"><img src="https://badgen.net/badge/License/GPL-3.0/green" alt="GPL-3.0"></a>
</p>

Luna is a macOS browser built with AppKit and WebKit — one `WKWebView` per tab, SQLite for
history, Liquid Glass for the chrome. It favours a quiet, keyboard-driven interface over
breadth of features.

## Highlights

- Native macOS chrome, with a real Liquid Glass sidebar
- Spaces and Profiles on separate storage containers, so logins stay separate
- Pinned tiles and auto-archiving Today tabs
- Content blocking, HTTPS-Only and per-site permissions
- Password autofill from the macOS Keychain, behind Touch ID — no vault of Luna's own
- Command Bar: URL, search, open tabs and history in one input
- Search engine customization, including custom `%s` templates
- Import from Safari, Arc, Chrome, Brave, Edge and seven more
- Reduce Transparency, Increase Contrast and Reduce Motion each designed, not degraded

## Quick start

```sh
git clone https://github.com/ziadmyassine/luna-browser.git
cd luna-browser
brew install xcodegen swiftlint swiftformat
make gen
make run
```

## Development

- Main app target: `Luna`; the engine package is `BrowserKit/` and imports no AppKit
- Project configuration is managed with `XcodeGen` in [`project.yml`](project.yml)
- Regenerate the project after adding a file with `make gen` — `Luna.xcodeproj` is not committed
- `make build`, `make test`, `make lint`, `make fmt`, or `open Luna.xcodeproj`

## Docs

- [TODO](TODO.md) — the full specification and plan of record
- [UI specification](docs/UI-SPEC.md)
- [Settings specification](docs/SETTINGS-SPEC.md)
- [Passwords & passkeys](docs/PASSWORDS.md) — what the Keychain and Apple's entitlements actually allow
- [Spaces specification](docs/SPACES-SPEC.md)
- [Performance](docs/PERF.md)

## License

[GPL-3.0-or-later](LICENSE). The source of every released build has to be available,
in-app updates included.
