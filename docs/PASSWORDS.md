# Passwords, autofill & passkeys — what is actually reachable

**TODO.md §14.1's spike, and its answer.** Read this before writing any UI copy
about passwords, and before promising anything in marketing or onboarding.

Measured on **macOS 26 (Darwin 27.0.0)** on 2026-09-19, against a binary signed
**ad-hoc** (`codesign -s -`) — which is the signature `project.yml` gives Luna
today (`CODE_SIGN_IDENTITY: "-"`, no team, no provisioning profile).

---

## 1. The short answer

| Question §14.1 asks | Answer |
|---|---|
| Can we write **synchronizable** `kSecClassInternetPassword` items? | **No, not while ad-hoc signed.** `-34018 errSecMissingEntitlement`. |
| Can we write **local** internet passwords? | **Yes.** Add, read, update and delete all return `errSecSuccess`. |
| Do our items show up in the **Passwords app** and sync? | **Only once Luna is signed with a real identity** — and re-test it then: §5a's fix gives our items a security domain, which may change how the Passwords app classifies them. |
| Is it an ACL prompt (Allow / Always Allow) or a hard denial? | **Neither.** See §3 — the items are not in Luna's search domain at all, so there is nothing to prompt about. |
| Can we read what **Safari / the Passwords app** already saved? | **No, at any signature.** Structural, not a permission we can ask for. |
| Can we do **passkeys / WebAuthn**? | **No, until Apple grants an entitlement.** Apply-only. See §4. |
| Can we show **Safari's own autofill panel**? | **No.** Measured — a plain `WKWebView` on a site with a saved Apple password offers nothing. See §5b. |
| Can we see credentials **other apps** put in the Keychain? | **No, and must not.** See §5a, which is where that went wrong once. |

**The feature still ships**, because the useful half works: Luna saves and fills
passwords today, in the user's own Keychain, with no vault of its own. What is
gated on M4's signing work is only whether those items *sync*.

---

## 2. The measurement

The probe: a standalone Swift binary, ad-hoc signed, touching only items under a
reserved `.invalid` host it created itself. It never enumerated or read any
pre-existing Keychain item — a spike is not a reason to read someone's
passwords, and the question can be answered without it.

```
1. SecItemAdd synchronizable (legacy API):        -34018 (A required entitlement is not present.)
2. SecItemCopyMatching own item:                  -25300 (The specified item could not be found.)
3. SecItemAdd kSecUseDataProtectionKeychain:      -34018 (A required entitlement is not present.)

A. SecItemAdd local (no synchronizable):               0 (No error.)
B. read back own local item:                           0 (No error.)
C. SecItemUpdate:                                      0 (No error.)
```

Lines 1–3 are the same refusal from two directions, and that is the finding:
**both routes into the iCloud/data-protection keychain need an entitlement.**
`kSecAttrSynchronizable: true` and `kSecUseDataProtectionKeychain: true` both
require `com.apple.application-identifier`, which comes from a provisioning
profile, which requires a real signing identity. There is no API-level
workaround; it is not a flag we set wrongly.

Lines A–C are the fallback, and it is a complete one for a single Mac: the
legacy file-based login keychain accepts Luna's items, hands them back, and
lets Luna update them.

### What this means for the acceptance criterion

§14.1's acceptance was "a throwaway signed build that saves a credential, shows
it in the Passwords app, and fills it back on a real login page — **or a written
'no' with the failure mode**." This is the written no, with the failure mode:
`-34018`, from both routes, for a reason that is about signing and not about
code. The other half of the acceptance — save, show, fill — becomes testable
the moment a Developer ID profile exists, and needs no code changes to try.

---

## 3. Why Safari's passwords are permanently out of reach

Items created by Safari and the Passwords app live in Apple's own **keychain
access groups**. `keychain-access-groups` only ever grants groups prefixed with
your own team identifier, so there is no entitlement Luna can request that puts
it in Apple's group.

