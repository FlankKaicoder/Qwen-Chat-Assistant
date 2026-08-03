#!/usr/bin/env bash
set -euo pipefail

device="/dev/video11"
width="1280"
height="720"
pixfmt="NV12"
skip="5"
out_dir="/home/cat/图片"
prefix="camera"
timestamp=""

usage() {
  cat <<'USAGE'
Usage: capture-photo.sh [options]

Capture one still frame from the LubanCat IMX415 camera using the known working
NV12 camera pipeline, then convert it to JPG.

Options:
  --device PATH     V4L2 capture node (default: /dev/video11)
  --width N         Capture width (default: 1280)
  --height N        Capture height (default: 720)
  --pixfmt FOURCC   Pixel format (default: NV12)
  --skip N          Frames to skip before saving (default: 5)
  --out-dir DIR     Directory for outputs (default: /home/cat/图片)
  --prefix NAME     Output filename prefix (default: camera)
  --timestamp TS    Use explicit timestamp instead of date +%Y%m%d_%H%M%S
  -h, --help        Show this help
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --device)
      device="${2:?missing value for --device}"
      shift 2
      ;;
    --width)
      width="${2:?missing value for --width}"
      shift 2
      ;;
    --height)
      height="${2:?missing value for --height}"
      shift 2
      ;;
    --pixfmt)
      pixfmt="${2:?missing value for --pixfmt}"
      shift 2
      ;;
    --skip)
      skip="${2:?missing value for --skip}"
      shift 2
      ;;
    --out-dir)
      out_dir="${2:?missing value for --out-dir}"
      shift 2
      ;;
    --prefix)
      prefix="${2:?missing value for --prefix}"
      shift 2
      ;;
    --timestamp)
      timestamp="${2:?missing value for --timestamp}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

command -v v4l2-ctl >/dev/null 2>&1 || {
  echo "v4l2-ctl not found" >&2
  exit 127
}

command -v ffmpeg >/dev/null 2>&1 || {
  echo "ffmpeg not found" >&2
  exit 127
}

mkdir -p "$out_dir"

if [ -z "$timestamp" ]; then
  timestamp="$(date +%Y%m%d_%H%M%S)"
fi

base="${out_dir%/}/${prefix}_${timestamp}"
raw_path="${base}.nv12"
jpg_path="${base}.jpg"

v4l2-ctl -d "$device" \
  --set-fmt-video="width=${width},height=${height},pixelformat=${pixfmt}" \
  --stream-mmap=4 \
  --stream-skip="$skip" \
  --stream-count=1 \
  --stream-to="$raw_path"

case "$pixfmt" in
  NV12|nv12)
    ff_pixfmt="nv12"
    ;;
  *)
    echo "Unsupported conversion pixel format: $pixfmt" >&2
    echo "Raw frame saved: $raw_path" >&2
    exit 3
    ;;
esac

ffmpeg_stderr="${base}_ffmpeg.stderr.log"

set +e

timeout --signal=TERM --kill-after=2 10 \
  ffmpeg \
    -nostdin \
    -hide_banner \
    -loglevel error \
    -y \
    -f rawvideo \
    -pixel_format "$ff_pixfmt" \
    -video_size "${width}x${height}" \
    -framerate 1 \
    -i "$raw_path" \
    -frames:v 1 \
    -q:v 2 \
    "$jpg_path" \
    >/dev/null \
    2>"$ffmpeg_stderr"

ffmpeg_rc=$?

set -e

if [ "$ffmpeg_rc" -ne 0 ]; then
  echo "FFmpeg conversion failed, return code: $ffmpeg_rc" >&2
  echo "raw_path: $raw_path" >&2
  echo "jpg_path: $jpg_path" >&2

  if [ -s "$ffmpeg_stderr" ]; then
    echo "FFmpeg stderr:" >&2
    cat "$ffmpeg_stderr" >&2
  fi

  exit "$ffmpeg_rc"
fi

rm -f "$ffmpeg_stderr"

raw_size="$(stat -c '%s' "$raw_path")"

printf 'jpg=%s\n' "$jpg_path"
printf 'raw=%s\n' "$raw_path"
printf 'raw_size=%s\n' "$raw_size"
printf 'device=%s\n' "$device"
printf 'format=%sx%s %s\n' "$width" "$height" "$pixfmt"
