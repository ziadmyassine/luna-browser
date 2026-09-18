# Settings — the visual and behavioural contract (§23.1)

Decided 2026-09-18. This document is the source of truth for the Settings
window; where it disagrees with §23.1's one-line sketch, this wins.

Three decisions were taken before any code:

1. **A separate native window**, not a `luna://` page and not a sheet. It is the
   only surface that can host `NSGlassEffectView`, so it is the only one that
   can look like the rest of Luna. A sheet was rejected because it blocks the
   window you are trying to preview a setting against.
2. **Sidebar list + detail pane**, with a search field above the list. Nine
   sections do not fit in a toolbar row, and the sidebar is already Luna's
   navigation language.
3. **All nine sections ship**, with the unbuilt ones visibly disabled and
   explained rather than hidden.

---

## 1. Shape

Everything is a `Tokens.Metric` value. No literal lengths.

**Correction:** an earlier draft of this line claimed `TokenCheck` fails the
build on a stray literal. It does not — it is `#if DEBUG || TOKENCHECK_MAIN`,
validates the token *table* at runtime, and never scans source. Nothing in the
repo greps for numeric literals. Using tokens is still the rule; it is just not
an enforced one, so it is on review to catch.

| Thing | Value |
|---|---|
| Window content | 720 × 520, resizable, min 640 × 420 |
| Window corner | `windowCornerRadius` (25) |
| Section list width | `settingsListWidth` (230), fixed (not `sidebarWidth`, which is user-dragged) |
| Section row **pitch** / pill radius | `settingsSectionRow` (34) / `rowCornerRadius` (12) |
| Section row pill height | pitch less `rowGap` (3) — the gap comes out of the row |
| Section icon tile | `settingsSectionIcon` (24, radius 7), no outline |
| Pane inset | `chromeGapWide` (16) |
| Card row height | `settingsCardRow` (48) |
| Card row inset (text grid) | `chromeGapWide` (16) |
| Gap between cards | `settingsGroupGap` (26); a note under a card, `chromeGap` (8) |
| Search field | `urlPill` height (34), `settingsFieldCorner` (10), no border |
| Nav capsule | `settingsNavCapsule` (64 × 30, radius 10) |
| Segment | `settingsSegment*` — height 28, radius 8, 14 pt either side of its word |
| Pushbutton | `settingsButtonHeight` (26), `settingsFieldCorner`, 11 pt inset |
| Row and section label face | `TypeScale.settingsRow` (15) |
| Group header | same face, `Text.secondary` |
| Symbol size | `faviconSize` (16) |

### 1.2 The controls, re-measured against the same reference

The shell was the reference's two columns before this pass; what sat inside it
was AppKit's defaults. Each of these is a delta that was visible side by side
with the screenshot, and none of them changes what a control *does*:

- **The nav capsule is one plate with two bare chevrons**, not a pill holding
  two circular `GlassButton`s. Three rounded shapes where the reference has one.
- **The search field is a rounded rectangle**, not a full-radius pill, and
  carries no border: the well is already a recess.
- **Popups are `isBordered = false`.** Six push bezels down a card turn the pane
  into a form on a grey background. The menu, the keyboard handling and the
  VoiceOver role are AppKit's still — only the bezel is gone.
- **`SettingsPushButton` replaces `.push`**, and **`SettingsTextField` replaces
  the bezelled field**: both are the row's own wash with `Surface.well` or
  `Surface.selected` under them. AppKit's push bezel is a near-white plate and
  its text field is a white box; either one is the brightest thing in the pane.
- **A segment is as wide as its word**, and an unselected one carries no
  outline. A fixed 140 pt made "Auto · Light · Dark" cross half the pane.
- **A row lays its control out with explicit constraints**, not a horizontal
  stack: a stack sent a switch to the card's trailing edge and left a
  `SettingsChoice` beside the label with the spare width spread between its
  segments.
- **A group header names something the rows do not.** Three of them repeated
  the title of the only row underneath and are gone; the rest are
  `Text.secondary`.
- **A key equivalent is a chip** (`SettingsKeyChip`), and a row that is only a
  sentence is still a row (`SettingsRow.status`) — a bare `NSTextField` in a
  card squashes it to one line of type against its own edge.

