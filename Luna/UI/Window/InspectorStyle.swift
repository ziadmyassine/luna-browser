//
//  InspectorStyle.swift
//  Luna
//
//  The stylesheet Luna lays over WebKit's docked Web Inspector, so it reads as
//  part of the chrome it is docked into rather than a second app inside it.
//
//  The inspector is WebKit's own page, built from CSS variables, and this only
//  restyles it: every panel and feature is WebKit's. Its planes go clear —
//  the card stops painting behind a docked inspector, so the window's own
//  glass, the sidebar's or the top bar's, is what shows (`ContentCardView`) —
//  and its lines, washes and selections take the chrome's ink: black on light,
//  white on dark, at the alphas `Tokens.Ink` gives them. Tabs, rows, fields
//  and choices become rounded washes, as the sidebar's rows are. No system
//  blue, for §2's rule.
//
//  Split in three for length: the chrome here, the panels in `+Panels`, and
//  the one behaviour it adds, Elements' standing search field, in `+Script`.
//
//  Selectors are WebKit's and can change under it; a rule that stops matching
//  leaves that part of the inspector as WebKit drew it, never broken.
//

import AppKit

enum InspectorStyle {

    /// The stylesheet, both appearances: the inspector follows its web view's
    /// appearance, which is the window's, through `prefers-color-scheme`.
    static var css: String { chrome + panels }

    /// The alphas the stylesheet's ink is drawn at, from Luna's own washes,
    /// lines and text so the inspector and the chrome round it agree.
    enum Ink {
        static let hover = Tokens.Ink.hover.light
        static let selected = Tokens.Ink.selected.light
        /// A field sits between the two: filled enough to read as a place to
        /// type, lighter than a selection.
        static let field = (Tokens.Ink.hover.light + Tokens.Ink.selected.light) / 2
        static let line = 0.10
        static let lineSoft = 0.06
        /// Half a hover: a table's alternate rows are there to guide the eye
        /// along a line, and a full wash on every other row read as stripes.
        static let stripe = Tokens.Ink.hover.light / 2
        /// `Text.primary` is the label colour, which is this ink in both
        /// appearances.
        static let text = 0.85
        static let secondary = Tokens.Ink.secondary
        static let tertiary = Tokens.Ink.tertiary
        /// Scrollbar thumbs and the inspector's own quaternary rules: the
        /// chrome's decorative border.
        static let thumb = Tokens.Ink.border
    }

    /// The code palette: tags and selectors rose, attribute and property names
    /// warm, values blue. One step quieter than WebKit's own, which is tuned
    /// for an opaque white or near-black plane. Measured over the glass's
    /// light (95.5 % and 92 % white) and dark (17 % and 24 % white) planes,
    /// every colour holds 4.5:1 or better: 4.58 for the light names at worst,
    /// 5.31 for the dark tags.
    enum Syntax {
        static let tag = (light: "hsl(336, 50%, 45%)", dark: "hsl(336, 75%, 78%)")
        static let name = (light: "hsl(26, 58%, 38%)", dark: "hsl(30, 70%, 74%)")
        static let value = (light: "hsl(219, 60%, 46%)", dark: "hsl(212, 85%, 77%)")
        static let number = (light: "hsl(258, 45%, 52%)", dark: "hsl(262, 80%, 82%)")
    }

    /// The plate WebKit's pop-overs draw for themselves (the device settings,
    /// a breakpoint's options), over the inspector's own content. Left clear
    /// with the rest of its planes, their rows ran into the tree beneath.
    /// `raised` is what Luna's own popovers stand on without glass.
    static let popover = (light: css(Tokens.Surface.raised, in: .aqua), dark: css(Tokens.Surface.raised, in: .darkAqua))

    static let hoverFade = "\(Int(Tokens.Motion.controlHover.duration * 1000))ms"
    static let pressFade = "\(Int(Tokens.Motion.controlPress.duration * 1000))ms"

    /// `color` as CSS, as it resolves in the appearance `name`.
    private static func css(_ color: NSColor, in name: NSAppearance.Name) -> String {
        var resolved = color
        NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB) ?? color
        }
        let channels = [resolved.redComponent, resolved.greenComponent, resolved.blueComponent]
        return "rgb(" + channels.map { String(Int(($0 * 255).rounded())) }.joined(separator: ", ") + ")"
    }
}

extension InspectorStyle {

