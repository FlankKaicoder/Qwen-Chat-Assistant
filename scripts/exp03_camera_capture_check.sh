#!/usr/bin/env bash

set -u

OUT_DIR="${1:-output/exp03_camera_capture_$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUT_DIR"

LOG="$OUT_DIR/exp03_camera_capture_check.log"
MARKER="$OUT_DIR/start.marker"
touch "$MARKER"

exec > >(tee "$LOG") 2>&1

echo "============================================================"
echo " Experiment 03: Camera Capture Chain Check                  "
echo "============================================================"
echo "time    : $(date '+%Y-%m-%d %H:%M:%S')"
echo "workdir : $(pwd)"
echo "out_dir : $OUT_DIR"
echo

echo "==================== 1. experiment purpose ===================="
cat <<'TXT'
本实验只验证摄像头拍照链路：

/dev/video11 -> 项目脚本 / V4L2 原始采集 -> 图片文件

本实验不运行 Qwen、不运行 ASR、不运行 TTS。
原因是先把摄像头链路单独封口，避免后续图文推理失败时问题边界不清。
TXT
echo

echo "==================== 2. repo baseline ===================="
pwd
echo
git remote -v 2>/dev/null || true
git branch --show-current 2>/dev/null || true
git log -1 --oneline 2>/dev/null || true
echo
ls -lh
echo

echo "==================== 3. command availability ===================="
for cmd in bash python3 ffmpeg ffprobe v4l2-ctl file stat find sed grep awk; do
    printf "%-12s : " "$cmd"
    if command -v "$cmd" >/dev/null 2>&1; then
        command -v "$cmd"
    else
        echo "MISSING"
    fi
done
echo

echo "==================== 4. config camera related lines ===================="
if [ -f config/default.yaml ]; then
    grep -nEi "camera|video|photo|capture|placeholder|device|image" config/default.yaml || true
else
    echo "[MISS] config/default.yaml"
fi
echo

echo "==================== 5. project camera scripts ===================="
for f in scripts/capture-photo.sh scripts/test_camera.sh voice_assistant/camera.py; do
    echo
    echo "---------- $f ----------"
    if [ -f "$f" ]; then
        ls -lh "$f"
        sed -n '1,220p' "$f"
    else
        echo "[MISS] $f"
    fi
done
echo

echo "==================== 6. video devices ===================="
echo "----- /dev/video* -----"
ls -lh /dev/video* 2>/dev/null || true
echo

echo "----- v4l2-ctl --list-devices -----"
v4l2-ctl --list-devices 2>&1 || true
echo

echo "----- /dev/video11 --all -----"
if [ -e /dev/video11 ]; then
    v4l2-ctl -d /dev/video11 --all 2>&1 || true
else
    echo "[MISS] /dev/video11"
fi
echo

echo "----- /dev/video11 --list-formats-ext -----"
if [ -e /dev/video11 ]; then
    v4l2-ctl -d /dev/video11 --list-formats-ext 2>&1 || true
else
    echo "[MISS] /dev/video11"
fi
echo

echo "==================== 7. run project camera test script ===================="
if [ -f scripts/test_camera.sh ]; then
    chmod +x scripts/test_camera.sh 2>/dev/null || true
    echo "[RUN] bash scripts/test_camera.sh"
    bash scripts/test_camera.sh > "$OUT_DIR/07_test_camera_script.log" 2>&1
    rc=$?
    echo "[RC ] scripts/test_camera.sh -> $rc"
    echo "----- log tail -----"
    tail -120 "$OUT_DIR/07_test_camera_script.log" || true
else
    echo "[SKIP] scripts/test_camera.sh not found"
fi
echo

echo "==================== 8. run project capture-photo.sh ===================="
if [ -f scripts/capture-photo.sh ]; then
    chmod +x scripts/capture-photo.sh 2>/dev/null || true

    echo "[TRY-1] bash scripts/capture-photo.sh '$OUT_DIR/project_capture_arg.jpg'"
    bash scripts/capture-photo.sh "$OUT_DIR/project_capture_arg.jpg" \
        > "$OUT_DIR/08_capture_photo_with_arg.log" 2>&1
    rc1=$?
    echo "[RC ] capture-photo.sh with arg -> $rc1"
    echo "----- with-arg log tail -----"
    tail -120 "$OUT_DIR/08_capture_photo_with_arg.log" || true
    echo

    echo "[TRY-2] bash scripts/capture-photo.sh"
    bash scripts/capture-photo.sh \
        > "$OUT_DIR/08_capture_photo_no_arg.log" 2>&1
    rc2=$?
    echo "[RC ] capture-photo.sh no arg -> $rc2"
    echo "----- no-arg log tail -----"
    tail -120 "$OUT_DIR/08_capture_photo_no_arg.log" || true
else
    echo "[SKIP] scripts/capture-photo.sh not found"
fi
echo

echo "==================== 9. find newly generated images ===================="
echo "Search new images under:"
echo "  $OUT_DIR"
echo "  /home/cat/图片"
echo

