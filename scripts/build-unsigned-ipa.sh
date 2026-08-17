#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
build_root="$project_root/build"
archive_path="$build_root/UnraidPilot.xcarchive"
derived_data_path="$build_root/DerivedData"
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
  -derivedDataPath "$derived_data_path" \
  -archivePath "$archive_path" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  archive

app_path="$archive_path/Products/Applications/UnraidPilot.app"
build_products="$derived_data_path/Build/Intermediates.noindex/ArchiveIntermediates/UnraidPilot/BuildProductsPath/Release-iphoneos"
mkdir -p "$app_path/Frameworks"
find "$build_products" -maxdepth 2 -name '*.framework' -exec cp -RL {} "$app_path/Frameworks/" \;

if [[ ! -d "$app_path/Frameworks/AMSMB2.framework" ]]; then
  echo "AMSMB2.framework was not embedded in the app bundle" >&2
  exit 1
fi

rm -rf "$payload_path" "$ipa_path"
mkdir -p "$payload_path"
cp -R "$app_path" "$payload_path/"
cd "$build_root"
zip -qry "$ipa_path" Payload

echo "Unsigned IPA: $ipa_path"
