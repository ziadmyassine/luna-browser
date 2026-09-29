# iCloud sync: implementation plan (TODO §31.2–§31.12)

Build agents work from this file alone. Background and spike results: `docs/SYNC.md`.
Work style: every step starts with a failing test, then the smallest code that passes it.

## Fixed decisions (do not relitigate)

- CloudKit **private** database, container `iCloud.dev.novapps.luna`, team `FUUYR6KRSH`, bundle ID `dev.novapps.luna`. The build is Developer ID signed and **not sandboxed**. The spike passed on 2026-09-27 and is merged into the main checkout (uncommitted).
- A Developer ID profile can only use the **Production** environment, and Production has no just-in-time schema. Record types are created in Development (§2) and deployed to Production by hand.
- Sync is **opt-in**. It stays off until the user turns it on, even when the Mac is signed into iCloud.
- The first release syncs:
  - Spaces, pinned tabs, the Today-tab list and Favorites
  - per-site settings
  - key remaps and general settings
  - typed and bookmarked history (§31.5b)
  - open tabs across devices (§31.6)
- Bookmarks and boosts do not exist yet. Zones are designed so they can join later; do not build them.
- **Per-site zoom is not persisted today** (`UI/Browser/BrowserSession+Commands.swift`, the `pageZoom` comment). It gets a reserved schema field and no code.
- Cookies, logins and website storage never sync. URLs, titles and other user content go in `encryptedValues`.
- Local-first. Luna works fully with iCloud off or unavailable, and a failure shows as a quiet status line, never a modal.
- `BrowserKit/` imports no AppKit (`Tools/check-no-appkit.sh`). CloudKit and CryptoKit are allowed there.
- Site settings stay **global** (§5.9 is not done first). A site-setting record is keyed by host only.
- Private windows never sync.

## Facts from the code that shape the design

1. **The session writes its in-memory copy back to disk.** `BrowserSession.write(tab)` (`UI/Browser/BrowserSession+Tabs.swift`) saves the whole row through the `enqueue` write chain. An incoming change applied only to the database would be overwritten by the next local write. Incoming changes must therefore go through that chain (step S10).
2. **Some `siteSettings` columns are created on first use** by `ensurePermissionColumns` (`BrowserStore+SitePermissions.swift`) and `ensureBlockingColumns` (`Blocking/BrowserStore+Blocking.swift`). A trigger cannot name a column that may not exist, so v12 creates them up front.
3. **`places.id` and `visits.id` are local AUTOINCREMENT integers.** They are never reused on one Mac, but they differ between Macs.
4. **Tab rows are written on every activation and navigation** (`lastActiveAt`, `interactionState`). Change tracking must ignore the columns that only matter on this Mac.
5. **Settings live in `UserDefaults`,** spread across the app. The default table is in `Features/Settings/Shell/SettingsDefaults.swift`; other keys are in `SettingsStore.swift`, `General.swift`, `Appearance.swift`, `Downloads.swift`, `PasswordSettings.swift`, `PopupPolicy.swift`, `ContentBlocker.swift` and `WebViewFactory.swift`. Remaps are `luna.shortcut.<commandID>` strings (`App/KeyBindings.swift`).
6. **The Keychain does not depend on the bundle ID.** `CredentialStore` marks Luna's items with `kSecAttrCreator` `'Luna'`, a constant (`BrowserKit/Sources/BrowserKit/Passwords/CredentialStore.swift`). The item ACLs follow the code signature, so the first Developer ID launch may ask for Keychain access to items written by the ad-hoc build. That is expected; check it by hand in S0.

---

## 1. Architecture

**Where the engine lives: `BrowserKit/Sources/BrowserKit/Sync/`**
- CloudKit is Foundation-level and works on iOS, so this keeps §25.5 possible.
- The engine needs the store's internal `pool`.

**What the app layer owns:**
- the entitlement check (`SecTask` is macOS-only)
- the device name (`Host.current().localizedName`)
- the UserDefaults allowlist
- applying incoming changes to the session
- the Settings UI.

| File | Holds |
|---|---|
| `Sync/SyncRecord.swift` | A `Sendable` value type `SyncRecord` (recordType, recordName, zone, `schemaVersion`, fields `[String: SyncValue]`, `systemFields: Data?`). The whole sync core works on this type, never on `CKRecord`, which is not `Sendable` under Swift 6. |
| `Sync/SyncCloudKit.swift` | **The only file that uses `CKSyncEngine`, `CKContainer` or `CKRecord`.** It converts `CKRecord` ↔ `SyncRecord`, holds the thin `CKSyncEngineDelegate` adapter, and is the live `SyncEngineControl`. |
| `Sync/SyncEngineControl.swift` | The test seam, a protocol with `add(pending: [SyncPendingChange])`, `remove(pending:)`, `addZoneSaves(_:)`, `addZoneDeletes(_:)`, `fetchChanges()`, `sendChanges()`. |
| `Sync/SyncCoordinator.swift` | An actor holding all the logic: outbox → pending changes, building a batch, events, conflicts, account states, status. |
| `Sync/SyncMapping.swift` | Row ↔ `SyncRecord`, one mapper per record type. Pure. |
| `Sync/SyncMerge.swift` | The conflict rules. Pure. |
| `Sync/SyncSecret.swift` | The per-account HMAC secret and site record names. |
| `Sync/SyncStatus.swift` | The status enum and its status-line strings. |
| `Sync/DefaultsSync.swift` | Diffs `UserDefaults` against the `syncedDefaults` table. |
| `Store/Schema+Sync.swift` | The v12 migration and triggers. |
| `Store/BrowserStore+Sync.swift` | Reads the outbox, seeds zones, applies incoming changes, stores system fields. |
| `Features/Sync/SyncedDefaults.swift` (app) | The allowlist, and applying incoming settings with the right notifications. |
| `App/AppDelegate+Sync.swift` (app) | The entitlement gate, starting the engine, fetching on activate. |
| `UI/Browser/BrowserSession+Sync.swift` (app) | Applies incoming changes to the in-memory session. |

