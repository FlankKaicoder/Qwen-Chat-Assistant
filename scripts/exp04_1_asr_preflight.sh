#!/usr/bin/env bash

set -u

OUT_DIR="${1:-output/exp04_1_asr_preflight_$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUT_DIR"
mkdir -p "$OUT_DIR/wheel_probe"

MAIN_LOG="$OUT_DIR/exp04_1_asr_preflight.log"

exec > >(tee "$MAIN_LOG") 2>&1

section() {
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
}

section "Experiment 04.1: ASR environment and asset preflight"

echo "time       : $(date '+%Y-%m-%d %H:%M:%S %z')"
echo "workdir    : $(pwd)"
echo "output dir : $OUT_DIR"
echo
echo "本阶段只检查环境和资产，不安装 Python 包，不修改项目源码。"

section "1. System and CPU architecture"

{
    echo "----- uname -----"
    uname -a || true
    echo

    echo "----- machine architecture -----"
    uname -m || true
    arch 2>/dev/null || true
    getconf LONG_BIT 2>/dev/null || true
    echo

    echo "----- CPU information -----"
    lscpu 2>/dev/null || true
    echo

    echo "----- operating system -----"
    cat /etc/os-release 2>/dev/null || true
    echo

    echo "----- libc -----"
    getconf GNU_LIBC_VERSION 2>/dev/null || true
    ldd --version 2>&1 | head -5 || true
} | tee "$OUT_DIR/01_system_arch.log"

section "2. Python and pseudo-venv relationship"

{
    echo "----- system Python -----"
    command -v python3 || true
    python3 --version || true
    python3 -c '
import platform
import struct
import sys
print("sys.executable :", sys.executable)
print("sys.version    :", sys.version.replace("\n", " "))
print("machine        :", platform.machine())
print("platform       :", platform.platform())
print("pointer_bits   :", struct.calcsize("P") * 8)
'
    echo

    echo "----- system pip -----"
    command -v pip3 || true
    python3 -m pip --version 2>&1 || true
    echo

    echo "----- .venv/bin/python -----"
    if [ -e .venv/bin/python ]; then
        ls -lh .venv/bin/python
        file .venv/bin/python 2>/dev/null || true
        echo
        echo "wrapper content:"
        sed -n '1,40p' .venv/bin/python 2>/dev/null || true
        echo
        .venv/bin/python --version 2>&1 || true
        .venv/bin/python -c '
import sys
print("sys.executable:", sys.executable)
print("sys.prefix    :", sys.prefix)
print("base_prefix   :", sys.base_prefix)
print("real_venv     :", sys.prefix != sys.base_prefix)
' 2>&1 || true
    else
        echo "[MISS] .venv/bin/python"
    fi
} | tee "$OUT_DIR/02_python_environment.log"

section "3. Installed Python package status"

python3 - <<'PY' 2>&1 | tee "$OUT_DIR/03_python_imports.log"
from __future__ import annotations

import importlib
import importlib.metadata
import sys

modules = [
    "yaml",
    "numpy",
    "sherpa_onnx",
    "sherpa_onnx_core",
    "onnxruntime",
]

distributions = [
    "PyYAML",
    "numpy",
    "sherpa-onnx",
    "sherpa-onnx-core",
    "onnxruntime",
]

print("Python:", sys.version.replace("\n", " "))
print()

print("========== module imports ==========")
for name in modules:
    try:
        module = importlib.import_module(name)
        version = getattr(module, "__version__", "unknown")
        path = getattr(module, "__file__", "built-in")
        print(f"[OK  ] {name:<20} version={version} path={path}")
    except Exception as exc:
        print(f"[FAIL] {name:<20} {type(exc).__name__}: {exc}")

print()
print("========== distribution metadata ==========")
for name in distributions:
    try:
        version = importlib.metadata.version(name)
        print(f"[OK  ] {name:<20} {version}")
    except importlib.metadata.PackageNotFoundError:
        print(f"[MISS] {name}")
    except Exception as exc:
        print(f"[FAIL] {name:<20} {type(exc).__name__}: {exc}")
PY

section "4. requirements.txt"

{
    if [ -f requirements.txt ]; then
        nl -ba requirements.txt
    else
        echo "[MISS] requirements.txt"
    fi

    echo
    echo "----- sherpa-related requirements -----"
    grep -nEi 'sherpa|onnx|numpy|yaml' requirements.txt 2>/dev/null || true
} | tee "$OUT_DIR/04_requirements.log"

section "5. ASR-related project configuration"

{
    echo "----- complete config/default.yaml -----"
    sed -n '1,280p' config/default.yaml 2>/dev/null || true

    echo
    echo "----- parsed important sections -----"

    python3 - <<'PY'
from pathlib import Path
import pprint
import yaml

path = Path("config/default.yaml")
if not path.exists():
    print("[MISS]", path)
    raise SystemExit(0)

config = yaml.safe_load(path.read_text(encoding="utf-8"))

for key in ("paths", "audio", "models", "asr"):
    print()
    print(f"[{key}]")
    if key in config:
        pprint.pp(config[key], sort_dicts=False)
    else:
        print("<section not present>")

print()
print("top-level keys:", list(config.keys()))
PY
} 2>&1 | tee "$OUT_DIR/05_asr_config.log"

