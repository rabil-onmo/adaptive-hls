#!/usr/bin/env bash
set -euo pipefail
# Bash options make failures visible instead of silently producing partial HLS output.
# `-u` rejects unset variables, and `pipefail` preserves failures inside pipelines.


# Print the supported command-line shape and use sysexits' usage-error status.

usage() {
  echo "Usage: $0 INPUT_VIDEO [OUTPUT_DIR]" >&2
  exit 64
}

# Report runtime validation failures separately from argument-usage failures.

die() {
  echo "error: $*" >&2
  exit 1
}

# The script accepts the input video and an optional output directory.

[[ $# -ge 1 && $# -le 2 ]] || usage

# Keep the input path exactly as supplied; derive a predictable default output name.

input=$1
output_dir=${2:-"${input%.*}.hls"}

# Refuse invalid input, accidental overwrites, or missing FFmpeg tools before probing.

[[ -f "$input" ]] || die "input is not a file: $input"
[[ ! -e "$output_dir" ]] || die "output already exists: $output_dir"
command -v ffmpeg >/dev/null || die "ffmpeg is required"
command -v ffprobe >/dev/null || die "ffprobe is required"

# Read the primary video stream's height. This becomes the highest rendition rather
# than assuming that every source is 1080p or larger.

source_height=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$input")
[[ "$source_height" =~ ^[0-9]+$ ]] || die "could not read the primary video height"

# Five-second VOD segments balance startup latency, request overhead, and cacheability.

segment_duration=5
# Calculate a closed GOP matching the segment duration so segment boundaries can begin
# on keyframes. FFprobe normally returns a fractional rate such as 30000/1001.

frame_rate=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of csv=p=0 "$input")
gop=$(awk -F/ -v seconds="$segment_duration" 'NF == 2 && $2 > 0 { printf "%.0f\n", seconds * $1 / $2; found = 1 } END { if (!found) print seconds * 30 }' <<<"$frame_rate")

# Audio is optional. Probe once and add the first audio stream to every video variant
# only when the source actually contains audio.

has_audio=0
if ffprobe -v error -select_streams a:0 -show_entries stream=index -of csv=p=0 "$input" | grep -q '[0-9]'; then
  has_audio=1
fi

# Preserve the source height, then append only standard lower rungs that do not upscale
# the input. The order is also the order used in the master playlist.

heights=("$source_height")
for rung in 1080 720 480 360 240; do
  (( rung < source_height )) && heights+=("$rung")
done

# Return a target video bitrate in kbit/s for a rendition height. These conservative
# defaults keep the ladder useful across common resolutions without extra configuration.

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

# Split the decoded source once, then scale each branch independently. One filter graph
# avoids decoding the same input separately for every rendition.

filter="[0:v:0]split=${#heights[@]}"
for i in "${!heights[@]}"; do
  filter+="[split${i}]"
done
filter+=';'
for i in "${!heights[@]}"; do
  filter+="[split${i}]scale=-2:${heights[$i]}:flags=lanczos,format=yuv420p[v${i}]"
  (( i + 1 < ${#heights[@]} )) && filter+=';'
done

# FFmpeg writes playlists and segments into one directory per rendition, so create the
# complete output layout before encoding starts.

mkdir -p "$output_dir"
for i in "${!heights[@]}"; do
  mkdir -p "$output_dir/${heights[$i]}p"
done

# Build FFmpeg's argument vector as a Bash array. Arrays preserve paths and values with
# spaces without requiring fragile shell quoting or an eval.

args=(ffmpeg -hide_banner -y -i "$input" -filter_complex "$filter")
# `var_stream_map` describes how each encoded video stream pairs with its audio stream
# and supplies the rendition name used by `%v` in the output paths.

variant_map=''
# Add one independent video output for every selected height.

for i in "${!heights[@]}"; do
# Apply the ladder bitrate and a small 7% ceiling for rate control. The two-second
# buffer gives the encoder room to smooth short complexity spikes.

  bitrate=$(bitrate_for "${heights[$i]}")
  maxrate=$((bitrate * 107 / 100))
  args+=(
# Map the filtered video branch and configure H.264 settings shared by all variants.

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

# Use the first audio track for each rendition. A source without audio remains video-only;
# separate language tracks would require HLS audio groups instead of this simple map.

  if (( has_audio )); then
    # ponytail: first audio track only; add HLS audio groups when multiple languages are required.
    args+=(-map 0:a:0 -c:a:"$i" aac -b:a:"$i" 128k -ac:a:"$i" 2)
    variant_map+="v:${i},a:${i},name:${heights[$i]}p "
  else
    variant_map+="v:${i},name:${heights[$i]}p "
  fi
done

# Configure the HLS muxer for VOD playlists. Fixed GOPs and independent-segment flags
# make each segment decodable on its own and let players switch renditions safely.

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

# Execute the assembled command only after all streams, mappings, and output settings
# have been constructed.

"${args[@]}"
# The master playlist is the entry point players should load.

echo "Created $output_dir/master.m3u8"
