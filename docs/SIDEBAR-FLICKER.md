# The black band on the page's trailing edge (§4.1)

**Status: unsolved. Four approaches tried and reverted. Nothing from this
investigation is in the tree.**

This file exists so the next attempt starts from the measurements rather than
from the beginning. The expensive part of this work was not the code — every
patch was small — it was finding out what the band is *not*.

Investigated 2026-09-20 against `4a3d4a0`.

---

## The symptom

Hiding or showing the sidebar (`⌘S`) flashes a dark band down the **right** edge
of the page for the length of the slide. It is only visible on light pages: the
band is `#1b1b1b`, which is invisible on a dark one.

It is not a rendering glitch of the sidebar. The band tracks the sidebar
exactly:

| t | sidebar width | band width | sum |
|------|------|------|------|
| 3.92s | 230px | 30px | 260 |
| 3.97s | 130px | 130px | 260 |
| 4.03s | 60px | 210px | 270 |
| 6.40s | 30px | 230px | 260 |

**sidebar + band = 270px, the sidebar's full width.** The band is exactly the
slice of the page that has not caught up yet.

## Why it exists at all

`ContentCardView.beginGeometryTransition(toWidth:over:)` deliberately hands the
page its **final** width in one step, so it reflows once instead of once per
frame of the 0.20 s slide. That optimisation is correct and worth keeping — its
own doc comment records what the alternative looked like ("on a heavy site that
is a visible stutter and a column of text that jumps four times on the way").

The cost of that trade is that on hide the page becomes ~270 pt wider
*instantly*, and something has to fill the strip until WebKit paints it. The
whole investigation is about what that something is.

**Reverting the single-reflow optimisation would remove the band and cost the
stutter back. Do not do that.**

---

## How to reproduce and measure

This harness is the reusable part of this work. It turns "looks flickery" into a
frame count, which is the only way any of this was decidable.

Record four toggles over a light page (example.com works; it renders `#ebebeb`):

```sh
# 1. select a light page in Luna, then:
screencapture -v -V 13 /tmp/flicker.mov &
sleep 1.5
for i in 1 2 3 4; do
  osascript -e 'tell application "System Events" to keystroke "s" using command down'
  sleep 2.5
done
```

Count the flicker frames:

```sh
ffmpeg -v error -i /tmp/flicker.mov \
  -vf "crop=1920:958:0:36,scale=192:24,format=gray" \
  -f rawvideo -pix_fmt gray /tmp/flicker.gray -y

python3 - <<'PY'
W, H = 192, 24
d = open('/tmp/flicker.gray','rb').read()
n = len(d) // (W*H)
hits = []
for f in range(n):
    fr = d[f*W*H:(f+1)*W*H]
    c = [sum(fr[r*W+i] for r in range(H))//H for i in range(W)]
    w = 0
    while w < W and c[w] < 40: w += 1          # sidebar width
    right = [i for i, v in enumerate(c) if v < 40 and i > w+2]
    if right: hits.append((f, w*10, right[0]*10, (right[-1]+1)*10))
print(f"{n} frames | flicker frames: {len(hits)}")
for f, sb, a, b in hits[:8]:
    print(f"  f{f} t={f/60:.2f}s sidebar={sb}px band x{a}-{b} ({b-a}px)")
PY
```

**Baseline: 33 flicker frames out of 780, widest band 230px.** Any candidate fix
is judged against that number, recorded the same way.

To identify the band's colour rather than just its darkness, pull one frame and
sample pixels directly — do not eyeball it:

```sh
ffmpeg -v error -ss 6.40 -i /tmp/flicker.mov -frames:v 1 /tmp/f.png -y
ffmpeg -v error -i /tmp/f.png -f rawvideo -pix_fmt rgb24 /tmp/f.raw -y
python3 -c "
W=1920; d=open('/tmp/f.raw','rb').read()
px=lambda x,y:(lambda i:(d[i],d[i+1],d[i+2]))((y*W+x)*3)
print('page', px(1000,400), 'band', px(1800,400))"
```

### Notes on the harness

- **Wake the display first** (`caffeinate -u -t 2`) — a sleeping display records
  as pure black and silently invalidates everything.
- The computer-use MCP lost its display scope partway through this session.
  `screencapture` plus `osascript … keystroke` is a complete substitute and has
  no such dependency. `⌘2` selects the second sidebar row, so the whole protocol
  is keyboard-only.
- `xcodebuild`, `swift test`, `swift build` and `xcodegen` all need the command
  sandbox disabled in this environment.

---

## What is established

1. **The band is `#1b1b1b`**, sampled per-pixel, on a page rendering `#ebebeb`.
2. **It lasts 4–9 frames per toggle** (~70–150 ms), on both hide and show.
3. **`#1b1b1b` is WebKit's appearance-derived default.** It shows up in a unit
   test too: clear `underPageBackgroundColor` and `state.pageBackground` comes
   back `RGBA(0.1176, 0.1176, 0.1176)`. Luna sets `NSApp.appearance` from the
   Theme setting, every `WKWebView` inherits it, so a light page under dark
   chrome gets a near-black fill colour.
4. **It is not the content card.** `ContentCardView`'s layer background was
   forced to magenta; once a page was loaded, **0 frames** showed magenta. The
   card is never what is visible in the strip.
5. **It is not `underPageBackgroundColor` either** — see the open question.

## The open question

Attempt 4 put the page's true colour on `underPageBackgroundColor` and verified
it stayed there for the whole slide:

```
+30ms  underPage = 0.933333 0.933333 0.933333   (light)
+400ms underPage = 0.933333 0.933333 0.933333   (light)
```

**The band was still `#1b1b1b`.** So it is neither the card (4) nor the
UI-process value of `underPageBackgroundColor` (5) — and those were the only two
candidates this investigation considered.

An earlier magenta probe *appeared* to prove the band was the under-page fill.
**That experiment was confounded** — that build set the card's background *and*
the web view's under-page colour to magenta, so it could not distinguish them.
Do not treat it as evidence.

### The experiment to run first next time

Set a **different, distinctive colour on every candidate surface at once** and
see which one appears in the band:

- `ContentCardView`'s layer background
- `WKWebView.underPageBackgroundColor`
- `NSWindow.backgroundColor`
- the web view's own `layer.backgroundColor`
- `SpaceCornerFillView` / `TrafficLightSpace`

One recording then names the surface, instead of four attempts each eliminating
one. The likely remaining answer is that the WebContent process paints
newly-exposed area with its own fill during a resize, and does not consult the
UI-process `underPageBackgroundColor` for it — in which case no colour plumbing
fixes this and the fix has to be geometric (do not expose unpainted area), not
chromatic.

---

## Attempts, in order

Every one of these was built, measured and reverted. None is in the tree.

### 1. Paint the card in the page's colour
Give `ContentCardView` the page's colour so any exposed strip matches the page.

**Result: no effect.** Follow-up (card forced magenta) showed **0 magenta
frames** once a page was loaded — the card is never visible in the strip. The
premise was wrong.

### 2. Pin WebKit's own pre-slide value for the length of the slide
Theory: WebKit's answer is correct at rest and goes stale during relayout, so
hold the last good one across the transition.

**Result: 33 → 58 flicker frames. Worse.** Sampling the band pixel showed
WebKit's answer is *already* `#1b1b1b` at rest, so there was nothing good to
hold — pinning only made the wrong colour last longer. Theory disproved.

### 3. Sample the page's canvas colour, pin it at slide start
Sample the CSS canvas in the page script, plumb it
`AppDelegate → BrowserWindowController → ContentCardView`, apply it in
`beginGeometryTransition`.

**Result: 33 → 21.** A probe confirmed the correct colour reached a real
`WKWebView`. But pinning **magenta** through the identical path produced **0
magenta frames** — so setting the colour at slide start has no effect at all.
**WebKit latches its fill colour before `beginGeometryTransition` runs.** Any
future fix must have the colour standing *before* the slide begins.

### 4. Standing pin, set on page load
The full version: sample the CSS canvas colour (root element's background,
falling back to body) in `scrollScript`, post it to Swift, store it on
`TabController`, and have `matchBackgroundToTheme()` hand it to WebKit whenever
the site declares no `<meta name="theme-color">`. A `MutationObserver` on
`<html>`/`<body>` attributes re-samples when a page repaints itself. A flag
suppresses one KVO republish during `resetPerDocumentState`.

~250 lines across 4 files, 4 new tests, BrowserKit **163/163 green**.

**Result: 33 → 23, band still `#1b1b1b`.** The mechanism worked — verified in
the running app, the light colour was on the property for the entire slide (see
the open question above). It simply is not what paints the band.

Two independent reviews then found the change was **net-negative** anyway. Their
measured findings are recorded below, because any future attempt down this road
hits all of them.

---

## Regressions a canvas-sampling approach must handle

These were measured with throwaway WebKit probes during review of attempt 4.
They are the reason that approach cannot simply be re-applied.

1. **A Theme switch leaves a stale colour pinned forever.** `NSApp.appearance`
   is process-wide, so flipping it flips `prefers-color-scheme` in every live
   web view. A site that honours it repaints with **no DOM mutation, no resize,
   no scroll, no navigation** — so nothing re-samples. Measured: unpinned,
   WebKit tracked the flip correctly (`#101018`); pinned, it cannot. Consequence
   is worse than the original bug: `state.pageBackground` goes stale too, so
   §3.2b's bar paints a **white plane with dark ink over a dark page**. On
   Theme = auto this fires unattended at the macOS light/dark switch.
   *Needs a `matchMedia('(prefers-color-scheme: dark)')` listener.*

2. **A dark-mode toggle with a CSS transition samples the pre-toggle colour.**
   `getComputedStyle().backgroundColor` inside the mutation microtask returns
   the *interpolated* value, i.e. the start colour, and nothing clears the cache
   afterwards. Measured on two pages differing only by a `transition:`
   declaration, flipped white → black: without, the observer read
   `rgb(0,0,0)`; with, it read `rgb(255,255,255)`. That is the original bug with
   the polarity inverted — a **white** band on a black page. `schedule()` does
   not help (one rAF ≈ 16 ms into a 300–600 ms transition).
   *Needs `transitionend` or a deferred re-sample.*

3. **A transparent canvas is the CSS default, so the headline case is missed.**
   No UA stylesheet sets `background-color` on `html` or `body` — that is *why*
   CSS needs a canvas-propagation rule. Measured on
   `<html><body>hello</body></html>`: both computed values are
   `rgba(0,0,0,0)`, the sample is rejected, and `underPage` stays `#1e1e1e` on a
   page that renders white. A page that sets its background on a wrapper `<div>`
   is missed the same way.
   *Needs an explicit white fallback keyed on `color-scheme`.*

4. **Cross-document race.** `WKScriptMessage` delivery is asynchronous. A post
   from the outgoing document can arrive after `didCommit` has run and get
   pinned onto the incoming one. Unlike `topColour`, which self-heals on the
   next scroll, a pinned canvas is only rewritten when the sample *changes*, so
   a stale pin can stand indefinitely.
   *Needs a per-document generation counter echoed through the message.*

5. **`canvas()` must skip `background-image`**, the way `painted()` already
   deliberately does — otherwise `background-color: #fff` under a dark gradient
   pins white on a black page.

6. **`parse()` only understands `rgb()`/`rgba()`.** `getComputedStyle`
   serialises non-sRGB colours in their own space, so `oklch(…)` — Tailwind v4's
   default palette — fails to parse. Pre-existing, but a canvas fix promotes it
   from "the bar's top strip" to "the whole-page fill".

---

## A real issue found on the way, independent of the band

**Luna's `underPageBackgroundColor` is wrong for every page that declares no
`theme-color`.** WebKit derives it from the view's appearance, which carries
Luna's chrome theme rather than the page's, so a white site in dark Theme
reports `#1b1b1b`.

This is worth fixing on its own merits — it is the over-scroll colour, and it is
§3.2b's bar's fallback plane (`PageChromeBar.refreshPlane`, `topColour ??
documentColour`), where it drives the bar's `NSAppearance` and therefore its ink.
It is **not** what causes the band, so fixing it will not close this issue.

Note the option that does *not* work here: making the web view follow the OS
appearance instead of Luna's theme. On a machine whose OS is already in Dark
Mode — the common case for a user who also picked a dark chrome — that changes
nothing.

---

## Recordings

`~/Desktop/luna-sidebar-flicker/` holds a 60 fps capture of the pre-fix
behaviour (full speed, 5× slow motion, and the worst frame magnified). They can
be regenerated from the harness above; they are not in the repo because binary
video does not belong in git.
