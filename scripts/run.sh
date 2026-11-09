#!/usr/bin/env bash
#
# Rebuild and relaunch the Droob Student iOS app on a booted simulator.
#
# Usage:
#   ./scripts/run.sh                       # uses the first booted sim
#   ./scripts/run.sh "iPhone 16 Pro"       # boots/uses a named sim
#   DEVICE_ID=<udid> ./scripts/run.sh      # use a specific UDID
#
# Exits non-zero on any failure so you can chain it from another script.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

SCHEME="DroobStudent"
PROJECT="DroobStudent.xcodeproj"

# Resolve target simulator. Precedence: $DEVICE_ID > $1 (name) > first booted.
device_id="${DEVICE_ID:-}"
if [[ -z "$device_id" && $# -gt 0 ]]; then
    name="$1"
    device_id=$(xcrun simctl list devices available \
        | grep -E "$name" \
        | sed -nE 's/.*\(([-A-F0-9]+)\).*/\1/p' \
        | head -1)
    if [[ -z "$device_id" ]]; then
        echo "No simulator matching '$name' — available devices:" >&2
        xcrun simctl list devices available >&2
        exit 1
    fi
fi
if [[ -z "$device_id" ]]; then
    device_id=$(xcrun simctl list devices booted \
        | sed -nE 's/.*\(([-A-F0-9]+)\).*\(Booted\).*/\1/p' \
        | head -1)
fi
if [[ -z "$device_id" ]]; then
    echo "No booted simulator and no name passed. Boot one in Simulator.app or pass a name." >&2
    exit 1
fi

# Boot if needed (no-op if already booted).
xcrun simctl boot "$device_id" 2>/dev/null || true
open -a Simulator >/dev/null 2>&1 || true

echo "→ Building $SCHEME for $device_id"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=$device_id" \
    -derivedDataPath build \
    build \
    | xcbeautify --quiet 2>/dev/null \
    || xcodebuild \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration Debug \
        -destination "platform=iOS Simulator,id=$device_id" \
        -derivedDataPath build \
        build \
        | tail -40

APP_PATH="$PROJECT_DIR/build/Build/Products/Debug-iphonesimulator/$SCHEME.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "Build did not produce $APP_PATH" >&2
    exit 1
fi

BUNDLE_ID=$(defaults read "$APP_PATH/Info" CFBundleIdentifier)

echo "→ Installing $BUNDLE_ID"
xcrun simctl install "$device_id" "$APP_PATH"

# Terminate any running instance so launch picks up the fresh binary.
xcrun simctl terminate "$device_id" "$BUNDLE_ID" >/dev/null 2>&1 || true

echo "→ Launching $BUNDLE_ID"
xcrun simctl launch "$device_id" "$BUNDLE_ID"
