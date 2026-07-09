#!/usr/bin/env bash
set -u

OUT="${1:-output/exp06_2_tts_min_synth_wav_$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUT"
LOG="$OUT/run.log"

exec > >(tee "$LOG") 2>&1

echo "============================================================"
echo " Experiment 06.2: Sherpa-ONNX TTS minimal WAV synthesis"
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

echo "==================== 1. TTS assets ===================="
ls -lh models/matcha-icefall-zh-baker/model-steps-3.onnx
ls -lh models/matcha-icefall-zh-baker/lexicon.txt
ls -lh models/matcha-icefall-zh-baker/tokens.txt
ls -lh models/vocos-22khz-univ.onnx
echo

echo "==================== 2. TTS config ===================="
sed -n '/tts:/,/kws:/p' config/default.yaml
echo

echo "==================== 3. python import check ===================="
$PY - <<'PY'
import sys
print("python:", sys.executable)

mods = ["yaml", "numpy", "sherpa_onnx"]
for m in mods:
    try:
        mod = __import__(m)
        print(f"[OK] import {m}: {getattr(mod, '__version__', 'unknown')}")
    except Exception as e:
        print(f"[FAIL] import {m}: {type(e).__name__}: {e}")
        raise
PY
echo

echo "==================== 4. synthesize WAV ===================="

TEXT="${2:-你好，我是三五八八语音助手。现在正在进行端侧中文语音合成实验。}"
WAV="$OUT/tts_min_synth.wav"

cat > "$OUT/tts_min_synth.py" <<'PY'
from pathlib import Path
import sys
import time
import wave

import numpy as np

from voice_assistant.config import load_config
from voice_assistant.tts import SherpaTts

out_wav = Path(sys.argv[1])
text = sys.argv[2]

print("text:", text)
print("out :", out_wav)

cfg = load_config("config/default.yaml")

t0 = time.time()
tts = SherpaTts(cfg)
t1 = time.time()

sample_rate, samples = tts.synthesize_samples(text)
t2 = time.time()

samples = np.asarray(samples)

print("sample_rate:", sample_rate)
print("samples_dtype:", samples.dtype)
print("samples_shape:", samples.shape)
print("samples_min:", float(samples.min()) if samples.size else None)
print("samples_max:", float(samples.max()) if samples.size else None)
print("samples_mean:", float(samples.mean()) if samples.size else None)
print("init_seconds:", round(t1 - t0, 3))
print("synth_seconds:", round(t2 - t1, 3))

if samples.size == 0:
    raise RuntimeError("TTS generated empty samples")

# sherpa-onnx TTS 一般输出 float32 波形，范围约为 [-1, 1]。
# 为了保证 aplay / ffprobe / soxi 都能稳定识别，这里保存成 16-bit PCM WAV。
if samples.dtype.kind == "f":
    pcm = np.clip(samples, -1.0, 1.0)
    pcm = (pcm * 32767.0).astype(np.int16)
else:
    pcm = samples.astype(np.int16)

out_wav.parent.mkdir(parents=True, exist_ok=True)

with wave.open(str(out_wav), "wb") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(int(sample_rate))
    w.writeframes(pcm.tobytes())

duration = len(pcm) / float(sample_rate)
print("duration_seconds:", round(duration, 3))
print("pcm_peak:", int(np.max(np.abs(pcm))) if pcm.size else 0)
print("wav_saved:", out_wav)
PY

START=$(date +%s)

$PY "$OUT/tts_min_synth.py" "$WAV" "$TEXT"
RC=$?

END=$(date +%s)
ELAPSED=$((END - START))

echo
echo "return_code: $RC"
echo "elapsed_seconds: $ELAPSED"
echo

echo "==================== 5. output WAV check ===================="
if [ -f "$WAV" ]; then
    ls -lh "$WAV"
    file "$WAV" || true
    soxi "$WAV" 2>/dev/null || true
    ffprobe -hide_banner "$WAV" 2>&1 | tee "$OUT/ffprobe_tts_wav.log" || true

    echo
    echo "----- volume detect -----"
    ffmpeg -hide_banner -i "$WAV" -af volumedetect -f null - 2>&1 \
      | tee "$OUT/volumedetect.log" || true
    grep -E "mean_volume|max_volume" "$OUT/volumedetect.log" || true
else
    echo "[MISS] $WAV"
fi

echo
echo "==================== 6. abnormal check ===================="
grep -nEi "error|failed|not found|cannot|invalid|exception|traceback|segmentation|killed|oom|ModuleNotFound|No such file" \
  "$LOG" "$OUT/ffprobe_tts_wav.log" "$OUT/volumedetect.log" 2>/dev/null || true

echo
echo "==================== 7. summary ===================="
echo "return_code: $RC"
echo "elapsed_seconds: $ELAPSED"
echo "wav: $WAV"

if [ "$RC" -eq 0 ] && [ -s "$WAV" ]; then
    echo "[RESULT] Experiment 06.2 PASSED"
else
    echo "[RESULT] Experiment 06.2 FAILED"
fi

echo
echo "log saved to: $LOG"
