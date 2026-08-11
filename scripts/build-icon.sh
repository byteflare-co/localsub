#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
source_icon="$repo_dir/Config/LocalSub-AppIcon.png"
output_icon=${1:-"$repo_dir/.build/icon/LocalSub.icns"}
iconset_dir="$repo_dir/.build/icon/LocalSub.iconset"

test -f "$source_icon"
mkdir -p "$iconset_dir" "${output_icon:h}"

sips -z 16 16 "$source_icon" --out "$iconset_dir/icon_16x16.png" >/dev/null
sips -z 32 32 "$source_icon" --out "$iconset_dir/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$source_icon" --out "$iconset_dir/icon_32x32.png" >/dev/null
sips -z 64 64 "$source_icon" --out "$iconset_dir/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$source_icon" --out "$iconset_dir/icon_128x128.png" >/dev/null
sips -z 256 256 "$source_icon" --out "$iconset_dir/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$source_icon" --out "$iconset_dir/icon_256x256.png" >/dev/null
sips -z 512 512 "$source_icon" --out "$iconset_dir/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$source_icon" --out "$iconset_dir/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$source_icon" --out "$iconset_dir/icon_512x512@2x.png" >/dev/null

iconutil --convert icns --output "$output_icon" "$iconset_dir"
print -r -- "$output_icon"
