#!/usr/bin/env bash

set -u

OUT_DIR="${1:-output/exp04_3_asr_standard_wav_$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUT_DIR"
mkdir -p "$OUT_DIR/wheelhouse"
mkdir -p .python_packages
mkdir -p .venv/bin

MODEL_DIR="models/sherpa-onnx-conformer-zh-stateless2-2023-05-23"
PRE_DIR="$(ls -td output/exp04_1_asr_preflight_* 2>/dev/null | head -1 || true)"

MAIN_LOG="$OUT_DIR/exp04_3_asr_standard_wav_test.log"
exec > >(tee "$MAIN_LOG") 2>&1

section() {
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
}

section "Experiment 04.3: sherpa-onnx runtime and standard WAV test"

echo "time       : $(date '+%Y-%m-%d %H:%M:%S %z')"
echo "workdir    : $(pwd)"
echo "output dir : $OUT_DIR"
echo "model dir  : $MODEL_DIR"
echo "preflight  : ${PRE_DIR:-<none>}"

section "1. Model asset recheck"

required_files=(
    "$MODEL_DIR/tokens.txt"
    "$MODEL_DIR/encoder-epoch-99-avg-1.int8.onnx"
    "$MODEL_DIR/decoder-epoch-99-avg-1.onnx"
    "$MODEL_DIR/joiner-epoch-99-avg-1.int8.onnx"
)

missing=0

for file_path in "${required_files[@]}"; do
    if [ -s "$file_path" ]; then
        echo "[OK  ] $file_path"
        ls -lh "$file_path"
    else
        echo "[MISS] $file_path"
        missing=$((missing + 1))
    fi
done

if [ "$missing" -ne 0 ]; then
    echo "[RESULT] Required ASR model files are incomplete"
    exit 1
fi

echo
echo "----- model README -----"
cat "$MODEL_DIR/README.md" 2>/dev/null || true

echo
echo "----- standard WAV files -----"
find "$MODEL_DIR/test_wavs" -maxdepth 1 -type f -iname '*.wav' \
    -printf '%f %s bytes\n' | sort -V

section "2. Check sherpa_onnx runtime"

runtime_ok=0

if .venv/bin/python -c 'import sherpa_onnx' >/dev/null 2>&1; then
    runtime_ok=1
    echo "[OK] .venv/bin/python can import sherpa_onnx"
elif PYTHONPATH="$(pwd)/.python_packages" \
     python3 -c 'import sherpa_onnx' >/dev/null 2>&1; then
    runtime_ok=1
    echo "[OK] system Python can import sherpa_onnx through .python_packages"
else
    echo "[MISS] sherpa_onnx is not currently importable"
fi

section "3. Install runtime only when missing"

