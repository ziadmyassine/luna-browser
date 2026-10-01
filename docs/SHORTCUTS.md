# Shortcuts and web apps

Luna's default key map (#130, §20.1) checked against the keyboard shortcuts of
six web apps people live in: Gmail, Google Docs, Figma, Notion, Slack and
Linear. Checked 2026-10-01.

## Who gets a shortcut first

**The page does.** When the page has the keyboard, WebKit sends every ⌘
keystroke to the page before any menu sees it. If the page uses the key (it
calls `preventDefault`), Luna's menu command does not run. If the page ignores
it, the menu runs as usual.

Measured on 2026-10-01 with a `WKWebView` and a menu bar holding ⌘D and ⌘W: a
page that kept ⌘D stopped the menu's ⌘D, and the menu's ⌘W still ran; with the
page keeping ⌘W instead, the menu's ⌘W did not run. Nothing in Luna changes
this — `LunaWebView` only takes ⌘S in the Markdown editor, and no event monitor
looks at ⌘ keys.

So a clash does **not** mean the page never gets its shortcut. It means that
while you are in that web app, Luna's command is not on that key, and you reach
it from the menu bar or the Command Bar instead. When the keyboard is in Luna's
own chrome (the sidebar, the address field), Luna's command runs.

Two exceptions, which Luna takes before the page:

- **⌃⇥ and ⌃⇧⇥**, the tab switcher. Its event monitor runs before the window,
  because it has to see ⌃ come back up.
- **Any key while the page does not have the keyboard.**

