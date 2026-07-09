#!/usr/bin/env bash

set -u

PROJECT_DIR="/home/cat/ai/qwen3vl2b"
cd "$PROJECT_DIR" || exit 1

OUT="${1:-output/exp07_7_patch_once_nonstream_tts_$(date +%Y%m%d_%H%M%S)}"
REC_SECONDS="${2:-5}"

mkdir -p "$OUT"

LOG="$OUT/run.log"
exec > >(tee "$LOG") 2>&1

export PYTHONPATH="$PROJECT_DIR:$PROJECT_DIR/.python_packages:${PYTHONPATH:-}"
export LD_LIBRARY_PATH="$PROJECT_DIR:${LD_LIBRARY_PATH:-}"

PY="$PROJECT_DIR/.venv/bin/python"
if [ ! -x "$PY" ]; then
    PY="$(command -v python3)"
fi

echo "============================================================"
echo " Experiment 07.7: patch once to non-stream TTS playback"
echo "============================================================"
echo "time        : $(date '+%Y-%m-%d %H:%M:%S')"
echo "project_dir : $PROJECT_DIR"
echo "out_dir     : $OUT"
echo "python      : $PY"
echo "rec_seconds : $REC_SECONDS"
echo

echo "==================== 1. backup orchestrator.py ===================="
cp -av voice_assistant/orchestrator.py "$OUT/orchestrator.py.before"
cp -av voice_assistant/orchestrator.py "voice_assistant/orchestrator.py.exp07_7_before_$(date +%Y%m%d_%H%M%S).bak"
echo

echo "==================== 2. patch run_once_from_text ===================="
python3 - <<'PY'
from pathlib import Path

p = Path("voice_assistant/orchestrator.py")
s = p.read_text(encoding="utf-8")

old = '''        if speak and play:
            print("将使用流式 TTS：Qwen 每生成一句就直接写入喇叭 PCM 播放。", flush=True)
            player = StreamingTtsPlayer(self.config)
            try:
                ack_text = str(self.config["models"]["tts"].get("ack_text", "")).strip()
                if ack_text:
                    player.enqueue(ack_text)
                return self.ask_qwen(
                    text,
                    image_path=image_path,
                    force_photo=force_photo,
                    on_sentence=player.enqueue,
                )
            finally:
                player.close()
        return self.ask_qwen(text, image_path=image_path, force_photo=force_photo)
'''

new = '''        answer = self.ask_qwen(text, image_path=image_path, force_photo=force_photo)

        if speak and play:
            print("将使用整段 TTS：先得到完整 Qwen 回答，再合成并播放。", flush=True)
            player = StreamingTtsPlayer(self.config)
            try:
                player.enqueue(answer)
            finally:
                player.close()

        return answer
'''

if old not in s:
    print("[FAIL] target block not found")
    print("----- current run_once_from_text area -----")
    lines = s.splitlines()
    for i, line in enumerate(lines, 1):
        if "def run_once_from_text" in line:
            for j in range(max(1, i-5), min(len(lines), i+45)+1):
                print(f"{j:04d}: {lines[j-1]}")
            break
    raise SystemExit(1)

s = s.replace(old, new, 1)
p.write_text(s, encoding="utf-8")
print("[OK] patched voice_assistant/orchestrator.py")
PY

patch_rc=$?
echo "patch_return_code: $patch_rc"
echo

echo "----- patched relevant code -----"
nl -ba voice_assistant/orchestrator.py | sed -n '70,115p'
echo

if [ "$patch_rc" -ne 0 ]; then
    echo "[RESULT] Experiment 07.7 PATCH_FAILED"
    exit 1
fi

echo "==================== 3. py compile ===================="
"$PY" -m py_compile \
  voice_assistant/orchestrator.py \
  voice_assistant/streaming_tts.py \
  voice_assistant/audio_io.py \
  voice_assistant/qwen_runner.py \
  voice_assistant/cli.py \
  > "$OUT/py_compile.log" 2>&1

compile_rc=$?
cat "$OUT/py_compile.log"
echo "compile_return_code: $compile_rc"
echo

if [ "$compile_rc" -ne 0 ]; then
    echo "[FAIL] compile failed, restoring original orchestrator.py"
    cp -av "$OUT/orchestrator.py.before" voice_assistant/orchestrator.py
    echo "[RESULT] Experiment 07.7 COMPILE_FAILED_RESTORED"
    exit 1