**The seam (tests run without iCloud, and CI has no signing)**
- The adapter translates each `CKSyncEngine.Event` into a coordinator call that takes plain values:
  - `fetched(modifications:deletions:)`
  - `sent(saved:failed:)`
  - `accountChanged(_:)`
  - `zonesDeleted(_:reason:)`
  - `stateUpdated(Data)`
  - `fetchFinished()` (`didFetchChanges`: ends the turn-on fetch, stamps `lastSyncedAt`)
  - `failed(_:)`, for an error outside one record's save
- `nextRecordZoneChangeBatch` asks `coordinator.records(for:)`. If a record can no longer be built, it is removed from the pending changes and the batch returns nil for it.
- Tests drive the coordinator through `FakeSyncEngine` (in `BrowserKit/Tests/BrowserKitTests/`).
- **Nothing in `swift test` or `make test` may construct `CKContainer` or `CKSyncEngine`.** Without the entitlement, constructing either crashes.
- The adapter is about 80 lines of translation. It is proven by the probe self-test (S11) and the two-Mac run (S14).

**Hooking the coordinator up to the app**
- Two closures send incoming changes to the app:
  - `applyInbound: @Sendable (SyncChangeSet) async throws -> Void`. By default it writes straight to the store (tests and no session). The app replaces it with a route through `BrowserSession`'s `enqueue` chain.
  - `applySettings`, for settings.
- `status: @MainActor (SyncStatus) -> Void` reports the status to the UI.

**Change tracking: SQLite triggers writing to `syncOutbox`, not store hooks**
- Triggers catch every writer: the session, the importer, `BrowserStore+Jars`, migrations and FK cascade deletes (SQLite fires DELETE triggers for cascades).
- The outbox survives a crash.
- Store hooks would miss some writers, and GRDB's `TransactionObserver` reports rowids and loses the key on delete.
- Table: `syncOutbox(recordType TEXT, localKey TEXT, zone TEXT, isDelete BOOL, changedAt DATETIME, PRIMARY KEY(recordType, localKey))`, written with `INSERT OR REPLACE`.
- `localKey` is:
  - `hex(id)` for UUID blobs
  - the host for site settings
  - `places.id` for history
  - the defaults key for settings.
- Every trigger has this guard:
  `WHEN (SELECT applyingRemote FROM syncControl) = 0 AND EXISTS (SELECT 1 FROM syncZones WHERE zone = '<zone>' AND enabled)`
- Update triggers are `AFTER UPDATE OF <synced columns>` and also require `OLD.c IS NOT NEW.c` for at least one synced column, because GRDB's upsert sets every column.
- Synced columns, which cause outbox rows:
  - **spaces:** `name`, `symbolName`, `gradient`, `imageData`, `order`
  - **tabGroups:** `spaceID`, `name`, `symbolName`, `kind`, `order`
  - **tabs:** `spaceID`, `groupID`, `kind`, `order`, `archivedAt`, `url`, `title`, `customTitle`, `customSymbolName`, `pinnedURL`
  - **siteSettings:** every column except `updatedAt`
  - **visits:** `AFTER INSERT` when `NEW.type IN ('typed','bookmarked') AND NEW.syncOrigin IS NULL`. The outbox key is `placeId`.
- Local-only columns, which never trigger:
  - tabs: `interactionState`, `lastActiveAt`, `hasUnread`, `faviconKey`, `themeColor`, `isDormant`, `parentTabID`
  - spaces: `dataStoreIdentifier`
  - tabGroups: `isCollapsed`
- Incoming changes are applied in one transaction with `applyingRemote = 1`, which stops the echo.
- With sync off, nothing is written to the outbox. Turning a zone on seeds it with one `INSERT … SELECT`. History seeds only places with a typed or bookmarked visit in the last 90 days.
- Settings: `DefaultsSync` inserts outbox rows itself (step S9).

**v12 tables.** All live in `luna.sqlite`, so wiping the database wipes sync state with it.

| Table | Contents |
|---|---|
| `syncMeta(key PK, value BLOB)` | `engineState` (the JSON-encoded `CKSyncEngine.State.Serialization`, rewritten on every `.stateUpdate`), `deviceID` (UUID), `userRecordName`, `lastSyncedAt`, `secret` |
| `syncRecords(recordType, recordName PK, localKey, zone, systemFields BLOB)` | The last server system fields for each record (`encodeSystemFields`) |
| `syncParked(recordType, recordName PK, record BLOB)` | Incoming records whose parent Space or group has not arrived |
| `syncZones(zone PK, enabled BOOL)` | Which zones are on. Empty means sync is off. |
| `syncControl(id = 1, applyingRemote INT)` | The echo guard |
| `syncPresence(deviceID PK, name, updatedAt, tabs BLOB)` | Other Macs' open tabs. Needed because the engine delivers only changes, so they would be gone after a relaunch otherwise. |
| `syncedDefaults(key PK, value BLOB, modifiedAt)` | The last synced value of each allowlisted setting |
| `visits.syncOrigin TEXT NULL` | NULL for a local visit, otherwise the HistoryEntry recordName it came from |

