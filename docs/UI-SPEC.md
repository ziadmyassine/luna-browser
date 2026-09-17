# Luna — UI specification

> **Status:** agreed 2026-09-17. This is the build contract for the visual layer.
> Derived from `inspiration/` by measurement, plus the decisions in §32 of `TODO.md`.
> **Where this conflicts with §7, §8 or §30 of `TODO.md`, this document wins** — it is measured from
> Martin's actual reference, and §30 itself says the reference outranks the written sections.

## 0. Scope

Everything visible in `main-tab-bar-and-ui.png`, `non-side-bar-tab-ui.png` and `downloads-ui.png`,
built 1:1. That spans what the milestone list calls M1, all of M2's §5 Spaces work, and §15 downloads.

**Two layouts, one model.** Sidebar layout and top-bar layout are separate layout controllers over a
shared tab/space model (D13). Neither is a special case of the other.

---

## 1. Scale and geometry

> **Re-measured 2026-09-17, and the scale it was measured at was wrong.** The first pass read
> `main-tab-bar-and-ui.png` assuming the reference's sidebar was the 280 pt default, giving 2.725 px/pt.
> The reference's sidebar is not 280 — it is a resized 268. The capture's real scale comes from the one
> thing in the frame the app does not control: **the system traffic lights are 23 pt apart** (AppKit lays
> them out at x = 9 / 32 / 55, verified with a runtime probe) and measure **65.5 px** apart in the file,
> so the capture is **2.848 px/pt**. Every row below is re-derived at that scale; the ones that moved are
> marked. The reference is Dia, which uses the system window buttons untouched.

All sizes derive from measured ratios against sidebar width, normalised to a **280 pt** default sidebar.
Ratios are the source of truth; if the sidebar is resized, chrome metrics do **not** rescale — only the
sidebar's own content reflows. The ratios exist to fix proportions once, not to drive live layout.

| Token | Value | Was |
|---|---|---|
| `sidebarWidth` default / min / max | 280 / 160 / 420 pt | min was 180 |
| `rowHeight` (pitch) | 38 pt | 40 |
| `rowGap` / `rowPillHeight` (the drawn pill) | 3 / 35 pt | 4 / — |
| `rowInset` (pill inset from sidebar edge) | 8 pt | — |
| `faviconSize` | 16 pt | 18 |
| `rowCornerRadius` | 12 pt | 10 |
| `rowFaviconInset` / `rowTitleInset` | 17.5 / 45.5 pt | 15 / 41 |
| `rowIconGap` (favicon → title) | 12 pt | — |
| `separatorRowHeight` | 12 pt | 8 |
| `urlPill` | 266 × 34 pt, radius 17 (full) | × 32, radius 16 |
| `essentialsTile` | 128 × 42 pt, radius 12 | — |
| `essentialsTileGap` / `essentialsInset` | 8 / 8 pt (`= rowInset`) | 12 / 10 |
| `essentialsIcon` | 16 pt (`= faviconSize`) | 22 |
| `controlCircle` (top bar: back, capsule items) | 28 pt | 35, and before that a squircle for the toggle |
| `sidebarCircle` (**toggle**, back, reload) | 34 pt (`= urlPill.height`) | 28 |
| `controlPairGap` (back ↔ reload) | 5 pt | 8 |
| `trafficLightInset` (leading **and** top) | 18 pt | 8 leading, 18 top |
| `controlSquircle` (top-bar tab tile only) | 28 pt, radius 9 | — |
| `bottomCircle` (avatar, history) | 34 pt (`= sidebarCircle`) | — |
| `spaceDotsPill` | 56 × 22 pt, radius 11 | — |
| `spaceDot` | 6 pt | — |
| `glyphSize` (chrome SF Symbols) | 16 pt | 17, and 18 before that |
| `windowCornerRadius` | 25 pt | 18 |
| `contentCardRadius` | 25 pt (`= windowCornerRadius`) | 16 |
| `contentCardGap` | **gone** — the page is flush (§3.6) | 8 pt |
| `panelInset` (Command Bar, downloads list) | 8 pt | was `contentCardGap` |
| `topBarHeight` | 52 pt | — |
| `sidebarPeekEdge` (§3.8 hover-peek trigger strip) | 4 pt | — |
| `settingsSidebarWidth` / `settingsWindow` | 196 pt / 720 × 460 pt | was a 420 × 160 box |
| `hairline` | 1 pt @ 10 % white / 8 % black | — |

