#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
artifact_dir=${1:-}
version=${2:-}
expected_commit=${3:-}
[[ -n $artifact_dir && $artifact_dir == /* && -d $artifact_dir ]] || {
  print -u2 -- "usage: $0 /absolute/artifact/directory VERSION COMMIT_SHA"
  exit 64
}
/usr/bin/printf '%s\n' "$version" | /usr/bin/grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$' || {
  print -u2 -- "VERSION is invalid"
  exit 64
}
/usr/bin/printf '%s\n' "$expected_commit" | /usr/bin/grep -Eq '^[0-9a-f]{40}$' || {
  print -u2 -- "COMMIT_SHA must contain 40 lowercase hexadecimal characters"
  exit 64
}

archive="localsub-v${version}-source.tar.gz"
for required in "$archive" SHA256SUMS SOURCE-METADATA.json install.sh localsub.rb; do
  [[ -f "$artifact_dir/$required" && ! -L "$artifact_dir/$required" ]] || {
    print -u2 -- "missing regular release artifact: $required"
    exit 1
  }
done

source_sha=$(/usr/bin/shasum -a 256 "$artifact_dir/$archive" | /usr/bin/awk '{ print $1 }')
verification_dir=$(/usr/bin/mktemp -d /tmp/localsub-release-verification.XXXXXX)
cleanup() { /bin/rm -rf "$verification_dir" }
trap cleanup EXIT HUP INT TERM
/usr/bin/git -C "$repo_dir" cat-file -e "$expected_commit^{commit}" || {
  print -u2 -- "expected release commit is not available in the trusted checkout"
  exit 1
}
(
  cd "$repo_dir"
  /usr/bin/git archive --format=tar --prefix="localsub-v${version}/" "$expected_commit" \
    | /usr/bin/gzip -n >"$verification_dir/$archive"
)
/usr/bin/cmp -s "$verification_dir/$archive" "$artifact_dir/$archive" || {
  print -u2 -- "source archive differs from the trusted release commit"
  exit 1
}
"$repo_dir/scripts/render-cli-distribution.sh" \
  "$version" "$source_sha" "$verification_dir/rendered" >/dev/null
/usr/bin/cmp -s "$verification_dir/rendered/install.sh" "$artifact_dir/install.sh" || {
  print -u2 -- "installer differs from the trusted rendered template"
  exit 1
}
/usr/bin/cmp -s "$verification_dir/rendered/localsub.rb" "$artifact_dir/localsub.rb" || {
  print -u2 -- "Formula differs from the trusted rendered template"
  exit 1
}

metadata="$artifact_dir/SOURCE-METADATA.json"
metadata_keys=$(/usr/bin/plutil -p "$metadata" | /usr/bin/grep -c ' => ')
[[ $metadata_keys -eq 6 ]] || { print -u2 -- "source metadata must contain exactly six keys"; exit 1 }
[[ $(/usr/bin/plutil -extract version raw "$metadata") == $version ]] || {
  print -u2 -- "source metadata version does not match"
  exit 1
}
[[ $(/usr/bin/plutil -extract tag raw "$metadata") == "v$version" ]] || {
  print -u2 -- "source metadata tag does not match"
  exit 1
}
[[ $(/usr/bin/plutil -extract commit raw "$metadata") == $expected_commit ]] || {
  print -u2 -- "source metadata commit does not match"
  exit 1
}
[[ $(/usr/bin/plutil -extract source_archive raw "$metadata") == $archive ]] || {
  print -u2 -- "source metadata archive does not match"
  exit 1
}
[[ $(/usr/bin/plutil -extract source_sha256 raw "$metadata") == $source_sha ]] || {
  print -u2 -- "source metadata checksum does not match"
  exit 1
}
validated_with=$(/usr/bin/plutil -extract validated_with raw "$metadata")
[[ -n $validated_with && ${#validated_with} -le 200 ]] || {
  print -u2 -- "source metadata toolchain is missing or too long"
  exit 1
}

(
  cd "$artifact_dir"
  /usr/bin/shasum -a 256 "$archive" install.sh localsub.rb SOURCE-METADATA.json \
    >"$verification_dir/EXPECTED-SHA256SUMS"
)
/usr/bin/cmp -s "$verification_dir/EXPECTED-SHA256SUMS" "$artifact_dir/SHA256SUMS" || {
  print -u2 -- "SHA256SUMS does not exactly match the expected artifact set"
  exit 1
}
/bin/sh -n "$artifact_dir/install.sh"
/usr/bin/ruby -c "$artifact_dir/localsub.rb" >/dev/null
print -r -- "CLI release artifacts verified"
