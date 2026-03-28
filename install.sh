#!/bin/bash
# install.sh — Affinity installer for Linux
#
# Extracts a pre-configured Wine base (affinity-base.tar.zst, downloaded from
# GitHub Releases or bundled alongside this script) to the proper XDG location,
# installs the latest Affinity on top,
# applies the AffinityPluginLoader + WineFix patch, and creates a desktop entry.
#
# Wine:   Kron4ek Wine 11.5 staging-tkg
# DXVK:   2.7.1
# vkd3d:  proton 3.0b
# Custom: d2d1.dll, dxcore.dll, opencl.dll (ElementalWarrior patches)
#
# Usage:
#   ./install.sh [--installer /path/to/Affinity.exe]
#   ./install.sh --reinstall
#   ./install.sh --update

set -euo pipefail

# ─── Paths ────────────────────────────────────────────────────────────────────

INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/affinity"
WINE_DIR="${INSTALL_DIR}/wine"
PREFIX_DIR="${INSTALL_DIR}/prefix"
BIN_DIR="${HOME}/.local/bin"
APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICONS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps"

AFFINITY_EXE="${PREFIX_DIR}/drive_c/Program Files/Affinity/Affinity/Affinity.exe"
AFFINITY_APP_DIR="${PREFIX_DIR}/drive_c/Program Files/Affinity/Affinity"

AFFINITY_URL="https://downloads.affinity.studio/Affinity%20x64.exe"
PLUGIN_LOADER_URL="https://github.com/noahc3/AffinityPluginLoader/releases/latest/download/affinitypluginloader-plus-winefix.tar.xz"
AFFINITY_ICON_URL="https://raw.githubusercontent.com/seapear/AffinityOnLinux/main/Assets/Icons/Affinity-Canva.svg"

WINMD_URL="https://github.com/microsoft/windows-rs/raw/master/crates/libs/bindgen/default/Windows.winmd"

# ─── Colours ──────────────────────────────────────────────────────────────────

if [ -t 1 ]; then
    R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m'
    B='\033[0;34m' C='\033[0;36m' W='\033[1m' N='\033[0m'
else
    R='' G='' Y='' B='' C='' W='' N=''
fi

step()   { echo -e "\n${B}▶${N} $*"; }
ok()     { echo -e "  ${G}✓${N} $*"; }
info()   { echo -e "  ${C}·${N} $*"; }
warn()   { echo -e "  ${Y}!${N} $*"; }
die()    { echo -e "\n${R}✗ $*${N}\n" >&2; exit 1; }

header() {
    echo ""
    echo -e "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
    echo -e "  ${W}$*${N}"
    echo -e "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
}

# ─── Args ─────────────────────────────────────────────────────────────────────

USER_INSTALLER=""
MODE="install"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_ARCHIVE="${SCRIPT_DIR}/affinity-base.tar.zst"

GITHUB_REPO="Arecsu/run-affinity"
BASE_ARCHIVE_URL="https://github.com/${GITHUB_REPO}/releases/latest/download/affinity-base.tar.zst"
BASE_VERSION="$(wget -qO- "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" 2>/dev/null | grep '"tag_name"' | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --installer) USER_INSTALLER="$2"; shift 2 ;;
        --reinstall) MODE="reinstall"; shift ;;
        --update)    MODE="update"; shift ;;
        *) die "Unknown argument: $1" ;;
    esac
done

# ─── Helpers ──────────────────────────────────────────────────────────────────

download() {
    local url="$1" dest="$2" label="${3:-file}"
    info "Downloading ${label}..."
    wget -q --show-progress -O "$dest" "$url" || die "Failed to download: $label"
    ok "${label} downloaded"
}

wine_env() {
    export WINEPREFIX="$PREFIX_DIR"
    export WINELOADER="${WINE_DIR}/bin/wine"
    export WINEDLLPATH="${WINE_DIR}/lib/wine"
    export PATH="${WINE_DIR}/bin:${PATH}"
    export DXVK_ASYNC=0
    export DXVK_CONFIG="d3d9.deferSurfaceCreation = True; d3d9.shaderModel = 1"
    export DXVK_CONFIG_FILE="${PREFIX_DIR}/drive_c/dxvk.conf"
}

wine_run() {
    wine_env
    "${WINE_DIR}/bin/wine" "$@"
}

wine_stop() {
    wine_env
    "${WINE_DIR}/bin/wineserver" -k 2>/dev/null || true
    sleep 1
}

restore_winmetadata() {
    local zip="${INSTALL_DIR}/WinMetadata.zip"
    [ -f "$zip" ] || return 0
    info "Restoring WinMetadata..."
    mkdir -p "${PREFIX_DIR}/drive_c/windows/system32"
    if command -v 7z &>/dev/null; then
        7z x "$zip" -o"${PREFIX_DIR}/drive_c/windows/system32" -y >/dev/null 2>&1
    else
        unzip -o -q "$zip" -d "${PREFIX_DIR}/drive_c/windows/system32"
    fi
    ok "WinMetadata restored"
}