**Materials.** The section list is `Glass.apply(.sidebar, to:)` — the same
material as the browser sidebar, sampling the wallpaper, on a window that is
`isOpaque = false` with a clear background so there is something behind it to
sample. The detail pane is **opaque** (`Tokens.Surface.base`), exactly as the
content card is: a form is read, not looked through. Grouped control rows sit on
`Glass.backing(.control, cornerRadius: rowCornerRadius)`.

The window is titled "Luna Settings" with the title **hidden** and the titlebar
transparent over a `.fullSizeContentView`, so the glass column runs the full
height of the window and the traffic lights sit on it. It uses the standard
lights with no custom layout manager, and is **not** restorable into a browser
window.

### 1.1 The shape, re-measured against a reference

Martin's reference (Raycast's settings) is the same two-column window, and three
things in it are structural rather than decorative. All three are now Luna's:

- **A section row is a tile plus a word.** The symbol sits in a 26 pt rounded
  square drawn as a `Surface.well` recess — the same well the two search fields
  in the app sit in. A glyph loose beside a label reads as decoration; a tile
  reads as a place. The row is 36 pt and the label is 15 pt.
- **A card is one card.** Its rows butt together and are separated by a hairline
  that starts at the row's own text inset, not at the card's edge. Rows with a
  gap between them read as six small panels; ruled rows read as one group. The
  group's name sits above the card, indented to the same text inset, so every
  piece of type in the pane lines up on one edge.
- **There is no title over the pane.** It repeated, in 12 pt semibold, the word
  the user had just clicked two inches to the left. In its place is a
  back/forward capsule (`SettingsNavCapsule`) on the pane's top inset, level with
  the traffic lights across the divider, carrying the one thing the list cannot
  show: the order the sections were actually visited in.

---

## 2. Navigation

```
┌───────────────────────────────────────────────┐
│ ○ ○ ○                                         │
│ ┌──────────────┐ ┌──────────────────────────┐ │
│ │ [🔍 Search ] │ │  Privacy & Blocking      │ │
│ │ ⚙  General   │ │  ──────────────────────  │ │
│ │ ◐  Appearance│ │  ┌────────────────────┐  │ │
│ │ 🔒 Privacy   │ │  │ Block ads     [o=] │  │ │
│ │ 🔍 Search    │ │  │ Block trackers[o=] │  │ │
│ │ ⬇  Downloads │ │  │ Annoyances    [=o] │  │ │
│ │ ⌘  Shortcuts │ │  └────────────────────┘  │ │
│ │ ▦  Spaces    │ │                          │ │
│ │ 🧩 Extensions│ │                          │ │
│ │ ⚡ Advanced  │ │                          │ │
│ └──────────────┘ └──────────────────────────┘ │
└───────────────────────────────────────────────┘
```

- Exactly one section selected, always. Selection persists across launches
  (`settings.lastSection`).
- **The search field filters controls, not sections.** Typing "cookie" shows
  every section that contains a matching control, with the non-matching rows in
  it hidden and the match highlighted. This is the feature Firefox and Chrome
  have and Safari does not, and it is the single biggest usability win in a
  nine-section window.
- A section with no matches is dimmed in the list, not removed — removing rows
  makes the list jump under the pointer.
- `⌘,` opens the window; `⌘W` closes it; `⌘F` focuses the search field.
  `⌘1`…`⌘9` jump to a section.
- **Back and forward** walk the visited list. Picking a section after going back
  truncates whatever was ahead of the cursor, which is the rule a browser's own
  history has; a direction you cannot go is dimmed, never hidden, so the capsule
  does not change width while you use it.

---

## 3. Sections

A control is only listed here if it is **wired to working code**. Anything
listed as *disabled* renders as a normal row, dimmed, with a one-line reason
underneath — never a silently dead switch (§30.4).

### 3.1 General
| Control | Type | Wired to |
|---|---|---|
| Default browser | Button "Set as Default" + status line | `NSWorkspace.setDefaultApplication(at:toOpenURLsWithScheme:)` |
| On launch | Popup: Restore last session · New tab · Specific Space | `general.onLaunch` + `BrowserSession.restored` |
| Auto-archive tabs after | Popup: 6h · 12h · 24h · Never | **existing** `luna.autoArchiveHours` |
| Confirm before closing a window with multiple tabs | Toggle | `general.confirmClose` |