This is why the question "ACL prompt or hard denial?" has a third answer. A
keychain ACL prompt happens when an app asks for an item it can *see* but is not
trusted for. Luna cannot see these items at all: they are outside its search
domain, so `SecItemCopyMatching` returns `errSecItemNotFound` and no prompt is
possible. There is nothing for the user to allow.

**Consequence for the UI, and it is not negotiable:** Luna must never say or
imply "use your existing passwords", never offer to import from Safari, and
never show an empty list in a way that reads as "you have no saved passwords".
`Features/Settings/Sections/Passwords.swift` states the limitation in so many
words, and that paragraph is load-bearing copy, not filler.

### The iCloud Passwords extension is not a way round it

Verified separately, and recorded in TODO.md §14's constraint table: the
official iCloud Passwords browser extension's native-messaging helper is
allowlisted to specific browsers by **signing identifier and team identifier**
since macOS 15.4, and from 15.5 the host only talks to known browsers. Chrome,
Edge and Firefox are on that list. A new browser is not, and there is no
published way to apply. Do not design around it.

---

## 4. Passkeys

WebAuthn in a third-party `WKWebView` requires:

```
com.apple.developer.web-browser.public-key-credential
```

The name is **verified against Apple's current entitlement documentation**, as
§14.10 asks. It is **apply-only**: there is a request form, Apple decides, and
the turnaround is theirs, not ours. It is how Chrome and Firefox reach passkeys
held in Apple Passwords on macOS, so the mechanism is real and proven — it is
the grant that is uncertain.

### What the request actually costs

Verified against Apple's entitlement documentation rather than assumed, because
the first version of this section got it wrong:

- The request form is
  <https://developer.apple.com/contact/request/macos-browsers-passkeys/>.
- Apple requires the **Account Holder role on an *organisation's* Apple
  Developer account**. An individual membership does not qualify. For Luna that
  means an organisation enrolment — a D-U-N-S number and a legal entity — not
  just the $99.
- Apple reviews against published criteria, and Luna now meets them: an
  address field, search, curated bookmarks, direct navigation to the requested
  URL, and no rewriting of destination content.

  The first criterion — `http` and `https` declared in `CFBundleURLTypes` —
  was **not** met until this was written. `App/Info.plist` had no
  `CFBundleURLTypes` key at all, which also meant LaunchServices never listed
  Luna as a browser: `NSWorkspace.urlsForApplications(toOpen:)` for an `https`
  URL returned Safari, Dia and Chrome and not Luna, so §3.1's "Set as Default"
  button could not have worked and discarded the resulting error in silence.
  One missing key blocked the entitlement request, the default-browser feature
  and §12.2's links-from-other-apps at once. It is declared now; the rest of
  §22.2 (document types, Handoff activity types, category) is still open.

**Do not** file `com.apple.developer.web-browser` alongside it. An earlier draft
of this document said to, on the grounds that a default browser needs it. That
is wrong: it is an **iOS and iPadOS** entitlement, and macOS default-browser
registration needs no entitlement at all — it needs the `CFBundleURLTypes`
declaration above.

### What the form asks for, and the one thing Luna has not got

Read off the form itself on 2026-09-20:

| Field | Answer |
|---|---|
| Bundle ID | `dk.novapps.luna` — must already be registered under Certificates, Identifiers & Profiles |
| App Store URL / Apple ID | blank; Luna is not on the App Store |
| Is your app a web browser on macOS? | Yes |
| Does it support WebAuthn? | **Yes** — WebKit does, and Luna hides it only until this is granted. Worth one sentence saying so, or a reviewer testing today sees no passkey button |
| Integrate with passkeys in iCloud Keychain? | Yes — that is the whole request |
| A link to learn about and download the browser | **This is the blocker.** |

Apple downloads the browser and runs it. There is nothing to download: the
repository is public but has no releases, and pointing a reviewer at source they
must build themselves is a reviewer who says no.

