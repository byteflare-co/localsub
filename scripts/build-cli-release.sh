#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
output_dir=${1:-}
[[ -n $output_dir && $output_dir == /* && $output_dir != / ]] || {
  print -u2 -- "usage: $0 /absolute/output/directory"
  exit 64
}
[[ $(/usr/bin/uname -m) == arm64 ]] || {
  print -u2 -- "release validation requires Apple Silicon"
  exit 1
}
macos_major=$(/usr/bin/sw_vers -productVersion | /usr/bin/awk -F. '{ print $1 }')
(( macos_major >= 26 )) || {
  print -u2 -- "release validation requires macOS 26 or later"
  exit 1
}

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
if /usr/bin/git -C "$repo_dir" ls-files -s | /usr/bin/awk '$1 == "120000" { found = 1 } END { exit found ? 0 : 1 }'; then
  print -u2 -- "release source tree must not contain symbolic links"
  exit 1
fi

working_dir=$(/usr/bin/mktemp -d /tmp/localsub-cli-release.XXXXXX)
cleanup() { /bin/rm -rf "$working_dir" }
trap cleanup EXIT HUP INT TERM

archive_root="localsub-v${version}"
archive="${archive_root}-source.tar.gz"
(
  cd "$repo_dir"
  /usr/bin/git archive --format=tar --prefix="${archive_root}/" "$expected_tag" \
    | /usr/bin/gzip -n >"$working_dir/$archive"
)
source_sha=$(/usr/bin/shasum -a 256 "$working_dir/$archive" | /usr/bin/awk '{ print $1 }')

/bin/mkdir "$working_dir/unpacked"
/usr/bin/tar -xzf "$working_dir/$archive" -C "$working_dir/unpacked"
source_dir="$working_dir/unpacked/$archive_root"
/usr/bin/swift build --package-path "$source_dir" \
  --scratch-path "$working_dir/swift-build" -c release --product localsub
binary="$working_dir/swift-build/release/localsub"
[[ -x $binary ]] || { print -u2 -- "source archive did not build localsub"; exit 1 }
[[ $(LOCALSUB_NO_UPDATE_CHECK=1 "$binary" --version) == "localsub $version" ]] || {
  print -u2 -- "source-built binary version does not match $version"
  exit 1
}

rendered="$working_dir/rendered"
"$repo_dir/scripts/render-cli-distribution.sh" \
  "$version" "$source_sha" "$rendered" >/dev/null
commit_sha=$(/usr/bin/git -C "$repo_dir" rev-parse HEAD)
xcode_version=$(/usr/bin/xcodebuild -version | /usr/bin/tr '\n' ' ' | /usr/bin/sed 's/[[:space:]]*$//')
/usr/bin/printf '{\n  "version": "%s",\n  "tag": "%s",\n  "commit": "%s",\n  "source_archive": "%s",\n  "source_sha256": "%s",\n  "validated_with": "%s"\n}\n' \
  "$version" "$expected_tag" "$commit_sha" "$archive" "$source_sha" "$xcode_version" \
  >"$working_dir/SOURCE-METADATA.json"
(
  cd "$working_dir"
  /usr/bin/shasum -a 256 "$archive" rendered/install.sh rendered/localsub.rb SOURCE-METADATA.json \
    | /usr/bin/sed 's#  rendered/#  #' >SHA256SUMS
)

/bin/mkdir -p "$output_dir"
for artifact in "$archive" SHA256SUMS SOURCE-METADATA.json install.sh localsub.rb; do
  [[ ! -e "$output_dir/$artifact" ]] || {
    print -u2 -- "refusing to replace $output_dir/$artifact"
    exit 1
  }
done
/bin/cp -p "$working_dir/$archive" "$working_dir/SHA256SUMS" \
  "$working_dir/SOURCE-METADATA.json" "$output_dir/"
/bin/cp -p "$rendered/install.sh" "$rendered/localsub.rb" "$output_dir/"
"$repo_dir/scripts/verify-cli-release-artifacts.sh" \
  "$output_dir" "$version" "$commit_sha" >/dev/null

for artifact in "$archive" SHA256SUMS SOURCE-METADATA.json install.sh localsub.rb; do
  print -r -- "$output_dir/$artifact"
done
