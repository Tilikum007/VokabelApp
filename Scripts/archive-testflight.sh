#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SCHEME="${SCHEME:-VokabelApp}"
CONFIGURATION="${CONFIGURATION:-Release}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
ARCHIVE_PATH="${ARCHIVE_PATH:-$ROOT_DIR/build/TestFlight/$SCHEME-$TIMESTAMP.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-$ROOT_DIR/build/TestFlight/export-$TIMESTAMP}"
EXPORT_OPTIONS="${EXPORT_OPTIONS:-$ROOT_DIR/Configs/ExportOptions-TestFlight.plist}"
BACKEND_BASE_URL="${VOKABEL_BACKEND_BASE_URL:-}"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen fehlt. Installation: brew install xcodegen" >&2
  exit 1
fi

if [[ -z "$BACKEND_BASE_URL" ]]; then
  echo "VOKABEL_BACKEND_BASE_URL fehlt. Beispiel:" >&2
  echo "VOKABEL_BACKEND_BASE_URL=http://192.168.178.79:8080 Scripts/archive-testflight.sh" >&2
  exit 2
fi

xcodegen generate

xcodebuild \
  -project "$ROOT_DIR/VokabelApp.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  VOKABEL_BACKEND_BASE_URL="$BACKEND_BASE_URL" \
  VOKABEL_BACKEND_FALLBACK_1="" \
  VOKABEL_BACKEND_FALLBACK_2="" \
  VOKABEL_BACKEND_FALLBACK_3="" \
  clean archive

xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates

echo "Archive: $ARCHIVE_PATH"
echo "Export:  $EXPORT_PATH"
