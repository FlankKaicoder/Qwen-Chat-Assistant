#!/usr/bin/env bash
set -u

OUT="${1:-output/exp08_1_camera_qwen_tts_$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUT"

LOG="$OUT/run.log"
exec > >(tee "$LOG") 2>&1

echo "============================================================"
echo " Experiment 08.1: Camera -> Qwen3-VL -> TTS Playback"
echo "============================================================"
echo "time    : $(date '+%Y-%m-%d %H:%M:%S')"
echo "workdir : $(pwd)"
echo "out_dir : $OUT"
echo

PY="./.venv/bin/python"
if [ ! -x "$PY" ]; then
    PY="python3"
fi

export PYTHONPATH="$(pwd):$(pwd)/.python_packages:${PYTHONPATH:-}"
export LD_LIBRARY_PATH="$(pwd):${LD_LIBRARY_PATH:-}"

echo "==================== 1. precheck ===================="
echo "python : $PY"
$PY --version || true
echo

echo "----- qwen assets -----"
for f in \
  demo \
  imgenc \
  librknnrt.so \
  librkllmrt.so \
  qwen3-vl-2b_vision_rk3588.rknn \
  qwen3-vl-2b-instruct_w8a8_rk3588.rkllm
do
    if [ -e "$f" ]; then
        echo "[OK] $f"
        ls -lh "$f"
    else
        echo "[MISS] $f"
    fi
done
echo

echo "----- tts assets -----"
for f in \
  models/matcha-icefall-zh-baker/model-steps-3.onnx \
  models/matcha-icefall-zh-baker/lexicon.txt \
  models/matcha-icefall-zh-baker/tokens.txt \
  models/vocos-22khz-univ.onnx
do
    if [ -e "$f" ]; then
        echo "[OK] $f"
        ls -lh "$f"
    else
        echo "[MISS] $f"
    fi
done
echo

echo "----- camera config -----"
grep -nE "capture_script|photo_dir|temp_dir|placeholder_image" config/default.yaml || true
echo

echo "==================== 2. camera capture ===================="
set +e
$PY - <<'PY' > "$OUT/camera_capture_stdout.txt" 2> "$OUT/camera_capture_stderr.txt"
from pathlib import Path
from voice_assistant.config import load_config
from voice_assistant.camera import CameraAdapter

cfg = load_config("config/default.yaml")
p = CameraAdapter(cfg).capture()
print(f"PHOTO_PATH={p}")
PY
CAMERA_RC=$?
set -e

echo "camera_return_code: $CAMERA_RC"
echo
echo "----- camera stdout -----"
cat "$OUT/camera_capture_stdout.txt" || true
echo
echo "----- camera stderr -----"
cat "$OUT/camera_capture_stderr.txt" || true
echo

PHOTO="$(grep '^PHOTO_PATH=' "$OUT/camera_capture_stdout.txt" | tail -1 | cut -d= -f2-)"
echo "photo_path: $PHOTO"

if [ -n "$PHOTO" ] && [ -f "$PHOTO" ]; then
    cp -av "$PHOTO" "$OUT/captured_photo.jpg"
    echo "[OK] captured photo copied to $OUT/captured_photo.jpg"
else
    echo "[FAIL] captured photo not found"
fi
echo

echo "==================== 3. image validate ===================="
if [ -f "$OUT/captured_photo.jpg" ]; then
    file "$OUT/captured_photo.jpg" | tee "$OUT/photo_file.txt"
    sha256sum "$OUT/captured_photo.jpg" | tee "$OUT/photo_sha256.txt"
    ffprobe -hide_banner -v error \
      -select_streams v:0 \
      -show_entries stream=codec_name,width,height,pix_fmt \
      -of default=nw=1 \
      "$OUT/captured_photo.jpg" \
      > "$OUT/photo_ffprobe.txt" 2>&1 || true
    cat "$OUT/photo_ffprobe.txt"
else
    echo "[SKIP] no captured photo"
fi
echo

echo "==================== 4. qwen visual qa ===================="
QUESTION="<image>请用一句中文简短描述摄像头拍到的画面。"
echo "$QUESTION" > "$OUT/question.txt"

set +e
$PY voice_assistant.py ask "$QUESTION" \
  --image "$PHOTO" \
  --no-speak \
  --no-play \
  > "$OUT/qwen_stdout.txt" \
  2> "$OUT/qwen_stderr.txt"
QWEN_RC=$?
set -e

