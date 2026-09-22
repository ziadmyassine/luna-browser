import Foundation

//  The shell every internal page is poured into, and the only stylesheet they
//  have.
//
//  There is not one colour or length value in this file. Every declaration
//  reads `var(--luna-…)`, the custom properties are generated from
//  `Design/Tokens.swift` by `Features/InternalPages/InternalPageTheme`, and the
//  only fallbacks are CSS system colours and CSS keywords (`Canvas`,
//  `CanvasText`, `GrayText`, `AccentColor`, `thin`, `medium`) — the OS's own
//  values, never a second palette that can drift from Luna's.
//  `InternalPagesTests.stylesheetCarriesNoLiterals` fails if a hex value, an
//  `rgb(`, or an absolute length ever appears here.
//
//  Light and dark (§8.8) and Increase Contrast are not branched in Swift:
//  `prefers-color-scheme` and `prefers-contrast` do it inside the page, which is
//  the only hook that works — on macOS 26.5 Increase Contrast is not an
//  `NSAppearance` at all (`Design/Tokens.swift` header), so there is nothing for
//  a Swift-side branch to observe and nothing to invalidate. The palette ships
//  all four variants and the page picks. Reduce Motion is
//  `prefers-reduced-motion`, live for the same reason.

extension InternalPages {

    /// Every custom property the stylesheet reads. The app's generator must
    /// define all of them, and may define nothing else — that is the whole
    /// token→CSS contract, and it is checked from both sides
    /// (`InternalPagesTests` here, `InternalPageThemeTests` in the app).
    public static let paletteVariables: [String] = [
        "--luna-surface-base", "--luna-surface-raised",
        "--luna-text-primary", "--luna-text-secondary", "--luna-text-tertiary",
        // No `--luna-accent`: nothing on an internal page is accent-coloured.
        // Selection and focus are ink here, the same way they are material in
        // the chrome — there is no system blue anywhere in Luna.
        "--luna-line-hairline", "--luna-line-border", "--luna-danger",
        // §3.3's recess and §3.4's selected wash, and the shadow §5's popover
        // stands on. The shadow is the page's whole claim to depth: see
        // `.pane` below for why a page gets a shadow instead of a material.
        "--luna-surface-well", "--luna-surface-selected", "--luna-surface-hover",
        "--luna-shadow", "--luna-shadow-lift", "--luna-shadow-reach",
        "--luna-hairline", "--luna-gap", "--luna-gap-wide",
        "--luna-row-height", "--luna-row-radius", "--luna-row-inset", "--luna-favicon",
        "--luna-tile-w", "--luna-tile-h", "--luna-tile-radius", "--luna-tile-icon",
        "--luna-pill-h", "--luna-pill-inset", "--luna-card-radius",
        "--luna-size-row", "--luna-size-pill", "--luna-size-label",
        "--luna-size-title", "--luna-size-body",
        "--luna-motion-hover"
    ]

