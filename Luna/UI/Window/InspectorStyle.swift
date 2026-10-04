//
//  InspectorStyle.swift
//  Luna
//
//  The stylesheet Luna lays over WebKit's docked Web Inspector, so it reads as
//  the chrome carried on into the card rather than a second app inside it.
//
//  The inspector is WebKit's own page, built from CSS variables, and this only
//  restyles it: every panel and feature is WebKit's. Its planes go clear —
//  the card stops painting behind a docked inspector, so the window's own
//  glass, the sidebar's or the top bar's, is what shows (`ContentCardView`) —
//  and its lines, washes and selections take the chrome's ink: black on light,
//  white on dark, at the alphas `Tokens.Surface` and `Tokens.Line` use. Its
//  tabs become pills, as the sidebar's rows are. No system blue, for §2's rule.
//
//  Selectors are WebKit's and can change under it; a rule that stops matching
//  leaves that part of the inspector as WebKit drew it, never broken.
//

import Foundation

enum InspectorStyle {

    /// The stylesheet, both appearances: the inspector follows its web view's
    /// appearance, which is the window's, through `prefers-color-scheme`.
    static let css = """
    :root:root {
      --luna-ink: 0, 0, 0;
      --luna-hover: rgba(var(--luna-ink), \(Ink.hover));
      --luna-selected: rgba(var(--luna-ink), \(Ink.selected));
      --luna-field: rgba(var(--luna-ink), \(Ink.field));
      --luna-line: rgba(var(--luna-ink), \(Ink.line));
      --luna-line-soft: rgba(var(--luna-ink), \(Ink.lineSoft));
    }
    @media (prefers-color-scheme: dark) {
      :root:root { --luna-ink: 255, 255, 255; }
    }

    :root:root, body:is(.mac-platform, .window-inactive) {
      --background-color: transparent;
      --background-color-content: transparent;
      --background-color-intermediate: var(--luna-hover);
      --background-color-secondary: transparent;
      --background-color-unfocused: transparent;
      --background-color-alternate: var(--luna-hover);
      --background-color-selected: var(--luna-selected);
      --panel-background-color: transparent;
      --panel-background-color-light: transparent;
      --even-zebra-stripe-row-background-color: transparent;
      --odd-zebra-stripe-row-background-color: var(--luna-hover);
      --border-color: var(--luna-line);
      --border-color-secondary: var(--luna-line-soft);
      --separator-color: var(--luna-line-soft);
      --selected-background-color: var(--luna-selected);
      --selected-background-color-unfocused: var(--luna-hover);
      --selected-background-color-hover: var(--luna-hover);
      --selected-foreground-color: var(--text-color);
      --selected-secondary-text-color: var(--text-color-secondary);
      --glyph-color-active: var(--text-color);
      --button-background-color: var(--luna-field);
      --button-background-color-hover: var(--luna-selected);
      --tab-bar-background: transparent;
      --tab-item-background: transparent;
      --tab-item-light-border-color: transparent;
      --tab-item-medium-border-color: transparent;
      --tab-item-dark-border-color: transparent;
    }

    html, body, body.window-inactive, .content-view, .sidebar, .panel, .details-section,
    .CodeMirror, .CodeMirror-gutters, .console-messages, .console-prompt, .tab-bar {
      background-color: transparent !important;
    }
    body { font-family: -apple-system, system-ui, sans-serif; }

    /* The tab bar: no rules between tabs, tabs as pills sized to their names. */
    .tab-bar > .border { display: none; }
    .tab-bar > .tabs { align-items: center; gap: 2px; padding: 0 6px; }
    .tab-bar > .tabs > .item {
      border: none !important;
      border-radius: 7px;
      height: 26px !important;
      margin-block: auto;
      padding: 0 10px;
      flex-grow: 0 !important;
      background: transparent !important;
      transition: background-color 120ms;
    }
    .tab-bar > .tabs > .item:not(.selected, .disabled):hover { background-color: var(--luna-hover) !important; }
    .tab-bar > .tabs > .item:not(.disabled).selected { background-color: var(--luna-selected) !important; }
    .tab-bar > .tabs > .item:not(.disabled).selected > .name { color: var(--text-color); font-weight: 600; }
    .tab-bar > .tabs > .item > .icon { opacity: 0.75; }
    .tab-bar > .navigation-bar .item.divider { background-color: var(--luna-line-soft); }

    /* Bars: one soft rule under each, no frames. */
    .navigation-bar, .filter-bar, .sidebar > .navigation-bar { border-color: var(--luna-line-soft) !important; }
    .sidebar { border-color: var(--luna-line-soft) !important; }

    /* Search and filter fields: filled and round, no bezel. */
    input[type="search"], input[type="text"].search, .search-bar > input, .filter-bar > input[type="search"] {
      appearance: none;
      border: none !important;
      border-radius: 7px;
      background-color: var(--luna-field) !important;
      padding-inline: 8px;
      min-height: 22px;
      outline: none;
    }
    input[type="search"]:focus, .search-bar > input:focus {
      box-shadow: 0 0 0 1px var(--luna-line) inset !important;
    }

    /* Selected rows: the chrome's selected wash, round at the ends. */
    .tree-outline .item.selected .selection-area, .tree-outline:focus-within .item.selected .selection-area,
    .data-grid tr.selected, .data-grid:focus tr.selected {
      background-color: var(--luna-selected) !important;
      border-radius: 5px;
    }
    .tree-outline .item.selected, .tree-outline:focus .item.selected * { color: var(--text-color) !important; }

    /* Buttons in the bars: washes, not bezels. The scope bars' chosen word
       (Styles, Computed, Layout…) wears the selected wash, not a dark pill. */
    .navigation-bar .item.button:hover { background-color: var(--luna-hover); border-radius: 6px; }
    .navigation-bar .item.radio.button.text-only:is(.selected, :hover) { color: var(--text-color) !important; }
    .navigation-bar .item.radio.button.text-only:is(.selected, :hover)::before {
      background-color: var(--luna-selected) !important;
      opacity: 1 !important;
      border-radius: 7px;
    }
    .navigation-bar .item.radio.button.text-only:not(.selected):hover::before { background-color: var(--luna-hover) !important; }
    """

    /// The alphas the stylesheet's ink is drawn at, from Luna's own washes and
    /// lines so the inspector and the chrome round it agree.
    private enum Ink {
        static let hover = Tokens.Ink.hover.light
        static let selected = Tokens.Ink.selected.light
        /// A field sits between the two: filled enough to read as a place to
        /// type, lighter than a selection.
        static let field = (Tokens.Ink.hover.light + Tokens.Ink.selected.light) / 2
        static let line = 0.10
        static let lineSoft = 0.06
    }
}
