#!/usr/bin/env bash
set -u

OUT_DIR="${1:-output/exp09_4b_camera_hang_diagnose_manual}"
mkdir -p "$OUT_DIR"

PY=".venv/bin/python"
if [ ! -x "$PY" ]; then
  PY="$(command -v python3)"
fi

export PYTHONPATH="$(pwd)/.python_packages:$(pwd):${PYTHONPATH:-}"

LOG="$OUT_DIR/run.log"
exec > >(tee "$LOG") 2>&1

echo "============================================================"
echo " Experiment 09.4b: camera hang diagnose after photo intent"
echo "============================================================"
echo "time    : $(date '+%Y-%m-%d %H:%M:%S')"
echo "workdir : $(pwd)"
echo "out_dir : $OUT_DIR"
echo "python  : $PY"
echo

echo "==================== 1. process check ===================="
ps -ef | grep -E "voice_assistant.py|capture-photo|v4l2-ctl|ffmpeg|arecord|aplay|demo|imgenc" | grep -v grep || true
echo

echo "==================== 2. camera device holder check ===================="
which fuser >/dev/null 2>&1 && fuser -v /dev/video11 2>&1 || true
echo

echo "==================== 3. capture work residue ===================="
ls -lah /tmp/qwen_voice_assistant 2>/dev/null || true
echo
find /tmp/qwen_voice_assistant -maxdepth 3 -type f -printf "%p %s bytes\n" 2>/dev/null | sort || true
echo

echo "==================== 4. video device quick info ===================="
ls -lh /dev/video11 /dev/video-camera0 2>/dev/null || true
echo
v4l2-ctl -d /dev/video11 --all > "$OUT_DIR/v4l2_all.txt" 2>&1 || true
tail -80 "$OUT_DIR/v4l2_all.txt"
echo

echo "==================== 5. direct capture-photo.sh with timeout ===================="
mkdir -p "$OUT_DIR/direct_capture"

echo "[RUN] timeout 45s scripts/capture-photo.sh --out-dir $OUT_DIR/direct_capture --prefix direct --timestamp manual"

timeout 45s bash scripts/capture-photo.sh \
  --out-dir "$OUT_DIR/direct_capture" \
  --prefix direct \
  --timestamp manual \
  > "$OUT_DIR/capture_photo_stdout.txt" \
  2> "$OUT_DIR/capture_photo_stderr.txt"

CAP_RC=$?

echo "capture_photo_return_code: $CAP_RC"
echo

echo "----- capture stdout -----"
cat "$OUT_DIR/capture_photo_stdout.txt"
echo

echo "----- capture stderr -----"
cat "$OUT_DIR/capture_photo_stderr.txt"
echo

echo "----- direct capture files -----"
find "$OUT_DIR/direct_capture" -maxdepth 1 -type f -printf "%p %s bytes\n" | sort || true
echo

if [ -f "$OUT_DIR/direct_capture/direct_manual.jpg" ]; then
  ffprobe -hide_banner -v error \
    -select_streams v:0 \
    -show_entries stream=codec_name,width,height,pix_fmt \
    -of default=noprint_wrappers=1 \
    "$OUT_DIR/direct_capture/direct_manual.jpg" \
    > "$OUT_DIR/direct_capture_ffprobe.txt" 2>&1 || true
  cat "$OUT_DIR/direct_capture_ffprobe.txt"
fi
echo

echo "==================== 6. minimal v4l2 1280x720 capture ===================="
RAW="$OUT_DIR/v4l2_1280x720.nv12"
JPG="$OUT_DIR/v4l2_1280x720.jpg"

echo "[RUN] timeout 30s v4l2-ctl direct capture"

timeout 30s v4l2-ctl -d /dev/video11 \
  --set-fmt-video=width=1280,height=720,pixelformat=NV12 \
  --stream-mmap=3 \
  --stream-skip=5 \
  --stream-count=1 \
  --stream-to="$RAW" \
  > "$OUT_DIR/v4l2_direct_stdout.txt" \
  2> "$OUT_DIR/v4l2_direct_stderr.txt"

V4L2_RC=$?

echo "v4l2_direct_return_code: $V4L2_RC"
echo

echo "----- v4l2 stdout -----"
cat "$OUT_DIR/v4l2_direct_stdout.txt"
echo

echo "----- v4l2 stderr -----"
cat "$OUT_DIR/v4l2_direct_stderr.txt"
echo

