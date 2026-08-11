#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
working_dir=$(/usr/bin/mktemp -d /tmp/localsub-distribution-test.XXXXXX)
cleanup() { /bin/rm -rf "$working_dir" }
trap cleanup EXIT HUP INT TERM

fake_sha=$(/usr/bin/printf 'a%.0s' {1..64})
current_version=$(/usr/bin/sed -n 's/.*static let current = "\([^"]*\)".*/\1/p' \
  "$repo_dir/Sources/LocalSubCLIKit/CLIParser.swift")
[[ $current_version == *-* ]] || {
  print -u2 -- "distribution test expects the current release to be a prerelease"
  exit 1
}
for install_doc in "$repo_dir/README.md" "$repo_dir/docs/README.en.md" "$repo_dir/docs/cli-distribution.md"; do
  /usr/bin/grep -Fq "/releases/download/v${current_version}/install.sh" "$install_doc" || {
    print -u2 -- "prerelease installer URL is not version-pinned in $install_doc"
    exit 1
  }
  /usr/bin/grep -Fq 'brew install byteflare-co/tap/localsub' "$install_doc" || {
    print -u2 -- "Homebrew Formula install command is missing from $install_doc"
    exit 1
  }
  if /usr/bin/grep -Fq 'brew install --cask byteflare-co/tap/localsub' "$install_doc"; then
    print -u2 -- "CLI documentation still points to the retired binary Cask"
    exit 1
  fi
done

rendered="$working_dir/rendered"
"$repo_dir/scripts/render-cli-distribution.sh" \
  "$current_version" "$fake_sha" "$rendered" >/dev/null

/bin/sh -n "$rendered/install.sh"
/usr/bin/ruby -c "$rendered/localsub.rb" >/dev/null
if command -v brew >/dev/null 2>&1; then
  # The public tap may already contain the same class; only suppress that cross-file duplicate.
  brew style --except-cops Lint/DuplicateMethods "$rendered/localsub.rb" >/dev/null
fi
/bin/zsh -n "$repo_dir/scripts/dogfood-cli-release.sh"
/bin/zsh -n "$repo_dir/scripts/readback-draft-release-id.sh"
/usr/bin/grep -q "version=\"$current_version\"" "$rendered/install.sh"
/usr/bin/grep -q "sha256 \"$fake_sha\"" "$rendered/localsub.rb"
/usr/bin/grep -q '^class Localsub < Formula$' "$rendered/localsub.rb"
/usr/bin/grep -q 'license "Apache-2.0"' "$rendered/localsub.rb"
/usr/bin/grep -q 'depends_on macos: :tahoe' "$rendered/localsub.rb"
/usr/bin/grep -q 'swift.*build' "$rendered/localsub.rb"
/usr/bin/grep -q 'LOCALSUB_NO_UPDATE_CHECK=1' "$rendered/install.sh" "$rendered/localsub.rb"
if /usr/bin/grep -q '__LOCALSUB_' "$rendered/install.sh" "$rendered/localsub.rb"; then
  print -u2 -- "rendered distribution contains an unresolved placeholder"
  exit 1
fi

if "$repo_dir/scripts/render-cli-distribution.sh" \
  "invalid" "$fake_sha" "$working_dir/invalid" >/dev/null 2>&1; then
  print -u2 -- "renderer accepted an invalid version"
  exit 1
fi

fake_gh="$working_dir/fake-gh"
fake_gh_state="$working_dir/fake-gh-state"
/usr/bin/touch "$fake_gh_state"
/bin/chmod 600 "$fake_gh_state"
/usr/bin/printf '%s\n' '#!/bin/zsh' \
  'set -euo pipefail' \
  'count=$(/usr/bin/wc -l <"$LOCALSUB_FAKE_GH_STATE")' \
  '/usr/bin/printf "call\\n" >>"$LOCALSUB_FAKE_GH_STATE"' \
  'if (( count >= 2 )); then /usr/bin/printf "123456\\n"; fi' \
  >"$fake_gh"
