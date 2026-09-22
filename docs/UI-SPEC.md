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
| `sidebarWidth` default / min / max | 280 / **250** / 420 pt | min was 180, then 160, then 220 |
| `sidebarFootFloor` — the min where §3.1's head is not in the column | **220** pt | — |
| `sidebarFootWidth` — what §3.5's foot occupies, derived | 190 pt | — |
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
| `spaceDotsPill` / `spaceDotChip` | 56 × 22 pt, radius 11 / 14 pt (= `spaceDotPitch`) | — |
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
| §2's section row | **the sidebar's own**: `rowHeight` 38 / `rowPillHeight` 35 / `rowCornerRadius` 12 | `settingsSectionRow` 34 with a 24 pt icon tile |
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

**The tint survives the window going inactive, and Luna is what makes it.**
`NSGlassEffectView` drops `tintColor` the moment its window stops being the active one, and
there is no `NSVisualEffectView.state` to ask it not to. Measured on the sidebar, dark mode:
the plane went from 0.166/0.110/0.293 to 0.259/0.180/0.420 — half again as bright — every
time the user clicked into another app, and the difference was §2's tint exactly, black at
`Ink.glassTint`. So `GlassBackingView` paints the same tint over the material for the length
of an inactive window: the colour is the same in both states and only the layer carrying it
changes. Inactive now measures 0.172/0.118/0.278 against the active 0.166/0.110/0.293. It is
off in fullscreen and under Reduce Transparency for the reason the tint itself is — there is
no material there to have lost one.

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
> **The lights coming and going is not a layout change, and has to be made into one.** `⌘S` takes the
> traffic lights away with the sidebar and §3.8's peek lends them back; neither changes any view's
> bounds, so nothing in AppKit marks this row — which lays its toggle out *against* the lights — as
> needing another pass. Hiding the sidebar and showing it again therefore left the toggle where a row
> with no lights to clear correctly puts it: at the row inset, under the close button. Every view that
> places itself against the lights is a `TrafficLightNeighbour` (this row and §3.2b's bar), and both the
> peek and every chrome-state change mark all of them for layout.
> **Hover is a fill again, and a press is a shape** (M1). §3.1 has always said hover lifts the *fill*,
> and for a long time only the glyph could be lifted, because there was no translucent wash to lift a
> surface with. There is now: the three circles carry `Surface.hover` over their material under the
> pointer, `Surface.selected` under a press, and the press also swells the material 5 % and springs it
> back (§6). Back and forward are the exception that proves it — they are bare glyphs in the history
> capsule's material, so the *capsule* takes the swell.
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
- **Forward appears; it does not dim.** Back and forward are not the same answer to the same question.
  Back is on every page and is dimmed on the first one, so the eye learns where it is. Forward is
  unreachable on the great majority of pages — nothing has been gone back from — so a permanently
  dimmed chevron beside a live one would be a control that spends its whole life saying no. Once
  `canGoForward` is true the circle grows a second half and the two share **one capsule divided by a
  hairline**, which is the reference. One plate, two bare glyphs: a backing per chevron is what made
  §4's action capsule read as separate bright discs. `NavCluster`, used by §3.1 and §3.2b alike.
- **And the column's minimum width is the price of it.** The cluster is pinned to the trailing edge, so
  every point the second half adds is a point its leading end travels towards the toggle: at the old
  220 pt minimum the two overlapped by 22 pt the moment there was a forward to go to. `sidebarWidth.min`
  is 250 — the measured touching point is 243, and Martin asked for the smallest that does not overlap
  rather than the smallest that keeps a full `chromeGap`. `SidebarHeadRoomTests` runs that sum against
  the real row.
- **And 250 is only the price where that head is in the column**, which is one of the four cases
  §3.2b's placement and the sidebar's edge make between them. §3.2b takes the pill and these three
  circles onto the page, leaving a row holding nothing but the traffic lights' corner; and a trailing
  column does not contain the lights at all — macOS keeps them at the window's top-left — so its
  toggle starts at `rowInset` instead of 78 pt in, which is 86 pt off the 243. Either one puts the
  head under §3.5's foot, and then `sidebarFootFloor` answers: **220**. The foot itself occupies
  `sidebarFootWidth` — 190, derived from the tokens it is made of, the width at which the avatar, the
  Space strip and the Downloads/History cylinder close to exactly one `chromeGap` apart — and 220
  stands off it for the reason 250 stands off 243, plus the Essentials grid, which is the one thing in
  the column that keeps shrinking rather than stopping: a tile is 47 pt wide at 220 against 40 at 190.
  `Settings.sidebarWidth` is the single reader that resolves the two, and `SidebarWidthFloorTests`
  runs both sums against the real bar.
- **The morph stands still.** Nothing inside the capsule is laid out against its bounds — all three are
  placed off the leading edge at fixed distances — so the trailing edge is the only thing that travels
  and back never moves under the pointer. Measured against the bounds, a *shrink* re-reads them at the
  final width on its first frame: the divider jumps into the middle of back and the forward chevron
  slides left across it while fading. The fade is 0.20 s arriving, against an edge moving away from it,
  and 0.10 s leaving, against an edge coming at it — otherwise the chevron is at half opacity on the
  frame the edge sweeps through it and hangs outside a capsule that has already passed.

### 3.2 URL pill — full width less 8 pt each side, 34 pt tall, full radius, flush under the control row
> **Corrected:** not "12 pt below the control row". The 52 pt row already carries clear space below its
> buttons, and that *is* the gap the reference measures between reload and the pill. A second gap on top
> of it doubles a space that is already right.
- **Domain only**: `apple.com`, not the full URL (§30.3). eTLD+1 plus subdomain when meaningful.
- **A new tab shows the placeholder, not a name.** `Search or enter website name`, with nothing in the
  field and nothing selected when it opens for editing. `New Tab` is a label for a *row* in a list of
  tabs; in an address bar it reads as the name of a site you are on, and it stood where the one line
  saying what the bar is for should be. Luna's other pages keep their names — `History` is somewhere
  you actually are. "Website name" rather than "URL" because that is what people type: `apple.com`,
  not a scheme.
- Left-aligned text at 12 pt inset; trailing **sliders glyph** (site menu) at the same 12 pt from the
  right edge. It was 10 — a glyph is optically smaller than its box and can afford to sit closer in —
  and on §3.2b's 420 pt capsule that reads as intended, but in a 240 pt column, with the capsule's
  corner curving away right behind it, it read as site settings falling off the end of the pill.
  Whatever is at either end of a pill now stands as far in as the address does.
- **One affordance goes on the trailing edge; a second takes the other end.** That is where §3.2 has
  always drawn the sliders and where §3.4's rows draw theirs. A pill that also carries a reload —
  §3.2b's, which has 420 pt to put one in — moves site settings to the leading edge and keeps reload
  trailing; site settings is the one that says what the address *is*, so it leads. The sidebar's pill
  has no reload inside it: §3.1's circle is directly above, and this column is 200 pt wide with a
  domain already in it.
- **And the glyph is sized to the pill it is in, not to what stands beside it.** `barPillGlyphSize`
  (14) on §3.2b's bar and `pillGlyphSize` (13) in the column — and `glyphSize` (16) on neither. 16 is
  the size of a glyph that *is* its own button, which is what the toggle and the history cluster beside
  the bar's pill are; a glyph inside a capsule is measured against the address it shares the capsule
  with, and at 16 it was the loudest mark on the bar. The column takes the step further: the ink there
  is a finger's width from text set at 13. Hover **lifts the ink** rather than drawing
  §3.4's chip: a chip says "this mark you are reading is also a button", which is right on a tab row and
  wrong for a control plainly standing in a row of controls — and a rounded rectangle inside a capsule
  is two shapes.
- **The sliders glyph is an SF Symbol now** — `slider.horizontal.3`, the same family, weight and size as
  everything else in the chrome. It was drawn (see below) at a heavier stroke than its neighbours, which
  read as a different set of controls on a bar that has four of them.
- **The two reserved slots are gone.** §3.2 held two further glyph-sized places open beside the sliders
  for AI and extension actions, which §16.4 puts in §4's action capsule anyway. They cost 42 pt, and in a
  column barely 200 pt wide — with a real control at the end of it — that was most of the line: the short
  placeholder itself truncated, to `Search the…`.
- **No leading mark.** The pill wore one for a while — a magnifier while what was in it read as a search,
  a globe or the site's favicon while it read as an address. Martin's verdict was that an address bar is
  not where it belongs: a favicon at the head of the one line saying what page you are on is a second
  thing to read, on both surfaces and in both of §3.2b's forms. The rule survives in §9.1's field, which
  is answering a question as it is being typed rather than labelling a page you are already on.
- **Neither pill is a field. A click opens §9.1, standing on the pill.** Both surfaces hand the whole
  job over — the field, the history, the ranking, the autofill and the list are all the Command Bar's —
  and the bar opens *on the pill that handed it over*: same line, same corner, a little wider, with the
  glass growing downwards to hold the list. The click and `⌘L` both open it on the current URL
  (`.editCurrentURL`), and the pill is hidden for the duration, because the bar's own input row is
  showing what the pill was showing.
  - The sidebar's pill has handed off since there was nowhere in a 250 pt column to put a list of
    completions. §3.2b's used to edit in place with §3.4's search phrases under it, which was a second
    and much thinner answer to a question §9.1 answers completely: it knew nothing of open tabs,
    history or commands, had no autofill, and made the page bar the one place in Luna where typing an
    address got you a different set of suggestions. It is gone, and so is editing in place.
  - **The bar is wider than the pill it grew from** — a `chromeGapWide` at each end, and never less
    than `commandBarMinWidth` (360). A result row spends about 140 pt on its icon, its insets and
    §21.2's Profile badge whatever is left over, so a bar exactly as wide as a 244 pt sidebar pill was
    a column of `OpenAI | Rese…`. It keeps the pill's centre line where the window's edge allows and is
    clamped inside it where it does not, which in the column means leading-aligned with the pill and
    overhanging the page — which is what a panel floating over a page is entitled to do.
  - **What opens is the height, and only the height.** The input row is already on the line the address
    was on and the extra width is there on the first frame; the glass grows from the pill's height to
    the bar's on §6's `commandBarIn`. Two earlier versions were worse: masking the body put an
    offscreen pass around a live glass panel over a live web page, and fading `alphaValue` on the panel
    — which covers the whole window — put every pixel of the page showing through it into a
    transparency layer for the length of the animation. Both stuttered.
  - **The bar is drawn before it opens, at the pill's size** (M1), and there is no fade left in the
    anchored case at all. A Command Bar's first frame costs about 65 ms — a fresh glass backdrop over a
    live page, eight rows of text, and a field taking the window's first responder with it, measured —
    and wherever that lands, four frames are dropped. So it lands on a bar the size of a pill, in the
    pill's place, in the same commit that hides the pill: what the user sees is the address bar they
    clicked becoming a field. The reveal then has nothing left to build, and the spring is a height.
  - **And it closes the way it opened.** The anchored bar's glass runs back down to the pill's height
    on the same `commandBarIn`, and the pill is unhidden at the end of that rather than the start — a
    frame earlier and the address is on screen twice on the same 34 pt, which is the whole thing
    hiding it was for. The floating bar, which grew out of nothing, shrinks to 0.96 and fades the way
    it arrived. Before this the bar was `removeFromSuperview()`: there, and then not. On the floating
    panel that reads as a window being shut rather than a summoned thing going away; on the anchored
    one it is worse, because what that bar is saying is "I am the pill you clicked, opened up" — and a
    bar that vanishes to reveal the pill underneath was never the pill at all. The way out has to make
    the same claim the way in made, or it withdraws it. Two things go with it: the bar stops
    hit-testing on the first closing frame, since it covers the window and the pill it is folding into
    is underneath it; and a bar that never opened — one still standing at the pill's height waiting for
    the store — closes at once, because folding a height onto itself is 0.18 s of nothing.
  - **And it waits for the store before it opens.** The opening query's history lands about 9 ms after
    that first composite, and opening without it meant the morph grew around one list and settled on
    another — rows re-ranking under the pointer a quarter-second after the click, which is what Martin
    saw twice. The bar holds at the pill's size until the query lands, the user types, or 100 ms have
    passed, whichever comes first. On a warm store the deadline never fires.
- **`⌘L` belongs to whichever address bar is on screen**, and all three now answer it the same way:
  §3.2's pill, §3.2b's and §4's each hand the address to §9.1 standing on themselves. The claim is
  chained rather than assigned — each layout answers only for itself and passes the command on — and
  the page bar and the column are asked last, because they are the two that can be hidden by a setting
  rather than by a layout. Before this, `⌘L` in the sidebar layout did **nothing at all**: the top
  bar's claim was the whole chain, it answered "not my layout", and the fallback that would have opened
  §9.1 was never reached, because the closure it tests for was not nil.
- **The corner is re-cut on every layout pass.** `cornerRadius` is half the pill's height and
  `updateLayer` is where it lands, and nothing marks a view for display merely because it was resized —
  so the radius was whatever the height happened to be the last time something else asked for a redraw.
  In the sidebar that was a pass during the column's first layout, at a fraction of the final height,
  and the pill stayed a visibly rounded *rectangle* for the rest of the session.
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
- **A leading mark says what a *query* is** — in §9.1's field, not here. A **magnifier** while what is
  typed reads as a search, the site's **favicon** when it reads as an address Luna already has a mark
  for, and a **globe** when it reads as an address and no mark has arrived. It answers while you type, before
  Return decides anything: the same string can be either, and which one it is is a rule rather than
  something the user should have to hold in their head — `apple.com` is a place, `apple news` is a
  question, and the mark is the pill saying which it read. It asks `CommandBarURL.direct`, exactly as
  the commit path does, so a pill showing a globe cannot then run a search. Luna's own pages are a
  search, not a globe: `luna://` is a scheme the bar accepts, and a globe over a page that is nowhere
  on the web is the one answer here that is untrue. Sized `faviconSize` rather than `pillGlyphSize`,
  because it is §3.4's favicon slot in a pill — a slot that shows a site's own mark most of the time
  is a favicon box that sometimes draws a symbol.
  > **It sits in §9.1's result rows' own icon column**, so the query sits above the rows' titles and
  > the bar reads as one column with the list it filters. That is a change from "flush with the rows":
  > flush with their *icons* is what it was, and the query was a favicon's width to the left of
  > everything it was finding.
  > **It was tried in the address bar and taken back out** — twice, on both pills and in both of
  > §3.2b's forms. See §3.2's "No leading mark": the glyph answers a question being typed, and an
  > address bar showing a page you are already on is not asking one.
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
| Share… | page | `NSSharingServicePicker.show(relativeTo:of:preferredEdge:)`, from the sliders glyph |
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
- **Share is Luna's own item, not `standardShareMenuItem`.** The system's item draws a share glyph that
  nothing on the item controls: `image` is nil before the menu opens and still nil after `menu.update()`
  — probed — and AppKit draws one anyway, a size under this menu's glyphs and in the column they stand
  in. Dressed like every other row it came out as two share marks side by side, with the word pushed a
  glyph's width past every other word; left undressed it is AppKit's smaller mark and a title 4 pt short
  of the column. An ordinary item showing the same picker from the same glyph has one mark, in the
  column, and gives up nothing but AppKit assembling the row. Still not a submenu: the reference's
  chevron is `sharingServices(forItems:)`, deprecated since macOS 13 with Apple's own note pointing at
  the picker.
- **§4's Reload row is dressed by the same helper.** That layout has no reload button, so its copy of
  this menu grows a row at the top — the only item here that one layout adds, and the one that would
  otherwise be the single glyph-less line in a menu of glyphs.
- **A disabled caption needs no quieter ink.** AppKit dims the whole item, attached glyph included;
  applying secondary ink on top of that reads as faded rather than quiet. Measured, both ways.

#### 3.2b Page bar — the pill and §3.1's three circles, on a bar over the page
`Settings ▸ Appearance ▸ Search bar` (SETTINGS-SPEC §3.2) moves the pill out of the sidebar and onto a
bar across the top of the content pane, taking the sidebar toggle and the back/forward cluster with it —
and reload, which moves *inside* the capsule where there is 420 pt to hold it. The sidebar
keeps its tabs, its Essentials and its bottom bar — and its top 52 pt, because that row is what keeps
the traffic lights' corner clear; with its buttons gone it shrinks to `sidebarHeadlessRow` and the
column closes up over the pill's own 34 pt.

| | Open | Collapsed |
|---|---|---|
| band | `pageBar` (52) | `pageBarCollapsed` (30) |
| controls | toggle · back(·forward), on the traffic lights' centre line | gone |
| pill | `pageBarPillWidth` (420) wide, `sidebarCircle` tall, `.glass` | **the same frame**, `pageBarCollapsedPillHeight` (22) tall, `.bare` |
| glyphs | site settings **leading**, reload **trailing**, both inside the capsule; address centred between them | **none** — the strip carries the address and nothing else |

- **The bar is a plane in the page's own colour**, from `TabState.pageBackground` — WebKit's
  `underPageBackgroundColor`, which is the colour the document is actually painted on. Not
  `themeColor`: that is a decoration a site may offer and most do not, while this is measured from the
  document and is always there. **Observed, never read back.** `publishState` used to hand WebKit the
  site's `theme-color` and read the property in the same statement, and nil hands the question *back*
  to WebKit, which answers it off the next paint — so the read returned the document that had just
  gone away, and nothing re-read it afterwards. Measured on two documents, `#0a0a14` then `#3a0a0a`:
  `didFinish` for the second reported the first's `10,10,20`, and Back to the first reported
  `58,10,10`. It has its own KVO now, and the only two writes are the `themeColor` observation and
  `resetPerDocumentState`'s clear — a pinned colour belongs to the document that offered it. A side
  effect worth having: a site that repaints itself (its own dark-mode toggle) changes no URL, no title
  and no loading flag, and the bar follows it now where before nothing carried the news out.
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
  background, which is what a centred card on a tinted page wanted anyway. A layer carrying a
  background **image** cannot answer either, so the walk **steps over it** and keeps going down the
  stack. It used to end the sample there, and that is the "the bar goes white over a black page" bug:
  `getroosta.app` lays a two-stop `linear-gradient` (`div.horizon`) over `footer.night`, so from
  roughly 6500 pt down every sample came back empty and the bar fell to the document's white — over a
  footer measured at `12,12,13`, with the screen reading `13,13,14` under the bar. Stepping over
  never loses anything: what "nothing" falls back to *is* the document's background, which is the
  bottom of every stack, so giving up early only threw away the opaque surfaces painted between.
  The change crosses on
  `Motion.themeWash`, the same 0.25 s a navigation changes it on. The hit tests are the cost, so the
  sample is skipped for moves under 4 pt and re-taken on a resize — the viewport's top edge moves
  without a scroll when the bar itself changes height.
- **A page coming back out of the cache says so itself.** Back and Forward are served from WebKit's
  page cache, which restores a document **without re-running user scripts** — so nothing posted,
  `resetPerDocumentState` had already cleared the colour, and the bar went on wearing the page that
  had just been left until the next scroll. The listeners survive the restore, so the script also
  listens for `pageshow`, drops the 4 pt cache and asks again. Measured: from a page at `#3a0a0a`
  back to one at `#0a0a14`, the bar stayed red until the page was scrolled.
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
- **The bar hears about the traffic lights itself.** Its controls are laid out *against* the lights, and
  macOS takes them out of the window on the way into fullscreen and hands them back on the way out —
  without resizing anything, so nothing marks the bar dirty and it keeps a placement measured against
  lights that have moved. In fullscreen that put the buttons a light's width off wherever the pane is
  the whole window and the open pill off the centre line the collapsed one shares, which turned the
  dissolve below into a move. §3.1's control row has the same dependency and is fixed by
  `BrowserWindowController.relayoutChrome` — but that pass walks the **chrome host's** subviews and this
  bar is not one of them: it is an overlay on the content card, so it observes
  `didEnter`/`didExitFullScreen` itself (`PageBarLights.swift`), twice per edge, because AppKit restores
  the buttons after posting. **The general rule is in §21 / item 8: fullscreen keeps the same views, so
  a chrome fix reads as already applying there — and the things it moves out from under them are the
  material and the lights.**
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
- **Pressing the address opens the bar, then hands it to §9.1.** A press on the collapsed capsule
  would otherwise give the Command Bar a 22 pt anchor sized to `apple.com` to grow out of; the bar it
  belongs to is 52 pt with a 420 pt pill in it, and that is the shape the panel should take. So the bar
  opens first — **unanimated**, unlike every other change of this state, because the panel reads the
  pill's frame on the frame it is created and a pill two hundred milliseconds into a morph would be
  read mid-flight. Nothing is lost: the panel covers the bar for the whole of the animation that is not
  being run. The bar is then held open for as long as §9.1 stands on it, whatever the page does
  underneath: the scroll rule keeps running and is handed the bar back when the Command Bar closes. A
  committed address is not a special case — §9.1 navigates the tab itself and arriving opens the bar
  again on the same turn.
- **The offset comes from the page itself.** `WKWebView` publishes no scroll position on macOS — no
  `scrollView`, no KVO-able offset — so a passive, frame-coalesced listener posts `window.scrollY`
  through `TabController.scrollMessageName`. It is main-frame only: an ad iframe scrolling itself is
  not the page moving.
- **Only the band takes clicks.** The bar's frame is the *open* band's height in both states, so that
  nothing inside it has to resize while the two states cross-fade — which means that while it is
  collapsed its lower 22 pt is over live page. `PageChromeBar.hitTest` gives everything outside the
  band back to the page, so a link there stays clickable.

##### 3.2b.i Suggestions under the pill — **removed 2026-09-20**
Typing in the pill used to drop §3.4's search completions below it on `.popover` material, the same
width as the pill and lining up with it rather than with the bar.

It is gone, with the in-place editing it belonged to. Both address pills now hand the whole job to §9.1,
which grows out of the pill (§3.2) — so the completions under a page bar's address are the same ranked
list of tabs, history, commands and suggestions that `⌘T` shows, drawn by the same rows, instead of a
second and thinner list that knew only about search phrases. Two things the list got right were worth
keeping and are now §9.1's problem alone: one moving `.control` glass pill for the selection rather than
a fill per row, and a row geometry taken from `CommandBarResultRow` rather than from §3.4's tab rows,
whose insets are derived from a tab pill's height.

### 3.2c Load line — a 2 pt line on the bottom of the address bar, wherever the address bar is
Transcribed from the reference Martin sent, measured at that capture's 2x: a **2 pt** accent line lying
**on the inside of the pill's bottom edge**, running the capsule's whole width from the leading end,
with **both ends cut by the capsule itself**.

**It is the pill filling up, not a rule drawn inside one.** A line held clear of the bottom edge, with
its own rounded caps, is a second object floating in the capsule; a line lying on the edge and ending
where the corner takes it away is the bottom of the capsule turning blue. The reference measures the
second, to the pixel: the blue run ends exactly where the capsule's bottom stroke begins, and its
leading end is the corner's curve rather than a cap. (The first draft of this section had it 4 pt up
and 12 pt in from each end; Martin sent the reference back.)

