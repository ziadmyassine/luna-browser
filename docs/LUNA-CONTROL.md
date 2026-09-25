# Luna Control

Luna Control lets an AI agent or any other program on this Mac drive Luna over
the [Model Context Protocol](https://modelcontextprotocol.io): open tabs, read
pages, click, type, fill forms, take screenshots and run JavaScript. It works
with any MCP client. No client is special-cased.

It is **off by default**. Turn it on in Settings → Luna Control.

## How it fits together

```
MCP client ──stdio──▶ Luna.app/Contents/MacOS/luna-control ──Unix socket──▶ Luna
```

- `luna-control` is a small helper bundled in the app. It speaks MCP
  (JSON-RPC, one message per line) on stdin/stdout and passes each message
  through to the running Luna.
- Luna listens on `~/Library/Application Support/dk.novapps.luna/Control/luna.sock`
  only while the setting is on. Turning it off removes the socket and drops
  every connection.
- If Luna is not running or the setting is off, the helper still completes the
  MCP handshake and answers every tool call with an error saying how to fix it.
  It connects on the next call once Luna is back. It never launches Luna.
- Code: `BrowserKit/Sources/LunaControl` (protocol, tools, socket, relay,
  page scripts; Foundation only), `Features/Control` (the app side),
  `UI/Browser/BrowserSession+Control.swift` (tabs and folders).

## Setup

1. **Turn it on.** Settings → Luna Control → *Allow apps to control Luna*.
2. **Click Connect** beside your app under *Connect an app*. Luna adds itself
   to that app's MCP config, keeps every other server in it, and saves the
   file as it was next to it as `<file>.luna-backup`. Nothing is written
   until you press the button, and Disconnect removes only Luna's entry.
   For Claude Code the button copies a command instead: paste it into
   Terminal.
3. **Restart the app** if its row says so. Claude Desktop, Codex and Claude
   Code read their config when they start (in Claude Code, a new session is
   enough). In Cursor or VS Code, reload the window if Luna's tools do not
   show up.
4. **Try it.** Ask the app something like *"Use Luna to open news.ycombinator.com
   and tell me the top three stories."* The tabs it opens appear in a sidebar
   folder named after it, and its row in Settings shows *in use now*.

The app's row shows *Not installed* when none of its usual folders exist.
That is a guess from the files on disk: if yours lives somewhere else, use
the manual setup below.

### Manual setup

Each app's own documented format. The helper path is
`/Applications/Luna.app/Contents/MacOS/luna-control`; a development build's is
`DerivedData/Build/Products/Debug/Luna.app/Contents/MacOS/luna-control`.

**Claude Code** ([docs](https://code.claude.com/docs/en/mcp)), stored in
`~/.claude.json`:

```sh
claude mcp add --scope user luna -- /Applications/Luna.app/Contents/MacOS/luna-control
claude mcp remove luna --scope user
```

**Codex** ([docs](https://learn.chatgpt.com/docs/extend/mcp?surface=cli)),
`~/.codex/config.toml`:

```toml
[mcp_servers.luna]
command = "/Applications/Luna.app/Contents/MacOS/luna-control"
```

or `codex mcp add luna -- /Applications/Luna.app/Contents/MacOS/luna-control`.

**Cursor** ([docs](https://cursor.com/docs/context/mcp)), `~/.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "luna": { "type": "stdio", "command": "/Applications/Luna.app/Contents/MacOS/luna-control" }
  }
}
```

**Claude Desktop**
([docs](https://modelcontextprotocol.io/docs/develop/connect-local-servers)),
`~/Library/Application Support/Claude/claude_desktop_config.json`, then quit
and reopen Claude:

```json
{
  "mcpServers": {
    "luna": { "command": "/Applications/Luna.app/Contents/MacOS/luna-control" }
  }
}
```

**VS Code**
([docs](https://code.visualstudio.com/docs/copilot/customization/mcp-servers)),
`~/Library/Application Support/Code/User/mcp.json` (*MCP: Open User
Configuration*). Note the key is `servers`:

```json
{
  "servers": {
    "luna": { "type": "stdio", "command": "/Applications/Luna.app/Contents/MacOS/luna-control" }
  }
}
```

Luna's Connect edits the default profile's file. A VS Code profile of your
own keeps its own `mcp.json`, and a file with comments in it is left alone
rather than rewritten; add the entry by hand in either case.

**Any other MCP client**: most take the Claude Desktop entry above. *Other
apps* in Settings copies it.

## What the agent sees

The client is named from `clientInfo.name` in MCP's `initialize`, made readable
(`claude-code` → Claude Code, `codex-mcp-client` → Codex, nothing → Agent).
Every tab it opens goes into a sidebar folder with that name in the current
Space. The folder is made on first use and reused after that. In the sidebar it shimmers
while the agent is working in it. Agent tabs open in the background. The
user's window keeps showing what it was showing, and Luna is never brought to
the front.

Agents can also read and act on the user's own tabs. `tabs_list` lists them.
They can only close tabs in their own folder.

| Tool | What it does |
|---|---|
| `tabs_list` | Every open tab in every Space, with its number |
| `tab_open` | Open a tab in the agent's folder (`url` optional) |
| `navigate` | Go to `url`, or `back` / `forward` / `reload`, and wait for the load |
| `read_page` | Accessibility-style tree with refs (`e12`) on controls. `filter: interactive`, `ref`, `max_depth` |
| `page_text` | The page's readable text |
| `find` | Elements whose text, label or role match `query` |
| `click` | By `ref` or `coordinate` `[x, y]` (CSS pixels, same as the screenshot). `click_count` 1–3, `button` left/right/middle, `modifiers` (`cmd+shift`). Selects and date/colour pickers are refused (use `form_input`), file inputs too (use `file_upload`) |
| `type` | Type into the focused element or `ref`; a newline is Enter |
| `key` | `Enter`, `Tab`, `Escape`, `Backspace`, arrows, `F1`–`F12`, `cmd+a`, separated by spaces; `repeat` up to 50. An unknown key name is refused |
| `hover` | Hover over `ref` or `coordinate` (page events only) |
| `drag` | From `ref` or `start_coordinate` to `to_ref` or `coordinate`: a pointer drag, or HTML5 drag and drop for a draggable source |
| `scroll` | `direction` and `amount`, or bring `ref` into view |
| `form_input` | Set a field, checkbox or select by `ref` |
| `file_upload` | Give `files` to a file input by `ref` (input and change fire), or drop them on anything else. Each file is `{name, mimeType, data}` (base64) or `{path}` on this Mac. 10 MB a file, 25 MB a call |
| `screenshot` | PNG of the viewport at 1 px per CSS pixel. `scale` 0.1–1 shrinks it; after a scaled one, `click`, `hover`, `drag` and `scroll` points are read in that picture's pixels and mapped back until the next screenshot. `region` `[x0, y0, x1, y1]` (CSS pixels) zooms into part of the viewport and leaves the mapping alone |
| `gif` | `action` `start` records the tab: a frame after each call that can change the page, with a red ring where a click, hover or drag pointed. `stop` pauses, `export` writes an animated GIF to `Control/Recordings/` in Luna's Application Support folder and returns its path. The newest 60 frames are kept, at most 800 px wide |
| `viewport` | Lay one of the agent's own tabs out at `width` × `height` CSS pixels (320–3840 each), or back at the window's page size with neither. See *Viewport* |
| `javascript` | Run code in the page and return the last value as JSON |
| `console_read` | Console output since Luna Control first touched the page (`pattern`, `only_errors`, `clear`) |
| `network_read` | Requests since Luna Control first touched the tab, with headers and, with `include_bodies`, bodies. `pattern`, `clear`. See *Network log* |
| `tab_close` | Close a tab in the agent's folder |
| `wait` | Sleep up to 30 s |
| `request_user` | Ask the user to do a step only they can (`reason`), and wait up to five minutes for **Done** |
| `dialog` | Answer the `alert`/`confirm`/`prompt` open in the tab: `action` `accept` or `dismiss`, `text` for a prompt |
| `batch` | Up to 20 of the above in order (`actions: [{tool, args}]`). Stops at the first failure; a step's `ref` may be `"$N"`, the first ref in step N's result. No nesting |

Acting tools may wait for the user's approval first; see *Security*.

Every page tool takes an optional `tabId`. Without one it uses the tab the
agent last opened or acted on, or the tab in front if there is none yet. A
tab that has gone to sleep is woken first. It stays out of sight and does not
push the user's recent tabs out of the live-tab budget.

### Trusted input

`click`, `type`, `key` and pointer `drag`s are real input: the page's events
have `isTrusted` set, so editors that ignore script (Google Docs and the like)
take them. `Features/Control/ControlStage.swift` lends the tab to a borderless
window at (-20000, -20000) for the length of one call. The window can never
become key or main, ignores the mouse, is excluded from the Window menu and
Exposé, and is ordered in without activating Luna. Events are built with
`NSEvent` and handed straight to the web view; `CGEvent.post` is never used,
so the user's pointer does not move. The tab goes back to having no window
when the call ends.

- Only a tab in no window is staged. A tab the user has on screen is never
  taken, since that would take their first responder. An agent's own tab that
  the user has selected, or shows in a split, is refused as taken over. The
  user's own tab on screen gets page events instead.
- If the user shows the tab while a call is running, the next event is
  refused.
- WebKit passes keys the page did not handle to `NSApp.sendEvent`, where the
  main menu would treat an agent's Cmd+W as the user's. `LunaApplication`
  drops every key event from a stage window. Select All is done on the
  stage's web view. Copy, cut and paste are dropped, so the clipboard is never
  read or written.
- While the stage drives a page, the library prevents in the capture phase
  the default action of `contextmenu`, `mousedown` on a `<select>`, clicks on
  file, colour and date inputs, and `dragstart`. The page's own listeners
  still see the trusted events, but no native menu, picker or drag session
  opens on the user's screen. As a backstop, a menu that starts tracking while
  a stage is up gets an Escape posted to Luna's event queue. A menu the user
  opens in that moment closes too.
- A page on the stage is `hidden`: `requestAnimationFrame` does not run and
  timers are throttled. Results say `trusted: true` or `trusted: false`. Pass
  `trusted: false` to use page events for a page that only reacts on an
  animation frame.
- Page events are used for hover and middle clicks, because WebKit does not
  turn a moved event into a hover on the stage and `NSEvent` cannot build a
  middle-button press. They are also used for drag and drop from a draggable
  element: a trusted press there would start a real drag session that
  follows the user's pointer, so `dragstart` → `drop` → `dragend` is
  synthesised with one `DataTransfer`.

### Viewport

`viewport` sets the frame of the agent tab's web view while that view is in
no window, so an agent can test a phone layout while the user carries on in
their own tabs. No window changes size and no other tab is touched. The stage
takes the view at that size for trusted input and gives it back at it.

- Only a tab in the client's own folder, and only while it is in no window.
  A tab the user has selected or shows in a split is refused: its size is
  their window's.
- When the user shows the tab, the content card pins it to its edges, which
  ends the override; `viewport` with neither size puts it back explicitly.

Page events and reads run in a content world of their own that the page
cannot see: events dispatched on the element, `execCommand('insertText')` for
typing, the form's own `requestSubmit()` for Enter. They need no window at
all.

## Security

Whoever connects controls a browser that is signed in as the user, with every
cookie in every non-private Space. That is why it is opt-in, and why every
call passes one gate in Luna (`Features/Control/ControlService+Safety.swift`)
before it runs. `tabs_list` and `wait` go through it too.

### Who can connect

- The only way in is the Unix socket. There is no TCP port and no network
  listener, so nothing off this Mac can reach it.
- The socket's folder is `0700` and the socket is `0600`, so only programs
  running as the same macOS user can connect.
- The socket exists only while the setting is on.
- Private windows are not reachable. Luna Control only sees the main session.
- Luna's own pages (anything not `http`, `https`, `about`, `data`, `file` or
  `blob`) are refused for reading and acting alike.

### Modes and grants

Settings → Luna Control → *Before an app acts on a page*:

| Mode | Acting calls |
|---|---|
| **Ask** (default) | Every one waits for the user |
| **Per Site** | Allowed on a site the user allowed for this app; anywhere else waits, and the prompt can allow the site |
| **Allow All** | Allowed, except as below |

- *Acting* means `navigate`, `tab_open` with a URL, `click`, `type`, `key`,
  `drag`, `form_input`, `file_upload` and `javascript`. Reading (`tabs_list`,
  `read_page`, `page_text`, `find`, `screenshot`, `gif`, `console_read`,
  `network_read`), `scroll`, `hover`, `viewport`, `wait`, a blank `tab_open`
  and `tab_close` (own folder only) never ask. `gif` and `viewport` change
  nothing on the site: one keeps pictures in Luna's own folder, the other lays
  out the agent's own tab at another size.
- A grant is the app's display name plus the registrable domain
  (`shop.example.com` → `example.com`, via the public-suffix list). Settings
  lists every grant with a Revoke button.
- In every mode, opening a `file:` URL asks, and so does acting on a site
  whose page addressed the agent (below), and every sensitive action (below).
- Accepting a page dialog acts; dismissing it does not.
- `javascript` asks in Ask and Per Site modes even on a granted site, and
  the card never offers "allow on this site" for it; only Allow All runs it
  unasked. The card shows the script, cut to 200 characters.
- A `file_upload` with a `path` asks in Ask and Per Site mode even on an
  allowed site — a grant covers acting on the page, not which of the user's
  files leaves the Mac — and the card lists every path in full. Only Allow All
  skips it. Bytes the agent sends itself are an ordinary acting call.
- `batch` carries no permission of its own. `ControlSession` decodes each
  step and hands it to the gate alone, so every step is stopped, asked about,
  redacted and logged as if it had been sent by itself; a declined step ends
  the batch. `"$N"` is read from step N's result, which is page text, so a
  page can steer it to another element on that page — never past the gate.
- No tool can read or change the mode or the grants. Only Settings and the
  user's own answer to a prompt write them.
- The rules are one pure function, `ControlPolicy.decide`, tested in
  `ControlPolicyTests`.

### Asking

A call that needs approval waits without taking the user's window: the
folder's icon becomes a raised hand and the Dock icon bounces once
(`requestUserAttention(.informationalRequest)`). Luna is never activated and
no window becomes key. Clicking the folder opens a card saying what the call
will do and where, with **Deny**, **Allow Once** and, in Per Site mode,
**Allow on *site***. None of them is the default button. A request nobody
answers is declined after five minutes. If the page moved to another site
while the user was deciding, the call is not made. The agent reads a declined
call as an error telling it not to work around it.

### Sensitive actions and handing off

Before every `click`, `type`, `key`, `drag` and `form_input`, the page
library's `inspect` looks at the element the call names
(`ControlScripts+Inspect.swift`) and reports `ControlRisk`s. A `drag` is
inspected at both ends, so a slider CAPTCHA hands off and a drop on a pay or
delete control asks. In every mode, with or without a grant:

| Found | Decision |
|---|---|
| A CAPTCHA (reCAPTCHA, hCaptcha, Turnstile, Arkose), or typing into a password, card, one-time-code or other secret field | Refused and handed to the user |
| Submitting a form with a password field | Asks |
| Submitting a form with card fields, or pressing something labelled pay, buy, order, purchase, checkout, subscribe or donate | Asks |
| Submitting a form with an address, phone, birth date or ID number field | Asks |
| Pressing something labelled authorize, allow, grant or approve, or a link to (or `navigate`/`tab_open` of) an OAuth authorization URL (`client_id` with `redirect_uri` or `response_type`) | Asks |
| Pressing something labelled delete, erase or destroy | Asks |
| A link with a `download` attribute | Asks |

Asking here is never grantable, since it is about the action and not the
site. A handed-off call does nothing and tells the agent to call
`request_user`, which marks the folder like an approval. The card reads
"*agent* needs you to …" with **Not Now** and **Done**.

`javascript` is not inspected: it can do anything, which is why it asks in
every mode but Allow All and why Allow All is a trust decision. The inspection reads the
page just before the call. A page that swaps the element between the two can
get past it; the redactor and the dialog and download rules still apply.

### Page dialogs

`alert`, `confirm` and `prompt` from a tab in an agent's folder are held for
the agent rather than sheeted on the user's window, unless the user has that
tab in front of them. A call whose script opens one comes back at once with
the dialog's text. Every other call on the tab fails with the same text until
the agent answers with `dialog`. After 30 seconds the dialog is dismissed,
but not while an approval for that agent is waiting. A "Leave site?"
(`beforeunload`) prompt never appears: a `WKWebView` app has no public API
for it, and leaving a page always goes ahead.

### Downloads

A download started in a tab in an agent's folder waits for the user in
every mode, since it puts a file on this Mac. The card names the file and
says when it can run programs. That answer replaces the sheet Luna otherwise
shows for such files, so nothing lands on the user's window. Downloads are
in the activity log as `download`.

### Stop and pause

- Right-click an agent's folder for **Pause Agent** (new calls are refused,
  running ones finish), **Stop Agent** (running calls, including ones waiting
  for approval, are cancelled and new ones refused) and **Resume Agent**. The
  folder wears a pause or stop icon meanwhile.
- **Luna → Stop All Agents** does the same for every client until **Resume
  Agents**. It works even with the setting off.
- Selecting one of the agent's own tabs takes it over: acting calls on the
  tab in front are refused until the user leaves it.
- Holds last until resumed or until Luna quits.

### Uploads from disk

`ControlUpload` reads a `path` only after the gate, so it checks the file as
it is then, not as it was when the user approved it. It opens the path once
with `O_NOFOLLOW` and checks the open descriptor, so a path swapped for a link
in between reads nothing. Refused:

- a relative path, a symbolic link, anything but a regular file (a FIFO
  fails this rather than hanging the call);
- a file with more than one hard link — the other name could be anywhere;
- a file not owned by the user Luna runs as;
- anything in a credential store — `~/.ssh`, `~/.gnupg`, `~/.aws`,
  `~/.azure`, `~/.config/gcloud`, `~/.kube`, `~/.docker`, `~/.config/gh`,
  `~/.password-store`, `~/.1password`, `~/.netrc`, `~/.git-credentials`,
  `~/.npmrc`, `~/.pypirc`, both Keychains folders;
- other browsers' data (Chrome, Firefox, Brave, Arc, `~/Library/Safari`,
  `~/Library/Cookies`) and any app's `Application Support/*/Cookies*`;
- Luna's own data (its Application Support, Caches, WebKit, HTTPStorages,
  Cookies, Containers and Logs folders, preferences and saved state);
- files named like keys or env files anywhere: `id_rsa`, `id_dsa`,
  `id_ecdsa`, `id_ed25519`, `*.pem`, `*.key`, `*.p12`, `*.pfx`, `.env`,
  `.env.*`.

Each is judged both by the path as given (after `..`, case-insensitively) and
by where the open file really is (`F_GETPATH`), so a linked folder on the way
does not get round it. The lists are tables at the top of `ControlUpload`.
Also refused:

- more than 10 MB a file or 25 MB a call, inline files included.

The files cross the socket as base64 in one line; `LineReader` has no line
limit, so 25 MB is the cap. Tested headless in `ControlUploadGuardTests`, and
in a windowless page in `ControlScriptsTests.testUploadSetsFilesAndFiresChange`.

### Redaction

- The page scripts never return the value of a password field, any
  `autocomplete="cc-*"` field, a one-time code, or a field whose name, id or
  label says card number, CVV/CVC, OTP, PIN, SSN or IBAN. They show
  `value=[hidden]` and keep the label, so the agent can still find the field
  and hand it to the user.
- Screenshots, at any `scale` or `region`, and every `gif` frame draw those
  fields as dots (`-webkit-text-security`) for the picture and put them back
  after (`Features/Control/ControlCapture.swift`, tested in
  `ControlCaptureTests`). Fields inside iframes and shadow roots are not
  reached. A recording is written only when the agent exports it, to Luna's
  user-only Control folder; it holds whatever else the page showed.
- Every text result then goes through `ControlRedactor`: Luhn-valid runs of
  13–19 digits, JWTs, `Bearer` tokens, the values of `Authorization`,
  `Cookie`, `Set-Cookie`, API-key and CSRF headers, and query, cookie or JSON
  values whose name ends in token, secret, session, code, key, password and
  the like become `[hidden]`. It errs toward hiding; an order number that is
  not a valid card number stays.
- `javascript` can still read anything the page can, and returns it through
  the same redactor. A secret in a shape the redactor does not know gets
  through, so only connect agents you trust.

### Network log

`network_read` is an approximation, and its description tells the agent so.

- The first call on a tab adds a page-world script, from then on at document
  start and main frame only, that wraps `fetch`, `XMLHttpRequest`,
  `sendBeacon` and `WebSocket.send`. Tabs no agent has touched never get it.
  Other resources come from resource timing: URL, type, status, no headers.
- Each document the tab loads, main frame and iframes, is taken from the
  navigation response: status and response headers, minus `Set-Cookie`.
- Bodies are read only if textual, from a clone, and cut at 10 KB; the page
  log keeps the newest 500 entries and starts again on each navigation.
- It cannot see headers the browser adds (`Cookie`, `User-Agent`),
  `Set-Cookie`, cross-origin response headers the server does not expose,
  no-cors bodies, workers and service workers, requests from inside iframes,
  or the headers and bodies of images, scripts and stylesheets.
- Everything passes the redactor above, so `Authorization` values, tokens in
  URLs and secret JSON fields come back `[hidden]`.
- The page can read and rewrite the log, so it is fenced as untrusted like any
  other page text. The wrapped `fetch` is also visible to the page's own
  fingerprinting; that is not hidden.

### Untrusted page data

Page-derived text comes back fenced:

```
<untrusted_page_data nonce=3f9c… url="https://example.com/">
…
</untrusted_page_data nonce=3f9c…>
```

The nonce is new for each result and any `untrusted_page_data` tag inside the
text is escaped, so a page can neither close the fence nor open one of its
own. MCP's `instructions` and every page tool's description say that what is
inside is data, never instructions. If the text looks like it is talking to
an AI agent ("ignore previous instructions", "note to AI agents", a fake
`</system>`), Luna says so in the result and every acting call on that site
asks for the rest of the connection, whatever the mode.

### Activity log

Every call is written as one JSON line to
`~/Library/Application Support/dk.novapps.luna/Control/activity.jsonl` (mode
`0600`): time, app, tool, tab, site, a summary, the decision (`allowed`,
`approved`, `declined`, `refused`, `stopped`) and whether it failed. Typed
text is counted, not kept, and script is scrubbed and cut to 200 characters.
Past 4 MB the file rolls to `activity.1.jsonl`. Settings shows the last
twenty calls.

## The Settings pane

Settings → Luna Control opens on a night sky (`ControlSkyView`), always dark
whatever the appearance, with the switch in its lower corner and a chip in
its upper one saying whether apps can reach Luna and which are in use.

- **The moon is the switch's state.** New while Luna Control is off, full
  while it is on. Turning it on fills it over `Motion.moonrise` (1.1 s);
  turning it off empties it over `moonset` (0.6 s). The moon also rises again
  each time the pane is shown.
- **Each connected app is a light on one of two orbits**, in its own colour
  (`Tokens.Moon.satellites`, by its place in `ControlApp.all`), named beside
  it. The app in use trails a tail and a widening ring, and each call it
  makes runs a beam to the moon (`moonBeam`), which swells slightly as it
  lands. Connect flies a light from the app's planet in the list into its
  orbit (`satelliteLaunch`); Disconnect fades it out.
- **The rows** show each app's own icon, taken from the app installed on this
  Mac (`ControlAppIcon`: Claude Code and Claude Desktop use Claude's, Codex the
  ChatGPT app's), with a dashed ring in the app's colour once it is connected
  and a status dot: grey, green, or green with a ring while in use. An app
  with nothing installed to take an icon from gets a planet in its colour with
  its initials. The same icon flies on the app's orbit in the sky.
- **Before an app acts on a page** is three cards, each with a moon: a
  crescent for Ask, a half moon for Per Site, a full moon for Allow All. The
  chosen card's moon waxes to its phase (`modePhase`, 0.35 s). Allowed sites
  steps back to half strength outside Per Site mode, where it is not used.
- **Recent activity** is a rail with one dot per call in the calling app's
  colour. A call that arrives while the pane is open fades in at the top.

The four motions over 0.35 s — `moonrise`, `moonset`, `moonBeam`,
`satelliteLaunch` — plus the repeating `livePulse` are exempt from UI-SPEC
§6's budget because nothing waits on them: the setting has already changed
when they start. `TokenCheck` holds each to its value. Under Reduce Motion the
sky is still: the moon shows its phase, the lights sit on their orbits, and
nothing flies, beams, twinkles or pulses.
