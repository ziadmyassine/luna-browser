# Error page and empty pane paintings

One painting per error page and appearance, `error-<kind>-<light|dark>.jpg`,
served to the page at `luna://art/<file name without .jpg>` and drawn behind
its words (`InternalPageHTML.swift`, "A painted error page"). `https` is the
`httpsDowngrade` kind.

Each is a single Nano Banana Pro generation at 16:9, 2K, saved as JPEG at
quality 80. Every painting keeps the upper left and centre as open sky, with
the moon top right and the subject small on the dunes at the lower left,
because the headline stands in that sky.

`error-dns-light` came first, from the prompt below. Every other light
painting was generated with it as the image reference, and every dark one
with its own light painting as the reference, so the set stays one hand.

## error-dns-light.jpg — "Can't find that site", light

> A calm, minimal, painterly illustration for a web browser's light-mode error
> page called 'Can't find that site'. Soft early-morning sky in pale pearl
> white, faint lavender and warm cream gradients, very light and airy, low
> contrast. A delicate pale crescent moon sits high in the upper right, softly
> glowing, slightly translucent like a daytime moon. Along the bottom fifth of
> the frame, gentle rolling lunar dunes with a few soft shallow craters,
> rendered in muted silver-grey and blush tones with fine grain texture. On a
> small dune at the lower left, a tiny brass telescope on a tripod points up
> into an empty patch of sky, as if searching for something it can't find. A
> few sparse, very faint stars. The entire centre of the image is open, quiet,
> empty sky with generous negative space, so a text card can sit on top.
> Gouache and soft airbrush style, subtle paper grain, serene and slightly
> whimsical, Studio Ghibli sky meets Scandinavian minimalism. No text, no
> letters, no logos, no people, no borders.

## The other light paintings

Prompt, with `error-dns-light` as the reference:

> Use the reference image as the exact guide for style, palette, light, paper
> grain and composition: the same pale pearl-white and faint lavender morning
> sky, the same soft gouache and airbrush painting, the same pale crescent moon
> in the upper right, the same gentle silver-grey and blush lunar dunes with
> soft craters along the bottom fifth. Keep the whole upper-left and centre of
> the sky completely empty and calm, because a large headline sits there.
> Change the scene for an error page called '<title>': replace the telescope
> with <subject>. No text, no letters, no logos, no people, no borders.

| File | Subject |
|---|---|
| `offline` | a tiny brass satellite dish tilted down, its cable lying unplugged in the dust; the moon is a new moon, only a faint ring |
| `tls` | a small glass habitat dome with a brass frame, one pane cracked |
| `blocked` | a small rover stopped at a striped boom barrier, its tracks behind it |
| `https` | a round habitat pod with its airlock hatch swung open |
| `generic` | a tiny brass and cream rocket tipped over beside its launch stand, smoke curling from the nozzle |

## The dark paintings

Prompt, with the same kind's light painting as the reference:

> Repaint the reference image as the same scene at night, for a dark-mode web
> page. Keep the composition identical: <the scene, restated>, and the whole
> upper-left and centre of the sky completely empty and calm, because a large
> white headline sits there. Night palette: a deep, soft indigo-to-near-black
> sky, very dark and low contrast so white text reads clearly, a sprinkling of
> tiny faint stars. The crescent moon glows soft warm silver with a gentle
> halo. Dunes cool blue-grey with soft shadows. Same soft gouache and airbrush
> painting, subtle paper grain. No text, no letters, no logos, no people, no
> borders.

Each added one warm light to its subject: the telescope's and the rocket's
brass catch a highlight, the rover's headlight falls on the barrier, light
spills from the open hatch, and the crack in the dome catches the moon.

## The empty pane: `empty-light.jpg`, `empty-dark.jpg`

What the content pane shows with no page in it (`EmptyPaneView`). The light
one is the light prompt above with `error-dns-light` as the reference, for a
window with no tabs open, "a moment of rest": an empty brass-framed deck chair
facing the moon with a small brass lantern glowing beside it, and the whole
sky left open. The dark one is the night prompt with it as the reference; the
lantern casts a warm pool of light on the dust and the chair.