| | Value | Why |
|---|---|---|
| thickness | `loadLineHeight` = 2 | measured (4 px at 2x); the thickness §7 already wrote down for a progress line |
| above the bottom edge | `loadLineFloor` = `hairline` = 1 | the pill's own border, and nothing more: the line lies on the inside of the well. `hairline` rather than 0 so the geometry does not move when §3.2's pill swaps between its bordered plate and glass |
| run | the pill's full width | so a finished load reaches the end of the address bar rather than stopping a text inset short |
| ends | the capsule, as a mask | `LoadProgressLine.capsule(inPill:cornerRadius:)` — the well's shape, in the line's own coordinates, so the strip is cut by the corner instead of being held clear of it |
| colour | `Accent.tint` | §1 allows the accent as **fill**, which is all this is — never text, never a border |

**One line, three pills.** §3.2's in the column, §3.2b's on the page and §4's active tab all place it
through `LoadProgressLine.place(inPill:cornerRadius:)`, because a line lying on the edge of one surface
and floating inside another is two lines. §3.2b's collapsed capsule keeps it: the bar is 22 pt of the
page's own colour with a domain in it, and the line is the only thing left that can say the page is
still arriving. A consequence worth naming: below roughly 4 % the fill is still inside the corner's
curve and nothing shows, which is the reference's own behaviour — the line emerges from the corner.

