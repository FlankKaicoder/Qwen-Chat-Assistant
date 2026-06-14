#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

seconds="${1:-5}"
wav="${2:-/tmp/qwen_voice_assistant/test_record_only.wav}"
mkdir -p "$(dirname "$wav")"

if [ -x .venv/bin/python ]; then
    PYTHON=.venv/bin/python
else
    PYTHON=python3
fi

echo "Using python: $PYTHON"
echo "Recording ${seconds}s to ${wav}. Speak after recording starts."
"$PYTHON" voice_assistant.py record --seconds "$seconds" --out "$wav"
echo "Record done: $wav"
ls -lh "$wav"
file "$wav" || true