**Colour rules.** `Accent.tint` and `Accent.danger` are **fill and ring only** — as text they measure
4.02:1 and 3.57:1 and fail §21.4. Ask for a dedicated token before colouring any text.
Secondary and tertiary text are separated by **size and weight, not alpha**: §21.4's floor compresses them
to ~0.04 alpha apart, which is invisible.

**Typography.** Sidebar rows **13 pt**, URL pill **13 pt**, top-bar URL **13 pt**, section labels 12 pt
semibold. System font throughout, monospaced digits for any **numeric** face — not for titles.
> **Corrected.** This said 15 / 17 pt, on the strength of the same bad scale as §1's table. Re-measured,
> the reference's row titles and its URL pill have the **same** 20 px x-height and 25 px cap height, which
> at 2.848 px/pt is a 13 pt system font — §8.6's original number, which was right.
> Titles also drop `monospacedDigitSystemFont`: §1 asks for tabular digits "wherever a number is shown",
> and a page title is not a number. Monospaced digits visibly widen a title like "iPhone 18 Pro".

---

## 2. Materials and tint

**Decided:** the chrome is a **native macOS 26 Liquid Glass surface sampling what is behind the window**
(wallpaper, other windows). It is *not* tinted by the page. The single exception is the **URL pill**,
which carries a subtle wash derived from `webView.themeColor`.

This is why the same chrome reads violet over a violet wallpaper and pink over a pink one while the pages
are near-black and white respectively. The OS does the expensive part for free.

| Surface | Material |
|---|---|
| Sidebar | Liquid Glass, regular |
| Top bar | Liquid Glass, regular |
| Action capsule, control buttons, Essentials tiles | Liquid Glass, clear, over the bar |
| Downloads popover | Liquid Glass `.regular` + a heavier panel shadow |
| Content card | Opaque `Surface.base` — never translucent; a web page behind glass is unreadable |
| URL pill | `.control` glass **plus** a translucent page-derived wash — the one page-tinted surface in the app |
| Command Bar scrim | **`NSVisualEffectView` at `.withinWindow`** — the one surface that is deliberately not Liquid Glass |

**A dormant control is a well, not a plate.** §3.2's URL pill and §3.3's pinned tiles rest on
`Surface.well` — **black in both themes** — with a `Line.border` hairline catching the edge, so they read
as cut *into* the sidebar. They were `Surface.hover`, which is ink and therefore white on dark, so they
came out lighter than the plane around them and read as raised: the opposite of
`inspiration/main-tab-bar-and-ui.png`. `Surface.well` is the only token built with `recessInkColor`.

**The chrome tint is heavier, and it is off in fullscreen.** `Ink.glassTint` went 0.32/0.34 → 0.46/0.50:
untinted `.regular` glass samples the desktop so faithfully that the sidebar read as a pane of wallpaper
rather than as a surface. But the tint is *black* in dark mode by construction (`surfaceTintColor`), and
in fullscreen the glass is sampling the opaque `glassFallback` plane rather than a bright desktop —
darkening that by half took the sidebar under the content pane's own colour. So the tint is dropped
wherever the backdrop plane is up, which is exactly where it has nothing to do.

**Glass is the highlight, and nothing in the chrome is ever accent-blue.** A selected pinned tile, a
selected row, the pill you are typing in, the section you are looking at in Settings: all of them say so
by carrying the material, and all of them are a bordered plate when they do not. The accent ring, the
accent border and `NSSegmentedControl`'s solid blue block are gone from every one of them. The unread dot
is `Text.primary`; an internal page's focus ring is `--luna-text-primary`; `--luna-accent` is no longer
part of the internal-page palette at all.

**Why the Command Bar's scrim is not glass.** Liquid Glass composites what is behind the *window*, so
over a live page in the same window it does not blur the page — it replaces it. In fullscreen, with no
desktop left to sample, the page behind the Command Bar disappeared entirely behind a near-black plate.
`NSVisualEffectView` at `.withinWindow` is the only API that blurs in-window content, and that is what
§9.1's "blurred backdrop scrim" describes. Its material is `.sidebar` — the most see-through of the
in-window materials — and it is applied at **0.72**, not at full strength. `.hudWindow` and
`.fullScreenUI` both blur beautifully and then flatten everything above them into one dark wall: the page
stops being context, and the bar's own Liquid Glass has nothing but the scrim left to sample, so it
reads as a plate. The bar itself keeps §2's **untinted** `.popover` glass for the same reason the
chrome's tint exists — a bar floating over a page should look like a pane of the desktop, not like more
chrome. The choice still lives in `Design/Glass.swift` (`Glass.scrim()`); no other file knows which
material it got.

