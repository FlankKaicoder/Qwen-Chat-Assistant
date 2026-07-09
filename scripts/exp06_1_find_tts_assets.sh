#!/usr/bin/env bash
set -u

OUT="${1:-output/exp06_1_find_tts_assets_$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUT"
LOG="$OUT/run.log"

exec > >(tee "$LOG") 2>&1

echo "============================================================"
echo " Experiment 06.1: find and prepare TTS assets"
echo "============================================================"
echo "time    : $(date '+%Y-%m-%d %H:%M:%S')"
echo "workdir : $(pwd)"
echo "out_dir : $OUT"
echo

echo "==================== 1. expected config paths ===================="
grep -nA10 "tts:" config/default.yaml || true
echo

EXPECTED_MATCHA="./models/matcha-icefall-zh-baker"
EXPECTED_VOCOS="./models/vocos-22khz-univ.onnx"

echo "expected_matcha_dir : $EXPECTED_MATCHA"
echo "expected_vocos_file : $EXPECTED_VOCOS"
echo

echo "==================== 2. search roots ===================="
ROOTS=(
  "/home/cat/ai"
  "/home/cat"
  "/media/cat"
  "/home/cat/Downloads"
  "/home/cat/下载"
)

EXIST_ROOTS=()
for r in "${ROOTS[@]}"; do
    if [ -e "$r" ]; then
        EXIST_ROOTS+=("$r")
        echo "[OK] $r"
    else
        echo "[MISS] $r"
    fi
done
echo

echo "==================== 3. find matcha acoustic model ===================="
: > "$OUT/matcha_model_candidates.txt"
for r in "${EXIST_ROOTS[@]}"; do
    find "$r" \
      -type f \
      \( -name "model-steps-3.onnx" -o -iname "*matcha*.onnx" \) \
      2>/dev/null
done | sort -u | tee "$OUT/matcha_model_candidates.txt"
echo

echo "==================== 4. find vocos model ===================="
: > "$OUT/vocos_candidates.txt"
for r in "${EXIST_ROOTS[@]}"; do
    find "$r" \
      -type f \
      \( -name "vocos-22khz-univ.onnx" -o -iname "*vocos*.onnx" \) \
      2>/dev/null
done | sort -u | tee "$OUT/vocos_candidates.txt"
echo

echo "==================== 5. find complete matcha directories ===================="
: > "$OUT/matcha_dir_candidates.txt"

while IFS= read -r model; do
    [ -n "$model" ] || continue
    d="$(dirname "$model")"
    ok=1

    [ -f "$d/model-steps-3.onnx" ] || ok=0
    [ -f "$d/lexicon.txt" ] || ok=0
    [ -f "$d/tokens.txt" ] || ok=0

    if [ "$ok" -eq 1 ]; then
        echo "$d"
    fi
done < "$OUT/matcha_model_candidates.txt" | sort -u | tee "$OUT/matcha_dir_candidates.txt"

echo

echo "==================== 6. candidate detail ===================="
while IFS= read -r d; do
    [ -n "$d" ] || continue
    echo
    echo "----- MATCHA DIR: $d -----"
    ls -lh "$d" | head -80
    echo
    echo "files:"
    find "$d" -maxdepth 1 -type f | sort
done < "$OUT/matcha_dir_candidates.txt"

echo

while IFS= read -r f; do
    [ -n "$f" ] || continue
    echo
    echo "----- VOCOS FILE: $f -----"
    ls -lh "$f"
    file "$f" 2>/dev/null || true
done < "$OUT/vocos_candidates.txt"

echo

echo "==================== 7. auto copy if unique ===================="
MATCHA_COUNT=$(grep -c . "$OUT/matcha_dir_candidates.txt" 2>/dev/null || echo 0)
VOCOS_COUNT=$(grep -c . "$OUT/vocos_candidates.txt" 2>/dev/null || echo 0)

echo "matcha_candidate_count: $MATCHA_COUNT"
echo "vocos_candidate_count : $VOCOS_COUNT"

AUTO_COPIED=0

if [ "$MATCHA_COUNT" -eq 1 ] && [ "$VOCOS_COUNT" -eq 1 ]; then
    SRC_MATCHA="$(cat "$OUT/matcha_dir_candidates.txt")"
    SRC_VOCOS="$(cat "$OUT/vocos_candidates.txt")"

    echo
    echo "[INFO] unique TTS assets found."
    echo "src_matcha: $SRC_MATCHA"
    echo "src_vocos : $SRC_VOCOS"
    echo

    mkdir -p models

    if [ -e "$EXPECTED_MATCHA" ]; then
        echo "[SKIP] expected matcha dir already exists: $EXPECTED_MATCHA"
    else
        cp -av "$SRC_MATCHA" "$EXPECTED_MATCHA"
    fi

    if [ -e "$EXPECTED_VOCOS" ]; then
        echo "[SKIP] expected vocos file already exists: $EXPECTED_VOCOS"
    else
        cp -av "$SRC_VOCOS" "$EXPECTED_VOCOS"
    fi

    AUTO_COPIED=1
else
    echo
    echo "[INFO] not auto-copying because candidate count is not unique."
    echo "[INFO] If candidates exist, choose the correct one manually."
fi

echo

echo "==================== 8. final expected asset check ===================="

missing=0

check_file() {
    local p="$1"
    if [ -e "$p" ]; then
        echo "[OK] $p"
        ls -lh "$p"
    else
        echo "[MISS] $p"
        missing=$((missing + 1))
    fi
}

check_file "$EXPECTED_MATCHA/model-steps-3.onnx"
check_file "$EXPECTED_MATCHA/lexicon.txt"
check_file "$EXPECTED_MATCHA/tokens.txt"
check_file "$EXPECTED_VOCOS"

echo
echo "auto_copied: $AUTO_COPIED"
echo "missing_tts_required_files: $missing"

if [ "$missing" -eq 0 ]; then
    echo "[RESULT] Experiment 06.1 PASSED: TTS assets prepared."
else
    echo "[RESULT] Experiment 06.1 BLOCKED: TTS assets still missing."
fi

echo
echo "log saved to: $LOG"