**Record IDs**

| Type | `recordName` | Why |
|---|---|---|
| Space, TabGroup, Tab | UUID string of `id` | Already the same on every Mac |
| SiteSetting | `site-` + first 26 chars of base32(HMAC-SHA256(secret, host)) | The same on every Mac, and does not show the host. A plain hash of a hostname is easy to reverse by dictionary. |
| Setting | the defaults key (e.g. `search.engine`, `luna.shortcut.newTab`) | Not sensitive |
| HistoryEntry | `<deviceID>-<places.id>` | Each Mac writes only its own history records, so local integer ids are fine and history never conflicts. Only the number of places is visible. |
| Device | `deviceID` | One writer |
| SyncSecret | `secret` | Fixed name, so two Macs creating it at once shows up as `serverRecordChanged` |

- The secret is 32 random bytes in `encryptedValues`, in the `Meta` zone.
- Nothing keyed by the secret is sent until the secret has been fetched or saved successfully.

**Zones.** Each zone matches one switch. Zones are created at runtime and need no schema.

| Zone | Record types | Switch |
|---|---|---|
| `Spaces` | Space, TabGroup, Tab | Spaces, tabs and Favorites |
| `Sites` | SiteSetting | Site settings |
| `Settings` | Setting (remaps included) | Settings and shortcuts |
| `History` | HistoryEntry | Typed history (needs Spaces: visits belong to Spaces) |
| `Devices` | Device | Tabs on other Macs |
| `Meta` | SyncSecret | Always on while sync is on |
| later: `Bookmarks`, `Boosts` | — | A new zone and record type, deployed when those features exist |

Favorites and pinned tabs are `tabs.kind` values in one table with foreign keys. Separate zones would mean deleting and re-creating a record whenever a tab changes kind, so all tabs share one zone.

**How incoming history is applied**
- Upsert the place by URL, without incrementing `visitCount`.
- Then run `DELETE FROM visits WHERE syncOrigin = :recordName` and insert the record's visits with that `syncOrigin`.
- Visits whose `spaceID` is unknown locally are dropped.
- A deleted HistoryEntry deletes the visits with that `syncOrigin`.
- `inputHistory` does not sync.

---

## 2. Schema: commit `CloudKit/Schema.ckdb`

**Encryption rule:** user content goes in `encryptedValues`. Only structure is plain: `schemaVersion`, `modifiedAt`, id strings, `kind`, `position`, `createdAt`, `archivedAt`.
- References are plain STRING ids, never `CKRecord.Reference`, which brings cascade and sharing behaviour Luna does not want.
- No indexes are needed, because `CKSyncEngine` reads zone changes and never queries. `___recordID QUERYABLE` is there only so records can be browsed in the Console.
- The field is named `position` rather than `order`, to avoid a keyword clash.

```
DEFINE SCHEMA

  RECORD TYPE Space (
    "___recordID"   REFERENCE QUERYABLE,
    schemaVersion   INT64,
    modifiedAt      TIMESTAMP,
    position        INT64,
    name            ENCRYPTED STRING,
    symbolName      ENCRYPTED STRING,
    gradient        ENCRYPTED STRING,
    image           ENCRYPTED BYTES,
    GRANT WRITE TO "_creator", GRANT CREATE TO "_icloud", GRANT READ TO "_world"
  );

  RECORD TYPE TabGroup (
    "___recordID"   REFERENCE QUERYABLE,
    schemaVersion   INT64,
    modifiedAt      TIMESTAMP,
    spaceID         STRING,
    kind            STRING,
    position        INT64,
    name            ENCRYPTED STRING,
    symbolName      ENCRYPTED STRING,
    GRANT WRITE TO "_creator", GRANT CREATE TO "_icloud", GRANT READ TO "_world"
  );

  RECORD TYPE Tab (
    "___recordID"   REFERENCE QUERYABLE,
    schemaVersion   INT64,
    modifiedAt      TIMESTAMP,
    spaceID         STRING,
    groupID         STRING,
    kind            STRING,
    position        INT64,
    createdAt       TIMESTAMP,
    archivedAt      TIMESTAMP,
    url             ENCRYPTED STRING,
    title           ENCRYPTED STRING,
    customTitle     ENCRYPTED STRING,
    customSymbolName ENCRYPTED STRING,
    pinnedURL       ENCRYPTED STRING,
    GRANT WRITE TO "_creator", GRANT CREATE TO "_icloud", GRANT READ TO "_world"
  );

  RECORD TYPE SiteSetting (
    "___recordID"   REFERENCE QUERYABLE,
    schemaVersion   INT64,
    modifiedAt      TIMESTAMP,
    host            ENCRYPTED STRING,
    zoom            ENCRYPTED DOUBLE,
    automaticPictureInPicture ENCRYPTED INT64,
    localNetwork    ENCRYPTED INT64,
    savePasswords   ENCRYPTED INT64,
    popups          ENCRYPTED INT64,
    blockingDisabled ENCRYPTED INT64,
    insecureAllowed ENCRYPTED INT64,
    GRANT WRITE TO "_creator", GRANT CREATE TO "_icloud", GRANT READ TO "_world"
  );

  RECORD TYPE Setting (
    "___recordID"   REFERENCE QUERYABLE,
    schemaVersion   INT64,
    modifiedAt      TIMESTAMP,
    value           ENCRYPTED BYTES,
    GRANT WRITE TO "_creator", GRANT CREATE TO "_icloud", GRANT READ TO "_world"
  );

  RECORD TYPE HistoryEntry (
    "___recordID"   REFERENCE QUERYABLE,
    schemaVersion   INT64,
    modifiedAt      TIMESTAMP,
    url             ENCRYPTED STRING,
    title           ENCRYPTED STRING,
    visits          ENCRYPTED BYTES,
    GRANT WRITE TO "_creator", GRANT CREATE TO "_icloud", GRANT READ TO "_world"
  );

  RECORD TYPE Device (
    "___recordID"   REFERENCE QUERYABLE,
    schemaVersion   INT64,
    modifiedAt      TIMESTAMP,
    name            ENCRYPTED STRING,
    tabs            ENCRYPTED BYTES,
    GRANT WRITE TO "_creator", GRANT CREATE TO "_icloud", GRANT READ TO "_world"
  );

  RECORD TYPE SyncSecret (
    "___recordID"   REFERENCE QUERYABLE,
    schemaVersion   INT64,
    secret          ENCRYPTED BYTES,
    GRANT WRITE TO "_creator", GRANT CREATE TO "_icloud", GRANT READ TO "_world"
  );
```