# ─── Extract base archive ─────────────────────────────────────────────────────

extract_base() {
    if [ ! -f "$BASE_ARCHIVE" ]; then
        step "Downloading base archive..."
        info "Version: ${BASE_VERSION:-latest}"
        BASE_ARCHIVE="/tmp/affinity-base.tar.zst"
        download "$BASE_ARCHIVE_URL" "$BASE_ARCHIVE" "affinity-base.tar.zst (~1.2 GB)"
    fi

    step "Extracting base archive..."
    info "Source: $BASE_ARCHIVE ($(du -sh "$BASE_ARCHIVE" | cut -f1))"

    mkdir -p "$INSTALL_DIR"
    tar -I zstd -xf "$BASE_ARCHIVE" -C "$INSTALL_DIR" 2>/dev/null &
    TAR_PID=$!
    i=0; chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    while kill -0 $TAR_PID 2>/dev/null; do
        printf "\r  ${C}${chars:i++%${#chars}:1}${N} Extracting..."
        sleep 0.08
    done
    printf "\r  \r"
    wait $TAR_PID

    # The archive contains wine/ and wineprefix/ — rename wineprefix → prefix
    if [ -d "${INSTALL_DIR}/wineprefix" ] && [ ! -d "${INSTALL_DIR}/prefix" ]; then
        mv "${INSTALL_DIR}/wineprefix" "${INSTALL_DIR}/prefix"
    fi

    ok "Wine:   $(du -sh "$WINE_DIR" | cut -f1)"
    ok "Prefix: $(du -sh "$PREFIX_DIR" | cut -f1)"

    fix_username
}

fix_username() {
    local old_user="arecsu"
    local new_user="${USER:-$(whoami)}"
    [ "$old_user" = "$new_user" ] && return

    step "Adapting prefix for user '${new_user}'..."

    for regfile in "${PREFIX_DIR}/user.reg" "${PREFIX_DIR}/userdef.reg"; do
        [ -f "$regfile" ] || continue
        sed -i \
            -e "s|\\\\users\\\\${old_user}|\\\\users\\\\${new_user}|g" \
            -e "s|users\\\\${old_user}|users\\\\${new_user}|g" \
            -e "s|\"USERNAME\"=\"${old_user}\"|\"USERNAME\"=\"${new_user}\"|g" \
            "$regfile"
    done

    local old_dir="${PREFIX_DIR}/drive_c/users/${old_user}"
    local new_dir="${PREFIX_DIR}/drive_c/users/${new_user}"
    if [ -d "$old_dir" ] && [ ! -d "$new_dir" ]; then
        mv "$old_dir" "$new_dir"
    fi

    ok "Username updated"
}

prepare_prefix() {
    step "Preparing Wine prefix for new environment..."
    mkdir -p "${PREFIX_DIR}/dosdevices"
    ln -sfn "../drive_c" "${PREFIX_DIR}/dosdevices/c:"
    ln -sfn "/" "${PREFIX_DIR}/dosdevices/z:"

    wine_run wineboot --update >/dev/null 2>&1 || true
    wine_stop

    fix_username

    local current_user="${USER:-$(whoami)}"
    local temp_dir="${PREFIX_DIR}/drive_c/users/${current_user}/AppData/Local/Temp"
    mkdir -p "$temp_dir"

    local win_temp="C:\\\\users\\\\${current_user}\\\\AppData\\\\Local\\\\Temp"
    wine_run reg add "HKCU\\Environment" /v TEMP /t REG_SZ /d "${win_temp}" /f >/dev/null 2>&1 || true
    wine_run reg add "HKCU\\Environment" /v TMP  /t REG_SZ /d "${win_temp}" /f >/dev/null 2>&1 || true
    wine_stop

    ok "Prefix ready"
}

# ─── Install Affinity ─────────────────────────────────────────────────────────

install_affinity() {
    local installer

    if [ -n "$USER_INSTALLER" ]; then
        [ -f "$USER_INSTALLER" ] || die "Installer not found: $USER_INSTALLER"
        installer="$USER_INSTALLER"
        info "Using provided installer: $installer"
    else
        installer="/tmp/Affinity-x64.exe"
        download "$AFFINITY_URL" "$installer" "Affinity v3 installer"
    fi

    step "Running Affinity installer..."
    warn "Follow the installer GUI, then close it when done."
    wine_stop
    pkill -9 wineserver 2>/dev/null || true
    sleep 2
    wine_run "$installer" 2>/dev/null
    pkill -9 wineserver 2>/dev/null || true
    sleep 1

    [ -z "$USER_INSTALLER" ] && rm -f "$installer"

    [ -f "$AFFINITY_EXE" ] || die "Affinity.exe not found — did the installer complete successfully?"

    ok "Affinity installed"
}

