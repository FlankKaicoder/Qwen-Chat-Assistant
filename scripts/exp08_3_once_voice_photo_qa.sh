#!/usr/bin/env bash
set -u

OUT="${1:-output/exp08_3_once_voice_photo_qa_$(date +%Y%m%d_%H%M%S)}"
SECONDS_ARG="${2:-5}"

mkdir -p "$OUT"

LOG="$OUT/run.log"
exec > >(tee "$LOG") 2>&1

echo "============================================================"
echo " Experiment 08.3: voice command -> photo -> Qwen -> TTS"
echo "============================================================"
echo "time       : $(date '+%Y-%m-%d %H:%M:%S')"
echo "workdir    : $(pwd)"
echo "out_dir    : $OUT"
echo "record_sec : $SECONDS_ARG"
echo

PY="./.venv/bin/python"
if [ ! -x "$PY" ]; then
    PY="python3"
fi

export PYTHONPATH="$(pwd):$(pwd)/.python_packages:${PYTHONPATH:-}"
export LD_LIBRARY_PATH="$(pwd):${LD_LIBRARY_PATH:-}"

PHOTO_DIR="/home/cat/图片"

echo "==================== 1. source inspect ===================="
echo "----- once / intent / force_photo related code -----"
grep -RInE "force_photo|Intent|intent|camera|capture|run_once_from_microphone|run_once_from_text" \
  voice_assistant/cli.py \
  voice_assistant/orchestrator.py \
  voice_assistant/intent.py \
  2>/dev/null | head -160 || true
echo

echo "==================== 2. mark photo dir before run ===================="
touch "$OUT/start_marker"

echo "photo_dir: $PHOTO_DIR"
echo "latest photos before:"
ls -lt "$PHOTO_DIR"/voice_*.jpg "$PHOTO_DIR"/camera_*.jpg 2>/dev/null | head -10 || true
echo

echo "==================== 3. run official once ===================="
echo "[提示] 录音开始后，请说：请描述你看到的画面"
echo

set +e
$PY voice_assistant.py once --seconds "$SECONDS_ARG" \
  > "$OUT/once_stdout.txt" \
  2> "$OUT/once_stderr.txt"
ONCE_RC=$?
set -e

echo "once_return_code: $ONCE_RC"
echo
echo "----- once stdout -----"
cat "$OUT/once_stdout.txt" || true
echo
echo "----- once stderr -----"
cat "$OUT/once_stderr.txt" || true
echo

echo "==================== 4. collect new photos ===================="
find "$PHOTO_DIR" \
  \( -name "voice_*.jpg" -o -name "camera_*.jpg" \) \
  -newer "$OUT/start_marker" \
  -type f \
  -printf "%T@ %p\n" 2>/dev/null \
  | sort -nr > "$OUT/new_photos.txt" || true

cat "$OUT/new_photos.txt" || true

PHOTO="$(head -1 "$OUT/new_photos.txt" | cut -d' ' -f2-)"
echo "new_photo_path: $PHOTO"

if [ -n "$PHOTO" ] && [ -f "$PHOTO" ]; then
    cp -av "$PHOTO" "$OUT/once_photo.jpg"
    echo "[OK] once photo copied to $OUT/once_photo.jpg"
else
    echo "[WARN] no new photo detected during once run"
fi
echo

echo "==================== 5. photo validate ===================="
if [ -f "$OUT/once_photo.jpg" ]; then
    file "$OUT/once_photo.jpg" | tee "$OUT/photo_file.txt"
    sha256sum "$OUT/once_photo.jpg" | tee "$OUT/photo_sha256.txt"
    ffprobe -hide_banner -v error \
      -select_streams v:0 \
      -show_entries stream=codec_name,width,height,pix_fmt \
      -of default=nw=1 \
      "$OUT/once_photo.jpg" \
      > "$OUT/photo_ffprobe.txt" 2>&1 || true
    cat "$OUT/photo_ffprobe.txt"
else
    echo "[SKIP] no once photo"
fi
echo