section "6. ASR implementation and CLI call path"

{
    echo "----- voice_assistant/asr.py -----"
    if [ -f voice_assistant/asr.py ]; then
        nl -ba voice_assistant/asr.py
    else
        echo "[MISS] voice_assistant/asr.py"
    fi

    echo
    echo "----- stt-related cli.py lines -----"
    grep -nEi -C 6 'stt|transcrib|SherpaAsr|VoiceAssistant' \
        voice_assistant/cli.py 2>/dev/null || true

    echo
    echo "----- scripts/test_stt_record.sh -----"
    if [ -f scripts/test_stt_record.sh ]; then
        nl -ba scripts/test_stt_record.sh
    else
        echo "[MISS] scripts/test_stt_record.sh"
    fi

    echo
    echo "----- orchestrator ASR lines -----"
    grep -nEi -C 5 'SherpaAsr|asr|transcrib' \
        voice_assistant/orchestrator.py 2>/dev/null || true
} | tee "$OUT_DIR/06_asr_source.log"

section "7. ASR model directory inventory"

ASR_DIR="models/sherpa-onnx-conformer-zh-stateless2-2023-05-23"

{
    echo "expected ASR directory:"
    echo "$ASR_DIR"
    echo

    if [ -d "$ASR_DIR" ]; then
        echo "[OK] ASR model directory exists"
        ls -ld "$ASR_DIR"
        echo

        echo "----- directory tree -----"
        find "$ASR_DIR" -maxdepth 3 -printf '%y %p\n' | sort
        echo

        echo "----- model file sizes -----"
        find "$ASR_DIR" -maxdepth 3 -type f \
            -printf '%s bytes  %p\n' | sort -n
        echo

        echo "----- file type inspection -----"
        while IFS= read -r file_path; do
            echo
            echo "---------- $file_path ----------"
            ls -lh "$file_path"
            file "$file_path" 2>/dev/null || true
        done < <(
            find "$ASR_DIR" -maxdepth 3 -type f \
                \( -iname '*.onnx' \
                -o -iname 'tokens*.txt' \
                -o -iname '*.json' \
                -o -iname '*.yaml' \
                -o -iname '*.yml' \) | sort
        )
    else
        echo "[MISS] ASR model directory does not exist"
    fi

    echo
    echo "----- all models directories -----"
    if [ -d models ]; then
        find models -maxdepth 3 -printf '%y %p\n' | sort
    else
        echo "[MISS] models directory"
    fi
} | tee "$OUT_DIR/07_asr_model_inventory.log"

section "8. Direct import of project ASR module"

python3 - <<'PY' 2>&1 | tee "$OUT_DIR/08_project_asr_import.log"
from __future__ import annotations

import traceback

try:
    import voice_assistant.asr as asr_module

    print("[OK] import voice_assistant.asr")
    print("module:", asr_module.__file__)
    print("SherpaAsr:", getattr(asr_module, "SherpaAsr", None))
except Exception as exc:
    print("[FAIL] import voice_assistant.asr")
    print(type(exc).__name__ + ":", exc)
    traceback.print_exc()
PY

section "9. Binary wheel availability probe"

echo "说明：这里仅下载 wheel 到实验目录，不执行安装。"
echo

probe_wheel() {
    local requirement="$1"
    local safe_name
    safe_name="$(echo "$requirement" | tr '=<>!/' '_')"
    local log="$OUT_DIR/09_wheel_${safe_name}.log"

    echo "----- probe: $requirement -----"

    timeout 120 \
        python3 -m pip download \
        --disable-pip-version-check \
        --no-deps \
        --only-binary=:all: \
        --timeout 20 \
        --retries 1 \
        --dest "$OUT_DIR/wheel_probe" \
        "$requirement" \
        >"$log" 2>&1

    local rc=$?
    echo "return_code: $rc"
    cat "$log"

    if [ "$rc" -eq 0 ]; then
        echo "[OK] compatible binary distribution was downloaded"
    else
        echo "[WARN] wheel probe failed"
        echo "       可能原因：无对应平台 wheel、PyPI 网络不可达、pip 版本过旧或版本号不存在。"
    fi
    echo
}

probe_wheel "sherpa-onnx-core==1.13.2"
probe_wheel "sherpa_onnx==1.13.2"

{
    echo "----- downloaded files -----"
    find "$OUT_DIR/wheel_probe" -maxdepth 1 -type f \
        -printf '%f  %s bytes\n' | sort

    echo
    echo "----- file inspection -----"
    find "$OUT_DIR/wheel_probe" -maxdepth 1 -type f -print0 |
    while IFS= read -r -d '' wheel; do
        ls -lh "$wheel"
        file "$wheel" 2>/dev/null || true
    done
} | tee "$OUT_DIR/09_wheel_probe_result.log"

