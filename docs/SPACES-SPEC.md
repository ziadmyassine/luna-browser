# Spaces — the model, the behaviour and the scope (§5, §7, §8)

Written 2026-09-18. This is the source of truth for Spaces, Profiles and the
sidebar hierarchy. Where it disagrees with §5/§7's older lines in `TODO.md`,
this wins; the corrections are called out in §11 so nothing is lost silently.

Luna's target is **Arc's interaction model**. Arc is installed on this machine,
so the model below was read off its own `StorableSidebar.json` rather than from
anybody's blog post. Everything attributed to another browser was read from its
source or its on-disk data, and is cited.

**Dia is not a second target.** Dia's `User Data` holds plain Chromium profiles
("Main", "Work"), Chromium `SAVED_TAB_GROUP` state, and no space, workspace or
sidebar keys at all — only a leftover `arc.dnt_disabled_migration_done`. The
same company shipped Arc with Spaces and its successor without them. What the
owner uses in Dia today is **folders**, which is why §4 designs the hierarchy
for folders now even though they ship later.

---

## 1. What a Space is

A Space is a named, coloured workspace that owns a list of tabs and points at a
Profile. It is the unit the user switches between; the Profile is the unit that
owns cookies.

Two separate ideas, deliberately not merged:

| | Owns | Cardinality |
|---|---|---|
| **Space** | name, icon, gradient, its tab tree, per-Space settings | many Spaces → one Profile |
| **Profile** | one `WKWebsiteDataStore`, its Favorites | one Profile → many Spaces |

**Arc has exactly this shape.** From its own data:

```json
{ "id": "…defaultPersonalSpaceID",
  "profile": { "default": true },
  "customInfo": { "iconType": { "icon": "planet" } },
  "containerIDs": ["unpinned", "<uuid>", "pinned", "<uuid>"] }
```

`profile` is a reference, so several Spaces can name one Profile. Luna's
`Space.profileID` is the same thing and is **non-optional**, which is worth
keeping: Firefox's `userContextId: 0` "no container" state is a permanent source
of "why did this open outside a container" bugs, and Luna has no equivalent
state to explain.

---

## 2. The three tiers, and who owns each

Arc's Space owns exactly two containers — `pinned` and `unpinned` (= Today).
Favorites are a third thing, and they are **not** owned by the Space:

```json
"topAppsContainerIDs": [ { "default": true }, "2107A2FA-…" ]
```

That is a flat key/value pair — **profile → container**. Favorites belong to the
Profile, and every Space sharing that Profile shares its Favorites.

| Tier | Scope | Behaviour |
|---|---|---|
| **Favorites** (`.essential`) | **per Profile** | Icon tiles. Never auto-archive. Closing one puts the page away, keeps the tile. |
| **Pinned** | per Space | Persistent list. Never auto-archives. |
| **Today** | per Space | Auto-archives on the §12.3 schedule. |

**This is decision D-S2 and it changes existing behaviour.** Luna's `TabList` is
`[UUID: [Tab]]` keyed by Space, and `.essential` sits inside it, so Favorites are
currently **per-Space**. `TODO.md` §46 claims the opposite — "global, survives
Space switching". Both are wrong; Arc's answer is per-Profile, and Zen
independently lands near it by stripping a tab's workspace id when it is
promoted to Essential (`ZenPinnedTabManager.mjs:542-544`), making Essentials
global with an optional per-container mode.

Per-Profile is the right answer for the same reason the Profile exists at all: a
Favorite is a logged-in app tile. A tile that opens in a Space whose cookie jar
never saw that login is a broken tile.

---

## 3. Storage isolation

Each Profile owns exactly one identified `WKWebsiteDataStore`. Luna already does
this correctly and it is **stronger than every browser researched**:

- Zen and Floorp both use Firefox contextual identities (`userContextId`) — one
  cookie jar partition, shared history, shared cache policy. Zen's UI calls them
  "Profiles" and the tooltip promises "separate cookies and site data between
  spaces", which is why zen#1239 ("Website data is shared across workspaces", 24
  comments) exists: Arc refugees assume real isolation and do not get it.
