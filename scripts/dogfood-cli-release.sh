#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
binary_path=${1:-}
evidence_dir=${2:-}
[[ -n $binary_path && $binary_path == /* && -x $binary_path ]] || {
  print -u2 -- "usage: $0 /absolute/path/to/installed/localsub /absolute/new/evidence-directory"
  exit 64
}
[[ -n $evidence_dir && $evidence_dir == /* && $evidence_dir != / && ! -e $evidence_dir ]] || {
  print -u2 -- "evidence directory must be a new absolute path other than /"
  exit 64
}
binary_path=${binary_path:A}
ffmpeg_path=$(command -v ffmpeg || true)
ffprobe_path=$(command -v ffprobe || true)
[[ -n $ffmpeg_path && -n $ffprobe_path ]] || {
  print -u2 -- "ffmpeg and ffprobe are required for release dogfood"
  exit 1
}

/bin/mkdir -p "$evidence_dir/fixtures" "$evidence_dir/output" "$evidence_dir/logs"
fixture="$evidence_dir/fixtures/ja.mp4"
output="$evidence_dir/output/ja-captioned.mp4"

installed_version=$("$binary_path" --version)
expected_version=$(/usr/bin/sed -n 's/.*static let current = "\([^"]*\)".*/\1/p' \
  "$repo_dir/Sources/LocalSubCLIKit/CLIParser.swift")
[[ $installed_version == "localsub $expected_version" ]] || {
  print -u2 -- "installed binary version does not match this release checkout"
  exit 1
}
/usr/bin/printf '%s\n' "$installed_version" >"$evidence_dir/logs/version.log"
"$binary_path" doctor --language japanese >"$evidence_dir/logs/doctor.log" \
  2>"$evidence_dir/logs/doctor.stderr"
/usr/bin/grep -Fqx 'READY' "$evidence_dir/logs/doctor.log"

/usr/bin/say -v Kyoko -o "$evidence_dir/fixtures/ja.aiff" \
  'これはローカルサブの公開確認です。安全な字幕動画を作成します。'
"$ffmpeg_path" -hide_banner -loglevel error -y \
  -f lavfi -i color=c=navy:s=1280x720:r=30:d=8 \
  -i "$evidence_dir/fixtures/ja.aiff" -shortest \
  -c:v libx264 -pix_fmt yuv420p -c:a aac "$fixture"

"$binary_path" generate "$fixture" --output "$output" --language japanese \
  >"$evidence_dir/logs/generate.stdout" 2>"$evidence_dir/logs/generate.stderr"
for stage in inspecting extracting-audio transcribing building-cues exporting completed; do
  /usr/bin/grep -Fq "{\"stage\":\"$stage\"}" "$evidence_dir/logs/generate.stderr" || {
    print -u2 -- "missing CLI stage: $stage"
    exit 1
  }
done
[[ -s $output ]] || {
  print -u2 -- "captioned output was not created"
  exit 1
}

"$ffprobe_path" -v error -show_entries stream=index,codec_name,codec_type,duration \
  -show_entries format=duration -of json "$fixture" >"$evidence_dir/logs/input-ffprobe.json"
"$ffprobe_path" -v error -show_entries stream=index,codec_name,codec_type,duration \
  -show_entries format=duration -of json "$output" >"$evidence_dir/logs/output-ffprobe.json"
video_codec=$("$ffprobe_path" -v error -select_streams v:0 -show_entries stream=codec_name \
  -of default=nw=1:nk=1 "$output")
audio_count=$("$ffprobe_path" -v error -select_streams a -show_entries stream=index \
  -of csv=p=0 "$output" | /usr/bin/awk 'NF { count += 1 } END { print count + 0 }')
[[ $video_codec == h264 && $audio_count -eq 1 ]] || {
  print -u2 -- "output must contain H.264 video and exactly one audio stream"
  exit 1
}
input_duration=$("$ffprobe_path" -v error -show_entries format=duration -of default=nw=1:nk=1 "$fixture")
output_duration=$("$ffprobe_path" -v error -show_entries format=duration -of default=nw=1:nk=1 "$output")
/usr/bin/awk -v input="$input_duration" -v output="$output_duration" \
  'BEGIN { delta = input - output; if (delta < 0) delta = -delta; exit delta <= (1 / 15) ? 0 : 1 }' || {
    print -u2 -- "input and output duration differ by more than 1/15 second"
    exit 1
  }

: >"$evidence_dir/logs/caption-frame-signalstats.log"
max_y=0
for second in 1 2 3 4 5 6; do
  frame_stats=$("$ffmpeg_path" -hide_banner -loglevel error -ss "$second" -i "$output" \
    -frames:v 1 -vf 'crop=iw:ih/3:0:2*ih/3,signalstats,metadata=print:file=-' \
    -f null - 2>/dev/null)
  /usr/bin/printf 'second=%s\n%s\n' "$second" "$frame_stats" \
    >>"$evidence_dir/logs/caption-frame-signalstats.log"
  frame_y=$(/usr/bin/printf '%s\n' "$frame_stats" \
    | /usr/bin/sed -n 's/^lavfi.signalstats.YMAX=//p' | /usr/bin/awk 'NR == 1 { print int($1) }')
  if [[ -n $frame_y ]] && (( frame_y > max_y )); then
    max_y=$frame_y
  fi
done
(( max_y >= 200 )) || {
  print -u2 -- "no bright caption glyphs were detected in sampled lower-frame regions"
  exit 1
}

"$ffmpeg_path" -hide_banner -loglevel error -y -i "$output" \
  -vf 'fps=1,scale=640:-1,tile=4x1' -frames:v 1 "$evidence_dir/output/contact-sheet.png"
(
  cd "$evidence_dir"
  /usr/bin/shasum -a 256 output/ja-captioned.mp4 output/contact-sheet.png >logs/SHA256SUMS
)

print -r -- "LocalSub source-built CLI release dogfood passed"
print -r -- "$evidence_dir"