# ─── AffinityPluginLoader + WineFix ───────────────────────────────────────────

apply_plugin_loader() {
    step "Applying AffinityPluginLoader + WineFix..."

    local bundle="/tmp/affinitypluginloader-plus-winefix.tar.xz"
    download "$PLUGIN_LOADER_URL" "$bundle" "AffinityPluginLoader + WineFix"

    tar -xf "$bundle" -C "${AFFINITY_APP_DIR}"
    rm -f "$bundle"

    if [ -f "${AFFINITY_APP_DIR}/AffinityHook.exe" ] && [ ! -f "${AFFINITY_APP_DIR}/Affinity.real.exe" ]; then
        mv "${AFFINITY_APP_DIR}/Affinity.exe"     "${AFFINITY_APP_DIR}/Affinity.real.exe"
        mv "${AFFINITY_APP_DIR}/AffinityHook.exe" "${AFFINITY_APP_DIR}/Affinity.exe"
        ok "Launcher swapped — settings will save correctly on Linux"
    elif [ -f "${AFFINITY_APP_DIR}/Affinity.real.exe" ]; then
        ok "AffinityPluginLoader already applied"
    else
        warn "AffinityHook.exe not found — check the extracted bundle"
    fi
}

# ─── Desktop integration ──────────────────────────────────────────────────────

create_launcher() {
    step "Creating launcher script..."
    mkdir -p "$BIN_DIR"

    cat > "${BIN_DIR}/affinity" <<LAUNCHER
#!/bin/bash
export WINEPREFIX="${PREFIX_DIR}"
export WINELOADER="${WINE_DIR}/bin/wine"
export WINEDLLPATH="${WINE_DIR}/lib/wine"
export PATH="${WINE_DIR}/bin:\${PATH}"
export DXVK_ASYNC=0
export DXVK_CONFIG="d3d9.deferSurfaceCreation = True; d3d9.shaderModel = 1"
export DXVK_CONFIG_FILE="${PREFIX_DIR}/drive_c/dxvk.conf"

if [ "\$1" = "--dpi" ]; then
    exec "${BIN_DIR}/affinity-dpi-config"
fi
if [ "\$1" = "--winecfg" ]; then
    exec "${WINE_DIR}/bin/wine" winecfg
fi
if [ "\$1" = "--help" ]; then
    echo "Usage: affinity [--dpi | --winecfg | --help]"
    exit 0
fi

exec "${WINE_DIR}/bin/wine" "${AFFINITY_EXE}" "\$@" 2>/dev/null
LAUNCHER
    chmod +x "${BIN_DIR}/affinity"
    ok "Launcher: ${BIN_DIR}/affinity"
}

create_dpi_config() {
    mkdir -p "$BIN_DIR"

    cat > "${BIN_DIR}/affinity-dpi-config" <<DPISCRIPT
#!/bin/bash
WINEPREFIX="${PREFIX_DIR}"
REGEDIT="${WINE_DIR}/bin/regedit"
export WINEPREFIX
export PATH="${WINE_DIR}/bin:\${PATH}"

command -v zenity &>/dev/null || { echo "zenity is required" >&2; exit 1; }

get_dpi() {
    local reg="\${WINEPREFIX}/user.reg"
    local hex
    hex=\$(grep -A20 '\[Control Panel\\\\Desktop\]' "\$reg" 2>/dev/null \\
        | grep '"LogPixels"' | sed 's/.*dword:\([0-9a-fA-F]*\).*/\1/')
    [ -n "\$hex" ] && echo \$((0x\$hex)) || echo 96
}

cur=\$(get_dpi)
pct=\$(( (cur * 100) / 96 ))

dpi=\$(zenity --scale \\
    --title="Affinity DPI Configuration" \\
    --text="Adjust DPI scaling (96–480)\nCurrent: \${cur} DPI (\${pct}%)" \\
    --min-value=96 --max-value=480 --value="\$cur" --step=12 2>/dev/null) || exit 0

[ -z "\$dpi" ] && exit 0

hex=\$(printf "%08x" "\$dpi")
tmp=\$(mktemp /tmp/affinity-dpi-XXXXXX.reg)
cat > "\$tmp" <<REG
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\\Control Panel\\Desktop]
"LogPixels"=dword:\${hex}
REG
"\$REGEDIT" "\$tmp" >/dev/null 2>&1
rm -f "\$tmp"

new_pct=\$(( (dpi * 100) / 96 ))
zenity --info --title="DPI Set" \\
    --text="DPI set to \${dpi} (\${new_pct}%).\n\nRestart Affinity to apply." 2>/dev/null
