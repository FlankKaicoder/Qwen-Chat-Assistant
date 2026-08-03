#!/usr/bin/env bash

set -u

PROJECT_DIR="/home/cat/ai/qwen3vl2b"
cd "$PROJECT_DIR" || exit 1

OUT_DIR="${1:-output/exp10_2fa_camera_isolation_3runs_$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUT_DIR"

LOG="$OUT_DIR/run.log"
exec > >(tee "$LOG") 2>&1

DEVICE="/dev/video11"
PASS_COUNT=0
FAIL_COUNT=0
TIMEOUT_COUNT=0

echo "============================================================"
echo " Experiment 10.2f-a: Camera Isolation, Three Runs"
echo "============================================================"
echo "time        : $(date '+%Y-%m-%d %H:%M:%S')"
echo "project_dir : $PROJECT_DIR"
echo "out_dir     : $OUT_DIR"
echo "device      : $DEVICE"
echo

echo "==================== 1. source baseline ===================="

echo "----- camera.py -----"
nl -ba voice_assistant/camera.py \
    > "$OUT_DIR/camera_numbered.txt"
cat "$OUT_DIR/camera_numbered.txt"

echo
echo "----- capture-photo.sh -----"
nl -ba scripts/capture-photo.sh \
    > "$OUT_DIR/capture_photo_numbered.txt"
cat "$OUT_DIR/capture_photo_numbered.txt"
echo

echo "==================== 2. device baseline ===================="

ls -l "$DEVICE" \
    > "$OUT_DIR/device_ls.txt" 2>&1 || true
cat "$OUT_DIR/device_ls.txt"

echo
echo "----- device users before cleanup -----"

fuser -v "$DEVICE" \
    > "$OUT_DIR/fuser_before.txt" 2>&1 || true
cat "$OUT_DIR/fuser_before.txt"

echo
echo "----- related processes before cleanup -----"

ps -eo pid,ppid,stat,etime,cmd \
    | grep -E \
      "capture-photo.sh|v4l2-ctl|ffmpeg|voice_assistant.py|imgenc" \
    | grep -v -E \
      "grep|exp10_2fa_camera_isolation_3runs" \
    > "$OUT_DIR/processes_before.txt" || true

cat "$OUT_DIR/processes_before.txt"
echo

echo "==================== 3. clean project capture leftovers ===================="

pkill -TERM -f \
    "/home/cat/ai/qwen3vl2b/scripts/capture-photo.sh" \
    2>/dev/null || true

pkill -TERM -f \
    "v4l2-ctl.*(/dev/video11|video11)" \
    2>/dev/null || true

sleep 2

pkill -KILL -f \
    "/home/cat/ai/qwen3vl2b/scripts/capture-photo.sh" \
    2>/dev/null || true

pkill -KILL -f \
    "v4l2-ctl.*(/dev/video11|video11)" \
    2>/dev/null || true

sleep 1

echo "----- device users after cleanup -----"

fuser -v "$DEVICE" \
    > "$OUT_DIR/fuser_after_cleanup.txt" 2>&1 || true
cat "$OUT_DIR/fuser_after_cleanup.txt"

echo
echo "----- related processes after cleanup -----"

ps -eo pid,ppid,stat,etime,cmd \
    | grep -E \
      "capture-photo.sh|v4l2-ctl|ffmpeg|voice_assistant.py|imgenc" \
    | grep -v -E \
      "grep|exp10_2fa_camera_isolation_3runs" \
    > "$OUT_DIR/processes_after_cleanup.txt" || true

cat "$OUT_DIR/processes_after_cleanup.txt"
echo

echo "==================== 4. V4L2 query ===================="

set +e

timeout --signal=TERM --kill-after=3 10 \
    v4l2-ctl \
        --device="$DEVICE" \
        --all \
    > "$OUT_DIR/v4l2_all.txt" \
    2> "$OUT_DIR/v4l2_all_stderr.txt"

V4L2_QUERY_RC=$?

set -e

echo "v4l2_query_return_code: $V4L2_QUERY_RC"
cat "$OUT_DIR/v4l2_all.txt"
cat "$OUT_DIR/v4l2_all_stderr.txt"
echo

echo "==================== 5. three isolated captures ===================="

