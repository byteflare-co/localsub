#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
configuration=${1:-release}
bundle_dir="$repo_dir/.build/app/LocalSub.app"
scratch_dir="${TMPDIR:-/tmp}/localsub-swift-build-${UID}"

swift build --package-path "$repo_dir" --scratch-path "$scratch_dir" -c "$configuration" --product LocalSubApp
binary_dir=$(swift build --package-path "$repo_dir" --scratch-path "$scratch_dir" -c "$configuration" --show-bin-path)

mkdir -p "$bundle_dir/Contents/MacOS"
cp "$repo_dir/Config/Info.plist" "$bundle_dir/Contents/Info.plist"
cp "$binary_dir/LocalSubApp" "$bundle_dir/Contents/MacOS/LocalSub"
codesign --force --sign - --options runtime \
  --entitlements "$repo_dir/Config/LocalSubApp.entitlements" \
  "$bundle_dir"
codesign --verify --deep --strict --verbose=2 "$bundle_dir"
print -r -- "$bundle_dir"
