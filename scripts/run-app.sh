#!/bin/bash
# Build DemoApp, boot the simulator, install and launch the app.
# The app's print() output streams here; press Ctrl+C to stop watching.
#   scripts/run-app.sh                   # uses iPhone 18 Pro
#   SIMULATOR="iPhone 17" scripts/run-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

SIMULATOR="${SIMULATOR:-iPhone 18 Pro}"
DERIVED=.build/DemoApp
APP="$DERIVED/Build/Products/Debug-iphonesimulator/DemoApp.app"

if [ ! -d DemoApp/DemoApp.xcodeproj ]; then
  echo "DemoApp/DemoApp.xcodeproj not found. Create the project in Xcode first (phase 4)."
  exit 1
fi

echo "> Building for ${SIMULATOR}..."
xcodebuild -project DemoApp/DemoApp.xcodeproj -scheme DemoApp \
  -destination "platform=iOS Simulator,name=$SIMULATOR" \
  -derivedDataPath "$DERIVED" -quiet build

echo "> Booting simulator..."
xcrun simctl boot "$SIMULATOR" 2>/dev/null || true   # already booted is fine
# Show the simulator window. Xcode 27 replaced Simulator.app with DeviceHub.app.
# The app runs either way, so a missing viewer is only a warning.
XCODE_APPS="$(xcode-select -p)/../Applications"
open -a Simulator 2>/dev/null \
  || open "$XCODE_APPS/DeviceHub.app" 2>/dev/null \
  || echo "  (no simulator window app found; the app still runs in the background)"

echo "> Installing and launching..."
xcrun simctl install "$SIMULATOR" "$APP"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist")
xcrun simctl launch --console-pty --terminate-running-process "$SIMULATOR" "$BUNDLE_ID"
