#!/usr/bin/env bash

set -u

PROJECT_DIR="/home/cat/ai/qwen3vl2b"
cd "$PROJECT_DIR" || exit 1

OUT_DIR="${1:-output/exp10_2fb_nv12_to_jpg_isolation_$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUT_DIR"

LOG="$OUT_DIR/run.log"
exec > >(tee "$LOG") 2>&1

WIDTH=1280
HEIGHT=720
EXPECTED_SIZE=$((WIDTH * HEIGHT * 3 / 2))

SOURCE_RAW=$(
    find output/exp10_2fa_camera_isolation_3runs_* \
        -type f \
        -name '*.nv12' \
        -printf '%T@ %p\n' \
        2>/dev/null \
    | sort -nr \
    | head -1 \
    | cut -d' ' -f2-
)

echo "============================================================"
echo " Experiment 10.2f-b: NV12 to JPG Isolation"
echo "============================================================"
echo "time          : $(date '+%Y-%m-%d %H:%M:%S')"
echo "out_dir       : $OUT_DIR"
echo "source_raw    : $SOURCE_RAW"
echo "expected_size : $EXPECTED_SIZE"
echo

if [ -z "$SOURCE_RAW" ] || [ ! -f "$SOURCE_RAW" ]; then
    echo "[RESULT] SOURCE_RAW_NOT_FOUND"
    exit 1
fi

cp -a "$SOURCE_RAW" "$OUT_DIR/source.nv12"
SOURCE_RAW="$OUT_DIR/source.nv12"

ACTUAL_SIZE=$(stat -c '%s' "$SOURCE_RAW")

echo "actual_size   : $ACTUAL_SIZE"
echo

if [ "$ACTUAL_SIZE" -ne "$EXPECTED_SIZE" ]; then
    echo "[RESULT] RAW_SIZE_INVALID"
    exit 1
fi

echo "==================== 1. ffmpeg binary ===================="

type -a ffmpeg || true
command -v ffmpeg || true
readlink -f "$(command -v ffmpeg)" || true
ls -lh "$(command -v ffmpeg)" || true

echo
echo "----- version -----"

timeout --signal=TERM --kill-after=2 10 \
    ffmpeg -version \
    > "$OUT_DIR/ffmpeg_version.txt" \
    2>&1

FFMPEG_VERSION_RC=$?

cat "$OUT_DIR/ffmpeg_version.txt"
echo "ffmpeg_version_return_code: $FFMPEG_VERSION_RC"
echo

echo "==================== 2. original command test ===================="

START=$(date +%s)

timeout --signal=TERM --kill-after=3 15 \
    ffmpeg -y \
        -f rawvideo \
        -pix_fmt nv12 \
        -s "${WIDTH}x${HEIGHT}" \
        -i "$SOURCE_RAW" \
        -frames:v 1 \
        "$OUT_DIR/original.jpg" \
    > "$OUT_DIR/original_stdout.txt" \
    2> "$OUT_DIR/original_stderr.txt"

ORIGINAL_RC=$?
ORIGINAL_ELAPSED=$(($(date +%s) - START))

echo "original_return_code: $ORIGINAL_RC"
echo "original_elapsed    : $ORIGINAL_ELAPSED"

echo
echo "----- original stdout -----"
cat "$OUT_DIR/original_stdout.txt"

echo
echo "----- original stderr -----"
cat "$OUT_DIR/original_stderr.txt"

echo
ls -lh "$OUT_DIR/original.jpg" 2>/dev/null || true
echo

echo "==================== 3. nostdin command test ===================="

START=$(date +%s)

timeout --signal=TERM --kill-after=3 15 \
    ffmpeg \
        -nostdin \
        -hide_banner \
        -loglevel verbose \
        -y \
        -f rawvideo \
        -pixel_format nv12 \
        -video_size "${WIDTH}x${HEIGHT}" \
        -framerate 1 \
        -i "$SOURCE_RAW" \
        -frames:v 1 \
        -q:v 2 \
        "$OUT_DIR/nostdin.jpg" \
    > "$OUT_DIR/nostdin_stdout.txt" \
    2> "$OUT_DIR/nostdin_stderr.txt"

NOSTDIN_RC=$?
NOSTDIN_ELAPSED=$(($(date +%s) - START))

echo "nostdin_return_code: $NOSTDIN_RC"
echo "nostdin_elapsed    : $NOSTDIN_ELAPSED"

echo
echo "----- nostdin stdout -----"
cat "$OUT_DIR/nostdin_stdout.txt"

echo
echo "----- nostdin stderr -----"
cat "$OUT_DIR/nostdin_stderr.txt"

echo
ls -lh "$OUT_DIR/nostdin.jpg" 2>/dev/null || true
echo

echo "==================== 4. OpenCV fallback test ===================="

set +e

.venv/bin/python - <<'PY' \
    > "$OUT_DIR/opencv_stdout.txt" \
    2> "$OUT_DIR/opencv_stderr.txt"

from pathlib import Path

import numpy as np