**With no address bar on screen, the window's top edge takes it.** That is the sidebar layout with the
sidebar hidden (`⌘S`) and the search bar still in the column — the pill is parked off screen — and page
fullscreen, which takes the chrome with it. `ChromeState.loadProgressHost(searchBarOnPage:)` is the
whole rule, pure and tested the way `cardInsets` is; the window controller only ever asks whether the
answer is `.windowTop`. The fallback line is fed **whether or not it is the host**, so `⌘S` half way
through a load moves a line that is already at the right fraction rather than one starting again from
nothing. It is added above the chrome, because §3.8's peek slides a sidebar over that exact corner.

**Three rules, and all three are about not drawing.** They are what separates a progress bar from
decoration:
1. **A load under `reloadSkipThreshold` (0.15 s) plays nothing.** §7 wrote that rule for the bloom and it
   is the same rule here — a cached reload is over before a bar could say anything true about it, and a
   line flashing on every back-navigation is noise on the most common navigation there is. The reveal is
   *armed* rather than shown, and a load that finishes first cancels it.
2. **It never retreats.** `estimatedProgress` falls when a load commits a new document; a redirect two
   thirds of the way through a page is not the page getting further away.
3. **It finishes before it leaves.** The fill runs to full on `loadLineAdvance` and only then fades on
   `loadLineFade`, so the last thing seen is a full line and not a bar that vanished at four fifths.

A tab switch is not progress: the line carries the tab's id and starts over when it changes, because §4's
pill is literally the same view across a switch. Reduce Motion needs no special path — every step goes
through `Tokens.Motion`, which degrades each to an instant change (§21.2). It is decorative to
VoiceOver: loading is announced by §3.4's rows and by the reload glyph becoming a stop, not by 2 pt of
ink.

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
- **The tile you are on glows, in that site's own colour.** A lit ring just outside the tile's hairline
  (`essentialsGlowRim`, 1.5) with a bloom carrying past it (`essentialsGlowReach`, 7), 5 % of the same
  colour inside the glass, and it **appears with a pop** — opacity and a 1.06 → 1 scale together on
  `essentialGlow`, from the tile's own centre. It **flares out and settles**, it does not grow in:
  rendered at 0.88, 0.94, 1.00 and 1.06 over a real tile, anything under 1 puts the lit ring *inside*
  the tile's hairline with the grey line still outside it, which reads as a second smaller box drawn on
  the tile rather than as light. Reference: `inspiration/pinned-tab-glow-*.png`, at about half their gauge,
  which is what "not too thick" asked for. **On click, never on hover** — hover is already answered by
  the material arriving, and a glow that followed the pointer round the grid would be four answers to
  one question.
  > **The colour comes out of the favicon, not out of `theme-color`.** A pinned tab's page is closed
  > until you click it, so there is no `TabState` to read a theme colour from and the glow would arrive
  > a second after the click that asked for it. `FaviconTint` weights the icon's pixels by **chroma,
  > squared**, which is how X's black-and-white mark with one red notification dot comes out red rather
  > than grey. An icon with no colour in it — or one whose colours cancel — glows in `Text.secondary`
  > instead: the chrome's own ink, white on a dark sidebar and near-black on a light one. Not
  > `Accent.tint`, which would put the system's blue highlight back on the one surface this is about.
  > A dark mark is lifted to a brightness that can emit (floors of 0.55 saturation and 0.70 brightness,
  > ceiling of 0.95 saturation), because a favicon's colour was chosen to be *read* at 16 pt and not to
  > be given off at the edge of a tile.
  > **One glow for the grid, and it lies over the tiles.** Only one tile can be the tab you are on, and
  > `EssentialsGridView`'s header has what a backing view per tile cost the sidebar last time. Over
  > rather than under, because a selected tile carries `NSGlassEffectView` and the material composites
  > what is behind the *window* — under it the 5 % inside the glass simply vanished. Over it, the view
  > answers no hit test at all, or it would swallow every click on the pinned tab you are on.
  > **The light never travels.** It is one view moved between tiles, so the animated pass that a pin,
  > an unpin or a click's reload brings with it slid the glow across the grid from the tile you left to
  > the tile you pressed — the "morph between" Martin rejected. Its frame is set **immediately** in
  > every pass, animated or not, and it is set *before* the appear starts rather than by the layout pass
  > that follows: placed late, the pop played at the tile you came from and the light teleported after
  > it. It goes out where it was and appears where it now is, in one frame.
  > **The ring is layers with a continuous corner, not a stroked `CGPath`.** There is no public API for
  > a squircle's outline, so a path round a §3.3 tile pinches at the corners where the tile does not; a
  > `CALayer` with `cornerCurve` and a border draws the real curve, and the bloom is that border's own
  > shadow rather than a `shadowPath`, so it follows the ring instead of the box.
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
  > **Putting a page away silences it, explicitly.** Every teardown — this one, §19.2's budget, a
  > closed tab, a deleted Space — went through `TabController.detach`, which unhooked the view and let
  > go of it on the reasoning that a deallocated `WKWebView` closes its page and a closed page makes no
  > sound. That is true of the *last* reference and says nothing about the one before it: WebKit's own
  > async completions, a floating Picture-in-Picture window, element fullscreen and a snapshot in
  > flight each outlive the call by an unbounded amount, and for as long as one does, the page is still
  > playing. Reported as **closing a pinned tab with a video running and still hearing it in the
  > background**, with nothing left on screen to stop it. Audio is the one leak a user can *hear*, so
  > `detach` now suspends all media playback first and whichever reference goes last no longer decides.
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

