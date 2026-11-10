#!/usr/bin/env bash
# Package the Flutter macOS app and bundled Python engine (currently read-only).
set -euo pipefail
cd "$(dirname "$0")/.."

app="build/macos/Build/Products/Release/jolven_iso.app"
if [[ ! -d "$app/Contents/MacOS" ]]; then
  echo "Run flutter build macos --release first." >&2
  exit 1
fi
mkdir -p "$app/Contents/Resources/engine"
cp -a engine/jolven_iso "$app/Contents/Resources/engine/"
version="$(sed -n 's/^version: \([0-9][^+]*\).*/\1/p' pubspec.yaml | head -n1)"
mkdir -p dist
out="dist/Jolven-ISO-Builder-${version:-dev}-macOS-$(uname -m).zip"

# Re-sign after changing app resources. Ad-hoc signature is NOT notarization.
codesign --force --deep --sign - "$app"
codesign --verify --deep "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "$out"
shasum -a 256 "$out" > "$out.sha256"
echo "macOS archive: $out"