**Page-derived pill wash.** Blend `themeColor` (fallback `underPageBackgroundColor`) into the URL pill
fill at **12–18 %**, animated over 0.25 s, clamped so pill text always clears 4.5:1 (§21.4). If the
clamp cannot be met, drop the wash entirely rather than shipping unreadable chrome.

**Fullscreen.** Glass composites what is behind the *window*, and in macOS fullscreen there is nothing
behind it — the sidebar rendered very nearly black in dark mode. The chrome planes (sidebar, top bar)
therefore paint `Surface.glassFallback` **behind** the glass whenever the window is fullscreen: dark grey
in dark, light grey in light, with the material still on top of it. Only in fullscreen — painting it
always would be sampled by the glass in every window state and the wallpaper would stop coming through,
which is the whole look.
> **The plane goes up on `willEnterFullScreen`, not on `did`.** `styleMask` does not carry `.fullScreen`
> until the transition finishes, so reading it on `didEnterFullScreen` left the sidebar black for the
> whole half-second zoom and only grey once the window had landed. Leaving is driven by
> `didExitFullScreen` for the mirror-image reason: the plane has to survive the zoom back out.

**Reduce Transparency.** Every glass surface falls back to solid **`Surface.glassFallback`**, and the
page-derived wash is disabled outright.
> **Corrected in M1:** this originally said `Surface.base`. But the content card is also `Surface.base`,
> so obeying it literally made the sidebar and the card the same colour and the card vanished. There is a
> dedicated `Surface.glassFallback` token for exactly this.

> **Expect this to look like a bug (M1).** Because the chrome genuinely samples what is behind the window,
> another app's window sitting under Luna shows through the sidebar as a hard-edged translucent panel with
> its own corner radius. It was investigated as a rendering defect and reproduced 1:1 with a Finder window;
> the "artifact" was that window. It stops at the content card because the card is opaque, which is also
> why top-bar mode looks clean — the card is full-bleed there. Nothing to fix; this is §2 working.

**Verified API (M1).** macOS 26.5 provides `NSGlassEffectView` (`contentView`, `cornerRadius`, `tintColor`,
`style`) with `Style.regular` / `.clear`, plus `NSGlassEffectContainerView` for merging adjacent glass.
There is **no heavy or thick style** — weight comes from shadow, not material. There is no `NSLiquidGlass*`
type. Since the deployment target is macOS 26, the `NSVisualEffectView` fallback §8.4 imagined is dead code
and is not built; the path that actually runs is Reduce Transparency → solid colour. **Increase Contrast** promotes every hairline to 20 % and
adds a visible border to each control.

---

## 3. Sidebar layout

Vertical order, top to bottom:

### 3.1 Control row — height 52 pt, top-aligned
`[traffic lights] [sidebar toggle 28] ·············· [back 28] [reload 28]`
> **Corrected in M1** against `inspiration/main-tab-bar-and-ui.png`: the toggle sits beside the traffic
> lights, and back/reload are pinned to the **trailing** edge, not grouped after the toggle. The row must
> also *measure* the traffic lights rather than assume a width.
> **Corrected again:** the toggle is the **same circle** as its two neighbours, not a squircle. Back and
> reload are 5 pt apart, not 8, and the whole trio sits on the traffic lights' centre line rather than
> centred in the 52 pt row (the two are 1 pt apart, and the row asks the window for the line rather than
> guessing).
> **Corrected a third time — the circle is 28 pt, not 35.** 35 is what the reference measures, but the
> reference's sidebar is 268 pt of a 2146 px capture, and at Luna's scale a 35 pt circle is a control as
> tall as the row pill beneath it. 28 is the top-bar capsule item, so both layouts now agree on one
> diameter. The glyph came down with it, 17 → 16.
> **Corrected a fourth time — and it is 34 here, 28 on the bar.** 28 read as three small buttons
> floating above a bigger one: the URL pill directly beneath them is 34, and so is §3.5's bottom row, so
> the sidebar's head was the only thing in the column that did not line up. `sidebarCircle` is
> `urlPill.height`, derived rather than written down again. The **top bar keeps 28**, because its back
> button has to match the capsule items at the other end of the same bar.
> **The three were also drawn one point taller than wide.** They are centred on the traffic lights'
> midpoint, which is fractional, and `NSRect.integral` rounds the origin down and the far edge *up* — a
> 28 × 28 circle placed at a fractional y comes out 28 × 29 and reads as an egg. Chrome controls snap
> their **origin** only (`NSRect.pixelAligned`); a size that came from a token is not the layout's to
> round.