**Which reorders the work.** Developer ID signing and notarisation need no grant
from anybody, so the order is: get the certificate, sign and notarise a build,
publish it as a release, *then* file. Only passkeys wait on Apple.

Whether to file at all is a real choice and not an obvious yes. The entitlement
is granted to a **team ID**, not to source code, so passkeys would work in
official signed builds and not in a build someone makes from this repository.
That split already exists for notarisation, but passkeys make it user-visible.
If Luna would rather not have a feature that only the official binary has,
declining is coherent — the cost is that Luna never supports passkeys, and the
suppression script below becomes permanent rather than temporary.

### What Luna does in the meantime, and why it is not "nothing"

Without the entitlement, `window.PublicKeyCredential` is **still present** in
the DOM: WebKit defines the interface regardless. So feature detection
succeeds, the site offers "Sign in with a passkey", and the call then fails or
hangs on a sheet that never appears. The user is stranded on a login page whose
only offered method cannot work, with the password field they could have used
hidden behind a "use another method" link they have no reason to press.

**A dead passkey button is worse than no passkey button.** So
`PasskeySupport.suppressionScript` removes the interface at `documentStart` in
every frame, and sites fall back to passwords — which Luna does support. It also
wraps `navigator.credentials.get/create` to reject `publicKey` requests with
`NotSupportedError`, the error the spec defines for exactly this, so a library
that skipped detection gets a failure it already handles instead of a hang.

### Measured, not assumed

Both halves were checked in a real `WKWebView` on this Mac, with the script
installed exactly as `TabController` installs it (`documentStart`, all frames),
and probed **in the page world** — the world a website's own script runs in:

```
suppressed   { hasPublicKeyCredential: false, hasAttestationResponse: false,
               publicKeyGet: "NotSupportedError",
               passwordGet:  "passed through, returned null" }
```

A probe that accidentally ran in the *client* world — where the user script is
not installed — returned the unsuppressed behaviour, and so happens to be the
measurement of the premise:

```
unsuppressed { hasPublicKeyCredential: true, publicKeyGet: "NotAllowedError" }
```

That is §14.10's failure mode, observed rather than assumed: **the interface is
present, feature detection succeeds, and the call fails only once the user has
committed to it.**

`PasskeySupport.isAvailable` reads the entitlement off the **running process**
via `SecTaskCopyValueForEntitlement`, not off a build flag. The day a signed
build carries the entitlement, suppression stops, the settings row flips, and
passkeys work. Nothing needs editing.

---

## 5. How the shipped code is shaped around all this

- **`CredentialStore` tries synchronizable first, every time**, and falls back
  to local only on `-34018`, latching the result in `Capability`. Any other
  failure is surfaced, not papered over with a silent local write. The day the
  signature changes, the first save succeeds as synchronizable and the same
  code starts populating the Passwords app.
- **`migrateLocalItemsToSynced()`** rewrites the already-saved local items as
  synchronizable once the capability flips, so nothing saved before M4 is
  stranded. It re-adds before deleting, so a failure mid-way loses nothing.
- **The settings pane re-probes** rather than trusting a value latched at
  launch, and renders the storage line from the live answer.
- **`Credential` carries no password.** The secret is fetched from the Keychain
  at the instant of a fill and is never in `TabState`, never logged, never in a
  JS source string. `NewCredential` is the only type that holds one and is
  deliberately not `Codable` or `CustomStringConvertible`.

---

## 5a. Only Luna's own items — and how that was got wrong first

`CredentialStore` scoped every query with `kSecAttrService: "Luna"`. That
attribute belongs to `kSecClassGenericPassword`; on an **internet** password
the Keychain **silently ignores it**, in a query and in an add. Measured: the
same query run with `service: "Luna"` and with a random impossible service name
returned the identical row, and items came back with no service attribute at
all.

