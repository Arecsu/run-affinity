# run-affinity

Run Affinity v3 natively on any Linux distribution (although only tested on Cachy OS / Arch Linux)

Provides a fully self-contained, portable Wine environment with all dependencies pre-configured. Just run the installer and you should be ready to go in no time.

## Requirements

- A 64-bit Linux distribution
- Vulkan-capable GPU with up-to-date drivers
- `wget`, `tar`, `zstd` (for extraction)
- `7z` or `unzip` (for WinMetadata restoration)
- `zenity` (optional, for DPI configuration dialog. If you have a high DPI screen, you DO need to configure this)

## Quick Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Arecsu/run-affinity/main/install.sh)
```

The script will download the preconfigured wine prefix (~1.2 GB) from GitHub Releases automatically, and also Affinity latest installer.

## Manual Install

1. Download `install.sh` and `affinity-base.tar.zst` from the [latest release](https://github.com/Arecsu/run-affinity/releases/latest).
2. Place them in the same directory.
3. Run:
   ```bash
   chmod +x install.sh
   ./install.sh
   ```
4. Follow the Affinity installer GUI when it appears.
5. Set your preferred DPI scaling when prompted.

## Package

### Base
- **Wine 11.5 staging-tkg** (Kron4ek build) with NTSync support
- Fully portable. Installs to `~/.local/share/affinity/`, no system libraries modified
- **DXVK 2.7.1** — Vulkan-based Direct3D 9/10/11 translation
- **vkd3d-proton 3.0b** — Vulkan-based Direct3D 12 translation

### Custom Patched DLLs
Built from my [wine-affinity](https://github.com/Arecsu/wine-affinity) patches:
- **d2d1.dll** — Patched Direct2D with Affinity-specific fixes (stub `Widen` with empty geometry, bezier recursion guard)
- **dxcore.dll** — Full GPU adapter enumeration (upstream Wine's is a stub), with correct PCI ID reporting through DXVK
- **opencl.dll** — Patched OpenCL with `cl_khr_d3d10_sharing` extension support, enabling GPU-accelerated OpenCL in Affinity

### Pre-installed Libraries (via winetricks)
- .NET Framework 4.8
- Visual C++ Redistributables
- Microsoft EdgeWebView2 Runtime (for Affinity's built-in browser panels)
- Core fonts

### Features
- GPU OpenCL acceleration works (NVIDIA tested, no idea about AMD/Intel)
- DPI scaling configuration via `affinity --dpi` (requires zenity)
- Desktop / Application entry
- AffinityPluginLoader + WineFix applied automatically (settings save correctly on Linux)

## Usage

```bash
affinity              # Launch Affinity
affinity --dpi        # Configure DPI scaling
affinity --winecfg    # Open Wine configuration
affinity --help       # Show usage
```

Or launch from your application menu.

### Updating Affinity

```bash
./install.sh --update
```

### Reinstalling

```bash
./install.sh --reinstall
```

### Providing Your Own Installer

```bash
./install.sh --installer /path/to/Affinity-x64.exe
```

## Component Versions

| Component | Version |
|-----------|---------|
| Wine | 11.5 staging-tkg (Kron4ek, NTSync) |
| DXVK | 2.7.1 |
| vkd3d-proton | 3.0b |
| .NET Framework | 4.8 |
| EdgeWebView2 | 142.0.3595.94 |
| Custom DLLs | [wine-affinity](https://github.com/Arecsu/wine-affinity) patches |

## Credits

- [wine-affinity](https://github.com/Arecsu/wine-affinity) — Wine patches for Affinity (d2d1, dxcore, opencl)
- [Kron4ek/Wine-Builds](https://github.com/Kron4ek/Wine-Builds) — portable Wine builds
- [ElementalWarrior (James McDonnell)](https://gitlab.winehq.org/ElementalWarrior/wine) — original Affinity Wine patches
- [doitsujin/dxvk](https://github.com/doitsujin/dxvk) — DXVK
- [HansKristian-Work/vkd3d-proton](https://github.com/HansKristian-Work/vkd3d-proton) — vkd3d-proton
- [noahc3/AffinityPluginLoader](https://github.com/noahc3/AffinityPluginLoader) — Plugin loader + WineFix
- [seapear/AffinityOnLinux](https://github.com/seapear/AffinityOnLinux) — reference installer and icon
