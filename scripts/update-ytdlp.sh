#!/bin/bash
# Updates yt-dlp to the latest macOS standalone release.
# MuseDrop runs equivalent logic on app launch via BinaryUpdateService.
set -euo pipefail

BIN_DIR="${HOME}/Library/Application Support/MuseDrop/bin"
YT_DLP_PATH="${BIN_DIR}/yt-dlp"
TMP_PATH="${BIN_DIR}/yt-dlp.tmp"
DOWNLOAD_URL="https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"

mkdir -p "${BIN_DIR}"

echo "Checking latest yt-dlp release..."
curl -fsSL "${DOWNLOAD_URL}" -o "${TMP_PATH}"
chmod +x "${TMP_PATH}"

if ! VERSION="$("${TMP_PATH}" --version 2>/dev/null)"; then
    rm -f "${TMP_PATH}"
    echo "Downloaded file is not a valid yt-dlp binary." >&2
    exit 1
fi

mv -f "${TMP_PATH}" "${YT_DLP_PATH}"
xattr -d com.apple.quarantine "${YT_DLP_PATH}" 2>/dev/null || true

echo "yt-dlp updated to ${VERSION}"
echo "Binary location: ${YT_DLP_PATH}"