for index in 1 2 3; do
    RUN_DIR="$OUT_DIR/capture_$index"
    mkdir -p "$RUN_DIR"

    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    START_EPOCH=$(date +%s)

    echo
    echo "------------------------------------------------------------"
    echo " capture run $index"
    echo "------------------------------------------------------------"
    echo "start_time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "run_dir   : $RUN_DIR"
    echo

    fuser -v "$DEVICE" \
        > "$RUN_DIR/fuser_before.txt" 2>&1 || true

    set +e

    timeout --signal=TERM --kill-after=5 45 \
        bash scripts/capture-photo.sh \
            --out-dir "$RUN_DIR" \
            --prefix "isolate_${index}" \
            --timestamp "$TIMESTAMP" \
        > "$RUN_DIR/capture_stdout.txt" \
        2> "$RUN_DIR/capture_stderr.txt"

    CAPTURE_RC=$?

    set -e

    END_EPOCH=$(date +%s)
    ELAPSED_SECONDS=$((END_EPOCH - START_EPOCH))

    echo "capture_return_code: $CAPTURE_RC"
    echo "elapsed_seconds    : $ELAPSED_SECONDS"

    echo
    echo "----- stdout -----"
    cat "$RUN_DIR/capture_stdout.txt"

    echo
    echo "----- stderr -----"
    cat "$RUN_DIR/capture_stderr.txt"

    find "$RUN_DIR" \
        -maxdepth 1 \
        -type f \
        -printf '%f %s bytes\n' \
        | sort \
        > "$RUN_DIR/file_list.txt"

    echo
    echo "----- files -----"
    cat "$RUN_DIR/file_list.txt"

    PHOTO=$(
        find "$RUN_DIR" \
            -maxdepth 1 \
            -type f \
            \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) \
            | head -1
    )

    if [ -n "$PHOTO" ] && [ -s "$PHOTO" ]; then
        ffprobe -v error \
            -select_streams v:0 \
            -show_entries \
              stream=codec_name,width,height,pix_fmt \
            -of default=noprint_wrappers=1 \
            "$PHOTO" \
            > "$RUN_DIR/photo_ffprobe.txt" \
            2>&1 || true

        echo
        echo "----- photo ffprobe -----"
        cat "$RUN_DIR/photo_ffprobe.txt"
    fi

    fuser -v "$DEVICE" \
        > "$RUN_DIR/fuser_after.txt" 2>&1 || true

    ps -eo pid,ppid,stat,etime,cmd \
        | grep -E \
          "capture-photo.sh|v4l2-ctl|ffmpeg|voice_assistant.py|imgenc" \
        | grep -v -E \
          "grep|exp10_2fa_camera_isolation_3runs" \
        > "$RUN_DIR/processes_after.txt" || true

    if [ "$CAPTURE_RC" -eq 0 ] \
      && [ -n "$PHOTO" ] \
      && [ -s "$PHOTO" ]; then

        RESULT="PASS"
        PASS_COUNT=$((PASS_COUNT + 1))
    elif [ "$CAPTURE_RC" -eq 124 ] \
      || [ "$CAPTURE_RC" -eq 137 ]; then

        RESULT="TIMEOUT"
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        FAIL_COUNT=$((FAIL_COUNT + 1))
    else
        RESULT="FAIL"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi

    {
        echo "capture_index      : $index"
        echo "capture_return_code: $CAPTURE_RC"
        echo "elapsed_seconds    : $ELAPSED_SECONDS"
        echo "photo_path         : $PHOTO"
        echo "result             : $RESULT"
    } | tee "$RUN_DIR/summary.txt"

    sleep 3
done

echo
echo "==================== 6. kernel camera messages ===================="

dmesg --ctime 2>/dev/null \
    | grep -Ei \
      "rkisp|rkcif|mipi|csi|video11|imx415|v4l2|isp" \
    | tail -200 \
    > "$OUT_DIR/dmesg_camera_tail.txt" || true

cat "$OUT_DIR/dmesg_camera_tail.txt"
echo

echo "==================== 7. final residual process check ===================="

ps -eo pid,ppid,stat,etime,cmd \
    | grep -E \
      "capture-photo.sh|v4l2-ctl|ffmpeg|voice_assistant.py|imgenc" \
    | grep -v -E \
      "grep|exp10_2fa_camera_isolation_3runs" \
    > "$OUT_DIR/residual_processes.txt" || true

RESIDUAL_PROCESS_COUNT=$(
    wc -l < "$OUT_DIR/residual_processes.txt"
)

if [ "$RESIDUAL_PROCESS_COUNT" -gt 0 ]; then
    cat "$OUT_DIR/residual_processes.txt"
else
    echo "[OK] no related residual processes"
fi

echo
echo "==================== 8. summary ===================="

{
    echo "out_dir               : $OUT_DIR"
    echo "device                : $DEVICE"
    echo "v4l2_query_return_code: $V4L2_QUERY_RC"
    echo "capture_total         : 3"
    echo "capture_pass_count    : $PASS_COUNT"
    echo "capture_fail_count    : $FAIL_COUNT"
    echo "capture_timeout_count : $TIMEOUT_COUNT"
    echo "residual_process_count: $RESIDUAL_PROCESS_COUNT"
} | tee "$OUT_DIR/summary.txt"

echo

if [ "$PASS_COUNT" -eq 3 ] \
  && [ "$RESIDUAL_PROCESS_COUNT" -eq 0 ]; then

    echo "[RESULT] Experiment 10.2f-a CAMERA_STABLE_3_OF_3."
    echo "[NEXT] Add one retry to CameraAdapter, then rerun visual concise test."
elif [ "$PASS_COUNT" -ge 1 ]; then
    echo "[RESULT] Experiment 10.2f-a CAMERA_INTERMITTENT."
    echo "[NEXT] Add cleanup plus retry to CameraAdapter."
else
    echo "[RESULT] Experiment 10.2f-a CAMERA_UNAVAILABLE_OR_BLOCKED."
    echo "[NEXT] Inspect device users, capture stderr and kernel messages."
fi
