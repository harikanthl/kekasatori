#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST_DIR="$ROOT/ExcalidrawHost"
OUT_DIR="$ROOT/MuseDrop/Resources/ExcalidrawHost"

cd "$HOST_DIR"
npm install
npm run build

if [[ ! -f "$OUT_DIR/index.html" ]]; then
  echo "Build failed: $OUT_DIR/index.html not found" >&2
  exit 1
fi

echo "Excalidraw host built → $OUT_DIR"
