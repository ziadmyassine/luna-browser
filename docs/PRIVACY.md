# Privacy

Luna has no account, no server and no analytics. Everything below is every way
data leaves your Mac, and what turns it on.

| What | Sent to | When |
|---|---|---|
| **The pages you open** | The sites themselves, through WebKit | Whenever you browse |
| **What you type in the address bar** | Your search engine's suggestion service (Google, Bing or DuckDuckGo) | While you type, if **search suggestions** are on. They are on by default; turn them off in Settings ▸ Search. Anything that looks like a password, a login in a URL or a file path is never sent |
| **Site icons** | Each site you visit (`/favicon.ico` on that site) | When a tab shows a site without an icon yet. No third-party icon service is used |
| **Content blocking lists** | easylist.to | Once a day, for each blocking list that is on |
| **Update checks** | GitHub's releases API (`api.github.com`) | About once a day. A setting decides whether an update installs by itself (on by default) |
| **Extensions from the Chrome Web Store** | Google (`clients2.google.com`) | Only when you add an extension. What an extension itself sends depends on the permissions you grant it at install |
| **iCloud sync** | Your own iCloud account (CloudKit private database) | Only if you turn it on. Luna's developers have no server and cannot read it; sensitive fields use CloudKit's encrypted fields |
| **Pinned tabs in Safari's Favorites** | Safari's own iCloud sync, through Safari's bookmarks | Only if you turn it on (Settings ▸ iCloud). It needs Full Disk Access to edit Safari's bookmarks file |
| **Luna Control** | The AI app you connect (Claude, Codex, Cursor, VS Code) | Only if you turn it on (off by default). The app can read and act on your tabs, and asks you before sensitive steps. What that app does with the data is up to that app |

What stays on your Mac: history, tabs, Spaces and settings (a SQLite
database in Luna's Application Support folder), and each Space's cookies and
site data, kept apart from every other Space's. Passwords are in the macOS
Keychain; iCloud Keychain syncs them if you have it on.

Luna sends no telemetry, analytics or crash reports (decision D16 in
[DECISIONS.md](DECISIONS.md)).