/bin/chmod 700 "$fake_gh"
draft_id=$(LOCALSUB_FAKE_GH_STATE="$fake_gh_state" \
  LOCALSUB_RELEASE_READBACK_ATTEMPTS=3 LOCALSUB_RELEASE_READBACK_DELAY_SECONDS=0 \
  "$repo_dir/scripts/readback-draft-release-id.sh" \
  byteflare-co/localsub v9.9.9 "$fake_gh")
[[ $draft_id == 123456 ]]
[[ $(/usr/bin/wc -l <"$fake_gh_state") -eq 3 ]]
if "$repo_dir/scripts/render-cli-distribution.sh" \
  "0.1.0" "short" "$working_dir/invalid-sha" >/dev/null 2>&1; then
  print -u2 -- "renderer accepted an invalid source checksum"
  exit 1
fi

tag_fixture="$working_dir/tag-fixture"
tag_remote="$working_dir/tag-remote.git"
/usr/bin/git clone --quiet --no-hardlinks "$repo_dir" "$tag_fixture"
/usr/bin/git init --quiet --bare "$tag_remote"
/usr/bin/git -C "$tag_fixture" tag -f v9.9.8
/usr/bin/git -C "$tag_fixture" tag -f -a v9.9.9 -m 'annotated release fixture'
/usr/bin/git -C "$tag_fixture" push --quiet "$tag_remote" \
  refs/tags/v9.9.8 refs/tags/v9.9.9
fixture_commit=$(/usr/bin/git -C "$tag_fixture" rev-parse HEAD)
[[ $("$repo_dir/scripts/resolve-remote-tag-commit.sh" "$tag_fixture" "$tag_remote" v9.9.8) == $fixture_commit ]]
[[ $("$repo_dir/scripts/resolve-remote-tag-commit.sh" "$tag_fixture" "$tag_remote" v9.9.9) == $fixture_commit ]]

release_dir="$working_dir/release"
archive_root="localsub-v${current_version}"
archive="${archive_root}-source.tar.gz"
install_dir="$working_dir/install"
/bin/mkdir -p "$release_dir"
(
  cd "$repo_dir"
  /usr/bin/git archive --format=tar --prefix="${archive_root}/" HEAD \
    | /usr/bin/gzip -n >"$release_dir/$archive"
)
(
  cd "$release_dir"
  /usr/bin/shasum -a 256 "$archive" > SHA256SUMS
)
source_sha=$(/usr/bin/shasum -a 256 "$release_dir/$archive" | /usr/bin/awk '{ print $1 }')
install_rendered="$working_dir/install-rendered"
"$repo_dir/scripts/render-cli-distribution.sh" \
  "$current_version" "$source_sha" "$install_rendered" >/dev/null
commit_sha=$(/usr/bin/git -C "$repo_dir" rev-parse HEAD)
/usr/bin/printf '{\n  "version": "%s",\n  "tag": "v%s",\n  "commit": "%s",\n  "source_archive": "%s",\n  "source_sha256": "%s",\n  "validated_with": "test fixture"\n}\n' \
  "$current_version" "$current_version" "$commit_sha" "$archive" "$source_sha" \
  >"$release_dir/SOURCE-METADATA.json"
/bin/cp "$install_rendered/install.sh" "$install_rendered/localsub.rb" "$release_dir/"
(
  cd "$release_dir"
  /usr/bin/shasum -a 256 "$archive" install.sh localsub.rb SOURCE-METADATA.json >SHA256SUMS
)
"$repo_dir/scripts/verify-cli-release-artifacts.sh" \
  "$release_dir" "$current_version" "$commit_sha" >/dev/null
/bin/mkdir "$working_dir/forged-release"
/bin/cp "$release_dir/$archive" "$release_dir/install.sh" "$release_dir/localsub.rb" \
  "$release_dir/SOURCE-METADATA.json" "$release_dir/SHA256SUMS" "$working_dir/forged-release/"
/usr/bin/printf 'forged-source' >>"$working_dir/forged-release/$archive"
forged_sha=$(/usr/bin/shasum -a 256 "$working_dir/forged-release/$archive" | /usr/bin/awk '{ print $1 }')
/usr/bin/printf '{\n  "version": "%s",\n  "tag": "v%s",\n  "commit": "%s",\n  "source_archive": "%s",\n  "source_sha256": "%s",\n  "validated_with": "forged fixture"\n}\n' \
  "$current_version" "$current_version" "$commit_sha" "$archive" "$forged_sha" \
  >"$working_dir/forged-release/SOURCE-METADATA.json"
