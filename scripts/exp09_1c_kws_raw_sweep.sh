#!/usr/bin/env bash
set -u

OUT_DIR="${1:-output/exp09_1c_kws_raw_sweep_manual}"
SECONDS="${2:-4}"

mkdir -p "$OUT_DIR"

PY=".venv/bin/python"
if [ ! -x "$PY" ]; then
  PY="$(command -v python3)"
fi

export PYTHONPATH="$(pwd)/.python_packages:$(pwd):${PYTHONPATH:-}"

LOG="$OUT_DIR/run.log"
exec > >(tee "$LOG") 2>&1

echo "============================================================"
echo " Experiment 09.1c: KWS raw record + channel/gain/threshold sweep"
echo "============================================================"
echo "time    : $(date '+%Y-%m-%d %H:%M:%S')"
echo "workdir : $(pwd)"
echo "out_dir : $OUT_DIR"
echo "python  : $PY"
echo "seconds : $SECONDS"
echo

echo "==================== 1. config quick check ===================="
"$PY" - <<'PY'
from voice_assistant.config import load_config
cfg = load_config("config/default.yaml")
print("audio:", cfg["audio"])
print("kws  :", cfg["models"]["kws"])
PY
echo

record_raw_case() {
  local name="$1"
  local hint="$2"
  local wav="$OUT_DIR/${name}.raw_stereo.wav"
  local log="$OUT_DIR/${name}_arecord.log"
  local vol="$OUT_DIR/${name}_volumedetect.log"

  echo
  echo "==================== record case: $name ===================="
  echo "录音开始后请说：$hint"
  read -p "准备好后按回车开始录音..." _

  "$PY" - <<PY > "$OUT_DIR/${name}_record_cmd.txt"
from voice_assistant.config import load_config
cfg = load_config("config/default.yaml")
audio = cfg["audio"]
print(audio.get("mic_device", "plughw:2,0"))
print(audio.get("sample_rate", 16000))
print(audio.get("channels", 2))
PY

  MIC_DEVICE=$(sed -n '1p' "$OUT_DIR/${name}_record_cmd.txt")
  SAMPLE_RATE=$(sed -n '2p' "$OUT_DIR/${name}_record_cmd.txt")
  CHANNELS=$(sed -n '3p' "$OUT_DIR/${name}_record_cmd.txt")

  echo "mic_device : $MIC_DEVICE"
  echo "sample_rate: $SAMPLE_RATE"
  echo "channels   : $CHANNELS"

  echo "[RUN] arecord -D $MIC_DEVICE -f S16_LE -r $SAMPLE_RATE -c $CHANNELS -d $SECONDS $wav"
  arecord \
    -D "$MIC_DEVICE" \
    -f S16_LE \
    -r "$SAMPLE_RATE" \
    -c "$CHANNELS" \
    -d "$SECONDS" \
    "$wav" \
    > "$log" 2>&1

  RC=$?
  cat "$log"
  echo "arecord_return_code_${name}: $RC"

  if [ -f "$wav" ]; then
    ls -lh "$wav"
    file "$wav" || true
    soxi "$wav" 2>/dev/null || true

    ffmpeg -hide_banner -i "$wav" -af volumedetect -f null - > "$vol" 2>&1 || true
    grep -E "mean_volume|max_volume" "$vol" || true

    ffprobe -hide_banner "$wav" > "$OUT_DIR/${name}_ffprobe.txt" 2>&1 || true
  else
    echo "[MISS] $wav"
  fi
}

record_raw_case "positive_lubancat" "鲁班猫"
record_raw_case "negative_hello" "你好你好"

echo
echo "==================== 2. run sweep detector ===================="

cat > "$OUT_DIR/kws_sweep.py" <<'PY'
from __future__ import annotations

import contextlib
import io
from pathlib import Path

import sherpa_onnx

from voice_assistant.config import load_config
from voice_assistant.audio_utils import read_wav_channel, silence_stderr

out_dir = Path(__file__).resolve().parent
cfg = load_config("config/default.yaml")
audio = cfg["audio"]
base_kws = cfg["models"]["kws"]

sample_rate = int(audio.get("sample_rate", 16000))

positive_wav = out_dir / "positive_lubancat.raw_stereo.wav"
negative_wav = out_dir / "negative_hello.raw_stereo.wav"

channels = ["left", "right", "mix"]
gains = [1.0, 2.0, 4.0, 8.0]
thresholds = [0.005, 0.01, 0.03, 0.05, 0.07, 0.1, 0.2]
scores = [1.5, 2.0, 4.0]

