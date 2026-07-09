#!/usr/bin/env bash
set -u

OUT="${1:-output/exp06_3_tts_wav_playback_$(date +%Y%m%d_%H%M%S)}"
WAV="${2:-}"

mkdir -p "$OUT"
LOG="$OUT/run.log"

exec > >(tee "$LOG") 2>&1

echo "============================================================"
echo " Experiment 06.3: TTS WAV playback through ALSA"
echo "============================================================"
echo "time    : $(date '+%Y-%m-%d %H:%M:%S')"
echo "workdir : $(pwd)"
echo "out_dir : $OUT"
echo

if [ -z "$WAV" ]; then
    WAV="$(ls -td output/exp06_2_tts_min_synth_wav_* 2>/dev/null | head -1)/tts_min_synth.wav"
fi

echo "wav: $WAV"
echo

echo "==================== 1. playback device config ===================="
sed -n '/audio:/,/models:/p' config/default.yaml || true
echo

echo "==================== 2. ALSA devices ===================="
echo "----- aplay -l -----"
aplay -l || true
echo

echo "----- /proc/asound/cards -----"
cat /proc/asound/cards 2>/dev/null || true
echo

echo "==================== 3. WAV info before playback ===================="
if [ ! -f "$WAV" ]; then
    echo "[MISS] wav not found: $WAV"
    echo "[RESULT] Experiment 06.3 FAILED"
    exit 1
fi

ls -lh "$WAV"
file "$WAV" || true
soxi "$WAV" 2>/dev/null || true
ffprobe -hide_banner "$WAV" 2>&1 | tee "$OUT/ffprobe_tts_wav.log" || true
echo

echo "----- volume detect -----"
ffmpeg -hide_banner -i "$WAV" -af volumedetect -f null - 2>&1 \
  | tee "$OUT/volumedetect.log" || true
grep -E "mean_volume|max_volume" "$OUT/volumedetect.log" || true
echo

echo "==================== 4. direct aplay playback ===================="
echo "[INFO] Playing TTS WAV through plughw:2,0"
START=$(date +%s)

aplay -D plughw:2,0 "$WAV" > "$OUT/aplay_tts_wav.log" 2>&1
RC=$?

END=$(date +%s)
ELAPSED=$((END - START))

cat "$OUT/aplay_tts_wav.log"
echo
echo "aplay_return_code: $RC"
echo "aplay_elapsed_seconds: $ELAPSED"
echo

echo "==================== 5. optional converted playback file ===================="
# 这里额外生成一个 44.1kHz stereo 版本，用于排除部分声卡对 22.05kHz mono 播放支持不佳的问题。
CONVERTED="$OUT/tts_min_synth_44100_stereo.wav"

ffmpeg -y -hide_banner \
  -i "$WAV" \
  -ar 44100 \
  -ac 2 \
  "$CONVERTED" \
  > "$OUT/ffmpeg_convert_44100_stereo.log" 2>&1

CONVERT_RC=$?

echo "convert_return_code: $CONVERT_RC"

if [ "$CONVERT_RC" -eq 0 ] && [ -s "$CONVERTED" ]; then
    ls -lh "$CONVERTED"
    file "$CONVERTED" || true
    soxi "$CONVERTED" 2>/dev/null || true

    echo
    echo "[INFO] Playing converted 44.1kHz stereo WAV through plughw:2,0"
    aplay -D plughw:2,0 "$CONVERTED" > "$OUT/aplay_tts_wav_44100_stereo.log" 2>&1
    RC2=$?
    cat "$OUT/aplay_tts_wav_44100_stereo.log"
else
    RC2=99
    echo "[WARN] converted file was not generated"
    cat "$OUT/ffmpeg_convert_44100_stereo.log" || true
fi

echo
echo "aplay_converted_return_code: $RC2"
echo

echo "==================== 6. abnormal check ===================="
grep -nEi "error|failed|not found|cannot|invalid|exception|traceback|segmentation|killed|oom|No such file|underrun|xrun" \
  "$LOG" \
  "$OUT/aplay_tts_wav.log" \
  "$OUT/aplay_tts_wav_44100_stereo.log" \
  "$OUT/ffmpeg_convert_44100_stereo.log" \
  "$OUT/ffprobe_tts_wav.log" \
  "$OUT/volumedetect.log" 2>/dev/null || true

echo

echo "==================== 7. summary ===================="
echo "wav: $WAV"
echo "aplay_return_code: $RC"
echo "aplay_elapsed_seconds: $ELAPSED"
echo "aplay_converted_return_code: $RC2"

if [ "$RC" -eq 0 ] || [ "$RC2" -eq 0 ]; then
    echo "[RESULT] Experiment 06.3 PASSED_BY_COMMAND"
    echo "[NOTE] Please confirm by listening whether the synthesized Chinese voice was audible."
else
    echo "[RESULT] Experiment 06.3 FAILED"
fi

echo
echo "log saved to: $LOG"
