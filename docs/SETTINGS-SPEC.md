# Settings — the visual and behavioural contract (§23.1)

Decided 2026-09-18. This document is the source of truth for the Settings
window; where it disagrees with §23.1's one-line sketch, this wins.

Three decisions were taken before any code:

1. **A native window**, not a `luna://` page and not a sheet. It is the
   only surface that can host `NSGlassEffectView`, so it is the only one that
   can look like the rest of Luna. A sheet was rejected because it blocks the
   window you are trying to preview a setting against.
   *Amended 2026-09-23:* not a free-standing one either. It is a child of the
   browser window it was opened from — centred over it, moving with it, and
   going into its fullscreen Space instead of opening on the desktop. Asked for
   from another window, it moves there; that window closing closes it. It has no
   minimise light of its own, because it goes to the Dock with its window.
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
| Window content | 720 × 560, resizable, min 640 × 520 (the floor holds §2's eleven rows) |
| Window corner | `windowCornerRadius` (25) |
| Section list width | `settingsListWidth` (230), fixed (not `sidebarWidth`, which is user-dragged) |
| Type | `TypeScale.settingsRow` — **13 pt, the sidebar's own face** |
| Caption under a row | `TypeScale.settingsCaption` (11) |
| Every control in the pane | `settingsControl` (28) high, `settingsControlCorner` (8) |
| Section row **pitch** / pill radius | `rowHeight` (38) / `rowCornerRadius` (12) — the sidebar's |
| Section row pill height | `rowPillHeight` (35): the pitch less `rowGap`, which comes out of the row |
| Section row glyph / title column | `rowFaviconInset` (17.5) / `rowTitleInset` (42.5) — the sidebar's |
| Section icon tile | **none.** See §2.1 |
| Pane inset | `chromeGapWide` (16) |
| Card row height | `settingsCardRow` (44) |
| Card row inset (text grid) | `chromeGapWide` (16) |
| Gap between cards | `settingsGroupGap` (24); one of a run of like cards, `settingsListGap` (12); a note under a card, `chromeGap` (8) |
| Search field | `urlPill`, exactly as `HistoryFilterField` draws it |
| Nav capsule | `settingsNavCapsule` (64 × 30, radius 10) |
| Group header | the row's face, `Text.secondary`, **flush with the card's edge** |
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
- **A key equivalent is a chip** (`SettingsKeyChip`) when it is a control and
  flat type when it is not (§3.6), and a row that is only a sentence is still a
  row (`SettingsRow.status`) — a bare `NSTextField` in a card squashes it to one
  line of type against its own edge.

### 1.3 The second pass

- **The type is the sidebar's**, 13 pt, not 15. A form set two points larger
  than the window behind it reads as a different app.
- **One height and one corner for every control** — `settingsControl` (28) and
  `settingsControlCorner` (8) — the way the browser's chrome standardises on
  `capsuleHeight` and `controlCircle`. A window where each control picked its
  own size read as a form, not as Luna.
- **Nothing on the right is glass** (see Materials above).
- **The search field is the browser's**, `urlPill` and all, rather than a
  near-miss of it.
- **The accent focus ring is suppressed unless focus arrived from a key press.**
  §4 keeps disabled rows in the key loop, so AppKit made the first one the
  window's initial responder and drew a blue halo round a dimmed row. `⌘,` now
  lands on the search field, and the ring returns on `Tab`.


**Materials — and there is exactly one.** The section list is
`Glass.apply(.sidebar, to:)`, the same material as the browser sidebar, on a
window that is `isOpaque = false` so there is something behind it to sample.
Everything on the right is **flat**: the pane is `Surface.base`, a card is
`Surface.raised` with `Line.border`, and a control is `Surface.well` (dormant)
or `Surface.selected` (chosen) — the same three planes the browser's chrome
uses.

Cards were `Glass.backing(.control,…)` for one build and it is a mistake worth
recording: the pane under them is opaque, so a material there has nothing to
refract, and nine of them stacked down a form turned the whole window into
something to look at rather than to read. Glass earns its place where there is a
desktop behind it. On a form there is not.

The window is titled "Luna Settings" with the title **hidden** and the titlebar
transparent over a `.fullSizeContentView`, so the glass column runs the full
height of the window and the traffic lights sit on it. It is **not** restorable
into a browser window.

Its root view is `WindowRootView` — the browser window's own — so the two windows
are cut to the same 25 pt corner. It wore the system's before, which is rounder,
and one app with two window shapes is a difference you see without being able to
name it. And `TrafficLightLayoutManager` — §7.7's single owner of a window
button's frame — puts the lights at `trafficLightInset` here too, which the
column above was already laid out from: the search field clears that number, and
until the lights were moved to meet it they sat at AppKit's own 9 pt and the two
disagreed.

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
  group's name sits above the card **on the card's own edge**, not on the rows'
  text inset: it labels the card, and a name indented under nothing reads as a
  row of the card above it rather than as the title of the one below. §3.7's
  `Spaces … [New Space]` is the same line with a control on the far edge, so
  the pair frames its cards.
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
│ │ ⋰ Luna Ctrl  │ │                          │ │
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

### 2.1 The list is the browser's sidebar

Not "like" it: the same views, the same tokens, the same springs. §2's rows are
laid out on `rowHeight` / `rowPillHeight` / `rowGap`, their glyph and title stand
on `rowFaviconInset` and `rowTitleInset`, and the two fills are `RowPillView` —
§3.4's **glass** pills, one selected and one hover, moved between rows on
`selectedRowMove` and `rowHover` by `RowPillView.move(to:spec:)`, which both
lists now share. A section row itself draws nothing at all.

Three things it stopped doing, all of them Martin's report that Settings did not
look like the app:

- **The selected row was a flat `Surface.selected` wash** painted on the row's
  own layer. Over the column's glass that is a grey band; the sidebar's answer
  is clear glass *plus* that wash, which is why a selected tab reads as a raised
  surface. It is the same class now, so it cannot drift again.
- **Every glyph sat on a 24 pt rounded square** carrying `Surface.selected`. Ten
  of them turned a list of places into a row of buttons, and put a
  selected-looking shape on nine rows that were not selected. Gone; the symbol
  sits on the column, 16 pt, like a favicon.
- **The pitch was 34 pt around a 31 pt pill.** It is the sidebar's 38 around 35.
  Ten rows are 40 pt taller for it, which is why §1's height floor moved from
  420 to 480 — at 420 the list ran past the bottom of the column it is
  constrained inside.

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
| Ask before quitting Luna | Toggle | `general.confirmQuit` — read by `AppDelegate.applicationShouldTerminate` |

> **Added: the quit guard, and it is the only row in this card with a reader.**
> ⌘Q is next to ⌘W and takes every window with it. The toggle defaults **on**, and §3.1's
> sheet (UI-SPEC §5.2) carries its own way off — *Quit, and don't ask again* writes
> `general.confirmQuit = false`. A preference you can only turn **off** from a dialog is a trap,
> which is why it is also here.

### 3.2 Appearance
| Control | Type | Wired to |
|---|---|---|
| Theme | Segmented: Auto · Light · Dark | `NSApp.appearance` |
| Layout | Segmented: Sidebar · Top bar | `Settings.chromeLayout` — UI-SPEC §3 vs §4 |
| Search bar | Segmented: In the sidebar · On the page | `Settings.searchBarPlacement` — UI-SPEC §3.2b |
| Material | Segmented: Clear · Opaque | `Glass.density` — UI-SPEC §2a |
| Optimise glass for this display | Segmented: Auto · On · Off | **§7 below** |
| Sidebar position | Segmented: Left · Right | *disabled* — right-hand sidebar is not built |

**Favicons are no longer a row.** A switch for them was listed here; the sidebar
has drawn them since M1, every browser draws them, and a preference whose only
honest default is "on" is one more row to read past.

**"Search bar" is gone under the top bar, not dimmed.** §4 has one place for an
address and the tab strip is built around it, so under that layout this is not a
question with a greyed-out answer — it is not a question. A dimmed row is for a
control that has an answer Luna cannot honour yet; this one has none to have.
Under the sidebar it moves UI-SPEC §3.2's pill — and §3.1's back, reload and sidebar
toggle with it — onto the top of the page, where it collapses to the domain as
the page scrolls. The two keys resolve to one answer in
`Settings.searchBarIsOnPage`, so the sidebar cannot drop its pill in a layout
with no page bar to put it in.

The glass rows carry a **live preview tile** below them: a 160 × 72 sample of
the real material, redrawn the instant either segment changes. On a 1× display
the difference is the whole point of the setting, so it must be visible without
closing the window.

**Material is above "Optimise glass" because it is the bigger of the two.** It
changes how much of the desktop reaches the eye through every chrome surface in
the app; the row below it changes how one material is rendered on one class of
display. Both re-skin every live surface in one pass and neither needs a
relaunch. UI-SPEC §2a has the alphas and the measurement they come from.

### 3.3 Privacy & Blocking
| Control | Type | Wired to |
|---|---|---|
| Block ads | Toggle | `ContentBlocker.setEnabled(_:for: .ads)` |
| Block trackers | Toggle | `.trackers` |
| Block annoyances | Toggle | `.annoyances` |
| Filter list status | Static: rule count + last refresh + "Refresh Now" | `ContentBlocker.refresh(force: true)`, `onStatusChange` |
| HTTPS-Only Mode | Toggle | **existing** `blocking.httpsOnly` |
| Clear all site data | Button, confirms first | `WKWebsiteDataStore` |

**The per-site exemption list is not here.** "Sites with blocking disabled" was
a list you could only ever *remove* from — there was no way to turn blocking off
for a site from it — sitting a window away from the page the answer is about.
Per-site answers now live in exactly one place, UI-SPEC §3.2a's site menu behind
the sliders glyph on the address pill, which is where the problem is noticed and
where the same menu also clears that site's cache and cookies. What stays in this
section is what is genuinely global: which filter lists run at all, HTTPS-Only,
and clearing everything. A one-sentence note under the filter-list card says
where the switch went; a sentence is not a second copy of the control.

A plain paragraph states that Luna does **not** check URLs against a malware or
phishing list, and that macOS still applies XProtect and Gatekeeper (§17.7).
That copy is required, not optional.

### 3.3a Passwords
| Control | Type | Wired to |
|---|---|---|
| Offer to fill passwords | Toggle | `PasswordSettings.isEnabled` |
| Offer to save passwords | Toggle | `PasswordSettings.offersToSave` |
| Suggest strong passwords | Toggle | `PasswordSettings.offersGeneratedPasswords` |
| Require Touch ID to fill | Toggle, **on by default** | `PasswordSettings.requiresAuthentication` |
| Saved to | Status line | `CredentialStore.refreshCapability()`, re-probed on open |
| Passkeys | Toggle, **disabled**, with its reason | `PasskeySupport.isAvailable` |
| Manage saved passwords | Button "Open Passwords…" | the Passwords app |

Two notes carry copy that is **required, not decorative** — the same standing as
§17.7's Safe Browsing paragraph:

1. Luna has no vault of its own; everything goes into Apple's Keychain, and
   there is no Luna account or server.
2. Luna **cannot read** what Safari and the Passwords app already saved. Those
   are in Apple's own keychain access groups and no setting changes that. An
   empty list must never read as "you have no saved passwords". The same is true
   of credentials other applications put in the keychain — `git`'s, for one.
   Luna sees only its own (`docs/PASSWORDS.md` §5a).

The Touch ID row is the one place §14 chooses friction, and it is on by default
because a saved password is otherwise readable by anyone at an unlocked Mac. Its
subtitle names the fallback — "Touch ID, or your login password" — so a Mac with
no Touch ID does not read the row as one that does nothing for them.

The passkey row is the §30.4 case done properly: dimmed, still focusable, still
read by VoiceOver, with the real reason — an entitlement only Apple can grant —
as its accessibility help. It flips to enabled on its own when the entitlement
arrives, because it is rendered from the live process entitlement rather than a
build flag.

**Not here, and said so rather than half-built:** addresses and payment-card
autofill (§14.8 puts them out of scope), and any editor for saved passwords —
the Passwords app is where they live, and a second place to change one is a
second place for it to be wrong.

### 3.4 Search
| Control | Type | Wired to |
|---|---|---|
| Search engine | Popup: DuckDuckGo · Google · Bing · Kagi · Custom | `CommandBarModel` — **currently hard-coded to DuckDuckGo**, must be lifted to a setting |
| Custom engine URL | Text field with `%s`, validated | same |
| Search suggestions | Toggle, **default off** | *disabled* until §9.6's suggest endpoint exists |
| Settings in search results | Toggle, **default on** | `search.settingsResults` |
| Shortcuts in search results | Toggle, **default on** | `search.shortcutResults` |

Default off matters: suggestions send every keystroke to a third party, and
D16 says we collect nothing. Shipping it on by default would contradict the
privacy policy we have already written.

**Settings in search results defaults on, and that is the opposite argument.**
Type a section's name into the Command Bar and the section is offered, with
its own symbol and `Open in Settings` under it — `SettingsResults`, ranked
below every page and above the search row. The index is the ten titles in
`SettingsSectionRegistry` plus a handful of keywords each (`static var
keywords` on the section, deliberately not its instance `searchIndex`, which
cannot be read without building all ten panes). It is compiled in, so nothing
leaves the Mac for it and the privacy argument above simply does not apply.
The switch is there for anyone who wants the bar to answer with pages and
nothing else.

**Shortcuts in search results is the same argument and a separate switch**, for
§3.6's menu commands — see `ShortcutResults` and the note under §3.6. Two
switches rather than one because the two rows do different things: a settings
row opens a pane to go and read, a shortcut row does something to the page in
front of you, and wanting one of those in an address bar is no reason to want
the other.

**A keyword is a weaker claim than a name.** Both kinds of row sit above the
search row when the query matched their own title, and *below* it when only a
keyword matched — `CommandBarSource.keywordSettings` and `.keywordShortcut`.
`google` is a keyword of this section and also the name of a website, and it
was taking the top row from the search: a word the user cannot see on the row
must not outrank the word they typed. `downloads` still opens the pane, being
a name; `cookies` searches the web first and offers Privacy & Blocking
underneath.

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
A table of every `MainMenu` command and its key equivalent, read by walking
`NSApplication.mainMenu`, grouped by menu, searchable — and editable wherever
the command is Luna's to move. A row is joined to its `BrowserCommand` **by
selector**, the one thing a live menu item and the command table cannot disagree
about; the key map is still declared once, in `BrowserCommand`, and rebinding
rebuilds the whole bar (`MainMenu.rebuild`) because a live menu item silently
refuses a new ⌘-number.

**Every command in the table is also reachable from the Command Bar.** Type its
name — or something near it: "copy link" finds Copy URL — and the row carries
the command's symbol and the keystroke it wears right now, so the bar is where
a shortcut is learned as well as where a command is run. The symbol on
`BrowserCommand` is what marks a command as belonging there; the ones without
one are macOS's (Undo, Cut, Minimize) or are already answered elsewhere in the
list. Each row is checked against the responder chain when the bar opens, the
same question a menu asks before it opens, so Back with nothing behind it is
not offered. See `ShortcutResults`.

**Which rows are editable is carried by the drawing, not by a sentence.** An
editable shortcut sits in a box — `SettingsShortcutRecorder`, a well with a
hairline and a pointing-hand cursor — and clicking it records the next
keystroke; Escape cancels, Delete clears, and a keystroke with no ⌘/⌃/⌥ is
refused. A shortcut that cannot be moved is printed flat (`SettingsKeyChip`,
`isFixed`) and says nothing more — with one exception: the numbered families,
which are built per session rather than from the table and would otherwise be
taken for macOS's, carry "Numbered from your sidebar" and "Numbered from your
Spaces". A legend above the table states the rule, and search matches
"editable" and "cannot be changed".

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

### 3.10 Luna Control
Listed between Extensions and Advanced in §2: both it and Extensions are about what else
gets into the browser. [LUNA-CONTROL.md](LUNA-CONTROL.md) has the protocol.

| Control | Type | Wired to |
|---|---|---|
| Allow apps to control Luna | Toggle, off by default, plus a one-line note that connected apps act in the user's signed-in sites | `ControlService` — the socket exists only while it is on |
| Connect an app: Claude Code, Codex, Cursor, Claude Desktop, VS Code | One row each: *Not installed* / *Not connected* / *Connected*, with *in use now* while that app is on the socket. Button: Connect / Disconnect, or for Claude Code Copy Command | `ControlApp` (`LunaControl`) edits the app's MCP config, keeping every other entry and writing `<file>.luna-backup` first. Only on a press |
| Other apps | Button: Copy JSON | The generic `mcpServers` entry |

Claude Code gets a command rather than an edit because it rewrites
`~/.claude.json` itself while running, and two writers to one file lose
changes. The row reads that file to show whether the command was run.

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
appearance.glassDensity
search.engine               search.customEngineURL
search.suggestions          search.settingsResults
search.shortcutResults
downloads.directory         downloads.askEachTime
downloads.autoOpen          downloads.clearPolicy
advanced.userAgent          advanced.showDevelopMenu
advanced.webInspector       advanced.allowControl
settings.lastSection
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
- ~~**Passwords**~~ — **moved into §3.3a on 2026-09-19.** The objection was that
  §14.1 had not run and the window "must not hint at a password manager that may
  never ship in this shape". The spike has now run (`docs/PASSWORDS.md`), and
  what shipped is not a password manager: it is a bridge into the user's own
  Keychain. The section states both halves of the spike's answer — what works
  today and what is waiting on a signature — which is the condition the
  objection was really asking for.
- **Per-site permissions** (camera, mic, location) — §17.8's chip UI is unbuilt,
  so there is no data to list yet.
- **Telemetry / usage reporting** — there is nothing to toggle. D16 says none is
  collected, and a switch labelled "off" implies an "on" exists.