- **Luna gives a Space a real data store, so Luna may say so plainly.** That is a
  marketing line we have actually earned. It also obliges us not to overstate it
  where it is not true — see §8 on permissions.

### 3.1 What the SDK actually guarantees

Verified in `WKWebsiteDataStore.h` on this machine, not recalled:

```objc
+ (WKWebsiteDataStore *)dataStoreForIdentifier:(NSUUID *)identifier;
    // Throws exception if identifier is 0.
+ (void)removeDataStoreForIdentifier:(NSUUID *)identifier completionHandler:…;
    // WKWebView using the data store must be released before removal.
+ (void)fetchAllDataStoreIdentifiers:…;
    // Default or non-persistent data stores do not have an identifier.
```

Three consequences, each a work item:

1. **The all-zero UUID throws an Objective-C exception, which Swift cannot
   catch.** Luna has no guard: `dataStoreIdentifier` is a `NOT NULL UNIQUE` blob
   column with no value check, and nothing validates it on read. A bad migration
   or a decode default crashes the app un-catchably. **Guard at the GRDB read
   boundary.** None of the five codebases researched does this.
2. **WebKit is the registry.** `allDataStoreIdentifiers` is the source of truth
   for which stores exist on disk, so a failed delete is always recoverable on a
   later launch and orphan cleanup is cheap. DuckDuckGo relies on exactly this:
   *"If this fails, we are going to still clean them next time as WebKit keeps
   track of all stores for us."*
3. **A cached store reference is itself what blocks removal.** Ora's
   `BrowserEngine.profileCache` has no eviction path, so even if it called
   `remove(forIdentifier:)` it would fail for every space forever. Luna's
   `ProfileStore.remove` already drops its cache entry first. Keep that first.

### 3.2 Deletion is a retry loop, not a call

Every project that ships this in production arrived at the same shape
independently — Crest (MPL-2.0) and DuckDuckGo. Luna should too:

1. Release every `WKWebView` on the store, and drop the cached reference.
2. Check `allDataStoreIdentifiers`; absent → already done.
3. `remove(forIdentifier:)`. Success → done.
4. On failure, once: `removeData(ofTypes: allWebsiteDataTypes(), modifiedSince:
   .distantPast)`. The directory may survive, but the *data* is gone, which is
   what the user asked for.
5. Re-check the identifier list; it may have vanished as a side effect.
6. Back off and retry: `[125ms, 250ms, 500ms, 1s, 2s, 4s]`.
7. Still failing → persist the identifier to a **pending-removal set in
   `UserDefaults`** (not GRDB — it must survive a database wipe), drained on
   launch and on a debounced timer.

Plus an orphan sweep at launch: diff `allDataStoreIdentifiers` against the live
`Profile.dataStoreIdentifier` set and delete the strays.

DuckDuckGo instruments this in production with three telemetry pixels counting
leftovers, which tells you how often step 3 fails. Luna collects nothing (D16),
so log it and move on.

### 3.3 Changing a Space's Profile

`TODO.md` §5.5 says the default store "cannot be adopted into one later". True of
WebKit, **but Luna never uses the default store** — `ProfileStore.dataStore(for:)`
always calls `WKWebsiteDataStore(forIdentifier:)`. So Luna's real migration is
identified → identified, which is a materially easier problem. §5.5's framing is
stale and is corrected in §11.

Nobody has solved this well:

- **Firefox refuses outright**, with a 500-word essay on why it is deliberate:
  *"When you transfer one URL to another container you risk that website knowing
  about both of your disguises."*
- **Chrome refuses outright** — `// Profiles must be the same.` in
  `tab_drag_controller.cc`.
- **Arc allows it with a warning**: *"If you move the tab between different
  profiles, you could be logged out of an account if you're not logged into it
  in the other profile."*
- **Zen allows it silently and it does not work** — zen#15023: reassigning a
  workspace's container does not re-container its open tabs, and the only user
  feedback is an unexplained greyed-out menu item.

