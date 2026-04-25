#!/usr/bin/env bash
set -u

# ============================================================
# CONFIG — edit me
# ============================================================

# How many simulators to spin up.
DEVICE_COUNT=5

# Device model (must exist in `xcrun simctl list devicetypes`).
DEVICE_TYPE="iPhone 16"

# Maestro flows to run, in order. Each entry runs as one round
# against ALL simulators in sequence, then the next entry runs.
# App data persists between rounds — that's the point.
# Paths are relative to this script's directory (or absolute).
FLOWS=(
  "flows/flow_increment.yaml"
  "flows/flow_increment.yaml"
  "flows/flow_increment.yaml"
  "flows/flow_assert_nine.yaml"
)

# Path to the Xcode project. Empty = auto-detect a single .xcodeproj
# in the parent directory.
PROJECT=""

# Build scheme. Empty = use the project filename without .xcodeproj.
SCHEME=""

# 1 = keep simulators after the run; 0 = delete them.
KEEP_SIMS=0

# 1 = skip xcodebuild and reuse the existing .app; 0 = build fresh.
SKIP_BUILD=0

# ============================================================
# END CONFIG — you shouldn't need to edit below this line
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UDID_FILE="$SCRIPT_DIR/.simulator_udids.txt"
BUILD_DIR="$SCRIPT_DIR/.build"

export PATH="$PATH:$HOME/.maestro/bin"

command -v xcrun      >/dev/null || { echo "ERROR: xcrun not found." >&2; exit 1; }
command -v xcodebuild >/dev/null || { echo "ERROR: xcodebuild not found." >&2; exit 1; }
command -v maestro    >/dev/null || { echo "ERROR: maestro not on PATH. Install: curl -Ls https://get.maestro.mobile.dev | bash" >&2; exit 1; }

if [ -z "$PROJECT" ]; then
  PROJECT="$(find "$HOST_DIR" -maxdepth 1 -name '*.xcodeproj' -print -quit)"
fi
[ -n "$PROJECT" ] && [ -e "$PROJECT" ] || { echo "ERROR: no .xcodeproj found in $HOST_DIR. Set PROJECT in this script." >&2; exit 1; }
[ -z "$SCHEME" ] && SCHEME="$(basename "$PROJECT" .xcodeproj)"

APP_PATH="$BUILD_DIR/Build/Products/Debug-iphonesimulator/$SCHEME.app"

if [ "$SKIP_BUILD" != "1" ]; then
  echo "### Building scheme '$SCHEME' from $(basename "$PROJECT")..."
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
    -sdk iphonesimulator -configuration Debug \
    -derivedDataPath "$BUILD_DIR" build >/dev/null
  echo "Build OK -> $APP_PATH"
fi
[ -d "$APP_PATH" ] || { echo "ERROR: app bundle missing at $APP_PATH" >&2; exit 1; }

echo
echo "### Resetting all simulators on this machine..."
xcrun simctl shutdown all 2>/dev/null || true
xcrun simctl delete all
xcrun simctl delete unavailable 2>/dev/null || true

RUNTIME_ID=$(xcrun simctl list runtimes available 2>/dev/null \
  | awk -F' - ' '/iOS .* - com\.apple\.CoreSimulator\.SimRuntime\.iOS-/ {print $NF}' \
  | tail -1)
[ -n "$RUNTIME_ID" ] || { echo "ERROR: no iOS runtime installed." >&2; exit 1; }
DEVICE_TYPE_ID="com.apple.CoreSimulator.SimDeviceType.$(echo "$DEVICE_TYPE" | tr ' ' '-')"

echo "### Creating $DEVICE_COUNT '$DEVICE_TYPE' simulators on $RUNTIME_ID..."
: > "$UDID_FILE"
for i in $(seq 1 "$DEVICE_COUNT"); do
  UDID=$(xcrun simctl create "TestDevice-$i" "$DEVICE_TYPE_ID" "$RUNTIME_ID")
  [ -n "$UDID" ] || { echo "  failed to create TestDevice-$i" >&2; continue; }
  echo "$UDID" >> "$UDID_FILE"
  echo "  TestDevice-$i -> $UDID"
done

echo
echo "### Pre-installing app on each simulator..."
while IFS= read -r UDID; do
  [ -z "$UDID" ] && continue
  xcrun simctl boot "$UDID" 2>/dev/null || true
  xcrun simctl bootstatus "$UDID" -b >/dev/null
  xcrun simctl install "$UDID" "$APP_PATH" || echo "  install failed on $UDID" >&2
  xcrun simctl shutdown "$UDID" 2>/dev/null || true
done < "$UDID_FILE"

ROUND=0
for FLOW in "${FLOWS[@]}"; do
  ROUND=$((ROUND+1))
  FLOW_PATH="$SCRIPT_DIR/$FLOW"
  [ -f "$FLOW_PATH" ] || FLOW_PATH="$FLOW"
  if [ ! -f "$FLOW_PATH" ]; then
    echo "WARNING: flow not found: $FLOW (skipping)" >&2
    continue
  fi

  echo
  echo "### Round $ROUND: $FLOW"
  TOTAL=0; PASS=0; FAIL=0
  while IFS= read -r UDID; do
    [ -z "$UDID" ] && continue
    TOTAL=$((TOTAL+1))
    echo "--- [$TOTAL] $UDID ---"
    xcrun simctl boot "$UDID" 2>/dev/null || true
    xcrun simctl bootstatus "$UDID" -b >/dev/null
    if maestro --device "$UDID" test "$FLOW_PATH"; then
      PASS=$((PASS+1))
    else
      FAIL=$((FAIL+1))
    fi
    xcrun simctl shutdown "$UDID" 2>/dev/null || true
  done < "$UDID_FILE"
  echo "Round $ROUND: $PASS passed, $FAIL failed (of $TOTAL)"
done

echo
if [ "$KEEP_SIMS" = "1" ]; then
  echo "### KEEP_SIMS=1; leaving simulators in place. UDIDs: $UDID_FILE"
else
  echo "### Tearing down simulators..."
  while IFS= read -r UDID; do
    [ -z "$UDID" ] && continue
    xcrun simctl shutdown "$UDID" 2>/dev/null || true
    xcrun simctl delete "$UDID" 2>/dev/null || true
  done < "$UDID_FILE"
  rm -f "$UDID_FILE"
fi

echo "### Done. $ROUND round(s) executed across $DEVICE_COUNT device(s)."