So the filter did nothing and `baseQuery` matched on `kSecAttrServer` alone —
every internet password for that host in the user's keychain, whoever wrote it.
On the machine where this was found, Luna's picker was offering a `github.com`
credential **created in 2025**, a year before this feature existed; by its
account name, `git-credential-osxkeychain`'s, whose secret is a personal access
token rather than a password. Three consequences, all from one wrong constant:

- a fill would have typed another application's token into a login form;
- `save` shares the query, so an update could have rewritten another app's item;
- `delete` shares it too, so "never for this site" could have destroyed one.

And `migrateLocalItemsToSynced()` was the worst of them: `kSecMatchLimitAll`
with `kSecReturnData`, re-adding every row it found as Luna's own and deleting
the original. Dormant only because the entitlement wall keeps `capability` at
`.local` — it would have run on the first launch after Luna was signed, which
is the plan.

The fix is two attributes, because one was not enough:

| | |
|---|---|
| `kSecAttrCreator` = `'Luna'` | honoured in queries, so reads are scoped |
| `kSecAttrSecurityDomain` = `"luna"` | **part of the uniqueness constraint** (server, account, protocol, port, path, securityDomain, authenticationType), so Luna can add its own row for a (host, account) another application already holds |

With the creator alone, reads were correct but `SecItemAdd` returned
`errSecDuplicateItem` for exactly the case that matters — the user's own GitHub
account, already in the keychain from `git` — and the save failed silently.
`Tests/Passwords/CredentialOwnershipTests.swift` stages a deliberately foreign
item under an RFC 2606 `.invalid` host and pins all three: not offered, not
overwritten, not deleted.

**Consequence for the user:** Luna's picker shows only what Luna saved. A
password already in the keychain from another application — or in the Passwords
app — is not Luna's to offer, and §3 above is why it never will be.

---

## 5b. The picker, and why it is Luna's own

Safari's password panel — the one with the Passwords app icon, the account,
the site and a fingerprint — is not reachable from a third-party browser.
Measured, not assumed: a plain unsigned `WKWebView` was pointed at a login
page for a site that *did* have a saved Apple password, and its password field
focused. No key icon, no panel. `Password AutoFill` is scoped to "your app's
associated domain", which requires the *website operator* to name your app in
a file on their server — not something a browser can have for every site.
Apple's "Password use in web browsers" page reads like it says otherwise, but
the sentence is about `WebAuthentication` challenges and every topic on it is
passkeys. Kagi say the same of Orion in their own documentation: third-party
browsers "cannot sync with the Keychain used by Safari".

So Luna draws its own, as Chrome, Firefox, Arc, Zen and Orion all do. What is
copied from Safari is the *shape*, all of which is free:

| | |
|---|---|
| The site's favicon | from §4.7's cache, falling back to a key glyph |
| Account and site on two lines | one account can be right on one site and wrong on a lookalike |
| A fingerprint on the row | says what the click costs before it is spent |
| "All saved passwords…" | **not** Safari's "Other Passwords for this site" — Luna cannot read those, and a row promising a list it cannot fetch would be a lie in the one piece of chrome that has to be trustworthy |

Touch ID is `LocalAuthentication`, which needs no entitlement and works in a
build made from source. It runs in `PasswordCoordinator.fill` **before**
`CredentialStore.password(for:)`, so a cancelled prompt means the secret was
never fetched into the process. The policy is `.deviceOwnerAuthentication`, so
a Mac with no Touch ID falls through to the login password rather than losing
autofill; if there is no lock at all, the fill proceeds, because refusing would
protect nothing. It is on by default and `passwords.requireAuthentication`
turns it off.

---

## 6. §14.8's security rules, and where each is enforced

