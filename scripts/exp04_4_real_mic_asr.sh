#!/usr/bin/env bash

set -euo pipefail

OUT_DIR="$1"
mkdir -p "$OUT_DIR"

LOG="$OUT_DIR/exp04_4_real_mic_asr.log"
exec > >(tee "$LOG") 2>&1

echo "======================================="
echo " Experiment 04.4 Real Mic ASR Test"
echo "======================================="
echo "out dir: $OUT_DIR"
echo

TARGET_TEXT="你好，我是令凯。我正在使用RK3588语音助手进行测试。今天的天气很好。"

echo "请朗读："
echo
echo "$TARGET_TEXT"
echo
echo "5秒后开始录音..."
sleep 5

REC_WAV="$OUT_DIR/mic_test.wav"

echo
echo "========== record =========="

.venv/bin/python voice_assistant.py record \
  --seconds 8 \
  --out "$REC_WAV"

echo
echo "========== wav info =========="

ls -lh "$REC_WAV"
file "$REC_WAV"

ffprobe -v error \
  -show_entries stream=codec_name,sample_rate,channels,sample_fmt,duration \
  -show_entries format=size,duration \
  -of default=noprint_wrappers=1 \
  "$REC_WAV"

echo
echo "========== volume detect =========="

ffmpeg -hide_banner \
  -i "$REC_WAV" \
  -af volumedetect \
  -f null - 2>&1 \
  | tee "$OUT_DIR/volume_detect.log"

grep -E "mean_volume|max_volume" "$OUT_DIR/volume_detect.log" || true

echo
echo "========== audio stats =========="

.venv/bin/python - <<PY
from pathlib import Path
import wave
import numpy as np

wav_path = Path("$REC_WAV")

with wave.open(str(wav_path), "rb") as f:
    channels = f.getnchannels()
    sample_rate = f.getframerate()
    sample_width = f.getsampwidth()
    frames = f.getnframes()
    raw = f.readframes(frames)

audio = np.frombuffer(raw, dtype=np.int16)

peak = int(np.max(np.abs(audio))) if audio.size else 0
rms = float(np.sqrt(np.mean(audio.astype(np.float64) ** 2))) if audio.size else 0.0

peak_ratio = peak / 32768.0 if peak else 0.0
rms_ratio = rms / 32768.0 if rms else 0.0

print("channels    :", channels)
print("sample_rate :", sample_rate)
print("sample_width:", sample_width)
print("frames      :", frames)
print("duration_s  :", frames / sample_rate if sample_rate else 0)
print("samples     :", len(audio))
print("peak        :", peak)
print("rms         :", rms)
print("peak_ratio  :", peak_ratio)
print("rms_ratio   :", rms_ratio)

if peak >= 32760:
    print("[WARN] possible clipping: peak is near int16 limit")
elif peak < 1000:
    print("[WARN] signal may be too weak")
else:
    print("[OK] signal peak is in a usable range")
PY

echo
echo "========== ASR recognize =========="

.venv/bin/python voice_assistant.py stt "$REC_WAV" \
  > "$OUT_DIR/asr_result.txt" \
  2> "$OUT_DIR/asr_stderr.log"

ASR_RC=$?

echo "return_code: $ASR_RC"

echo
echo "----- ASR stdout -----"
cat "$OUT_DIR/asr_result.txt"

echo
echo "----- ASR stderr -----"
cat "$OUT_DIR/asr_stderr.log"

echo
echo "========== target text =========="
echo "$TARGET_TEXT" | tee "$OUT_DIR/target_text.txt"

echo
echo "========== rough comparison =========="

.venv/bin/python - <<PY
from pathlib import Path
import re

target = Path("$OUT_DIR/target_text.txt").read_text(encoding="utf-8").strip()
pred = Path("$OUT_DIR/asr_result.txt").read_text(encoding="utf-8").strip()

def norm(s: str) -> str:
    s = re.sub(r"[，。！？、,.!?\\s]", "", s)
    s = s.upper()
    return s

t = norm(target)
p = norm(pred)

common_chars = sum(1 for ch in p if ch in t)
precision_like = common_chars / len(p) if p else 0.0
recall_like = common_chars / len(t) if t else 0.0

print("target_norm:", t)
print("pred_norm  :", p)
print("target_len :", len(t))
print("pred_len   :", len(p))
print("char_overlap_precision_like:", round(precision_like, 3))
print("char_overlap_recall_like   :", round(recall_like, 3))

if not p:
    print("[RESULT] ASR produced empty text")
elif recall_like >= 0.6:
    print("[RESULT] ASR real mic test likely PASSED")
else:
    print("[RESULT] ASR produced text, but accuracy needs inspection")
PY

echo
echo "========== final files =========="
find "$OUT_DIR" -maxdepth 1 -type f -printf '%f %s bytes\n' | sort

echo
echo "[RESULT] Experiment 04.4 real mic ASR test finished"
echo "log saved to: $LOG"