**What the less obvious fields hold**

| Field | Contents |
|---|---|
| `SiteSetting` flags | `INT64` as tri-state: absent means unset, 0 means off, 1 means on |
| `SiteSetting.zoom` | Reserved and never written until per-site zoom is persisted |
| `Setting.value` | A property list holding one value; the record is deleted when the key is removed |
| `HistoryEntry.visits` | JSON `[{spaceID, at, kind}]`: the newest 10 typed or bookmarked visits from this Mac only |
| `Device.tabs` | JSON `[{spaceID, url, title}]`, at most 50; private, `about:blank` and `luna://` tabs are skipped |
| `Space.gradient` | The JSON of `GradientPair` |
| `Space.image` | The existing `imageData` bytes |

**Import (Development only), then deploy by hand**
```
xcrun cktool save-token --type management    # token: CloudKit Console › Settings › Tokens
xcrun cktool export-schema   --team-id FUUYR6KRSH --container-id iCloud.dev.novapps.luna --environment development --output-file /tmp/current.ckdb
xcrun cktool validate-schema --team-id FUUYR6KRSH --container-id iCloud.dev.novapps.luna --environment development --file CloudKit/Schema.ckdb
xcrun cktool import-schema   --team-id FUUYR6KRSH --container-id iCloud.dev.novapps.luna --environment development --file CloudKit/Schema.ckdb
```
- Check the flags with `xcrun cktool help import-schema`.
- Keep the exported `Users` type in the committed file: merge `/tmp/current.ckdb`'s `Users` block into `Schema.ckdb`.
- Deploy to Production in CloudKit Console › Schema › **Deploy Schema Changes**.
- **The Production schema can only grow.** Types and fields can never be removed or renamed, so deploy only after S8 is green.

**Schema versioning (§31.9).** Write this into `docs/SYNC.md`:
- Every record carries `schemaVersion`, which is 1 now.
- Readers ignore fields and record types they do not know, and never delete an unknown record type.
- A write sets only the fields this version knows. It starts from the stored `systemFields`, so the server keeps fields a newer client added. It never sets a field it does not know to nil.
- A write never lowers `schemaVersion`: it writes max(own, stored).
- A field's meaning never changes. New behaviour gets a new field name, which also matches Production being additive-only.

---

## 3. Conflict rules (§31.4)

A save that fails with `serverRecordChanged` is merged into the server's record (which carries the latest system fields) and saved again. "Local time" means the outbox row's `changedAt`, so the domain tables need no new `updatedAt` columns.