echo "==================== 6. parse recognized text and answer ===================="
$PY - <<'PY' "$OUT/once_stdout.txt" "$OUT/recognized_text.txt" "$OUT/qwen_answer.txt" "$OUT/parse_debug.txt"
from pathlib import Path
import sys

src = Path(sys.argv[1])
rec_dst = Path(sys.argv[2])
ans_dst = Path(sys.argv[3])
dbg_dst = Path(sys.argv[4])

text = src.read_text(encoding="utf-8", errors="ignore")
lines = text.splitlines()

recognized = ""
for line in lines:
    s = line.strip()
    if s.startswith("识别文本："):
        recognized = s.split("识别文本：", 1)[1].strip()
        break

# 兼容 07.7 后的整段 TTS stdout：
# 常见结构：
# 识别文本：xxx
# 正在调用 Qwen demo，请等待模型回答...
# 将使用整段 TTS：先得到完整 Qwen 回答，再合成并播放。
# <answer>
answer_lines = []
seen_qwen = False
for line in lines:
    s = line.strip()
    if "正在调用 Qwen demo" in s:
        seen_qwen = True
        continue
    if not seen_qwen:
        continue
    if not s:
        continue
    if s.startswith("将使用整段 TTS"):
        continue
    if s.startswith("将使用流式 TTS"):
        continue
    if s.startswith("识别文本："):
        continue
    if s.startswith("=========="):
        continue
    answer_lines.append(line)

answer = "\n".join(answer_lines).strip()

rec_dst.write_text(recognized, encoding="utf-8")
ans_dst.write_text(answer, encoding="utf-8")
dbg_dst.write_text(
    f"raw_lines={len(lines)}\nrecognized_chars={len(recognized)}\nanswer_chars={len(answer)}\n",
    encoding="utf-8",
)
PY

RECOGNIZED_TEXT="$(cat "$OUT/recognized_text.txt" 2>/dev/null || true)"
ANSWER_CHARS=$(python3 - <<'PY' "$OUT/qwen_answer.txt"
from pathlib import Path
import sys
p = Path(sys.argv[1])
print(len(p.read_text(encoding="utf-8", errors="ignore").strip()) if p.exists() else 0)
PY
)

echo "recognized_text: $RECOGNIZED_TEXT"
echo "qwen_answer_chars: $ANSWER_CHARS"
echo
echo "----- qwen answer -----"
cat "$OUT/qwen_answer.txt" || true
echo

echo "==================== 7. abnormal check ===================="
grep -nEi "error|failed|not found|segmentation|killed|cannot|invalid|timeout|oom|exception|Traceback|ModuleNotFound|Unable to install hw params|Broken pipe|xrun|underrun" \
  "$OUT"/*.txt "$OUT"/*.log "$OUT"/*_stderr.txt 2>/dev/null \
  > "$OUT/abnormal.txt" || true

cat "$OUT/abnormal.txt" || true
echo

UNDERRUN_COUNT=$(grep -R "underrun" "$OUT" 2>/dev/null | wc -l)
NEW_PHOTO_COUNT=$(wc -l < "$OUT/new_photos.txt" 2>/dev/null || echo 0)

echo "==================== 8. summary ===================="
{
    echo "out_dir          : $OUT"
    echo "once_return_code : $ONCE_RC"
    echo "recognized_text  : $RECOGNIZED_TEXT"
    echo "new_photo_count  : $NEW_PHOTO_COUNT"
    echo "new_photo_path   : $PHOTO"
    echo "qwen_answer_chars: $ANSWER_CHARS"
    echo "underrun_count   : $UNDERRUN_COUNT"
} | tee "$OUT/summary.txt"

echo
if [ "$ONCE_RC" -eq 0 ] && \
   [ "$NEW_PHOTO_COUNT" -gt 0 ] && \
   [ "$ANSWER_CHARS" -gt 0 ] && \
   [ "$UNDERRUN_COUNT" -eq 0 ]; then
    echo "[RESULT] Experiment 08.3 PASSED_BY_COMMAND"
    echo "[NOTE] Please confirm by listening whether the voice-triggered photo answer was spoken."
else
    echo "[RESULT] Experiment 08.3 NEEDS_CHECK"
fi

echo
echo "log saved to: $LOG"