echo "qwen_return_code: $QWEN_RC"
echo
echo "----- qwen stdout -----"
cat "$OUT/qwen_stdout.txt" || true
echo
echo "----- qwen stderr -----"
cat "$OUT/qwen_stderr.txt" || true
echo

$PY - <<'PY' "$OUT/qwen_stdout.txt" "$OUT/qwen_answer.txt" "$OUT/qwen_parse_debug.txt"
from pathlib import Path
import sys

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
dbg = Path(sys.argv[3])

text = src.read_text(encoding="utf-8", errors="ignore")
lines = text.splitlines()

start = 0
for i, line in enumerate(lines):
    if line.strip().startswith("text  :"):
        start = i + 1
        break

answer_lines = []
skip_prefixes = (
    "==========",
    "image :",
    "text  :",
    "正在调用 Qwen demo",
)

for line in lines[start:]:
    s = line.strip()
    if not s:
        continue
    if any(s.startswith(p) for p in skip_prefixes):
        continue
    answer_lines.append(line)

answer = "\n".join(answer_lines).strip()
dst.write_text(answer, encoding="utf-8")
dbg.write_text(
    "raw_lines=%d\nstart=%d\nanswer_chars=%d\n" % (
        len(lines), start, len(answer)
    ),
    encoding="utf-8",
)
PY

ANSWER_CHARS=$(python3 - <<'PY' "$OUT/qwen_answer.txt"
from pathlib import Path
import sys
p = Path(sys.argv[1])
print(len(p.read_text(encoding="utf-8", errors="ignore").strip()) if p.exists() else 0)
PY
)

echo "qwen_answer_chars: $ANSWER_CHARS"
echo
echo "----- qwen answer parsed -----"
cat "$OUT/qwen_answer.txt" || true
echo

echo "==================== 5. tts playback ===================="
if [ "$QWEN_RC" -eq 0 ] && [ "$ANSWER_CHARS" -gt 0 ]; then
    TTS_TEXT="下面播放摄像头画面理解结果：$(cat "$OUT/qwen_answer.txt")"
else
    TTS_TEXT="实验八没有得到有效的大模型回答，因此跳过正常播报。"
fi

printf "%s\n" "$TTS_TEXT" > "$OUT/tts_text.txt"

set +e
$PY voice_assistant.py tts-stream "$TTS_TEXT" \
  > "$OUT/tts_stdout.txt" \
  2> "$OUT/tts_stderr.txt"
TTS_RC=$?
set -e

echo "tts_return_code: $TTS_RC"
echo
echo "----- tts stdout -----"
cat "$OUT/tts_stdout.txt" || true
echo
echo "----- tts stderr -----"
cat "$OUT/tts_stderr.txt" || true
echo

echo "==================== 6. abnormal check ===================="
grep -nEi "error|failed|not found|segmentation|killed|cannot|invalid|timeout|oom|exception|Traceback|ModuleNotFound|Unable to install hw params|Broken pipe|xrun|underrun" \
  "$OUT"/*.txt "$OUT"/*.log "$OUT"/*.stderr "$OUT"/*_stderr.txt 2>/dev/null \
  > "$OUT/abnormal.txt" || true

cat "$OUT/abnormal.txt" || true
echo

UNDERRUN_COUNT=$(grep -R "underrun" "$OUT" 2>/dev/null | wc -l)

echo "==================== 7. summary ===================="
{
    echo "out_dir           : $OUT"
    echo "camera_return_code: $CAMERA_RC"
    echo "qwen_return_code  : $QWEN_RC"
    echo "tts_return_code   : $TTS_RC"
    echo "photo_path        : $PHOTO"
    echo "qwen_answer_chars : $ANSWER_CHARS"
    echo "underrun_count    : $UNDERRUN_COUNT"
} | tee "$OUT/summary.txt"

echo
if [ "$CAMERA_RC" -eq 0 ] && \
   [ "$QWEN_RC" -eq 0 ] && \
   [ "$TTS_RC" -eq 0 ] && \
   [ "$ANSWER_CHARS" -gt 0 ] && \
   [ "$UNDERRUN_COUNT" -eq 0 ]; then
    echo "[RESULT] Experiment 08.1 PASSED_BY_COMMAND"
    echo "[NOTE] Please confirm by listening whether the camera description was spoken."
else
    echo "[RESULT] Experiment 08.1 NEEDS_CHECK"
fi

echo
echo "log saved to: $LOG"
