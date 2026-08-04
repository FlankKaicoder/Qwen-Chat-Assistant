#!/usr/bin/env bash

PROJECT_DIR="/home/cat/ai/qwen3vl2b"
OUT_DIR="${1:-output/exp12_0_baseline_manual}"

cd "$PROJECT_DIR" || {
    echo "[ERROR] project directory not found: $PROJECT_DIR"
    exit 0
}

mkdir -p "$OUT_DIR"

LOG="$OUT_DIR/run.log"
SUMMARY="$OUT_DIR/summary.txt"

export PYTHONPATH="$PWD:$PWD/.python_packages${PYTHONPATH:+:$PYTHONPATH}"

if [ -x "$PWD/.venv/bin/python" ]; then
    PY="$PWD/.venv/bin/python"
else
    PY="/usr/bin/python3"
fi

exec > >(tee "$LOG") 2>&1

echo "============================================================"
echo " Experiment 12.0: Multi-turn Stability Baseline Audit"
echo "============================================================"
echo "time       : $(date '+%Y-%m-%d %H:%M:%S')"
echo "project    : $PROJECT_DIR"
echo "out_dir    : $OUT_DIR"
echo "python     : $PY"
echo

echo "========== 1. git baseline =========="
BRANCH=$(git branch --show-current)
HEAD_FULL=$(git rev-parse HEAD)
HEAD_SHORT=$(git rev-parse --short HEAD)
DIRTY_COUNT=$(git status --porcelain | wc -l)

echo "branch      : $BRANCH"
echo "head        : $HEAD_FULL"
echo "head_short  : $HEAD_SHORT"
echo "dirty_count : $DIRTY_COUNT"
git log -5 --oneline --decorate
echo

echo "========== 2. experiment 11 ancestry =========="
if git merge-base --is-ancestor 19b90b1 HEAD 2>/dev/null; then
    EXP11_PRESENT=1
    echo "exp11_commit_present=1"
else
    EXP11_PRESENT=0
    echo "exp11_commit_present=0"
fi
echo

echo "========== 3. Python environment =========="
"$PY" --version
echo "PYTHONPATH=$PYTHONPATH"
echo

echo "========== 4. source compile =========="
"$PY" -m py_compile \
    voice_assistant.py \
    voice_assistant/cli.py \
    voice_assistant/config.py \
    voice_assistant/intent.py \
    voice_assistant/orchestrator.py \
    voice_assistant/controlled_session.py \
    voice_assistant/qwen_runner.py \
    voice_assistant/camera.py \
    voice_assistant/audio_io.py \
    voice_assistant/asr.py \
    voice_assistant/tts.py \
    voice_assistant/wake.py

COMPILE_RC=$?
echo "compile_return_code=$COMPILE_RC"
echo

echo "========== 5. regression tests =========="
"$PY" -m unittest discover -s tests -v
TEST_RC=$?
echo "test_return_code=$TEST_RC"
echo

echo "========== 6. VoiceAssistant initialization =========="
"$PY" - <<'PY'
from voice_assistant.config import load_config
from voice_assistant.orchestrator import VoiceAssistant

config = load_config("config/default.yaml")
assistant = VoiceAssistant(config)

print("config_load=PASS")
print("assistant_init=PASS")
print("assistant_type=" + type(assistant).__name__)
PY

INIT_RC=$?
echo "init_return_code=$INIT_RC"
echo

echo "========== 7. listen-controlled CLI =========="
"$PY" voice_assistant.py listen-controlled --help
HELP_RC=$?
echo "help_return_code=$HELP_RC"
echo

echo "========== 8. important configuration =========="
"$PY" - <<'PY'
from voice_assistant.config import load_config

cfg = load_config("config/default.yaml")

audio = cfg.get("audio", {})
paths = cfg.get("paths", {})
qwen = cfg.get("qwen", {})
intent = cfg.get("intent", {})

print("mic_device:", audio.get("mic_device"))
print("speaker_device:", audio.get("speaker_device"))
print("sample_rate:", audio.get("sample_rate"))
print("channels:", audio.get("channels"))
print("command_seconds:", audio.get("command_seconds"))
print("capture_script:", paths.get("capture_script"))
print("photo_dir:", paths.get("photo_dir"))
print("max_new_tokens:", qwen.get("max_new_tokens"))
print("intent_keys:", sorted(intent.keys()))
PY

CONFIG_RC=$?
echo "config_return_code=$CONFIG_RC"
echo

echo "========== 9. hardware devices =========="
if [ -e /dev/video11 ]; then
    CAMERA_EXISTS=1
    echo "camera_exists=1"
    ls -lh /dev/video11
else
    CAMERA_EXISTS=0
    echo "camera_exists=0"
fi

echo
echo "----- capture devices -----"
arecord -l 2>&1 | head -40

echo
echo "----- playback devices -----"
aplay -l 2>&1 | head -40
echo

echo "========== 10. storage =========="
df -h "$PROJECT_DIR" /tmp /home/cat/图片 2>/dev/null
echo

echo "========== 11. memory =========="
free -m
echo

MEM_AVAILABLE_KB=$(
    awk '/MemAvailable:/ {print $2}' /proc/meminfo
)
echo "mem_available_kb=$MEM_AVAILABLE_KB"
echo

echo "========== 12. file handles =========="
cat /proc/sys/fs/file-nr
echo

