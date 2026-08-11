#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
artifact_dir=${1:-}
tap_dir=${2:-}
version=${3:-}
commit_sha=${4:-}
[[ -n $tap_dir && $tap_dir == /* && -d $tap_dir/.git ]] || {
  print -u2 -- "usage: $0 /absolute/artifact/directory /absolute/homebrew-tap VERSION COMMIT_SHA"
  exit 64
}
[[ -z $(/usr/bin/git -C "$repo_dir" status --porcelain) ]] || {
  print -u2 -- "LocalSub source checkout must be clean"
  exit 1
}
[[ $(/usr/bin/git -C "$repo_dir" rev-parse HEAD) == $commit_sha ]] || {
  print -u2 -- "LocalSub source checkout HEAD does not match COMMIT_SHA"
  exit 1
}
[[ $(/usr/bin/git -C "$repo_dir" rev-parse "v${version}^{commit}") == $commit_sha ]] || {
  print -u2 -- "LocalSub release tag does not match COMMIT_SHA"
  exit 1
}
[[ -z $(/usr/bin/git -C "$tap_dir" status --porcelain) ]] || {
  print -u2 -- "Homebrew tap checkout must be clean"
  exit 1
}
tap_origin=$(/usr/bin/git -C "$tap_dir" remote get-url origin)
/usr/bin/printf '%s\n' "$tap_origin" \
  | /usr/bin/grep -Eq '^(git@github\.com:|https://github\.com/)byteflare-co/homebrew-tap(\.git)?$' || {
    print -u2 -- "Homebrew tap origin is not byteflare-co/homebrew-tap"
    exit 1
  }
"$repo_dir/scripts/verify-cli-release-artifacts.sh" \
  "$artifact_dir" "$version" "$commit_sha" >/dev/null

/bin/mkdir -p "$tap_dir/Formula"
destination="$tap_dir/Formula/localsub.rb"
[[ ! -L $destination ]] || { print -u2 -- "Formula destination must not be a symlink"; exit 1 }
staged=$(/usr/bin/mktemp "$tap_dir/Formula/.localsub.rb.XXXXXX")
cleanup() { /bin/rm -f "$staged" }
trap cleanup EXIT HUP INT TERM
/usr/bin/install -m 0644 "$artifact_dir/localsub.rb" "$staged"
/bin/mv -f "$staged" "$destination"
/usr/bin/cmp -s "$artifact_dir/localsub.rb" "$destination" || {
  print -u2 -- "staged tap Formula differs from the verified release Formula"
  exit 1
}
trap - EXIT HUP INT TERM
print -r -- "$destination"