DPISCRIPT

    chmod +x "${BIN_DIR}/affinity-dpi-config"
    ok "DPI config: ${BIN_DIR}/affinity-dpi-config"
}

create_desktop_entry() {
    step "Creating desktop entry..."
    mkdir -p "$APPS_DIR" "$ICONS_DIR"

    info "Downloading Affinity icon..."
    wget -q --timeout=10 -O "${ICONS_DIR}/affinity.svg" "$AFFINITY_ICON_URL" 2>/dev/null \
        && ok "Icon downloaded" \
        || warn "Could not download icon — desktop entry will use fallback"

    cat > "${APPS_DIR}/affinity.desktop" <<EOF
[Desktop Entry]
Name=Affinity
Comment=The unified Affinity application
Icon=${ICONS_DIR}/affinity.svg
Exec=${BIN_DIR}/affinity %U
Terminal=false
Type=Application
Categories=Graphics;
StartupNotify=true
StartupWMClass=affinity.exe
Actions=DPI;WineCfg;

[Desktop Action DPI]
Name=Configure DPI
Exec=${BIN_DIR}/affinity-dpi-config

[Desktop Action WineCfg]
Name=Wine Configuration
Exec=${BIN_DIR}/affinity --winecfg
EOF

    rm -f "${APPS_DIR}/wine/Programs/Affinity.desktop" \
          "${APPS_DIR}/wine-protocol-affinity.desktop"

    update-desktop-database "$APPS_DIR" 2>/dev/null || true
    ok "Desktop entry created"
}

run_dpi_config() {
    step "DPI configuration..."
    info "Opening DPI dialog — set your preferred scaling and close it."
    pkill -9 wineserver 2>/dev/null || true
    sleep 3
    "${BIN_DIR}/affinity-dpi-config"
}

# ─── Main ─────────────────────────────────────────────────────────────────────

header "Affinity Linux Installer"
echo ""
echo -e "  Base archive : ${C}${BASE_ARCHIVE}${N}"
echo -e "  Version      : ${C}${BASE_VERSION:-local}${N}"
echo -e "  Install dir  : ${C}${INSTALL_DIR}${N}"
echo -e "  Mode         : ${W}${MODE}${N}"

# Preflight
for cmd in wget tar; do
    command -v "$cmd" &>/dev/null || die "Missing required tool: $cmd"
done
if ! command -v 7z &>/dev/null && ! command -v unzip &>/dev/null; then
    die "Need either 7z or unzip installed"
fi

mkdir -p "$INSTALL_DIR" "$BIN_DIR" "$APPS_DIR"

case "$MODE" in

    install)
        if [ -d "${WINE_DIR}" ] || [ -d "${PREFIX_DIR}" ]; then
            die "Existing installation found at ${INSTALL_DIR}\nUse --reinstall to wipe and reinstall, or --update to only update Affinity."
        fi
        header "Extracting base (Wine + prefix)"
        extract_base
        header "Preparing prefix"
        prepare_prefix
        header "Installing Affinity"
        install_affinity
        restore_winmetadata
        header "Applying AffinityPluginLoader + WineFix"
        apply_plugin_loader
        header "Desktop integration"
        create_launcher
        create_dpi_config
        create_desktop_entry
        header "DPI configuration"
        run_dpi_config
        ;;

    reinstall)
        header "Removing existing installation"
        step "Wiping ${INSTALL_DIR}..."
        rm -rf "$INSTALL_DIR"
        mkdir -p "$INSTALL_DIR"
        ok "Wiped"
        header "Extracting base (Wine + prefix)"
        extract_base
        header "Preparing prefix"
        prepare_prefix
        header "Installing Affinity"
        install_affinity
        restore_winmetadata
        header "Applying AffinityPluginLoader + WineFix"
        apply_plugin_loader
        header "Desktop integration"
        create_launcher
        create_dpi_config
        create_desktop_entry
        header "DPI configuration"
        run_dpi_config
        ;;

    update)
        [ -d "$WINE_DIR" ]  || die "No existing installation found. Run without --update first."
        [ -d "$PREFIX_DIR" ] || die "No existing prefix found. Run without --update first."
        header "Updating Affinity"
        wine_stop
        install_affinity
        restore_winmetadata
        header "Updating AffinityPluginLoader + WineFix"
        apply_plugin_loader
        ok "Update complete — desktop entry and Wine prefix unchanged"
        ;;

esac

echo ""
echo -e "${G}${W}Done!${N}"
echo ""
echo -e "  Launch   : ${C}affinity${N}  (or from your app menu)"
echo -e "  DPI      : ${C}affinity --dpi${N}"
echo -e "  Wine cfg : ${C}affinity --winecfg${N}"
echo -e "  Update   : ${C}./install.sh --update${N}"
echo ""
