#!/usr/bin/env bash
set -u

OUT="${1:-output/exp06_0_tts_precheck_$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUT"
LOG="$OUT/run.log"

exec > >(tee "$LOG") 2>&1

echo "============================================================"
echo " Experiment 06.0: TTS asset / dependency / entry precheck"
echo "============================================================"
echo "time    : $(date '+%Y-%m-%d %H:%M:%S')"
echo "workdir : $(pwd)"
echo "out_dir : $OUT"
echo

echo "==================== 1. basic repo info ===================="
pwd
git log -1 --oneline 2>/dev/null || true
git status --short 2>/dev/null || true
echo

echo "==================== 2. command availability ===================="
for cmd in python3 ffmpeg ffprobe aplay arecord amixer file soxi grep find sed awk; do
    printf "%-10s : " "$cmd"
    if command -v "$cmd" >/dev/null 2>&1; then
        command -v "$cmd"
    else
        echo "MISSING"
    fi
done
echo

echo "==================== 3. audio config ===================="
if [ -f config/default.yaml ]; then
    sed -n '/audio:/,/models:/p' config/default.yaml
else
    echo "[MISS] config/default.yaml"
fi
echo

echo "==================== 4. tts related config search ===================="
grep -nEi "tts|vocos|matcha|speaker|playback|sample|onnx|model" config/default.yaml 2>/dev/null || true
echo

echo "==================== 5. required TTS assets ===================="

check_path() {
    local p="$1"
    if [ -e "$p" ]; then
        if [ -d "$p" ]; then
            echo "[OK ] DIR  $p"
            find "$p" -maxdepth 2 -type f | sort | head -80 | sed 's/^/      /'
            du -sh "$p" 2>/dev/null || true
        else
            echo "[OK ] FILE $p"
            ls -lh "$p"
            file "$p" 2>/dev/null || true
        fi
    else
        echo "[MISS]      $p"
    fi
}

missing=0

for p in \
    "./models/matcha-icefall-zh-baker" \
    "./models/vocos-22khz-univ.onnx"
do
    check_path "$p"
    [ -e "$p" ] || missing=$((missing + 1))
done

echo
echo "missing_tts_assets: $missing"
echo

echo "==================== 6. python executable ===================="
if [ -x .venv/bin/python ]; then
    PY=.venv/bin/python
else
    PY=python3
fi

echo "PY=$PY"
$PY --version || true
echo

echo "==================== 7. python import check ===================="
$PY - <<'PY' || true
import sys, importlib
print("python:", sys.executable)
print("version:", sys.version)
mods = [
    "yaml",
    "numpy",
    "sherpa_onnx",
    "onnxruntime",
    "soundfile",
    "scipy",
]
for m in mods:
    try:
        mod = importlib.import_module(m)
        ver = getattr(mod, "__version__", "unknown")
        print(f"[OK] import {m}: {ver}")
    except Exception as e:
        print(f"[FAIL] import {m}: {type(e).__name__}: {e}")
PY
echo

echo "==================== 8. project tts source overview ===================="
for f in \
    voice_assistant/tts.py \
    voice_assistant/streaming_tts.py \
    voice_assistant/cli.py \
    voice_assistant/orchestrator.py \
    scripts/test_tts_play.sh
do
    if [ -f "$f" ]; then
        echo
        echo "----- $f -----"
        grep -nEi "tts|vocos|matcha|sherpa|play|aplay|speaker|wav|onnx|class|def |argparse|subparser|add_parser" "$f" | head -160 || true
    else
        echo "[MISS] $f"
    fi
done
echo

echo "==================== 9. cli help ===================="
$PY voice_assistant.py --help 2>&1 | tee "$OUT/voice_assistant_help.txt" || true
echo
$PY voice_assistant.py tts --help 2>&1 | tee "$OUT/voice_assistant_tts_help.txt" || true
echo
$PY voice_assistant.py tts-stream --help 2>&1 | tee "$OUT/voice_assistant_tts_stream_help.txt" || true
echo

echo "==================== 10. playback quick sanity ===================="
TEST_WAV="$OUT/test_tone_44100_stereo.wav"

python3 - <<PY
import wave, math, struct
path = "$TEST_WAV"
sr = 44100
dur = 1.0
freq = 440
amp = 0.2
n = int(sr * dur)
with wave.open(path, "wb") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(sr)
    for i in range(n):
        v = int(amp * 32767 * math.sin(2 * math.pi * freq * i / sr))
        w.writeframesraw(struct.pack("<hh", v, v))
print(path)
PY

file "$TEST_WAV" || true
soxi "$TEST_WAV" 2>/dev/null || true

echo
echo "[INFO] Now play 1s test tone through plughw:2,0"
aplay -D plughw:2,0 "$TEST_WAV" > "$OUT/aplay_test_tone.log" 2>&1
cat "$OUT/aplay_test_tone.log"
echo

echo "==================== 11. summary ===================="
echo "missing_tts_assets: $missing"

if [ "$missing" -eq 0 ]; then
    echo "[RESULT] Experiment 06.0 PRECHECK PASSED: TTS assets appear present."
else
    echo "[RESULT] Experiment 06.0 PRECHECK BLOCKED: TTS assets missing."
fi

echo
echo "log saved to: $LOG"