fi

echo "==================== 4. run official once after patch ===================="
echo "[INFO] 请在倒计时结束后说一句短问题，建议说：你是谁"
echo

for i in 3 2 1; do
    echo "record starts in $i ..."
    sleep 1
done

echo "[RUN] voice_assistant.py once --seconds $REC_SECONDS"

timeout 300s "$PY" voice_assistant.py once \
  --seconds "$REC_SECONDS" \
  > "$OUT/once_stdout.txt" \
  2> "$OUT/once_stderr.log"

once_rc=$?

echo
echo "once_return_code: $once_rc"
echo

echo "==================== 5. once stdout ===================="
cat "$OUT/once_stdout.txt" || true
echo

echo "==================== 6. once stderr ===================="
cat "$OUT/once_stderr.log" || true
echo

echo "==================== 7. parse output ===================="
python3 - "$OUT/once_stdout.txt" "$OUT/recognized_text.txt" "$OUT/qwen_answer.txt" <<'PY'
import sys
from pathlib import Path

src = Path(sys.argv[1])
rec_out = Path(sys.argv[2])
ans_out = Path(sys.argv[3])

text = src.read_text(encoding="utf-8", errors="ignore") if src.exists() else ""
lines = text.splitlines()

recognized = ""
answer_lines = []

for i, line in enumerate(lines):
    s = line.strip()
    if s.startswith("识别文本："):
        recognized = s.split("：", 1)[1].strip()
        continue
    if s.startswith("正在调用 Qwen"):
        answer_lines = []
        continue
    if s.startswith("将使用整段 TTS"):
        break
    if answer_lines is not None and recognized:
        # 跳过提示行，保留 Qwen 回答行
        if not s.startswith("将使用") and not s.startswith("正在调用"):
            answer_lines.append(line)

answer = "\n".join(answer_lines).strip()

rec_out.write_text(recognized, encoding="utf-8")
ans_out.write_text(answer, encoding="utf-8")
PY

echo "recognized_text: $(cat "$OUT/recognized_text.txt" 2>/dev/null || true)"
echo "qwen_answer_chars: $(python3 - <<PY
from pathlib import Path
p = Path("$OUT/qwen_answer.txt")
s = p.read_text(encoding="utf-8", errors="ignore") if p.exists() else ""
print(len(s))
PY
)"
echo

echo "========== qwen clean answer =========="
cat "$OUT/qwen_answer.txt" 2>/dev/null || true
echo

echo "==================== 8. underrun / abnormal check ===================="
underrun_count="$(grep -ci "underrun" "$OUT/once_stderr.log" 2>/dev/null || true)"

grep -nEi "error|failed|not found|segmentation|killed|cannot|invalid|timeout|oom|exception|Traceback|ModuleNotFound|Broken pipe|Unable to install hw params" \
  "$OUT/once_stdout.txt" \
  "$OUT/once_stderr.log" \
  > "$OUT/abnormal_without_underrun.txt" 2>/dev/null || true

echo "underrun_count: $underrun_count"
echo

echo "----- abnormal_without_underrun -----"
cat "$OUT/abnormal_without_underrun.txt" || true
echo

echo "==================== 9. summary ===================="
echo "patch_return_code  : $patch_rc"
echo "compile_return_code: $compile_rc"
echo "once_return_code   : $once_rc"
echo "underrun_count     : $underrun_count"
echo "recognized_text    : $(cat "$OUT/recognized_text.txt" 2>/dev/null || true)"
echo "out_dir            : $OUT"

if [ "$patch_rc" -eq 0 ] && [ "$compile_rc" -eq 0 ] && [ "$once_rc" -eq 0 ] && [ "$underrun_count" -eq 0 ]; then
    echo "[RESULT] Experiment 07.7 PASSED_NO_UNDERRUN"
    echo "[NOTE] Please confirm by listening whether the assistant answer was spoken."
elif [ "$patch_rc" -eq 0 ] && [ "$compile_rc" -eq 0 ] && [ "$once_rc" -eq 0 ]; then
    echo "[RESULT] Experiment 07.7 PASSED_WITH_UNDERRUN"
    echo "[NOTE] Once still works, but underrun remains."
else
    echo "[RESULT] Experiment 07.7 FAILED_OR_INCOMPLETE"
fi

echo
echo "log saved to: $LOG"
