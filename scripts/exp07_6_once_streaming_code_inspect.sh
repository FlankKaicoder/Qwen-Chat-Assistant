#!/usr/bin/env bash

set -u

PROJECT_DIR="/home/cat/ai/qwen3vl2b"
cd "$PROJECT_DIR" || exit 1

OUT="${1:-output/exp07_6_once_streaming_code_inspect_$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUT"

LOG="$OUT/run.log"
exec > >(tee "$LOG") 2>&1

echo "============================================================"
echo " Experiment 07.6: inspect once streaming TTS code"
echo "============================================================"
echo "time        : $(date '+%Y-%m-%d %H:%M:%S')"
echo "project_dir : $PROJECT_DIR"
echo "out_dir     : $OUT"
echo

echo "==================== 1. source files ===================="
for f in \
  voice_assistant/cli.py \
  voice_assistant/orchestrator.py \
  voice_assistant/streaming_tts.py \
  voice_assistant/audio_io.py \
  voice_assistant/tts.py \
  voice_assistant/qwen_runner.py
do
    if [ -f "$f" ]; then
        echo "[OK] $f"
        cp -av "$f" "$OUT/$(basename "$f").copy" >/dev/null 2>&1 || true
    else
        echo "[MISS] $f"
    fi
done
echo

echo "==================== 2. grep key symbols ===================="
grep -RniE \
  "once|StreamingTtsPlayer|streaming|流式|tts-stream|no_speak|no_play|speak|play|PcmSpeakerStream|write_samples|underrun|aplay|arecord|QwenRunner|ask_stream|generate|sentence|句" \
  voice_assistant \
  > "$OUT/grep_key_symbols.txt" 2>&1 || true

cat "$OUT/grep_key_symbols.txt"
echo

echo "==================== 3. cli.py ===================="
nl -ba voice_assistant/cli.py | sed -n '1,260p' | tee "$OUT/cli_numbered.txt"
echo

echo "==================== 4. orchestrator.py ===================="
nl -ba voice_assistant/orchestrator.py | sed -n '1,320p' | tee "$OUT/orchestrator_numbered.txt"
echo

echo "==================== 5. streaming_tts.py ===================="
nl -ba voice_assistant/streaming_tts.py | sed -n '1,320p' | tee "$OUT/streaming_tts_numbered.txt"
echo

echo "==================== 6. audio_io.py ===================="
nl -ba voice_assistant/audio_io.py | sed -n '1,360p' | tee "$OUT/audio_io_numbered.txt"
echo

echo "==================== 7. qwen_runner.py ===================="
nl -ba voice_assistant/qwen_runner.py | sed -n '1,360p' | tee "$OUT/qwen_runner_numbered.txt"
echo

echo "==================== 8. config tts/audio/qwen ===================="
echo "----- audio -----"
sed -n '/audio:/,/models:/p' config/default.yaml | tee "$OUT/config_audio.txt"
echo

echo "----- models/qwen part -----"
sed -n '/models:/,$p' config/default.yaml | head -120 | tee "$OUT/config_models_qwen.txt"
echo

echo "==================== 9. py compile ===================="
python3 -m py_compile \
  voice_assistant/cli.py \
  voice_assistant/orchestrator.py \
  voice_assistant/streaming_tts.py \
  voice_assistant/audio_io.py \
  voice_assistant/tts.py \
  voice_assistant/qwen_runner.py \
  > "$OUT/py_compile.log" 2>&1

compile_rc=$?
cat "$OUT/py_compile.log"
echo "compile_return_code: $compile_rc"
echo

echo "==================== 10. summary ===================="
echo "compile_return_code: $compile_rc"
echo "out_dir            : $OUT"

if [ "$compile_rc" -eq 0 ]; then
    echo "[RESULT] Experiment 07.6 CODE_INSPECT_COMPLETED"
else
    echo "[RESULT] Experiment 07.6 CODE_INSPECT_WITH_COMPILE_ERROR"
fi

echo
echo "log saved to: $LOG"
