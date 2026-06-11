#!/usr/bin/env bash

set -u

OUT_DIR="${1:-output/exp00_env_asset_check_manual}"
mkdir -p "$OUT_DIR"

LOG="$OUT_DIR/exp00_env_asset_check.log"

exec > >(tee "$LOG") 2>&1

echo "============================================================"
echo " Experiment 00: RK3588 Qwen Voice Assistant Env/Asset Check "
echo "============================================================"
echo "time    : $(date '+%Y-%m-%d %H:%M:%S')"
echo "workdir : $(pwd)"
echo "out_dir : $OUT_DIR"
echo

echo "==================== 1. system info ===================="
uname -a || true
echo
cat /etc/os-release 2>/dev/null || true
echo

echo "==================== 2. repo info ===================="
git remote -v || true
echo
git branch --show-current || true
git log -1 --oneline || true
echo
ls -lh
echo

echo "==================== 3. command availability ===================="
for cmd in git python3 pip3 ffmpeg v4l2-ctl arecord aplay amixer file ldd sha256sum; do
    printf "%-12s : " "$cmd"
    if command -v "$cmd" >/dev/null 2>&1; then
        command -v "$cmd"
    else
        echo "MISSING"
    fi
done
echo

echo "==================== 4. python info ===================="
python3 --version || true
pip3 --version || true
echo

echo "==================== 5. requirements.txt ===================="
if [ -f requirements.txt ]; then
    cat requirements.txt
else
    echo "[MISS] requirements.txt"
fi
echo

echo "==================== 6. config/default.yaml ===================="
if [ -f config/default.yaml ]; then
    sed -n '1,240p' config/default.yaml
else
    echo "[MISS] config/default.yaml"
fi
echo

echo "==================== 7. required assets ===================="

check_path() {
    local p="$1"
    if [ -e "$p" ]; then
        if [ -d "$p" ]; then
            echo "[OK ] DIR  $p"
            find "$p" -maxdepth 2 -type f | head -20 | sed 's/^/      /'
        else
            echo "[OK ] FILE $p"
            ls -lh "$p"
            file "$p" 2>/dev/null || true
            sha256sum "$p" 2>/dev/null | awk '{print "      sha256:", $1}' || true
        fi
    else
        echo "[MISS]      $p"
    fi
}

REQUIRED_PATHS=(
"./demo"
"./imgenc"
"./librknnrt.so"
"./librkllmrt.so"
"./qwen3-vl-2b_vision_rk3588.rknn"
"./qwen3-vl-2b-instruct_w8a8_rk3588.rkllm"
"./models/sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20"
"./models/sherpa-onnx-conformer-zh-stateless2-2023-05-23"
"./models/matcha-icefall-zh-baker"
"./models/vocos-22khz-univ.onnx"
"./demo.jpg"
)

missing=0
for p in "${REQUIRED_PATHS[@]}"; do
    check_path "$p"
    if [ ! -e "$p" ]; then
        missing=$((missing + 1))
    fi
done
echo

echo "==================== 8. executable bit check ===================="
for f in ./demo ./imgenc ./run_qwen3vl.sh ./scripts/capture-photo.sh ./voice_assistant.py; do
    if [ -e "$f" ]; then
        ls -lh "$f"
        if [ -x "$f" ]; then
            echo "[OK ] executable: $f"
        else
            echo "[WARN] not executable: $f"
        fi
    else
        echo "[MISS] $f"
    fi
done
echo

echo "==================== 9. ldd check ===================="
for f in ./demo ./imgenc; do
    if [ -e "$f" ]; then
        echo
        echo "----- ldd $f -----"
        ldd "$f" || true
    else
        echo "[SKIP] $f not found"
    fi
done
echo

echo "==================== 10. camera device check ===================="
echo "----- /dev/video* -----"
ls -lh /dev/video* 2>/dev/null || true
echo

echo "----- v4l2-ctl --list-devices -----"
v4l2-ctl --list-devices || true
echo

if [ -e /dev/video11 ]; then
    echo "[OK] /dev/video11 exists"
    echo
    echo "----- v4l2-ctl -d /dev/video11 --all -----"
    v4l2-ctl -d /dev/video11 --all || true
    echo
    echo "----- v4l2-ctl -d /dev/video11 --list-formats-ext -----"
    v4l2-ctl -d /dev/video11 --list-formats-ext || true
else
    echo "[WARN] /dev/video11 not found"
fi
echo

echo "==================== 11. audio device check ===================="
echo "----- arecord -l -----"
arecord -l || true
echo

echo "----- aplay -l -----"
aplay -l || true
echo

echo "----- /proc/asound/cards -----"
cat /proc/asound/cards 2>/dev/null || true
echo

echo "==================== 12. writable dir check ===================="
mkdir -p /tmp/qwen_voice_assistant
mkdir -p /home/cat/图片

ls -ld /tmp/qwen_voice_assistant || true
ls -ld /home/cat/图片 || true

touch /tmp/qwen_voice_assistant/write_test.tmp 2>/dev/null && echo "[OK] /tmp/qwen_voice_assistant writable" || echo "[WARN] /tmp/qwen_voice_assistant not writable"
rm -f /tmp/qwen_voice_assistant/write_test.tmp

touch /home/cat/图片/write_test.tmp 2>/dev/null && echo "[OK] /home/cat/图片 writable" || echo "[WARN] /home/cat/图片 not writable"
rm -f /home/cat/图片/write_test.tmp
echo

echo "==================== 13. summary ===================="
echo "missing_required_assets: $missing"

if [ "$missing" -eq 0 ]; then
    echo "[RESULT] Required assets appear complete. You can continue to Experiment 01."
else
    echo "[RESULT] Some required assets are missing. Fill them before Experiment 01."
fi

echo
echo "log saved to: $LOG"
