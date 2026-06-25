# iNiR Dotfiles

One-command system bootstrap for Fedora/Nobara Linux and **Asahi Fedora (Apple Silicon Mac)** with the iNiR desktop environment.

## Quick Start (New System)

```bash
curl -fsSL https://raw.githubusercontent.com/leeprky/dotfiles/main/setup.sh | bash
```

The script auto-detects your OS and architecture (x86_64 vs aarch64) and applies the correct configuration.

### Recommended: Install iNiR separately first

Run the bootstrap **after** installing iNiR so the script doesn't touch your iNiR state:

```bash
# 1. Install iNiR
git clone --depth 1 https://github.com/snowarch/inir.git ~/.config/quickshell/inir
cd ~/.config/quickshell/inir && sudo make install

# 2. Run dotfiles bootstrap (skips iNiR setup)
curl -fsSL https://raw.githubusercontent.com/leeprky/dotfiles/main/setup.sh | bash -s -- --skip-inir
```

This avoids overwriting niri configs and iNiR runtime state.

### Asahi Fedora (Apple Silicon MacBook)

Running the same command on an Asahi Fedora install automatically:
- Detects aarch64 architecture (or `VARIANT_ID=asahi-remix`)
- Skips x86-only packages (NVIDIA, Intel/AMD firmware, GRUB, etc.)
- Installs Asahi-specific packages (kernel-asahi, asahi-firmware, apple-bce, etc.)
- Configures HiDPI output scaling for Retina displays (uncomment in `config.d/95-hidpi.kdl`)
- Provides Mac keyboard layout guidance

### Manual Setup Options

| Flag | Description |
|------|-------------|
| `--skip-packages` | Skip DNF package installation |
| `--skip-flatpak`  | Skip Flatpak installation |
| `--skip-snap`     | Skip Snap installation |
| `--skip-inir`     | Skip iNiR shell setup (use when iNiR is already installed) |
| `--skip-asahi`    | Skip Asahi-specific setup (auto-detected) |

```bash
# Skip optional parts on any platform
curl -fsSL https://raw.githubusercontent.com/leeprky/dotfiles/main/setup.sh | bash -s -- --skip-flatpak --skip-snap
```

## What It Does

1. Detects OS (Fedora/Nobara/Asahi) and architecture (x86_64/aarch64)
2. Installs 400+ RPM packages via DNF (auto-filtered per platform)
3. Installs Asahi-specific packages on aarch64 (kernel, firmware, drivers)
4. Installs Flatpak apps (Zen Browser, VSCodium, OBS, Proton VPN/Mail/Pass, etc.)
5. Installs Snap packages
6. Clones this repo and symlinks configs with GNU Stow (skips niri — managed by iNiR)
7. Sets system locale (`en_GB.utf8`), keymap (`gb`), timezone (`Europe/London`), hostname
8. Installs user tools: eza (aarch64 binary), uv, starship, spicetify
9. Sets up the iNiR shell (cloned from [snowarch/inir](https://github.com/snowarch/inir)) — use `--skip-inir` to leave iNiR untouched
10. Installs custom fonts and updates font cache
11. Sets fish as the default shell
12. Enables systemd services

## Structure

```
.
├── setup.sh              # Main bootstrap script (curl-friendly, auto-detects arch)
├── pack.sh               # Snapshot current system configs into repo
├── packages/
│   ├── dnf-packages.txt              # DNF package manifest (cross-platform)
│   ├── dnf-packages-asahi-additions.txt  # Asahi-specific DNF packages (aarch64 only)
│   ├── flatpak-packages.txt
│   └── snap-packages.txt
├── configs/
│   └── home/             # Mirrors $HOME structure, applied via stow
│       ├── .bashrc
│       ├── .zshrc
│       ├── .config/
│       │   ├── fish/
│       │   ├── starship.toml
│       │   ├── kitty/
│       │   ├── foot/
│       │   ├── gtk-3.0/
│       │   └── ...
│       └── .local/
│           ├── bin/      # Custom scripts (inir launcher, etc.)
│           └── share/fonts/
│
├── packages/
│   ├── inir-overlays/    # Patches applied on top of upstream iNiR
│   │   ├── defaults/niri/config.d/  # Custom niri window rules & animations
│   │   ├── modules/                 # QML overrides (Firefox toggle, etc.)
│   │   └── scripts/colors/         # Firefox theme generator
│   └── inir-state/       # Snapshot of iNiR CLI config & theme metadata
```

## Updating Your Snapshot

On your current system, run pack.sh to re-capture everything:

```bash
cd ~/dotfiles
./pack.sh --apply    # copies current configs into repo
git add -A
git commit -m "Update config snapshot $(date +%Y-%m-%d)"
git push
```

Then on a new system, `curl ... | bash` will pull the latest.

## Post-Install Steps

After reboot on any platform:
1. Run `spicetify apply` to apply the Spotify theme
2. Run `niri` to start the compositor (or select Niri from your display manager)
3. Run `inir cheatsheet` to see all keybindings

**Asahi Fedora specific:**
- Verify GPU acceleration: `glxinfo -B` or `vulkaninfo`
- Check secure boot: `asahi-sbctl status`
- Mac keyboard: Fn row maps to F1-F12 by default; see `/usr/local/share/quickshell/inir/defaults/niri/config.d/10-input-and-cursor.kdl` for Option/Command swap options
- HiDPI: enable output scale in the iNiR display settings or in `~/.config/niri/config.d/95-hidpi.kdl`

## Notes

**niri configs** are managed by iNiR, not by the stow package. To customize keybinds, startup processes, or window rules, edit the files in `~/.config/niri/config.d/` directly — they won't be overwritten by the bootstrap script.

**iNiR overlays** (in `packages/inir-overlays/`) are applied on top of the upstream iNiR repo when `setup_inir` runs. If you install iNiR separately and use `--skip-inir`, apply them manually:
```bash
rsync -a ~/.dotfiles/packages/inir-overlays/ ~/.config/quickshell/inir/
```
