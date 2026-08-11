#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
version=${1:-}
team_id=${2:-}
archive_sha=${3:-}
output_dir=${4:-}

/usr/bin/printf '%s\n' "$version" | /usr/bin/grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$' || {
  print -u2 -- "usage: $0 VERSION TEAM_ID ARCHIVE_SHA256 OUTPUT_DIR"
  exit 64
}
/usr/bin/printf '%s\n' "$team_id" | /usr/bin/grep -Eq '^[A-Z0-9]{10}$' || {
  print -u2 -- "TEAM_ID must contain exactly 10 uppercase letters or digits"
  exit 64
}
/usr/bin/printf '%s\n' "$archive_sha" | /usr/bin/grep -Eq '^[0-9a-f]{64}$' || {
  print -u2 -- "ARCHIVE_SHA256 must contain exactly 64 lowercase hexadecimal characters"
  exit 64
}
[[ -n $output_dir && $output_dir == /* ]] || {
  print -u2 -- "OUTPUT_DIR must be an absolute path"
  exit 64
}

/bin/mkdir -p "$output_dir"
installer="$output_dir/install.sh"
cask="$output_dir/localsub.rb"
[[ ! -e $installer && ! -e $cask ]] || {
  print -u2 -- "refusing to replace existing rendered distribution files"
  exit 1
}

/usr/bin/sed \
  -e "s/__LOCALSUB_VERSION__/$version/g" \
  -e "s/__LOCALSUB_TEAM_ID__/$team_id/g" \
  "$repo_dir/scripts/install-cli.sh.template" > "$installer"
/bin/chmod 0755 "$installer"

/usr/bin/sed \
  -e "s/__LOCALSUB_VERSION__/$version/g" \
  -e "s/__LOCALSUB_ARCHIVE_SHA256__/$archive_sha/g" \
  "$repo_dir/packaging/homebrew/localsub.rb.template" > "$cask"

/bin/sh -n "$installer"
/usr/bin/ruby -c "$cask" >/dev/null
print -r -- "$installer"
print -r -- "$cask"