| Type | Rule |
|---|---|
| Space | Last writer wins on the whole record (`modifiedAt` against local `changedAt`). Delete beats edit. `dataStoreIdentifier` never syncs: an incoming Space gets a fresh local cookie store through `upsert`'s guard. |
| TabGroup | Last writer wins. Delete beats edit, and its tabs fall back to loose (`ON DELETE SET NULL`), as they do locally. |
| Tab | Last writer wins. Delete beats edit. An incoming `archivedAt` is ignored if this Mac's `lastActiveAt` is later, and the unarchived state is sent back, so one Mac's idle clock never archives a tab in use on another. An incoming `url`/`title` is **not** applied to a tab with a live web view on this Mac; structural fields still are. Clashing `position` values heal through the existing renumber-on-load (ties broken by `createdAt`). `parentTabID` stays local. |
| Favorites | Union, because each Favorite is its own record. More than 12 arriving in a Space: the extras are demoted to pinned locally, deterministically by (`position`, `createdAt`), and the demotion is not sent back. |
| SiteSetting | The four permission flags, field by field: a set value beats an unset one. If both are set, the newer `modifiedAt` wins. `blockingDisabled` and `insecureAllowed` are always written as 0 or 1 and follow the newer record (last writer wins): they are `NOT NULL` locally, so with set-beats-unset, once any Mac turned blocking off for a site no Mac could turn it back on. |
| Setting | Last writer wins per key. |
| HistoryEntry, Device | One writer per record, so they never conflict. If one ever does, local wins. |
| SyncSecret | The server always wins. |
| Unknown type or newer `schemaVersion` | Ignore unknown fields, never lower `schemaVersion`, never nil an unknown field. |
| Turning sync on (first time or again) | Fetch first. iCloud wins for any record it has. Then upload local rows that have no `systemFields`. Rows that have `systemFields` but did not arrive in that fresh full fetch are deleted locally. |
| The seed Space | On the first fetch after turning sync on, if iCloud already has Spaces, drop this Mac's seed Space when it was never renamed (still `"Personal"`, as written by `seedIfEmpty`) and has no tabs. Otherwise keep both Spaces. |

**Deletions without tombstone records:** the stored `systemFields` prove a row once existed on the server.
- An offline Mac that edits a record deleted elsewhere saves with an old change tag and gets `unknownItem`, and the row is deleted locally.
- A row that was not edited gets the deletion on its next fetch.
- An expired change token loses deletions, but a stale row is never uploaded again unless it is edited, and that edit then hits `unknownItem`.

This replaces §31.4's "30-day grace"; see the TODO corrections at the end.

---

## 4. Account and availability states (§31.7)

None of these shows a modal. Each ends in the status line (§5), and Luna keeps working with local data.

| State | Detected by | Behaviour | Status line |
|---|---|---|---|
| Build lacks the iCloud entitlement (Debug, tests, CI) | App gate: `SecTaskCopyValueForEntitlement(com.apple.developer.icloud-container-identifiers)` | No engine; master switch disabled | "iCloud sync needs the signed build." |
| Sync off (default) | `syncZones` empty | No `CKContainer`, no `cloudd` traffic | "iCloud sync off" |
| No account, or restricted | `accountStatus` | Engine paused | "Sign in to iCloud to sync." |
| Temporarily unavailable | `accountStatus` / `CKError.accountTemporarilyUnavailable` | Quiet retry on activate | "iCloud is unavailable right now." |
| Signed out mid-session | `.accountChange(.signOut)` | Wipe sync state (`syncMeta` except `deviceID`, `syncRecords`, `syncOutbox`, `syncParked`, `syncPresence`); keep local data | "Sign in to iCloud to sync." |
| **Switched account** | `.accountChange(.switchAccounts)`, or a `userRecordName` different from the stored one | **Wipe sync state, keep local data, turn the master switch off.** Nothing is uploaded to the new account until the user turns sync on again. | "Signed into a different iCloud account." |
| iCloud turned off for Luna | `notAuthenticated` | As no account | "Sign in to iCloud to sync." |
| Storage full | `quotaExceeded` | Keep the outbox; the engine retries | "iCloud storage is full." |
| Offline | `networkUnavailable` / `networkFailure` | The engine retries | "Offline — will sync when connected." |
| Zone missing | `zoneNotFound` on save | Save the zone again and re-queue | none |
| Data removed on another Mac | zone deletion with reason `.deleted` | Turn master off, wipe sync state, keep local data | "Luna's iCloud data was removed from another Mac." |
| Encrypted data reset | reason `.encryptedDataReset` | Wipe `systemFields` and upload everything again | none |
| Up to date | `lastSyncedAt` | none | "Synced 2 min ago" (relative) |

Push: `CKSyncEngine` needs the push entitlement (H2) to hear other Macs' changes at once. The app also calls `fetchChanges()` on every app activation, so without push, changes still arrive then.

---

## 5. Settings UI (§31.10)

**The account row**
- Where: the top of the Settings sidebar, directly under `SettingsSearchField` and above General, in the style of Raycast.
- What it shows, with no plate of its own:
  - an avatar circle
  - the user's name in bold
  - the word "iCloud" under it, as macOS's settings put "Apple Account" under the name.
- It is **not** in `SettingsSectionRegistry.all`, so the ⌘1…⌘8 numbering is unchanged and About stays where it is.
- Name: `NSFullUserName()`. CloudKit no longer exposes the user's name, because user discoverability is deprecated.
- Avatar: the macOS login picture, read from OpenDirectory `kODAttributeTypeJPEGPhoto` on the current user's record, or from the CSIdentity image. If neither exists, draw initials on a `Tokens` colour. Never touch Contacts; there must be no permission prompt.
- Status: `SyncStatus`'s line is the row's tooltip and part of its accessibility label, not its subtitle. **Changed 2026-09-29:** it was the subtitle, and every line but "iCloud sync off" and "Syncing…" was cut off at the column's width. The page's own status row shows it in full.
- **It is dressed as a list row** (changed 2026-09-29; it was a bordered plate that swelled like a button). It answers the pointer the way the section rows under it do, per CLAUDE.md "List rows are not buttons":
  - hover: `RowPillView(role: .hover)`
  - while the account page is showing: `RowPillView(role: .selected)`, and the list's selection pill fades out
  - it opens its page on mouse-down, as a section row does, and does not swell
  - the name is in full-strength ink only while its page is showing; the word under it is `Text.tertiary`.