### 3.2 Appearance
| Control | Type | Wired to |
|---|---|---|
| Theme | Segmented: Auto · Light · Dark | `NSApp.appearance` |
| Optimise glass for this display | Segmented: Auto · On · Off | **§7 below** |
| Show tab favicons in the sidebar | Toggle | `SidebarIcons.favicon(for:)` — **not** the row model, which holds no image |
| Sidebar position | Segmented: Left · Right | *disabled* — right-hand sidebar is not built |

The glass row carries a **live preview tile** beside it: a 160 × 72 sample of
the real material, redrawn the instant the segment changes. On a 1× display the
difference is the whole point of the setting, so it must be visible without
closing the window.

### 3.3 Privacy & Blocking
| Control | Type | Wired to |
|---|---|---|
| Block ads | Toggle | `ContentBlocker.setEnabled(_:for: .ads)` |
| Block trackers | Toggle | `.trackers` |
| Block annoyances | Toggle | `.annoyances` |
| Filter list status | Static: rule count + last refresh + "Refresh Now" | `ContentBlocker.refresh(force: true)`, `onStatusChange` |
| HTTPS-Only Mode | Toggle | **existing** `blocking.httpsOnly` |
| Sites with blocking disabled | List + Remove | `isDisabled(forHost:)` / `setDisabled(_:forHost:)` |
| Clear all site data | Button, confirms first | `WKWebsiteDataStore` |

A plain paragraph states that Luna does **not** check URLs against a malware or
phishing list, and that macOS still applies XProtect and Gatekeeper (§17.7).
That copy is required, not optional.

### 3.4 Search
| Control | Type | Wired to |
|---|---|---|
| Search engine | Popup: DuckDuckGo · Google · Bing · Kagi · Custom | `CommandBarModel` — **currently hard-coded to DuckDuckGo**, must be lifted to a setting |
| Custom engine URL | Text field with `%s`, validated | same |
| Search suggestions | Toggle, **default off** | *disabled* until §9.6's suggest endpoint exists |

Default off matters: suggestions send every keystroke to a third party, and
D16 says we collect nothing. Shipping it on by default would contradict the
privacy policy we have already written.

### 3.5 Downloads
| Control | Type | Wired to |
|---|---|---|
| Save files to | Path popup + Choose… | `downloads.directory` — **currently hard-coded** to `.downloadsDirectory` |
| Ask where to save each file | Toggle | `downloads.askEachTime` |
| Open "safe" files after downloading | Toggle, **default off** | `downloads.autoOpen` |
| Clear download list | Popup: Manually · On quit · After a day | `downloads.clearPolicy` |

Auto-open defaults off on purpose. It is the setting Safari ships on and it is
the one most often named in macOS malware write-ups.

### 3.6 Shortcuts
Read-only table of every `MainMenu` command and its key equivalent, grouped by
menu, searchable. **Rebinding is disabled** with the reason "Custom shortcuts
are not implemented yet" — the key map is declared once in `MainMenu` (§22.5)
and making it editable is a separate piece of work.

### 3.7 Spaces & Profiles
| Control | Type | Wired to |
|---|---|---|
| Space list | Reorderable, rename, delete | `BrowserStore` |
| New Space | Button | `session.createSpace(name:)` |
| Profile per Space | Popup | `Profile` / `WKWebsiteDataStore(forIdentifier:)` |
| Delete a profile's data | Button, confirms | *disabled* — `BrowserStore` has no `delete(profileID:)` |

### 3.8 Extensions — **entirely disabled**
One centred explanation: Luna supports Safari Web Extensions, the plumbing is
not built yet (§16), and Chrome extensions will not all work (§26). A link to
the repo's compatibility notes. No fake list, no fake install button.

### 3.9 Advanced
| Control | Type | Wired to |
|---|---|---|
| User-agent | Popup: Default · Safari · Chrome · Custom | `WebViewFactory` UA string |
| Show Develop menu | Toggle | `MainMenu` |
| Enable Web Inspector | Toggle | `WKWebView.isInspectable` |
| Restore all settings to defaults | Button, confirms, requires the word to be typed | every key below |
| Reveal the database in Finder | Button | `NSWorkspace.activateFileViewerSelecting` |

---

## 4. Shared row widgets

Agent A owns these and publishes them before anyone builds a section. Every
section is assembled from them; no section hand-rolls a control.

