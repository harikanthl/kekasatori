#!/usr/bin/env bash
set -euo pipefail

SRC="${SRCROOT}/MuseDrop/Resources/ExcalidrawHost"
DEST="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/ExcalidrawHost"

if [[ ! -f "${SRC}/index.html" ]]; then
  echo "error: Excalidraw host missing at ${SRC}/index.html" >&2
  echo "Run ./scripts/build-excalidraw-host.sh first." >&2
  exit 1
fi

rm -rf "${DEST}"
mkdir -p "${DEST}"
ditto "${SRC}" "${DEST}"

echo "Copied Excalidraw host → ${DEST}"
