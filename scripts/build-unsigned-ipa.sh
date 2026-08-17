#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
build_root="$project_root/build"
archive_path="$build_root/UnraidPilot.xcarchive"
payload_path="$build_root/Payload"
ipa_path="$build_root/UnraidPilot-unsigned.ipa"

cd "$project_root"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen is required: brew install xcodegen" >&2
  exit 1
fi

xcodegen generate
xcodebuild \
  -project UnraidPilot.xcodeproj \
  -scheme UnraidPilot \
  -configuration Release \
  -sdk iphoneos \
  -archivePath "$archive_path" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  archive

rm -rf "$payload_path" "$ipa_path"
mkdir -p "$payload_path"
cp -R "$archive_path/Products/Applications/UnraidPilot.app" "$payload_path/"
cd "$build_root"
zip -qry "$ipa_path" Payload

echo "Unsigned IPA: $ipa_path"