    /// Wraps a body in the shell.
    @MainActor
    static func document(title: String, bodyClass: String, body: String, script: String = "") -> String {
        let script = script.isEmpty ? "" : "<script>\(script)</script>"
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <title>\(HTML.escape(title))</title>
        <style>\(palette)\(stylesheet)</style>
        </head>
        <body class="\(bodyClass)">\(body)\(script)</body>
        </html>
        """
    }

    static let stylesheet = """
    *,*::before,*::after{box-sizing:border-box}
    html,body{height:100%}
    body{
      margin:0;
      background:var(--luna-surface-base,Canvas);
      color:var(--luna-text-primary,CanvasText);
      font-family:-apple-system,system-ui,sans-serif;
      font-size:var(--luna-size-row,medium);
      -webkit-font-smoothing:antialiased;
    }
    a{color:inherit;text-decoration:none}
    /* **Ink, not accent.** A focus ring still has to be unmistakable, and this
       one is — but Luna's chrome has no system blue anywhere, and an internal
       page is Luna's UI. `Highlight` is the OS's own focus colour as a
       fallback, for a page rendered before the palette lands. */
    :focus-visible{
      outline:medium solid var(--luna-text-primary,Highlight);
      outline-offset:var(--luna-hairline);
    }
    /* **The two surfaces a page gets, and why it does not get glass.**
       Luna's chrome is Liquid Glass; a page cannot be. The material composites
       what is behind the *window*, and a `WKWebView`'s layer is out of process
       — `docs/UI-SPEC.md` records a hand-built plane of scrim, frost and tint
       being tried on exactly this and the page coming through it perfectly
       sharp. A `backdrop-filter` here would blur `--luna-surface-base`, which
       is flat, so it would cost a compositing pass and change nothing.

       What does carry across is everything about the surface that is not the
       sampling: the plane, the hairline that catches its edge, the continuous
       corner, and the shadow. That is precisely what the chrome falls back to
       under Reduce Transparency — and a page is a permanent Reduce
       Transparency, because there is nothing behind it to see.

       `.pane` is a surface you look at; `.plate` is one you can press, and is
       the only one of the two that answers the pointer. The error card was a
       `.plate` and lit up under the cursor like a button. */
    .pane,.plate{
      background:var(--luna-surface-raised,Canvas);
      border:var(--luna-hairline,thin) solid var(--luna-line-border,ButtonBorder);
    }
    .plate{transition:background-color var(--luna-motion-hover,0s) ease-out}
    .plate:hover{background:var(--luna-surface-hover,Canvas)}
    /* §5's popover shadow. The one thing on a page that says "above". */
    .lifted{box-shadow:0 var(--luna-shadow-lift) var(--luna-shadow-reach) var(--luna-shadow,transparent)}
    /* §3.3's recess: darker than the plane it is cut into, in both themes,
       with the same hairline catching the edge. A pinned tile and the address
       field are this, and so is anything on a page that holds something. */
    .well{
      background:var(--luna-surface-well,Canvas);
      border:var(--luna-hairline,thin) solid var(--luna-line-border,ButtonBorder);
    }
    @media (prefers-reduced-motion: reduce){*{transition:none!important;animation:none!important}}

    /* History (§6.4) — the closed-tab shelf, laid out like the §3.4 tab list. */
    .history{
      max-width:calc(var(--luna-tile-w) * 5);
      margin-inline:auto;padding:var(--luna-gap-wide);
      display:flex;flex-direction:column;gap:var(--luna-gap-wide);
    }
    /* The rule under the header is §3.4's own: the sidebar closes its command
       group with a hairline before the tabs start, and this page has the same
       shape — a fixed head, then a list. */
    .history .head{
      display:flex;align-items:center;gap:var(--luna-gap-wide);flex-wrap:wrap;
      padding-inline:var(--luna-row-inset);
      padding-bottom:var(--luna-gap-wide);
      border-bottom:var(--luna-hairline,thin) solid var(--luna-line-hairline,ButtonBorder);
    }
    .history h1{
      flex:0 0 auto;margin:0;
      font-size:var(--luna-size-pill,large);font-weight:600;
    }
    /* Title and filter share a line: the list is the page, and a full-width
       field above it read as a form to fill in rather than as a way to narrow
       what is already there. */
    .search{
      flex:1 1 auto;min-width:0;
      height:var(--luna-pill-h);
      padding-inline:var(--luna-pill-inset);
      border-radius:calc(var(--luna-pill-h) / 2);
      background:var(--luna-surface-hover,Field);
      border:var(--luna-hairline,thin) solid var(--luna-line-border,ButtonBorder);
      color:var(--luna-text-primary,FieldText);
      font-size:var(--luna-size-row,medium);
      -webkit-appearance:none;appearance:none;
    }
    /* Pills with a gap, not lines with rules between them: §3.4's rows have no
       separators, and neither do these. */
    .rows{
      margin:0;padding:0;list-style:none;
      display:flex;flex-direction:column;gap:calc(var(--luna-hairline) * 3);
    }
    .row{
      display:flex;align-items:center;gap:var(--luna-row-inset);
      min-height:var(--luna-row-height);
      padding-inline:var(--luna-row-inset);
      border-radius:var(--luna-row-radius);
      transition:background-color var(--luna-motion-hover,0s) ease-out;
    }
    .row:hover{background:var(--luna-surface-hover,Canvas)}
    .row .text{min-width:0;flex:1 1 auto;display:flex;flex-direction:column}
    .row .title{overflow:hidden;white-space:nowrap;text-overflow:ellipsis}
    .row .sub{
      overflow:hidden;white-space:nowrap;text-overflow:ellipsis;
      color:var(--luna-text-tertiary,GrayText);font-size:var(--luna-size-label,small);
    }
    /* The trailing chip, on hover and on keyboard focus — §3.4's row does the
       same thing with its close button. It keeps its space at all times, so
       nothing reflows under the pointer. */
    .row .go{
      flex:0 0 auto;
      display:inline-flex;align-items:center;
      padding-block:calc(var(--luna-hairline) * 3);
      padding-inline:var(--luna-row-inset);
      border-radius:calc(var(--luna-row-radius) / 2);
      color:var(--luna-text-secondary,CanvasText);font-size:var(--luna-size-label,small);
      opacity:0;
      transition:opacity var(--luna-motion-hover,0s) ease-out;
    }
    .row:hover .go,.row:focus-visible .go{opacity:1}
    .empty{
      color:var(--luna-text-secondary,GrayText);
      padding:var(--luna-gap-wide);text-align:center;
      max-width:calc(var(--luna-tile-w) * 3);margin-inline:auto;
    }

    /* Favicons — sub-resources of a luna:// document, which is the only place a
       luna:// sub-resource loads at all (§4.4). Never an image element: a
       background image that fails to decode leaves the monogram underneath
       showing, where a broken one leaves §4.7's forbidden broken-image glyph. */
    .icon{
      flex:0 0 auto;
      display:flex;align-items:center;justify-content:center;
      border-radius:var(--luna-row-radius);
      background-color:var(--luna-surface-hover,Canvas);
      background-image:var(--fav,none);
      background-size:cover;background-repeat:no-repeat;
      color:var(--luna-text-secondary,CanvasText);
      font-size:var(--luna-size-label,small);
      overflow:hidden;
    }
    .icon.has-fav{color:transparent;background-color:transparent}
    .row .icon{width:var(--luna-favicon);height:var(--luna-favicon)}

    /* Errors (§4.5)
       One card, six kinds, and the kind is a class on `.error` rather than a
       second layout. It is the §3.6 content card's own corner, standing on §5's
       shadow, with §3.3's well holding the mark and §3.2's pill holding the
       address that failed — the four shapes this window already has. */
    .error{
      min-height:100%;
      display:flex;flex-direction:column;align-items:center;justify-content:center;
      padding:var(--luna-gap-wide);text-align:center;
    }
    .error .card{
      max-width:calc(var(--luna-tile-w) * 4.5);
      display:flex;flex-direction:column;align-items:center;gap:var(--luna-gap);
      padding:calc(var(--luna-gap-wide) * 2) calc(var(--luna-gap-wide) * 1.5);
      border-radius:var(--luna-card-radius);
    }
    /* The mark stands in a §3.3 tile rather than floating over the card. A
       favicon-sized glyph alone on five hundred points of plane reads as a
       bullet point on a paragraph that has lost its list; the recess is what
       makes it the subject of the page. The tile keeps its own corner ratio
       on the way up, so it is §3.3's shape and not a rounder one. */
    .error .mark{
      display:flex;align-items:center;justify-content:center;
      width:calc(var(--luna-tile-h) * 1.3);height:calc(var(--luna-tile-h) * 1.3);
      border-radius:calc(var(--luna-tile-radius) * 1.3);
      color:var(--luna-text-secondary,CanvasText);
      margin-bottom:var(--luna-gap);
    }
    .error .mark svg{
      width:calc(var(--luna-tile-icon) * 1.75);
      height:calc(var(--luna-tile-icon) * 1.75);
    }
    /* Ink for the four that report, §8.1's danger for the two that warn: the
       blocker stopped this, and the connection is not what it said it was. */
    .error.tls .mark,.error.blocked .mark,.error.httpsDowngrade .mark{
      color:var(--luna-danger,LinkText);
    }
    /* Balanced, both of them: a card this narrow strands the last word of a
       two-line sentence on a line of its own, and the eye reads that gap as a
       paragraph break in a page that has one paragraph. */
    .error h1{
      font-size:var(--luna-size-title,xx-large);font-weight:600;margin:0;
      text-wrap:balance;
    }
    .error p{
      margin:0;color:var(--luna-text-secondary,CanvasText);
      font-size:var(--luna-size-body,medium);line-height:1.45;
      text-wrap:balance;
    }
    /* The address that failed, in the shape the address bar would have shown
       it in. It is evidence, not prose, so it is not set as a sentence. */
    .error .target{
      max-width:100%;
      margin-top:var(--luna-gap);
      padding:calc(var(--luna-gap) / 2) var(--luna-pill-inset);
      border-radius:calc(var(--luna-pill-h) / 2);
      color:var(--luna-text-tertiary,GrayText);font-size:var(--luna-size-label,small);
      overflow-wrap:anywhere;
    }
    .error .note{
      color:var(--luna-text-tertiary,GrayText);font-size:var(--luna-size-label,small);
      overflow-wrap:anywhere;
    }
    .actions{display:flex;gap:var(--luna-gap);margin-top:var(--luna-gap-wide)}
    .button{
      display:inline-flex;align-items:center;
      height:var(--luna-pill-h);
      padding-inline:var(--luna-gap-wide);
      border-radius:calc(var(--luna-pill-h) / 2);
      font-size:var(--luna-size-row,medium);
    }
    /* **The one the page is recommending, and there is no blue to say so.**
       §3.4's selected wash is twice the hover, which is exactly the step that
       separates "the answer" from "the other thing you may do" without
       inventing an accent Luna does not have. It keeps that fill under the
       pointer instead of lifting to it — there is nothing above selected, and
       a key button that dimmed on hover would be reading backwards. */
    .button.key{
      background:var(--luna-surface-selected,Canvas);
      color:var(--luna-text-primary,CanvasText);
    }
    .button.key:hover{background:var(--luna-surface-selected,Canvas)}
    """
}