#### 3.3a Empty wells — what a Space with nothing pinned shows instead

A Space that has pinned no tabs and made no folders draws two dashed wells where the pinned
things would be: a **block** in §3.3's grid, under the URL pill, with a `pin` glyph over
"Drag a tab here to pin it"; and a **row pill** under it, where §3.4b's first folder will
stand, with a `folder` glyph beside "Drag a folder here to pin it".

- **Each well appears only for the tier it describes.** Pin one tab and the block goes; make
  one folder and the row goes. They are independent — a Space with four tiles and no folders
  draws the row well alone.
- **Each well is drawn as the thing that is missing, not as a notice about it.** The row well
  stands in §3.4's own two columns — its `folder` glyph centred on the favicon column at
  `groupIconSize`, its line starting at `rowTitleInset`, both in `TypeScale.sidebarHint`, which
  *is* the column's 13 pt row face. The block well **is one empty tile**: `essentialsTile`'s
  height and corner, standing in `slotRect(at: 0)`, its `pin` at a tile's own `essentialsIcon`,
  and its glyph and line centred as a pair the way a tile centres its icon. Each line stops
  half a `rowInset` short of the cross's slot, which is the clearance §3.4's own title column
  keeps. One dash, one face, one cross between them.
  > **Each well's glyph is the size the thing it stands in for draws its own.** Both were a
  > folder's 20 pt, which in the grid was the biggest thing on screen with a 13 pt line beside
  > it, and the line's room went into it.
  > It was two dashed boxes of 12 pt semibold grey, centred, which would have been the only bold
  > type in §3 — a poster about an empty column rather than the column's own voice. Centring the
  > row well also cost it the room: at the default width its line came out as
  > "Drag a folder here to pi…".
  > **The block was 70 pt and stacked, chosen to be taller than a tile so it could not be
  > mistaken for one.** Being mistaken for one is the point. At 70 the grid also dropped 16 pt
  > the moment the first tab was pinned — the column jumping in answer to a drop that had
  > already landed — and `EssentialsGridView.height(forTiles:hinting:)` now returns the
  > one-tile height for a grid giving advice, so nothing moves at all.
- **Dismissed by the cross, which is revealed on hover** exactly as §3.4's close is — a tip is
  mostly read, not dismissed, and a cross standing in the well at rest took a quarter of the
  line's room. It stands top-right in the block and in the row's own trailing slot, one
  `rowInset` inside the well in both. The line keeps that slot clear whether or not the cross is
  in it, so nothing steps sideways when the pointer arrives. The cross is `rowTrailingChip`, so
  it answers a hover and a press like every other glyph in the column (§6).
- **One answer for the whole app, not one per Space.** `Settings.showsPinnedTabHint` and its
  pair store the *dismissal*, so a key nobody has written reads as "show it". Advice already
  taken does not need repeating in the Space next door — where, by definition, the user is now
  doing the thing it describes.
- **Neither well carries a fill at rest.** Nothing else in §3 does — an unselected row has no
  background at all (§30.7) — and empty is drawn here the way §3.3 draws its own empty slot: a
  dashed `Line.border` and nothing behind it. `Surface.hover` is what a lift arriving over one
  looks like, which is the same lift every other target in the column takes.
  > **They were `Surface.well`**, a dark recess cut into the plane, sitting a few points from
  > the grid's own dashed drop outline, which has never had a fill. A well answering the pointer
  > then meant swapping one material for another rather than lifting the one it has.
- **The block stands where the first tile stands, and stays there under a lift.** §3.3's grid is
  zero points tall until something is pinned and opens to a tile's height for the length of a
  drag; the well has already made that movement, so `isAwaitingDrop` adds nothing and nothing
  jumps when a §6.6 lift comes into the air — or when it lands. The well's own dashed line is
  the drop outline, so the grid draws no second one inside it.
- **Neither well is a drop target of its own.** §6.6 already resolves both zones: the grid's
  region is the block's, and a point above the list's first row is §3.4b's tier, which is what
  the row well stands on. So a tab dropped on the row well gets a folder made round it, which
  is §3.4b's rule and not a second one.
- **§30.9's still draws both**, for the reason it is built from `SidebarList.rows` — a picture
  that leaves them out is a column whose rows stand a hundred points too high, and that
  correction lands inside the cross-fade that exists to hide one.

The reference for both is a browser that draws a star-marked box for its favourites and a
pin-marked capsule under it. Luna's copy differs — both lines name what you *drag* rather than
what the tier is called — and Luna draws no section label over either well, because §3 has no
section labels anywhere else.

### 3.4 List rows — 38 pt of pitch around a 35 pt pill
Order: §3.4b's pinned folders → **separator** → `New Tab` row → tabs.
> **The rule moved and the command moved with it.** It used to close off a leading command
> group: `New Tab`, rule, tabs. §3.4b gave the space above it a job — the pinned folders — so the
> rule now marks the bottom of that tier and `New Tab` sits under it, at the head of the tabs
> it opens into. With nothing saved there is no tier and no rule, and the list starts at
> `New Tab` exactly as it always did.
> **It was `+ Add Tab` and it made a blank tab.** That is the one tab nobody wants: the next thing
> anybody does with one is reach for the address bar. The row asks the question instead — it opens §9.1
> in `.newTab`, so what it lands on is still a new tab, and closing the bar without choosing leaves the
> list exactly as it was rather than one empty page longer.
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
  > **The chip is every glyph button's, not just this one's** (M1). §3.2's two glyphs inside the URL
  > pill lifted their ink instead, on the argument that a rounded rectangle inside a capsule is two
  > shapes; Martin's macOS 26 reference for a plain button is that chip, and he asked for it on the
  > site-settings glyph by name. One class draws it for all of them (`RowGlyphView`): hover is
  > `Surface.hover`, a press is `Surface.selected` and a 5 % swell, and both cross-fade on §6's
  > `controlHover`.
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
- **The list scrolls with no scroller.** Not a hidden one, not an overlay one — none. An overlay
  scroller is drawn *over* the content, and the content here is a pill inset 8 pt from the sidebar's
  trailing edge with the close affordance a `rowInset` inside that, so it lands on the one strip of the
  row the pointer is already on: narrow while it fades in, then knob-and-track wide the moment the
  pointer comes near, which over this list is nearly always, because the pointer is over the list in
  order to use the list. A scroller is a place to drag and a read-out of position; the first is the
  wheel, the trackpad, the arrow keys and `scrollRowToVisible`, all of which work with no scroller
  present, and the second the rows say better — a row cut off at the edge is the list telling you there
  is more, in the list's own terms.
- **Selected and hover fills are `Surface.selected` / `Surface.hover`.** Clear glass alone is very nearly
  the sidebar's own glass, and a selected row read as unselected until these were asked for.
- Loading shows a shimmer sweep across the title, not a spinner.
- `+ New Tab` is a first-class row with identical metrics to a tab (§30.6).
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
  > **The lift travels to where it lands, then hands over.** Every landing the lift can reach is
  > somewhere on screen — a slot in §3.3's grid, the gap it has opened in §3.4's list, or a folded
  > §3.4b folder's own header — so it goes there on `tabInsert` and the move is committed when it
  > arrives, not when the hand lets go. Only the grid did this; every other drop faded the lift out
  > wherever the pointer happened to be, which for a drop into a folder was the whole of the
  > movement: the tab vanished in mid-air and the folder was one row longer the next time you
  > looked at it. A drop on a §3.5 Space dot still fades where it stands, because the tab is
  > leaving this column rather than landing in it.
  > **A folder taking a drop is boxed, whole.** A dashed box in `Line.border` filled with
  > `Surface.selected` closes round the folder's entire extent — its name, the tabs already in it,
  > and the row the list has just opened for the one arriving — so the tab is seen to be going
  > *inside* something rather than merely stepping in by `groupIndent`. It is one view for the
  > list, like §3.4's two pills and for the same reason, and it lies under the rows and answers
  > no hit test (`SidebarGroupDropView`). The dash is §3.3's: the grid's empty slot, §3.3a's two
  > wells and this are one mark. The wash is the heavier of §3.4's two, and that is the
  > distinction those two carry — `hover` says the pointer is over this, and a folder taking a
  > drop is the chosen destination for the thing in the air.
  > **A shut folder's extent is its header, so the box is the header and the list stays still.**
  > There is no row inside a folded group for a gap to open between, and the lift sinks onto the
  > name it is being filed under. No gap opens beside it: a list making room under a shut folder
  > is saying the tab lands next to it while the box says it lands inside it, which is two
  > answers to one question.
  > **A folder's header is not split down the middle.** Every other row divides at its midpoint,
  > because its two halves mean the same kind of thing — before this row, after this row. A
  > folder's header does not: the lower part is the one gesture that puts a tab *inside* the
  > folder and the upper part only puts it above, which the row overhead has already offered.
  > So `groupDropEdge` gives the folder everything below the top 10 pt of its 38, and the
  > boundary above it keeps twice `dragThreshold`.
  > **A shut folder opens on the drop.** The drop is the one moment the user is asking where
  > that tab has gone, and a folder that swallows it and stays shut answers by making the row
  > disappear. `setGroupCollapsed(false, …)` runs before the reorder, so the list arrives at its
  > new shape once instead of opening a step after the row lands.
  > **An expanded folder used to say nothing at all.** The indent the lift already carried was
  > the whole of the feedback, and a 16 pt step is not an answer to "where is this going". The
  > outline a folded header wore was the only mark either state had, and a hairline round one row
  > is not much of a target for a tab about to disappear into it.
  > **Every step is a haptic tick.** The pointer moves continuously and the list does not — it *steps*,
  > as the lift changes places with one neighbour — and that step is `Tokens.Haptics.step()`, fired the
  > once per crossing, in §3.3's grid and §3.4's list alike. The pattern is `.alignment`, which is what
  > the system itself uses when something snaps into a position: a shape onto a guide, a window onto a
  > screen edge. The first target of a gesture is not a step — nothing has been passed yet — so it is
  > silent. It is also silent on any Mac without a Force Touch trackpad, and that is correct rather than
  > broken: `NSHapticFeedbackManager.defaultPerformer` already honours System Settings ▸ Trackpad, so
  > there is no Luna setting for it and nothing to check before calling.

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

