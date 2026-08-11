#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
artifact_dir=${1:-}
notes_file=${2:-}
repository="byteflare-co/localsub"
gh_path=$(command -v gh || true)

[[ -n $gh_path ]] || { print -u2 -- "gh is required"; exit 1 }
[[ -n $artifact_dir && $artifact_dir == /* && -d $artifact_dir ]] || {
  print -u2 -- "usage: $0 /absolute/artifact/directory /absolute/release-notes.md"
  exit 64
}
[[ -n $notes_file && $notes_file == /* && -f $notes_file ]] || {
  print -u2 -- "release notes must be an absolute path to a regular file"
  exit 64
}
[[ -z $(/usr/bin/git -C "$repo_dir" status --porcelain) ]] || {
  print -u2 -- "release checkout must be clean"
  exit 1
}

version=$(/usr/bin/sed -n 's/.*static let current = "\([^"]*\)".*/\1/p' \
  "$repo_dir/Sources/LocalSubCLIKit/CLIParser.swift")
tag="v$version"
head_sha=$(/usr/bin/git -C "$repo_dir" rev-parse HEAD)
[[ $(/usr/bin/git -C "$repo_dir" rev-parse "$tag^{commit}") == $head_sha ]] || {
  print -u2 -- "local tag $tag does not resolve to HEAD"
  exit 1
}
remote_tag_sha=$("$repo_dir/scripts/resolve-remote-tag-commit.sh" \
  "$repo_dir" origin "$tag")
[[ $remote_tag_sha == $head_sha ]] || {
  print -u2 -- "remote tag $tag does not resolve to HEAD"
  exit 1
}

archive="localsub-v${version}-source.tar.gz"
"$repo_dir/scripts/verify-cli-release-artifacts.sh" \
  "$artifact_dir" "$version" "$head_sha"

"$gh_path" auth status >/dev/null
immutable=$("$gh_path" api "repos/$repository/immutable-releases" --jq .enabled)
[[ $immutable == true ]] || {
  print -u2 -- "GitHub immutable releases must be enabled before publication"
  exit 1
}
if "$gh_path" release view "$tag" --repo "$repository" >/dev/null 2>&1; then
  print -u2 -- "release $tag already exists; refusing to replace it"
  exit 1
fi

"$gh_path" release create "$tag" \
  "$artifact_dir/$archive" \
  "$artifact_dir/SHA256SUMS" \
  "$artifact_dir/SOURCE-METADATA.json" \
  "$artifact_dir/install.sh" \
  "$artifact_dir/localsub.rb" \
  --repo "$repository" \
  --verify-tag \
  --draft \
  --prerelease \
  --title "LocalSub CLI $tag" \
  --notes-file "$notes_file"

release_ids=$("$gh_path" api "repos/$repository/releases" --paginate \
  --jq ".[] | select(.tag_name == \"$tag\" and .draft == true) | .id")
release_count=$(/usr/bin/printf '%s\n' "$release_ids" | /usr/bin/awk 'NF { count += 1 } END { print count + 0 }')
[[ $release_count -eq 1 ]] || { print -u2 -- "expected exactly one draft release"; exit 1 }
release_id=$release_ids
"$gh_path" api --method PATCH "repos/$repository/releases/$release_id" \
  -F draft=false -F prerelease=true >/dev/null

"$gh_path" release view "$tag" --repo "$repository" \
  --json url,isDraft,isPrerelease,tagName,targetCommitish
