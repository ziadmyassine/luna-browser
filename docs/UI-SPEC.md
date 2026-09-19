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
| `sidebarWidth` default / min / max | 280 / **220** / 420 pt | min was 180, then 160 |
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
| `essentialsTileGap` / `essentialsRowGap` / `essentialsInset` / `essentialsVerticalInset` | 5 / 6 / 8 / 6 pt | 8 / 8 / 8, and 12 / 10 before that |
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
| `sidebarPeekEdge` (§3.8 hover-peek trigger strip) | 44 pt | 24, and 4 before that |
| `dragThreshold` (§6.6, press → lift) | 4 pt | — |
| `historyPanel` (§3.5's History **pop-out**) | 320 × 420 (a ceiling) | 640 × 520 |
| `downloadsPanel` (§15.3's list, the same pop-out) | 360 × 340 (a ceiling) | was an `NSPanel` |
| `historyPopoutGap` (pop-out ↔ its button) | 5 pt (`= controlPairGap`) | — |
| `scrimStrength` | **gone**, with the scrim itself — see §9.1 | 0.55 |
| `settingsListWidth` / `settingsWindow` | 230 pt / 720 × 520 pt | 196, and a 420 × 160 box before that |
| `settingsSectionRow` / `settingsSectionIcon` | 36 pt / 26 pt, radius 7 | — |
| `settingsCardRow` / `settingsGroupGap` | 52 / 26 pt | 36 / 3 |
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
(wallpaper, other windows). It is **not tinted by the page**, anywhere. The URL pill used to be the one
exception and is not one any more — see the wash note below.

This is why the same chrome reads violet over a violet wallpaper and pink over a pink one while the pages
are near-black and white respectively. The OS does the expensive part for free.

| Surface | Material |
|---|---|
| Sidebar | Liquid Glass, regular |
| Top bar | Liquid Glass, regular |
| Action capsule, control buttons, Essentials tiles | Liquid Glass, clear, over the bar |
| Downloads popover | Liquid Glass `.regular` + a heavier panel shadow |
| Content card | Opaque `Surface.base` — never translucent; a web page behind glass is unreadable |
| URL pill | `Surface.well` at rest, `.control` glass when hovered or open for editing. **No page tint** |
| History pop-out | Liquid Glass `.regular` + `Shadow.popover`, standing on the §3.5 button |
| Downloads pop-out | The same surface, standing on whichever Downloads button the layout shows |
| Command Bar backdrop | **None.** The bar floats over the page as it is — see §9.1 |

**A dormant control is a well, not a plate.** §3.2's URL pill and §3.3's pinned tiles rest on
`Surface.well` — **black in both themes** — with a `Line.border` hairline catching the edge, so they read
as cut *into* the sidebar. They were `Surface.hover`, which is ink and therefore white on dark, so they
came out lighter than the plane around them and read as raised: the opposite of
`inspiration/main-tab-bar-and-ui.png`. `Surface.well` is the only token built with `recessInkColor`.

**Density is frost, not tint.** `Ink.glassTint` stays at 0.32/0.34 — it is what stops untinted
`.regular` glass reading as a pane of wallpaper — and the chrome's *opacity* is a second, separate token:
`Surface.frost`, which is `glassFallback` at 0.46/0.50, painted **behind** the glass in every window
state. Raising the tint instead was tried and is wrong: the tint is *black* in dark mode by construction
(`surfaceTintColor`), so more of it is a dimmer sidebar rather than a thicker one, which is "darker", not
"more opaque". Frost separates the two — the material still samples and refracts the desktop, but through
a surface rather than through a hole.

### 2a. Clear or Opaque — the user's own answer

**How much of the desktop comes through is a setting**, `Glass.density`, stored in
`appearance.glassDensity` and offered as *Material: Clear / Opaque* in Settings ▸ Appearance ▸ Glass.
`Clear` is the default and is everything above. `Opaque` swaps `Surface.frost` for
`Surface.frostOpaque` — the same plane at **0.62 light / 0.66 dark** instead of 0.46/0.50 — and gives
the popover surfaces a plane of their own (`Surface.popoverFrostOpaque`, over `Surface.raised`, because
a popover reads as raised *above* the chrome rather than as more of it). Controls are untouched at
either density: a frosted control reads as a hole rather than as something raised.

**The two alphas are measured off Martin's reference, and the first measurement was wrong** in a way
worth recording, because it is the easy mistake. Comparing *means* said the panel keeps ~45 % of the
backdrop's red — "the colour comes through and the shape does not" — and gave 0.86, which on screen was
a different kind of surface rather than a denser one. Look at the image instead of at its average and
the wallpaper's shape is plainly still there. A mean cannot see that; contrast can. A flat plane over a
blurred backdrop compresses contrast by exactly the amount of plane there is, linearly in the alpha and
independently of what the blur did to the mean:

```
composite     = a · plate + (1 − a) · blurred backdrop
sd(composite) =             (1 − a) · sd(blurred backdrop)
```

| Red channel, off the reference | mean | sd | range |
|---|---|---|---|
| panel interior | 52.0 | 10.3 | 38–82 |
| wallpaper, box-blurred r = 40 | 85–109 | 28.6–35.3 | — |
| wallpaper, box-blurred r = 60 | 85–107 | 24.7–31.2 | — |

`1 − a = 10.3 / 28 ≈ 0.37`, so **a ≈ 0.63**. The mean agrees independently: `0.66 × 35 + 0.34 × X = 52`
solves to `X = 85`, exactly where the blurred wallpaper beside the panel sits. Two estimates from
different statistics landing on the same number is the reason to trust it — and it makes `Opaque` a step
above `Clear`'s 0.50 rather than a plate, which is what the reference actually shows.

**And it stops short of 1.0, by rule.** At full strength the frost *is* the Reduce Transparency fallback
plane: there is no glass left above it, and "more opaque" would quietly have become "off".
`TokenCheck.checkGlassDensity` asserts both halves — opaque is denser than clear in every variant, and
neither passes 0.95.

Assigning the setting re-skins every live surface in one pass and needs no relaunch, exactly as §7's
does. It is cheaper than §7's: the density changes a *plane*, not the material, so nothing is rebuilt and
there is no swap to flash.

The tint is dropped wherever the opaque backdrop is up (fullscreen, §3.8's peek): there the glass is
sampling a plate rather than a bright desktop, and darkening that plane by a third takes the sidebar
under the content pane's own colour. In fullscreen the material is hidden outright — see **Fullscreen**
below — so there is nothing left to tint there at all.

**Glass is the highlight, and nothing in the chrome is ever accent-blue.** A selected pinned tile, a
selected row, the pill you are typing in, the section you are looking at in Settings: all of them say so
by carrying the material, and all of them are a bordered plate when they do not. The accent ring, the
accent border and `NSSegmentedControl`'s solid blue block are gone from every one of them. The unread dot
is `Text.primary`; an internal page's focus ring is `--luna-text-primary`; `--luna-accent` is no longer
part of the internal-page palette at all.

**The Command Bar has no backdrop, and that is the third answer to the question.** §9.1 asked for a
"blurred backdrop scrim" and Luna built one twice, because Liquid Glass cannot be it: glass composites
what is behind the *window*, so over a live page in the same window it does not blur the page, it
replaces it, and in fullscreen — no desktop left to sample — the page disappeared behind a near-black
plate. `NSVisualEffectView` at `.withinWindow` is the only API that blurs in-window content, so the
backdrop was the one surface in Luna deliberately not made of glass.

> **Two versions of it, and the second is what Martin actually saw.** The first was built at
> `alphaValue = 0.55`, and `CommandBarPanel` carried a comment saying exactly why that cannot work:
> `alphaValue` on an `NSVisualEffectView` does not thin a material, it cross-fades the blurred result
> back over the sharp original — so every step below 1.0 bought a flat grey film over a page that was
> still perfectly legible. Two files disagreed and the code was the one that was wrong. The second went
> to full strength and painted `Surface.frost` over it, borrowing §3.8's peeked-sidebar recipe on the
> argument that a blur wants a *surface* to be rather than a hole — and that plane followed §2a's
> density, so at `.opaque` it was `Ink.frostOpaque`: **0.66 in dark mode**. Measured off a capture over
> apple.com: the page's shapes do survive the blur, and are then flattened under a sheet two thirds of
> the way to solid. What read was the sheet.
>
> **Why the peek's recipe never transferred.** That plane stands over the *desktop*, which glass
> refracts at full brightness, and the frost is what stops the wallpaper reading as the chrome. This one
> stood over a page the blur had already softened, at a setting whose whole subject is how much desktop
> comes through — a question this surface does not ask. So §2a moves the chrome and had no business
> here.

Shown the blur on its own, with the plane gone, Martin's answer was that the backdrop is not wanted at
all: *"just remove the blur around it completely, it is not needed."* So there is no scrim, no
`Glass.scrim()` and no `GlassScrim.swift`. `CommandBarPanel` still covers the window — that is what stops
a click reaching the page and what carries §9.1's dismissal — and simply draws nothing while doing it.
The finding about what glass composites is kept where it still decides something, in `Glass.peekPlane`.

Five materials had been tried on screen before the surface was dropped, and the record is worth keeping
for the next thing that wants an in-window blur. `.hudWindow` and `.fullScreenUI` blur beautifully and
then flatten everything above them into one dark wall. `.menu` and `.underWindowBackground` take the page
away completely. `.selection` barely registers. `.sidebar` is the one that blurs while leaving the page
visible underneath, and it is what the backdrop used until it was removed.

**Desaturation was the material's, and there was no dial for it.** Every in-window material desaturates
what it blurs, and the material's own tint is not tunable — a `CIColorControls` saturation boost on the
layer collapses the backdrop group into an opaque plate. What `alphaValue` looked like a dial for, it was
not: see the note above. The bar itself keeps §2's **untinted** `.popover` glass for the same reason the
chrome's tint exists — a bar floating over a page should look like a pane of the desktop, not like more
chrome (and §2a gives it a plane when the user asks for one).

**Its type is a step above the chrome's.** The query is 13 → **15 pt** (`TypeScale.commandBarQuery`) and
a result row's title and subtitle 13 → **14** (`commandBarRow`). §1's 13 pt is measured off the reference
and is right for a column of two dozen sidebar rows you scan; the Command Bar is a single modal surface
in the middle of the window that you look *at* while you type into it, and set at the sidebar's size it
read as a chrome field that had floated loose. §3.4's 38 pt row has the room.

**The Command Bar's query starts where its rows do.** Indenting it by a favicon's width lined it up
with the *titles* it filters and left a visible notch out of the panel's top-left corner. The list's
leading edge is the panel's left margin, and that is where the query starts.

**Its rows carry real favicons** (§4.7): the live session's icon for a tab that is open, the on-disk
cache by host for everything else, and the row's own symbol only when there is neither. A column of
identical grey glyphs is not a list you can scan. A favicon is never a template — a site's icon is its
own colours, not chrome ink — so selection brightens the title and leaves the icon alone.

**Page-derived pill wash — withdrawn.** The rule was: blend `themeColor` into the URL pill fill at
12–18 %, animated over 0.25 s, clamped so the pill's text still clears 4.5:1 (§21.4). It was built, it
was correct, and on screen it was wrong: the one fixed landmark in the sidebar changed shade with every
navigation. getroosta.app and YouTube lifted it, Apple's pages left it where it was, and a control that
is a different colour on every site is not a control you stop noticing. The pill is `Surface.well` in
every state and on every page — the same recess a pinned tile rests in, so the head of the sidebar is
one surface rather than two that agree only sometimes.

**Fullscreen.** Glass composites what is behind the *window*, and in macOS fullscreen there is nothing
behind it — the sidebar rendered very nearly black in dark mode. The chrome planes (sidebar, top bar)
therefore paint `Surface.fullScreenChrome` — **#202020 dark**, `glassFallback`'s grey in light — whenever
the window is fullscreen. Only in fullscreen: painting it always would be sampled by the glass in every
window state and the wallpaper would stop coming through, which is the whole look.
> **And the material stands down while it is up.** The plane used to be painted *behind* the glass, with
> the material still on top. But a material with nothing to sample is not refracting anything — it is a
> film that lifts the plane a few steps and makes its colour un-nameable, which is why the fullscreen
> sidebar read as a lighter grey than the token said. In fullscreen the glass is hidden and the plate is
> the colour, exactly: sampled on screen at #202020 across the sidebar. Controls keep their glass — a
> control's job is to read as raised above whatever the plane became.
> **The peeked sidebar is exempt.** §7.2's floating plane is fullscreen's one un-flattened chrome
> surface. A sidebar that is *always* showing in fullscreen is the window's own edge and should be the
> plate; a sidebar that slid out over the page for a glance is a panel floating in front of it, and
> flattening that to the same #202020 made it read as a hole cut in the page rather than as something
> on top of it. It keeps `Surface.frost`, §2's tint and its rim in every window state. Measured: the
> windowed peek samples #2A2419 over a gold wallpaper — the desktop refracting through — and the
> fullscreen peek #252525, the same construction with nothing behind the window to sample. That gap is
> physics, not a token; what matters is that it is a floating plane in both, and not the plate.
> **The plane goes up on `willEnterFullScreen`, not on `did`.** `styleMask` does not carry `.fullScreen`
> until the transition finishes, so reading it on `didEnterFullScreen` left the sidebar black for the
> whole half-second zoom and only grey once the window had landed. Leaving is driven by
> `didExitFullScreen` for the mirror-image reason: the plane has to survive the zoom back out.

**Reduce Transparency.** Every glass surface falls back to solid **`Surface.glassFallback`**.
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
> **And then they were squircles.** A `.continuous` corner curve at `radius == side / 2` is a
> superellipse, with straight flanks — which is the "still a bit longer than wide" left after the
> rounding was fixed. Apple's continuous curve is defined for radii *below* half the side; at or above
> it the only right answer is a real arc. `RoundedMetric.cornerCurve` returns `.circular` exactly when
> the shape is a circle, the button's layer and its focus ring follow it, and `GlassBackingView` masks
> to it — `NSGlassEffectView` has no corner curve of its own, so clipping is the only lever there is.
> Everything that really is a squircle (the §3.3 tiles, the §3.6 pane, the window) is unchanged.

- **The lights change without changing anyone's bounds.** macOS takes them away entering fullscreen and
  puts them back on the way out, and the row is 52 pt and exactly as wide either way — so nothing marks
  it dirty and it kept whichever placement it last computed, which is the toggle sitting on top of the
  green light after a return to windowed. Both fullscreen edges mark the chrome for layout, and again on
  the next runloop turn, because AppKit restores the buttons *after* it posts the notification.
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
- **The sliders glyph is drawn, not an SF Symbol.** The family ships `slider.horizontal.3` (three bars)
  and `slider.horizontal.2.square` (two, in a box); the bare pair the reference shows exists under no
  name — checked against all 9,524 in `CoreGlyphs.bundle`. `SiteMenuGlyph` draws it as a template image
  with real holes punched in the knobs, so it takes its colour from `contentTintColor` and this stays
  the one glyph in Luna that is drawn rather than named.
- **It is 13 pt, not `glyphSize`'s 16.** 16 is the size of a glyph that is its own button — the three
  §3.1 circles, the §3.5 bar — and this one is not: it sits inside a control that is already a landmark,
  beside text set at 13. At 16 it was the loudest mark in a pill whose whole job is to be quiet.
- **It takes §3.4's close-button chip on hover**, out of the same two tokens: an 18 pt `rowTrailingChip`
  hit target with the glyph centred in it, drawn only while the pointer is on the glyph itself. The
  pill's own glass says the *pill* is live; the chip says the glyph is a button rather than a badge
  printed on one. `pillGlyphInset` is measured to the mark the eye sees, so the chip is placed by
  centring it on where the glyph would have been rather than being inset itself — insetting the chip
  would shift the glyph 2.5 pt inwards the moment it gained a background it only shows on hover.
- Two further icon slots are **reserved and sized** to the left of the sliders glyph but render nothing.
  AI and extension actions live in the top-bar action capsule, not here.
- Click or `⌘L` → expands to the full URL, selected, in edit mode. `Esc` reverts.
- **Dormant at rest.** The pill is a bordered plate on the sidebar's plane until it is hovered or opened
  for editing, and it takes its glass then. Constant glass made it the brightest thing in the column — a
  second lit surface directly under three lit circles, pulling the eye to an address the user already
  knows. **No accent ring while editing**: the material is what says the pill is live.
- **It does not take the page's colour.** See §2: the wash is withdrawn, and the pill is the same
  `Surface.well` on every site.

#### 3.2a Site menu
The sliders glyph opens a plain `NSMenu` — on macOS 26 that *is* the liquid-glass menu, with the
system's own material, blur, submenu chevrons, keyboard navigation and Reduce Transparency handling. It
is one menu, shown from the sidebar pill and from §4's; the top-bar copy adds Reload at the top, because
§4 gives that layout no reload button.

| Item | Scope | Wired to |
|---|---|---|
| Share… | page | `NSSharingServicePicker.standardShareMenuItem` |
| Copy Link | page | `NSPasteboard` — URL **and** string, so a plain text field gets the address |
| Block Ads & Trackers | **per site** | `ContentBlocker.isDisabled(forHost:)` / `setDisabled(_:forHost:)` |
| Automatic Picture-In-Picture | **per site**, default on | `SitePermissions` → `TabController.enterAutomaticPictureInPicture` |
| Local Network | **per site**, default off | `SitePermissions` → a `WKContentRuleList` that refuses private-network loads |
| Site Settings ▸ Clear Cache / Clear Cookies | **per site** | `WKWebsiteDataStore.dataRecords`, filtered to this site's registrable domain |
| Site Settings ▸ Advanced Settings | app | opens SETTINGS-SPEC §3.9 |
| Connection is secure | page, disabled caption | scheme plus `WKWebView.hasOnlySecureContent` |

- **Per-site is the whole point.** "Block ads" as a global preference is a decision made once and then
  fought with on the four sites it breaks. These answers are taken about *this* site, where the problem
  was noticed, and they are the only place those answers can be given — SETTINGS-SPEC §3.3 has given up
  its copy of the exemption list rather than keep a second one a window away.
- **A checkmark means the thing is on for this site**, not that an exemption is: Block Ads & Trackers is
  ticked when blocking is running here.
- **Automatic Picture-In-Picture is JavaScript because WebKit gives no other door.** `WKWebView` can
  *close* every media presentation and there is no matching call to open one; `webkitSetPresentationMode`
  is what Safari's own automatic PiP drives. The video must be playing, unmuted and at least 320 px wide
  — a muted background autoplay banner popping out over the screen is the feature at its worst. Coming
  back to the tab always puts the video back in the page, permission or not.
- **Local Network is a content rule list, and a page served *from* the local network is exempt.** macOS
  asks an app once whether it may reach the LAN; a browser has to ask per site, and WebKit exposes no
  per-origin hook. What a rule list does well is refuse the loads: a page that has not been given the
  permission cannot fetch `192.168.1.1`, `printer.local` or `localhost`. `unless-top-url` carries the
  same patterns as the trigger, so `localhost:3000` may load its own assets and reach the rest of the
  LAN without being asked — the difference between a permission and a firewall.
  > **No `|` anywhere in those patterns.** WebKit's URL-filter engine takes a documented subset of
  > regular expressions and it is smaller than it looks: `Disjunctions are not supported yet` is what
  > `([:/]|$)` came back with. Alternation is spelled out as separate patterns, `172.16–172.31` is three
  > character classes, and `\d` is not available either. A test hands the JSON to WebKit, because the
  > compile is a fire-and-forget `Task` and a refused pattern fails completely silently.
- **The glyphs are in the titles, because `NSMenuItem.image` is not drawn on this macOS.** Measured with
  five images on five items — template symbol, non-template symbol, explicit 16 pt, a plain red square
  and a named AppKit template — in Luna and in a bare test app: none appeared. `SidebarMenu.label`
  (§3.4a) puts the symbol in `attributedTitle` instead, and this menu and the tab menu share it, so the
  two cannot drift apart on size, tint or alignment. `SiteMenu.Glyph` names every symbol in one place
  and a test walks it: a misspelt name costs the icon silently, leaving one item out of the column.
- **Share arrives with an image and it is cleared.** `standardShareMenuItem` is the one item on this
  build whose `image` macOS *does* draw, so dressing it while it still had one showed two share glyphs
  side by side; AppKit's own is a size larger and a few points left of the column the rest sit in.
- **§4's Reload row is dressed by the same helper.** That layout has no reload button, so its copy of
  this menu grows a row at the top — the only item here that one layout adds, and the one that would
  otherwise be the single glyph-less line in a menu of glyphs.
- **A disabled caption needs no quieter ink.** AppKit dims the whole item, attached glyph included;
  applying secondary ink on top of that reads as faded rather than quiet. Measured, both ways.

#### 3.2b Page bar — the pill and §3.1's three circles, on a bar over the page
`Settings ▸ Appearance ▸ Search bar` (SETTINGS-SPEC §3.2) moves the pill out of the sidebar and onto a
bar across the top of the content pane, taking the sidebar toggle, back and reload with it. The sidebar
keeps its tabs, its Essentials and its bottom bar — and its top 52 pt, because that row is what keeps
the traffic lights' corner clear; with its buttons gone it shrinks to `sidebarHeadlessRow` and the
column closes up over the pill's own 34 pt.

| | Open | Collapsed |
|---|---|---|
| band | `pageBar` (52) | `pageBarCollapsed` (30) |
| controls | toggle · back · reload, on the traffic lights' centre line | gone |
| pill | `pageBarPillWidth` (420) wide, `sidebarCircle` tall, `.glass` | **the same frame**, `pageBarCollapsedPillHeight` (22) tall, `.bare` |
| glyph | sliders on the **leading** edge, domain centred | **none** — the strip carries the address and nothing else |

- **The bar is a plane in the page's own colour**, from `TabState.pageBackground` — WebKit's
  `underPageBackgroundColor`, which is the colour the document is actually painted on. Not
  `themeColor`: that is a decoration a site may offer and most do not, while this is measured from the
  document and is always there.
- **And the plane follows the page down.** `pageBackground` is one answer for a whole document, so a
  bar wearing it stayed white all the way down a site whose second section is black — the plane stopped
  being the page's top edge the moment the page moved. What is under the bar is a question only the page
  can answer, so the scroll script answers it too: three points across the top of the viewport, each
  taking everything painted at that pixel — `elementsFromPoint`, front to back — and stopping at the
  first opaque background. **Down the z-order, not up the DOM**: an ancestor walk was tried and is
  wrong in the ordinary case, because a site with a sticky transparent header over a dark section
  answers *white* — the header is what is under the point, its ancestors are the body, and the dark
  section is a sibling painted behind it. Measured on `getroosta.app`: the ancestor walk said
  `255,255,255` where the stack says `12,12,13`. The three have to **agree** — the bar is one colour
  across the whole pane, so a top edge that is two colours has no right answer, and the sample says
  nothing rather than picking one. Nothing means the document's own
  background, which is what a centred card on a tinted page wanted anyway. The change crosses on
  `Motion.themeWash`, the same 0.25 s a navigation changes it on. The hit tests are the cost, so the
  sample is skipped for moves under 4 pt and re-taken on a resize — the viewport's top edge moves
  without a scroll when the bar itself changes height.
- **It had to be a plane, and the reason is measured.** Floating controls over the page were tried
  first. No material in Luna can react to a page — `NSGlassEffectView` composites what is behind the
  *window*, and `NSVisualEffectView` will not sample a `WKWebView`'s out-of-process layer (§2,
  `Glass.peekPlane`) — so over a white site the glass showed a light desktop and three white circles
  disappeared into a white page. A plane taken from the page reads as the site's own top edge and, more
  to the point, is a *known* surface for the controls to stand on.
- **The bar wears the appearance its plane calls for.** Everything drawn on it resolves from an
  `NSAppearance`, so `NSColor.wantsLightInk(in:)` picks one for the whole subtree and the domain, the
  glyph ink and the glass fallbacks all follow. A dark app over a white site gets dark glyphs on the
  bar and light ones everywhere else: the bar is the one surface in Luna whose background is not
  Luna's.
- **The collapsed pill is not sized to its address.** It was, and a capsule a point short of its own
  text does not lose a pixel off the last letter — it drops characters until an ellipsis fits, which is
  what turned `apple.com` into `apple.c…`. It keeps the open pill's width instead, which puts the
  question out of reach: the open pill has a glyph to clear that the collapsed one does not, so the
  collapsed one has strictly more room than the address it is showing needs.
- **The bar stands above the page, not over it.** It takes the site's own colour, so laid on top it
  merged with the document's top edge and hid whatever the document had put there. The page starts
  below the band instead, in both states — which makes the 22 pt between them a real change of height,
  and the page reflows for it. That is affordable because it is rare: the bar changes state at most
  once per reversal of scroll direction, never once per frame, and the page's animation runs on the
  same `sidebarCollapse` spec so the two arrive together.
- **The page decides which state.** At the top of a document the bar is open; once the page has
  scrolled `pageBarScrollSlack` past where the bar last answered, it collapses to the thin strip of
  site colour with the domain in it. Scrolling back up by the same slack, reaching the top, or arriving
  anywhere new opens it again. The rule is `PageBarScroll`, a value with no view in it, because the
  cases that matter are the awkward ones: a momentum wobble must not flip it, and a long scroll down
  must not mean scrolling all the way back before the address returns.
- **The change between them is a dissolve, not a move.** The pill keeps its frame across the collapse —
  the same x and the same width — and loses only its height, its glass and its glyph, where it stands.
  Both were worked out separately before: open, clear of the buttons; collapsed, sized to the domain and
  centred in what was left of the bar. Those are different sums whenever the buttons are in the way, so
  the address slid in from the side; and even once they shared a centre, the capsule's two edges still
  drew inwards from 420 pt to the width of `apple.com` while the material faded, which is the same
  sideways motion by another route. The glass and the glyph fade rather than cut, which takes some care:
  a glass backing's radius is fixed when it is built, so the height change forces a new one mid-fade,
  and it is given the alpha the old one had reached instead of the target it was heading for.
- **Arriving opens the bar, and arriving is more than a new address.** A load *starting* counts too — a
  reload, a form post and a same-address navigation all leave the URL exactly where it was, and every
  one of them is an arrival. And the first offset a new document reports is treated as where it
  *starts*, not as a scroll: WebKit restores the scroll position on a reload and on back/forward, and
  plenty of pages jump to an anchor of their own as they load, so the first thing heard from a document
  can be `y = 4000`. Measured from an anchor of zero that reads as a long scroll down, and the bar
  collapsed the instant the site appeared — at exactly the sites where the address was most worth
  showing.
- **Pressing the address opens the bar.** A press on the collapsed capsule used to start the editing
  inside 22 pt of it — a whole URL or a query in a capsule sized to `apple.com`, with no buttons beside
  it and nowhere for §3.2b.i's list to go. It opens first, and the typing happens in the pill that
  grows out of it, so there is one place to type and it is always the open one. The bar is then held
  open for as long as the editing lasts, whatever the page does underneath: the scroll rule keeps
  running and is handed the bar back the moment editing ends. Return is the exception — a navigation is
  on its way and arriving opens the bar anyway, so it is not collapsed for the moment in between.
- **The offset comes from the page itself.** `WKWebView` publishes no scroll position on macOS — no
  `scrollView`, no KVO-able offset — so a passive, frame-coalesced listener posts `window.scrollY`
  through `TabController.scrollMessageName`. It is main-frame only: an ad iframe scrolling itself is
  not the page moving.
- **Only the band takes clicks.** The overlay is pinned to the whole pane so the suggestion list below
  the pill can be clicked at all (hit testing stops at a superview's bounds), and `PageChromeBar.hitTest`
  gives everything outside the band back to the page.

##### 3.2b.i Suggestions under the pill
Typing in the pill drops §3.4's completions below it on the §5 popover material, the same width as the
pill and lining up with it rather than with the bar.

- **`SearchSuggestions` and nothing else.** That object owns the one network call in the query path,
  states exactly what leaves the Mac, and exists so `UI/CommandBar` stays free of a wire. A second
  fetcher here would be a second answer to a question that has one. It is not `CommandBarResultsView`
  either: that ranks tabs, history and commands around `CommandBarResult`, which is §9's model, and
  borrowing it would put a `UI/CommandBar` type on a surface `CommandBarPrivacyTests` does not cover.
- **The selection is §9.2's**: one `.control` glass pill that moves between rows on
  `Motion.selectedRowMove`, not a fill switched on and off per row. One backing instead of five, and
  the movement is what makes the highlight readable while the arrows are held down.
- **The list opens on the first suggestion**, so Return takes it without arrowing down first. What was
  typed is still a real entry and still reachable: ↑ off the top of the list lands on it, as does ↓ off
  the bottom — the same way out at either end, rather than a wrap. With no phrases the arrows are left
  alone and the caret moves as it would in any text field.
- **A row paints nothing of its own**, hover included, exactly as §9.2's rows do not. A second grey
  plate that lit under the pointer and then stayed there read as a second selection — one the keyboard
  could not move. Selection changes the *ink* instead: §3.4's "brighter text", as a step from secondary
  to primary rather than a fade, because §1 forbids separating tiers by alpha alone.
- A row commits on **mouse-down**: the field is first responder while the list is showing, so a click
  anywhere else ends editing, and by mouse-up the list had already gone.

### 3.3 Essentials grid — reshapes around how many tiles are in it
- Tiles 128 × 42, radius 12. **The sides are an alignment; the top, the bottom and the gutter are
  gaps, and they are not the same number.** The grid is inset `rowInset` (8) from the sidebar's leading
  and trailing edges, because the tiles have to agree with the URL pill above and the row pills below.
  Its gutter between two tiles side by side is **5**; the gap between one row of tiles and the next, and
  the margin above the first row and below the last, are both **6**. A full row-inset between two tiles
  read as two separate controls that happened to be side by side, and the same number above them pushed
  the block a visible step away from the pill it belongs under. Across and down are different distances
  even at the same length — a horizontal neighbour is a hand's width away, a vertical one is directly
  underneath — so they are separate numbers. **Tile width flexes:** the grid must survive the
  160–420 pt resize range.
- **Two across was a fixed number, and a fixed number is wrong at both ends.** One pinned tab sat in a
  half-width tile with a hole beside it; eight made four rows of the narrowest column on screen. The
  shape is derived instead — `EssentialsGridView.shape(for:)`, static and pure for the same reason
  `ChromeState.cardInsets` is: **as few rows as will hold them, then as evenly as they divide.** Four
  across is the ceiling, so `rows = ⌈n/4⌉` and `columns = ⌈n/rows⌉`. That gives 1, 2, 3 and 4 across in
  one row, then 3 + 2 for five, 3 + 3 for six, 4 + 3 for seven and 4 + 4 for eight. Five spreads to 3
  and not 4 because the columns come from the row count, which is what makes it read as 3 + 2 rather
  than as 4 + 1. A short last row is **left-aligned** — the grid fills in reading order, and a centred
  orphan breaks the column the tiles above it stand in. The tiles change width to fill the row; height,
  radius, gutter and icon stay the tokens they were.
- **The shape counts the slot a live drag is holding open**, so carrying a fifth tile up reshapes the
  grid to 3 + 2 while the lift is still in the air rather than after the drop.
- **A live drag holds a slot open.** `dropIndex` is the slot §6.6's lift is over: the tiles step round
  it, the grid grows by a row when it needs to, and the outline is drawn there rather than only in an
  empty grid. The tile being carried is taken *out* of the grid (`draggedID`) for the length of the
  gesture, so the slot index under the pointer is already the index the tab lands at.
- **A tile moves on the same gesture a row does, and stays a tile up here.** Picking one up lifts it as
  a tile, and it is the one place in the sidebar where a lift moves sideways: two columns are two
  positions, and which one you are over is a question only the pointer's `x` can answer. **It is not
  snapped to a slot while it is in the air** — jumping between two positions as the pointer crosses the
  gutter reads as the tile being taken off you and put somewhere. It goes where the hand goes, bounded by
  the grid, while the grid's own outline says where it will land; letting go is the movement that puts
  it there, and the tile it is standing in for stays hidden until the lift has come to rest on top of
  it.
  > **The move is committed before anything is revealed, and the revealed tile is placed first.** The
  > row and the tile the lift stands in for are hidden, not gone, and they are hidden where the tab came
  > *from* — so putting them back before the model has moved shows the tab in the place it just left.
  > A hidden tile is also not laid out, so it still carries the frame it had when it was picked up, and
  > the pass that reveals it is an animated one: it reappeared at its old slot and slid to the new one
  > under the lift that had just settled there. Commit, place, then reveal.

- **Pinning the tab you are looking at keeps its page.** Pinning drops a tab's web view to save a
  WebContent process (§19.2), which is right for a tab you are filing away and wrong for the one on
  screen: the pane went blank under the pointer, mid-gesture, and the site you had just dragged up there
  had to be re-loaded by clicking the tile you had only just made. The current tab keeps its page; the
  live-tab budget reclaims it on the way out like any other. Carried down
  into the list it becomes a row — the tab is unpinned and behaves like any other — and carried back up
  it becomes a tile again. Dropping one on a slot it already occupies is a reorder inside the Essentials
  section; dropping a *row* there is a pin, which also puts the page away (§19.2).
- **A tile remembers the link it was pinned at, and closing it goes back there.** `Tab.pinnedURL`
  (schema `v3`) is set when the tab is pinned and cleared when it is unpinned — the address the user was
  looking at when they decided to keep it, not wherever the site walked afterwards. That is what makes
  the two ways a tile's page goes away different things:
  > **Filed away** — pinning a tab that is not on screen, or §19.2's budget reclaiming a cold one.
  > Nothing was decided about the page; it simply costs a WebContent process to keep. The blob stays, and
  > clicking the tile lands where you left off.
  > **Closed** — `⌘W` on the tile. That *is* a decision, and it is "I am finished with this page". The
  > tile stays, because a tile is a place you keep; the page does not, so `url` returns to `pinnedURL`
  > and `interactionState` is dropped — top of the page, no back/forward history.
  >
  > Both end in the same visible state, which is why they used to be one call and looked right until you
  > closed a tile and clicked it again. Order matters inside the closing one: `discardController` caches
  > the blob it captured onto the row on its way out, so clearing `interactionState` first would put the
  > closed page's history straight back on the tab it had just been taken off. A tile from before `v3`'s
  > backfill has no home and is filed away instead — nil means "no home", and inventing one out of the
  > current address is a worse answer than the behaviour that was already there.
- **Icon only, centred, 16 pt.** No label. Visually distinct from the text rows below (§30.5).
- **Dormant, and glass when it is the tab you are on.** A tile at rest is `Surface.hover` plus a
  hairline; the material arrives when the tile is selected or hovered and leaves with the pointer.
  There is **no accent ring** — glass is Luna's highlight, everywhere, and nothing in the chrome turns
  blue to say "this one".
- **Pinning and unpinning animate.** Tiles are keyed by tab, so one survives a pin, an unpin or a
  reorder and travels to its new slot on §6's `tabInsert` spring; a new tile fades up, a removed one
  fades out where it stood, and the list below slides with the grid's height instead of snapping.
  > **A tile that has just been made does not travel, because it has nowhere to travel from.** It is a
  > fresh view, so its frame is the grid's own origin until something places it, and the pass that
  > places it is the animated one — so a pin ended with the lift coming to rest in the right slot and a
  > second tile then flying up to it out of the foot of the leading edge. It lands in its slot and fades
  > up there; the tiles that were already in the grid still travel, because they have somewhere to come
  > from. Same rule as the hidden tile above, and the same symptom that gave it away.
- **Pinning** (§6.6's other half): right-click a row → *Pin* (§3.4a), or drag it up into the grid. Pinning
  moves the tab into the Essentials section **and puts its page away** — the tile is the tab, so the page
  costs no WebContent process until it is clicked again (§19.2). A pinned tab cannot be closed, only
  unpinned (right-click → *Unpin*, or drag it back down); `⌘W` on one puts the page away and leaves
  the tile.
  > **A tab dragged across the grid's edge is selected by the drop.** Carrying a tab up into the grid or
  > back down out of it is a decision about *that* tab, taken with it under the hand, and a drop that
  > left the previous page on screen made the tile you had just made look like it belonged to something
  > else. So the drop selects it, and selecting it is also what loads it — unpinning does not wake a page
  > on its own (§19.2). A reorder *within* a section is not that: shuffling the list is housekeeping, and
  > it leaves the selection alone.
  > **Selection is taken before the pin, not after.** `pinTab` puts a cold tile's page away and spares
  > only the tab that is already current, so pinning first would tear the live page down and rebuild it
  > from `interactionState` a moment later — under the pointer, mid-gesture. `pinTab(selecting:)` moves
  > the selection first and the existing "except the page you are looking at" branch does the rest.
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
  > **And no focus ring on a click.** AppKit makes a clicked control that accepts first responder the
  > window's first responder and draws the accent ring round it — a blue halo on a pinned tile, which is
  > the one colour Luna's chrome never uses. A press already says which control you are on, because the
  > material lights up under it; the ring is restored the moment focus arrives from the key loop, which
  > is the case §20.2 is about.
  > **No accent anywhere on it.** The pill used to take an `Accent.tint` border while the list had focus.
  > A blue ring around the current tab is a system list; Luna's selection is the glass plus §3.4's wash,
  > and the hairline is `Line.border` in every focus state.
- **Status dot** leads the row only when the tab has unread/updated content (the Discord row in the
  reference). Audio gets a **trailing** speaker glyph, click-to-mute.
- **Hover** reveals a trailing close affordance and lifts the row fill to 6 %. It is an 11 pt `xmark`
  inside an **18 pt hit target**, inset a full `rowInset` inside the pill's trailing edge. The
  rounded-square **chip is drawn only while the pointer is on the chip itself**, together with a
  *Close Tab* tip: the square is that control's own affordance, and painting it for the whole row put a
  grey tile on every row the pointer merely crossed. Pressing it closes the tab (§6.3 — archived, and
  undoable).
  > **Whatever is drawn is what is hit, and the row is resolved when you press.** The speaker and the
  > `xmark` share one slot, so the affordance reports the glyph it was actually showing rather than the
  > list re-deriving it from hover — a second chance to disagree. And the row a press belongs to is
  > looked up from the view at that moment: the table builds a row view once and then moves it up the
  > list as tabs are closed above it, so a row index captured when the view was made goes stale, and
  > pressing close on a tab used to mute the tab underneath it.
- **Today's tabs stack newest-first.** A new tab goes to the *top* of the section, not the bottom: the
  list is a record of what you are doing and it is read from the top, and a tab appended to the end of a
  long day's browsing opens off the bottom of the scroll — the one tab you certainly want to see is the
  one you cannot. Pinned tiles and Favorites are the opposite and still join the end, because those are
  slots the user placed deliberately and a new one must not push the arrangement down.
- **Selected and hover fills are `Surface.selected` / `Surface.hover`.** Clear glass alone is very nearly
  the sidebar's own glass, and a selected row read as unselected until these were asked for.
- Loading shows a shimmer sweep across the title, not a spinner.
- `+ Add Tab` is a first-class row with identical metrics to a tab (§30.6).
- **The unread dot is ink, not accent.** It was `Accent.tint`; it is `Text.primary` now, and it reads
  because it is bright rather than because it is a different hue.
- **Reordering is a tracked gesture, not a dragging session** (§6.6). A press past `dragThreshold`
  lifts the row: the pill, the favicon and the title travel as one view, locked to the sidebar's own `x`
  and following the pointer's `y`, while the rows between the tab's old slot and its new one slide by
  exactly one row to open the gap under it. Carried up into §3.3's grid the lift **becomes a tile** —
  the same view, a tile's geometry, §6's `tabInsert` between the two — and the grid opens a slot to
  receive it; carried back down it becomes a row again.
  > **Why not `NSTableView`'s own drag and drop.** AppKit hands the pointer a snapshot that floats free
  > in two dimensions, can be carried out of the window, and leaves the list static behind it. A sidebar
  > tab has one degree of freedom. None of "lock it to the column", "carry the row's own highlight" or
  > "morph into a tile" is something a dragging session exposes, so the gesture is tracked by hand and
  > the table is a drag *destination* only.
  > **Nothing is committed until the mouse comes up.** The gap is drawn by offsetting row views, which
  > costs nothing and is thrown away by the reload that follows the drop; a reorder committed per row
  > crossed would be a SQLite write and an undo entry each time.
  > **A lift arriving from the grid opens the same gap.** An Essentials tab is not a row in the list at
  > all, so there was no dragged row to measure the gap from and the list sat still while a tile was
  > carried down over it. The incoming gap is the simpler of the two — the landing row and everything
  > under it step down by one row, and nothing closes up behind — and the list's two row pills are parked
  > either way, because the lift is carrying §3.4's pill itself.
  > **There is no drag and drop left in the sidebar.** With the §3.3 tiles on this gesture too, nothing
  > in the column is an `NSDraggingSource` or an `NSDraggingDestination`, and `SidebarDrag`'s pasteboard
  > type is gone. A §3.5 Space dot is the lift's third landing place, beside the list and the grid.
  > **Every step is a haptic tick.** The pointer moves continuously and the list does not — it *steps*,
  > as the lift changes places with one neighbour — and that step is `Tokens.Haptics.step()`, fired the
  > once per crossing, in §3.3's grid and §3.4's list alike. The pattern is `.alignment`, which is what
  > the system itself uses when something snaps into a position: a shape onto a guide, a window onto a
  > screen edge. The first target of a gesture is not a step — nothing has been passed yet — so it is
  > silent. It is also silent on any Mac without a Force Touch trackpad, and that is correct rather than
  > broken: `NSHapticFeedbackManager.defaultPerformer` already honours System Settings ▸ Trackpad, so
  > there is no Luna setting for it and nothing to check before calling.

### 3.5 Bottom utility bar — 52 pt, pinned
`[profile avatar circle 34, left] ··· [space dots pill 56 × 22, centred] ··· [downloads | history, right]`

> **Downloads and History are one cylinder, not two circles.** They are the same kind of thing — the
> shelf of what you already have, glanced at rather than worked in, both opening as a pop-out that stands
> on its own button — and §4's action capsule pairs the same two at the other end of the window. Two
> glass discs 5 pt apart read as two controls that happen to be near each other, each with its own
> specular rim catching the light at a different angle; the material is applied **once**, at
> `bottomCircle.height / 2`, and the two buttons inside it are bare glyphs. Same finding, same fix, as
> the action capsule's. The cylinder is exactly one `bottomCircle` tall — two of them fused, not a new
> size — so the foot stays one row of equal-height controls.
> **The other home considered was §3.1's control row**, and it is the wrong one: that row is where
> *actions on this page* live, and a finished download is not one of those.
> **The pill is centred in the bar while it fits, and in what is left when it does not.** The dots widen
> by 8 pt per Space beyond three, so "does it fit" is not a question §1's minimum can settle once:
> clamping to one side would slide the pill under one cluster and leave clear air under the other, so the
> overflow is centred instead and stays symmetrical.
#### 3.4a Tab context menu — right-click a row, or a §3.3 tile
`[Pin] · [Duplicate] · [Copy Link] · [Rename… | Change Icon… | Mute Site] · [Close]`

Seven items in five groups, taken from `inspiration/tab-context-menu.png`. A plain `NSMenu`, for the
reason §3.2a gives: on macOS 26 that **is** the liquid-glass menu — AppKit draws its own material,
its own blur, its own submenu chevrons — and a hand-rolled panel would be a worse copy that also had
to reimplement keyboard navigation, VoiceOver and Reduce Transparency.

> **The glyphs are in the titles, because `NSMenuItem.image` draws nothing on this macOS.** §3.2a
> recorded that as a dead end; it is a dead *property*, not a dead requirement. Re-measured with a
> five-way probe in a bare AppKit app — a plain system symbol, one through
> `withSymbolConfiguration`, one explicitly sized with `isTemplate` on, a hand-drawn red square and
> a named AppKit template — and **none of the five appeared**. An `NSTextAttachment` in
> `attributedTitle` is drawn, because it is text rather than a menu image, and it keeps everything a
> custom `NSMenuItem.view` would have cost: the native highlight, arrow-key navigation, the
> key-equivalent column on the right, and the plain `title` underneath for VoiceOver and type-select.
> A **tab stop** at `menuGlyph + rowIconGap` is what lines the words up in a column instead of each
> one starting after its own glyph — the same two tokens §3.4's rows use for the same relationship.
> The symbol is tinted by hand rather than left as a template: the thing drawing it is a text run,
> which tints nothing, so an untinted template comes out black on a dark menu.
> **`menuGlyph` is 12 pt, two under the `menuSwatch` beside it.** A swatch is a solid disc and reads
> at any size; a symbol is a line drawing, and at 14 it was heavier than the word next to it and
> pulled the eye off the text. 12 sits just under the menu font's cap height, which is where a glyph
> introduces a label instead of competing with it.

> **The reference has seventeen items and this has seven, and the ten missing are declined rather
> than deferred.** Split, Chat With This Tab, the three Group commands, Move to Profile, Move to
> Window and both Bookmarks rows are features Luna either does not have or reaches another way, and a
> menu that lists what an app cannot do teaches the user to stop reading it. *Copy Link as Markdown*
> becomes plain **Copy Link**, which is the same pasteboard §3.2a's site menu writes — copying a link
> from the row and copying it from the pill must not produce two different answers.
> **The groups stay even though most now hold one item.** The grouping is what makes seven items
> scannable at a glance: the one that files the tab away, the one that copies it, the three that
> change what it *is*, the one that ends it.

- **One menu, both halves of the sidebar.** A §3.3 tile is a tab, so a tile gets this menu too, with
  *Pin* reading **Unpin** — which is the item §3.3 has promised since the grid was built and never
  had. A shorter, second answer to the same right-click would be two menus, not one.
- **Every item closes over a `UUID`, never a row index.** The table recycles row views and moves them
  between rows, so an index captured when the menu was built is stale as soon as a tab is inserted
  above it — the bug that once made pressing close on one tab mute the tab underneath (§3.4).
- **Duplicate carries the session, not just the address** (`interactionState`, read off the live
  controller where there is one — the row's copy is only as fresh as the last settled load, §6.2).
  You duplicate a tab to keep the trail you are on and go somewhere else from it. The copy lands
  directly below the original; a duplicate of a *tile* is an ordinary tab, because a tile is a place
  the user put something and it is capped at twelve per Profile.
- **Rename and Change Icon persist; Mute does not.** `Tab.customTitle` and `Tab.customSymbolName`
  (schema `v4`, two nullable columns, no backfill) outrank the page's own title and the site's
  favicon everywhere a tab is drawn — the row, the tile, §6.6's lift, and §9.2's switch-to-tab rows,
  which also *search* by the name the user gave. A mute is a decision about the noise a page is
  making now: a tab that came back silent after a relaunch, with nothing on screen to say why, is a
  bug report, not a feature.
  > **Nil is not the empty string, in both columns.** Nil means "the user has not named this tab" and
  > the page's title answers; a stored `""` would look identical in the sidebar and keep overriding
  > the page's title with nothing forever. So a rename to blank normalises to nil, which is also the
  > way back — the dialog says so, and puts the page's own title in as the placeholder.
  > Both are picked, not typed: the icon comes from a curated list for the reason §3.7's Space icon
  > row gives (a symbol name that does not resolve draws *nothing*, and a text field cannot say which
  > of the six thousand names it is), and it is its own list rather than the Spaces one — a Space icon
  > names a mode and a tab icon names a page, so the two vocabularies barely overlap.
- **Mute is per tab and it really mutes.** There is no public WebKit API for it: Safari's rides on
  `_setPageMuted:`, which is SPI, and the two public calls that come close are the wrong shape —
  `pauseAllMediaPlayback()` stops the picture too and `setAllMediaPlaybackSuspended(true)` refuses to
  let it start again. Mute means *keep playing, quietly*, which is a property of the media elements,
  so it is set on the media elements and kept there by three things: a `volumechange` listener in the
  **capture** phase (media events do not bubble — the same finding §4.3's audible-tab badge is built
  on), a `MutationObserver` for the players every modern site builds in JavaScript, and a re-assert on
  `didCommit` rather than `didFinish`, because an autoplaying page is making noise long before the
  load settles. Its one honest limit: `evaluateJavaScript` does not reach subframes, so an embedded
  player in an iframe keeps playing and the row's speaker badge — which *is* injected into every
  frame — is right to keep showing.
  > **The mute lives on `BrowserSession`, not on the `TabController`.** A controller is thrown away
  > every time a tab goes cold (§19.2), so a mute held there would evaporate and the tab would come
  > back making noise; `ensureController` re-asserts it on the way up. §3.4's speaker glyph reads the
  > same set, which is what stops the row and the sound disagreeing.
- **`Close` shows `⌘W` and does not install it.** A context menu's key equivalents are live only
  while it is open; the rest of the time §20.1's responder chain has the command. On a tile, Close is
  still §3.3's "send the tile home".


> **It is called History and it carries a clock.** Luna's internal word for the shelf is "the archive";
> the user's word for what they are looking for is "history". The glyph is `clock.arrow.circlepath`,
> because a box means storage and a clock means "earlier".
> **It opens a pop-out from the button, not a tab and not a panel over the page.** Looking something up
> in your history is a glance, and a glance should not leave a tab behind to close afterwards — and a web
> page cannot be Liquid Glass, so the one surface in the app that is *about* the tabs looked like a
> website. `HistoryPanel` is an untinted `.popover` body **standing on the History button**: 320 × 420
> (a ceiling), leading edge aligned to the button, foot a `historyPopoutGap` above its head, growing
> upward because up and across is where the window is. `esc` or a click outside dismisses it. Title and
> filter share one line, the filter is §3.2's `Surface.well` pill, and the rows are §3.4's — favicon,
> title, a quieter host · date, a fill that lifts on hover. Choosing one unarchives the tab where it was.
> `luna://archive` still resolves and still renders, because a URL someone has bookmarked should not stop
> working; nothing in the chrome navigates to it any more.
> **It was the Command Bar's shell, and that was the same mistake one size smaller.** Scrim, a 640 pt
> body, centred over the pane: a glance at a shelf took the whole page away and put a window-sized panel
> where the user was not looking. The Command Bar earns that — you summon it, and it is the thing you are
> doing. History is opened *from a button*, and a surface opened from a button belongs on it. What is
> left of the overlay is a transparent sheet that catches the click that dismisses it, which is exactly
> what an `NSMenu` puts up and for the same reason. **The shadow does what the scrim used to:** with no
> backdrop behind it the panel has only its own edge, so it carries `Shadow.popover` — the token §6.6's
> drag lift already uses. It grows out of the button on §6's `commandBarIn`, anchored at the corner
> standing on it rather than at its own centre.
> **Every row is one width, and it is the list's.** A pill measured off each row inherits whatever that
> row's own stack negotiated, so a long title and a short one highlighted differently — and a row wider
> than the list put glass over the panel's own rounded edge. The pill takes `x` and width from the list,
> inset `rowInset`, and only `y` and height from the row. The stack is `.width`-aligned rather than
> `.leading`, so the stack itself is the width every row has; the scroller is `.overlay`, because a
> legacy one is laid out *beside* the document and would take a scroller's width off the rows; and the
> scroll view carries a `panelInset` at each end, so the first and last rows are whole rather than sliced
> by the header above them and the panel's edge below.
> **The highlight is §9.1's, exactly.** One `.control` glass pill that *moves* on `selectedRowMove`,
> not a fill per row — the two lists are the same list of the same things over the same page, and a
> history panel that highlighted differently from the Command Bar would be two designs in one app. The
> pointer and `↓`/`↑` drive the same selection; the filter field owns the keystrokes, because it is what
> has focus, and hands them down.

- **Space dots** are the Space switcher: one 6 pt dot per Space, active dot 100 % white, inactive 35 %.
  Click a dot to switch; the pill widens by 8 pt per Space beyond three.
- Avatar is the active profile; click opens the profile menu.

### 3.6 Content pane
Opaque, **flush** to the window's top and bottom, flush to the window edge the sidebar is *not* on, and
flush against the sidebar. Only the two corners on the edge it **shares with the sidebar** are rounded,
at `windowCornerRadius`, so they nest with the window's own corners instead of leaving a crescent of
glass inside each one. With the sidebar on the right (§3.9) the whole thing mirrors, corner fill and all.
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

**The sidebar's plane is a window drag handle — and only the plane.** Pressing anywhere that is not a
control moves the window: the control row, the grid's background, the rule under `+ Add Tab`, the empty
list below the last tab. `NSTableView` swallows that press by default, which left the top 52 pt as the
only place in a 280 pt column you could pick the window up by.

> **Every control has to say so, one at a time.** `NSView.mouseDownCanMoveWindow` answers `true` for any
> view that draws no background of its own, which is every glass surface in Luna — so on a window that
> moves by its background, the press that should have picked a pinned tile up picked the *window* up
> instead, and the tile never saw it. `GlassButton`, the URL pill, a Space dot and the resize handle all
> answer `false`, and a `GlassBackingView` hit-tests to nil: it is decoration filling its host edge to
> edge, so wherever the host has no glyph it was the deepest view under the pointer.

**The page is revealed, not resized.** For the length of a chrome transition its width is a constraint of
its own, set to the *destination* width before the chrome starts moving, with the page anchored to the
card's trailing edge. So a sidebar collapse costs WebKit **one** relayout instead of one per frame of a
0.20 s slide, nothing under the pointer shifts, and a heavy site stops stuttering on `⌘S`.

> **That width is never the resting state.** It was, and a constant carries no relationship, so it had to
> be re-derived from `bounds` on every layout pass — and a constraint constant written from inside
> `layout()` is not reliably picked up, because the pass that would read it has already run. A window
> resized in one jump (the zoom button, or a hidden sidebar) left the page at its old width with the
> pane's own grey showing beside it. At rest the page is pinned on all four edges and Auto Layout keeps
> it right for free; the width constraint is swapped in for the transition and swapped back out at the
> end, with a watchdog on the duration so a dropped completion handler cannot strand it.

Entering page fullscreen animates the pane to fill the window over 0.3 s.

### 3.7 Sidebar resize handle
An invisible 8 pt grab strip on the sidebar/content divider — whichever of the sidebar's two vertical
edges is the one the page is on. Drag resizes within 220–420 pt, double-click resets to 280. With the
sidebar on the right the pointer's meaning inverts: the width asked for is measured back from the
column's far edge.
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

### 3.9 Which side, and where the tabs go
**One setting, because it is one question.** `Settings.tabsPosition` is Left / Centre / Right, and the
layout decides which of those it can offer: §3's sidebar is a column, so it has two sides and no middle;
§4's strip runs along a bar, so it has all three. Settings ▸ Appearance ▸ **Tabs** rebuilds its segments
when the Layout row above it changes rather than dimming one — a disabled answer still has to be read
past, and "Centre" under the sidebar is not temporarily unavailable, it is an answer the question does
not have. A stored `.centre` is remembered rather than rewritten, and a sidebar reads it as the left.

**The default is Centre**, which is where §4's strip belongs and which the sidebar has always read as
left — so nobody's chrome moves who has not asked for it to.

> **The traffic lights do not follow the sidebar.** macOS puts them at the window's top-left and offers
> no API that says otherwise, so a right-hand sidebar leaves them floating over the page's top-left
> corner — which is what every browser that offers this does. §3.1's control row therefore stops
> reserving their space when it is not the thing they are on, and closes up around it.

### 3.8 Hover-peek — the hidden sidebar

With the sidebar hidden, pushing the pointer into the window's leading **44 pt** brings it back **over**
the page after §6's 0.10 s intent delay, and lets it go again 0.10 s after the pointer leaves both the
strip and the sidebar itself.

> **It was 4 pt, then 24, and both meant aiming.** A *screen* edge can be one point wide because the
> pointer piles up against it; a window edge has nothing to stop the pointer. The gesture is "shove the
> mouse over to the left", which lands somewhere in the first inch, and 44 pt is about the width of that
> shove. Nothing is spent on it: the strip never takes a click (its `hitTest` returns nil, so the page
> keeps every event), and the intent delay is what keeps a wide strip from firing on the way past.

- **The page does not move.** Only the chrome's leading constraint and its opacity animate; the card's
  insets stay collapsed, so nothing reflows for a glance at the tab list.
- The hidden sidebar parks at `-width` rather than collapsing to zero width: it keeps its layout, and it
  is one constraint away from coming back.
- The traffic lights come back with it, and go again with it.
- **The peeked sidebar stands on a plane of its own** (`Glass.peekPlane()`). The window's glass is
  behind the content pane, not in front of it, so a sidebar floating over the page had no background at
  all and the page read straight through the gaps between its rows. The plane is the same `.sidebar`
  material the window is made of, a sibling of the chrome so the host's clipping is not between the
  material and what it samples, sharing the chrome's four edges so it slides with it.
- **It is rounded on its trailing edge, and nowhere else** — §3.6's seam read the other way round. When
  the sidebar is on, the pane rounds the edge it shares with it; when the sidebar is floating in front
  of a flush pane, the corner belongs to the sidebar. `Glass.backing` takes a `maskedCorners` set and
  clips to it, because `NSGlassEffectView` has one radius and no corner set of its own.
- **And it carries the edge itself** (`rimmed`). §3.6's hairline is drawn by the *page*, on the side
  where the page meets the sidebar; a sidebar floating over a flush pane has no page edge to draw it, so
  the plane takes the same `Line.border` hairline round its own rounded edge. A material with no edge on
  it reads as a smudge rather than as a surface.
- **Nothing blurs the page.** Liquid Glass composites what is behind the *window*, and
  `NSVisualEffectView` at `.withinWindow` will not sample a `WKWebView`'s out-of-process layer — a
  hand-built plane of scrim + frost + tint was tried and the page came through it perfectly sharp. What
  the material gives instead is the right *surface*, which is what "floating" meant: over a website the
  peeked sidebar wears exactly the finish it wears over the wallpaper.
- The asymmetry is deliberate: the same delay guards both edges, because the pointer leaves the trigger
  strip the instant the sidebar arrives over it, and a zero-delay close would flicker.

---

## 4. Top-bar layout

One 52 pt glass bar spanning the window. **Content is flush full-bleed below it — no inset card, no gap.**

`[traffic lights] [back] [tab tiles …] [ACTIVE TAB pill] [tab tiles …] [hairline] [action capsule]`
> **There is no sidebar toggle on this bar.** There is no sidebar in this layout to hide, so the button
> either did nothing or silently changed a preference.
> **Back is a capsule of one**, and both ends of the bar are the same object. It was a bare glass circle
> of `TopBarMetrics.capsuleItem` — the same 28 pt *item* as the buttons at the other end, which is not
> the same *size*: the cylinder adds its padding, and one control at 28 beside three at 36 is the
> mismatch the eye catches. Same class, same radius, one item in it.
> **Switching the active tab animates.** The outgoing tab's pill collapses into a tile and the incoming
> tile expands into the pill, each seeded at the other's frame, with every tile after them sliding along
> on §6's `tabInsert` spring. The strip is one ordered run, and it used to jump.

- **Tabs are visible in this mode as a horizontal strip.** Inactive tabs render as 28 pt icon-only tiles;
  the **active tab expands into the URL pill** showing its domain, favicon and sliders glyph. This is why
  tiles appear on both sides of the pill and why the pill is not exactly window-centred.
  > This supersedes §30.12's claim that tabs are invisible in this mode.
- **No reload button** in this layout — the reference omits it. Reload is `⌘R` and the site menu.
- The strip scrolls horizontally when it overflows; the active tab is always scrolled into view.
- **Where the run sits is `Settings.tabsPosition`** (§3.9), and it is **centred** by default. "Centred"
  means centred in the span between Back and the hairline, not in the window: the two clusters it sits
  between are different widths, and a run centred on the window reads as off-centre between them —
  which is the thing the eye actually measures. When the tabs overflow the span the alignment stops
  meaning anything and the run scrolls from its leading edge. The clear run is padding *inside* the
  scroll view's document, because a document narrower than its clip view is anchored at the clip's
  leading edge whatever origin it is given.
- **Action capsule**: its own rounded glass capsule, separated by a vertical hairline, holding
  `[+ new tab] [history] [downloads] [profile]`. Extension action buttons dock here when extensions ship
  (v2) — build the capsule to host a variable number of items now.
  > **History is here because there is no sidebar to put it in**, and it sits beside Downloads because
  > §3.5 pairs the same two at the other end of the window. Profile stays last: it is about *who*, not
  > about *what*.
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

## 5. Downloads popover — and the list behind it

- **Renders outside the window bounds**, floating above the top edge, with a **visible pointer tail**
  into the downloads button. It is an `NSPanel`, not an in-window view.
- Size ~330 × 58, radius 14. Heavier glass than the bar, with its own shadow.
- Row: `[file-type icon 34] [filename, middle-truncated, 14 pt] [confirm button 30, radius 9]`
- Middle truncation is required — `97103328759-202…01-2026-08-31.pdf` keeps both the prefix and the
  extension, which head- or tail-truncation would each destroy.
- Appears on download completion, auto-dismisses after 4 s, or on confirm. Hovering cancels the timer.

**The list is a pop-out, not a panel.** §15.3's list — everything downloaded, with open, reveal, retry
and clear — was an `NSPanel`: a standard titled utility window with a table and a row of push buttons.
Pressing a button in Liquid Glass chrome and being handed that is a different application answering; it
takes focus off the page, it has to be closed rather than glanced away from, and it was the only surface
in Luna that looked like it was built in 2012. It is now §3.5's pop-out at `downloadsPanel`, standing on
whichever Downloads button the layout shows — down from §4's capsule, up from §3.5's cylinder — with
`⌘⌥L` opening the same thing. The completion popover above is untouched and is still an `NSPanel`,
because that one genuinely has to draw past the window's edge.

> `PopoutPanelView` is the shared surface: sheet, glass body, `Shadow.popover`, the two clamps and the
> spring. The only thing that differs between History and Downloads is **which way it grows** out of its
> button, so the caller says `.above` or `.below` and nothing else changes.
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
| URL pill theme wash | **withdrawn** — see §2 |
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
  > **The window is `isOpaque = false` with a clear background, like the browser's.** The column is
  > `.sidebar` glass, and glass composites what is behind the *window* — so on an opaque window it had
  > nothing to sample and came out as a flat plate beside a browser sidebar that is a pane of the
  > desktop. The pane on the right is opaque in its own right, exactly as §3.6's content card is.
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