SELF_FD_COUNT=$(
    find "/proc/$$/fd" -maxdepth 1 -type l 2>/dev/null |
    wc -l
)
echo "audit_shell_fd_count=$SELF_FD_COUNT"
echo

echo "========== 13. thermal zones =========="
THERMAL_COUNT=0

for zone in /sys/class/thermal/thermal_zone*; do
    [ -f "$zone/temp" ] || continue

    TYPE=$(cat "$zone/type" 2>/dev/null || echo unknown)
    TEMP=$(cat "$zone/temp" 2>/dev/null || echo 0)

    awk \
        -v name="$TYPE" \
        -v value="$TEMP" \
        'BEGIN {
            printf "%-28s %.1f C\n", name, value / 1000
        }'

    THERMAL_COUNT=$((THERMAL_COUNT + 1))
done

echo "thermal_zone_count=$THERMAL_COUNT"
echo

echo "========== 14. CPU frequency =========="
for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
    FREQ_PATH="$cpu/cpufreq/scaling_cur_freq"
    GOV_PATH="$cpu/cpufreq/scaling_governor"

    [ -f "$FREQ_PATH" ] || continue

    CPU_NAME=$(basename "$cpu")
    FREQ_VALUE=$(cat "$FREQ_PATH")
    GOV_VALUE=$(cat "$GOV_PATH" 2>/dev/null || echo unknown)

    awk \
        -v name="$CPU_NAME" \
        -v value="$FREQ_VALUE" \
        -v gov="$GOV_VALUE" \
        'BEGIN {
            printf "%-8s %6.0f MHz  governor=%s\n",
                   name, value / 1000, gov
        }'
done
echo

echo "========== 15. possible residual processes =========="
RESIDUAL_LOG="$OUT_DIR/residual_processes.txt"

pgrep -af \
    '(^|/)(demo|imgenc|v4l2-ctl|ffmpeg|arecord|aplay)( |$)|voice_assistant.py' \
    > "$RESIDUAL_LOG" 2>/dev/null || true

cat "$RESIDUAL_LOG"

RESIDUAL_COUNT=$(
    grep -v \
        'exp12_0_baseline_audit' \
        "$RESIDUAL_LOG" 2>/dev/null |
    grep -c . || true
)

echo "residual_process_count=$RESIDUAL_COUNT"
echo

echo "========== 16. photo baseline =========="
PHOTO_DIR="/home/cat/图片"

PHOTO_COUNT=$(
    find "$PHOTO_DIR" \
        -maxdepth 1 \
        -type f \
        -name 'voice_*.jpg' \
        2>/dev/null |
    wc -l
)

LATEST_PHOTO=$(
    find "$PHOTO_DIR" \
        -maxdepth 1 \
        -type f \
        -name 'voice_*.jpg' \
        -printf '%T@ %p\n' \
        2>/dev/null |
    sort -nr |
    head -1 |
    cut -d' ' -f2-
)

echo "photo_count=$PHOTO_COUNT"
echo "latest_photo=$LATEST_PHOTO"
echo

echo "========== 17. final summary =========="

RESULT="PASS"

if [ "$BRANCH" != "exp/12-multiturn-stability" ]; then
    RESULT="FAIL"
fi

if [ "$DIRTY_COUNT" -ne 0 ]; then
    RESULT="FAIL"
fi

if [ "$EXP11_PRESENT" -ne 1 ]; then
    RESULT="FAIL"
fi

if [ "$COMPILE_RC" -ne 0 ]; then
    RESULT="FAIL"
fi

if [ "$TEST_RC" -ne 0 ]; then
    RESULT="FAIL"
fi

if [ "$INIT_RC" -ne 0 ]; then
    RESULT="FAIL"
fi

if [ "$HELP_RC" -ne 0 ]; then
    RESULT="FAIL"
fi

if [ "$CONFIG_RC" -ne 0 ]; then
    RESULT="FAIL"
fi

if [ "$CAMERA_EXISTS" -ne 1 ]; then
    RESULT="FAIL"
fi

{
    echo "out_dir               : $OUT_DIR"
    echo "branch                : $BRANCH"
    echo "head                  : $HEAD_SHORT"
    echo "dirty_count           : $DIRTY_COUNT"
    echo "exp11_commit_present  : $EXP11_PRESENT"
    echo "compile_return_code   : $COMPILE_RC"
    echo "test_return_code      : $TEST_RC"
    echo "init_return_code      : $INIT_RC"
    echo "help_return_code      : $HELP_RC"
    echo "config_return_code    : $CONFIG_RC"
    echo "camera_exists         : $CAMERA_EXISTS"
    echo "mem_available_kb      : $MEM_AVAILABLE_KB"
    echo "residual_process_count: $RESIDUAL_COUNT"
    echo "photo_count           : $PHOTO_COUNT"
    echo "result                : $RESULT"
} | tee "$SUMMARY"

echo
if [ "$RESULT" = "PASS" ]; then
    echo "[RESULT] Experiment 12.0 PASSED"
else
    echo "[RESULT] Experiment 12.0 FAILED_OR_NEEDS_CHECK"
fi

echo
echo "log saved to    : $LOG"
echo "summary saved to: $SUMMARY"

# 始终正常结束，避免影响调用它的交互终端。
exit 0
