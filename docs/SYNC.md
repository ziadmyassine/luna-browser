# iCloud sync — §31.1 spike

## The question

Can one Developer ID–signed, non-sandboxed Luna carry the iCloud (CloudKit)
entitlements with an embedded provisioning profile, reach `cloudd`, and still
become the default browser? §22.1 rules out the App Sandbox, and Apple
documents CloudKit against sandboxed apps, so everything in §31.2+ rests on
this answer.

## Verdict: yes

Run on 2026-09-27. The Developer ID build with no sandbox entitlement launches,
talks to `cloudd`, reads the iCloud account and user record, and saves, lists
and deletes a custom zone in the private database of `iCloud.dev.novapps.luna`.
The same build is unsandboxed and registered as an `https` handler, so nothing
in the sandbox story changes for §22.1. Option (a), (b) and (c) are not needed.

One step is left to a person: clicking Make Luna Default on the signed build
(below). Setting the default shows macOS's confirmation sheet, so the spike
does not do it.

## What was built

- Bundle ID `dev.novapps.luna` (was `dk.novapps.luna`), matching the App ID
  `FUUYR6KRSH.dev.novapps.luna` and container `iCloud.dev.novapps.luna`.
- `Signing/Luna.entitlements`: `com.apple.application-identifier`,
  `com.apple.developer.team-identifier`,
  `com.apple.developer.icloud-container-identifiers` = [`iCloud.dev.novapps.luna`],
  `com.apple.developer.icloud-services` = [`CloudKit`],
  `com.apple.developer.icloud-container-environment` = `Production`.
  No `com.apple.security.app-sandbox`.
- `make signed`: a Release build, the profile copied to
  `Contents/embedded.provisionprofile`, the `luna-control` helper and then the
  app signed with `Developer ID Application: NovApps ApS (FUUYR6KRSH)`,
  Hardened Runtime and a secure timestamp. `make build`, `make test` and CI
  stay ad-hoc. The profile is never committed (`*.provisionprofile` is
  ignored); it lives at `Signing/Luna_Developer_ID.provisionprofile`.
- `Luna --cloudkit-probe` (`App/CloudKitProbe.swift`): runs before
  `NSApplication` exists, so no window, Dock icon or focus change. Prints the
  sandbox state and entitlements read from its own signature, the current
  `https` handler and whether Luna is among the registered `https` handlers,
  then `accountStatus`, `userRecordID`, and a custom zone `spike` saved,
  listed and deleted, with the `CKError` code of any failure. A zone needs no
  schema, so the round-trip proves the daemon connection in Production. Delete
  the file once §31.2's sync code proves the same thing.

## Commands and results

```
make signed
codesign -dv --entitlements - DerivedData/Build/Products/Release/Luna.app
codesign --verify --deep --strict --verbose=2 DerivedData/Build/Products/Release/Luna.app
spctl -a -vv DerivedData/Build/Products/Release/Luna.app
DerivedData/Build/Products/Release/Luna.app/Contents/MacOS/Luna --cloudkit-probe
```

`codesign -dv`: `Identifier=dev.novapps.luna`, `flags=0x10000(runtime)`,
`TeamIdentifier=FUUYR6KRSH`, timestamped; the five entitlements above.

`codesign --verify --deep --strict`: valid on disk, satisfies its Designated
Requirement (helper validated too).

`spctl -a -vv`: `accepted`, `source=Unnotarized Developer ID`. This Mac
reports `override=security disabled` (Gatekeeper is off), so this says nothing
about a quarantined download; that needs notarisation (§24.4).

Probe, exit 0:

```
[probe] bundle dev.novapps.luna
[probe] sandboxed false
[probe] entitlements ["com.apple.application-identifier", "com.apple.developer.icloud-container-environment", "com.apple.developer.icloud-container-identifiers", "com.apple.developer.icloud-services", "com.apple.developer.team-identifier"]
[probe] default https handler /Applications/Dia.app
[probe] https handlers include dev.novapps.luna: true (25 apps)
[probe] container iCloud.dev.novapps.luna
[probe] accountStatus 1 (CKAccountStatus(rawValue: 1))
[probe] userRecordID ok (_aa94eb7…)
[probe] save zone spike ok
[probe] allRecordZones ["_defaultZone", "spike"]
[probe] delete zone spike ok
```

`accountStatus` 1 is `.available`. No `CKError`, no amfid rejection, no
`cloudd` error mentioning the container.

## The profile must name the signing certificate

The first run was killed at launch (SIGKILL) with amfid
`-413 No matching profile found`, and taskgated-helper listing every
entitlement, even `team-identifier`, as unsatisfied. The profile named a
Developer ID certificate (SHA-1 `7A1372F1…`) other than the one in the
keychain (`8DE756B7…`); two had been created minutes apart. A profile whose
`DeveloperCertificates` lacks the signing certificate is discarded whole. Check
before signing:

```
security cms -D -i Signing/Luna_Developer_ID.provisionprofile -o p.plist
plutil -extract DeveloperCertificates.0 raw p.plist | base64 -d | shasum
security find-identity -v -p codesigning
```

## Default browser

The signed app has no sandbox entitlement, `NSWorkspace.urlForApplication(toOpen:)`
and `urlsForApplications(toOpen:)` answer from it, Launch Services lists Luna
as an `https` handler, and `CFBundleURLTypes` still declares `http` and
`https`. The final check is a person opening
`DerivedData/Build/Products/Release/Luna.app` and clicking Make Luna Default
in Settings ▸ General.

## What §31.2 needs to know

- Container `iCloud.dev.novapps.luna`, team `FUUYR6KRSH`, private database.
- A Developer ID profile allows only the Production environment. Production
  has no just-in-time schema: saving a record of a type the schema does not
  know fails. Record types are created in the CloudKit Console's Development
  schema (by hand, or by a Development build saving records) and deployed to
  Production before a Developer ID build can use them.
- A Development-environment build needs a separate macOS App Development
  profile: an Apple Development certificate on team `FUUYR6KRSH`, this Mac
  registered as a device, and `icloud-container-environment` = `Development`.
  The only Apple Development identity on this Mac today is on another team.
  Not tried in this spike.
- Hardened Runtime is on in the signed build. A web page asking for the
  camera or microphone needs `com.apple.security.device.camera` and
  `com.apple.security.device.audio-input` under it (§24.4); neither is in
  `Signing/Luna.entitlements` yet.
