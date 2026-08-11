#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
version=${1:-}
source_sha=${2:-}
output_dir=${3:-}

/usr/bin/printf '%s\n' "$version" | /usr/bin/grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$' || {
  print -u2 -- "usage: $0 VERSION SOURCE_SHA256 OUTPUT_DIR"
  exit 64
}
/usr/bin/printf '%s\n' "$source_sha" | /usr/bin/grep -Eq '^[0-9a-f]{64}$' || {
  print -u2 -- "SOURCE_SHA256 must contain exactly 64 lowercase hexadecimal characters"
  exit 64
}
[[ -n $output_dir && $output_dir == /* && $output_dir != / ]] || {
  print -u2 -- "OUTPUT_DIR must be an absolute path other than /"
  exit 64
}

/bin/mkdir -p "$output_dir"
installer="$output_dir/install.sh"
formula="$output_dir/localsub.rb"
[[ ! -e $installer && ! -e $formula ]] || {
  print -u2 -- "refusing to replace existing rendered distribution files"
  exit 1
}

/usr/bin/sed \
  -e "s/__LOCALSUB_VERSION__/$version/g" \
  -e "s/__LOCALSUB_SOURCE_SHA256__/$source_sha/g" \
  "$repo_dir/scripts/install-cli.sh.template" > "$installer"
/bin/chmod 0755 "$installer"

/usr/bin/sed \
  -e "s/__LOCALSUB_VERSION__/$version/g" \
  -e "s/__LOCALSUB_SOURCE_SHA256__/$source_sha/g" \
  "$repo_dir/packaging/homebrew/localsub.rb.template" > "$formula"

/bin/sh -n "$installer"
/usr/bin/ruby -c "$formula" >/dev/null
print -r -- "$installer"
print -r -- "$formula"
