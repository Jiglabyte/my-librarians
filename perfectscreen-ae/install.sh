#!/bin/bash
# PerfectScreen — Mac install script.
# Copies the extension into the user CEP folder and enables debug mode
# (required to load unsigned extensions).

set -e

SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/Library/Application Support/Adobe/CEP/extensions/perfectscreen-ae"

mkdir -p "$(dirname "$DEST")"
rm -rf "$DEST"
cp -r "$SRC" "$DEST"
echo "Copied extension to: $DEST"

# Enable unsigned extensions for every CEP runtime AE 2020+ might use.
for v in 9 10 11 12; do
  defaults write "com.adobe.CSXS.$v" PlayerDebugMode 1 2>/dev/null || true
done
# Make sure cfprefsd picks up the change.
killall cfprefsd 2>/dev/null || true

echo "PlayerDebugMode enabled for CSXS 9-12."
echo "Restart After Effects, then open: Window > Extensions > PerfectScreen"
