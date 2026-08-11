#!/bin/zsh
set -euo pipefail

repository=${1:-}
tag=${2:-}
gh_path=${3:-}
attempts=${LOCALSUB_RELEASE_READBACK_ATTEMPTS:-10}
delay_seconds=${LOCALSUB_RELEASE_READBACK_DELAY_SECONDS:-1}

[[ $repository == */* && -n $tag && $tag != *'"'* && $gh_path == /* && -x $gh_path ]] || {
  print -u2 -- "usage: $0 owner/repository tag /absolute/path/to/gh"
  exit 64
}
[[ $attempts == <1-30> ]] || {
  print -u2 -- "LOCALSUB_RELEASE_READBACK_ATTEMPTS must be between 1 and 30"
  exit 64
}
[[ $delay_seconds == <0-9> ]] || {
  print -u2 -- "LOCALSUB_RELEASE_READBACK_DELAY_SECONDS must be between 0 and 9"
  exit 64
}

for attempt in {1..$attempts}; do
  release_ids=$("$gh_path" api "repos/$repository/releases" --paginate --slurp \
    --jq "flatten | .[] | select(.tag_name == \"$tag\" and .draft == true) | .id")
  release_count=$(/usr/bin/printf '%s\n' "$release_ids" \
    | /usr/bin/awk 'NF { count += 1 } END { print count + 0 }')
  if (( release_count == 1 )); then
    print -r -- "$release_ids"
    exit 0
  fi
  if (( release_count > 1 )); then
    print -u2 -- "multiple draft releases exist for $tag; refusing to choose"
    exit 1
  fi
  (( attempt == attempts )) || /bin/sleep "$delay_seconds"
done

print -u2 -- "draft release $tag was not visible after $attempts read-back attempts"
exit 1
