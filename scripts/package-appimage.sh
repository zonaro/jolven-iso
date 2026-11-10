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
# Ship the audited Python engine source alongside Flutter; never call it as root implicitly.
mkdir -p "$appdir/usr/share/jolven-iso/engine"
cp -a engine/jolven_iso "$appdir/usr/share/jolven-iso/engine/"
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

# Pin both the packager and the embedded AppImage runtime to immutable
# upstream release tags AND expected SHA-256 digests. Never execute an
# unverified binary downloaded from a moving "continuous" release.
tool="build/appimage/appimagetool-x86_64.AppImage"
runtime="build/appimage/type2-runtime-x86_64"
tool_url="https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-x86_64.AppImage"
runtime_url="https://github.com/AppImage/type2-runtime/releases/download/20251108/runtime-x86_64"
tool_sha="ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0"
runtime_sha="2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d"

download_verified() {
  local url="$1" output="$2" sha="$3"
  if [[ -f "$output" ]]; then
    if printf '%s  %s\n' "$sha" "$output" | sha256sum -c --status; then
      return 0
    fi
    rm -f -- "$output"
  fi
  local partial="$output.partial"
  rm -f -- "$partial"
  curl --fail --location --silent --show-error "$url" -o "$partial"
  if ! printf '%s  %s\n' "$sha" "$partial" | sha256sum -c --status; then
    rm -f -- "$partial"
    echo "SHA-256 mismatch from upstream release: $url" >&2
    exit 70
  fi
  mv -- "$partial" "$output"
}

download_verified "$tool_url" "$tool" "$tool_sha"
download_verified "$runtime_url" "$runtime" "$runtime_sha"
chmod +x "$tool"

version="$(sed -n 's/^version: \([0-9][^+]*\).*/\1/p' pubspec.yaml | head -n1)"
out="dist/Jolven-ISO-Builder-${version:-dev}-x86_64.AppImage"
ARCH=x86_64 "$tool" --appimage-extract-and-run --runtime-file "$runtime" "$appdir" "$out"
sha256sum "$out" > "$out.sha256"
echo "AppImage criado: $out"