```swift
@MainActor protocol SettingsSection: AnyObject {
    static var id: String { get }             // "privacy"
    static var title: String { get }          // "Privacy & Blocking"
    static var symbolName: String { get }     // SF Symbol
    var view: NSView { get }
    /// Every searchable label in this section, lowercased (§2's search).
    var searchIndex: [String] { get }
    /// Show only rows matching `query`; empty string restores all.
    func filter(_ query: String)
}

// Built by `SettingsRow`:
static func toggle(_ title: String, subtitle: String?, value: Bool,
                   isEnabled: Bool, disabledReason: String?,
                   onChange: @escaping (Bool) -> Void) -> NSView
static func segmented(_ title: String, options: [String], selected: Int, …) -> NSView
static func popup(_ title: String, options: [String], selected: Int, …) -> NSView
static func text(_ title: String, value: String, placeholder: String, …) -> NSView
static func button(_ title: String, action: String, isDestructive: Bool, …) -> NSView
static func note(_ markdownish: String) -> NSView          // the §17.7 paragraph
static func group(_ rows: [NSView]) -> NSView              // glass-backed card
```

A disabled row is **dimmed, still focusable, and still read by VoiceOver**,
with its reason as the accessibility help. A control nobody can explain is
worse than a missing one.

---

## 5. Motion

Reuses `Tokens.Motion`. Nothing new is invented.

| Moment | Token |
|---|---|
| Section change | `spaceSwitchCrossfade` on the detail pane |
| Row appears/hides under search | `rowHover` opacity, staggered by index, capped at 6 rows |
| Toggle flip | AppKit default — never re-animate a system control |
| Glass preview tile | `layoutSwitch` |
| Window open | `commandBarIn` scale + fade |

Under Reduce Motion every one of these becomes an instant swap. The pane still
changes; it just does not slide.

---

## 6. Persistence

All keys live on `UserDefaults.standard`, one flat namespace per domain, and
every one of them has a declared default in a single `SettingsDefaults` table
so "Restore all settings" is a loop rather than a list someone forgets to
update.

```
general.onLaunch            general.confirmClose
appearance.theme            appearance.glassOptimisation
appearance.showFavicons
search.engine               search.customEngineURL
downloads.directory         downloads.askEachTime
downloads.autoOpen          downloads.clearPolicy
advanced.userAgent          advanced.showDevelopMenu
advanced.webInspector       settings.lastSection
```

**Existing keys are not renamed**: `blocking.httpsOnly`, `blocking.*`,
`luna.autoArchiveHours`, `luna.activeSpaceID` stay where they are. The naming
is already inconsistent (`luna.` vs bare domain); unifying it is a migration,
not a settings-window job. Recorded as debt.

---

## 7. The 1× glass adaptation

**The problem, measured on this machine.** `system_profiler` reports
`Resolution: 1920 × 1080` and `UI Looks like: 1920 × 1080` — one point is one
physical pixel. Every accessibility reducer is off, so nothing is disabling the
effect; Liquid Glass is simply being rendered at a quarter of the pixel density
it was designed against. Three consequences, in order of how much they hurt:

1. The specular rim that makes glass read as glass is sub-point. At 2× it gets
   two physical pixels; at 1× it gets one, so it either vanishes or aliases.
2. The blurred backdrop has a quarter of the samples, so smooth falloff bands —
   worst in dark mode.
3. `Glass.Style.control` uses `NSGlassEffectView.Style.clear`, the most
   refraction-dependent variant, and it is used for the URL pill, the control
   circles and the row backing — the chrome that is on screen constantly.

**What the setting changes.** `NSGlassEffectView` exposes exactly three knobs:
`style`, `tintColor`, `cornerRadius`. So the adaptation is honest and small:

| | 2× (Retina) | 1× optimised |
|---|---|---|
| `.control` style | `.clear` | `.regular` |
| `.control` tint | none | `Tokens.Surface.glassTint` at reduced alpha |
| `.sidebar` / `.topBar` tint | `glassTint` | `glassTint` at **increased** alpha |

Nothing else changes. No new material, no hand-drawn fake glass, no blur
radius — that is not exposed and pretending otherwise would be inventing API.

**Detection, and the part that is easy to get wrong.** The scale factor is a
property of the **window's current screen**, not of the app. A window dragged
from a 1× display to a 2× one must re-resolve, so:

