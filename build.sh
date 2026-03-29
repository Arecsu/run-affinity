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

# Squished GUID format used by MSI UpgradeCodes entries.
# First 3 components are fully reversed; last 2 have each pair of chars swapped.
def squish_guid(guid):
    g = guid.strip('{}').replace('-', '')
    c1, c2, c3 = g[0:8][::-1], g[8:12][::-1], g[12:16][::-1]
    swap = lambda s: ''.join(s[i+1]+s[i] for i in range(0, len(s), 2))
    return c1 + c2 + c3 + swap(g[16:20]) + swap(g[20:32])

# Known Affinity product GUIDs — their squished forms appear as values in
# UpgradeCodes entries, which MsiEnumRelatedProducts uses to detect existing installs.
#
# How these were found:
#   1. Run the installer with WINEDEBUG=+reg and observe it opening
#      'SOFTWARE\Serif\Affinity\Affinity' (found in SetupUI.log under
#      AppData/Local/Temp/AffinitySetup/<uuid>/SetupUI.log).
#   2. SetupUI.log shows: MsiEnumRelatedProducts → IsAnyVersionInstalled: True,
#      using UpgradeCode {92E5A9B4-9D51-45EB-A6C8-85C3A04099B2}.
#   3. MsiEnumRelatedProducts looks up squished UpgradeCodes keys in
#      Software\Classes\Installer\UpgradeCodes\ and
#      Software\Microsoft\Windows\CurrentVersion\Installer\UpgradeCodes\
#      and finds the squished product GUID as the value.
#   4. The product GUIDs below were collected from
#      Software\Microsoft\Windows\CurrentVersion\Uninstall\{...} blocks
#      (DisplayName = "Affinity", "Affinity Photo 2", "Affinity Designer 2").
AFFINITY_PRODUCT_GUIDS = [
    '{04B92E6E-F98B-424D-ACD4-D6DFAD696947}',
    '{8BD2A40D-67A6-45F5-877D-6D9D04C9D5A2}',
    '{BB7D42B8-B4F0-4703-A0F5-801B34C9D57A}',
    '{D462B8D8-7672-4E28-91D2-1EDBE7291680}',
]
affinity_squished = set(squish_guid(g) for g in AFFINITY_PRODUCT_GUIDS)

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
        key_line = (parts[i+1] if i+1 < len(parts) else "").split('\n')[0]
        values = (parts[i+1] if i+1 < len(parts) else "")
        # Remove if the key path itself mentions affinity/serif
        key_matches = bool(re.search(r'affinity|serif', key_line, re.IGNORECASE))
        # Also remove .af* file extension registrations (Affinity file types)
        key_matches = key_matches or bool(re.search(r'Classes\\\\\.af([a-z]|\\])', key_line, re.IGNORECASE))
        # Also remove entries under MSI/installer paths where values mention affinity/serif
        # (these have GUID key paths, so key path matching alone won't catch them)
        msi_path = bool(re.search(r'Uninstall|Installer\\\\(Products|Features|Components|Patches)|UserData\\\\[^\\\\]+\\\\(Products|Components|Features|Patches)', key_line, re.IGNORECASE))
        # Also remove CLSID registrations that point to Affinity DLLs
        clsid_path = bool(re.search(r'Classes\\\\CLSID', key_line, re.IGNORECASE))
        value_matches = (msi_path or clsid_path) and bool(re.search(r'affinity|serif', values, re.IGNORECASE))
        # Also remove UpgradeCodes entries whose values are squished Affinity product GUIDs
        # (MsiEnumRelatedProducts checks these to detect any installed version)
        if not value_matches and 'UpgradeCodes' in key_line:
            value_matches = any(s in values for s in affinity_squished)
        if key_matches or value_matches:
            i += 2
            continue
        result.append(parts[i] + values)
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
    --exclude='prefix/drive_c/users/*/AppData/Roaming/Affinity' \
    --exclude='prefix/drive_c/users/*/AppData/Local/Affinity' \
    --exclude='prefix/drive_c/users/*/AppData/Local/Temp' \
    --exclude='*.bak' \
    --exclude='*.orig' \
    wine/ prefix/

echo "Done: $(du -sh "${OUTPUT}" | cut -f1)"

# ─── Restore registry backups ─────────────────────────────────────────────────
echo "Restoring registry backups..."
for regfile in prefix/system.reg prefix/user.reg prefix/userdef.reg; do
    bak="${AFFINITY_DIR}/${regfile}.bak"
    [ -f "$bak" ] && mv "$bak" "${AFFINITY_DIR}/${regfile}"
done
echo "Done."