#### 3.4b Folders, and the tier that holds them

The list has two tiers, divided by §3.4's rule:

```
§3.3 grid          ░ pinned tiles ░
pinned folders      ▸ Research  (3)      ← a folder, folded
                    ▸ Invoices  (1)      ← and another
────────────────────────────────────     ← the rule
                    + New Tab
today               ▾ Trip
                        flights.example
                        hotel.example
                      news.example
```

**The tier under the tiles holds folders and nothing else.** There is no such thing as a
loose kept tab any more, and that is the whole shape of this section: §3.3's grid is the
pages you reach in one click, the tier under it is the *work* you keep, and work has a name.
A run of loose rows up there was a second today's-tabs with no name on any of it, and the
first thing every user did with it was wish for folders.

So a tab dropped in that tier gets a folder made around it, at the slot it was dropped in,
with its name field already open — one gesture, and the thing that arrives is the thing the
tier is made of. `BrowserSession.reorderTab` is where that happens, and it is deliberately
one rule in one place: there are four ways a tab can land there — the drop, the menu, an
import, an undo — and a rule enforced at four gestures is a rule with three holes in it.

**And "Saved" is gone from the vocabulary.** The tab menu has no *Save Tab*: putting a tab up
there and putting it in a folder are now one act with one name, and *Add to Folder ▸* is it.
The folder menu says *Pin Folder* / *Unpin Folder*, which is the tier the user can see —
pinned tiles above, pinned folders under them. A database written before this rule has loose
rows in that tier; they are gathered into one folder per Space called *Saved*, which is what
the tier used to be called, rather than demoted to today's tabs. The user put them up there
deliberately.

**Nothing changes for a tab inside a folder.** It closes in two presses, dims rather than
leaving, goes back to the address it was kept at, and wakes when it is clicked — exactly as
a kept row always did. What changed is where the row is allowed to stand, not what it does.

**Luna never opens a page the user closed.** A dimmed row and a §3.3 tile are places rather
than pages, and only a click on one loads it. Three paths used to load one without being
asked, and all three are the same bug: the selection moving to the row under a tab being
closed, the selection Luna picks when it walks into a Space with nothing open in it, and
§9.2's bar offering a dimmed row as *Switch to tab* — that last one put the site straight
back in the folder the moment the user searched for it again, where what they wanted was a
new tab, and history's own row is what gives them one. Closing the page of the last open row
therefore leaves the Space with nothing selected, and §3.4's pill leaves with it: a fill
still lying on the row is the next `⌘W` aimed at the row itself.

**And the bar hands back a page, not the filing it was in.** A fourth path did the same thing
from the other end: a tab closed out of a folder is archived *with its `groupID`*, and §9.2's
*Reopen* put it back into the folder — dimmed, two levels in, one press from being let go,
which is the state the user had just finished putting it in. `⌘⇧T` and §11's list still mean
undo and still put a tab back exactly where it was taken from; the bar's rows are places, so
one chosen there comes back the way any other address from the bar does — a tab of the day, on
its own, at the top of its page.

**A group is one row with its tabs under it.** It has a name and an icon the user picked, a
chevron that says which way it is folded, and a §3.4-shaped row exactly like a tab's — same
pitch, same pill, same hover and selection fills. Its tabs step in by `groupIndent` (16 pt, a favicon's own
width) and a hairline runs down the space that opens.

**The chevron is a mark, not a button.** The whole header folds, so the glyph takes no press,
no hover and no place in the row's hit test — it is a plain image view (§6's register of
buttons excludes it on purpose). It was a `RowGlyphView` and lit its own chip and swelled
under its own press, which put a second target inside a row that has one: aiming at a 16 pt
glyph to do the thing the whole 38 pt row already does is a smaller target for no more reach,
and a chip appearing inside the heading read as a control the heading did not have.

**The chevron follows the name.** It stands one `groupChevronGap` after the folder's own title,
not in front of its icon. Leading the row it took the column every other row draws a favicon
in and pushed the folder's icon out of it, so a list of folders and tabs had two icon columns
instead of one; behind the name it costs nothing, because the name is the only thing on the
row that is ever short. The folder's header therefore starts at the column's own left edge
like every other top-level row, and the indent under it is the whole of what says a tab is
inside.

- **Called a folder everywhere the user can read it.** "Group" is what the code calls the
  type; the menus say *New Folder*, *Add to Folder*, *Pin Folder*. A folder is what the thing
  already looks like — a named row with an icon and items under it — and it is the word the
  feature was asked for in.
- **Made empty, and named on its own row.** Right-click the column's empty plane for
  *New Folder*, or `Add to Folder ▸ New Folder` on a tab to make one around it. Either way
  the folder appears immediately and its name field opens on the row with the placeholder
  name selected, so the first keystroke is the name. No dialog: a sheet for this puts a
  window in front of the list the folder has just appeared in and asks about a row the user
  can no longer see. Escape leaves it called *New Folder* — a name nobody chose still beats
  a row that cannot be told from any other.
- **Renamed the same way, and re-iconned from a submenu.** The folder menu's *Rename* opens
  that same field; *Change Icon ▸* lists the sixteen with the current one ticked. Neither
  carries an ellipsis, because neither opens anything before it commits.
- **The icon can be an emoji.** Sixteen symbols is a vocabulary; a folder for a trip wants the
  flag of the country it is to. *Change Icon ▸ Emoji…* opens macOS's own palette over the
  row's icon slot — its search, its recents and its skin tones, none of which is worth
  rebuilding badly — and the first character it inserts is the icon. It is the one item in
  either folder menu that carries an ellipsis, because it is the one that opens something
  before it commits. `TabGroup.symbolName` holds either a symbol's name or the emoji itself,
  and `RowEmoji` is the one place that asks which.
- **A folder's icon is drawn at `groupIconSize`, and an emoji is fitted to it.** A favicon is
  a picture and fills its 16 pt square; a symbol drawn at the same point size puts about two
  thirds of that on the row, so a folder measured the same as the tabs under it and did not
  look it. The larger box is centred on the favicon's own column, so the list still reads as
  one column of icons and the title inset does not move. An emoji goes the other way — Apple
  Color Emoji at 16 pt draws 20 pt of picture, so one set at the slot's own size was cropped
  on all four edges. `RowEmoji` measures the ink and picks the font size that fills the slot
  exactly, then centres the picture on that ink rather than on the line's box.
- **A folder's header can be dragged as well as folded.** The two are told apart by whether
  the hand moved: still, it folds; moved, it lifts. A folder is a slot in this tier like any
  other and an arrangement you cannot rearrange is not an arrangement.
- **A tab in the column is renamed on its row too.** §3.4a's *Rename* opens the same field,
  on the name the row is showing. Emptying it — or typing the page's own title back — is how
  a tab goes back to being named by its page. §3.3's tiles and §4's strip keep the dialog and
  keep the ellipsis with it: neither draws the name as a line of text there is room to type
  on.
- **The fold is persisted.** A group the user put away and found open again the next morning
  has lost the only thing folding it was for. Folding is a row diff like any other, so the
  tabs fade over §6's `tabInsert` rather than blinking out.
- **A group may never be pinned.** §3.3's grid is one tile per tab and a group is a list of
  them, so there is no tile for one to be. The grid is simply not offered while a group is in
  the air, and neither is a §3.5 Space dot — a group belongs to the Space it was made in, and
  a tab carried out of that Space leaves the group behind rather than dragging the name away
  from the rest of its tabs. Both boundaries that could write a pinned group repair it
  instead of refusing, the way `Profile` guards its data-store identifier.
- **Groups and loose tabs share one run of indices**, so a group can stand between two tabs.
  That is what makes moving either of them renumber both — a `[Tab]` return from the ordering
  layer would have left a group's index behind on disk and the arrangement after a relaunch
  would not have been the one on screen.

**The rule and `New Tab` are one block.** Nothing can be dropped between them: both rows
mean the pinned tier at both halves and both open their gap above the rule, so the command
row never drifts off the line it belongs to while a lift goes past. It also makes the saved
tier's drop target the whole block rather than a hairline — the difference between aiming at
a row and aiming at a line — and the head of today's tabs is reached from the top half of
the first of them instead.

**The rule appears with the tier, not with the list.** With nothing saved there is no bottom
to mark, so there is no rule and the column starts at `New Tab`. A drag is the exception: it
comes out for the length of one, because a zone you cannot see is a zone you cannot aim at.
The §30.9 Space-swipe still is built from `SidebarList.rows` for exactly this reason — a
still with its own idea of the head drew a rule that was both in the wrong place and always
there, appearing for the length of a swipe and vanishing when the real column arrived.

**The Space past the last one is drawn as nothing, and drawn deliberately.** A swipe off the
end of the strip is not arriving somewhere; it is making somewhere. So the still carries no
tiles and no rows — not even §30.6's `New Tab`, which an empty Space does have — and the only
thing standing on that plane is the `+` and its ring. It has to be *built* as nothing rather
than left alone: the still is rebuilt only when the answer to "which Space" changes, and while
that answer was an optional id the blank case shared nil with "nothing has been shown yet", so
the guard held and the plane kept whichever Space the previous stroke had drawn on it —
pinned tiles and all.

**The pinned tier is the run above the rule, and what makes a tab in it kept is what closing
does.** A tab in a pinned folder takes **two presses** to let go:

| press | what happens |
|---|---|
| first | the page closes, the row stays, **dimmed**, back at the address it was saved at |
| second | there is no page left to close, so it means the row: archived, and undoable |

Clicking a dimmed row opens it again and takes the second press back off it. So does dragging
it below the rule: a tab on the ordinary side is an ordinary tab, never one press from
disappearing.

- **Dimmed is `Text.tertiary` plus a favicon at `dormantIconOpacity`**, which is what a
  loading row wears — both are rows with no page behind them right now, and both come back at
  full strength the moment there is one. Deliberately *not* `Text.disabled`, which is the tier
  for a control that cannot be operated; this row is one click from being open again.