    /// Variables, type, the tab bar, bars, fields and the DOM tree.
    static let chrome = """
    :root:root {
      --luna-ink: 0, 0, 0;
      --luna-hover: rgba(var(--luna-ink), \(Ink.hover));
      --luna-selected: rgba(var(--luna-ink), \(Ink.selected));
      --luna-field: rgba(var(--luna-ink), \(Ink.field));
      --luna-line: rgba(var(--luna-ink), \(Ink.line));
      --luna-line-soft: rgba(var(--luna-ink), \(Ink.lineSoft));
      --luna-stripe: rgba(var(--luna-ink), \(Ink.stripe));
      --luna-thumb: rgba(var(--luna-ink), \(Ink.thumb.light));
      --luna-text: rgba(var(--luna-ink), \(Ink.text));
      --luna-text-2: rgba(var(--luna-ink), \(Ink.secondary.light));
      --luna-text-3: rgba(var(--luna-ink), \(Ink.tertiary.light));
      --luna-code: ui-monospace, "SF Mono", Menlo, monospace;
      --luna-tag: \(Syntax.tag.light);
      --luna-name: \(Syntax.name.light);
      --luna-value: \(Syntax.value.light);
      --luna-number: \(Syntax.number.light);
      --luna-popover: \(popover.light);
    }
    @media (prefers-color-scheme: dark) {
      :root:root {
        --luna-ink: 255, 255, 255;
        --luna-thumb: rgba(var(--luna-ink), \(Ink.thumb.dark));
        --luna-text-2: rgba(var(--luna-ink), \(Ink.secondary.dark));
        --luna-text-3: rgba(var(--luna-ink), \(Ink.tertiary.dark));
        --luna-tag: \(Syntax.tag.dark);
        --luna-name: \(Syntax.name.dark);
        --luna-value: \(Syntax.value.dark);
        --luna-number: \(Syntax.number.dark);
        --luna-popover: \(popover.dark);
      }
    }

    :root:root, body:is(.mac-platform, .window-inactive, .window-docked-inactive) {
      --text-color: var(--luna-text);
      --text-color-active: var(--luna-text);
      --text-color-secondary: var(--luna-text-2);
      --text-color-tertiary: var(--luna-text-3);
      --text-color-quaternary: var(--luna-thumb);
      --text-color-gray-medium: var(--luna-text-2);
      --text-color-gray-dark: var(--luna-text);
      --console-secondary-text-color: var(--luna-text-3);
      --background-color: transparent;
      --background-color-content: transparent;
      --background-color-intermediate: transparent;
      --background-color-secondary: transparent;
      --background-color-tertiary: var(--luna-hover);
      --background-color-unfocused: transparent;
      --background-color-alternate: var(--luna-hover);
      --background-color-selected: var(--luna-selected);
      --panel-background-color: transparent;
      --panel-background-color-light: transparent;
      --popover-background-color: var(--luna-popover);
      --popover-border-color: var(--luna-line);
      --even-zebra-stripe-row-background-color: transparent;
      --odd-zebra-stripe-row-background-color: var(--luna-stripe);
      --border-color: var(--luna-line);
      --border-color-secondary: var(--luna-line-soft);
      --separator-color: var(--luna-line-soft);
      --selected-background-color: var(--luna-selected);
      --selected-background-color-unfocused: var(--luna-hover);
      --selected-background-color-hover: var(--luna-hover);
      --selected-background-color-active: var(--luna-selected);
      --selected-text-background-color: var(--luna-selected);
      --selected-foreground-color: var(--luna-text);
      --selected-secondary-text-color: var(--luna-text-2);
      --glyph-color: var(--luna-text-2);
      --glyph-color-pressed: var(--luna-text);
      --glyph-color-active: var(--luna-text);
      --glyph-color-active-pressed: var(--luna-text);
      --button-background-color: var(--luna-field);
      --button-background-color-hover: var(--luna-selected);
      --button-background-color-pressed: var(--luna-selected);
      --link-text-color: var(--luna-text-2);
      --tab-bar-background: transparent;
      --tab-item-background: transparent;
      --tab-item-light-border-color: transparent;
      --tab-item-medium-border-color: transparent;
      --tab-item-dark-border-color: transparent;
      --tab-item-border-color: transparent;
      --tab-bar-height: 40px;
      --syntax-highlight-boolean-color: var(--luna-tag);
      --syntax-highlight-string-color: var(--luna-value);
      --syntax-highlight-number-color: var(--luna-number);
      --syntax-highlight-link-color: var(--luna-value);
      --syntax-highlight-comment-color: var(--luna-text-3);
    }

    html, body, body.window-inactive, .content-view, .sidebar, .panel, .details-section,
    .CodeMirror, .CodeMirror-gutters, .console-messages, .console-prompt, .tab-bar, #main {
      background-color: transparent !important;
    }
    body { font-family: -apple-system, system-ui, sans-serif; }
    /* Docked at a side, WebKit rules a straight line down the edge the page
       meets. The page carries its own edge there, round its corners, as the
       card does beside the sidebar, and the line stood apart from it. */
    body.docked:is(.left, .right) { border: none !important; }
    @media (prefers-reduced-motion: reduce) {
      * { transition: none !important; }
    }

    /* Code in the system's monospace, a size up. */
    .tree-outline.dom, .spreadsheet-css-declaration:not(.style-attribute), .CodeMirror,
    .console-messages, .console-message-text, .console-prompt, .object-tree,
    .formatted-node-preview, .computed-style-section .computed-property-item {
      font-family: var(--luna-code) !important;
    }
    .tree-outline.dom, .spreadsheet-css-declaration, .console-messages { font-size: 11.5px !important; }

    .syntax-highlighted .html-attribute-name, .cm-s-default .cm-m-xml.cm-attribute {
      color: var(--luna-name) !important;
    }
    .syntax-highlighted :is(.html-comment, .css-comment, .javascript-comment), .cm-s-default .cm-comment {
      color: var(--luna-text-3) !important;
      font-style: italic;
    }
    .syntax-highlighted .html-doctype { color: var(--luna-text-3) !important; }
    .tree-outline.dom li .html-text-node { color: var(--luna-text); }

    /* The tab bar: one row, no rules, no frames. The controls are lifted out of
       their groups so they can sit at either end: picking and device settings
       lead, docking and closing trail. */
    .tab-bar { align-items: center; padding: 0 8px; gap: 2px; }
    .tab-bar > .border { display: none !important; }
    .tab-bar > .navigation-bar, .tab-bar > .navigation-bar > .item.group { display: contents !important; }
    .tab-bar > .navigation-bar .item { margin: 0 !important; }
    .tab-bar > .navigation-bar .item.button {
      display: flex; align-items: center; justify-content: center;
      width: 28px !important; height: 28px !important; min-width: 0; padding: 0 !important;
      border-radius: 8px;
    }
    .tab-bar > .navigation-bar .item.button:hover { background-color: var(--luna-hover); }
    .tab-bar > .navigation-bar .item.button:is(:active, .activated) { background-color: var(--luna-selected); }
    .tab-bar > .navigation-bar .item.button > .glyph { color: var(--luna-text-2); transform: scale(0.88); }
    .tab-bar > .navigation-bar .item.divider { display: none; }
    .tab-bar .item:is(.inspect, .device-settings) { order: 1; }
    .tab-bar .item:is(.console-warnings, .console-errors) { order: 2; }
    .tab-bar > .tabs { order: 3; }
    .tab-bar .item:is(.dock-left, .dock-bottom, .dock-right) { order: 5; }
    .tab-bar .item.undock { order: 6; }
    .tab-bar .item.dock-close { order: 7; }

    /* No gap or padding between the tabs: WebKit measures them one by one to
       decide which fold into its overflow menu, and space between them is
       space it does not count. */
    .tab-bar > .tabs {
      flex: 1; min-width: 0; height: 100%; align-items: center;
      flex-wrap: nowrap !important; overflow: hidden;
      border: none !important; background: transparent !important;
    }
    .tab-bar > .tabs > .item {
      flex: 0 0 auto !important; height: 28px !important; margin-block: auto; padding: 0 10px !important;
      border: none !important; border-radius: 8px; background: transparent !important;
    }
    .tab-bar > .tabs > .item > .flex-space { display: none; }
    .tab-bar > .tabs > .item > .icon { width: 14px; height: 14px; opacity: 0.6; }
    .tab-bar > .tabs > .item > .name {
      margin-inline-start: 6px; font-size: 12px; color: var(--luna-text-2) !important;
    }
    .tab-bar > .tabs > .item:not(.selected, .disabled):hover { background-color: var(--luna-hover) !important; }
    .tab-bar > .tabs > .item:not(.disabled).selected { background-color: var(--luna-selected) !important; }
    .tab-bar > .tabs > .item:not(.disabled).selected > .name { color: var(--luna-text) !important; font-weight: 600; }
    .tab-bar > .tabs > .item:not(.disabled).selected > .icon { opacity: 0.9; }
    .tab-bar > .tabs > .item.pinned { width: 28px !important; padding: 0 !important; justify-content: center; }
    .tab-bar > .tabs > .item.pinned:not(.hidden):is([title^="Search"]) { margin-inline-start: auto; }
    #main { border-top: 1px solid var(--luna-line-soft); }

    /* Every control answers the pointer with a wash, and a press with the
       swell every button of Luna's gives (§6). */
    .tab-bar > .tabs > .item, .tab-bar > .navigation-bar .item.button, .scope-bar > li,
    .navigation-bar .item.radio.button.text-only, .find-banner.luna-pinned > button.segmented {
      transition: background-color \(hoverFade), transform \(pressFade);
    }
    .tab-bar > .tabs > .item:active, .tab-bar > .navigation-bar .item.button:active, .scope-bar > li:active,
    .navigation-bar .item.radio.button.text-only:active, .find-banner.luna-pinned > button.segmented:active {
      transform: scale(\(Tokens.Motion.pressSwell));
    }

    /* Elements: the path and its tools move under the tree, as a quiet footer. */
    .content-view.tab.elements > .content-browser > .navigation-bar {
      order: 2; height: 30px; padding-inline: 6px;
      border-top: 1px solid var(--luna-line-soft); border-bottom: none !important;
    }
    .content-view.tab.elements .hierarchical-path-component > .icon { display: none; }
    .hierarchical-path-component { color: var(--luna-text-2); }
    .hierarchical-path-component > .title > .content { font-size: 11.5px; }
    .hierarchical-path:not(.always-show-last-path-component-separator) > .hierarchical-path-component:last-child {
      color: var(--luna-text);
      font-weight: 600;
    }
    .hierarchical-path-component > .separator { opacity: 0.35; }

    .navigation-bar { border-color: var(--luna-line-soft) !important; }
    .sidebar .navigation-bar { padding-inline: 6px; }
    .navigation-bar .item.button > .glyph { color: var(--luna-text-2); }
    .navigation-bar .item.button:hover { background-color: var(--luna-hover); border-radius: 6px; }
    .navigation-bar .item.button:is(.activated, .selected) > .glyph { color: var(--luna-text); }
    .navigation-bar .item.divider { background-color: var(--luna-line-soft) !important; }
    .sidebar { border-color: var(--luna-line-soft) !important; }
    .navigation-bar .item.text-only.button:not(.radio) {
      border: none !important; border-radius: 6px;
      background: var(--luna-hover) !important; color: var(--luna-text-2);
    }

    /* Segmented choices (Styles, Computed, Layout…): words, the chosen one on
       the selected wash. */
    .navigation-bar .item.radio.button.text-only {
      font-size: 12px; white-space: nowrap; color: var(--luna-text-2) !important;
    }
    .sidebar > .navigation-bar { flex-wrap: nowrap; overflow: hidden; }
    .navigation-bar .item.radio.button.text-only:is(.selected, :hover) { color: var(--luna-text) !important; }
    .navigation-bar .item.radio.button.text-only.selected { font-weight: 600; }
    .navigation-bar .item.radio.button.text-only:is(.selected, :hover)::before {
      background-color: var(--luna-selected) !important; opacity: 1 !important; border-radius: 7px;
    }
    .navigation-bar .item.radio.button.text-only:not(.selected):hover::before {
      background-color: var(--luna-hover) !important;
    }

    /* Fields: filled and round, no bezel. */
    input[type="search"], input[type="text"].search, .search-bar > input, .filter-bar > input[type="search"],
    .find-banner > input[type="search"] {
      appearance: none; min-height: 24px; padding-inline: 8px; outline: none;
      border: none !important; border-radius: 8px;
      background-color: var(--luna-field) !important; color: var(--luna-text);
    }
    input[type="search"]::placeholder { color: var(--luna-text-3); }
    input[type="search"]:focus, .search-bar > input:focus { box-shadow: 0 0 0 1px var(--luna-line) inset !important; }
    .filter-bar { background: transparent !important; border-color: var(--luna-line-soft) !important; }
    .filter-bar > .navigation-bar { border: none !important; }

    /* The DOM tree: the selection and the hover are rounded washes, inset. */
    .tree-outline .item.selected .selection-area, .tree-outline.dom li.selected .selection-area {
      margin-inline: 4px; border-radius: 6px; background-color: var(--luna-selected) !important;
    }
    .tree-outline.dom li.hovered:not(.selected) .selection-area {
      margin-inline: 4px; border-radius: 6px; background-color: var(--luna-hover) !important;
    }
    .tree-outline .item.selected, .tree-outline:focus .item.selected * { color: var(--text-color) !important; }
    .tree-outline.dom li.selected > span::after { color: var(--luna-text-3) !important; }
    .tree-outline.dom li .badge {
      border: none !important; border-radius: 5px;
      background: var(--luna-hover) !important; color: var(--luna-text-2) !important;
    }
    .tree-outline li .disclosure-button, .tree-outline.dom li::before { opacity: 0.5; }
    """
}
