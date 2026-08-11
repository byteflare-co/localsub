#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
working_dir=$(/usr/bin/mktemp -d /tmp/localsub-distribution-test.XXXXXX)
cleanup() { /bin/rm -rf "$working_dir" }
trap cleanup EXIT HUP INT TERM

fake_sha=$(/usr/bin/printf 'a%.0s' {1..64})
rendered="$working_dir/rendered"
"$repo_dir/scripts/render-cli-distribution.sh" \
  "0.1.0-alpha.1" "ABCDE12345" "$fake_sha" "$rendered" >/dev/null

/bin/sh -n "$rendered/install.sh"
/usr/bin/ruby -c "$rendered/localsub.rb" >/dev/null
/usr/bin/grep -q 'version="0.1.0-alpha.1"' "$rendered/install.sh"
/usr/bin/grep -q 'expected_team_id="ABCDE12345"' "$rendered/install.sh"
/usr/bin/grep -q "sha256 \"$fake_sha\"" "$rendered/localsub.rb"
if /usr/bin/grep -q '__LOCALSUB_' "$rendered/install.sh" "$rendered/localsub.rb"; then
  print -u2 -- "rendered distribution contains an unresolved placeholder"
  exit 1
fi

if "$repo_dir/scripts/render-cli-distribution.sh" \
  "invalid" "ABCDE12345" "$fake_sha" "$working_dir/invalid" >/dev/null 2>&1; then
  print -u2 -- "renderer accepted an invalid version"
  exit 1
fi
if "$repo_dir/scripts/render-cli-distribution.sh" \
  "0.1.0" "SHORT" "$fake_sha" "$working_dir/invalid-team" >/dev/null 2>&1; then
  print -u2 -- "renderer accepted an invalid Team ID"
  exit 1
fi

release_dir="$working_dir/release"
package_dir="$working_dir/package/localsub-v0.1.0-alpha.1-darwin-arm64"
install_dir="$working_dir/install"
/bin/mkdir -p "$release_dir" "$package_dir"
/bin/cp /usr/bin/true "$package_dir/localsub"
/bin/cp "$repo_dir/LICENSE" "$repo_dir/NOTICE" "$package_dir/"
(
  cd "$working_dir/package"
  /usr/bin/zip -X -q -r "$release_dir/localsub-v0.1.0-alpha.1-darwin-arm64.zip" \
    localsub-v0.1.0-alpha.1-darwin-arm64
)
(
  cd "$release_dir"
  /usr/bin/shasum -a 256 localsub-v0.1.0-alpha.1-darwin-arm64.zip > SHA256SUMS
)

installer_error="$working_dir/installer-error.log"
if LOCALSUB_RELEASE_BASE_URL="file://$release_dir" LOCALSUB_INSTALL_DIR="$install_dir" \
  "$rendered/install.sh" >/dev/null 2>"$installer_error"; then
  print -u2 -- "installer accepted a binary from an unexpected Apple team"
  exit 1
fi
/usr/bin/grep -q 'unexpected Apple Developer Team Identifier' "$installer_error" || {
  print -u2 -- "installer did not reach the expected Team ID control"
  /bin/cat "$installer_error" >&2
  exit 1
}
[[ ! -e "$install_dir/localsub" ]] || {
  print -u2 -- "failed installer published an executable"
  exit 1
}

print -r -- "CLI distribution checks passed"
