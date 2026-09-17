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

All sizes derive from measured ratios against sidebar width, normalised to a **280 pt** default sidebar.
Ratios are the source of truth; if the sidebar is resized, chrome metrics do **not** rescale — only the
sidebar's own content reflows. The ratios exist to fix proportions once, not to drive live layout.

| Token | Value | Ratio |
|---|---|---|
| `sidebarWidth` default / min / max | 280 / 180 / 420 pt | 1.000 |
| `rowHeight` | 40 pt | 0.144 |
| `rowInset` (pill inset from sidebar edge) | 8 pt | — |
| `faviconSize` | 18 pt | 0.063 |
| `rowCornerRadius` | 10 pt | — |
| `urlPill` | 266 × 32 pt, radius 16 (full) | 0.951 × 0.114 |
| `essentialsTile` | 128 × 42 pt, radius 12 | 0.459 × 0.150 |
| `essentialsTileGap` | 10 pt | — |
| `essentialsIcon` | 22 pt | — |
| `controlCircle` (back, reload) | 35 pt | 0.125 |
| `controlSquircle` (sidebar toggle) | 28 pt, radius 9 | 0.097 |
| `bottomCircle` (avatar, archive) | 34 pt | 0.121 |
| `spaceDotsPill` | 56 × 22 pt, radius 11 | 0.199 × 0.078 |
| `spaceDot` | 6 pt | — |
| `windowCornerRadius` | 18 pt | — |
| `contentCardRadius` | 16 pt | — |
| `contentCardGap` | 8 pt | — |
| `topBarHeight` | 52 pt | — |
| `hairline` | 1 pt @ 10 % white / 8 % black | — |

**Colour rules.** `Accent.tint` and `Accent.danger` are **fill and ring only** — as text they measure
4.02:1 and 3.57:1 and fail §21.4. Ask for a dedicated token before colouring any text.
Secondary and tertiary text are separated by **size and weight, not alpha**: §21.4's floor compresses them
to ~0.04 alpha apart, which is invisible.

**Typography.** Sidebar rows **15 pt**, URL pill **17 pt**, top-bar URL **15 pt**, section labels 12 pt
semibold. System font throughout, monospaced digits for any numeric badge.
> This deliberately departs from §8.6's 13 pt. The reference is visibly roomier than Arc and 13 pt looks
> undersized at a 40 pt row. §8.6 should be corrected, not this.

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

**Page-derived pill wash.** Blend `themeColor` (fallback `underPageBackgroundColor`) into the URL pill
fill at **12–18 %**, animated over 0.25 s, clamped so pill text always clears 4.5:1 (§21.4). If the
clamp cannot be met, drop the wash entirely rather than shipping unreadable chrome.

**Reduce Transparency.** Every glass surface falls back to solid **`Surface.glassFallback`**, and the
page-derived wash is disabled outright.
> **Corrected in M1:** this originally said `Surface.base`. But the content card is also `Surface.base`,
> so obeying it literally made the sidebar and the card the same colour and the card vanished. There is a
> dedicated `Surface.glassFallback` token for exactly this.

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
`[traffic lights] [sidebar toggle 28] ·············· [back 35] [reload 35]`
> **Corrected in M1** against `inspiration/main-tab-bar-and-ui.png`: the toggle sits beside the traffic
> lights, and back/reload are pinned to the **trailing** edge (centres ~209 / ~251 pt), not grouped after the
> toggle. The row must also *measure* the traffic lights rather than assume a width.