if [ -f "$RAW" ]; then
  RAW_SIZE=$(stat -c%s "$RAW")
  echo "raw_size: $RAW_SIZE"
  echo "expected: 1382400"

  timeout 20s ffmpeg -y -hide_banner \
    -f rawvideo \
    -pix_fmt nv12 \
    -s 1280x720 \
    -i "$RAW" \
    -frames:v 1 \
    "$JPG" \
    > "$OUT_DIR/ffmpeg_nv12_to_jpg.log" 2>&1

  FFMPEG_RC=$?
  echo "ffmpeg_return_code: $FFMPEG_RC"

  if [ -f "$JPG" ]; then
    ffprobe -hide_banner -v error \
      -select_streams v:0 \
      -show_entries stream=codec_name,width,height,pix_fmt \
      -of default=noprint_wrappers=1 \
      "$JPG" \
      > "$OUT_DIR/v4l2_jpg_ffprobe.txt" 2>&1 || true
    cat "$OUT_DIR/v4l2_jpg_ffprobe.txt"
  fi
else
  echo "[MISS] $RAW"
fi
echo

echo "==================== 7. CameraAdapter.capture() with external timeout ===================="
timeout 60s "$PY" - <<'PY' > "$OUT_DIR/camera_adapter_stdout.txt" 2> "$OUT_DIR/camera_adapter_stderr.txt"
from voice_assistant.config import load_config
from voice_assistant.camera import CameraAdapter

cfg = load_config("config/default.yaml")
p = CameraAdapter(cfg).capture()
print("image_path:", p)
print("size_bytes:", p.stat().st_size)
PY

CAM_RC=$?

echo "camera_adapter_return_code: $CAM_RC"
echo

echo "----- camera adapter stdout -----"
cat "$OUT_DIR/camera_adapter_stdout.txt"
echo

echo "----- camera adapter stderr -----"
cat "$OUT_DIR/camera_adapter_stderr.txt"
echo

CAM_IMG=$(grep -E "^image_path:" "$OUT_DIR/camera_adapter_stdout.txt" | sed 's/^image_path:[[:space:]]*//' | tail -1)

if [ -n "$CAM_IMG" ] && [ -f "$CAM_IMG" ]; then
  ffprobe -hide_banner -v error \
    -select_streams v:0 \
    -show_entries stream=codec_name,width,height,pix_fmt \
    -of default=noprint_wrappers=1 \
    "$CAM_IMG" \
    > "$OUT_DIR/camera_adapter_ffprobe.txt" 2>&1 || true
  cat "$OUT_DIR/camera_adapter_ffprobe.txt"
fi
echo

echo "==================== 8. dmesg tail ===================="
dmesg | tail -180 > "$OUT_DIR/dmesg_tail.txt" 2>&1 || true
cat "$OUT_DIR/dmesg_tail.txt"
echo

echo "==================== 9. abnormal scan ===================="
grep -nEi "error|failed|timeout|Traceback|ModuleNotFound|ImportError|Unable|Broken pipe|No such file|not found|cannot|select|VIDIOC|Input/output|busy|Device or resource|killed|oom|segmentation|exception" \
  "$OUT_DIR"/*.txt "$OUT_DIR"/*.log "$OUT_DIR"/*.stderr 2>/dev/null \
  > "$OUT_DIR/abnormal.txt" || true

cat "$OUT_DIR/abnormal.txt"
echo

echo "==================== 10. summary ===================="
DIRECT_JPG="$OUT_DIR/direct_capture/direct_manual.jpg"

DIRECT_JPG_OK=0
[ -f "$DIRECT_JPG" ] && DIRECT_JPG_OK=1

RAW_OK=0
[ -f "$RAW" ] && [ "$(stat -c%s "$RAW" 2>/dev/null || echo 0)" = "1382400" ] && RAW_OK=1

CAM_OK=0
[ "$CAM_RC" = "0" ] && [ -n "$CAM_IMG" ] && [ -f "$CAM_IMG" ] && CAM_OK=1

echo "out_dir                  : $OUT_DIR"
echo "capture_photo_return_code: $CAP_RC"
echo "direct_jpg_ok            : $DIRECT_JPG_OK"
echo "v4l2_direct_return_code  : $V4L2_RC"
echo "raw_1280x720_ok          : $RAW_OK"
echo "camera_adapter_return_code: $CAM_RC"
echo "camera_adapter_ok        : $CAM_OK"

if [ "$CAP_RC" = "0" ] && [ "$DIRECT_JPG_OK" = "1" ] && [ "$CAM_OK" = "1" ]; then
  echo "[RESULT] Experiment 09.4b CAMERA_CHAIN_OK_NOW"
elif [ "$CAP_RC" = "124" ] || [ "$V4L2_RC" = "124" ] || [ "$CAM_RC" = "124" ]; then
  echo "[RESULT] Experiment 09.4b CAMERA_CAPTURE_TIMEOUT"
else
  echo "[RESULT] Experiment 09.4b CAMERA_CHAIN_NEEDS_CHECK"
fi

echo
echo "log saved to: $LOG"