if [ "$runtime_ok" -eq 0 ]; then
    echo "sherpa_onnx 缺失，开始安装到项目私有目录："
    echo "$(pwd)/.python_packages"
    echo

    if [ -n "$PRE_DIR" ]; then
        find "$PRE_DIR/wheel_probe" -maxdepth 1 -type f \
            -name 'sherpa_onnx-1.13.2-*.whl' \
            -exec cp -v {} "$OUT_DIR/wheelhouse/" \; 2>/dev/null || true

        find "$PRE_DIR/wheel_probe" -maxdepth 1 -type f \
            -name 'sherpa_onnx_core-1.13.2-*.whl' \
            -exec cp -v {} "$OUT_DIR/wheelhouse/" \; 2>/dev/null || true
    fi

    if ! compgen -G "$OUT_DIR/wheelhouse/sherpa_onnx-1.13.2-*.whl" \
        >/dev/null; then
        echo "[DOWNLOAD] sherpa_onnx==1.13.2"

        python3 -m pip download \
            --disable-pip-version-check \
            --no-deps \
            --only-binary=:all: \
            --timeout 60 \
            --retries 5 \
            --dest "$OUT_DIR/wheelhouse" \
            "sherpa_onnx==1.13.2"
    fi

    if ! compgen -G "$OUT_DIR/wheelhouse/sherpa_onnx_core-1.13.2-*.whl" \
        >/dev/null; then
        echo "[DOWNLOAD] sherpa-onnx-core==1.13.2"

        python3 -m pip download \
            --disable-pip-version-check \
            --no-deps \
            --only-binary=:all: \
            --timeout 60 \
            --retries 5 \
            --dest "$OUT_DIR/wheelhouse" \
            "sherpa-onnx-core==1.13.2"
    fi

    echo
    echo "----- downloaded wheels -----"
    ls -lh "$OUT_DIR/wheelhouse"
    sha256sum "$OUT_DIR"/wheelhouse/*.whl

    echo
    echo "----- install to .python_packages -----"

    python3 -m pip install \
        --disable-pip-version-check \
        --no-deps \
        --upgrade \
        --target "$(pwd)/.python_packages" \
        "$OUT_DIR"/wheelhouse/sherpa_onnx_core-1.13.2-*.whl \
        "$OUT_DIR"/wheelhouse/sherpa_onnx-1.13.2-*.whl

    runtime_ok=1
else
    echo "[SKIP] Runtime already importable; no duplicate installation"
fi

section "4. Ensure project Python wrapper uses .python_packages"

if [ -f .venv/bin/python ]; then
    cp -a .venv/bin/python "$OUT_DIR/python_wrapper.before"
fi

cat > .venv/bin/python <<'PYWRAPPER'
#!/usr/bin/env bash
set -e

PROJECT_DIR="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"

export PYTHONPATH="$PROJECT_DIR/.python_packages${PYTHONPATH:+:$PYTHONPATH}"

exec /usr/bin/python3 "$@"
PYWRAPPER

chmod +x .venv/bin/python

cat .venv/bin/python

section "5. Runtime import and version verification"

.venv/bin/python - <<'PY'
from __future__ import annotations

import importlib.metadata
import platform
import sys

import sherpa_onnx

print("Python executable :", sys.executable)
print("Python version    :", sys.version.replace("\n", " "))
print("machine           :", platform.machine())
print("module path       :", sherpa_onnx.__file__)
print("module version    :", getattr(sherpa_onnx, "__version__", "unknown"))
print("sherpa-onnx       :", importlib.metadata.version("sherpa-onnx"))
print("sherpa-onnx-core  :", importlib.metadata.version("sherpa-onnx-core"))
print("OfflineRecognizer :", sherpa_onnx.OfflineRecognizer)
print(
    "from_transducer   :",
    hasattr(sherpa_onnx.OfflineRecognizer, "from_transducer"),
)

assert hasattr(sherpa_onnx.OfflineRecognizer, "from_transducer")
print("[OK] sherpa_onnx runtime verification passed")
PY

section "6. Create direct OfflineRecognizer test"

cat > "$OUT_DIR/direct_offline_asr_test.py" <<'PY'
from __future__ import annotations

import time
import wave
from pathlib import Path

import numpy as np
import sherpa_onnx


PROJECT_DIR = Path.cwd()
MODEL_DIR = (
    PROJECT_DIR
    / "models"
    / "sherpa-onnx-conformer-zh-stateless2-2023-05-23"
)


def read_pcm16_wav(path: Path) -> tuple[int, np.ndarray]:
    with wave.open(str(path), "rb") as wav:
        channels = wav.getnchannels()
        sample_rate = wav.getframerate()
        sample_width = wav.getsampwidth()
        frames = wav.getnframes()
        raw = wav.readframes(frames)

    if sample_width != 2:
        raise ValueError(
            f"{path}: expected 16-bit PCM, sample_width={sample_width}"
        )

    samples = np.frombuffer(raw, dtype="<i2")

    if channels > 1:
        samples = samples.reshape(-1, channels)[:, 0]

    samples = samples.astype(np.float32) / 32768.0
    return sample_rate, samples


def main() -> None:
    encoder = MODEL_DIR / "encoder-epoch-99-avg-1.int8.onnx"
    decoder = MODEL_DIR / "decoder-epoch-99-avg-1.onnx"
    joiner = MODEL_DIR / "joiner-epoch-99-avg-1.int8.onnx"
    tokens = MODEL_DIR / "tokens.txt"

    print("========== create recognizer ==========")
    print("encoder:", encoder)
    print("decoder:", decoder)
    print("joiner :", joiner)
    print("tokens :", tokens)

    create_start = time.perf_counter()

    recognizer = sherpa_onnx.OfflineRecognizer.from_transducer(
        encoder=str(encoder),
        decoder=str(decoder),
        joiner=str(joiner),
        tokens=str(tokens),
        num_threads=2,
        provider="cpu",
    )

    create_seconds = time.perf_counter() - create_start
    print(f"recognizer_create_s: {create_seconds:.6f}")
    print()

    wav_paths = sorted(
        (MODEL_DIR / "test_wavs").glob("*.wav"),
        key=lambda path: int(path.stem),
    )

    non_empty = 0
    total_audio_seconds = 0.0
    total_decode_seconds = 0.0

    print("========== recognize standard WAVs ==========")

    for wav_path in wav_paths:
        sample_rate, samples = read_pcm16_wav(wav_path)
        audio_seconds = len(samples) / sample_rate

        stream = recognizer.create_stream()
        stream.accept_waveform(sample_rate, samples)

        start = time.perf_counter()
        recognizer.decode_stream(stream)
        decode_seconds = time.perf_counter() - start

        text = stream.result.text.strip()
        rtf = decode_seconds / audio_seconds if audio_seconds else 0.0

        total_audio_seconds += audio_seconds
        total_decode_seconds += decode_seconds

        if text:
            non_empty += 1

        print()
        print(f"wav            : {wav_path.name}")
        print(f"sample_rate    : {sample_rate}")
        print(f"samples        : {len(samples)}")
        print(f"audio_seconds  : {audio_seconds:.6f}")
        print(f"decode_seconds : {decode_seconds:.6f}")
        print(f"rtf            : {rtf:.6f}")
        print(f"text           : {text}")

    total_rtf = (
        total_decode_seconds / total_audio_seconds
        if total_audio_seconds
        else 0.0
    )

    print()
    print("========== direct recognition summary ==========")
    print(f"wav_count           : {len(wav_paths)}")
    print(f"non_empty_count     : {non_empty}")
    print(f"total_audio_seconds : {total_audio_seconds:.6f}")
    print(f"total_decode_seconds: {total_decode_seconds:.6f}")
    print(f"overall_rtf         : {total_rtf:.6f}")

    if not wav_paths:
        raise RuntimeError("No model test WAV files found")

    if non_empty != len(wav_paths):
        raise RuntimeError(
            f"Some WAV files produced empty text: "
            f"{non_empty}/{len(wav_paths)}"
        )

    print("[RESULT] Direct OfflineRecognizer standard WAV test PASSED")


if __name__ == "__main__":
    main()
PY

.venv/bin/python \
    "$OUT_DIR/direct_offline_asr_test.py" \
    2>&1 | tee "$OUT_DIR/06_direct_offline_asr.log"

section "7. Project SherpaAsr integration test"

cat > "$OUT_DIR/project_sherpa_asr_test.py" <<'PY'
from __future__ import annotations

import copy
import time
from pathlib import Path

from voice_assistant.asr import SherpaAsr
from voice_assistant.config import load_config


def run_test(name: str, config: dict, wav_paths: list[Path]) -> None:
    print()
    print(f"========== {name} ==========")
    print(
        "asr_input_gain:",
        config["audio"].get("asr_input_gain"),
    )

    start = time.perf_counter()
    asr = SherpaAsr(config)
    create_seconds = time.perf_counter() - start

    print(f"recognizer_create_s: {create_seconds:.6f}")

    non_empty = 0

    for wav_path in wav_paths:
        start = time.perf_counter()
        text = asr.transcribe_wav(wav_path)
        elapsed = time.perf_counter() - start

        if text:
            non_empty += 1

        print()
        print(f"wav       : {wav_path.name}")
        print(f"elapsed_s : {elapsed:.6f}")
        print(f"text      : {text}")

    print()
    print(f"non_empty: {non_empty}/{len(wav_paths)}")

    if non_empty != len(wav_paths):
        raise RuntimeError(
            f"{name}: empty transcription found "
            f"({non_empty}/{len(wav_paths)})"
        )


def main() -> None:
    config = load_config("config/default.yaml")

    model_dir = Path(
        config["models"]["asr"]["encoder"]
    ).parent

    wav_paths = sorted(
        (model_dir / "test_wavs").glob("*.wav"),
        key=lambda path: int(path.stem),
    )

    if not wav_paths:
        raise RuntimeError("No standard test WAV files found")

    # 第一轮使用当前项目配置，验证真实项目行为。
    run_test("project config", config, wav_paths)

    # 第二轮把增益设为 1.0，用来判断标准测试音频是否受 5 倍增益影响。
    gain1_config = copy.deepcopy(config)
    gain1_config["audio"]["asr_input_gain"] = 1.0

    run_test("gain=1.0 control", gain1_config, wav_paths)

    print()
    print("[RESULT] Project SherpaAsr integration test PASSED")


if __name__ == "__main__":
    main()
PY

.venv/bin/python \
    "$OUT_DIR/project_sherpa_asr_test.py" \
    2>&1 | tee "$OUT_DIR/07_project_sherpa_asr.log"

section "8. Official CLI stt test"

TEST_WAV="$MODEL_DIR/test_wavs/0.wav"

echo "test WAV: $TEST_WAV"
file "$TEST_WAV"
ffprobe -v error \
    -show_entries stream=codec_name,sample_rate,channels,sample_fmt,duration \
    -show_entries format=format_name,size,duration \
    -of default=noprint_wrappers=1 \
    "$TEST_WAV" || true

set +e

.venv/bin/python voice_assistant.py stt "$TEST_WAV" \
    >"$OUT_DIR/08_cli_stt_stdout.log" \
    2>"$OUT_DIR/08_cli_stt_stderr.log"

CLI_RC=$?

set -e

echo "return_code: $CLI_RC"

echo
echo "----- stdout -----"
cat "$OUT_DIR/08_cli_stt_stdout.log"

echo
echo "----- stderr -----"
cat "$OUT_DIR/08_cli_stt_stderr.log"

if [ "$CLI_RC" -eq 0 ] && [ -s "$OUT_DIR/08_cli_stt_stdout.log" ]; then
    echo "[OK] voice_assistant.py stt returned non-empty output"
else
    echo "[WARN] voice_assistant.py stt did not complete successfully"
    echo "       如果前两层测试已通过，则这属于 CLI 依赖耦合问题，"
    echo "       不能判定 ASR runtime 或模型失败。"
fi

section "9. Final result"

DIRECT_OK=0
PROJECT_OK=0
CLI_OK=0

if grep -q \
    "Direct OfflineRecognizer standard WAV test PASSED" \
    "$OUT_DIR/06_direct_offline_asr.log"; then
    DIRECT_OK=1
fi

if grep -q \
    "Project SherpaAsr integration test PASSED" \
    "$OUT_DIR/07_project_sherpa_asr.log"; then
    PROJECT_OK=1
fi

if [ "$CLI_RC" -eq 0 ] && [ -s "$OUT_DIR/08_cli_stt_stdout.log" ]; then
    CLI_OK=1
fi

echo "direct_offline_recognizer : $DIRECT_OK"
echo "project_sherpa_asr        : $PROJECT_OK"
echo "official_cli_stt          : $CLI_OK"

if [ "$DIRECT_OK" -eq 1 ] && [ "$PROJECT_OK" -eq 1 ]; then
    echo
    echo "[RESULT] Experiment 04.3 ASR core chain PASSED"

    if [ "$CLI_OK" -eq 1 ]; then
        echo "[RESULT] Official voice_assistant.py stt entry also PASSED"
    else
        echo "[NOTE] ASR core passed, but official CLI still needs dependency decoupling"
    fi
else
    echo
    echo "[RESULT] Experiment 04.3 ASR core chain FAILED"
fi

echo
echo "main log: $MAIN_LOG"
echo "out dir : $OUT_DIR"
