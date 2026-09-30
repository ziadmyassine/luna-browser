# Pinned tabs in Safari's Favorites

Settings ▸ iCloud ▸ Safari ▸ **Show pinned tabs in Safari's Favorites** puts the user's Favorites tiles
and pinned tabs straight into Safari's Favorites, one bookmark each, beside the user's own. Safari's own
iCloud sync takes them to the iPhone, where they are on Safari's start page. Off by default.

Code: `Features/SafariFavorites/` — `SafariBookmarksDocument` (the edit), `SafariBookmarksFile` (the lock,
the guarded write, the wake-up), `SafariFavorites` (what goes in, when, and the status the Settings page
shows). Tests: `Tests/SafariFavorites/`.

## Why this is the way in

There is no public interface. Safari Web Extensions have no bookmarks API, Apple's iCloud Bookmarks
extension exists only on Windows, CloudKit only reaches a team's own containers, and the sync agent's XPC
needs a private entitlement. What is left is Safari's own file, `~/Library/Safari/Bookmarks.plist`,
written the way Safari writes it. Research and sources: `reports/Live Safari sync for Luna.md` (not
committed).

**Writing the tree is not enough.** Safari's sync agent (`SafariBookmarksSyncAgent`) does not compare the
file with iCloud; it uploads what the top-level `Sync.Changes` array lists, clears the list, and fills in each
new item's `Sync.Data` (its CloudKit system fields).
Measured 2026-09-29: a bookmark written into the tree alone was shown by Safari on the Mac, got a
`ServerID`, and was never uploaded.

## The entries

Each has its own `Token` (a new UUID).

| Edit | Entry |
|---|---|
| New bookmark | `{Type: Add, BookmarkType: Leaf, BookmarkUUID, BookmarkServerID}`; the item gets `Sync: {ServerID}`, a new uppercase UUID, and `dateAdded`, which every item Safari writes carries |
| Delete | `{Type: Delete, BookmarkType, BookmarkUUID, BookmarkServerID, DeletedBookmarkSyncData}` from the item's `Sync`; a folder needs one for everything under it too |
| Rename | `{Type: Modify, BookmarkType, BookmarkUUID, BookmarkServerID, ChangedAttributes: [Title]}` |

**The Add must name its record.** Safari, open, writes an Add without one and names it itself. With
Safari closed the agent does not: measured 2026-09-30, an Add without `BookmarkServerID` sat on the list
through repeated wake-ups, where both tests that named the record were uploaded within seconds. A
bookmark of Luna's still waiting without a name is given one on the next run.

"Uploaded" means the item has `Sync.Data`. A bookmark removed before it was ever uploaded only loses its pending entries: iCloud has nothing to
delete. Entries are recorded only when the top-level `Sync` has `CloudKitMigrationState`, which is
Safari saying iCloud bookmarks are on.

Luna changes only the bookmarks it added, whose `WebBookmarkUUID`s it keeps in
`safari.lunaBookmarkIDs`; everything else in Favorites is the user's. A page the user already has there
is not added again. Existing bookmarks keep their places and new ones go at the end (a reorder is a move,
which is not recorded). Switching the setting off deletes Luna's bookmarks, recorded the same way.

The first builds kept them in a folder called Luna. Its ID is in `safari.lunaFolderID`; the next run
deletes that folder, by ID only, and puts the bookmarks at the top level.

## The lock and the write

Safari and the agent hold a `lock` folder beside the file while writing, with a `details.plist`
(`LockFileProcessID`, `LockFileProcessName`, `LockFileUsername`, `LockFileDate`, `LockFileHostname` =
the Mac's `IOPlatformUUID`). The agent writes while Safari is closed too, whenever another device
changes a bookmark. So Luna takes the same lock and replaces the file only if it still holds what was
read; otherwise it reads again two seconds later, up to five times. A lock whose process has gone, on
this Mac, is taken over.

## Making the agent upload

The agent uploads in three cases only, read from its own log (`*** Starting CloudKit bookmark sync for
trigger:`): **User Did Update Database** — Safari, or another process holding the private
`com.apple.private.safari.can-use-bookmarks-sync-agent` entitlement, edited its bookmarks; **Received Push
Notification** — iCloud reported a change from another device; and its timers. Measured 2026-09-30, none
of these started it:

- the distributed notifications Safari's framework posts (`WebBookmarksDidReloadDistributedNotification`
  and two more) — an early test that seemed to work had been caught by a push a minute later;
- Darwin notifications from Safari's code (`com.apple.bookmarks.BookmarksFileChanged` and three more);
- a message to its Mach service, which does start the agent, and whose connection it then refuses for
  the missing entitlement;
- a network drop: `BookmarkSyncNetworkConnectivity` is registered only while a sync is waiting for a
  network, not as a standing trigger.

Only the five binaries in `Safari.app` and its extensions hold the entitlement. So Luna has Safari make
the edit (`SafariSyncNudge`), after any write that queued entries:

1. If Safari is not running, it is started with `activates = false, hides = true`: no window, no focus,
   only its Dock icon for a few seconds.
2. `osascript`: `add reading list item "https://luna.invalid/safari-sync" with title "Luna"`. A new
   item is an edit; re-adding one already in the list is not, and nothing uploads.
3. Luna waits until that item has `Sync.Data`: the agent uploads the whole list at once, Luna's entries
   with it. Measured: about two seconds.
4. Safari is quit if Luna started it, and the item is taken out of the file with a Delete entry, which
   goes up with the next upload. With Safari open, it is left for the next write to take out.

Sending Apple events needs `com.apple.security.automation.apple-events` (hardened runtime) and
`NSAppleEventsUsageDescription`; macOS asks the user once.

## Permissions

`~/Library/Safari` is protected: Luna needs **Full Disk Access**, which only the user can grant. Without
it the Settings page shows a line with **Open Privacy Settings…**, and Luna tries again when it is next
brought to the front.

macOS keeps **one** Full Disk Access entry per app ID, for one signature. Any other copy of Luna that
reaches into `~/Library/Safari` replaces it with an entry of its own, switched off, and the signed build
loses access: measured 2026-09-30, a Debug build, an old disk image and a test run each did this. So the
feature runs in Release builds only (`#if !DEBUG` in `AppDelegate`), and the signed build should be run
from one place, `/Applications`.

## Limits

- Safari's internal format, not an interface: a Safari update can change it. The tests pin the format
  Luna writes; a two-device check is the only proof it still lands.
- The Favorites tiles first, named by host unless the user named them (a tile's page title changes
  with every visit), then pinned tabs, flat, in sidebar order across Spaces; Luna's folders inside the
  pinned section are not mirrored.
- A Luna bookmark the user deletes in Safari comes back while the tab is still pinned. History is not sent at all.
