#!/bin/zsh
#
#  make-dmg.sh
#  Luna — §30.17
#
#  Builds the disk image a new user opens first: Luna.app, an Applications
#  alias, and `dmg-background.swift`'s backdrop with an arrow between the two.
#
#  The window's look is set through Finder, which is the only thing that writes
#  a `.DS_Store` — so the first run of this on a Mac raises the automation
#  prompt for Terminal controlling Finder once, and never again.
#
#  usage: Tools/make-dmg.sh [path/to/Luna.app] [out.dmg] [--dark]
#
set -euo pipefail

APP=${1:-DerivedData/Build/Products/Release/Luna.app}
OUT=${2:-build/Luna.dmg}
# A disk image stores one background picture, in the volume's `.DS_Store`, and
# Finder draws the icon labels in the system's appearance rather than the
# background's — so light is the one that survives both. `--dark` is here for
# a release that wants the other plane, not for a Mac that happens to be dark.
APPEARANCE=${3:-}
VOLUME="Luna"
STAGE=$(mktemp -d)
RW="$STAGE/rw.dmg"
MOUNT=""

if [[ ! -d "$APP" ]]; then
  echo "no app at $APP — build one first (make build, or a Release archive)" >&2
  exit 1
fi

cleanup() {
  [[ -n "$MOUNT" ]] && hdiutil detach "$MOUNT" -quiet 2>/dev/null || true
  rm -rf "$STAGE"
}
trap cleanup EXIT

mkdir -p "$(dirname "$OUT")" "$STAGE/root/.background"
cp -R "$APP" "$STAGE/root/Luna.app"
ln -s /Applications "$STAGE/root/Applications"
swift "$(dirname "$0")/dmg-background.swift" "$STAGE/root/.background/background.tiff" $APPEARANCE >/dev/null

# Sized to the contents plus room to breathe; UDRW because the window's
# settings have to be written into it before it is compressed.
hdiutil create -srcfolder "$STAGE/root" -volname "$VOLUME" -fs HFS+ \
  -format UDRW -ov "$RW" -quiet
# Mounted where Finder can see it: it addresses a disk by name, and a volume
# under `/private/var/folders` is not one it will answer for. The name comes
# back from `attach` rather than being assumed — a second Luna already
# mounted makes this one "Luna 1".
MOUNT=$(hdiutil attach "$RW" -readwrite -noverify -noautoopen | grep -o '/Volumes/.*' | tail -1)
DISK=$(basename "$MOUNT")

# The icons sit on the background's own centre line: `dmg-background.swift`
# draws its arrow between these two points, in a window 640 x 400.
osascript <<EOF
tell application "Finder"
  tell disk "$DISK"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 140, 840, 540}
    set theOptions to the icon view options of container window
    set arrangement of theOptions to not arranged
    set icon size of theOptions to 96
    set text size of theOptions to 12
    set background picture of theOptions to file ".background:background.tiff"
    set position of item "Luna.app" of container window to {165, 190}
    set position of item "Applications" of container window to {475, 190}
    close
    open
    -- Again after the reopen: Finder puts the status bar back on a window it
    -- has just been told to open, and a strip of chrome under the icons is
    -- the one thing on this page that is not the page.
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 140, 840, 540}
    update without registering applications
    delay 1
  end tell
end tell
EOF

sync
hdiutil detach "$MOUNT" -quiet
rm -f "$OUT"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT" -quiet
echo "wrote $OUT"
