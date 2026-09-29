# Reading surface — Markdown reader and editor (18.9), shared with Reader (18.3)

Build plan. Design mockup: https://claude.ai/artifact/YTX4rZLZFc9PPKWMDhwf3V
(boards "Reading pop-out (Aa)", "Site settings", "Dark", "Source", "Edit", "Sepia").

## Owner decisions (2026-09-29)

1. Engine: the one that holds up longest and covers the most — `swift-markdown`
   (Apple's Swift wrapper over GitHub's cmark-gfm). Same parser GitHub renders
   READMEs with, so a document looks the way its author saw it: tables, task
   lists, strikethrough, autolinks, fenced code with a language. Foundation's
   `AttributedString(markdown:)` was rejected: no task lists, no footnotes, and
   it drops raw structure we need. New SwiftPM dependency in `BrowserKit`
   (Foundation only, no AppKit).
2. Preferences are global and sync over iCloud.
3. Save: ⌘S saves while editing, whatever the sidebar toggle is bound to (it is
   user-rebindable). Autosave after a pause as well. No unsaved-changes prompt.
4. Undo and redo ALWAYS work in the editor with ⌘Z / ⇧⌘Z (and the Edit menu),
   survive autosave, ⌘S and switching views, and win over Luna's window-level
   ⌘Z (restore hidden element / closed tab) while the editor has focus.
5. Aa shows on Markdown documents and while Reader is on; Phase 7 adds article
   pages.

## Architecture

```
            ReadingPreferences (BrowserKit, UserDefaults "reading.*", synced)
                 │ typeface · size · width · page · outline · wrap
                 ▼
  ReadingStyle.css(palette:)  ◄── InternalPages.palette (InternalPageTheme + Tokens.Reading)
        │                    │
        ▼                    ▼
  Reader (in place)     Markdown document: swift-markdown → MarkdownHTML,
                        loaded with load(data, baseURL: original URL)
        └────────┬───────────┘
                 ▼
  ReadingScript (.defaultClient world): prefs as data-attrs/CSS vars, outline,
  copy buttons, view switching, editor → "lunaReading" handler (page world can't reach it)
                 ▲
  App: URL pill "Aa" RowGlyphView → ReadingMenu → SiteSettingsPanel (same class)
```

Shared: stylesheet, preferences, the Aa pop-out, the in-page script.
Markdown-only: loading, renderer, Source and Edit views, saving.

BrowserKit `Engine/Reading/`: `ReadingPreferences`, `ReadingStyle`,
`ReadingScript`, `TabController+Reading`, `MarkdownHTML`, `MarkdownSource`,
`SyntaxHighlighter`, `MarkdownDocument`.
App: `UI/Popout/ReadingMenu.swift`, `Design/Tokens+Reading.swift`, pill, toast,
settings defaults, sync, theme.

## Key mechanics

- Preferences: `reading.typeface|size|width|page|outline|wrap`, `Key` enum like
  `PopupPolicy.Key`; registered in `Features/Settings/Shell/SettingsDefaults.swift`
  and `Features/Sync/SyncedDefaults.swift`. View mode belongs to the tab.
- Loading: local — branch in `decidePolicyFor navigationResponse` before the
  `canShowMIMEType` fallback (`TabController+Delegates.swift` ~131) for main-frame
  file URLs conforming to `net.daringfireball.markdown`. Web — `text/markdown`,
  `text/x-markdown`, or `text/plain` with `.md`/`.markdown` path: cancel, fetch
  text behind a stubbable `fetchText` seam, load. URL in the pill stays the
  original. Not in-place (site CSP) and not `luna://` (address + history).
- Security: raw HTML never reaches output; links http/https/mailto/#/relative
  only; meta CSP `default-src 'none'; img-src file: http: https: data:;
  style-src 'unsafe-inline'; script-src 'none'; form-action 'none'; base-uri
  'none'`; message handler only in `.defaultClient`; save writes only to the
  tab's own `MarkdownDocument.url`, file URLs only.
- Edit: `<textarea>` over a highlighted backdrop `<pre>` (current-line band),
  live preview beside it. Preview updates by replacing the preview DOM only —
  never assign `textarea.value` after load, or the undo stack is lost. Undo is
  WebKit's native text undo through the responder chain (`undo:`/`redo:` in
  `App/BrowserCommand.swift:131-133`).