NEW_IMAGES_FILE="$OUT_DIR/09_new_images.log"
: > "$NEW_IMAGES_FILE"

for d in "$OUT_DIR" "/home/cat/图片"; do
    if [ -d "$d" ]; then
        find "$d" -type f -newer "$MARKER" \
            \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.bmp" \) \
            -printf "%T@ %p\n" 2>/dev/null >> "$NEW_IMAGES_FILE" || true
    fi
done

sort -n "$NEW_IMAGES_FILE" | tee "$OUT_DIR/09_new_images_sorted.log"

LATEST_IMG="$(sort -n "$NEW_IMAGES_FILE" | tail -1 | cut -d' ' -f2- || true)"

if [ -n "${LATEST_IMG:-}" ] && [ -f "$LATEST_IMG" ]; then
    echo
    echo "[FOUND] latest image: $LATEST_IMG"
    cp -f "$LATEST_IMG" "$OUT_DIR/latest_project_capture$(echo "$LATEST_IMG" | sed 's/.*//')" 2>/dev/null || true
    cp -f "$LATEST_IMG" "$OUT_DIR/latest_project_capture.jpg" 2>/dev/null || true
else
    echo
    echo "[WARN] no new project-generated image found yet"
fi
echo

echo "==================== 10. fallback raw V4L2 capture ===================="
echo "如果项目脚本失败，这一步用于区分："
echo "  - 摄像头驱动 /dev/video11 是否能出帧"
echo "  - 还是项目脚本本身有问题"
echo

RAW="$OUT_DIR/v4l2_frame_1280x720.nv12"
JPG="$OUT_DIR/v4l2_frame_1280x720.jpg"

if [ -e /dev/video11 ] && command -v v4l2-ctl >/dev/null 2>&1; then
    echo "[RUN] v4l2-ctl raw NV12 capture"
    v4l2-ctl -d /dev/video11 \
        --set-fmt-video=width=1280,height=720,pixelformat=NV12 \
        --stream-mmap=3 \
        --stream-count=1 \
        --stream-to="$RAW" \
        > "$OUT_DIR/10_v4l2_raw_capture.log" 2>&1
    rc=$?
    echo "[RC ] v4l2 raw capture -> $rc"
    echo "----- v4l2 raw capture log -----"
    cat "$OUT_DIR/10_v4l2_raw_capture.log" || true
    echo

    if [ -s "$RAW" ]; then
        echo "[OK ] raw file generated: $RAW"
        ls -lh "$RAW"
        stat "$RAW" || true

        if command -v ffmpeg >/dev/null 2>&1; then
            echo
            echo "[RUN] ffmpeg convert NV12 raw -> JPG"
            ffmpeg -y -hide_banner \
                -f rawvideo \
                -pix_fmt nv12 \
                -s 1280x720 \
                -i "$RAW" \
                -frames:v 1 \
                "$JPG" \
                > "$OUT_DIR/10_ffmpeg_nv12_to_jpg.log" 2>&1
            rc2=$?
            echo "[RC ] ffmpeg convert -> $rc2"
            echo "----- ffmpeg convert log -----"
            cat "$OUT_DIR/10_ffmpeg_nv12_to_jpg.log" || true
        else
            echo "[SKIP] ffmpeg missing"
        fi
    else
        echo "[WARN] raw file not generated or empty"
    fi
else
    echo "[SKIP] /dev/video11 or v4l2-ctl unavailable"
fi
echo

echo "==================== 11. output file inspection ===================="
find "$OUT_DIR" -maxdepth 1 -type f \
    \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.bmp" -o -iname "*.nv12" -o -iname "*.log" \) \
    -printf "%p\n" | sort | while read -r f; do
        echo
        echo "---------- $f ----------"
        ls -lh "$f" || true
        file "$f" 2>/dev/null || true
        if echo "$f" | grep -Eiq '\.(jpg|jpeg|png|bmp)$'; then
            ffprobe -hide_banner "$f" 2>&1 | head -40 || true
        fi
    done
echo

echo "==================== 12. final summary ===================="
PASS=0

if [ -s "$OUT_DIR/latest_project_capture.jpg" ]; then
    echo "[OK ] project script produced image: $OUT_DIR/latest_project_capture.jpg"
    PASS=1
fi

if [ -s "$JPG" ]; then
    echo "[OK ] fallback V4L2 produced image: $JPG"
    PASS=1
fi

if [ "$PASS" -eq 1 ]; then
    echo "[RESULT] Experiment 03 basic camera capture PASSED."
    echo "         摄像头至少可以完成出图。下一步可根据日志判断是项目脚本出图，还是 fallback 出图。"
else
    echo "[RESULT] Experiment 03 camera capture NOT PASSED yet."
    echo "         需要继续根据 /dev/video11、v4l2-ctl、capture-photo.sh 日志定位。"
fi

echo
echo "log saved to: $LOG"
echo "out dir     : $OUT_DIR"
