# Contributing to Luna

Thanks for helping. This page is how to build Luna, how work is tracked, and the
rules a change has to meet. The rules for how the code itself is written —
buttons, toasts, motion, tokens, comments — are in [CLAUDE.md](CLAUDE.md); they
apply to people and AI agents alike.

## Build and run

You need macOS 26 and Xcode 26, and three tools from Homebrew:

```sh
brew install xcodegen swiftlint
make gen    # generates Luna.xcodeproj from project.yml
make run    # builds and opens Luna
```

Run `make gen` again whenever you add or remove a file: `Luna.xcodeproj` is
generated and not committed. The other targets:

| Command | What it does |
|---|---|
| `make build` | Debug build |
| `make test` | the app's tests (XCTest) |
| `cd BrowserKit && swift test` | the engine package's tests |
| `make lint` | SwiftLint in strict mode: a warning fails it |
| `make check` | lint, plus the checks that BrowserKit has no AppKit and the Command Bar stays offline |
| `make signed` | a Developer ID build with the iCloud entitlements (needs the certificate and `Config/Signing/Luna_Developer_ID.provisionprofile`) |
| `make dmg` | the disk image, from the Release build |

A direct `xcodebuild` must pass `-derivedDataPath DerivedData`.

## How work is tracked

Everything to do is a GitHub issue, and every issue is on the
[Luna project board](https://github.com/users/ziadmyassine/projects/2): **Todo**, **In Progress**, **Done**.

- **Bugs** carry the `bug` label, new work `enhancement`, and every issue an
  `area:` label. `priority: top` marks the four top priorities; `later` is the
  v2 backlog, which is not started without a go-ahead.
- **Milestones** M0 to M6 group the issues into the order Luna is being built in.
- **Plan numbers.** Issues moved from the old `TODO.md` keep its numbers in their
  titles (`§6.4 Archive browser`, `§31.2 …`). A `§` number in a comment or a doc
  is one of these issues; search the issues for it.
- Open an issue before a large change, so the approach can be agreed first.

## Making a change

1. Branch from `main`, or work on `main` if you have push access and the change is small.
2. Keep one change per commit, and write the message as a plain sentence saying
   what the change does and why: *"Take two presses of Escape to leave fullscreen,
   and say so after the first"*. No prefixes, no ticket numbers in the subject;
   put `Fixes #123` in the body to close an issue.
3. Add or update tests. Logic without a test is not finished.
4. Run `make lint`, `make test` and the BrowserKit tests before you push. CI runs
   the same on every push and pull request (`.github/workflows/ci.yml`).
5. If the change is something a user can see, add a line to
   [CHANGELOG.md](CHANGELOG.md), and update the spec it touches in `docs/`.

## Ground rules

- **Never invent an API.** Every WebKit API named in the plan's issues has been verified to exist. If you need something not listed here, check `WKWebView.h` / `WKWebsiteDataStore.h` in the WebKit source (`github.com/WebKit/WebKit/tree/main/Source/WebKit/UIProcess/API/Cocoa`) *before* designing around it. Private/underscored SPI (`_WK*`) is **banned** unless a task explicitly authorises it, because it breaks on OS updates and blocks notarisation-free distribution debugging.
- **One issue = one change.** Each issue should land as a self-contained change with its own acceptance criteria met.
- **Do not skip the "Gotcha" boxes.** They are the results of research, not speculation; ignoring them is how this project dies at 60% complete.
- **Design tokens are law.** Everything visual references §8's token table. No raw hex values in view code.
- **Performance budget is law.** See §19. A browser that eats 12 GB with 40 tabs is a failed product regardless of how pretty the sidebar is.
- **Read the other browsers freely; ship Luna's own implementation (§33).** No limit on what you read — they are the fastest available answer to "how does WebKit actually behave here". The constraint is on the output: what lands in Luna must fit Luna's architecture, concurrency model and budgets, not theirs transplanted. Attribute anything verbatim.
- When a task says "match Arc", the acceptance criterion is *felt behaviour*, not pixel-identical copying. Do not clone Arc's exact artwork, icon set, wordmark, or copy strings — build our own visual identity on the same interaction skeleton.

## Definition of done

A task is done when: it builds warning-free under Swift 6 strict concurrency · it has tests where logic exists · it meets its stated acceptance criterion · it respects Reduce Motion / Increase Contrast / Reduce Transparency · it uses design tokens, never literals · it doesn't regress the §19.1 budgets · it works in light **and** dark · it's reachable by keyboard · it's in the menu bar if it's a user-facing command · and any new user-visible data handling is reflected in the Privacy Policy.

## Reporting security problems

Not in a public issue: see [SECURITY.md](SECURITY.md).