- It is not in `Tests/Design/ButtonFeedbackTests.swift`; that file's header says why.
- Accessibility: role radio button, value on while its page is showing; label "iCloud, <name>, <status>".

**The account page** (`Features/Settings/Sections/Account.swift`), opened by the row. Rows in order:
1. **Sync with iCloud**: a `SystemSwitch`, off by default.
2. The status line, in secondary text.
3. Five zone switches (`SystemSwitch`): Spaces, tabs and Favorites · Site settings · Settings and shortcuts · Typed history · Tabs on other Macs. They are disabled while the master switch is off, and Typed history is also disabled while Spaces is off.
4. The line "Cookies, logins and website data stay on this Mac."
5. **Sync Now**: `SettingsPushButton`. It runs `fetchChanges()` then `sendChanges()`.
6. **Remove Luna Data from iCloud…**: `SettingsPushButton(isDestructive: true)`. It asks through `SettingsHost.confirm`, then deletes every zone, wipes sync state and turns sync off.

`SystemSwitch` and `SettingsPushButton` are already registered in `ButtonFeedbackTests`.

**`docs/SETTINGS-SPEC.md` needs:**
- the account row in §2 (placement, plate, content, button behaviour)
- the account page in §3
- the "Sync — not even a disabled row" line removed from §9.

**Settings that sync** (allowlist in `Features/Sync/SyncedDefaults.swift`):
- appearance: `appearance.theme`, `luna.chromeLayout`, `luna.tabsPosition`, `luna.searchBarPlacement`, `luna.macWindowCorners`
- search: `search.engine`, `search.customEngineURL`, `search.suggestions`, `search.settingsResults`, `search.shortcutResults`
- general: `luna.autoArchiveHours`, the confirm-quit key (`General.swift`), `downloads.autoOpen`
- privacy and pages: `blocking.httpsOnly`, the blocker category enabled keys (`ContentBlocker.Key.enabled`), the popup mode and show-address keys (`PopupPolicy`), `advanced.userAgent`, `advanced.userAgentCustom`
- the password switches for enabled, offer-to-save and generate
- every `luna.shortcut.*` key.

**Settings that never sync:**
- `downloads.directory`, sidebar width, `settings.lastSection`, `luna.activeSpaceID`, onboarding, updates and extension keys, `appearance.glassOptimisation`, `luna.pendingStoreRemovals`, blocker hashes and chunks
- **settings that would weaken security on another Mac:** `advanced.allowControl` and require-Touch-ID (`PasswordSettings` requireAuthentication).

**Applying an incoming setting:**
1. Write it to `UserDefaults.standard`.
2. Post `Settings.didChange` and `KeyBindings.didChange`.
3. Call `SearchSettings.reload()` and `AppearanceSection.applyStoredTheme()` (the same refresh `SettingsDefaults.restoreAll` does).

**Outgoing settings:** on `UserDefaults.didChangeNotification`, debounced by 1 s, diff the allowlist against `syncedDefaults`.

**Tabs on other Macs (§31.6, §30.21):** a "Tabs on Other Macs" submenu in the History menu (`App/MainMenu.swift` `historyMenu()`).
- One section per Mac, named with its device name.
- Macs whose `updatedAt` is more than 30 days old are hidden, and so is this Mac.
- This Mac publishes its own tabs on app activation and when its set of tabs changes, at most once a minute.
- Turning sync off deletes this Mac's Device record.

---

## 6. Steps

Each step begins by writing the failing test(s) named, then the code.

