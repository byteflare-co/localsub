#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
tap_name="byteflare-co/localsub-ci"
command -v brew >/dev/null 2>&1 || { print -u2 -- "Homebrew is required"; exit 1 }
if brew tap | /usr/bin/grep -Fqx "$tap_name"; then
  print -u2 -- "refusing to replace existing tap $tap_name"
  exit 1
fi
if brew list --formula | /usr/bin/grep -Fqx localsub; then
  print -u2 -- "refusing to replace an existing Homebrew localsub installation"
  exit 1
fi

working_dir=$(/usr/bin/mktemp -d /tmp/localsub-homebrew-test.XXXXXX)
cleanup() {
  if brew list --formula 2>/dev/null | /usr/bin/grep -Fqx localsub; then
    brew uninstall --force localsub >/dev/null
  fi
  if brew tap 2>/dev/null | /usr/bin/grep -Fqx "$tap_name"; then
    brew untap --force "$tap_name" >/dev/null
  fi
  /bin/rm -rf "$working_dir"
}
trap cleanup EXIT HUP INT TERM

version=$(/usr/bin/sed -n 's/.*static let current = "\([^"]*\)".*/\1/p' \
  "$repo_dir/Sources/LocalSubCLIKit/CLIParser.swift")
archive_root="localsub-v${version}"
archive="${archive_root}-source.tar.gz"
(
  cd "$repo_dir"
  /usr/bin/git archive --format=tar --prefix="${archive_root}/" HEAD \
    | /usr/bin/gzip -n >"$working_dir/$archive"
)
source_sha=$(/usr/bin/shasum -a 256 "$working_dir/$archive" | /usr/bin/awk '{ print $1 }')
"$repo_dir/scripts/render-cli-distribution.sh" \
  "$version" "$source_sha" "$working_dir/rendered" >/dev/null
/usr/bin/sed -i '' \
  "s#https://github.com/byteflare-co/localsub/releases/download/v${version}/${archive}#file://${working_dir}/${archive}#" \
  "$working_dir/rendered/localsub.rb"

HOMEBREW_NO_AUTO_UPDATE=1 brew tap-new "$tap_name" >/dev/null
tap_dir=$(brew --repository "$tap_name")
/bin/cp "$working_dir/rendered/localsub.rb" "$tap_dir/Formula/localsub.rb"
brew style "$tap_name/localsub"
brew audit --formula --strict "$tap_name/localsub"
HOMEBREW_NO_AUTO_UPDATE=1 brew install --build-from-source "$tap_name/localsub"
LOCALSUB_NO_UPDATE_CHECK=1 brew test "$tap_name/localsub"

/usr/bin/sed -i '' '/license/a\
  revision 1' "$tap_dir/Formula/localsub.rb"
HOMEBREW_NO_AUTO_UPDATE=1 brew upgrade --build-from-source "$tap_name/localsub"
LOCALSUB_NO_UPDATE_CHECK=1 brew test "$tap_name/localsub"
brew uninstall localsub
brew untap "$tap_name"
print -r -- "Homebrew Formula install, test, upgrade, and uninstall passed"
