#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
: "${LOCALSUB_SIGNING_IDENTITY:?Set LOCALSUB_SIGNING_IDENTITY to a Developer ID Application identity}"
: "${LOCALSUB_NOTARY_PROFILE:?Set LOCALSUB_NOTARY_PROFILE to a notarytool keychain profile}"

"$repo_dir/scripts/build-app.sh" release >/dev/null
bundle="$repo_dir/.build/app/LocalSub.app"
archive="$repo_dir/.build/app/LocalSub-notarization.zip"

codesign --force --deep --timestamp --options runtime \
  --sign "$LOCALSUB_SIGNING_IDENTITY" \
  --entitlements "$repo_dir/Config/LocalSubApp.entitlements" \
  "$bundle"
codesign --verify --deep --strict --verbose=2 "$bundle"
ditto -c -k --keepParent "$bundle" "$archive"
xcrun notarytool submit "$archive" --keychain-profile "$LOCALSUB_NOTARY_PROFILE" --wait
xcrun stapler staple "$bundle"
xcrun stapler validate "$bundle"
spctl --assess --type execute --verbose=2 "$bundle"
print -r -- "$bundle"
