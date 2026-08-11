#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
: "${LOCALSUB_SIGNING_IDENTITY:?Set LOCALSUB_SIGNING_IDENTITY to a Developer ID Application identity}"
: "${LOCALSUB_NOTARY_PROFILE:?Set LOCALSUB_NOTARY_PROFILE to a notarytool keychain profile}"
: "${LOCALSUB_EXPECTED_TEAM_ID:?Set LOCALSUB_EXPECTED_TEAM_ID to the 10-character Apple Developer Team ID}"

output_dir=${1:-}
[[ -n $output_dir && $output_dir == /* && $output_dir != / ]] || {
  print -u2 -- "usage: $0 /absolute/output/directory"
  exit 64
}
/usr/bin/printf '%s\n' "$LOCALSUB_EXPECTED_TEAM_ID" | /usr/bin/grep -Eq '^[A-Z0-9]{10}$' || {
  print -u2 -- "LOCALSUB_EXPECTED_TEAM_ID must contain exactly 10 uppercase letters or digits"
  exit 64
}
[[ $(/usr/bin/uname -m) == arm64 ]] || {
  print -u2 -- "release builds require Apple Silicon"
  exit 1
}
macos_major=$(/usr/bin/sw_vers -productVersion | /usr/bin/awk -F. '{ print $1 }')
(( macos_major >= 26 )) || {
  print -u2 -- "release builds require macOS 26 or later"
  exit 1
}

"$repo_dir/scripts/check-cli-release-credentials.sh" >/dev/null

version=$(/usr/bin/sed -n 's/.*static let current = "\([^"]*\)".*/\1/p' \
  "$repo_dir/Sources/LocalSubCLIKit/CLIParser.swift")
/usr/bin/printf '%s\n' "$version" | /usr/bin/grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$' || {
  print -u2 -- "could not read a valid CLI version"
  exit 1
}
expected_tag="v$version"
[[ -z $(/usr/bin/git -C "$repo_dir" status --porcelain) ]] || {
  print -u2 -- "release checkout must be clean"
  exit 1
}
[[ $(/usr/bin/git -C "$repo_dir" tag --points-at HEAD) == $expected_tag ]] || {
  print -u2 -- "HEAD must have the exact tag $expected_tag"
  exit 1
}

working_dir=$(/usr/bin/mktemp -d /tmp/localsub-cli-release.XXXXXX)
cleanup() { /bin/rm -rf "$working_dir" }
trap cleanup EXIT HUP INT TERM

scratch="$working_dir/swift-build"
/usr/bin/swift build --package-path "$repo_dir" --scratch-path "$scratch" -c release --product localsub
binary="$scratch/release/localsub"
[[ -x $binary ]] || { print -u2 -- "release binary was not produced"; exit 1 }
[[ $($binary --version) == "localsub $version" ]] || {
  print -u2 -- "release binary version does not match $version"
  exit 1
}

/usr/bin/codesign --force --timestamp --options runtime \
  --sign "$LOCALSUB_SIGNING_IDENTITY" "$binary"
/usr/bin/codesign --verify --strict --verbose=2 "$binary"
actual_team_id=$(/usr/bin/codesign -dv --verbose=4 "$binary" 2>&1 \
  | /usr/bin/sed -n 's/^TeamIdentifier=//p')
[[ $actual_team_id == $LOCALSUB_EXPECTED_TEAM_ID ]] || {
  print -u2 -- "signed binary Team Identifier does not match LOCALSUB_EXPECTED_TEAM_ID"
  exit 1
}
actual_identifier=$(/usr/bin/codesign -dv --verbose=4 "$binary" 2>&1 \
  | /usr/bin/sed -n 's/^Identifier=//p')
[[ $actual_identifier == localsub ]] || {
  print -u2 -- "signed binary identifier is not localsub"
  exit 1
}

package_name="localsub-v${version}-darwin-arm64"
package_dir="$working_dir/$package_name"
/bin/mkdir "$package_dir"
/bin/cp -p "$binary" "$package_dir/localsub"
/bin/cp -p "$repo_dir/LICENSE" "$repo_dir/NOTICE" "$package_dir/"
archive="$working_dir/${package_name}.zip"
(
  cd "$working_dir"
  /usr/bin/zip -X -q -r "$archive" "$package_name"
)

/usr/bin/xcrun notarytool submit "$archive" \
  --keychain-profile "$LOCALSUB_NOTARY_PROFILE" --wait
/usr/sbin/spctl --assess --type execute --verbose=2 "$binary"

archive_sha=$(/usr/bin/shasum -a 256 "$archive" | /usr/bin/awk '{ print $1 }')
rendered="$working_dir/rendered"
"$repo_dir/scripts/render-cli-distribution.sh" \
  "$version" "$LOCALSUB_EXPECTED_TEAM_ID" "$archive_sha" "$rendered" >/dev/null

checksums="$working_dir/SHA256SUMS"
(
  cd "$working_dir"
  /usr/bin/shasum -a 256 "${package_name}.zip" "rendered/install.sh" \
    | /usr/bin/sed 's#  rendered/#  #'
) > "$checksums"

/bin/mkdir -p "$output_dir"
for artifact in "${package_name}.zip" SHA256SUMS; do
  [[ ! -e "$output_dir/$artifact" ]] || {
    print -u2 -- "refusing to replace $output_dir/$artifact"
    exit 1
  }
done
for artifact in install.sh localsub.rb; do
  [[ ! -e "$output_dir/$artifact" ]] || {
    print -u2 -- "refusing to replace $output_dir/$artifact"
    exit 1
  }
done

/bin/cp -p "$archive" "$checksums" "$output_dir/"
/bin/cp -p "$rendered/install.sh" "$rendered/localsub.rb" "$output_dir/"

print -r -- "$output_dir/${package_name}.zip"
print -r -- "$output_dir/SHA256SUMS"
print -r -- "$output_dir/install.sh"
print -r -- "$output_dir/localsub.rb"
