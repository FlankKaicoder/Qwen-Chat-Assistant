#!/usr/bin/env bash
set -u

OUT="${1:-output/exp06_4_tts_stream_official_$(date +%Y%m%d_%H%M%S)}"
TEXT="${2:-你好，我是三五八八端侧语音助手。现在正在验证流式中文语音合成和播放。}"

mkdir -p "$OUT"
LOG="$OUT/run.log"

exec > >(tee "$LOG") 2>&1

echo "============================================================"
echo " Experiment 06.4: official tts-stream entry verification"
echo "============================================================"
echo "time    : $(date '+%Y-%m-%d %H:%M:%S')"
echo "workdir : $(pwd)"
echo "out_dir : $OUT"
echo

if [ -x .venv/bin/python ]; then
    PY=.venv/bin/python
else
    PY=python3
fi

echo "PY=$PY"
$PY --version || true
echo

echo "==================== 1. text ===================="
echo "$TEXT"
echo

echo "==================== 2. audio / tts config ===================="
sed -n '/audio:/,/models:/p' config/default.yaml || true
echo
sed -n '/tts:/,/kws:/p' config/default.yaml || true
echo

echo "==================== 3. relevant audio_io source ===================="
if [ -f voice_assistant/audio_io.py ]; then
    grep -nEi "class PcmSpeakerStream|def __init__|def write_samples|def close|aplay|ffmpeg|speaker_device|playback_sample_rate|playback_channels|stereo|mono|resample|Popen|stdin" \
      voice_assistant/audio_io.py | head -200 || true
else
    echo "[MISS] voice_assistant/audio_io.py"
fi
echo

echo "==================== 4. tts-stream help ===================="
$PY voice_assistant.py tts-stream --help 2>&1 | tee "$OUT/tts_stream_help.txt" || true
echo

echo "==================== 5. run official tts-stream ===================="
START=$(date +%s)

# 用 timeout 防止 aplay 管道或线程异常时一直不退出。
timeout 90s $PY voice_assistant.py tts-stream "$TEXT" \
  > "$OUT/tts_stream_stdout.log" \
  2> "$OUT/tts_stream_stderr.log"

RC=$?
END=$(date +%s)
ELAPSED=$((END - START))

echo "return_code: $RC"
echo "elapsed_seconds: $ELAPSED"
echo

echo "----- stdout -----"
cat "$OUT/tts_stream_stdout.log"
echo

echo "----- stderr -----"
cat "$OUT/tts_stream_stderr.log"
echo

echo "==================== 6. abnormal check ===================="
grep -nEi "error|failed|not found|cannot|invalid|exception|traceback|segmentation|killed|oom|No such file|underrun|xrun|Broken pipe|timeout|Unable to install hw params" \
  "$LOG" "$OUT/tts_stream_stdout.log" "$OUT/tts_stream_stderr.log" 2>/dev/null || true
echo

echo "==================== 7. summary ===================="
echo "return_code: $RC"
echo "elapsed_seconds: $ELAPSED"

if [ "$RC" -eq 0 ]; then
    echo "[RESULT] Experiment 06.4 PASSED_BY_COMMAND"
    echo "[NOTE] Please confirm by listening whether the official tts-stream voice was audible."
elif [ "$RC" -eq 124 ]; then
    echo "[RESULT] Experiment 06.4 FAILED_TIMEOUT"
else
    echo "[RESULT] Experiment 06.4 FAILED"
fi

echo
echo "log saved to: $LOG"
