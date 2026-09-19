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
| Do our items show up in the **Passwords app** and sync? | **Only if the write above succeeds**, i.e. only once Luna is signed with a real identity. |
| Is it an ACL prompt (Allow / Always Allow) or a hard denial? | **Neither.** See §3 — the items are not in Luna's search domain at all, so there is nothing to prompt about. |
| Can we read what **Safari / the Passwords app** already saved? | **No, at any signature.** Structural, not a permission we can ask for. |
| Can we do **passkeys / WebAuthn**? | **No, until Apple grants an entitlement.** Apply-only. See §4. |

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

Budget the request into **M4**, and file it early: the wait is the long pole,
and it costs nothing to be waiting while the rest of M4 happens. File
`com.apple.developer.web-browser` in the same submission — a default browser
needs it and it is the same form.

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
