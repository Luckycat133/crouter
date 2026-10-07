#!/bin/sh
set -eu

[ "$#" -ge 2 ] && [ "$#" -le 3 ] || {
  printf 'usage: %s VIDEO OUTPUT_DIR [FRAME_COUNT]\n' "$0" >&2
  exit 2
}

video=$1
output_dir=$2
frame_count=${3:-16}

[ -f "$video" ] || { printf 'video not found: %s\n' "$video" >&2; exit 2; }
case $frame_count in *[!0-9]*|'') printf 'FRAME_COUNT must be an integer\n' >&2; exit 2 ;; esac
[ "$frame_count" -ge 4 ] && [ "$frame_count" -le 32 ] || {
  printf 'FRAME_COUNT must be between 4 and 32\n' >&2
  exit 2
}

command -v ffmpeg >/dev/null 2>&1 || { printf 'ffmpeg is required\n' >&2; exit 3; }
command -v ffprobe >/dev/null 2>&1 || { printf 'ffprobe is required\n' >&2; exit 3; }

duration=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$video")
awk -v value="$duration" 'BEGIN { exit !(value > 0) }' || {
  printf 'could not determine a positive video duration\n' >&2
  exit 3
}

mkdir -p "$output_dir"
rate=$(awk -v frames="$frame_count" -v seconds="$duration" 'BEGIN { printf "%.10f", frames / seconds }')

ffmpeg -hide_banner -loglevel error -y -i "$video" \
  -vf "fps=${rate},scale=1280:-2" -frames:v "$frame_count" -q:v 2 \
  "$output_dir/frame-%03d.jpg"

columns=4
rows=$(( (frame_count + columns - 1) / columns ))
ffmpeg -hide_banner -loglevel error -y -framerate 1 -i "$output_dir/frame-%03d.jpg" \
  -vf "scale=480:-2,tile=${columns}x${rows}:padding=8:margin=8:color=black" \
  -frames:v 1 "$output_dir/storyboard-001.jpg"

printf '{"video":"%s","duration_seconds":%s,"requested_frames":%s,"storyboard":"%s/storyboard-001.jpg"}\n' \
  "$video" "$duration" "$frame_count" "$output_dir"
