#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# iNiR Dotfiles Bootstrap — setup.sh
# ─────────────────────────────────────────────────────────────────────────────
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/leeprky/dotfiles/main/setup.sh | bash
#
# Or after cloning:
#   ./setup.sh
#
# What it does:
#   1. Detects OS (Fedora / Nobara / RHEL)
#   2. Installs RPM packages via DNF (full 400+ package list)
#   3. Installs Flatpak apps (Zen, VSCodium, OBS, Proton, etc.)
#   4. Installs Snap packages
#   5. Clones/updates this dotfiles repo
#   6. Symlinks all configs with GNU Stow
#   7. Sets system locale/timezone/hostname
#   8. Installs user tools (eza, uv, starship, spicetify)
#   9. Sets up iNiR shell (clones + installs from source)
#  10. Installs custom fonts and refreshes font cache
#  11. Configures fish as default shell
#  12. Enables systemd services
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════

GITHUB_USER="leeprky"
REPO_NAME="dotfiles"
REPO_BRANCH="main"
REPO_URL="https://github.com/$GITHUB_USER/$REPO_NAME.git"
INIR_REPO_URL="https://github.com/snowarch/inir.git"

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
INIR_DIR="${INIR_DIR:-$HOME/.config/quickshell/inir}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"

# Architecture — set automatically in detect_os
ARCH="$(uname -m)"

# Hostname to set (tuned per-platform in detect_os)
HOSTNAME=""
TIMEZONE="Europe/London"
LOCALE="en_GB.utf8"
KEYMAP="gb"

# Groups to add the user to
USER_GROUPS="wheel video users input autologin i2c"

# Systemd services to enable (script checks which exist)
SYSTEM_SERVICES=(
    bluetooth chronyd firewalld fwupd
    irqbalance smartmontools systemd-resolved
    NetworkManager
)

USER_SERVICES=(
    pipewire pipewire-pulse wireplumber
    inir niri
)

# ═══════════════════════════════════════════════════════════════════════════
# HELPERS
# ═══════════════════════════════════════════════════════════════════════════

if [[ -t 1 ]]; then
    BOLD="\033[1m"
    DIM="\033[2m"
    RED="\033[1;31m"
    GREEN="\033[1;32m"
    YELLOW="\033[1;33m"
    BLUE="\033[1;34m"
    CYAN="\033[1;36m"
    NC="\033[0m"
else
    BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; CYAN=""; NC=""
fi

info()  { printf "${BLUE}⋅${NC} %s\n" "$*"; }
ok()    { printf "${GREEN}✓${NC} %s\n" "$*"; }
warn()  { printf "${YELLOW}!${NC} %s\n" "$*"; }
fail()  { printf "${RED}✗${NC} %s\n" "$*"; exit 1; }
skip()  { printf "${DIM}−${NC} %s\n" "$*"; }
header(){ printf "\n${BOLD}${CYAN}═══ %s ═══${NC}\n" "$*"; }

