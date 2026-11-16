//
//  InspectorStyle+Panels.swift
//  Luna
//
//  The second half of the inspector's stylesheet: the panels inside the tabs —
//  Styles, the box model, the console, tables, scope bars and Elements'
//  standing search field.
//

import Foundation

extension InspectorStyle {

    /// The console's warnings and errors keep their amber and red, as tints
    /// rather than WebKit's opaque bands, so the glass still reads behind them.
    enum Notice {
        static let warning = (fill: "hsla(43, 95%, 50%, 0.08)", edge: "hsla(43, 95%, 45%, 0.18)")
        static let error = (fill: "hsla(0, 85%, 55%, 0.07)", edge: "hsla(0, 85%, 50%, 0.16)")
    }

    static let panels = """
    .data-grid tr.selected { background-color: var(--luna-selected) !important; }

    /* Styles: rules without the card. The selector in the tag's rose, its
       origin quiet on the right, no braces, warm names over plain values. */
    .spreadsheet-css-declaration {
      padding-bottom: 10px !important; color: var(--luna-text-3);
      background: transparent !important; border-bottom: 1px solid var(--luna-line-soft) !important;
    }
    .spreadsheet-css-declaration.locked { background: transparent !important; }
    .spreadsheet-css-declaration :is(.header, .header-groupings):first-child { padding-top: 10px !important; }
    .spreadsheet-css-declaration .selector > .icon { display: none; }
    .spreadsheet-css-declaration .selector > .icon + * { padding-inline-start: 0; }
    .spreadsheet-css-declaration .selector > .matched { color: var(--luna-tag); font-weight: 600; }
    .spreadsheet-css-declaration .selector.style-attribute {
      font: 600 12px -apple-system, system-ui, sans-serif !important; color: var(--luna-text) !important;
    }
    .spreadsheet-css-declaration :is(.open-brace, .close-brace) { display: none; }
    .spreadsheet-css-declaration .origin, .spreadsheet-css-declaration .origin .go-to-link {
      font: 11px -apple-system, system-ui, sans-serif; text-decoration: none; color: var(--luna-text-3) !important;
    }
    .spreadsheet-css-declaration .origin .go-to-link:hover { text-decoration: underline; color: var(--luna-text-2) !important; }
    .spreadsheet-style-declaration-editor .property { line-height: 18px; }
    body:not(.meta-key-pressed) .spreadsheet-style-declaration-editor
      > .property:not(.disabled, .invalid-name, .invalid-value, .other-vendor, .overridden) > .content .name:not(.editing) {
      color: var(--luna-name) !important;
    }
    body:not(.meta-key-pressed) .spreadsheet-style-declaration-editor
      > .property:not(.disabled, .invalid-name, .invalid-value, .other-vendor, .overridden) > .content .value:not(.editing) {
      color: var(--luna-text) !important;
    }
    .spreadsheet-style-declaration-editor .property :is(.colon, .semicolon) { color: var(--luna-text-3); }
    .spreadsheet-css-declaration.locked .origin::after, .spreadsheet-css-declaration .locked-icon { opacity: 0.45; }
    .panel.details.css-style > .content > .inherited, .panel.details.css-style .section-header, .style-rules .inherited {
      font-size: 11px; color: var(--luna-text-3); background: transparent !important;
    }
    .details-section { border-color: var(--luna-line-soft) !important; }
    .details-section > .header {
      font-size: 12px; font-weight: 600; color: var(--luna-text);
      background: transparent !important; border: none !important;
    }

    /* The Styles footer: a field, and two word toggles on washes. */
    .panel.details.css-style .options-container {
      gap: 6px; padding-inline: 8px;
      background: transparent !important; border-top: 1px solid var(--luna-line-soft) !important;
    }
    .options-container > .new-rule { opacity: 0.6; }
    .sidebar > .panel.details.css-style > .content ~ .options-container > .toggle {
      padding: 3px 8px !important; font-size: 11.5px; color: var(--luna-text-2) !important;
    }
    .sidebar > .panel.details.css-style > .content ~ .options-container > .toggle::before { border-radius: 7px !important; }
    .sidebar > .panel.details.css-style > .content ~ .options-container > .toggle:is(.selected, :hover) {
      color: var(--luna-text) !important;
    }
    .sidebar > .panel.details.css-style > .content ~ .options-container > .toggle.selected::before {
      background-color: var(--luna-selected) !important; opacity: 1 !important;
    }
    .sidebar > .panel.details.css-style > .content ~ .options-container > .toggle:not(.selected):hover::before {
      background-color: var(--luna-hover) !important; opacity: 1 !important;
    }
    .class-list-container, .forced-pseudo-class-container {
      background: transparent !important; border-color: var(--luna-line-soft) !important;
    }

    /* The box model: the four colours the page's highlight uses, as nested
       rounded plates on soft lines. */
    .details-section .row.box-model .box {
      border: 1px solid var(--luna-line) !important; border-radius: 10px; background-color: transparent;
    }
    .details-section .row.box-model .box.position { border-color: var(--luna-line-soft) !important; border-radius: 12px; }
    .details-section .row.box-model .box.border { border-radius: 8px; }
    .details-section .row.box-model .box.padding { border-radius: 7px; }
    .details-section .row.box-model .box.content { border-radius: 6px; }

    /* Scope bars (All, Errors, By Type…): words, the chosen one on the
       selected wash rather than a solid plate. */
    .scope-bar > li {
      padding: 5px 9px !important; font-size: 11.5px; line-height: 12px;
      --scope-bar-border-color-default: transparent;
    }
    .scope-bar > li::after {
      width: 100% !important; height: 100% !important; border: none !important; border-radius: 7px !important;
    }
    .scope-bar > li:is(.selected, :hover) {
      --scope-bar-text-color-default: var(--luna-text);
      --scope-bar-background-color-default: var(--luna-selected);
      --scope-bar-border-color-default: transparent;
      --scope-bar-background-opacity-default: 1;
    }
    .scope-bar > li:not(.selected):hover { --scope-bar-background-color-default: var(--luna-hover); }
    .scope-bar > li.selected { font-weight: 600; }

    /* Tables: the faintest stripe, no column plates, a soft header. */
    .table .data-list .cell { background-color: transparent !important; }
    .table > .header { border-color: var(--luna-line-soft) !important; }
    .table > .header > :is(.sort-ascending, .sort-descending) { background-color: var(--luna-hover) !important; }
    .table .data-list > li.selected { background-color: var(--luna-selected) !important; }

    /* The console: messages on soft rules, the prompt on the chrome. */
    .console-messages :is(.console-message, .console-user-command) { border-color: var(--luna-line-soft) !important; }
    .console-messages .console-session-divider, .console-session > .console-session-header { color: var(--luna-text-3); }
    .quick-console { background: transparent !important; border-top: 1px solid var(--luna-line-soft) !important; }
    .console-message.console-warning-level {
      background-color: \(Notice.warning.fill) !important; border-color: \(Notice.warning.edge) !important;
    }
    .console-message.console-error-level {
      background-color: \(Notice.error.fill) !important; border-color: \(Notice.error.edge) !important;
    }
    .navigation-bar > .item.find-banner.console > input[type="search"] { border: none !important; border-radius: 8px !important; }
    .navigation-bar > .item.find-banner.console > button {
      border: none !important; border-radius: 7px !important; background: transparent !important;
    }
    .navigation-bar > .item.find-banner.console > button:not(:disabled):hover { background: var(--luna-hover) !important; }

    /* Elements' standing search field, full width under the tab bar
       (`InspectorStyle.script`). */
    .find-banner.luna-pinned {
      display: flex; align-items: center; gap: 4px; height: 40px !important; padding: 0 8px; text-align: left;
      border: none !important; background: transparent !important;
    }
    .find-banner.luna-pinned + .supports-find-banner.showing-find-banner { top: 40px !important; }
    .find-banner.luna-pinned > input[type="search"] {
      order: 0; flex: 1; width: auto !important; max-width: none !important; height: 28px !important;
      margin: 0 !important; padding-inline: 10px !important; border-radius: 9px !important; font-size: 12px;
    }
    .find-banner.luna-pinned > label { order: 1; margin-inline: 6px 2px; font-size: 11px; color: var(--luna-text-3); }
    .find-banner.luna-pinned > button.segmented {
      order: 2; min-width: 26px; height: 26px !important; margin: 0 !important;
      border: none !important; border-radius: 7px !important;
    }
    .find-banner.luna-pinned > button.segmented:not(:disabled):hover { background: var(--luna-hover) !important; }
    .find-banner.luna-pinned > button:not(.segmented) { display: none; }
    .find-banner > button.segmented > .glyph { filter: none !important; opacity: 0.6; }
    @media (prefers-color-scheme: dark) {
      .find-banner > button.segmented > .glyph { filter: invert() !important; }
    }

    /* Scrollbars: thin thumbs on nothing. */
    ::-webkit-scrollbar { width: 10px; height: 10px; background: transparent; }
    ::-webkit-scrollbar-thumb {
      border: 3px solid transparent; border-radius: 5px;
      background-color: var(--luna-thumb); background-clip: content-box;
    }
    ::-webkit-scrollbar-corner { background: transparent; }
    .reference-page-link { opacity: 0.5; }
    """
}