**There is an API that might make Luna the first to do it properly.** Verified
present in the SDK on this machine, `API_AVAILABLE(macos(26.0))`, and Luna
targets 26.0:

```objc
- (void)fetchDataOfTypes:…  NS_SWIFT_NAME(fetchData(of:completionHandler:));
- (void)restoreData:(NSData *)data …  NS_SWIFT_NAME(restoreData(_:completionHandler:));
```

The header does not state that restoring into a *different* store is supported.
**Spike it before promising it in the UI** — this project has already been burned
once by a plausible-sounding API detail that did not exist (§15.1). If it works,
"move my logins across" becomes the default and the logout becomes the opt-out.
If it does not, ship Arc's warning and be honest that it is a fresh session.

**Either way, reassigning a Profile must rebuild every web view in that Space.**
Nook's `assign(spaceId:toProfile:)` sets the field and persists, and nothing
else — so every already-loaded tab keeps writing to the old store until
something unloads it. Ora has the fix in fifteen lines
(`refreshBrowserPageForPrivacySettings`: destroy → recreate, driven by a
notification). That is the shape Luna's `setProfile` needs.

---

## 4. The hierarchy — designed now, folders shipped later

The owner's daily driver is folders, not Spaces. Folders are out of scope for
this milestone, but the **model is not**: retrofitting a tree onto a flat list
with real user data is the expensive version of this work.

Arc's sidebar is one polymorphic tree:

```
items[] : { id, parentID, childrenIds[], title, createdAt,
            data: tab | itemContainer | splitView }
```

One tree, payload varies — which is how Arc gets folders, split view and nesting
without three separate systems.

Luna's `Tab` is flat. It has `parentTabID`, but that is **tab lineage** (which
tab opened which, for §7's indentation), not containment — a folder is a named
node that is not a tab.

**D-S3: adopt a node tree now.**

```swift
struct SidebarNode {
    var id: UUID
    var spaceID: UUID
    var parentID: UUID?        // nil = top level of its section
    var kind: Kind             // .tab(Tab) | .folder(name, isCollapsed)
    var section: TabKind       // .essential | .pinned | .today
    var order: Int
}
```

Ship it holding only `.tab` nodes. Folders then become a new case plus a UI, not
a migration. Nook stores its gradient the same way — `gradientData: Data`, an
encoded blob rather than an enum index — and got a gradient editor for free
instead of a schema change. Same lesson, different field.

---

## 5. Switching Spaces

**D-S4: containment, never hide/show.** Luna already mounts exactly one web view
and keeps the rest alive and detached, which is correct. The research is
unusually clear here:

- Zen migrated **away** from hide/show and left the receipt in its source:
  *"Bug: When updating from previous versions, we used to hide the tabs not used
  in the new workspace — we now need to show them again. TODO: Remove this on
  future versions."*
- Floorp still does hide/show: `updateTabsVisibility()` is O(all tabs in window)
  × three passes on **every** switch, with no perf comments anywhere in its
  workspace code.

Rules:

1. Other Spaces' web views stay alive. Eviction is the §19.2 hibernation policy's
   job, on its own clock — never a side effect of switching.
2. Switching is a view move, not a teardown.
3. **Persist the active Space; never infer it.** Luna already does
   (`luna.activeSpaceID`). Floorp infers it by majority vote over the first ten
   visible tabs, which is the direct cause of "always starts on the wrong
   workspace".
4. A Space remembers its own last-active tab. Luna already does.

### 5.1 The bug that must not ship

**"Last tab" is evaluated over the window, never over the visible Space.**

zen#9272: Zen evaluated it over the current Space only, so closing the one tab in
Space B quit the browser while Space A still had five open — and because it took
the window-close path rather than a session end, **nothing was restored**. One
user lost ~500 tabs. Floorp's equivalent (floorp#2152) is still open, with the
maintainer conceding: *"resolving the bugs around this area seems to be a bit
challenging."*

Luna is currently safe by accident — `closeTab` archives and never closes a
window — but the moment a window-close rule is added, this is where it goes
wrong. Decide it in the close handler, not after.