- Traffic lights are **system-drawn**, inset into the sidebar **18 pt from the window's leading edge and
  18 pt from its top — one number, both axes**. They were 8 pt in and 18 pt down, which is unequal
  padding into a corner and the first thing the eye catches. A single `TrafficLightLayoutManager` owns
  their frame for all six window states (§7.7 — this is the #1 bug source in Arc-style browsers).
- Back and reload are circular glass with a hairline border; **hover lifts the fill** (not the border).
- **All three carry their glass at rest.** The toggle spent one build as a bare glyph that only took
  its material on hover; that made the single control which brings a hidden sidebar back invisible until
  the pointer happened to find it, which is the wrong trade for the one button on this row that is not
  reachable any other way.
- Back is disabled-dimmed at 35 % when `canGoBack` is false. Reload becomes a **stop** glyph while loading.

### 3.2 URL pill — full width less 8 pt each side, 34 pt tall, full radius, flush under the control row
> **Corrected:** not "12 pt below the control row". The 52 pt row already carries clear space below its
> buttons, and that *is* the gap the reference measures between reload and the pill. A second gap on top
> of it doubles a space that is already right.
- **Domain only**: `apple.com`, not the full URL (§30.3). eTLD+1 plus subdomain when meaningful.
- Left-aligned text at 12 pt inset; trailing **sliders glyph** (site menu) at 10 pt from the right edge.
- Two further icon slots are **reserved and sized** to the left of the sliders glyph but render nothing.
  AI and extension actions live in the top-bar action capsule, not here.
- Click or `⌘L` → expands to the full URL, selected, in edit mode. `Esc` reverts.
- **Dormant at rest.** The pill is a bordered plate on the sidebar's plane until it is hovered or opened
  for editing, and it takes its glass then. Constant glass made it the brightest thing in the column — a
  second lit surface directly under three lit circles, pulling the eye to an address the user already
  knows. **No accent ring while editing**: the material is what says the pill is live.
- **The page-derived wash blends over `Surface.chromeFill`, not `Surface.raised`.** `raised` is an
  *opaque plane*, so a theme colour blended onto it produced an opaque plate: on a site whose theme
  colour is a near-neutral grey the pill stopped being translucent and simply turned grey.

### 3.3 Essentials grid — 2 across, wrapping
- Tiles 128 × 42, radius 12, **8 pt gap, 8 pt outer inset — both `rowInset`**. The grid used to sit at
  10 pt against the pill's and the rows' 8, two points proud of everything above and below it; and its
  12 pt inner gutter was wider than its outer margin. **Tile width flexes:** the grid must survive the
  160–420 pt resize range.
- **Icon only, centred, 16 pt.** No label. Visually distinct from the text rows below (§30.5).
- **Dormant, and glass when it is the tab you are on.** A tile at rest is `Surface.hover` plus a
  hairline; the material arrives when the tile is selected or hovered and leaves with the pointer.
  There is **no accent ring** — glass is Luna's highlight, everywhere, and nothing in the chrome turns
  blue to say "this one".
- **Pinning and unpinning animate.** Tiles are keyed by tab, so one survives a pin, an unpin or a
  reorder and travels to its new slot on §6's `tabInsert` spring; a new tile fades up, a removed one
  fades out where it stood, and the list below slides with the grid's height instead of snapping.
- **Pinning** (§6.6's other half): right-click a row → *Pin Tab*, or drag it up into the grid. Pinning
  moves the tab into the Essentials section **and puts its page away** — the tile is the tab, so the page
  costs no WebContent process until it is clicked again (§19.2). A pinned tab cannot be closed, only
  unpinned (right-click → *Unpin Tab*, or drag it back down); `⌘W` on one puts the page away and leaves
  the tile.
  > **This was half-implemented and looked broken.** `pinTab` put the page away and never changed the
  > tab's kind, so the row left the list, no tile appeared, and the command did nothing visible.

### 3.4 List rows — 38 pt of pitch around a 35 pt pill
Order: `+ Add Tab` row → **separator** → tabs.
> **`Archive` is no longer a row here.** It was a second door to the page §3.5's bottom-bar button
> already opens, sitting directly under the pinned tiles where the eye lands first — a history button at
> the top of a list of live tabs. History belongs with the other standing destinations at the foot of the
> sidebar, and that is the only place it is now.
> The rule stays and still closes off the command group. It spans the sidebar edge to edge, not inset
> like a row pill, and its row is 12 pt tall — 6 pt of clear space either side of the hairline.

- `[status dot 6] [favicon 16] [title 13 pt, single line, **faded**, never ellipsised] [trailing affordance]`
- **The favicon is square-inset inside the pill**: the same 9.5 pt of padding on its leading edge as
  above and below it, which lands it 17.5 pt from the sidebar's edge. The title clears it by 12 pt, so it
  starts 45.5 pt in, and stops 8 pt short of the pill's trailing edge.
- **A title that does not fit fades out over the last 24 pt.** No `…`: the reference lets the last glyph
  dissolve rather than spending three characters saying the obvious.
- **Selected row:** filled translucent pill spanning sidebar width minus 8 pt each side, radius 10,
  **visible hairline border**, brighter text. **Unselected rows have no background at all** (§30.7).
  > **No accent anywhere on it.** The pill used to take an `Accent.tint` border while the list had focus.
  > A blue ring around the current tab is a system list; Luna's selection is the glass plus §3.4's wash,
  > and the hairline is `Line.border` in every focus state.
- **Status dot** leads the row only when the tab has unread/updated content (the Discord row in the
  reference). Audio gets a **trailing** speaker glyph, click-to-mute.
- **Hover** reveals a trailing close/archive affordance and lifts the row fill to 6 %. That affordance is
  an **18 pt rounded-square chip with its own translucent fill** holding an 11 pt glyph, inset a full
  `rowInset` inside the pill's trailing edge — measured off Martin's close-button reference. A bare glyph
  floating in the pill, which is what §3.4's silence produced, reads as part of the title.
- **Selected and hover fills are `Surface.selected` / `Surface.hover`.** Clear glass alone is very nearly
  the sidebar's own glass, and a selected row read as unselected until these were asked for.
- Loading shows a shimmer sweep across the title, not a spinner.
- `+ Add Tab` is a first-class row with identical metrics to a tab (§30.6).
- **The unread dot is ink, not accent.** It was `Accent.tint`; it is `Text.primary` now, and it reads
  because it is bright rather than because it is a different hue.
- **Reordering opens a gap.** The list's drop feedback is `NSTableView.DraggingDestinationFeedbackStyle.gap`,
  not the default insertion rule: the rows animate apart to make a slot the size of the row being
  dragged, so the tab's landing place is visible and locked the whole way down. A 2 pt line between two
  rows that never move reads as a static list with a ghost floating over it.

### 3.5 Bottom utility bar — 52 pt, pinned
`[profile avatar circle 34, left] ··· [space dots pill 56 × 22, centred] ··· [history circle 34, right]`

> **It is called History and it carries a clock.** Luna's internal word for the shelf is "the archive";
> the user's word for what they are looking for is "history". The route stays `luna://archive` — a URL is
> not a label — and the glyph is `clock.arrow.circlepath`, because a box means storage and a clock means
> "earlier".

- **Space dots** are the Space switcher: one 6 pt dot per Space, active dot 100 % white, inactive 35 %.
  Click a dot to switch; the pill widens by 8 pt per Space beyond three.
- Avatar is the active profile; click opens the profile menu.

### 3.6 Content pane
Opaque, **flush** to the window's top, bottom and trailing edges and flush against the sidebar. Only its
two **leading** corners are rounded, at `windowCornerRadius`, so they nest with the window's own corners
instead of leaving a crescent of glass inside each one.
> **Corrected.** This said "inset 8 pt from the sidebar and from the window's top, right and bottom
> edges", and called the gap "what makes the whole thing read as floating". The reference has no gap on
> any edge — the page runs to the glass. The floating read comes from the window's glass and its shadow
> against the wallpaper, not from a moat around the page.

**The pane carries the glass edge.** It is opaque, so the chrome's material stops dead at its leading
edge and the two planes met with nothing between them. A `Line.border` hairline runs down that edge,
following the rounded leading corners and nothing else — the same edge every other glass surface has.

**Hiding the sidebar gives the page the whole window — traffic lights included.** They used to keep
their place in the titlebar and float over the page, which meant the one piece of chrome that did *not*
go away was sitting on top of the site's own navigation. `⌘S` means "give the page the window", so the
lights are hidden with everything else and come back the moment there is a sidebar to put them in —
including §3.8's peek.

**The page is revealed, not resized.** Its width is a constraint of its own, set to the *destination*
width before the chrome starts moving, and the page is anchored to the card's trailing edge. So a
sidebar collapse costs WebKit **one** relayout instead of one per frame of a 0.20 s slide, nothing under
the pointer shifts, and a heavy site stops stuttering on `⌘S`.

Entering page fullscreen animates the pane to fill the window over 0.3 s.

### 3.7 Sidebar resize handle
An invisible 8 pt grab strip on the sidebar/content divider. Drag resizes within 160–420 pt, double-click
resets to 280.
> **Nothing is drawn.** §3.7 asked for a `◁|▷` glyph to fade in on hover, and on screen it read as a
> piece of UI that had come loose: a small mark floating over the page, attached to neither surface,
> appearing for no reason the user had asked for. The resize cursor already says the divider is
> draggable, which is what every native split view relies on.
> **This was drawn, hovered, dragged — and did nothing.** `SidebarViewController` reports the width out
> through `onWidthChange`, and nothing was ever connected to it; the same was true of the sidebar toggle
> and of committing text in the URL pill. `AppDelegate.wireSidebar` is where all three now land. A live
> drag applies the width **unanimated** — the pointer is the animation, and a 0.20 s spring per drag
> event leaves the divider permanently behind the mouse.

---

### 3.8 Hover-peek — the hidden sidebar

With the sidebar hidden, pushing the pointer into the window's leading **4 pt** brings it back **over**
the page after §6's 0.10 s intent delay, and lets it go again 0.10 s after the pointer leaves both the
strip and the sidebar itself.

- **The page does not move.** Only the chrome's leading constraint and its opacity animate; the card's
  insets stay collapsed, so nothing reflows for a glance at the tab list.
- The hidden sidebar parks at `-width` rather than collapsing to zero width: it keeps its layout, and it
  is one constraint away from coming back.
- The traffic lights come back with it, and go again with it.
- The asymmetry is deliberate: the same delay guards both edges, because the pointer leaves the trigger
  strip the instant the sidebar arrives over it, and a zero-delay close would flicker.

---

## 4. Top-bar layout

One 52 pt glass bar spanning the window. **Content is flush full-bleed below it — no inset card, no gap.**

`[traffic lights] [back 28] [tab tiles …] [ACTIVE TAB pill] [tab tiles …] [hairline] [action capsule]`
> **There is no sidebar toggle on this bar.** There is no sidebar in this layout to hide, so the button
> either did nothing or silently changed a preference. Back is `TopBarMetrics.capsuleItem` — the same
> circle as the new-tab, downloads and profile buttons at the other end of the bar, so the bar has one
> button size.
> **Switching the active tab animates.** The outgoing tab's pill collapses into a tile and the incoming
> tile expands into the pill, each seeded at the other's frame, with every tile after them sliding along
> on §6's `tabInsert` spring. The strip is one ordered run, and it used to jump.

- **Tabs are visible in this mode as a horizontal strip.** Inactive tabs render as 28 pt icon-only tiles;
  the **active tab expands into the URL pill** showing its domain, favicon and sliders glyph. This is why
  tiles appear on both sides of the pill and why the pill is not exactly window-centred.
  > This supersedes §30.12's claim that tabs are invisible in this mode.
- **No reload button** in this layout — the reference omits it. Reload is `⌘R` and the site menu.
- The strip scrolls horizontally when it overflows; the active tab is always scrolled into view.
- **Action capsule**: its own rounded glass capsule, separated by a vertical hairline, holding
  `[+ new tab] [downloads] [profile]`. Extension action buttons dock here when extensions ship (v2) —
  build the capsule to host a variable number of items now.
  > **Corrected: the capsule is one glass surface, not three merged ones.** It gave each item its own
  > `.control` backing and handed them to `NSGlassEffectContainerView`, on the theory that Liquid Glass
  > unions neighbours within `spacing`. On screen it did not: three separate bright circles, each with
  > its own specular rim, and the white `+` and `↓` washed out against those rims. The glass is applied
  > once, to the capsule, at full radius; the items inside it are bare glyphs.

### 4.1 Switching layouts
**The switch is a setting, not a button.** `Settings.chromeLayout` (`⌘,`) chooses the layout; the sidebar
toggle and `⌘S` only hide and show the sidebar within it. The two are different decisions taken at
different rates — one is a reflex, several times a minute, the other a preference taken once — and a
control that did both meant the reflex silently changed the preference.

When the layout does change, sidebar width collapses to 0 while the top bar's height animates 0 → 52 and
its contents stagger in at 20 ms intervals. Total 0.3 s. Traffic lights re-anchor in the same transaction
— never as a second step, or they visibly jump.

> **A layout pass must never be caught in that transaction.** The switch calls `layoutSubtreeIfNeeded()`
> with `allowsImplicitAnimation` on, and any `layout()` that sets subview frames from `bounds` then has
> every assignment routed through the animator instead of landing. Coming back from top-bar layout, the
> sidebar drew its control buttons 1001 pt to the right and its list 1070 pt wide — the frames the pass
> computed were correct and were never applied, and the sidebar looked empty. Bounds-derived frames are a
> consequence of the layout, not a change to animate: they go through `Motion.immediately`. The animation
> belongs to whatever moved `bounds`.

> **`NSTableView` does not survive being hidden.** While the top bar shows, the sidebar is `isHidden`
> inside a 52 pt host, so the list has no visible rect and AppKit releases the row views it was
> recycling. The list reloads when its layout comes back on screen.

---

## 5. Downloads popover

- **Renders outside the window bounds**, floating above the top edge, with a **visible pointer tail**
  into the downloads button. It is an `NSPanel`, not an in-window view.
- Size ~330 × 58, radius 14. Heavier glass than the bar, with its own shadow.
- Row: `[file-type icon 34] [filename, middle-truncated, 14 pt] [confirm button 30, radius 9]`
- Middle truncation is required — `97103328759-202…01-2026-08-31.pdf` keeps both the prefix and the
  extension, which head- or tail-truncation would each destroy.
- Appears on download completion, auto-dismisses after 4 s, or on confirm. Hovering cancels the timer.
> **Gotcha (crashed the app, found by runtime bisect):** **never set `frameCenterRotation` on a view that
> contains a `Glass` backing.** `Glass.backing` puts an `NSGlassEffectView` inside, which lays its own
> `contentView` out with constraints — and Auto Layout cannot express a rotation, so the engine returns
> **NaN** and AppKit traps in `_NSViewValidateGeometry` ("Invalid view geometry: y is NaN") on the next
> layout pass, with no frames of ours in the stack. The tail's diamond is a `CAShapeLayer` mask on an
> unrotated view of the same bounding box instead. It crashed on *every* completed download; the TCC
> dialog only made the timing deterministic.
- The full downloads panel is the secondary surface; **this popover is primary** (§30.15).

### 5.1 Completion animation — the particle sweep
On completion the filename **dissolves into particles and reassembles**:
1. Text renders to a bitmap, sampled into ~1200 particles on a grid.
2. Particles displace upward and outward with per-particle jitter, fading to 0 over **0.22 s**, swept
   left → right so the dissolve reads as directional.
3. They settle back into place over **0.18 s** with a 0.04 s stagger, ease-out.
4. Total **0.4 s**, and the stagger lives **inside** each phase: a given particle's dissolve spans 0.18 s
   starting at `sweepIndex × 0.04`, so 0.22 + 0.18 = 0.40 overall.
5. **One composited node**, not 1200 `CALayer`s — that is the rule. `CAEmitterLayer` turns out not to
   satisfy step 3: it is a simulation with no handle on an individual particle, so "settle back into
   place with a 0.04 s stagger" is unreachable, and its single `emitterPosition` cannot sample glyph
   shape. A single layer-backed view drawing every particle itself is correct and costs ~0.3 ms of an
   8.3 ms frame at 120 Hz.
- **Reduce Motion: the animation does not run.** The filename simply appears.

---

## 6. Motion

Nothing exceeds **0.35 s** except the two cases marked, which are tied to real work rather than taste.
Every entry degrades to instant under Reduce Motion.

| Interaction | Animation |
|---|---|
| Space switch | spring, response 0.30, damping 0.70; sidebar content cross-fades 0.18 s |
| Sidebar collapse / expand | 0.20 s ease-out width + 0.12 s opacity |
| Layout switch (sidebar ↔ top bar) | 0.30 s, contents stagger 20 ms |
| Hover-peek reveal | 0.10 s intent delay → 0.15 s ease-out slide |
| Command Bar in | 0.18 s spring, scale 0.96 → 1.0 + fade, anchored 20 % from window top |
| Tab insert / remove | 0.22 s spring height + fade, no list jump |
| Row hover fill | 0.12 s ease-out |
| Control button hover lift | 0.10 s ease-out |
| Selected-row pill move | 0.20 s spring, response 0.28, damping 0.80 |
| URL pill theme wash | 0.25 s ease-in-out |
| Split divider snap | 0.12 s |
| Downloads popover in | 0.20 s spring, scale 0.94 → 1.0, from the tail anchor |
| Downloads particle sweep | **0.40 s** (see §5.1) |
| Page reload bloom | **tied to load duration** (see §7) |
| Content card → fullscreen | 0.30 s ease-in-out |

---

## 7. Reload / refresh animation — **DEFERRED 2026-09-17**

> **Not in scope. Do not wire this up, and do not spend time on it.**
> **Two defects were found by running it before it was set aside — fix these first if it is revived:**
> 1. `updateLayer()` never runs, because AppKit skips the display pass for a hidden view, so
>    `arcLayer.colors` stays nil and **the bloom plays with no arc at all**. Set `needsDisplay = true`
>    in `begin()`.
> 2. `layoutBands`' `contentsRect` comment has the axis backwards — it is **y-up**, so `y: index/count`
>    composites the five snapshot strips in reverse vertical order.
> With both fixed the arc measured correctly over a flat grey page (white 164 → amber → mint → lavender
> over base 138), and a sub-0.15 s reload correctly drew nothing.
> `Features/Reload/` is built, tested and deliberately left **unreferenced** — it is dead code by choice,
> not by oversight, so a future view-hierarchy audit does not "fix" it back in. The spec below is kept
> because the transcription work is done and the arc colours were sampled from the reference video; it is
> a record, not a task. Reviving it is wiring, not rebuilding.


Transcribed from `refresh-animation-ui.mov`, which is an **iPhone pull-to-refresh** at 120 fps — not a
desktop reload. What it shows:

1. The page blurs heavily (illegible) and desaturates toward the surface colour.
2. A **prismatic arc** sweeps down from the top: a concave-up crescent, horizontally centred, banded
   **white → amber → mint → lavender** from inner to outer edge, soft-edged and heavily blurred.
   > **Corrected in M1.** This originally read "white → amber → lavender → mint". The clip was sampled at
   > t = 1.40/1.55/1.70 s by ridge-tracking hue and chroma: amber sits at hue 56°, mint at 194°, lavender at
   > 277°, composites `#EEECCA` / `#E1EBEF` / `#E2D0EE`. Mint and lavender were transposed. Values live in
   > `Tokens.Bloom`.
3. The arc descends and dissipates; the screen reaches near-flat surface colour.
4. Content returns as a **staggered de-blur**: title first, then body, then chrome icons.

Total in the clip: **~2.3 s**, which is a gesture-driven mobile interaction.

**Adaptation for Luna.** A 2.3 s full-page blur on every desktop reload would be obnoxious and breaks the
0.35 s budget. The animation is therefore **bound to real load progress**, not to a fixed duration:

- **The frozen snapshot is released at `progress >= 0.5`**, not only at `didFinish` — otherwise a ten-second
  load sits under a stale picture of the previous page.
- **Arc in:** 0.25 s ease-out on reload commit. Blur is **light (8 pt), not illegible** — the page stays
  readable throughout.
- **Arc hold:** persists while loading, drifting slowly downward. Honest progress, not theatre.
- **Arc out + de-blur:** 0.30 s on `didFinish`, staggered 40 ms across the viewport top-to-bottom.
- A load finishing under 0.15 s plays **nothing** — no flash on cached reloads.
- Implemented as a `CAGradientLayer` arc over the content card with a `CIGaussianBlur` on the snapshot,
  never on the live webview. **It must be `webView.takeSnapshot`, not a layer capture:** a `WKWebView` renders
  out-of-process, so its local layer is a remote proxy with no backing store and `CALayer.render(in:)` returns
  blank for page content. The snapshot is blurred **once** into a `CGImage` — measured 6.8 ms for 3200×2000 at
  sigma 16 — after which steady state is six composited quads and zero CPU.
- **Reduce Motion: no blur, no arc.** A 2 pt progress line at the top of the content card instead.

---

## 8. Behaviour

- **Keyboard:** the §20.1 default map applies. `⌘S` **hides and shows the sidebar**; `⌘,` opens Settings.
  > **Corrected.** `⌘S` used to swap sidebar layout for top-bar layout, so a reflex the user performs
  > several times a minute silently changed a preference they set once. Which layout the window wears is
  > now `Settings.chromeLayout`, and `⌘S` is only a reveal. In top-bar layout it is dimmed.
- **Every chrome control is keyboard reachable** with a visible focus ring (§21.1, §20.2).
- **Settings is shaped like the browser** (§3, §3.6): a glass column of sections and an opaque
  `Surface.base` pane beside it, rounded on its leading edge. Sections live in `SettingsPane.all` — one
  struct and one view each — so adding one touches no window, list or selection code. It replaced a
  420 × 160 box with a segmented control in it, which read as a different app.
- **Drag and drop:** rows reorder within a section, move between sections, and drop onto a Space dot to
  move to that Space.
- **VoiceOver:** Essentials tiles are icon-only, so each needs an explicit label — the site name, not the
  URL. Space dots are a tab list with position and count.
- **Differentiate Without Colour:** Spaces must be distinguishable by icon and label, never by gradient
  alone (§21.2). The dots therefore carry a tooltip and an accessible label with the Space name.

---

## 9. Out of scope here

Peek (§13), split view (§10), Boosts (§18.7), reader mode (§18.3), extensions (§16, v2), AI surfaces
(§25.6), the New Tab page (§30.19) and the import screen (§30.17). Each gets its own pass.
