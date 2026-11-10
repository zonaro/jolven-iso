#!/usr/bin/env bash
# Build a pinned Jolven usr/ tarball for the ISO overlay injector.
# Does NOT install anything on the host and does NOT run sudo.
set -Eeuo pipefail

usage() {
  printf 'Usage: %s <40-character-jolven-commit-sha> [output-directory]\n' "$0" >&2
  exit 64
}
[[ $# -ge 1 && $# -le 2 ]] || usage
ref="$1"
[[ "$ref" =~ ^[a-f0-9]{40}$ ]] || usage
arch="$(uname -m)"
[[ "$arch" == x86_64 ]] || { echo "Currently supported: x86_64" >&2; exit 69; }
for cmd in git meson ninja tar sha256sum mktemp realpath; do
  command -v "$cmd" >/dev/null || { echo "Missing build tool: $cmd" >&2; exit 69; }
done
output="${2:-.}"
mkdir -p -- "$output"
output="$(realpath -- "$output")"
work="$(mktemp -d -t jolven-package.XXXXXXXX)"
trap 'rm -rf -- "$work"' EXIT

echo "Fetching pinned Jolven commit: $ref"
git clone --filter=blob:none https://github.com/zonaro/jolven.git "$work/src"
git -C "$work/src" checkout --detach "$ref"
resolved="$(git -C "$work/src" rev-parse HEAD)"
[[ "$resolved" == "$ref" ]] || { echo "Commit mismatch." >&2; exit 70; }
meson setup "$work/build" "$work/src" --prefix=/usr --buildtype=release -Dprofile=release
meson compile -C "$work/build"
DESTDIR="$work/stage" meson install -C "$work/build" --no-rebuild

[[ -x "$work/stage/usr/bin/jolven" ]] || { echo "Jolven binary missing." >&2; exit 70; }
[[ -x "$work/stage/usr/bin/jolven-session" ]] || { echo "Jolven Session missing." >&2; exit 70; }
[[ -x "$work/stage/usr/libexec/jolven-game-mode-setup" ]] ||
  { echo "Privileged helper missing." >&2; exit 70; }

tarball="$output/jolven-linux-$arch-$ref.tar.gz"
tar -C "$work/stage" --owner=0 --group=0 --numeric-owner -czf "$tarball" usr
(
  cd -- "$output"
  sha256sum "$(basename "$tarball")" > "$(basename "$tarball").sha256"
)
echo "Prepared: $tarball"
echo "Use this archive and SHA-256 in the experimental composer."
