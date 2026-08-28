#!/usr/bin/env bash
# Generate the Xcode project and open it, for signing locally with a real
# Apple Developer team.
#
# AltStore only uses Individual paid teams, so an Organization membership
# falls back to free 7-day signing. Building here with the org team selected
# produces a year-long provisioning profile instead.
#
# Usage:  ./Scripts/local-build.sh
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not found. Installing via Homebrew..."
  brew install xcodegen
fi

mkdir -p Generated
xcodegen generate

cat <<'NEXT'

Project generated: EasynewsPlayer.xcodeproj

Next steps in Xcode:
  1. Select the EasynewsPlayer-iOS scheme.
  2. Click the project, then the EasynewsPlayer-iOS target.
  3. Signing & Capabilities tab:
       - tick "Automatically manage signing"
       - set Team to your organization team
       - change the Bundle Identifier if Xcode reports it is taken
  4. Plug in the iPhone, pick it as the run destination, press Run.

The installed app is signed for a year rather than seven days, and does not
need AltServer or AltStore at all.

NEXT

open EasynewsPlayer.xcodeproj
