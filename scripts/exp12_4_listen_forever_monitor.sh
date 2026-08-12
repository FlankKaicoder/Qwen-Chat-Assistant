#!/usr/bin/env bash

set -u

PROJECT="/home/cat/ai/qwen3vl2b"
cd "$PROJECT" || exit 0

TS=$(date +%Y%m%d_%H%M%S)

OUT="output/exp12_4_listen_forever_${TS}"
mkdir -p "$OUT"

LOG="$OUT/listen_forever.log"
MONITOR="$OUT/resource_monitor.tsv"
SUMMARY="$OUT/summary.txt"

export PYTHONPATH="$PWD:$PWD/.python_packages${PYTHONPATH:+:$PYTHONPATH}"

PY="$PWD/.venv/bin/python"

PHOTO_BEFORE=$(
    find /home/cat/图片 \
        -maxdepth 1 \
        -type f \
        -name 'voice_*.jpg' \
        | wc -l
)

echo -e \
"time\tpid\trss_kb\tfd_count\tthread_count\tdemo_count\tarecord_count\tmax_temp_c" \
> "$MONITOR"

monitor_process() {
    local pid="$1"

    while kill -0 "$pid" 2>/dev/null; do
        local rss="0"
        local fd="0"
        local threads="0"
        local demo_count="0"
        local arecord_count="0"
        local max_temp="0"

        rss=$(
            awk '/VmRSS:/ {print $2}' \
                "/proc/$pid/status" \
                2>/dev/null \
            || echo 0
        )

        fd=$(
            find "/proc/$pid/fd" \
                -maxdepth 1 \
                -type l \
                2>/dev/null \
            | wc -l
        )

        threads=$(
            find "/proc/$pid/task" \
                -mindepth 1 \
                -maxdepth 1 \
                -type d \
                2>/dev/null \
            | wc -l
        )

        demo_count=$(
            pgrep -P "$pid" -x demo \
                2>/dev/null \
            | wc -l
        )

        arecord_count=$(
            pgrep -x arecord \
                2>/dev/null \
            | wc -l
        )

        max_temp=$(
            for z in /sys/class/thermal/thermal_zone*/temp; do
                [ -f "$z" ] || continue
                cat "$z"
            done \
            | sort -nr \
            | head -1
        )

        if [ -z "$max_temp" ]; then
            max_temp=0
        fi

        max_temp=$(
            awk \
                -v t="$max_temp" \
                'BEGIN { printf "%.1f", t / 1000.0 }'
        )

        echo -e \
"$(date '+%H:%M:%S')\t${pid}\t${rss}\t${fd}\t${threads}\t${demo_count}\t${arecord_count}\t${max_temp}" \
        >> "$MONITOR"

        sleep 2
    done
}

cleanup_monitor() {
    if [ -n "${MON_PID:-}" ]; then
        kill "$MON_PID" 2>/dev/null || true
        wait "$MON_PID" 2>/dev/null || true
    fi
}

trap cleanup_monitor EXIT INT TERM

echo "============================================================"
echo " Experiment 12.4: listen-forever KWS/ASR validation"
echo "============================================================"
echo
echo "请按以下顺序完成 6 轮："
echo
echo "1. 鲁班猫 -> 看一下画面"
echo "2. 鲁班猫 -> 一加一等于几"
echo "3. 鲁班猫 -> 看一下画面"
echo "4. 鲁班猫 -> 你是谁"
echo "5. 鲁班猫 -> 看一下画面"
echo "6. 鲁班猫 -> 一加一等于几"
echo
echo "完成第 6 轮后，按 Ctrl+C 结束 listen-forever。"
echo

"$PY" voice_assistant.py \
    listen-forever \
    --wake-mode kws \
    --wake-timeout 30 \
    --seconds 5 \
    --no-speak \
    --no-play \
    2>&1 | tee "$LOG" &

LISTEN_PID=$!

echo "listen_forever_pid=$LISTEN_PID"

monitor_process "$LISTEN_PID" &
MON_PID=$!

wait "$LISTEN_PID"
LISTEN_RC=$?

cleanup_monitor
MON_PID=""

PHOTO_AFTER=$(
    find /home/cat/图片 \
        -maxdepth 1 \
        -type f \
        -name 'voice_*.jpg' \
        | wc -l
)

NEW_PHOTO_COUNT=$(
    expr "$PHOTO_AFTER" - "$PHOTO_BEFORE"
)

ZOMBIE_COUNT=$(
    ps -eo stat,comm \
    | awk '$1 ~ /^Z/ && $2 == "demo" {count++} END {print count+0}'
)

FINAL_DEMO_COUNT=$(
    pgrep -x demo 2>/dev/null \
    | wc -l
)

FINAL_ARECORD_COUNT=$(
    pgrep -x arecord 2>/dev/null \
    | wc -l
)

MAX_RSS=$(
    awk \
        'NR > 1 && $3 > max {max=$3} END {print max+0}' \
        "$MONITOR"
)

FIRST_RSS=$(
    awk \
        'NR == 2 {print $3}' \
        "$MONITOR"
)

LAST_RSS=$(
    awk \
        'NR > 1 {v=$3} END {print v+0}' \
        "$MONITOR"
)

MAX_TEMP=$(
    awk \
        'NR > 1 && $8 > max {max=$8} END {print max+0}' \
        "$MONITOR"
)

{
    echo "out_dir                 : $OUT"
    echo "listen_return_code      : $LISTEN_RC"
    echo "photo_before            : $PHOTO_BEFORE"
    echo "photo_after             : $PHOTO_AFTER"
    echo "new_photo_count         : $NEW_PHOTO_COUNT"
    echo "first_rss_kb            : $FIRST_RSS"
    echo "last_rss_kb             : $LAST_RSS"
    echo "max_rss_kb              : $MAX_RSS"
    echo "max_temperature_c       : $MAX_TEMP"
    echo "final_demo_count        : $FINAL_DEMO_COUNT"
    echo "final_arecord_count     : $FINAL_ARECORD_COUNT"
    echo "demo_zombie_count       : $ZOMBIE_COUNT"
} | tee "$SUMMARY"

echo
echo "========== log =========="
echo "$LOG"

echo
echo "========== monitor =========="
echo "$MONITOR"

echo
echo "========== summary =========="
cat "$SUMMARY"

exit 0
