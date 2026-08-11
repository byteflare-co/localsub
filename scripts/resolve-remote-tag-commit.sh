#!/bin/zsh
set -euo pipefail

repository_dir=${1:-}
remote=${2:-}
tag=${3:-}
[[ -n $repository_dir && $repository_dir == /* && -d $repository_dir && -n $remote && -n $tag ]] || {
  print -u2 -- "usage: $0 /absolute/repository/directory REMOTE TAG"
  exit 64
}
/usr/bin/printf '%s\n' "$tag" | /usr/bin/grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$' || {
  print -u2 -- "TAG is invalid"
  exit 64
}

/usr/bin/git -C "$repository_dir" ls-remote --tags "$remote" \
  "refs/tags/$tag" "refs/tags/$tag^{}" \
  | /usr/bin/awk -v direct="refs/tags/$tag" -v peeled="refs/tags/$tag^{}" '
      $2 == direct { direct_sha = $1; direct_count += 1 }
      $2 == peeled { peeled_sha = $1; peeled_count += 1 }
      END {
        if (direct_count != 1 || peeled_count > 1) exit 1
        print (peeled_count == 1 ? peeled_sha : direct_sha)
      }
    '