- **It is a stored column (`Tab.isDormant`, schema `v6`), not something inferred.** "Has no
  web view" is true of every tab after a relaunch and of every cold one §19.2 has reclaimed,
  and neither of those is a page anybody closed. A tab that came back from lunch one press
  from deletion would be a data-loss bug wearing a feature's clothes.
- **`.pinned` is the tier**, and it needed no new column: it already meant "the run above
  today's tabs" and §3.4b only gives it the behaviour its name always claimed.
- **A folder's tier is its tabs' tier.** Carry a folder across the rule and its tabs go with
  it; drop a tab into a pinned folder and it is kept, whichever side it came from. So "is this
  tab kept" has one answer wherever it is asked, and `closeTab` never has to look at a folder
  to decide what a press means.

**The rule is only drawn when there is a tier to close off — or when a drag is up.** With
nothing saved there is no bottom to mark. But the space above it is somewhere a tab can be
put, and a zone that is invisible until you have already used it is one nobody finds, so the
rule comes out for the length of every §6.6 lift and goes away again on the drop.

**Where a drop lands is read from the two halves of a row, not from the gap between two.**
That is the whole reason a group can be dropped into at its end: the gap under a group's last
tab and the gap over the next slot are the *same* boundary and mean two different things —
the end of the group, and after it. A pointer knows which half of which row it is on, so the
destination table is keyed the same way. A folded group has no tabs on screen to drop between,
so the lower half of its header means "into it, at the end", and its header is outlined while
a lift is aimed there — the only feedback a folded group can give.

**§3.4a's menu gained one item, and folders have a menu of their own.** A tab gets an
`Add to Folder ▸` submenu (`New Folder`, then every existing folder, then `Remove from
Folder`) — a submenu because the number of entries is the user's rather than the design's, and
a menu that grows by one every time somebody makes a folder stops being scannable at about the
fourth. It is the only route a menu offers into the pinned tier, and that is the point: there
is nothing up there but folders. It does not appear on a §3.3 tile, where the grid is one tile
per page and has no folders in it. A folder header's own menu is five items —
`Rename · Change Icon ▸ | Pin Folder | Remove Folder, Keep Tabs · Close Folder and Tabs` —
rather than a longer §3.4a,
because half of that menu has no meaning on a group: no address to copy, nothing to duplicate,
no sound to mute. **Ungroup removes a name and never a page**; *Close Group* is the one that
ends the tabs, and it ends them one at a time through `closeTab` so each lands in §6.3's
archive with its own undo — and so a *saved* group dims its tabs on the first Close Group and
lets them go on the second, exactly as pressing close on each of them would.

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
> standing on it rather than at its own centre — **and folds back into that same corner when it closes**,
> which is the same spring, the same 0.96 and the same pivot, run the other way. It used to be
> `removeFromSuperview()`: on screen one frame and gone the next, which reads as a window being closed
> rather than as a glance ending, and it took the button's ownership of the surface with it. The
> controller counts the pop-out as gone the moment it is dismissed — `esc`, the button, a click outside —
> so the next one may open immediately; the view fading is nobody's business but its own, and it stops
> hit-testing on the first frame so the click that closed it is not eaten by the sheet that is leaving.
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
  > **A dot answers the pointer like every other button** (§3.4, §6). It wears §3.4's washes on a chip
  > the size of its own slot — `spaceDotChip`, which is `spaceDotPitch`, because a 6 pt hover target is
  > no target — and hands its **press to the pill**, which is the glass under it and the thing that
  > swells. That is `NavCluster`'s rule: a control with no material of its own does not swell, the one
  > holding it does. Before this the dots were the only controls in the chrome that said nothing at all
  > until the Space had already changed. Measured on screen: hover changes exactly 14 × 14 pt, a press
  > changes the whole 42 × 22 pt pill.
  > **The page is the ruler.** One page of hand is one page of column, at whatever width the §3.7
  > handle has left the sidebar — so there is no "points per Space" number, and there should never have
  > been one. Every value it held was a *fraction* of a page, which meant the column moved a multiple
  > of the fingers pushing it: 120 pt against a 280 pt sidebar was two and a third points of column per
  > point of hand. That is the "it multiplies my swipe" this gesture was reported for twice, and
  > damping the trackpad's acceleration never touched it because the acceleration was not where it came
  > from. Half a page commits.
  > **A flick commits too, and that is what pays for the ruler being a page wide.** Half of a 280 pt
  > column is 140 pt of finger, which no reflex performed dozens of times a day can cost — so a release
  > still moving at `spaceFlickSpeed` turns the page however far it got. A short stroke still going is
  > a page turn; a long one that has come to rest is a page turn; a short one that has come to rest is
  > a look, and it springs back.
  > **The `+`'s ring is the threshold, not a read-out of one.** Past the last Space the same two
  > fingers make a new one, and the circle closing is the whole of what it costs: full ring, let go,
  > Space; short of full, let go, nothing; pan back and it empties under the hand, which is how a
  > create is called off. `Haptics.latch` ticks as it closes and again if the hand retreats past
  > `ringReArm` and pushes out afresh. The *disc* keeps its own faster clock — it is in from the edge
  > and standing still after `spaceCreateEntrance` of the sweep — because the gesture is a thing that
  > appears and then a thing that fills.
  > **Both create defects were this one distance being two.** The first asked for three pages and
  > closed the ring after one, which could not be performed at all: against the damping ceiling three
  > pages needs longer than a trackpad stroke lasts, so the ring closed and the release made nothing,
  > every time. The second brought the distance down to a page a hand can cover and left the ring
  > closing a third of the way in, on the reasoning that a ring should promise rather than receipt —
  > which is true of a ring that is promising something. This one promised and did not deliver, so all
  > the early close bought was a more convincing way of being told the wrong thing. **A read-out that
  > is not the threshold is a read-out of nothing.**
  > **The resistance is distance and stiffness.** A page is twice what a switch costs, which is the
  > asymmetry `TokenCheck` holds — against the **widest** the column gets, since a create that cannot
  > be finished in one stroke is a dead end rather than resistance. And the column does not follow the
  > hand out there: past the last Space its travel bends over against `spaceCreateGive`, 1:1 under the
  > fingers at first and stiffer with every point of push, so a whole page of hand leaves it a little
  > under half way out and the last third of the ring is paid against a column that has all but
  > stopped. A flick is no longer excluded by how the gesture *ended*, and that is not a relaxation: a
  > rule that makes a closed circle mean nothing in some releases is the same lie in a different place.
  > **The release is a hand that kept going.** Its duration is the distance left over the speed the
  > fingers let go at (`Motion.spaceSettle`), not one fixed number — released a tenth of a page from
  > home the column used to crawl the last 28 pt over the same 0.18 s it took to cross a whole page
  > from a flick. And the *whole* read-out travels on one clock: the column, the still, §8.2a's wash
  > and this strip are all functions of one number, but only the first two are layer properties, so
  > animating those and setting the rest outright made the dots snap to the Space they were heading for
  > while the column was still a third of the way there. `SpaceSwipeSettle` tweens the number instead,
  > and every frame of the gesture — finger down or not — is drawn the one way.
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
control moves the window: the control row, the grid's background, the rule under `+ New Tab`, the empty
list below the last tab. `NSTableView` swallows that press by default, which left the top 52 pt as the
only place in a 280 pt column you could pick the window up by.

> **One window, one handle** (M1). §3.2b's page bar is chrome too, and it used to move the window as
> well — so with the sidebar out there were two drag surfaces, one of them the band the user is aiming
> at for the pill, the toggle and the history cluster. It is over the *page*, inside the card, clipped
> to the page's corners, and it no longer moves anything. The exception is a hidden sidebar: with the
> column put away that bar is the only chrome above the page, and a window whose only handle has been
> put away is one you cannot move. Asked at mouse-down rather than stored, so it cannot be a copy of a
> chrome state that has since changed.

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

**The strip starts below §3.2b's band.** The top `pageBar` points of that edge do not peek, because with
the sidebar hidden that corner is where §3.2b puts the sidebar toggle — and a strip that ran the full
height pulled the sidebar out from under the pointer on its way to that button. The button then moved a
column's width to the right, the pointer followed it off the strip, the peek closed, and the button went
back: it could not be hit at all.

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

## 5. Downloads — the list, and how a file gets to it

**One surface, in both chromes.** Everything downloaded — open, reveal, retry, clear — is §3.5's
pop-out at `downloadsPanel`, standing on whichever Downloads button the layout shows: down from §4's
capsule, up from §3.5's cylinder, and `⌘⌥L` opens the same thing. It also puts itself up when a
download starts (§5.0) and when one lands, and counts itself down after **4 s** unless the pointer is
on it.

- Row: `[file-type icon 34] [filename, middle-truncated, 14 pt] [size or state]`, with §3.2c's line
  under it while the bytes are moving — see §5.0, item 4.
- Middle truncation is required — `97103328759-202…01-2026-08-31.pdf` keeps both the prefix and the
  extension, which head- or tail-truncation would each destroy.
- **Completion is announced on the button the file was thrown at**, in both layouts, by
  `AppDelegate.announceCompletion` → `downloadsSite()`. A list already standing open is showing that
  row finish and is left exactly as it is.

**The list is a pop-out, not a panel.** §15.3's list was an `NSPanel`: a standard titled utility window
with a table and a row of push buttons. Pressing a button in Liquid Glass chrome and being handed that
is a different application answering; it takes focus off the page, it has to be closed rather than
glanced away from, and it was the only surface in Luna that looked like it was built in 2012.

> `PopoutPanelView` is the shared surface: sheet, glass body, `Shadow.popover`, the two clamps and the
> spring. The only thing that differs between History and Downloads is **which way it grows** out of its
> button, so the caller says `.above` or `.below` and nothing else changes.
> **Gotcha (crashed the app, found by runtime bisect):** **never set `frameCenterRotation` on a view that
> contains a `Glass` backing.** `Glass.backing` puts an `NSGlassEffectView` inside, which lays its own
> `contentView` out with constraints — and Auto Layout cannot express a rotation, so the engine returns
> **NaN** and AppKit traps in `_NSViewValidateGeometry` ("Invalid view geometry: y is NaN") on the next
> layout pass, with no frames of ours in the stack. It was a rotated square being used as a pointer
> tail, and the answer was a `CAShapeLayer` mask on an unrotated view of the same bounding box.