| # | Step | First failing test(s) | Files | By hand |
|---|---|---|---|---|
| S0 | Check the Keychain survives the bundle-ID change. **Already confirmed while planning:** the creator is the constant `'Luna'`. No migration code. | None | none | Launch the signed build once and fill a saved password. A single Keychain access prompt for items from the ad-hoc build is expected: choose Always Allow. |
| S1 | Value boundary and CloudKit canary | `CloudKitBoundaryTests`: `encryptedValues` round-trips on a `CKRecord` created with no container; `encodeSystemFields` round-trips and keeps `recordChangeTag`; a record rebuilt from system fields with only known keys set reports only those in `changedKeys()`; `CKError(.serverRecordChanged)` with a server record is readable; `SyncRecord` ↔ `CKRecord` keeps every field and its encryption | `Sync/SyncRecord.swift`, conversion half of `Sync/SyncCloudKit.swift` | none |
| S2 | Schema v12 | `StoreMigrationTests`: v12 creates the six `siteSettings` flag columns up front; creates every sync table and `visits.syncOrigin`; a v11 fixture migrates; migrating twice is harmless | `Store/Schema+Sync.swift`, `Store/Schema.swift` (register `v12`); delete `ensurePermissionColumns` and `ensureBlockingColumns` and their calls | none |
| S3 | Triggers and outbox | `SyncOutboxTests`: renaming a Space with the zone on gives one row; a change to only `lastActiveAt` or `interactionState` gives none; `applyingRemote = 1` gives none; the zone off gives none; deleting a Space adds deletes for its tabs; a typed visit gives a History row and a link visit none; turning a zone on seeds every row (History: last 90 days only) | `Schema+Sync.swift`, `Store/BrowserStore+Sync.swift` | none |
| S4 | Record mapping and the committed schema file | `SyncMappingTests`: round-trip for each type; `url`/`title`/`host`/`name`/`value`/`tabs`/`visits` only in encrypted fields; a newer `schemaVersion` is kept; an unknown field is never set. `SyncSchemaFileTests`: parse `CloudKit/Schema.ckdb` (located via `#filePath`) and assert every field each mapper writes is declared, with matching `ENCRYPTED` | `Sync/SyncMapping.swift`, `CloudKit/Schema.ckdb` | **H1a** |
| S5 | Secret and site record names | `SyncSecretTests`: the same secret and host give the same name; a different secret gives a different name; the name never contains the host; nothing keyed is sent before the secret is settled; a race resolves to the server's secret | `Sync/SyncSecret.swift` | none |
| S6 | Applying incoming changes | `SyncApplyTests`: Spaces, then groups, then tabs in one batch; a missing parent is parked and applied when it arrives; deletions applied; a newer pending local edit is skipped; history replaces visits by `syncOrigin`; a visit for an unknown Space is dropped; an incoming Space gets a fresh non-zero `dataStoreIdentifier`; nothing reaches the outbox | `BrowserStore+Sync.swift` | none |
| S7 | Merge rules | `SyncMergeTests`: one test per row of §3, including the archive-against-activity rule, the site-settings field merge, the turn-on reconciliation and dropping the seed Space | `Sync/SyncMerge.swift` | none |
| S8 | Coordinator, seam and fake | `SyncCoordinatorTests` with `FakeSyncEngine`: outbox becomes pending changes; the batch is built from current rows (a row that is gone is removed from pending); a successful save clears the outbox row only if `changedAt` has not moved; `serverRecordChanged` merges and re-queues; `unknownItem` deletes locally; `zoneNotFound` saves the zone again; `quotaExceeded`, offline and no-account set the status; state is saved on `stateUpdated` and handed back on start; sign-out wipes; switching account wipes and turns the master off; zones deleted elsewhere turn sync off; Remove All deletes the zones and wipes | `Sync/SyncCoordinator.swift`, `Sync/SyncEngineControl.swift`, `Sync/SyncStatus.swift`, `BrowserKit/Tests/BrowserKitTests/FakeSyncEngine.swift` | none |
| S9 | Settings and shortcuts | `SyncedDefaultsTests` (app tests, `Tests/Settings/`): an allowlisted change reaches the outbox; a key outside the allowlist does not; `advanced.allowControl` and require-Touch-ID never sync; an incoming value is written and posts both notifications; an incoming value is not echoed back; a removed key deletes its record | `Sync/DefaultsSync.swift`, `Features/Sync/SyncedDefaults.swift` | none |
| S10 | The session applies incoming changes | `SessionRemoteChangeTests` (`Tests/Browser/`): a remote rename, reorder or new tab updates `TabList`; the store write runs on `enqueue` after an already-queued stale write; a live tab keeps its URL; a remote Space delete goes through the session's teardown and jar-removal path with no undo; a 13th Favorite is demoted and not sent back; a remote archive loses to later local activity | `UI/Browser/BrowserSession+Sync.swift` | none |
| S11 | Live engine, wiring, gate and probe self-test | `SyncGateTests` (app tests): the unsigned test host reports "iCloud sync needs the signed build" and never constructs `CKContainer`; sync off means no engine; activation calls `fetchChanges` only when sync is on | adapter half of `Sync/SyncCloudKit.swift`; `App/AppDelegate+Sync.swift`; `App/CloudKitProbe.swift` extended to save, fetch and delete one record of each type in a throwaway zone (keep the probe; it is the Production schema check) | **H1b, H2**, then `make signed` and `Luna --cloudkit-probe` must print ok for all eight types |
| S12 | Tabs on other Macs | `DevicePresenceTests`: capped at 50; private, `about:blank` and `luna://` tabs skipped; at most one publish a minute; this Mac excluded; Macs older than 30 days hidden; the History menu's "Tabs on Other Macs" lists the others and opens a tab on click | presence code in `Sync/SyncCoordinator.swift`; `App/MainMenu.swift` | none |
| S13 | Account row and page | `SettingsAccountRowTests`: the row sits under the search field and above General; it is not in `SettingsSectionRegistry.all` (⌘ numbering unchanged); shows `NSFullUserName()`; falls back to initials without a picture; the subtitle says iCloud and the tooltip follows each `SyncStatus`; it is dressed as a list row (no plate, no border, the list's pills, no swell); clicking opens the account page and fades the list pill. `AccountSectionTests`: master off by default; zone switches disabled while off; History disabled without Spaces; the cookie line is present; Remove goes through `SettingsHost.confirm`; the master switch is disabled when the gate says unavailable | `Features/Settings/Shell/SettingsAccountRow.swift`, `Features/Settings/Sections/Account.swift`, `Features/Settings/Shell/SettingsWindowController.swift` / `SettingsSectionList.swift` (placement), `Tests/Design/ButtonFeedbackTests.swift` | none |
| S14 | Docs and the two-Mac run | None: this step is documentation | Write the what-syncs table, the §31.9 rule, the schema, the Privacy Policy text for §31.11 and the §31.12 checklist into `docs/SYNC.md`; update `docs/SETTINGS-SPEC.md`; apply the TODO corrections below | **H3.** Ask the user first: a test Apple ID or theirs? |

**By hand**
- **H1a:** get a management token for `cktool`, export the current Development schema, merge in `Users`, then validate and import `CloudKit/Schema.ckdb` into Development (commands in §2).
- **H1b:** CloudKit Console › Schema › Deploy Schema Changes to Production. Do this only after S8 is green, because it cannot be undone.
- **H2:** in the developer portal:
  1. Turn on Push Notifications for App ID `dev.novapps.luna`.
  2. Regenerate the Developer ID profile into `Signing/Luna_Developer_ID.provisionprofile`.
  3. Check that its certificate matches the signing identity (the `security cms` / `shasum` check in `docs/SYNC.md`).
  4. Add `com.apple.developer.aps-environment = production` to `Signing/Luna.entitlements`.
- **H3:** a second Mac on the same Apple ID, running the signed build. It is not notarised yet (§24.4), so open it past Gatekeeper. Run the §31.12 checklist:
  - create, rename, reorder and delete Spaces, tabs, groups and Favorites on both Macs
  - edit offline on both, then reconnect
  - conflicting renames
  - archive on one Mac while the tab is active on the other
  - site settings and shortcuts
  - typed history ranking on the second Mac
  - Tabs on Other Macs
  - account switch (sync turns off)
  - storage full (a full test account)
  - Remove Luna Data from iCloud (the other Mac shows the removed line)
  - a cold restore onto a wiped Mac.

---

## 7. Parallelism

These can run as separate agents at the same time, because they touch different files:

| Wave | Steps in parallel | Why they don't collide |
|---|---|---|
| 1 | S1 (`Sync/SyncRecord.swift`, `Sync/SyncCloudKit.swift`) · S2 then S3 (one agent: `Store/Schema+Sync.swift`, `Store/Schema.swift`, `Store/BrowserStore+Sync.swift`, the two `ensure*` files) · S5 (`Sync/SyncSecret.swift`) | Separate files. S2 and S3 share `Schema+Sync.swift`, so they are one agent in sequence. |
| 2 | S4 (`Sync/SyncMapping.swift`, `CloudKit/Schema.ckdb`) · S7 (`Sync/SyncMerge.swift`) | Both need only S1's `SyncRecord`. H1a can start as soon as S4 is merged. |
| 3 | S6 (`BrowserStore+Sync.swift`, needs S3 and S4) · S13's UI shell (`SettingsAccountRow.swift`, `Account.swift`, against a stub `SyncStatus`) | S13's wiring to the real coordinator waits for S8. |
| 4 | S8 (needs S3–S7) | One agent; it touches the coordinator only. |
| 5 | S9 (settings files) · S10 (`BrowserSession+Sync.swift`) · S12 (presence and `MainMenu.swift`) | Separate files. Each adds only its own closure hook to the coordinator; merge those one at a time. |
| 6 | S11, then S14 | They need the whole chain, H1b and H2. |

`FakeSyncEngine.swift` belongs to S8. Earlier steps test pure functions and the store directly.

---

## 8. Risks

- **Real data from the start.** A Developer ID build only talks to Production, so every test writes to a real private database, and schema mistakes are permanent. The guards are S4's schema-file test, S11's probe self-test, and Remove Luna Data from iCloud.
- **Push may not be enabled.** Without H2, other Macs' changes arrive only on activation or Sync Now.
- **Today tabs in use on two Macs at once** overwrite each other by last-writer-wins. Live tabs ignoring the incoming URL limits this but does not remove it.
- **The Keychain may ask for access once** after the signature changes from ad-hoc to Developer ID (S0).

## 9. Decisions recorded (2026-09-27)

- **The seed Space:** if iCloud already has Spaces, drop this Mac's seed Space when it was never renamed and has no tabs. Otherwise keep both.
- **Account switch:** wipe sync state, keep local data, turn the master switch off.
- **Site settings** stay global, keyed by host.
- **Settings placement:** the account row at the top of the Settings sidebar opens the account page. It is not a numbered page.
- **Tabs on Other Macs** is a submenu of the History menu.
- **Security settings:** `advanced.allowControl` and require-Touch-ID stay on each Mac.
- **Still open:** a test Apple ID or the user's own for H3. Ask at S14.

## 10. TODO corrections (apply in S14)

- **§31.4:** replace "deletions = tombstones with a 30-day grace" with "deletions: stored system fields are the evidence (`unknownItem` on an edit to a deleted record deletes it locally); no tombstone records". Also say that Favorites are a union because each is its own record.
- **§31.7:** replace "account switch (wipe local sync state and re-seed on identity change)" with "account switch: wipe local sync state, keep local data, and turn sync off until the user turns it on again. Nothing is uploaded to the new account automatically."
- **§31.2:** the zones are `Spaces` (Spaces, groups, tabs, Favorites), `Sites`, `Settings`, `History`, `Devices` and `Meta`. `Bookmarks` and `Boosts` join later.
- **§31.5:** zoom is not synced until per-site zoom is persisted (a reserved field exists). Name the settings allowlist and its exclusions.
- **§31.10:** settings live behind the account row, not a numbered page.
- **§30.21:** its home is History › Tabs on Other Macs.
- **§32 table:** the bundle is now `dev.novapps.luna`.
