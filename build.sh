#!/bin/bash
# build.sh — rebuild affinity-base.tar.zst from the current installation
#
# Excludes Affinity program files and MSI installer cache.
# Run this after updating Wine DLLs or the prefix configuration.

set -euo pipefail

AFFINITY_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/affinity"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT="${SCRIPT_DIR}/affinity-base.tar.zst"

if [ ! -d "${AFFINITY_DIR}/wine" ] || [ ! -d "${AFFINITY_DIR}/prefix" ]; then
    echo "Error: no Affinity installation found at ${AFFINITY_DIR}" >&2
    exit 1
fi

echo "Building archive from ${AFFINITY_DIR}..."
echo "Output: ${OUTPUT}"

rm -f "${OUTPUT}"

tar -I zstd -cf "${OUTPUT}" \
    -C "${AFFINITY_DIR}" \
    --transform 's/^prefix/wineprefix/' \
    --exclude='prefix/drive_c/Program Files/Affinity' \
    --exclude='prefix/drive_c/windows/Installer' \
    wine/ prefix/

echo "Done: $(du -sh "${OUTPUT}" | cut -f1)"
