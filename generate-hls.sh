#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 INPUT_VIDEO [OUTPUT_DIR]" >&2
  exit 64
}

die() {
  echo "error: $*" >&2
  exit 1
}

[[ $# -ge 1 && $# -le 2 ]] || usage

input=$1
output_dir=${2:-"${input%.*}.hls"}

[[ -f "$input" ]] || die "input is not a file: $input"
[[ ! -e "$output_dir" ]] || die "output already exists: $output_dir"
command -v ffmpeg >/dev/null || die "ffmpeg is required"
command -v ffprobe >/dev/null || die "ffprobe is required"

source_height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$input")
[[ "$source_height" =~ ^[0-9]+$ ]] || die "could not read the primary video height"

segment_duration=5
frame_rate=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of csv=p=0 "$input")
gop=$(awk -F/ -v seconds="$segment_duration" 'NF == 2 && $2 > 0 { printf "%.0f\n", seconds * $1 / $2; found = 1 } END { if (!found) print seconds * 30 }' <<<"$frame_rate")

has_audio=0
if ffprobe -v error -select_streams a:0 -show_entries stream=index -of csv=p=0 "$input" | grep -q '[0-9]'; then
  has_audio=1
fi

heights=("$source_height")
for rung in 1080 720 480 360 240; do
  (( rung < source_height )) && heights+=("$rung")
done

bitrate_for() {
  local height=$1
  if (( height > 1440 )); then echo 16000
  elif (( height > 1080 )); then echo 10000
  elif (( height > 720 )); then echo 6000
  elif (( height > 480 )); then echo 2800
  elif (( height > 360 )); then echo 1400
  elif (( height > 240 )); then echo 800
  else echo 400
  fi
}

filter="[0:v:0]split=${#heights[@]}"
for i in "${!heights[@]}"; do
  filter+="[split${i}]"
done
filter+=';'
for i in "${!heights[@]}"; do
  filter+="[split${i}]scale=-2:${heights[$i]}:flags=lanczos,format=yuv420p[v${i}]"
  (( i + 1 < ${#heights[@]} )) && filter+=';'
done

mkdir -p "$output_dir"
for i in "${!heights[@]}"; do
  mkdir -p "$output_dir/${heights[$i]}p"
done

args=(ffmpeg -hide_banner -y -i "$input" -filter_complex "$filter")
variant_map=''
for i in "${!heights[@]}"; do
  bitrate=$(bitrate_for "${heights[$i]}")
  maxrate=$((bitrate * 107 / 100))
  args+=(
    -map "[v${i}]"
    -c:v:"$i" libx264
    -preset veryfast
    -profile:v:"$i" high
    -g:v:"$i" "$gop"
    -keyint_min:v:"$i" "$gop"
    -sc_threshold:v:"$i" 0
    -b:v:"$i" "${bitrate}k"
    -maxrate:v:"$i" "${maxrate}k"
    -bufsize:v:"$i" "$((bitrate * 2))k"
  )

  if (( has_audio )); then
    # ponytail: first audio track only; add HLS audio groups when multiple languages are required.
    args+=(-map 0:a:0 -c:a:"$i" aac -b:a:"$i" 128k -ac:a:"$i" 2)
    variant_map+="v:${i},a:${i},name:${heights[$i]}p "
  else
    variant_map+="v:${i},name:${heights[$i]}p "
  fi
done

args+=(
  -f hls
  -hls_time "$segment_duration"
  -hls_playlist_type vod
  -hls_flags independent_segments
  -hls_segment_filename "$output_dir/%v/segment_%03d.ts"
  -master_pl_name master.m3u8
  -var_stream_map "${variant_map% }"
  "$output_dir/%v/index.m3u8"
)

"${args[@]}"
echo "Created $output_dir/master.m3u8"