Single-letter shortcuts (Gmail's `c`, `j`, `k`; Linear's `c`; Figma's tools)
never clash: every Luna shortcut has ⌘ or ⌃ in it.

## Luna's default keys

From `BrowserCommand.all`, plus the app menu and the numbered families.

| Area | Keys |
| --- | --- |
| App | ⌘, Settings · ⌘H Hide · ⌥⌘H Hide Others · ⌘Q Quit · ⌘? Luna Help |
| File | ⌘T New Tab · ⌘N New Window · ⇧⌘N Private Window · ⌘L Open Location · ⌘O Open File · ⌘W Close Tab · ⇧⌘K Close All Tabs · ⌥⌘K Clean Up Tabs · ⇧⌘T Reopen Last Archived Tab · ⇧⌘W Close Window |
| Edit | ⌘Z ⇧⌘Z ⌘X ⌘C ⌘V ⌘A · ⌘F Find · ⌘G / ⇧⌘G Find Next / Previous · ⌘E Use Selection for Find · ⇧⌘C Copy URL · ⌥⇧⌘C Copy URL as Markdown |
| View | ⌘S Hide Sidebar · ⌘D Add to Favorites · ⌘R Reload · ⌥⌘R Force Refresh · ⌘. Stop · ⌘+ / ⌘= / ⌘- / ⌘0 Zoom · ⇧⌘P Picture in Picture · ⇧⌘R Reader · ⇧⌘H Hide Something · ⌥⌘L Downloads · ⌘1…⌘9 Sidebar items |
| History | ⌘[ Back · ⌘] Forward · ⌘Y Show History |
| Develop | ⌥⌘I Web Inspector · ⌥⌘C JavaScript Console · ⌥⌘U Page Source · ⌥⌘E Empty Caches |
| Window | ⌘M Minimize · ⌥⌘← / ⌥⌘→ (and ⇧⌘[ / ⇧⌘]) Previous / Next Tab · ⌃⌥← / ⌃⌥→ Previous / Next Space |
| Spaces | ⌃1…⌃9 |
| Tab switcher | ⌃⇥ / ⌃⇧⇥ (event monitor, not a menu item) |

## Clashes

"In the app" means the web app keeps the key while it has the keyboard, so
Luna's command is on the menu bar and the Command Bar only. **Keep** means no
change is proposed.

| Keys | Luna | Web apps that use it | Recommendation |
| --- | --- | --- | --- |
| ⇧⌘C | Copy URL | Gmail (add Cc), Docs (word count), Slack (code), Figma (copy as PNG), Linear (inline code) | Keep. Five of six use it, but only while you are typing or on the canvas; the app's meaning is the one you want there. Arc uses ⇧⌘C for Copy URL too. |
| ⇧⌘H | Hide Something | Docs (find and replace), Slack (huddle), Notion (last highlight colour), Figma (show/hide layer) | Keep. A rare command; the page's meaning is right in each app. |
| ⇧⌘K | Close All Tabs | Docs (input tools), Slack (browse DMs), Figma (place image) | Keep. The app wins while it has the keyboard; with the keyboard in Luna's chrome the tabs close, but as one ⌘Z step with a toast saying how many. If this proves annoying, unbind it rather than move it. |
| ⌘D | Add to Favorites | Notion (duplicate block), Figma (duplicate), Linear (due date, strikethrough) | Keep. Safari and Chrome use ⌘D to bookmark; web apps already expect to win it. |
| ⌘. | Stop Loading | Docs (superscript), Slack (hide right sidebar), Linear (copy issue ID) | Keep. Stop only matters while a page loads. |
| ⌘[ / ⌘] | Back / Forward | Gmail and Docs (indent), Figma (send backward / bring forward); Slack and Notion use them for back and forward too | Keep. Every browser's keys. |
| ⇧⌘R | Reader | Gmail and Docs (align right) | Keep. Safari's key. |
| ⌘G / ⇧⌘G | Find Next / Previous | Figma (group / ungroup), Slack (search / find previous) | Keep. Fixed by macOS. |
| ⌘F | Find | Docs, Notion, Slack (their own search) | Keep. Same meaning; the app's search is the better one there. |
| ⌘E | Use Selection for Find | Notion (inline code), Figma (flatten) | Keep. Fixed by macOS. |
| ⌘R | Reload | Figma (rename), Notion (fill right, in a table) | Keep. Only while that app has the keyboard. |
| ⌘S | Hide Sidebar | Docs (save) | Keep. Docs saves on its own. |
| ⌘, | Settings | Docs (subscript) | Keep. Fixed by macOS. |
| ⌘Y | Show History | Docs (repeat last action) | Keep. Safari's key. |
| ⌘O | Open File | Docs (open a document) | Keep. Same idea. |
| ⌘L | Open Location | Notion (copy page link) | Keep. Notion lists it; Chrome and Safari also let a page take ⌘L. |
| ⌘M | Minimize | Gmail (spelling suggestions), Linear (comment) | Keep. Fixed by macOS. |
| ⌥⌘C | JavaScript Console | Docs (copy formatting), Figma (copy properties) | Keep. Safari's key, and the Develop menu can be hidden. |
| ⌥⌘H | Hide Others | Docs (braille support) | Keep. Fixed by macOS. |
| ⌥⌘K | Clean Up Tabs | Figma (create component) | Keep. |
| ⌥⇧⌘C | Copy URL as Markdown | Slack (code block) | Keep. |
| ⌥⌘R | Force Refresh | Slack (canvas reader view, in a canvas only) | Keep. Safari's key. |
| ⌃1…⌃9 | Switch Space | Slack (⌃1 Home, ⌃number for its tabs) | Keep. Arc's keys. In Slack, ⌃⌥← / ⌃⌥→ still change Space. |
| ⌘+ / ⌘- / ⌘0 | Zoom | Docs, Notion, Figma (their own zoom) | Keep. Same meaning. |

No clash: ⌘T, ⌘N, ⇧⌘N, ⌘W, ⇧⌘W, ⇧⌘T, ⇧⌘P, ⌥⌘L, ⌥⌘I, ⌥⌘U, ⌥⌘E, ⌥⌘←/→,
⌃⌥←/→ and ⌘1…⌘9. Slack and Notion use ⌘N, ⌘T, ⌘W, ⇧⌘T, ⌘1…⌘9 and ⌃⇥ only in
their desktop apps.

## Proposals, not made

- **Let no page keep ⌘Q, ⌘W, ⌘T, ⌘N, ⇧⌘N, ⇧⌘T and ⇧⌘W**, as Chrome does. Today
  any page can keep them (measured above), so a page can stop ⌘W from closing
  its tab. None of the six apps does this in a browser. This would be a
  `performKeyEquivalent` override in `LunaWebView` that sends these keys to the
  menu first.
- **⇧⌘K**: unbind Close All Tabs by default if a clash is ever reported. It is
  the one destructive command on a key that three of these apps use.

## Sources

- Gmail: support.google.com/mail/answer/6594
- Google Docs: support.google.com/docs/answer/179738
- Notion: notion.com/help/keyboard-shortcuts
- Slack: slack.com/help/articles/201374536
- Linear: its shortcut list (linear.app's own docs page moved; checked through
  defkey.com/linear-shortcuts)
- Figma: its help centre page on keyboard use lists only a few shortcuts. The
  ones above are Figma's well-known keys, not re-checked against the app.