| Rule | Enforced in |
|---|---|
| Never persist without an explicit user action | `PasswordCoordinator` never writes; only `confirmSave`, called by the chip's button, does |
| Never fill cross-origin, or an iframe whose origin differs from the page | `PasswordCoordinator.isFrameTrusted`, against `WKFrameInfo.securityOrigin` — scheme, host **and** port, not eTLD+1 |
| Require a recent user gesture before filling | There is no code path from a page event to a filled field; a fill begins only with a click on Luna's own popover |
| Never expose credentials to page JavaScript | `callAsyncJavaScript` with bound arguments, never string interpolation |
| Treat a fill after a redirect chain as suspicious | `sawServerRedirect`, set in `didReceiveServerRedirect…`, cleared in `didStartProvisionalNavigation`, shown in the popover |
| Match on eTLD+1 with a public-suffix list, never a substring | `PublicSuffix`, with the PSL's own algorithm including wildcards and exceptions |
| Addresses and payment cards are out of scope | Not built, and the settings pane does not mention them |

Note the deliberate asymmetry: **matching a credential to a site uses eTLD+1,
but trusting a frame uses a strict origin.** A same-site check on frames would
let `evil.example.com` inside `bank.example.com` collect the password, which is
the attack the rule exists for.

### Hosts with no registrable domain

`localhost`, a dotless intranet name, and IP literals have no eTLD+1. The first
version of `PublicSuffix` returned nil for all of them and called that the safe
answer. It is not an answer at all: every password path begins with
`guard let site = PublicSuffix.siteKey(...)`, so the whole feature went
**silently dead** on `http://localhost:8080/` — which is the first place anyone
building a login form tries it — and on every router, NAS and printer on a home
network. Nothing appeared and nothing explained why.

These are now their own site key, matched whole: `localhost` matches
`localhost` and nothing else, and `10.0.0.1` does not match `192.168.1.1`.
That does not weaken §14.3's rule, which exists to stop a *wildcard* spanning
two owners; an exact host cannot span anything. Safari and Chrome key these the
same way.

Two consequences, both shared with Safari and both worth knowing:

- every dev server on `localhost` shares one credential space, because the key
  is the host and ports are not part of it;
- two different routers that both answer on `192.168.1.1` look like one site.

---

## 7. Not built, and why

- **§14.6 verification codes.** §14.6 is conditional on §14.1 showing we can
  read synchronizable TOTP secrets. It shows we cannot read *anything* Apple's
  apps saved, so one-tap TOTP fill is out. The form detector reports
  `hasOneTimeCode` so the field is recognised, but Luna does not pretend to
  more. The clipboard fallback §14.6 allows is not built yet.
- **§14.7 native-messaging bridge** for 1Password / Bitwarden. The host side
  lives in the `WKWebExtensionController` delegate, and Luna has no extension
  loading at all (§16 is out of v1 by decision D-32). The bridge would have
  nothing to bridge to. This is the one part of §14 that is genuinely blocked
  on §16 rather than on Apple, and it is a real gap for users whose passwords
  are in 1Password.
- **§14.9's Feedback / DTS request.** A human action, not code. Worth filing
  alongside the M4 entitlement request.
- **The full Public Suffix List.** `PublicSuffix` embeds a curated subset plus
  the PSL's own default rule, so an unlisted suffix errs **narrow** (a declined
  fill) and never wide (a leak). Regenerate from the real list before v1.

---

## 8. Reproducing the spike

The probe is not committed — it is a throwaway, and a committed binary that
writes Keychain items is a liability. To re-measure after the signing change,
write a short Swift file that:

1. `SecItemAdd`s a `kSecClassInternetPassword` with
   `kSecAttrSynchronizable: kCFBooleanTrue` under a host in a reserved
   `.invalid` domain;
2. reads it back with the same server and account;
3. repeats step 1 with `kSecUseDataProtectionKeychain: true`;
4. deletes both.

Keep it scoped to items it created. Do **not** enumerate the keychain with
`kSecMatchLimitAll` to "see what is there" — that reads the developer's own
passwords to answer a question their absence already answers.

Then: `swiftc -o probe probe.swift && codesign -s - -f probe && ./probe`.