def create_spotter(score: float, threshold: float):
    with silence_stderr():
        return sherpa_onnx.KeywordSpotter(
            tokens=base_kws["tokens"],
            encoder=base_kws["encoder"],
            decoder=base_kws["decoder"],
            joiner=base_kws["joiner"],
            keywords_file=base_kws["keywords_file"],
            num_threads=int(base_kws.get("num_threads", 2)),
            sample_rate=sample_rate,
            keywords_score=score,
            keywords_threshold=threshold,
            provider="cpu",
        )

def detect_one(wav: Path, channel: str, gain: float, score: float, threshold: float) -> str:
    sr, samples = read_wav_channel(wav, channel, gain)
    if sr != sample_rate:
        print(f"[WARN] {wav.name}: sample rate {sr} != {sample_rate}")

    spotter = create_spotter(score, threshold)
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

print("case,channel,gain,score,threshold,keyword")

best = []
for channel in channels:
    for gain in gains:
        for score in scores:
            for th in thresholds:
                try:
                    pos = detect_one(positive_wav, channel, gain, score, th)
                except Exception as e:
                    pos = f"ERROR:{type(e).__name__}:{e}"

                try:
                    neg = detect_one(negative_wav, channel, gain, score, th)
                except Exception as e:
                    neg = f"ERROR:{type(e).__name__}:{e}"

                print(f"positive,{channel},{gain},{score},{th},{pos}")
                print(f"negative,{channel},{gain},{score},{th},{neg}")

                if pos and not pos.startswith("ERROR") and not neg:
                    best.append((channel, gain, score, th, pos))

print()
print("========== best_candidates ==========")
if not best:
    print("NONE")
else:
    for x in best:
        print(f"channel={x[0]} gain={x[1]} score={x[2]} threshold={x[3]} keyword={x[4]}")
PY

"$PY" "$OUT_DIR/kws_sweep.py" > "$OUT_DIR/kws_sweep_result.csv" 2> "$OUT_DIR/kws_sweep_stderr.txt"
SWEEP_RC=$?

echo "sweep_return_code: $SWEEP_RC"
echo

echo "----- sweep stderr -----"
cat "$OUT_DIR/kws_sweep_stderr.txt"
echo

echo "----- best candidates -----"
sed -n '/best_candidates/,$p' "$OUT_DIR/kws_sweep_result.csv"
echo

echo "==================== 3. abnormal scan ===================="
grep -nEi "Traceback|ModuleNotFound|ImportError|No such file|not found|cannot|killed|oom|segmentation|exception" \
  "$OUT_DIR"/*.txt "$OUT_DIR"/*.log "$OUT_DIR"/*.csv > "$OUT_DIR/abnormal.txt" 2>/dev/null || true
cat "$OUT_DIR/abnormal.txt"
echo

echo "==================== 4. summary ===================="
POS_MEAN=$(grep -E "mean_volume" "$OUT_DIR/positive_lubancat_volumedetect.log" 2>/dev/null | tail -1 | sed 's/.*mean_volume: //')
POS_MAX=$(grep -E "max_volume" "$OUT_DIR/positive_lubancat_volumedetect.log" 2>/dev/null | tail -1 | sed 's/.*max_volume: //')
NEG_MEAN=$(grep -E "mean_volume" "$OUT_DIR/negative_hello_volumedetect.log" 2>/dev/null | tail -1 | sed 's/.*mean_volume: //')
NEG_MAX=$(grep -E "max_volume" "$OUT_DIR/negative_hello_volumedetect.log" 2>/dev/null | tail -1 | sed 's/.*max_volume: //')
BEST_COUNT=$(sed -n '/best_candidates/,$p' "$OUT_DIR/kws_sweep_result.csv" | grep -c "channel=" || true)

echo "out_dir         : $OUT_DIR"
echo "sweep_return_code: $SWEEP_RC"
echo "positive_mean   : ${POS_MEAN:-}"
echo "positive_max    : ${POS_MAX:-}"
echo "negative_mean   : ${NEG_MEAN:-}"
echo "negative_max    : ${NEG_MAX:-}"
echo "best_count      : $BEST_COUNT"

if [ "$SWEEP_RC" = "0" ] && [ "$BEST_COUNT" -gt 0 ]; then
  echo "[RESULT] Experiment 09.1c PASSED_FOUND_KWS_SETTING"
elif [ "$SWEEP_RC" = "0" ]; then
  echo "[RESULT] Experiment 09.1c NO_KWS_DETECTION_SETTING_FOUND"
else
  echo "[RESULT] Experiment 09.1c FAILED"
fi

echo
echo "log saved to: $LOG"
