# Frequently asked questions

**macOS says Luna "cannot be opened" or is from an unidentified developer.**
Builds you make yourself are signed ad hoc, not with a Developer ID. Right-click
Luna in Finder, choose **Open**, and confirm once. Released builds will be signed
and notarised.

**Pinned tabs don't show up in Safari's Favorites.**
Settings ▸ iCloud ▸ Safari needs **Full Disk Access** for Luna (System Settings ▸
Privacy & Security ▸ Full Disk Access) to edit Safari's bookmarks. Only one copy of
Luna can hold that permission; a second copy on your Mac (a debug build, an old
disk image) takes it over. On the iPhone, Safari can take a while to fetch the
change. See [SAFARI-FAVORITES.md](SAFARI-FAVORITES.md).

**The iCloud Passwords extension says it can't work in Luna.**
Its helper only runs for browsers Apple has approved, through an entitlement Luna
does not have yet. Luna's own password autofill from the Keychain works meanwhile.
See [PASSWORDS.md](PASSWORDS.md).

**Why no passkeys?**
They need the same Apple entitlement. Details in [PASSWORDS.md](PASSWORDS.md).

**Why WebKit and not Chromium?**
Researched and decided: [research/ENGINES.md](research/ENGINES.md).

**Where is the list of what's being worked on?**
Every task, bug and feature is an issue on the
[project board](https://github.com/users/ziadmyassine/projects/2).

**Escape doesn't take me out of full screen.**
It takes two presses; the first shows a note saying so. A video in full screen
still leaves on one.
