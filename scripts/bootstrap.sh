#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v flutter >/dev/null; then
  echo "Flutter SDK não encontrado; instale o Flutter antes de continuar." >&2
  exit 1
fi
flutter create --platforms=linux,windows,macos --project-name jolven_iso .
rm -f test/widget_test.dart
flutter pub get
echo "Ambiente pronto. Rode flutter test, flutter analyze e flutter run."