run_sudo() {
    if [[ "${EUID:-0}" -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════
# SYSTEM DETECTION
# ═══════════════════════════════════════════════════════════════════════════

detect_os() {
    header "Detecting system"

    ARCH="$(uname -m)"

    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_ID="$ID"
        OS_VERSION="$VERSION_ID"
        OS_NAME="$PRETTY_NAME"
    else
        OS_ID="unknown"
        OS_VERSION="unknown"
        OS_NAME="Unknown Linux"
    fi

    info "OS: $OS_NAME"
    info "Arch: $ARCH"

    case "$OS_ID" in
        nobara|fedora|fedora-asahi-remix|rhel|centos)
            PKG_MANAGER="dnf"
            info "Package manager: DNF"
            ;;
        *)
            fail "Unsupported OS: $OS_ID (this script targets Fedora/Nobara/RHEL)"
            ;;
    esac

    IS_NOBARA=0
    IS_ASAHI=0
    if [[ "$OS_ID" == "nobara" ]]; then
        IS_NOBARA=1
        info "Nobara Linux detected — including Nobara-specific packages"
    fi
    if [[ "$ARCH" == "aarch64" || "${VARIANT_ID:-}" == "asahi-remix" ]]; then
        IS_ASAHI=1
        info "Apple Silicon (aarch64) detected — applying Asahi Fedora configuration"
    fi

    # Set platform-specific defaults
    if [[ -z "$HOSTNAME" ]]; then
        if [[ "$IS_NOBARA" -eq 1 ]]; then
            HOSTNAME="NobaraOS"
        elif [[ "$IS_ASAHI" -eq 1 ]]; then
            HOSTNAME="MacBook"
        else
            HOSTNAME="fedora"
        fi
    fi

    if [[ "${EUID:-0}" -ne 0 ]]; then
        if command -v sudo &>/dev/null; then
            info "Sudo available — will elevate when needed"
        else
            fail "sudo is required but not available"
        fi
    fi

    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════
# PACKAGE INSTALLATION
# ═══════════════════════════════════════════════════════════════════════════

install_dnf_packages() {
    header "Installing DNF packages"

    local pkg_list="$DOTFILES_DIR/packages/dnf-packages.txt"

    if [[ ! -f "$pkg_list" ]]; then
        warn "Package list not found at $pkg_list — skipping DNF install"
        return
    fi

    # x86-only packages to skip on aarch64
    local x86_only=(
        "mcelog" "microcode_ctl"
        "ryzenadj" "lact"
        "cuda-devel"
        "dkms-nvidia"
    )

    local pkgs=()
    while IFS= read -r pkg; do
        [[ -z "$pkg" || "$pkg" =~ ^# ]] && continue

        # Skip Nobara-specific on non-Nobara
        if [[ "$IS_NOBARA" -eq 0 ]]; then
            [[ "$pkg" =~ ^nobara- ]] && continue
            [[ "$pkg" =~ ^nvidia- ]] && continue
        fi

        # Skip x86-only packages on aarch64 (Asahi)
        if [[ "$IS_ASAHI" -eq 1 ]]; then
            local skip=0
            for x in "${x86_only[@]}"; do
                [[ "$pkg" == "$x" ]] && { skip=1; break; }
            done
            # Skip x86 firmware on Apple Silicon
            [[ "$pkg" =~ ^amd- ]] && skip=1
            [[ "$pkg" =~ ^intel-.*firmware ]] && skip=1
            # x86-specific bootloader packages (aarch64 uses grub2-efi-aa64)
            [[ "$pkg" == "grub2-efi-x64"* ]] && skip=1
            [[ "$pkg" == "grub2-efi-ia32"* ]] && skip=1
            [[ "$pkg" == "grub2-pc"* ]] && skip=1
            [[ "$pkg" == "shim-x64" ]] && skip=1
            [[ "$pkg" == "shim-ia32" ]] && skip=1
            [[ "$skip" -eq 1 ]] && continue
        fi

        pkgs+=("$pkg")
    done < "$pkg_list"

    info "Installing ${#pkgs[@]} packages (this will take a while)..."

    run_sudo dnf install -y --skip-broken "${pkgs[@]}" 2>&1 | tail -5 || {
        warn "Some DNF packages failed to install (see above)"
    }

    ok "DNF packages installed"
}

install_asahi_packages() {
    header "Installing Asahi Fedora packages"

    if [[ "$IS_ASAHI" -eq 0 ]]; then
        skip "Not an Asahi system — skipping"
        return
    fi

    # Ensure Asahi repos are set up
    info "Ensuring Asahi repositories are configured..."
    if ! dnf repolist 2>/dev/null | grep -q asahi; then
        run_sudo dnf install -y asahi-repos 2>&1 | tail -3 || warn "Could not install asahi-repos"
    fi

    # Update all repos now that asahi-repos is available
    run_sudo dnf update -y --refresh 2>&1 | tail -3 || true

    # Install Asahi-specific packages from additions file
    local add_list="$DOTFILES_DIR/packages/dnf-packages-asahi-additions.txt"
    if [[ -f "$add_list" ]]; then
        local add_pkgs=()
        while IFS= read -r pkg; do
            [[ -z "$pkg" || "$pkg" =~ ^# ]] && continue
            add_pkgs+=("$pkg")
        done < "$add_list"

        if [[ ${#add_pkgs[@]} -gt 0 ]]; then
            info "Installing ${#add_pkgs[@]} Asahi-specific packages..."
            run_sudo dnf install -y --skip-broken "${add_pkgs[@]}" 2>&1 | tail -5 || {
                warn "Some Asahi packages failed to install (see above)"
            }
        fi
    else
        warn "Asahi additions list not found at $add_list"
    fi

    # Install Asahi kernel if not already present
    if ! rpm -q kernel-asahi &>/dev/null 2>&1; then
        info "Installing Asahi kernel..."
        run_sudo dnf install -y kernel-asahi 2>&1 | tail -3 || warn "Could not install kernel-asahi"
    fi

    ok "Asahi packages installed"
}

install_flatpak_packages() {
    header "Installing Flatpak applications"

    local pkg_list="$DOTFILES_DIR/packages/flatpak-packages.txt"

    if [[ ! -f "$pkg_list" ]]; then
        warn "Flatpak list not found — skipping"
        return
    fi

    # Ensure Flathub is added
    run_sudo flatpak remote-add --if-not-exists flathub \
        https://flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true

    while IFS= read -r app; do
        [[ -z "$app" || "$app" =~ ^# ]] && continue
        info "Installing $app..."
        run_sudo flatpak install -y flathub "$app" 2>&1 | tail -1 || warn "Failed to install $app"
    done < "$pkg_list"

    ok "Flatpak applications installed"
}

install_snap_packages() {
    header "Installing Snap packages"

    local pkg_list="$DOTFILES_DIR/packages/snap-packages.txt"

    if [[ ! -f "$pkg_list" ]]; then
        warn "Snap list not found — skipping"
        return
    fi

    # Ensure snapd is running
    run_sudo systemctl enable --now snapd.socket 2>/dev/null || true
    run_sudo systemctl enable --now snapd.service 2>/dev/null || true

    # Wait for snapd to be ready
    sleep 2

    while IFS= read -r pkg; do
        [[ -z "$pkg" || "$pkg" =~ ^# ]] && continue
        info "Installing snap: $pkg..."
        run_sudo snap install "$pkg" 2>&1 | tail -1 || warn "Failed to install snap $pkg"
    done < "$pkg_list"

    ok "Snap packages installed"
}

# ═══════════════════════════════════════════════════════════════════════════
# DOTFILES REPO
# ═══════════════════════════════════════════════════════════════════════════

clone_dotfiles() {
    header "Cloning dotfiles repository"

    if [[ -d "$DOTFILES_DIR/.git" ]]; then
        info "Repository already exists at $DOTFILES_DIR — updating..."
        git -C "$DOTFILES_DIR" pull --ff-only origin "$REPO_BRANCH" 2>&1 | tail -1 || warn "Could not update dotfiles — continuing with local copy"
    else
        info "Cloning $REPO_URL -> $DOTFILES_DIR"
        git clone --depth 1 -b "$REPO_BRANCH" "$REPO_URL" "$DOTFILES_DIR" || fail "Could not clone dotfiles — check network and URL"
    fi

    ok "Dotfiles repository ready at $DOTFILES_DIR"
}

stow_configs() {
    header "Symlinking configs with GNU Stow"

    local stow_dir="$DOTFILES_DIR/configs"

    if [[ ! -d "$stow_dir/home" ]]; then
        warn "No configs directory found — skipping symlinks"
        return
    fi

    if ! command -v stow &>/dev/null; then
        warn "GNU Stow not installed — installing..."
        run_sudo dnf install -y stow 2>&1 | tail -3 || {
            warn "Could not install stow — skipping symlinks"
            return
        }
    fi

    cd "$stow_dir"

    # Use --no-folding to create individual symlinks (not dir symlinks).
    # Do NOT use --adopt — that moves existing files into the stow tree
    # and can overwrite committed dotfiles with local versions.
    # Instead, --restow will unlink/re-link stow-managed files only and
    # leave pre-existing files (like niri configs) untouched.
    if [[ -d "home" ]]; then
        if stow --verbose=1 --target="$HOME" --no-folding --restow home 2>&1; then
            ok "Home configs linked"
        else
            warn "Stow encountered errors — check for conflicts above"
        fi
    fi

    cd "$HOME"
}

# ═══════════════════════════════════════════════════════════════════════════
# SYSTEM CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════

setup_system() {
    header "Configuring system settings"

    # Hostname
    local current_hostname
    current_hostname="$(hostname 2>/dev/null || echo "")"
    if [[ "$current_hostname" != "$HOSTNAME" ]]; then
        info "Setting hostname to $HOSTNAME..."
        run_sudo hostnamectl set-hostname "$HOSTNAME"
    else
        skip "Hostname already set to $HOSTNAME"
    fi

    # Locale
    info "Setting locale to $LOCALE..."
    run_sudo localectl set-locale "LANG=$LOCALE" 2>/dev/null || warn "Could not set locale"

    # Keymap
    info "Setting keymap to $KEYMAP..."
    run_sudo localectl set-keymap "$KEYMAP" 2>/dev/null || true

    # Timezone
    info "Setting timezone to $TIMEZONE..."
    run_sudo timedatectl set-timezone "$TIMEZONE" 2>/dev/null || true

    # User groups
    local current_groups
    current_groups="$(groups)"
    for group in $USER_GROUPS; do
        if ! echo "$current_groups" | grep -qw "$group"; then
            info "Adding user to group $group..."
            run_sudo usermod -aG "$group" "$USER" 2>/dev/null || true
        fi
    done

    ok "System settings applied"
}

setup_systemd() {
    header "Enabling systemd services"

    info "Enabling system services..."
    for svc in "${SYSTEM_SERVICES[@]}"; do
        if systemctl list-unit-files "$svc" &>/dev/null; then
            run_sudo systemctl enable --now "$svc" 2>/dev/null && ok "  $svc" || warn "  $svc failed"
        else
            skip "  $svc not found"
        fi
    done

    info "Enabling user services..."
    for svc in "${USER_SERVICES[@]}"; do
        if systemctl --user list-unit-files "$svc" &>/dev/null 2>&1; then
            systemctl --user enable --now "$svc" 2>/dev/null && ok "  $svc" || warn "  $svc failed"
        else
            skip "  $svc not found"
        fi
    done
}

# ═══════════════════════════════════════════════════════════════════════════
# USER TOOLS
# ═══════════════════════════════════════════════════════════════════════════

install_user_tools() {
    header "Installing user-level tools"

    # eza (modern ls) — static binary
    if ! command -v eza &>/dev/null; then
        info "Installing eza..."
        local eza_arch
        if [[ "$ARCH" == "aarch64" ]]; then
            eza_arch="aarch64-unknown-linux-gnu"
        else
            eza_arch="x86_64-unknown-linux-gnu"
        fi
        local eza_url
        eza_url="$(curl -fsSL https://api.github.com/repos/eza-community/eza/releases/latest \
            | grep browser_download_url | grep "$eza_arch" \
            | grep -v tar.gz | head -1 | cut -d'"' -f4)" 2>/dev/null || true
        if [[ -n "$eza_url" ]]; then
            curl -fsSL "$eza_url" -o ~/.local/bin/eza 2>/dev/null && \
                chmod +x ~/.local/bin/eza && ok "eza installed" || warn "eza download failed"
        fi
    else
        skip "eza already installed"
    fi

    # uv (Python package manager)
    if ! command -v uv &>/dev/null; then
        info "Installing uv..."
        curl -fsSL https://astral.sh/uv/install.sh | bash 2>/dev/null && ok "uv installed" || warn "uv install failed"
    else
        skip "uv already installed"
    fi

    # Starship prompt
    if ! command -v starship &>/dev/null; then
        info "Installing starship..."
        curl -fsSL https://starship.rs/install.sh | sh -s -- -y 2>/dev/null && ok "starship installed" || warn "starship install failed"
    else
        skip "starship already installed"
    fi

    # Spicetify CLI
    if ! command -v spicetify &>/dev/null; then
        info "Installing spicetify..."
        curl -fsSL https://raw.githubusercontent.com/spicetify/cli/main/install.sh | sh 2>/dev/null && ok "spicetify installed" || warn "spicetify install failed"
    else
        skip "spicetify already installed"
    fi

    # Ensure ~/.local/bin is in PATH
    mkdir -p ~/.local/bin
}

# ═══════════════════════════════════════════════════════════════════════════
# iNiR SHELL
# ═══════════════════════════════════════════════════════════════════════════

setup_inir() {
    header "Setting up iNiR shell"

    if [[ -d "$INIR_DIR/.git" ]]; then
        info "iNiR already cloned — updating..."
        git -C "$INIR_DIR" pull --ff-only 2>&1 | tail -1 || warn "Could not update iNiR — continuing with local copy"
    else
        mkdir -p "$(dirname "$INIR_DIR")"
        info "Cloning iNiR from $INIR_REPO_URL..."
        git clone --depth 1 "$INIR_REPO_URL" "$INIR_DIR" || fail "Could not clone iNiR — check network"
    fi

    if [[ -f "$INIR_DIR/Makefile" ]]; then
        info "Building iNiR (this may take a moment)..."
        make -C "$INIR_DIR" install 2>&1 | tail -3 || warn "iNiR build incomplete — see docs"
    fi

    # Create inir launcher if not present
    if [[ ! -f ~/.local/bin/inir ]]; then
        if [[ -f "$INIR_DIR/scripts/inir" ]]; then
            cp "$INIR_DIR/scripts/inir" ~/.local/bin/inir
            chmod +x ~/.local/bin/inir
            ok "inir launcher installed"
        fi
    fi

    ok "iNiR shell ready"
}

apply_inir_overlays() {
    header "Applying iNiR local customizations"

    local overlay_dir="$DOTFILES_DIR/packages/inir-overlays"

    if [[ ! -d "$overlay_dir" ]]; then
        skip "No iNiR overlays found at $overlay_dir"
        return
    fi

    if [[ ! -d "$INIR_DIR" ]]; then
        warn "iNiR is not cloned yet — skipping overlays"
        return
    fi

    local count=0
    while IFS= read -r -d '' f; do
        local rel="${f#$overlay_dir/}"
        local dst="$INIR_DIR/$rel"
        mkdir -p "$(dirname "$dst")"
        cp "$f" "$dst"
        count=$((count + 1))
    done < <(find "$overlay_dir" -type f -print0)

    if [[ "$count" -gt 0 ]]; then
        ok "Applied $count iNiR overlay files"
    else
        skip "No overlay files to apply"
    fi
}

restore_inir_state() {
    header "Restoring iNiR state and wallpapers"

    local state_dir="$DOTFILES_DIR/packages/inir-state"
    local wall_dir="$DOTFILES_DIR/packages/wallpapers"
    local old_home="/home/leeparky04"

    # Wallpapers
    if [[ -d "$wall_dir" && -n "$(ls -A "$wall_dir" 2>/dev/null)" ]]; then
        mkdir -p "$HOME/Pictures/Wallpapers"
        cp "$wall_dir"/* "$HOME/Pictures/Wallpapers/"
        ok "Restored $(ls "$wall_dir" | wc -l) wallpapers"
    else
        skip "No wallpapers to restore"
    fi

    # iNiR runtime config (config.json has hardcoded paths — fix them)
    if [[ -f "$state_dir/config.json" ]]; then
        mkdir -p "$HOME/.config/inir"
        sed "s|$old_home|$HOME|g" "$state_dir/config.json" > "$HOME/.config/inir/config.json"
        ok "Restored iNiR CLI config"
    else
        skip "No iNiR config to restore"
    fi

    # Theme metadata (has hardcoded paths too)
    if [[ -f "$state_dir/theme-meta.json" ]]; then
        mkdir -p "$HOME/.local/state/quickshell/user/generated"
        sed "s|$old_home|$HOME|g" "$state_dir/theme-meta.json" > "$HOME/.local/state/quickshell/user/generated/theme-meta.json"
        ok "Restored theme metadata"
    fi

    # Active wallpaper path
    if [[ -f "$state_dir/wallpaper-path.txt" ]]; then
        mkdir -p "$HOME/.local/state/quickshell/user/generated/wallpaper"
        sed "s|$old_home|$HOME|g" "$state_dir/wallpaper-path.txt" > "$HOME/.local/state/quickshell/user/generated/wallpaper/path.txt"
        ok "Restored wallpaper path"
    fi

    # Other runtime state (small files)
    for f in todo.json notepad-tabs.json; do
        if [[ -f "$state_dir/$f" ]]; then
            mkdir -p "$HOME/.local/state/quickshell/user"
            cp "$state_dir/$f" "$HOME/.local/state/quickshell/user/$f"
        fi
    done

    ok "iNiR state restored"
}

# ═══════════════════════════════════════════════════════════════════════════
# FONTS
# ═══════════════════════════════════════════════════════════════════════════

setup_fonts() {
    header "Installing custom fonts"

    local font_src="$DOTFILES_DIR/configs/home/.local/share/fonts"
    local font_dst="$HOME/.local/share/fonts"

    if [[ ! -d "$font_src" ]]; then
        skip "No custom fonts to install"
        return
    fi

    shopt -s nullglob
    local font_files=("$font_src"/*.ttf "$font_src"/*.otf "$font_src"/*.woff2)
    shopt -u nullglob

    if [[ ${#font_files[@]} -eq 0 ]]; then
        skip "No font files found (only non-font files in directory)"
    else
        mkdir -p "$font_dst"
        cp "${font_files[@]}" "$font_dst/"
        info "Fonts copied — updating font cache..."
        fc-cache -f "$font_dst" 2>/dev/null || true
        ok "Font cache updated"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════
# SHELL SETUP
# ═══════════════════════════════════════════════════════════════════════════

setup_shell() {
    header "Configuring shell"

    # Set fish as default shell
    local fish_path
    fish_path="$(command -v fish 2>/dev/null || true)"
    if [[ -n "$fish_path" ]]; then
        local current_shell
        current_shell="$(getent passwd "$USER" 2>/dev/null | cut -d: -f7 || echo "$SHELL")"
        if [[ "$current_shell" != "$fish_path" ]]; then
            info "Setting fish as default shell..."
            if chsh -s "$fish_path" 2>/dev/null; then
                ok "Default shell set to fish"
            elif run_sudo chsh -s "$fish_path" "$USER" 2>/dev/null; then
                ok "Default shell set to fish"
            else
                warn "Could not change shell — do it manually: chsh -s $fish_path"
            fi
        else
            skip "fish is already the default shell"
        fi
    else
        warn "fish not found — install it with: sudo dnf install fish"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════
# CLEANUP
# ═══════════════════════════════════════════════════════════════════════════

cleanup() {
    header "Finalizing"

    info "Refreshing desktop database..."
    command -v update-desktop-database &>/dev/null && \
        update-desktop-database ~/.local/share/applications 2>/dev/null || true

    info "Updating mime database..."
    command -v update-mime-database &>/dev/null && \
        update-mime-database ~/.local/share/mime 2>/dev/null || true

    info "Reloading systemd user daemon..."
    systemctl --user daemon-reload 2>/dev/null || true

    ok "Setup complete! Restart or log out for all changes to take effect."
    echo ""
    info "Next steps after reboot:"
    echo "  1. Run 'spicetify apply' to apply the Spotify theme"
    echo "  2. Run 'niri' to start the compositor (or select Niri from your display manager)"
    echo "  3. Run 'inir cheatsheet' to see all keybindings"
    if [[ "$IS_ASAHI" -eq 1 ]]; then
        echo ""
        echo "  Asahi Fedora notes:"
        echo "  - GPU acceleration: verify with 'glxinfo -B' or 'vulkaninfo'"
        echo "  - HiDPI: niri output scale is set in config.d/95-hidpi.kdl"
        echo "  - Mac keyboard: Fn row keys are mapped as F1-F12 by default"
        echo "  - T2/BridgeOS: run 'asahi-sbctl status' to check secure boot"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════

main() {
    echo ""
    printf "${BOLD}${CYAN}"
    echo "  ╔══════════════════════════════════════════╗"
    echo "  ║       iNiR Dotfiles Bootstrap            ║"
    echo "  ╚══════════════════════════════════════════╝"
    printf "${NC}\n"

    # Parse args
    SKIP_PACKAGES=0
    SKIP_FLATPAK=0
    SKIP_SNAP=0
    SKIP_INIR=0
    SKIP_ASAHI=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --skip-packages) SKIP_PACKAGES=1 ;;
            --skip-flatpak)  SKIP_FLATPAK=1 ;;
            --skip-snap)     SKIP_SNAP=1 ;;
            --skip-inir)     SKIP_INIR=1 ;;
            --skip-asahi)    SKIP_ASAHI=1 ;;
            --help|-h)
                echo "Usage: curl -fsSL https://raw.githubusercontent.com/$GITHUB_USER/$REPO_NAME/$REPO_BRANCH/setup.sh | bash"
                echo ""
                echo "Options (set via env vars or flags):"
                echo "  --skip-packages   Skip DNF package installation"
                echo "  --skip-flatpak    Skip Flatpak installation"
                echo "  --skip-snap       Skip Snap installation"
                echo "  --skip-inir       Skip iNiR shell setup"
                echo "  --skip-asahi      Skip Asahi-specific setup"
                exit 0
                ;;
            *)
                warn "Unknown option: $1"
                ;;
        esac
        shift
    done

    detect_os

    # Make sure ~/.local/bin exists
    mkdir -p ~/.local/bin

    # Ensure git is available (needed to clone the repo)
    if ! command -v git &>/dev/null; then
        info "Git not found — installing..."
        run_sudo dnf install -y git 2>&1 | tail -3
    fi

    # Clone/update dotfiles first (so we have package lists and configs)
    clone_dotfiles

    # Install packages
    [[ "$SKIP_PACKAGES" -eq 0 ]] && install_dnf_packages
    [[ "$SKIP_ASAHI" -eq 0 ]] && install_asahi_packages
    [[ "$SKIP_FLATPAK" -eq 0 ]] && install_flatpak_packages
    [[ "$SKIP_SNAP" -eq 0 ]] && install_snap_packages

    # Install user tools
    install_user_tools

    # iNiR (must build before systemd — inir needs its service file)
    [[ "$SKIP_INIR" -eq 0 ]] && setup_inir
    [[ "$SKIP_INIR" -eq 0 ]] && apply_inir_overlays
    [[ "$SKIP_INIR" -eq 0 ]] && restore_inir_state

    # System configuration
    setup_system
    setup_systemd

    # Configs and dotfiles
    stow_configs
    setup_fonts

    # Shell
    setup_shell

    # Done
    cleanup
}

main "$@"
