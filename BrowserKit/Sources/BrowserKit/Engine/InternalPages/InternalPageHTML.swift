import Foundation

//  The shell every internal page is poured into, and the only stylesheet they
//  have.
//
//  **There is not one colour or length value in this file.** Every declaration
//  reads `var(--luna-…)`, the custom properties are generated from
//  `Design/Tokens.swift` by `Features/InternalPages/InternalPageTheme`, and the
//  only fallbacks are CSS **system** colours and CSS **keywords** (`Canvas`,
//  `CanvasText`, `GrayText`, `AccentColor`, `thin`, `medium`) — the OS's own
//  values, never a second palette that can drift from Luna's.
//  `InternalPagesTests.stylesheetCarriesNoLiterals` fails if a hex value, an
//  `rgb(`, or an absolute length ever appears here.
//
//  Light and dark (§8.8) and Increase Contrast are **not** branched in Swift:
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
        "--luna-surface-base", "--luna-surface-raised", "--luna-surface-hover",
        "--luna-text-primary", "--luna-text-secondary", "--luna-text-tertiary",
        "--luna-line-hairline", "--luna-line-border", "--luna-accent", "--luna-danger",
        "--luna-hairline", "--luna-gap", "--luna-gap-wide",
        "--luna-row-height", "--luna-row-radius", "--luna-row-inset", "--luna-favicon",
        "--luna-tile-w", "--luna-tile-h", "--luna-tile-radius", "--luna-tile-gap", "--luna-tile-icon",
        "--luna-pill-h", "--luna-pill-inset", "--luna-card-radius",
        "--luna-size-row", "--luna-size-pill", "--luna-size-label",
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
    :focus-visible{
      outline:medium solid var(--luna-accent,AccentColor);
      outline-offset:var(--luna-hairline);
    }
    .plate{
      background:var(--luna-surface-raised,Canvas);
      border:var(--luna-hairline,thin) solid var(--luna-line-border,ButtonBorder);
      transition:background-color var(--luna-motion-hover,0s) ease-out;
    }
    .plate:hover{background:var(--luna-surface-hover,Canvas)}
    @media (prefers-reduced-motion: reduce){*{transition:none!important;animation:none!important}}

    /* New Tab (§30.19) */
    .newtab{
      min-height:100%;
      display:flex;flex-direction:column;align-items:center;justify-content:center;
      gap:var(--luna-gap-wide);
      padding:var(--luna-gap-wide);
    }
    .pill{
      display:flex;align-items:center;gap:var(--luna-pill-inset);
      width:min(100%,calc(var(--luna-tile-w) * 4 + var(--luna-tile-gap) * 3));
      height:calc(var(--luna-pill-h) + var(--luna-gap) * 2);
      padding-inline:var(--luna-pill-inset);
      border-radius:calc((var(--luna-pill-h) + var(--luna-gap) * 2) / 2);
      font-size:var(--luna-size-pill,large);
      color:var(--luna-text-secondary,CanvasText);
    }
    .pill .lead{
      flex:0 0 auto;width:var(--luna-favicon);
      text-align:center;color:var(--luna-text-tertiary,GrayText);
    }
    .grid{
      display:grid;
      grid-template-columns:repeat(auto-fit,var(--luna-tile-w));
      gap:var(--luna-tile-gap);
      justify-content:center;
      width:min(100%,calc(var(--luna-tile-w) * 4 + var(--luna-tile-gap) * 3));
      margin:0;padding:0;list-style:none;
    }
    .tile{
      display:flex;align-items:center;gap:var(--luna-row-inset);
      width:var(--luna-tile-w);height:var(--luna-tile-h);
      padding-inline:var(--luna-row-inset);
      border-radius:var(--luna-tile-radius);
    }
    .tile .label{
      min-width:0;overflow:hidden;white-space:nowrap;text-overflow:ellipsis;
      font-size:var(--luna-size-label,small);
    }
    .tile.add{color:var(--luna-text-tertiary,GrayText);justify-content:center}

    /* Archive (§6.4) */
    .archive{
      max-width:calc(var(--luna-tile-w) * 5);
      margin-inline:auto;padding:var(--luna-gap-wide);
      display:flex;flex-direction:column;gap:var(--luna-gap);
    }
    .archive h1{font-size:var(--luna-size-pill,large);font-weight:600;margin:0}
    .search{
      height:var(--luna-pill-h);width:100%;
      padding-inline:var(--luna-pill-inset);
      border-radius:calc(var(--luna-pill-h) / 2);
      background:var(--luna-surface-raised,Field);
      border:var(--luna-hairline,thin) solid var(--luna-line-border,ButtonBorder);
      color:var(--luna-text-primary,FieldText);
      font-size:var(--luna-size-row,medium);
      -webkit-appearance:none;appearance:none;
    }
    .rows{margin:0;padding:0;list-style:none;display:flex;flex-direction:column}
    .rows li+li{border-top:var(--luna-hairline,thin) solid var(--luna-line-hairline,ButtonBorder)}
    .rows li[hidden]+li{border-top:0}
    .row{
      display:flex;align-items:center;gap:var(--luna-row-inset);
      min-height:var(--luna-row-height);
      padding-inline:var(--luna-row-inset);
      border-radius:var(--luna-row-radius);
      transition:background-color var(--luna-motion-hover,0s) ease-out;
    }
    .row:hover{background:var(--luna-surface-hover,Canvas)}
    .row .text{min-width:0;display:flex;flex-direction:column}
    .row .title{overflow:hidden;white-space:nowrap;text-overflow:ellipsis}
    .row .sub{
      overflow:hidden;white-space:nowrap;text-overflow:ellipsis;
      color:var(--luna-text-tertiary,GrayText);font-size:var(--luna-size-label,small);
    }
    .row .go{
      margin-inline-start:auto;flex:0 0 auto;
      color:var(--luna-text-secondary,CanvasText);font-size:var(--luna-size-label,small);
    }
    .empty{color:var(--luna-text-secondary,GrayText);padding:var(--luna-gap-wide);text-align:center}

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
    .tile .icon{width:var(--luna-tile-icon);height:var(--luna-tile-icon)}

    /* Errors (§4.5) */
    .error{
      min-height:100%;
      display:flex;flex-direction:column;align-items:center;justify-content:center;
      padding:var(--luna-gap-wide);text-align:center;
    }
    .error .card{
      max-width:calc(var(--luna-tile-w) * 4);
      display:flex;flex-direction:column;align-items:center;gap:var(--luna-gap);
      padding:var(--luna-gap-wide);
      border-radius:var(--luna-card-radius);
    }
    .error h1{font-size:var(--luna-size-pill,large);font-weight:600;margin:0}
    .error p{margin:0;color:var(--luna-text-secondary,CanvasText)}
    .error .target{
      color:var(--luna-text-tertiary,GrayText);font-size:var(--luna-size-label,small);
      overflow-wrap:anywhere;
    }
    .error .mark{
      width:var(--luna-tile-icon);height:var(--luna-tile-icon);
      color:var(--luna-text-tertiary,GrayText);
    }
    .error.blocked .mark,.error.tls .mark{color:var(--luna-danger,LinkText)}
    .actions{display:flex;gap:var(--luna-gap);margin-top:var(--luna-gap)}
    .button{
      display:inline-flex;align-items:center;
      height:var(--luna-pill-h);
      padding-inline:var(--luna-gap-wide);
      border-radius:calc(var(--luna-pill-h) / 2);
      font-size:var(--luna-size-row,medium);
    }
    """
}