Zen's structural answer is worth copying: a dedicated per-window empty tab, so a
Space is never in the illegal zero-tab state.

---

## 6. Lifecycle

### 6.1 Create
A new Space takes a name, an SF Symbol and the next gradient. **It must be able
to join an existing Profile**, which is impossible today: `createSpace(name:)`
always mints a fresh `Profile`, so many-Spaces-to-one-Profile is modelled and
unreachable. Signature becomes `createSpace(name:profileID:)`, defaulting to a
new Profile.

### 6.2 Rename, reorder, re-icon, re-gradient
All missing; four Settings rows are dimmed for it. All are `Space` field writes
plus a persist and a `notifyChange`.

**Reordering is the biggest hole in the entire prior art — nobody implements
it.** Nook persists an index and has no reorder function; Ora has no order field
at all; Refrax has `position` and sorts by it but never reorders. Copy Nook's
one good idea instead: on load, compare the persisted order against `0..<n` and
renumber if it differs. That self-heal makes `reorderSpace` trivial and
immunises `delete(spaceID:)` against the gaps every delete leaves.

### 6.3 Delete a Space
Luna's `deleteSpace` is already better than most: last-Space guard, tears down
every web view, cascades tab rows, removes the store only when no other Space
names that Profile. Three changes:

1. **Offer to adopt the tabs** rather than destroying them. Refrax takes
   `closeTabs: Bool` and re-homes the tabs into another Space when false; that is
   what Arc users expect. Today Luna's tabs vanish, un-undoably.
2. **Archive rather than delete** when the user does choose to close them, so
   `⌘⇧T` and the archive still work. This is free — `closeTab` already archives.
3. **Delete the Profile row too.** `BrowserStore` has no `delete(profileID:)`, so
   profile rows orphan in SQLite even when their store is gone.

Deletion must be a real close that emits real close events. zen#12740's
maintainer states the rule: drop the record without firing closes and every
downstream index keeps ghosts — switch-to-tab, session store, other windows, and
live content processes.

### 6.4 The deletion dialog
Firefox warns about tabs and not data. Chrome warns about data and not windows.
Neither gets it right, and many-to-one forces Luna to say a third thing neither
has to:

> Delete **Work**? This closes 12 open tabs and permanently deletes cookies,
> logins and site data for 34 sites. **Spaces Research and Side Project also use
> this profile and will be affected.**

That last clause is mandatory whenever the Profile is shared, and is the one
piece of this dialog with no prior art to copy.

---

## 7. Moving tabs between Spaces

Luna's `moveTab(_:toSpace:)` already discards the controller so cookies cannot
cross profiles — which is correct and which Zen gets wrong (zen#11268: moving a
tab into a workspace keeps its old container, so Space membership and container
membership drift apart).

Add:

1. **Warn when the target Space is on a different Profile**, using Arc's wording.
   Crossing Profiles is a session-losing operation and must never be silent.
2. **Never re-home a tab in place across a Profile boundary.** Even Firefox's
   native implementation refuses: *"A load which switched container must not
   commit in the tab it started in"* — it always opens a new tab and leaves the
   original. Preserves back/forward semantics and avoids a history that spans two
   cookie jars.
3. Keep drag-onto-a-Space-dot. Two cheap additions from Zen worth stealing: a
   hover-the-sidebar-edge auto-switch during a drag (20 pt threshold), and
   re-tinting the dragged ghost to the destination Space's colour as it crosses.

---

## 8. Per-Space settings

| Setting | State | Note |
|---|---|---|
| Name, icon, gradient | **missing** | §6.2 |
| Default search engine (§5.4) | **missing** | `search.engine` is global. Neither Zen nor Floorp has this. |
| Auto-archive override (§5.2) | **missing** | `luna.autoArchiveHours` is global |
| Link-routing rule (§25.3) | **missing** | Arc: `{ rules: [], defaultDestination: { space: { mostRecent } } }` |
| Content blocking | global | Ora does it per-Space and it is the best part of that codebase |
| Cookie policy | — | **Incompatible with shared Profiles.** `httpCookieStore.setCookiePolicy` is a property of the *data store*, so a policy set on a shared Profile applies to every Space on it. Per-Space cookie policy must go through a content rule list instead. |
| Site permissions | **undecided** | See below |