- Save: `NSFileCoordinator`; restore detected line endings (textarea normalises
  CRLF); compare modification date with the one read at load — if the file
  changed on disk, keep both safe (reload offer via prompt, never overwrite
  silently). Autosave ~1 s after the last keystroke, and on tab close, window
  close, quit, navigation and switching away from Edit. `TabState.isEdited`
  drives "— Edited" in the pill until the write lands. `PageToast.saved` on ⌘S
  only (autosave is silent).

## Phases (failing tests first; headless, off-screen, never take focus; measure, don't screenshot)

1. Shared surface + preferences, Reader moved onto it — ~4 h.
   Tests: ReadingPreferencesTests (defaults 19/serif/680/match, clamp 14…28,
   round trip), ReadingStyleTests (widths 580/680/820; old Reader rules present),
   PageToolsTests (computed max-width/font-size after apply), ShellTests and
   SyncedDefaultsTests for new keys. Existing Reader tests stay green.
2. Page colours Paper/Sepia/Night — ~3 h. `Tokens.Reading`, TokenCheck contrast
   (text ≥ 7:1, secondary + syntax ≥ 4.5:1), `InternalPageTheme` emits
   `--luna-reading-*`, `--luna-syntax-*`, `--luna-press-swell`.
3. Renderer (pure Swift, swift-markdown) — ~6 h. Add the package in
   `BrowserKit/Package.swift`. Tests: headings + unique slugs, nested/ordered
   lists, table alignment, task lists, strikethrough, autolinks, fence language,
   XSS (`<script>`, `<img onerror>`, `javascript:`/`data:` links, `<iframe>`),
   relative images kept, title = first H1 else file name, Source rows +
   dimmed markers, `isMarkdown(url:mime:)` truth table, SyntaxHighlighter.
4. Open in the tab, Read view, outline, copy — ~6 h. MarkdownPageTests: local
   renders and URL stays file URL, sibling image loads, reload re-reads disk,
   script never runs, handler absent in page world, stubbed web `.md` renders,
   Back skips raw text, outline tracks headings, copy hands code to seam,
   5,000-line README renders in ~40 ms (measured).
5. Aa glyph + Reading pop-out — ~7 h. `SiteSettingsPanel` gains a Control row
   kind and header symbol; `ReadingMenu` content for Markdown local / web /
   Reader; pill order sliders < address < Aa < reload (measured minX); opening
   one pop-out closes the other; geometry 280 / 52 / 38 / 17.5 / 45.5;
   `SettingsChoice` gets `font:`; swatches are `SpaceSwatchChip`; every new
   button in `Tests/Design/ButtonFeedbackTests.swift`; new toasts in
   PageToastTests. If "Narrow / Medium / Wide" does not fit 280 pt, glyphs.
6. Source, Edit, save, undo — ~10 h. Tests: view switch without reload; Edit
   only for local UTF-8; typing updates preview and sets isEdited; ⌘Z/⇧⌘Z undo
   and redo typing, still after an autosave, a ⌘S and a Read↔Edit round trip;
   editor ⌘Z does not restore a hidden element or closed tab; ⌘S saves in Edit
   with the sidebar toggle on its default ⌘S and when rebound, and hides the
   sidebar outside Edit; autosave fires after the pause and on close/quit/
   navigate; CRLF preserved; on-disk change detected, never overwritten.
7. Aa on article pages + docs — ~3 h (optional). Reader scoring probe after
   didFinish; update TODO 18.3/18.9; UI-SPEC section for the Reading pop-out.

Total ~39 h.

## Risks

- Web `.md` behind a login falls back to plain text (fetch skips the tab's cookies).
- Local image read access via `load(data, baseURL:)` is unverified — Phase 4
  test; fallback `loadFileURL` + in-place rewrite.
- Back/reload/session restore for `load(data:)` documents need their own tests.
- Very large files: cap live highlighting above ~5,000 lines.
- Generalising `SiteSettingsPanel` touches tested code — its tests stay green.
- Non-UTF-8 files open read-only.
