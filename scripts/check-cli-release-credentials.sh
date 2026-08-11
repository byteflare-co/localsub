#!/bin/zsh
set -euo pipefail

: "${LOCALSUB_SIGNING_IDENTITY:?Set LOCALSUB_SIGNING_IDENTITY to a Developer ID Application identity}"
: "${LOCALSUB_NOTARY_PROFILE:?Set LOCALSUB_NOTARY_PROFILE to a notarytool keychain profile}"
: "${LOCALSUB_EXPECTED_TEAM_ID:?Set LOCALSUB_EXPECTED_TEAM_ID to the 10-character Apple Developer Team ID}"

/usr/bin/printf '%s\n' "$LOCALSUB_EXPECTED_TEAM_ID" | /usr/bin/grep -Eq '^[A-Z0-9]{10}$' || {
  print -u2 -- "LOCALSUB_EXPECTED_TEAM_ID must contain exactly 10 uppercase letters or digits"
  exit 64
}
[[ $(/usr/bin/uname -m) == arm64 ]] || {
  print -u2 -- "release signing requires Apple Silicon"
  exit 1
}
macos_major=$(/usr/bin/sw_vers -productVersion | /usr/bin/awk -F. '{ print $1 }')
(( macos_major >= 26 )) || {
  print -u2 -- "release signing requires macOS 26 or later"
  exit 1
}

identity_matches=$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null \
  | /usr/bin/grep -F -c "\"$LOCALSUB_SIGNING_IDENTITY\"" || true)
[[ $identity_matches -eq 1 ]] || {
  print -u2 -- "expected exactly one valid Keychain signing identity named: $LOCALSUB_SIGNING_IDENTITY"
  exit 1
}

/usr/bin/xcrun notarytool history --keychain-profile "$LOCALSUB_NOTARY_PROFILE" >/dev/null || {
  print -u2 -- "notarytool could not authenticate with Keychain profile: $LOCALSUB_NOTARY_PROFILE"
  exit 1
}

print -r -- "LocalSub release credentials are ready for Team $LOCALSUB_EXPECTED_TEAM_ID"