#### The completion popover — **removed 2026-09-21**

A download landing used to put up a second surface: an `NSPanel` floating **outside** the window above
the top edge, ~330 × 58 at radius 14, with a pointer tail down into §4's Downloads button, a
middle-truncated filename, a confirm button and a 4 s timer. It was built as §30.15's primary surface,
with the list behind it as secondary.

It was aimed at one chrome and redundant in the other. A body that floats above the window's top edge
with its tail pointing *down* is a shape that only exists for a button at the top: hung off §3.5's
cylinder in the bottom-left it appeared in the opposite corner of the screen with its tail in the
sidebar toggle, answering the right event at the wrong end of the window. And in the top bar, where it
was at least aimed correctly, it was a card repeating what the list underneath it already said — two
answers to one question with one floating over the other.

So there is one answer now, and §5.0 is why it can be: a file that has just been *thrown* at a button
should be found at that button. `DownloadManager` no longer knows what the announcement looks like; it
fires `onFinish` and the host puts the list up on `downloadsSite()`'s anchor.

### 5.0 Arrival — the file goes to the button

A download **starting** was the event with nowhere to happen. Everything §5 had was about a download
*finishing*; until then the only thing that had changed was a number inside a panel nobody had open.
So:

1. **The file's own icon leaves the page on an arc** and lands on the Downloads button — the real
   file-type icon at `downloadsFileIcon`, carrying `Shadow.popover` because it crosses an arbitrary
   page, shrinking to `glyphSize` on the way, solid until the last sixth and then gone.
   `downloadFlight`: 0.30 s, **linear**, and the linearity is the point — see 2.
2. **It is a thrown object, and the physics is in the path.** The quadratic's control point is the
   **corner** of the box the two ends make, nudged away from the landing by one icon, so
   `x(t) = origin.x(1−t)² + landing.x(1−(1−t)²)` and `y(t) = origin.y(1−t²) + landing.y·t²`:
   horizontal speed decaying, vertical accelerating as the square. It covers the ground first and
   turns into the button at the end, in both layouts, and it arrives with pace for the catch to
   answer. A timing curve on top of this is a second acceleration fighting the first.
   > **What this replaced, and why.** The first build lifted the *midpoint* straight up, on the
   > reasoning that a lob goes up before it comes down. It does — but a lob to a button in the
   > **bottom** corner leaves the page in the wrong direction and then comes back, and the eye
   > follows that as a detour rather than as a throw. `easeInOut` made it worse at the other end:
   > the icon *slowed down* into the button, which is the one moment it should be arriving with
   > pace, so the catch was answering nothing.
3. **The button's glass catches it**: `downloadCatchSwell` (18 %) springing back to rest on
   `downloadCatch`. It is the **capsule** that bulges, never the glyph inside it — §6's hand-up rule,
   for the same reason presses use it. The swell is bigger than a press's 5 % because a press is the
   user doing something to the button and this happens in a corner they are not looking at.
4. **Then §15.3's list opens underneath, with the bar running** — `[filename] [4.2 MB of 18 MB]` and
   §3.2c's line, `loadLineHeight` of `Accent.tint` **over a `Surface.hover` track**. The track is the
   one difference from the address bar's line: a pill is its own track and a row is not, so without
   one the line says how far the bytes have come and nothing about how far they have to go.
   It counts itself down after §5's 4 s, and hovering it stops the clock.

**Both chromes, one animation.** §3.5 puts Downloads at the bottom-left of the window and §4 at the
top-right; the arc is drawn between two points and knows nothing else, so the layout decides where the
file goes and not what happens to it. `AppDelegate.downloadsSite()` is the single place that answers
"which button", for the flight, for the list and for `⌘⌥L` alike.

**It leaves from the pointer.** WebKit does not say which element started a download or where that
element was drawn, and asking the page would be Luna running script on every site to decorate an
animation. The pointer is where the link the user just clicked was, which is almost every download;
the centre of the content is the fallback for the rest, and a file appearing to leave from the middle
of the page is a thing that came from the page.

**A download the user declined never flies.** The flight fires when the destination is settled, not
when `WKDownload` arrives — §15.4's confirmation sits between the two, and a file thrown across the
window behind a modal sheet is a flight nobody sees for a download that did not happen.

- **Reduce Motion: nothing flies and nothing bulges.** The list still opens — that is information,
  not motion.

---

### 5.1 Completion animation — the particle sweep — **removed 2026-09-21**

The filename in the completion popover dissolved into ~1200 particles and reassembled: a directional
left → right dissolve over **0.22 s**, a settle back into place over **0.18 s** with a 0.04 s
per-particle stagger, **0.40 s** total, drawn as **one composited node** rather than 1200 `CALayer`s
(`CAEmitterLayer` could not do it — a simulation gives no handle on an individual particle, so
"settle back into place with a stagger" is unreachable, and one `emitterPosition` cannot sample glyph
shape). It cost ~0.3 ms of an 8.3 ms frame at 120 Hz.

It drew the popover's filename and nothing else, so it went when the popover did. The motion §5 has
now is §5.0's, at the other end of the download: the arrival is the thing worth animating, because it
is the thing the user has no other way to find out about.

---

### 5.3 First run — the installer, and the screen after it

Two surfaces a user sees before Luna has done anything for them, and the only
two that have to work on a Mac with no Luna data on it at all.

**The disk image** (`Tools/make-dmg.sh`, `Tools/dmg-background.swift`). Luna.app,
an Applications alias, and an arrow between them, on the moon used as a light
source: an enormous crescent bleeding off the top-right corner, soft enough to
read as where the light is coming from rather than as a logo printed twice.
The plane is artwork (`assets/dmg/dmg-background-*.jpg`); the arrow and the one
line of type — "Drag Luna into Applications" — are drawn over it at build time,
because type that has been through a resampler is the one thing on this page a
reader looks at closely.

It is **dark, with a light chip under each icon label**. Finder draws those two
labels itself and takes no colour, so the ground under them is the only lever
there is. Measured on macOS 26, each plane opened fresh under each appearance:

| | light system | dark system |
|---|---|---|
| light plane | black labels | black labels |
| bare dark plane | **black labels — on near-black** | white labels |
| dark plane, chipped | black labels | black labels |

A dark system picks the label colour from what is behind it; a light system
draws black whatever is there — so a light ground under the name is black text
on both, which is what lets the dark plane ship. The chip is a capsule sized to
the name and centred on the icon's column: a diffuse pool of light does the
same job and reads as a smudge. A disk image stores **one** background picture,
in the volume's `.DS_Store`, and nothing re-reads it when the appearance
changes, so one plane has to serve both kinds of Mac;
`Tools/make-dmg.sh … --light` builds the other. The window is 640 × 400 with
its toolbar and status bar off; the icons sit on the line the arrow is drawn
between.

**The backdrop cannot follow the appearance, and three probes say why.** A
picture with an alpha channel is composited — but onto a fixed white, measured
identical under both appearances, so a translucent plane is a white page on a
dark Mac. A volume with no background picture at all gets Finder's own icon
view background, which *does* react (near-black with white labels in dark, white
with black labels in light) — and has no artwork, no arrow and no instruction
on it. And `backgroundImageAlias` is a single alias: one picture, resolved once.
So the choice is art or reaction, and art wins: one image ships, the dark one,
because the chips keep it legible on a light Mac and it is what the app looks
like. `--light` builds the other for anyone who wants it.

**The app icon on that page is not ours to switch.** macOS 26 has an icon
appearance of its own — System Settings ▸ Appearance ▸ *Icon & widget style* —
and pinning it to Dark renders every app's icon dark in light mode, Luna's with
the rest. Luna ships both renditions (`Assets.car` carries the icon under
`NSAppearanceNameAqua` and `NSAppearanceNameDarkAqua`), and with the style left
on Default the light tile appears in light mode. A dark tile on a light Mac is
that setting, not a missing variant.

**First run** (`Features/Onboarding/`, §30.17–30.18) is a window over the
browser, not a sheet in front of it: the session is restoring behind it, and a
gate before the thing the gate is about is a form with no context. Closing it
is an answer, and it never asks twice (`OnboardingState.hasRun`).

| | |
|---|---|
| Size | `commandBarMinWidth` of prose beside a pane as wide as Settings' detail side, at Settings' height |
| Left | Opaque `Surface.base`: the page's title at `pageTitle`, one sentence at `pageBody`, two answers at the foot |
| Right | The sidebar's own material — `Glass.sidebar` under a `SpaceWashView` set to neutral, so it paints nothing and the material is the colour |
| Answers | `Back` over the preferred one, both the column's width, in the same place on every page |
| Lights | `TrafficLightLayoutManager(pinningLightsIn:)`, all three, two of them dim — §7.7's one owner, so they land where every other Luna window's do |

- **Three pages**: welcome, transfer, done. The words live in `OnboardingPage`
  and nowhere else, because §30.18's copy warning — the reference promises
  "bookmarks, history, and **extensions**" and Luna can import none of the
  third — is a promise that gets broken in a string literal nobody is looking
  at. `OnboardingCopyTests` asserts every string the screen can show.
- **The transfer page lists the browsers that are on this Mac**, and only
  those. §30.18 asked for the rest greyed out with a reason; on a real Mac that
  is eight rows of "isn't installed" around the two that are, which is a wall
  with the answer hidden in it. An installed browser Luna cannot read yet keeps
  its place and says why — Safari, which needs Full Disk Access — because that
  one is a thing the user can fix.
- **Where the reason has an answer, the row carries the answer.** A
  `DetectedSource` with an `ImportRemedy` shows a button in place of the
  sentence — `Grant Luna Full Disk Access`, which opens that pane rather than
  the top of Privacy & Security. Two lines describing where a switch is, when
  the switch can be one press away, is the paragraph earning its keep by
  being long.
