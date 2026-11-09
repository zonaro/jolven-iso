#!/usr/bin/env bash
# Initial AppImage packaging. Requires an existing Flutter Linux release bundle.
set -euo pipefail

cd "$(dirname "$0")/.."
bundle="build/linux/x64/release/bundle"
appdir="build/appimage/AppDir"
mkdir -p dist

if [[ ! -x "$bundle/jolven_iso" || ! -f "$bundle/lib/libflutter_linux_gtk.so" ]]; then
  echo "Flutter bundle ausente: rode 'flutter build linux --release'." >&2
  exit 1
fi
if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "Instale librsvg2-bin (rsvg-convert) para gerar o ícone." >&2
  exit 1
fi

rm -rf -- "$appdir"
mkdir -p "$appdir/usr"
cp -a "$bundle/." "$appdir/usr/"
mkdir -p "$appdir/usr/share/icons/hicolor/256x256/apps"
rsvg-convert -w 256 -h 256 assets/icons/jolven-iso.svg \
  > "$appdir/usr/share/icons/hicolor/256x256/apps/jolven-iso.png"
cp "$appdir/usr/share/icons/hicolor/256x256/apps/jolven-iso.png" "$appdir/jolven-iso.png"

cat > "$appdir/jolven-iso.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Jolven ISO Builder
Comment=Configure uma ISO oficial Nobara com Jolven
Exec=jolven_iso
Icon=jolven-iso
Categories=Utility;Development;
Terminal=false
DESKTOP

cat > "$appdir/AppRun" <<'APPRUN'
#!/usr/bin/env bash
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
export LD_LIBRARY_PATH="$ROOT/usr/lib:${LD_LIBRARY_PATH:-}"
cd "$ROOT/usr"
exec "$ROOT/usr/jolven_iso" "$@"
APPRUN
chmod +x "$appdir/AppRun"
ln -s jolven-iso.png "$appdir/.DirIcon"

tool="build/appimage/appimagetool-x86_64.AppImage"
if [[ ! -x "$tool" ]]; then
  echo "Baixando appimagetool upstream (checksum/pinning exigidos para release estável)." >&2
  curl --fail --location --silent --show-error \
    "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage" \
    -o "$tool"
  chmod +x "$tool"
fi

version="$(sed -n 's/^version: \([0-9][^+]*\).*/\1/p' pubspec.yaml | head -n1)"
out="dist/Jolven-ISO-Builder-${version:-dev}-x86_64.AppImage"
ARCH=x86_64 "$tool" --appimage-extract-and-run "$appdir" "$out"
sha256sum "$out" > "$out.sha256"
echo "AppImage criado: $out"