- read `window.backingScaleFactor`, never `NSScreen.main`;
- observe `NSWindow.didChangeBackingPropertiesNotification` **and**
  `NSApplication.didChangeScreenParametersNotification`;
- re-apply to every glass view on change, in one pass.

Setting is tri-state, default **Auto**:

- **Auto** — optimised when `backingScaleFactor < 2`, plain otherwise.
- **On** / **Off** — the user's override, respected on every display.

Stored in `appearance.glassOptimisation` as `auto` | `on` | `off`.

### 7.1 What it actually achieved — measured, and it is not a clean win

One window, one position, one backdrop, dark, 1×, only the setting flipped.
Luminance separation of each element against the bar behind it:

| | plain (`off`) | optimised (`on`) |
|---|---|---|
| URL pill vs bar | +6.07 | −8.19 |
| control circle vs bar | +7.12 | −3.24 |
| row backing vs bar | **+0.79** | **−16.03** |

- **The row backing is the real gain.** +0.8 of separation is invisible; −16 is
  not. This is the one place `.clear` genuinely fails at 1×.
- **The control circle is a regression** — 7.1 units of separation become 3.2.
- **Every control flips polarity**: raised on `.clear`, inset on `.regular`. No
  public knob turns that back; closing the gap needs Δalpha ≈ 0.32 on top of what
  the bar already carries, past the point it stops being glass.

So the setting is a **preference, not a fix**, which is why it is tri-state.

**Three things §7 above got wrong**, left in place because they were the frozen
contract the work was built against:

1. **"Increased tint alpha fixes the banding."** It does not. Across an alpha
   sweep the transmitted backdrop's standard deviation held at 6.85–7.20 — a
   ratio of 0.98–1.04. The banding fix comes entirely from `style`: `.regular`
   transmits sd ≈ 7.0 against `.clear`'s ≈ 17.7, a 2.5× reduction.
2. **"`.control` tint at reduced alpha restores the raised read."** It cannot.
3. **"The specular rim is the dominant cause."** Unconfirmed. The dominant
   measured effect is *transmission*, not rim: `.clear` passes 2.5× more backdrop
   structure. `.clear` controls at 1× are not invisible (+6 to +7 against the
   bar) — only the row backing is.

### 7.2 A finding bigger than this setting

`tintColor` **ignores hue on `.regular` glass.** Red, blue, yellow and white at
alpha 1.0 render byte-identically; only alpha is read, and it brightens linearly
at ≈ +25.3 luminance units per unit alpha. (`.clear` *does* honour the colour's
luminance, so this is style-specific.)

`Tokens.Surface.glassTint` documents itself as "a *plane* tint rather than ink —
deeper over a dark desktop, milkier over a light one", and flips white-on-light
to black-on-dark to achieve that. On `.regular` glass — which is every chrome
plane in Luna — that flip buys **nothing**. Someone should decide whether
`surfaceTintColor` is worth keeping for chrome planes at all. Recorded, not
acted on.

Two smaller measured notes: `NSGlassEffectView` **cannot be captured offscreen**
(`cacheDisplay` returns fully transparent), so every number here came from a real
screen capture; and `NSGlassEffectView.h` in MacOSX26.5.sdk has exactly four
properties — `contentView`, `cornerRadius`, `tintColor`, `style`. There is no
blur radius and no third style.

---

## 8. Accessibility

- Full keyboard: Tab walks rows, the section list is an `NSOutlineView`-style
  accessible list, `⌘F` reaches search from anywhere in the window.
- Every control has a label that reads without its visual context — "Block ads",
  not "Ads".
- Disabled rows keep their label and gain their reason as accessibility help.
- The glass preview tile is decorative and marked as such; the segmented
  control beside it carries the meaning.
- Contrast: all text clears §21.4 in both themes, checked by `TokenCheck`.

---

## 9. Deliberately not here

- **Sync** — no Developer ID certificate exists, so §31 cannot be built or
  tested. Not even a disabled row; it would imply a roadmap commitment.
- **Passwords** — §14.1 is a spike that has not run. The Settings window must
  not hint at a password manager that may never ship in this shape.
- **Per-site permissions** (camera, mic, location) — §17.8's chip UI is unbuilt,
  so there is no data to list yet.
- **Telemetry / usage reporting** — there is nothing to toggle. D16 says none is
  collected, and a switch labelled "off" implies an "on" exists.
