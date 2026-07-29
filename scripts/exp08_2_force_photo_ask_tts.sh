#!/usr/bin/env bash
set -u

OUT="${1:-output/exp08_2_force_photo_ask_tts_$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUT"

LOG="$OUT/run.log"
exec > >(tee "$LOG") 2>&1

echo "============================================================"
echo " Experiment 08.2: official ask --force-photo -> Qwen -> TTS"
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

QUESTION="请用一句中文简短描述摄像头拍到的画面。"
echo "$QUESTION" > "$OUT/question.txt"

echo "==================== 1. official ask --force-photo ===================="
set +e
$PY voice_assistant.py ask "$QUESTION" \
  --force-photo \
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

PHOTO="$(grep '^image :' "$OUT/qwen_stdout.txt" | tail -1 | sed 's/^image :[[:space:]]*//')"
echo "photo_path: $PHOTO"

if [ -n "$PHOTO" ] && [ -f "$PHOTO" ]; then
    cp -av "$PHOTO" "$OUT/force_photo.jpg"
    echo "[OK] force photo copied to $OUT/force_photo.jpg"
else
    echo "[WARN] force photo not found or not parsed"
fi
echo

echo "==================== 2. photo validate ===================="
if [ -f "$OUT/force_photo.jpg" ]; then
    file "$OUT/force_photo.jpg" | tee "$OUT/photo_file.txt"
    sha256sum "$OUT/force_photo.jpg" | tee "$OUT/photo_sha256.txt"
    ffprobe -hide_banner -v error \
      -select_streams v:0 \
      -show_entries stream=codec_name,width,height,pix_fmt \
      -of default=nw=1 \
      "$OUT/force_photo.jpg" \
      > "$OUT/photo_ffprobe.txt" 2>&1 || true
    cat "$OUT/photo_ffprobe.txt"
else
    echo "[SKIP] no photo"
fi
echo

echo "==================== 3. parse qwen answer ===================="
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
    f"raw_lines={len(lines)}\nstart={start}\nanswer_chars={len(answer)}\n",
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
echo "----- qwen answer -----"
cat "$OUT/qwen_answer.txt" || true
echo

echo "==================== 4. tts playback ===================="
if [ "$QWEN_RC" -eq 0 ] && [ "$ANSWER_CHARS" -gt 0 ]; then
    TTS_TEXT="下面播放官方拍照问答结果：$(cat "$OUT/qwen_answer.txt")"
else
    TTS_TEXT="实验八点二没有得到有效的大模型回答。"
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

echo "==================== 5. abnormal check ===================="
grep -nEi "error|failed|not found|segmentation|killed|cannot|invalid|timeout|oom|exception|Traceback|ModuleNotFound|Unable to install hw params|Broken pipe|xrun|underrun" \
  "$OUT"/*.txt "$OUT"/*.log "$OUT"/*_stderr.txt 2>/dev/null \
  > "$OUT/abnormal.txt" || true

cat "$OUT/abnormal.txt" || true
echo

UNDERRUN_COUNT=$(grep -R "underrun" "$OUT" 2>/dev/null | wc -l)

echo "==================== 6. summary ===================="
{
    echo "out_dir          : $OUT"
    echo "qwen_return_code : $QWEN_RC"
    echo "tts_return_code  : $TTS_RC"
    echo "photo_path       : $PHOTO"
    echo "qwen_answer_chars: $ANSWER_CHARS"
    echo "underrun_count   : $UNDERRUN_COUNT"
} | tee "$OUT/summary.txt"

echo
if [ "$QWEN_RC" -eq 0 ] && \
   [ "$TTS_RC" -eq 0 ] && \
   [ "$ANSWER_CHARS" -gt 0 ] && \
   [ "$UNDERRUN_COUNT" -eq 0 ]; then
    echo "[RESULT] Experiment 08.2 PASSED_BY_COMMAND"
    echo "[NOTE] Please confirm by listening whether the force-photo answer was spoken."
else
    echo "[RESULT] Experiment 08.2 NEEDS_CHECK"
fi

echo
echo "log saved to: $LOG"