- Traffic lights are **system-drawn**, inset into the sidebar. A single `TrafficLightLayoutManager` owns
  their frame for all six window states (§7.7 — this is the #1 bug source in Arc-style browsers).
- Buttons are circular glass with a hairline border; **hover lifts the fill** (not the border).
- Back is disabled-dimmed at 35 % when `canGoBack` is false. Reload becomes a **stop** glyph while loading.

### 3.2 URL pill — 266 × 32, full radius, 12 pt below the control row
- **Domain only**: `apple.com`, not the full URL (§30.3). eTLD+1 plus subdomain when meaningful.
- Left-aligned text at 12 pt inset; trailing **sliders glyph** (site menu) at 10 pt from the right edge.
- Two further icon slots are **reserved and sized** to the left of the sliders glyph but render nothing.
  AI and extension actions live in the top-bar action capsule, not here.
- Click or `⌘L` → expands to the full URL, selected, in edit mode. `Esc` reverts.

### 3.3 Essentials grid — 2 across, wrapping
- Tiles 128 × 42, radius 12, 10 pt gap, 8 pt outer inset. **Tile width flexes:** 8 + 128 + 10 + 128 + 8 = 282,
  which does not fit a 280 pt sidebar, and the grid must survive the 180–420 pt resize range regardless.
- **Icon only, centred, 22 pt.** No label. Visually distinct from the text rows below (§30.5).
- Translucent fill + hairline. Active Essential gets a brighter fill and a 1 pt accent ring.

### 3.4 List rows — 40 pt each
Order: `Archive` folder row → `+ Add Tab` row → separator → tabs.

- `[status dot 6] [favicon 18] [title 15 pt, single line, tail-truncated] [trailing affordance]`
- Favicon at 12 pt from the pill's left edge; title starts 40 pt in.
- **Selected row:** filled translucent pill spanning sidebar width minus 8 pt each side, radius 10,
  **visible hairline border**, brighter text. **Unselected rows have no background at all** (§30.7).
- **Status dot** leads the row only when the tab has unread/updated content (the Discord row in the
  reference). Audio gets a **trailing** speaker glyph, click-to-mute.
- **Hover** reveals a trailing close/archive affordance and lifts the row fill to 6 %.
- Loading shows a shimmer sweep across the title, not a spinner.
- `Archive` and `+ Add Tab` are first-class rows with identical metrics to tabs (§30.6).

### 3.5 Bottom utility bar — 52 pt, pinned
`[profile avatar circle 34, left] ··· [space dots pill 56 × 22, centred] ··· [archive circle 34, right]`

- **Space dots** are the Space switcher: one 6 pt dot per Space, active dot 100 % white, inactive 35 %.
  Click a dot to switch; the pill widens by 8 pt per Space beyond three.
- Avatar is the active profile; click opens the profile menu.

### 3.6 Content card
Rounded 16 pt, opaque, inset 8 pt from the sidebar and from the window's top, right and bottom edges. The
gap shows the window's glass through it — **this is what makes the whole thing read as floating** (§30.11).
Entering page fullscreen animates the card to fill the window over 0.3 s.

### 3.7 Sidebar resize handle
A `◁|▷` handle floating on the sidebar/content divider, **appearing on hover after 0.1 s**. Drag resizes
within 180–420 pt, double-click resets to 280. The hit area is 8 pt wide; the drawn handle is 20 × 32.

---

## 4. Top-bar layout

One 52 pt glass bar spanning the window. **Content is flush full-bleed below it — no inset card, no gap.**

`[traffic lights] [sidebar toggle 28] [back 35] [tab tiles …] [ACTIVE TAB pill] [tab tiles …] [hairline] [action capsule]`

- **Tabs are visible in this mode as a horizontal strip.** Inactive tabs render as 28 pt icon-only tiles;
  the **active tab expands into the URL pill** showing its domain, favicon and sliders glyph. This is why
  tiles appear on both sides of the pill and why the pill is not exactly window-centred.
  > This supersedes §30.12's claim that tabs are invisible in this mode.
- **No reload button** in this layout — the reference omits it. Reload is `⌘R` and the site menu.
- The strip scrolls horizontally when it overflows; the active tab is always scrolled into view.
- **Action capsule**: its own rounded glass capsule, separated by a vertical hairline, holding
  `[+ new tab] [downloads] [profile]`. Extension action buttons dock here when extensions ship (v2) —
  build the capsule to host a variable number of items now.

### 4.1 Switching layouts
The sidebar toggle animates between the two. Sidebar width collapses to 0 while the top bar's height
animates 0 → 52 and its contents stagger in at 20 ms intervals. Total 0.3 s. Traffic lights re-anchor in
the same transaction — never as a second step, or they visibly jump.

---

## 5. Downloads popover

- **Renders outside the window bounds**, floating above the top edge, with a **visible pointer tail**
  into the downloads button. It is an `NSPanel`, not an in-window view.
- Size ~330 × 58, radius 14. Heavier glass than the bar, with its own shadow.
- Row: `[file-type icon 34] [filename, middle-truncated, 14 pt] [confirm button 30, radius 9]`
- Middle truncation is required — `97103328759-202…01-2026-08-31.pdf` keeps both the prefix and the
  extension, which head- or tail-truncation would each destroy.
- Appears on download completion, auto-dismisses after 4 s, or on confirm. Hovering cancels the timer.
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

## 7. Reload / refresh animation

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

- **Keyboard:** the §20.1 default map applies. `⌘S` toggles the sidebar, and in top-bar mode toggles back.
- **Every chrome control is keyboard reachable** with a visible focus ring (§21.1, §20.2).
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