section "10. Python supported wheel tags"

{
    python3 -m pip debug --verbose 2>&1 | sed -n '1,180p' || true
} | tee "$OUT_DIR/10_pip_tags.log"

section "11. Existing WAV input check"

{
    WAV_LIST="$OUT_DIR/11_wav_candidates.txt"
    : > "$WAV_LIST"

    find output /tmp/qwen_voice_assistant \
        -type f -iname '*.wav' \
        -printf '%T@ %p\n' 2>/dev/null \
        >> "$WAV_LIST" || true

    echo "----- WAV candidates -----"
    sort -nr "$WAV_LIST" | head -30

    LATEST_WAV="$(
        sort -nr "$WAV_LIST" |
        head -1 |
        cut -d' ' -f2-
    )"

    echo
    echo "latest_wav: ${LATEST_WAV:-<none>}"

    if [ -n "${LATEST_WAV:-}" ] && [ -f "$LATEST_WAV" ]; then
        echo
        ls -lh "$LATEST_WAV"
        file "$LATEST_WAV" 2>/dev/null || true

        echo
        echo "----- ffprobe -----"
        ffprobe -v error \
            -show_entries stream=codec_name,sample_rate,channels,sample_fmt,duration \
            -show_entries format=format_name,size,duration \
            -of default=noprint_wrappers=1 \
            "$LATEST_WAV" 2>&1 || true

        echo
        echo "----- Python wave -----"
        python3 - "$LATEST_WAV" <<'PY'
import sys
import wave

path = sys.argv[1]
with wave.open(path, "rb") as wav:
    channels = wav.getnchannels()
    sample_rate = wav.getframerate()
    sample_width = wav.getsampwidth()
    frames = wav.getnframes()
    duration = frames / sample_rate if sample_rate else 0

print("path        :", path)
print("channels    :", channels)
print("sample_rate :", sample_rate)
print("sample_width:", sample_width)
print("frames      :", frames)
print("duration_s  :", duration)
PY
    else
        echo "[WARN] no existing WAV found"
    fi
} | tee "$OUT_DIR/11_wav_input.log"

section "12. Preflight summary"

IMPORT_STATUS="FAIL"
if python3 -c 'import sherpa_onnx' >/dev/null 2>&1; then
    IMPORT_STATUS="OK"
fi

MODEL_DIR_STATUS="MISS"
if [ -d "$ASR_DIR" ]; then
    MODEL_DIR_STATUS="OK"
fi

ONNX_COUNT=0
TOKEN_COUNT=0
if [ -d "$ASR_DIR" ]; then
    ONNX_COUNT="$(
        find "$ASR_DIR" -type f -iname '*.onnx' 2>/dev/null |
        wc -l
    )"
    TOKEN_COUNT="$(
        find "$ASR_DIR" -type f \
            \( -iname 'tokens*.txt' -o -iname 'tokens.txt' \) \
            2>/dev/null |
        wc -l
    )"
fi

WHEEL_COUNT="$(
    find "$OUT_DIR/wheel_probe" -maxdepth 1 -type f \
        \( -iname '*.whl' -o -iname '*.tar.gz' \) \
        2>/dev/null |
    wc -l
)"

{
    echo "system_arch                : $(uname -m)"
    echo "python_version             : $(python3 --version 2>&1)"
    echo "sherpa_onnx_import         : $IMPORT_STATUS"
    echo "asr_model_directory        : $MODEL_DIR_STATUS"
    echo "asr_onnx_file_count        : $ONNX_COUNT"
    echo "asr_tokens_file_count      : $TOKEN_COUNT"
    echo "downloaded_distribution_count: $WHEEL_COUNT"
    echo

    if [ "$IMPORT_STATUS" = "OK" ] && \
       [ "$MODEL_DIR_STATUS" = "OK" ] && \
       [ "$ONNX_COUNT" -gt 0 ] && \
       [ "$TOKEN_COUNT" -gt 0 ]; then
        echo "[RESULT] ASR dependency and basic model assets appear ready."
        echo "         Next: instantiate SherpaAsr and recognize a known WAV."
    else
        echo "[RESULT] ASR preflight found missing or unverified components."
        echo "         Do not run full assistant yet."
        echo "         Use the logs to choose the correct installation/model repair."
    fi

    echo
    echo "Important logs:"
    echo "  $OUT_DIR/02_python_environment.log"
    echo "  $OUT_DIR/05_asr_config.log"
    echo "  $OUT_DIR/06_asr_source.log"
    echo "  $OUT_DIR/07_asr_model_inventory.log"
    echo "  $OUT_DIR/09_wheel_probe_result.log"
    echo "  $OUT_DIR/11_wav_input.log"
} | tee "$OUT_DIR/12_summary.log"

echo
echo "main log : $MAIN_LOG"
echo "out dir  : $OUT_DIR"