"$repo_dir/scripts/render-cli-distribution.sh" \
  "$current_version" "$forged_sha" "$working_dir/forged-rendered" >/dev/null
/bin/cp "$working_dir/forged-rendered/install.sh" "$working_dir/forged-rendered/localsub.rb" \
  "$working_dir/forged-release/"
(
  cd "$working_dir/forged-release"
  /usr/bin/shasum -a 256 "$archive" install.sh localsub.rb SOURCE-METADATA.json >SHA256SUMS
)
if "$repo_dir/scripts/verify-cli-release-artifacts.sh" \
  "$working_dir/forged-release" "$current_version" "$commit_sha" >/dev/null 2>&1; then
  print -u2 -- "release verifier accepted an internally consistent forged source archive"
  exit 1
fi
/bin/cp "$release_dir/install.sh" "$working_dir/trusted-install.sh"
/usr/bin/printf '\nmalicious-command\n' >>"$release_dir/install.sh"
if "$repo_dir/scripts/verify-cli-release-artifacts.sh" \
  "$release_dir" "$current_version" "$commit_sha" >/dev/null 2>&1; then
  print -u2 -- "release verifier accepted a modified installer and self-reported manifest"
  exit 1
fi
/bin/cp "$working_dir/trusted-install.sh" "$release_dir/install.sh"

LOCALSUB_RELEASE_BASE_URL="file://$release_dir" LOCALSUB_INSTALL_DIR="$install_dir" \
  "$install_rendered/install.sh" >/dev/null
[[ -x "$install_dir/localsub" ]] || {
  print -u2 -- "source installer did not publish an executable"
  exit 1
}
LOCALSUB_NO_UPDATE_CHECK=1 "$install_dir/localsub" --version \
  | /usr/bin/grep -Fqx "localsub $current_version"

bad_release="$working_dir/bad-release"
/bin/mkdir "$bad_release"
/bin/cp "$release_dir/$archive" "$bad_release/$archive"
/usr/bin/printf 'tampered' >>"$bad_release/$archive"
if LOCALSUB_RELEASE_BASE_URL="file://$bad_release" \
  LOCALSUB_INSTALL_DIR="$working_dir/bad-install" "$install_rendered/install.sh" >/dev/null 2>&1; then
  print -u2 -- "installer accepted a source archive with a mismatched checksum"
  exit 1
fi
[[ ! -e "$working_dir/bad-install/localsub" ]] || {
  print -u2 -- "failed installer published an executable"
  exit 1
}

symlink_release="$working_dir/symlink-release"
/bin/mkdir -p "$symlink_release/$archive_root"
/bin/cp "$repo_dir/Package.swift" "$symlink_release/$archive_root/Package.swift"
/bin/ln -s /tmp "$symlink_release/$archive_root/escape"
(
  cd "$symlink_release"
  /usr/bin/tar -czf "$archive" "$archive_root"
)
symlink_sha=$(/usr/bin/shasum -a 256 "$symlink_release/$archive" | /usr/bin/awk '{ print $1 }')
symlink_rendered="$working_dir/symlink-rendered"
"$repo_dir/scripts/render-cli-distribution.sh" \
  "$current_version" "$symlink_sha" "$symlink_rendered" >/dev/null
if LOCALSUB_RELEASE_BASE_URL="file://$symlink_release" \
  LOCALSUB_INSTALL_DIR="$working_dir/symlink-install" \
  "$symlink_rendered/install.sh" >/dev/null 2>&1; then
  print -u2 -- "installer accepted a source archive containing a symbolic link"
  exit 1
fi
[[ ! -e "$working_dir/symlink-install/localsub" ]] || {
  print -u2 -- "symlink archive failure published an executable"
  exit 1
}

if "$repo_dir/scripts/dogfood-cli-release.sh" >/dev/null 2>&1; then
  print -u2 -- "release dogfood accepted missing paths"
  exit 1
fi

print -r -- "CLI source distribution checks passed"