**Permissions need a decision now.** Firefox shipped per-container permission
isolation and left it **off by default**, so camera access granted in Work leaks
to Personal. Chrome's is genuinely per-profile. Luna's `siteSettings` table
(§11.1) — if it is keyed on host alone, Luna has silently chosen Firefox's weaker
behaviour while claiming real isolation. Key it on `(profileID, host)`.

**No automatic per-site Profile routing in v1.** Firefox built it twice — once as
an extension with a two-second cancellation heuristic that leaks (#2019, #920,
#2372, #2564), once properly at the network layer with redirect re-evaluation —
and still ships the good one disabled by default. The failure mode is an
**infinite redirect loop** whenever an identity provider and the site it logs you
into resolve to different containers (#2642), which covers Google, Microsoft and
Okta.

---

## 9. Making the boundary visible

The single most-cited confusion across both ecosystems, predicted by Mozilla in
2016 and still live in 2026:

> *"A user may open an account in one container and not understand why they are
> not logged into the account on other containers."*

zen#14371 is the modern version: two identical "Google Gemini — Switch to tab"
rows in the omnibox, different Spaces, different accounts, no way to tell them
apart, and picking wrong teleports you.

**D-S8: the Profile identity must appear on every surface where tabs from
different Profiles can meet** — Command Bar switch-to-tab, history, archive,
downloads, the command palette. Not only the Space strip. §9.2 already badges
open tabs with the Space colour; that badge must carry the Profile when the
Profiles differ, because the Space colour alone does not tell you whose cookies
you are about to use.

---

## 10. Scope

**S1 — unblock what is already dimmed.** `renameSpace`, `reorderSpace` with the
renumber-on-load self-heal, `setIcon`, `setGradient`, `BrowserStore.delete(profileID:)`,
the all-zero-UUID guard, the orphan sweep at launch.

**S2 — identity.** The twelve gradients, and Profile identity on every
cross-Space surface (§9).

**S3 — the Profile boundary.** `createSpace(name:profileID:)`, the
`fetchData`/`restoreData` spike, `setProfile` with a full web-view rebuild, the
move-across-Profiles warning, the deletion dialog, `siteSettings` keyed on
`(profileID, host)`.

**S4 — the tree.** `SidebarNode` migration, shipped holding only tabs. Folders
become a case, not a migration.

**S5 — per-Space settings.** Search engine, auto-archive override, link routing.

**S6 — folders.** The thing the owner actually wants. Cheap once S4 exists.

Sync (§31) stays out. When it comes, one rule carries: **an absence in your local
projection is not a deletion.** Zen shipped the opposite and wiped 100% of one
user's folders, pinned tabs and several Spaces across three machines when they
signed into sync on a fresh install (zen#15426). Their three tombstone guards are
the most transferable forty lines in any repo read for this document. And the
syncable identity must be `Profile.id`, never `dataStoreIdentifier`, which is
device-local.

---

## 11. Corrections to `TODO.md`

1. **§46 "Favorite … global, survives Space switching"** — wrong, and the code
   disagrees with it too. Favorites are **per Profile** (§2).
2. **§5.5's default-store warning** — stale. Luna never uses the default store,
   so the migration is identified → identified. Rewrite as: *a Space changing
   Profile moves it to a different identified store; without a data copy this
   logs the user out of that Space's sites.*
3. **§5.2 "auto-archive after override"** — listed as part of the Space model; it
   does not exist. Still wanted, now scoped in S5.
4. **§8.2's twelve gradients** — still unbuilt; every Space is identical. Now S2.
5. **`WKProcessPool`** — must not appear anywhere, per-Space or shared.
   Deprecated since macOS 12.0: *"Creating and using multiple instances of
   WKProcessPool no longer has any effect."* Nook carries comments claiming a
   `configuration.copy()` preserves one; it is cargo cult.

## 12. Things worth stealing that are not about Spaces

- **Warm up WebKit at launch.** The first `WKWebView` costs ~100–300 ms for
  process spawn, GPU context and shader compilation. Refrax creates a throwaway
  `about:blank` view after launch settles and releases it 150 ms later, moving
  that cost off the user's first click. Free win, measurable against §19.1.
- **Score evictions, don't LRU them.** Refrax protects pages with active media
  capture, playing audio, unsaved form data and pinned status, and decays by idle
  time — soft limit 25 live views, 1-hour idle threshold, minimum 3 retained
  under critical pressure. Luna's §19.2 policy already has the exemptions; the
  numbers are a useful starting point.
- **If extensions ever land, derive a second store UUID per Profile.** Nook
  reuses the Profile's UUID for both page and extension storage, merging them
  into one container.

---

## 13. Arc's shipped defaults and the usage data (added after research)

### 13.1 The number that should shape the whole feature

The Browser Company published usage data when they put Arc into maintenance:

> "Only 5.52% of DAUs use more than one Space regularly."
> "Arc was simply too different, with too many new things to learn, for too
> little reward."

**94% of daily Arc users never regularly used a second Space.** Spaces was not
abandoned for being bad — it was a power-user feature whose cost was paid by the
entire onboarding surface. And it came back anyway under pressure from the 5.52%,
who would not let it go. Low reach, extreme attachment.

**D-S11: design for the 94%.** Out of the box: one unnamed Space, **no visible
switcher**, no chrome tint, no onboarding step. The Space UI appears when the
user creates a second one. Arc already bends this way, retrofitting collapsed
Pinned sections to single-Space users after complaints. Spaces must be something
Luna *grows into*, never a concept it opens with.

### 13.2 `⌘1…⌘9` is the wrong binding, and Luna already ships it

| Product | Spaces / workspaces | ⌘-number is… |
|---|---|---|
| Arc | `⌃1…⌃9` | sidebar items |
| Dia | `Ctrl+1–9` (profiles) | — |
| Vivaldi | `⌘⇧<n>` | — |
| **Luna today** | **`⌘1…⌘9`** | **unused** |

Three independent products, three different modifiers, **none of them plain
⌘-number** — that namespace means "go to tab N" in Safari, Chrome, Firefox, Edge
and Arc. Arc even shipped a preference controlling what `⌘1–8` indexes *within*
the sidebar, which is how contested it is.

Luna currently binds `⌘1…⌘9` to Spaces (`MainMenu.setSpaces`) and has **no
"go to tab N" at all**. So the most valuable shortcut in the app is spent on the
feature 94% of users will not use twice.

**D-S12: move Spaces to `⌃1…⌃9`. Reserve `⌘1…⌘9` for sidebar items.**
Add `⌘⌥←/→` for previous/next Space, a two-finger sidebar swipe, and
"go to <Space>" in the Command Bar. This is a breaking change to a shipped
binding and is cheaper today than ever again.

### 13.3 Auto-archive — Arc's defaults, and its mistake

- **12 hours** for idle unpinned tabs; viewing a tab resets the timer.
- Pinned tabs never auto-archive. Media-playing tabs are exempt (retrofitted).
- Timing is **per Profile**, and it syncs.
- Little-Arc-style floating windows archive on a separate **6 hour** default.
- **"Auto Archive can't be disabled."**

That last line is the mistake, and Arc paid for it visibly: a one-time
explainer banner for new members, a defensive help article ("This can be a little
tough to get used to at first"), per-Profile timings, and a media exemption. You
do not ship an apology banner for a feature people understand.

**D-S13: Luna's auto-archive is disableable.** Default 12h, options Off / 6h /
12h / 24h / 7d / 30d, never archiving a tab that is playing media or holds
unsaved input (§19.2 already has both exemptions). The behaviour is right; making
it mandatory is what turns it into data loss.

### 13.4 Favorites: cap it, allow zero, load it lazily

Arc caps Favorites at **12 per Profile**, allows zero, and had to retrofit lazy
loading: *"We used to keep your Favorites loaded at all times, but now we only
load them if they've been used recently."* A permanently-resident global tier is
a memory problem. All three constraints carry to Luna's per-Profile tier.

### 13.5 The global-tier argument, settled by volume

The loudest complaint in this whole category, and the evidence is lopsided:

- **Vivaldi** ships pinned-per-Workspace with **no** global tier. One forum
  thread asking for one: **118 posts, 61 posters, 45,500 views**, no staff reply.
  Users also discovered that pinning the same URL into several workspaces creates
  **separate instances**, which is not what they wanted.
- **Zen** ships Luna's exact split — global Essentials + per-workspace Pinned —
  and gets the *opposite* request from roughly **17 people** across two threads.

An order of magnitude. **The split is right**; the refinement is §2's
per-Profile scoping, which answers Zen's "I don't want YouTube in my work space"
without answering it with duplication.

### 13.6 Re-tinting: keep it, ship the escape hatches

Nobody asks Arc to remove the tint. Every complaint is about execution:

- Arc shipped *"better contrast in Dark Mode"* for the theme picker in 2022.
- Arc needed a help article for *"How Do I Restore the Default Theme"* — getting
  *out* of a theme was not discoverable.
- Zen shipped the contrast bug outright: on a light gradient *"text like the 'new
  tab' text and the workspace title become very hard to read."*
- Zen has an open issue for being unable to reset a gradient to unset.
- Dia's sidebar refresh went to **"neutral-colored tab groups by default."**

So: derive sidebar and label foregrounds from the **chosen gradient's
luminance**, not from a fixed token; give one click back to neutral; keep
Light/Dark **global** and say so in the UI (Arc's docs shout it); honour Reduce
Motion on the cross-fade and Reduce Transparency on the gradient.

### 13.7 Deleting a Space — a cheap place to beat everyone

Vivaldi closes every tab in the workspace with no undo. Arc shows a titled
confirmation and, per third-party reports only, archives — **no vendor source
confirms what happens to the tabs, and there is no documented undo anywhere in
three years of release notes.** §6.3's archive-and-undo therefore beats both, and
it is nearly free because `closeTab` already archives.

### 13.8 Space and Folder stay orthogonal

Vivaldi publishes the cleanest articulation of the distinction, and it is the
argument for §4's node tree:

> "Like Tab Stacks, Workspaces let you organize your tabs into different
> categories, but the difference is that **when you select a workspace to view,
> you will see only the tabs for that category** in your window."

A Space **filters** which tabs exist right now. A folder **groups** the visible
ones. They compose — a Space containing four folders — and neither should
collapse into the other.

### 13.9 Link routing: the default is contested

Arc's help centre says the shipped default is a floating window: *"By default,
all links opened from another desktop app open in Little Arc."* The install on
this machine reads `defaultDestination: { space: { mostRecent } }`, and a later
Arc release note says *"By default, all Google Meet Links will open in your most
recent Space"* — so they appear to have drifted away from the floating window.
Either the setting was changed here or the default moved. **Unresolved; pick
Luna's own default deliberately rather than inheriting a contested one.**

Rules are `contains` / `is equal to` → a target Space, with a default of
specific-Space / most-recent-Space / floating-window. **Deleting a Space deletes
its routes** — Arc states this explicitly.

### 13.10 Smaller shipped behaviours worth copying

- Switching a Space restores that Space's **last-used tab**. Luna already does.
- New Spaces appear **next to the active Space**, not at the end of the list.
- A toast when a Space is created while the sidebar is hidden.
- A pinned tab always resets to its saved URL, and a link that would navigate it
  away opens a floating window instead. Arc needed a dedicated FAQ for this, so
  if Luna copies the behaviour it must also explain it.
- Support **emoji as well as SF Symbols** for Space icons. Arc supports emoji
  with skin tones, SigmaOS is emoji-first, Vivaldi allows custom icons. SF
  Symbols alone will not survive contact.
- Arc had to patch a real cross-profile leak: Command Bar suggestions bleeding
  between Spaces on different Profiles. §9's rule again, from the other side.

