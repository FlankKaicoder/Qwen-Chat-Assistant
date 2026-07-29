#!/usr/bin/env bash
set -u

SRC_DIR="${1:-}"
OUT_DIR="${2:-output/exp09_1d_kws_fast_sweep_existing_wav_manual}"

if [ -z "$SRC_DIR" ]; then
  echo "Usage: $0 <src_exp09_1c_dir> <out_dir>"
  exit 2
fi

mkdir -p "$OUT_DIR"

PY=".venv/bin/python"
if [ ! -x "$PY" ]; then
  PY="$(command -v python3)"
fi

export PYTHONPATH="$(pwd)/.python_packages:$(pwd):${PYTHONPATH:-}"

LOG="$OUT_DIR/run.log"
exec > >(tee "$LOG") 2>&1

echo "============================================================"
echo " Experiment 09.1d: fast KWS sweep using existing WAV"
echo "============================================================"
echo "time    : $(date '+%Y-%m-%d %H:%M:%S')"
echo "workdir : $(pwd)"
echo "src_dir : $SRC_DIR"
echo "out_dir : $OUT_DIR"
echo "python  : $PY"
echo

POS="$SRC_DIR/positive_lubancat.raw_stereo.wav"
NEG="$SRC_DIR/negative_hello.raw_stereo.wav"

echo "==================== 1. input wav check ===================="
ls -lh "$POS" "$NEG" || exit 1
file "$POS" "$NEG" || true
echo

cp -av "$POS" "$OUT_DIR/positive_lubancat.raw_stereo.wav"
cp -av "$NEG" "$OUT_DIR/negative_hello.raw_stereo.wav"

echo "==================== 2. volume check ===================="
for name in positive_lubancat negative_hello; do
  WAV="$OUT_DIR/${name}.raw_stereo.wav"
  ffmpeg -hide_banner -i "$WAV" -af volumedetect -f null - > "$OUT_DIR/${name}_volumedetect.log" 2>&1 || true
  echo "----- $name -----"
  grep -E "mean_volume|max_volume" "$OUT_DIR/${name}_volumedetect.log" || true
done
echo

echo "==================== 3. generate fast sweep python ===================="

cat > "$OUT_DIR/kws_fast_sweep.py" <<'PY'
from __future__ import annotations

from pathlib import Path
import time

import sherpa_onnx

from voice_assistant.config import load_config
from voice_assistant.audio_utils import read_wav_channel, silence_stderr

out_dir = Path(__file__).resolve().parent

cfg = load_config("config/default.yaml")
audio = cfg["audio"]
kws = cfg["models"]["kws"]

sample_rate = int(audio.get("sample_rate", 16000))

positive_wav = out_dir / "positive_lubancat.raw_stereo.wav"
negative_wav = out_dir / "negative_hello.raw_stereo.wav"

# 小范围先扫，避免板端长时间卡住
channels = ["left", "right"]
gains = [1.0, 2.0, 4.0, 8.0]
thresholds = [0.005, 0.01, 0.03, 0.05, 0.07, 0.1]
score = float(kws.get("keywords_score", 4.0))

def create_spotter(threshold: float):
    with silence_stderr():
        return sherpa_onnx.KeywordSpotter(
            tokens=kws["tokens"],
            encoder=kws["encoder"],
            decoder=kws["decoder"],
            joiner=kws["joiner"],
            keywords_file=kws["keywords_file"],
            num_threads=int(kws.get("num_threads", 2)),
            sample_rate=sample_rate,
            keywords_score=score,
            keywords_threshold=threshold,
            provider="cpu",
        )

def detect_with_existing_spotter(spotter, wav: Path, channel: str, gain: float) -> str:
    sr, samples = read_wav_channel(wav, channel, gain)
    stream = spotter.create_stream()
    chunk = int(sr * 0.1)

    for start in range(0, len(samples), chunk):
        stream.accept_waveform(sr, samples[start:start + chunk])
        while spotter.is_ready(stream):
            with silence_stderr():
                spotter.decode_stream(stream)
                keyword = spotter.get_result(stream)
            if keyword:
                return keyword

    stream.input_finished()
    while spotter.is_ready(stream):
        with silence_stderr():
            spotter.decode_stream(stream)
            keyword = spotter.get_result(stream)
        if keyword:
            return keyword

    return ""

print("case,channel,gain,score,threshold,keyword", flush=True)

best = []
idx = 0
total = len(channels) * len(gains) * len(thresholds)