try:
    import cv2
except Exception as exc:
    print(f"opencv_import_error: {type(exc).__name__}: {exc}")
    raise SystemExit(2)

width = 1280
height = 720

raw_path = Path(
    "output/"
)

raw_path = Path(__import__("sys").argv[0]) if False else None
PY

OPENCV_PRECHECK_RC=$?

set -e

# 独立执行真正的 OpenCV 转换，避免 heredoc 参数混乱。
set +e

.venv/bin/python - \
    "$SOURCE_RAW" \
    "$OUT_DIR/opencv.jpg" \
    "$WIDTH" \
    "$HEIGHT" \
    > "$OUT_DIR/opencv_stdout.txt" \
    2> "$OUT_DIR/opencv_stderr.txt" <<'PY'
from pathlib import Path
import sys

import numpy as np

try:
    import cv2
except Exception as exc:
    print(f"opencv_import_error: {type(exc).__name__}: {exc}")
    raise SystemExit(2)

raw_path = Path(sys.argv[1])
jpg_path = Path(sys.argv[2])
width = int(sys.argv[3])
height = int(sys.argv[4])

data = np.fromfile(raw_path, dtype=np.uint8)

expected = width * height * 3 // 2

print("raw_bytes:", data.size)
print("expected :", expected)

if data.size != expected:
    raise SystemExit(
        f"invalid raw size: {data.size}, expected {expected}"
    )

nv12 = data.reshape((height * 3 // 2, width))
bgr = cv2.cvtColor(nv12, cv2.COLOR_YUV2BGR_NV12)

ok = cv2.imwrite(str(jpg_path), bgr)

print("write_ok :", ok)
print("jpg_path :", jpg_path)

if not ok:
    raise SystemExit("cv2.imwrite failed")
PY

OPENCV_RC=$?

set -e

echo "opencv_return_code: $OPENCV_RC"

echo
echo "----- OpenCV stdout -----"
cat "$OUT_DIR/opencv_stdout.txt"

echo
echo "----- OpenCV stderr -----"
cat "$OUT_DIR/opencv_stderr.txt"

echo
ls -lh "$OUT_DIR/opencv.jpg" 2>/dev/null || true
echo

echo "==================== 5. output validation ===================="

for image in \
    "$OUT_DIR/original.jpg" \
    "$OUT_DIR/nostdin.jpg" \
    "$OUT_DIR/opencv.jpg"
do
    if [ -s "$image" ]; then
        echo "----- $image -----"

        ffprobe -v error \
            -select_streams v:0 \
            -show_entries \
              stream=codec_name,width,height,pix_fmt \
            -of default=noprint_wrappers=1 \
            "$image" || true

        echo
    fi
done

echo "==================== 6. summary ===================="

{
    echo "out_dir                  : $OUT_DIR"
    echo "source_raw               : $SOURCE_RAW"
    echo "expected_size            : $EXPECTED_SIZE"
    echo "actual_size              : $ACTUAL_SIZE"
    echo "ffmpeg_version_return_code: $FFMPEG_VERSION_RC"
    echo "original_return_code     : $ORIGINAL_RC"
    echo "original_elapsed_seconds : $ORIGINAL_ELAPSED"
    echo "original_jpg_exists      : $([ -s "$OUT_DIR/original.jpg" ] && echo 1 || echo 0)"
    echo "nostdin_return_code      : $NOSTDIN_RC"
    echo "nostdin_elapsed_seconds  : $NOSTDIN_ELAPSED"
    echo "nostdin_jpg_exists       : $([ -s "$OUT_DIR/nostdin.jpg" ] && echo 1 || echo 0)"
    echo "opencv_return_code       : $OPENCV_RC"
    echo "opencv_jpg_exists        : $([ -s "$OUT_DIR/opencv.jpg" ] && echo 1 || echo 0)"
} | tee "$OUT_DIR/summary.txt"

echo

if [ "$ORIGINAL_RC" -eq 0 ] \
  && [ -s "$OUT_DIR/original.jpg" ]; then

    echo "[RESULT] ORIGINAL_FFMPEG_NOW_PASSED."
    echo "[NEXT] Add per-stage timeout and detailed logging to capture-photo.sh."
elif [ "$NOSTDIN_RC" -eq 0 ] \
  && [ -s "$OUT_DIR/nostdin.jpg" ]; then

    echo "[RESULT] FFMPEG_NOSTDIN_FIX_CONFIRMED."
    echo "[NEXT] Patch capture-photo.sh with -nostdin."
elif [ "$OPENCV_RC" -eq 0 ] \
  && [ -s "$OUT_DIR/opencv.jpg" ]; then

    echo "[RESULT] FFMPEG_FAILED_BUT_OPENCV_PASSED."
    echo "[NEXT] Replace or fallback from FFmpeg to OpenCV conversion."
else
    echo "[RESULT] ALL_JPEG_CONVERSION_METHODS_FAILED."
    echo "[NEXT] Inspect FFmpeg/OpenCV logs and raw frame validity."
fi
