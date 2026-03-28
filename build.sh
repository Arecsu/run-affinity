#!/bin/bash
# build.sh — rebuild affinity-base.tar.zst from the current installation
#
# Excludes Affinity program files, MSI installer cache, and cleans
# Affinity/Serif registry entries from the prefix so the installer
# doesn't see a previous installation.
#
# Run this after updating Wine DLLs or the prefix configuration.

set -euo pipefail

AFFINITY_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/affinity"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT="${SCRIPT_DIR}/affinity-base.tar.zst"
WORK_DIR="$(mktemp -d)"

cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

if [ ! -d "${AFFINITY_DIR}/wine" ] || [ ! -d "${AFFINITY_DIR}/prefix" ]; then
    echo "Error: no Affinity installation found at ${AFFINITY_DIR}" >&2
    exit 1
fi

echo "Building archive from ${AFFINITY_DIR}..."
echo "Output: ${OUTPUT}"

# ─── Clean registry ───────────────────────────────────────────────────────────
echo "Cleaning Affinity/Serif registry entries..."

python3 - <<'PYEOF'
import re, shutil, os

affinity_dir = os.path.expandvars(os.path.expanduser(
    os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share")) + "/affinity"
))

for regfile in ["prefix/system.reg", "prefix/user.reg", "prefix/userdef.reg"]:
    path = os.path.join(affinity_dir, regfile)
    if not os.path.exists(path):
        continue

    with open(path, "r", errors="replace") as f:
        content = f.read()

    # Split into header + blocks (each block starts with a [key] line)
    parts = re.split(r'(\n\[)', content)
    result = [parts[0]]
    i = 1
    while i < len(parts):
        block = parts[i] + (parts[i+1] if i+1 < len(parts) else "")
        if re.search(r'affinity|serif', block, re.IGNORECASE):
            i += 2
            continue
        result.append(block)
        i += 2

    cleaned = "".join(result)
    removed = content.count("\n[") - cleaned.count("\n[")

    shutil.copy2(path, path + ".bak")
    with open(path, "w") as f:
        f.write(cleaned)

    print(f"  {regfile}: removed {removed} keys")
PYEOF

echo "Registry cleaned."

# ─── Build archive ────────────────────────────────────────────────────────────
rm -f "${OUTPUT}"

tar -I zstd -cf "${OUTPUT}" \
    -C "${AFFINITY_DIR}" \
    --transform 's/^prefix/wineprefix/' \
    --exclude='prefix/drive_c/Program Files/Affinity' \
    --exclude='prefix/drive_c/windows/Installer' \
    wine/ prefix/

echo "Done: $(du -sh "${OUTPUT}" | cut -f1)"

# ─── Restore registry backups ─────────────────────────────────────────────────
echo "Restoring registry backups..."
for regfile in prefix/system.reg prefix/user.reg prefix/userdef.reg; do
    bak="${AFFINITY_DIR}/${regfile}.bak"
    [ -f "$bak" ] && mv "$bak" "${AFFINITY_DIR}/${regfile}"
done
echo "Done."