- **A card, not a row.** Two chrome capsules tall, the app's own icon at
  `capsuleHeight + rowInset`, the name at `pageBody`, and a tick that fills
  with the accent. It answers the pointer and the finger like every other
  control (§6), because it is one. It stands `margin * 3` in from both sides
  of its pane — a plate the full width of its half is a table row, and flush
  to the scroll view it came back from a press with its corner sliced off by
  the clip.
- **The chosen card is `Glass.control`; every other card is a plate.** The
  pointer's own wash is already `Surface.selected`, so a chosen card drawn
  with the same wash was indistinguishable from the one under the pointer.
  Picked is the brighter material, not the same material with a mark on it.
- **The whole card is the target.** Its name and its reason are
  `NSTextField`s, and a label answers `hitTest` for its own rectangle — so a
  pointer aimed at the browser's name, which is the middle of the card, landed
  on a control that is not one. `OnboardingButton` had the same hole.
  Everything inside either is decoration.
- **The browser the Mac opens links with starts ticked**, or the first Luna
  can read. The screen's answer is "yes, bring it", and a column of empty
  circles asks the user to work that out from the button — and the one they
  would pick is the one they are switching from. It unticks like any other.
  The machine's answer is supplied by the window controller rather than read
  by the view, so the rule is provable without the test depending on the Mac
  it runs on.
- **The mark is the app's own icon at the appearance it is drawn on**, from
  `assets/icon/mark/Mark.xcassets`. Neither `NSApp.applicationIconImage` nor
  `NSImage(named: CFBundleIconName)` will do it: the `.icon` document carries
  an Aqua rendition and a DarkAqua one, and both of those hand back a single
  flattened rendering — measured as identical pixels under either appearance
  — so the white tile sat on a dark page. An imageset with a dark variant is
  the thing AppKit resolves, and `OnboardingScreenTests` measures the two.
- **The rows arrive staggered** on §6's `tabInsert`, 20 ms apart — the same
  stagger a layout switch gives its contents. Each one carries its own progress
  while the import runs; a bar under a list of five browsers says less than the
  five of them ticking off one at a time.
- **The import is §23.2's engine, unchanged**, one source at a time, and a
  failure marks its own row and lets the rest run. What it writes goes straight
  to the store, so the live session is told to pick it up
  (`BrowserSession.adoptSpacesWrittenElsewhere`) — additive only, so no open
  tab is replaced by a refresh it had nothing to do with.

---

### 5.2 Quit sheet — ⌘Q asks first

A glass panel in the browser window, not an `NSAlert`: the app icon at `topBarHeight`, the question
at `TypeScale.pageTitle`, one sentence of what is actually at stake, and three answers in a row.

| | |
|---|---|
| Surface | `Glass.popover` + `Shadow.popover`, `contentCardRadius`, half a chrome bar above centre |
| Width | the **answers'** width, floored at three quarters of `windowMinWidth` |
| Answers | `Quit, and don't ask again` — gap — `Cancel` `esc` — `Quit` `↩` |
| Backdrop | **none** — §9.1's finding, and it holds here |

- **The caption is the point.** Luna restores the session, so the honest line is the tab and Space
  count plus the promise. A download in flight replaces it: that is the one thing quitting destroys
  rather than parks, and a warning that overstates what it guards is one you learn to click through.
- **The two groups are held apart.** *Quit, and don't ask again* changes a setting; the other two
  answer this press. Evenly spaced, the permanent one is picked by muscle memory aiming at the
  temporary.
- **The recommended answer is filled with the accent**, and it is the only control in Luna that is —
  §2's "no system blue anywhere" survives everywhere else. Its two other states are AppKit's own
  `withSystemEffect` variants, so the hover and press match every stock control in whichever accent
  the user picked. `Tokens.Accent.onTint` carries the whole argument.
- **The key hint is the button's end cap**, full height and flush with the trailing edge, with the
  glyph dead centre of it. Inset from the edge, the capsule's own fill came back in the last four
  points and read as a chip that had come loose.
- **Escape and a click that missed both mean stay**, and an answer arrives exactly once.
- `applicationShouldTerminate` answers `.terminateCancel` while the question is up and the answer
  re-enters it — **not** `.terminateLater`, which parks the app in a nested modal loop.
- **It only asks where it can be answered.** The `.terminateCancel` above is a quit the user has
  already asked for, so every yes owes them a sheet they can see: with the browser window closed and
  §23.1's Settings window keeping the app alive, ⌘Q put the sheet on a window nobody could see and
  cancelled the quit waiting for it — an app that would not quit, with nothing on screen to say why.
  A closed window is still the window controller's window, so the test is `isVisible` and not
  existence. With no window to ask in the quit goes straight through: the tabs the question protects
  were put away when the window closed. `QuitConfirmation.isNeeded` is the rule, apart from the app
  it is about, because a wrong answer there is unquittable rather than merely quiet.

---

## 6. Motion

Nothing exceeds **0.35 s** except the two cases marked, which are not discrete transitions: §7's
reload bloom is bound to real load progress, and §3.4's row shimmer repeats for as long as the tab is
loading, so its duration is a rate and not a delay. Every entry degrades to instant under Reduce
Motion.

| Interaction | Animation |
|---|---|
| Space switch | spring, response 0.30, damping 0.70; sidebar content cross-fades 0.18 s |
| Sidebar collapse / expand | 0.20 s ease-out width + 0.12 s opacity |
| Layout switch (sidebar ↔ top bar) | 0.30 s, contents stagger 20 ms |
| Hover-peek reveal | 0.10 s intent delay → 0.15 s ease-out slide |
| Command Bar in / out | 0.18 s spring, scale 0.96 ↔ 1.0 + fade, anchored 20 % from window top |
| Command Bar in / out, on a pill | the same 0.18 s spent on the glass's height, pill ↔ list (§9.1) |
| Pop-out in / out (§6.4) | the same spring, 0.96 ↔ 1.0 + fade, pivoting on the button's corner both ways |
| Panel fade in / out (§14.3, §14.4) | `popoverIn`, and the same fade backwards on the way out |
| Tab insert / remove | 0.22 s spring height + fade, no list jump |
| Row hover fill | 0.12 s ease-out |
| Control button hover lift | 0.10 s ease-out |
| Control button press | fill one step up, + 5 % swell on a 0.16 s spring, damping 0.62 |
| Selected-row pill move | 0.20 s spring, response 0.28, damping 0.80 |
| URL pill theme wash | **withdrawn** — see §2 |
| Split divider snap | 0.12 s |
| Download flight (§5.0) | 0.30 s **linear** along the arc — the acceleration is the path's (§5.0) |
| Download catch (§5.0) | spring, response 0.24, damping 0.55; the capsule bulges 18 % and springs back |
| Row loading shimmer (§3.4) | **1.10 s** linear, repeating for as long as the load runs |
| Page reload bloom | **tied to load duration** (see §7) |
| Content card → fullscreen | 0.30 s ease-in-out |

> **The selected-row pill moves for ↓ and ↑, and for nothing else.** A list that has just been rebuilt
> has no continuity for a slide to describe, and one that has not changed has nowhere to slide — so the
> highlight is always *placed* from `layout()`, and animated only when the selection moved inside a list
> that stood still. Moving it from the method that replaces the list instead measured rows that had not
> been laid out at their new size yet: while somebody typed fast in the Command Bar, the pill slid to
> somewhere slightly wrong on every re-rank and the next layout pass pulled it back.
>
> **The Command Bar's own opening is 0.18 s of that same thread**, so nothing replaces its list while it
> is opening: asynchronous results that land inside that window are held, and applied *append-only* the
> moment it closes — a row the bar opened with never moves. The bar also waits, standing at the pill's
> own size, until the store has answered the query it is opening with (100 ms at the outside), so what
> the morph grows around is the list it is going to keep. See TODO.md §9.7.

> **Hover and press are a fill and a shape, on every button Luna draws.** Hover is `Surface.hover`
> over whatever the control is made of; a press is `Surface.selected` — the same wash at twice the lift
> — plus a 5 % swell that springs back when the button is let go. `GlassButton` washes above its
> material, `RowGlyphView` paints the chip on its own layer under the glyph, `TopBarButton` lifts the
> fill it already had. A button with no material of its own (`GlassMode.none`, the two chevrons inside
> §3.1's history capsule, an item inside §4's action capsule) hands the press to the surface that
> *has* one, because half a capsule swelling inside the other half is not a press.
>
> **"Every button" is a register now, not a sentence.** This rule was written when the sidebar got it
> and was then read as describing the app: the top bar, both action capsules, Settings' chevrons, its
> push button, the two appearance chips and the palette button all shipped with a hover and nothing
> under the finger. `Tests/Design/ButtonFeedbackTests.swift` is the list, and a new button that does
> not answer fails it.
>
> **Where a wash is the wrong answer, the control answers some other way — it does not skip it.** A
> colour swatch cannot take a 6 % white without showing a different colour, so `SpaceSwatchChip`
> answers the pointer with its ring; a control drawn as a well is black ink, so lifting it with white
> would flip a recess into a plate, and `SettingsShortcutRecorder` brightens its ink instead. Both
> still swell, because the swell is the one part of the answer that costs a control nothing.
>
> **A list row is not a button.** Its highlight is one pill that slides between rows (§3.4), and a
> full-width plate growing 5 % is the list jumping rather than a control being pressed.
>
> Measured against the macOS 26 controls Martin captured for the reference: theirs lift about 10.7 %
> on hover and 12.8 % under a press; Luna's are §3.4's own 6 % and 12 %, because those are the two
> steps the rest of the app is built from.

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
(§25.6) and the import screen (§30.17). Each gets its own pass.

§30.19's New Tab page is not on that list any more: it is gone. Every way into it already
opened §9.1's Command Bar — `⌘T`, §3.4's New Tab row, §4's `+`, and the page's own pill, which
handed off rather than taking a second line of input — so what was left was a page whose only
job was to be somewhere to stand while the bar was open. A tab with no address is `about:blank`,
an empty Space opens no tab at all, and the two wells in §3.3a are what the column says instead.
