# Luna Control

Luna Control lets an AI agent or any other program on this Mac drive Luna over
the [Model Context Protocol](https://modelcontextprotocol.io): open tabs, read
pages, click, type, fill forms, take screenshots and run JavaScript. It works
with any MCP client. No client is special-cased.

It is **off by default**. Turn it on in Settings → Advanced → *Allow apps to
control Luna*.

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

Claude Code:

```sh
claude mcp add luna -- /Applications/Luna.app/Contents/MacOS/luna-control
```

Codex:

```sh
codex mcp add luna -- /Applications/Luna.app/Contents/MacOS/luna-control
```

Cursor (`~/.cursor/mcp.json`) and Claude Desktop
(`~/Library/Application Support/Claude/claude_desktop_config.json`) take the
same entry:

```json
{
  "mcpServers": {
    "luna": { "command": "/Applications/Luna.app/Contents/MacOS/luna-control" }
  }
}
```

A development build's helper is at
`DerivedData/Build/Products/Debug/Luna.app/Contents/MacOS/luna-control`.

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
| `click` | By `ref` or `coordinate` `[x, y]` (CSS pixels, same as the screenshot). `click_count` |
| `type` | Insert text into the focused element or `ref` |
| `key` | `Enter`, `Tab`, `Escape`, `Backspace`, arrows, `cmd+a`, separated by spaces |
| `scroll` | `direction` and `amount`, or bring `ref` into view |
| `form_input` | Set a field, checkbox or select by `ref` |
| `screenshot` | PNG of the viewport at 1 px per CSS pixel |
| `javascript` | Run code in the page and return the last value as JSON |
| `console_read` | Console output since Luna Control first touched the page (`pattern`, `only_errors`, `clear`) |
| `tab_close` | Close a tab in the agent's folder |
| `wait` | Sleep up to 30 s |

Every page tool takes an optional `tabId`. Without one it uses the tab the
agent last opened or acted on, or the tab in front if there is none yet. A
tab that has gone to sleep is woken first. It stays out of sight and does not
push the user's recent tabs out of the live-tab budget.

Actions go through the DOM, in a content world of their own that the page
cannot see: events dispatched on the element, `execCommand('insertText')` for
typing, the form's own `requestSubmit()` for Enter. Nothing needs the window
to be focused or on screen. Some sites only accept real (trusted) input
events, and the synthesised ones will not work there.

## Security

Whoever connects controls a browser that is signed in as the user, with every
cookie in every non-private Space. That is why it is opt-in and why:

- The only way in is the Unix socket. There is no TCP port and no network
  listener, so nothing off this Mac can reach it.
- The socket's folder is `0700` and the socket is `0600`, so only programs
  running as the same macOS user can connect.
- The socket exists only while the setting is on.
- Private windows are not reachable. Luna Control only sees the main session.
- Password field values are never included in `read_page` or `find`. They are
  shown as `[hidden]`. `javascript` can still read anything the page can, so
  only connect agents you trust.