for channel in channels:
    for gain in gains:
        for th in thresholds:
            idx += 1
            t0 = time.time()
            print(f"[PROGRESS] {idx}/{total} channel={channel} gain={gain} threshold={th}", flush=True)

            try:
                spotter = create_spotter(th)
                pos = detect_with_existing_spotter(spotter, positive_wav, channel, gain)
                neg = detect_with_existing_spotter(spotter, negative_wav, channel, gain)
            except Exception as e:
                pos = f"ERROR:{type(e).__name__}:{e}"
                neg = f"ERROR:{type(e).__name__}:{e}"

            print(f"positive,{channel},{gain},{score},{th},{pos}", flush=True)
            print(f"negative,{channel},{gain},{score},{th},{neg}", flush=True)
            print(f"[COST] {time.time() - t0:.2f}s", flush=True)

            if pos and not pos.startswith("ERROR") and not neg:
                best.append((channel, gain, score, th, pos))

print()
print("========== best_candidates ==========", flush=True)
if not best:
    print("NONE", flush=True)
else:
    for channel, gain, score, th, keyword in best:
        print(f"channel={channel} gain={gain} score={score} threshold={th} keyword={keyword}", flush=True)
PY

echo "[RUN] timeout 240s $PY $OUT_DIR/kws_fast_sweep.py"
timeout 240s "$PY" "$OUT_DIR/kws_fast_sweep.py" > "$OUT_DIR/kws_fast_sweep_result.txt" 2> "$OUT_DIR/kws_fast_sweep_stderr.txt"
SWEEP_RC=$?

echo "sweep_return_code: $SWEEP_RC"
echo

echo "==================== 4. sweep result tail ===================="
tail -120 "$OUT_DIR/kws_fast_sweep_result.txt" || true
echo

echo "==================== 5. sweep stderr ===================="
cat "$OUT_DIR/kws_fast_sweep_stderr.txt"
echo

echo "==================== 6. best candidates ===================="
sed -n '/best_candidates/,$p' "$OUT_DIR/kws_fast_sweep_result.txt" || true
echo

echo "==================== 7. abnormal scan ===================="
grep -nEi "Traceback|ModuleNotFound|ImportError|No such file|not found|cannot|killed|oom|segmentation|exception" \
  "$OUT_DIR"/*.txt "$OUT_DIR"/*.log > "$OUT_DIR/abnormal.txt" 2>/dev/null || true
cat "$OUT_DIR/abnormal.txt"
echo

echo "==================== 8. summary ===================="
POS_MEAN=$(grep -E "mean_volume" "$OUT_DIR/positive_lubancat_volumedetect.log" 2>/dev/null | tail -1 | sed 's/.*mean_volume: //')
POS_MAX=$(grep -E "max_volume" "$OUT_DIR/positive_lubancat_volumedetect.log" 2>/dev/null | tail -1 | sed 's/.*max_volume: //')
NEG_MEAN=$(grep -E "mean_volume" "$OUT_DIR/negative_hello_volumedetect.log" 2>/dev/null | tail -1 | sed 's/.*mean_volume: //')
NEG_MAX=$(grep -E "max_volume" "$OUT_DIR/negative_hello_volumedetect.log" 2>/dev/null | tail -1 | sed 's/.*max_volume: //')
BEST_COUNT=$(sed -n '/best_candidates/,$p' "$OUT_DIR/kws_fast_sweep_result.txt" 2>/dev/null | grep -c "channel=" || true)

echo "src_dir          : $SRC_DIR"
echo "out_dir          : $OUT_DIR"
echo "sweep_return_code: $SWEEP_RC"
echo "positive_mean    : ${POS_MEAN:-}"
echo "positive_max     : ${POS_MAX:-}"
echo "negative_mean    : ${NEG_MEAN:-}"
echo "negative_max     : ${NEG_MAX:-}"
echo "best_count       : $BEST_COUNT"

if [ "$SWEEP_RC" = "0" ] && [ "$BEST_COUNT" -gt 0 ]; then
  echo "[RESULT] Experiment 09.1d PASSED_FOUND_KWS_SETTING"
elif [ "$SWEEP_RC" = "124" ]; then
  echo "[RESULT] Experiment 09.1d TIMEOUT_NEEDS_SMALLER_SWEEP"
elif [ "$SWEEP_RC" = "0" ]; then
  echo "[RESULT] Experiment 09.1d NO_KWS_DETECTION_SETTING_FOUND"
else
  echo "[RESULT] Experiment 09.1d FAILED"
fi

echo
echo "log saved to: $LOG"
