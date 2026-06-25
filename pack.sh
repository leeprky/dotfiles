#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# pack.sh — Snapshot current system configs into ~/dotfiles repo structure
# ─────────────────────────────────────────────────────────────────────────────
# Run this on your CURRENT system to extract all configs, package lists,
# fonts, and scripts into the ~/dotfiles directory. Then commit and push.
#
# Usage:
#   ./pack.sh              # interactive (dry-run first)
#   ./pack.sh --apply      # actually copy files
#   ./pack.sh --help       # show help
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── helpers ──────────────────────────────────────────────────────────────────
info()  { printf '\033[1;34m[⋅]\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m[✓]\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
skip()  { printf '\033[1;30m[–]\033[0m %s\n' "$*"; }
dry()   { [[ "${DRY_RUN:-0}" == "1" ]]; }

run() {
    if dry; then echo "    would run: $*"; else "$@"; fi
}

copy() {
    local src="$1" dst="$2"
    if dry; then
        echo "    would copy: $src -> $dst"
    else
        # Skip if src is already tracked in our dotfiles repo (stow symlink active)
        if [[ -L "$src" ]]; then
            local link_target
            link_target="$(readlink "$src")"
            case "$link_target" in
                */.dotfiles/configs/home/*|*/dotfiles/configs/home/*)
                    return 0 ;;
            esac
        fi
        # Also skip if src and dst would resolve to the same file
        if [[ -e "$dst" ]] && [[ "$(readlink -f "$src")" == "$(readlink -f "$dst")" ]]; then
            return 0
        fi
        mkdir -p "$(dirname "$dst")"
        cp -rL --preserve=mode,timestamps "$src" "$dst"
    fi
}

# ── check prerequisites ──────────────────────────────────────────────────────
check_prereqs() {
    local missing=0
    for cmd in rsync stow; do
        if ! command -v "$cmd" &>/dev/null; then
            warn "$cmd is required. Install with: sudo dnf install $cmd"
            missing=$((missing + 1))
        fi
    done
    return $missing
}

# ── package lists ────────────────────────────────────────────────────────────
pack_package_lists() {
    local dir="$DOTFILES_DIR/packages"
    mkdir -p "$dir"

    info "Exporting DNF user-installed packages..."
    if command -v dnf &>/dev/null; then
        dnf repoquery --userinstalled 2>/dev/null | sort > "$dir/dnf-packages.txt"
        ok "Saved $(wc -l < "$dir/dnf-packages.txt") DNF packages"
    else
        skip "DNF not available"
    fi

    info "Exporting Flatpak apps..."
    if command -v flatpak &>/dev/null; then
        flatpak list --app --columns=app 2>/dev/null | sort > "$dir/flatpak-packages.txt"
        ok "Saved $(wc -l < "$dir/flatpak-packages.txt") Flatpak apps"
    else
        skip "Flatpak not available"
    fi

    info "Exporting Snap packages..."
    if command -v snap &>/dev/null; then
        snap list 2>/dev/null | awk 'NR>1 {print $1}' | sort > "$dir/snap-packages.txt"
        ok "Saved $(wc -l < "$dir/snap-packages.txt") Snap packages"
    else
        skip "Snap not available"
    fi

    info "Exporting Cargo installed tools (with 10s timeout)..."
    if command -v cargo &>/dev/null; then
        timeout 10 cargo install --list 2>/dev/null | grep -E '^[a-zA-Z]' | awk '{print $1}' | sort > "$dir/cargo-packages.txt" || true
        ok "Saved $(wc -l < "$dir/cargo-packages.txt") Cargo packages"
    else
        skip "Cargo not available"
    fi

    info "Exporting npm global packages..."
    if command -v npm &>/dev/null; then
        npm list -g --depth=0 2>/dev/null | grep -v '^/' | awk 'NR>1 {print $2}' | cut -d@ -f1 | sort > "$dir/npm-packages.txt" || true
        ok "Saved $(wc -l < "$dir/npm-packages.txt") npm global packages"
    else
        skip "npm not available"
    fi

    # Export Asahi-specific packages if on aarch64
    if [[ "$(uname -m)" == "aarch64" ]]; then
        info "Exporting Asahi-specific DNF packages..."
        if command -v dnf &>/dev/null; then
            # Packages from asahi repos
            dnf repoquery --userinstalled 2>/dev/null | grep -i asahi | sort > "$dir/dnf-packages-asahi-additions.txt" || true
            ok "Saved Asahi-specific packages"
        fi
    fi
}

# ── dotfiles ─────────────────────────────────────────────────────────────────
pack_dotfiles() {
    local home="$DOTFILES_DIR/configs/home"

    info "Copying top-level dotfiles..."
    for f in .bashrc .bash_profile .profile .zshrc .zshenv .gitconfig .gitignore .bash_logout .gtkrc-2.0 .gtkrc-2.0-kde4; do
        [[ -f "$HOME/$f" ]] && copy "$HOME/$f" "$home/$f"
    done

    info "Copying .config/ directories and files..."
    local config_dirs=(
        alacritty btop cava dunst easyeffects fish foot fuzzel
        gtk-3.0 gtk-4.0 gtkrc gtkrc-2.0 kitty Kvantum matugen mpv niri
        spicetify starship.toml user-dirs.dirs wireplumber wlsunset
        qt5ct qt6ct
    )
    for dir in "${config_dirs[@]}"; do
        local src="$HOME/.config/$dir"
        [[ -e "$src" ]] && copy "$src" "$home/.config/$dir"
    done

    info "Copying .local/share/fonts/..."
    if [[ -d "$HOME/.local/share/fonts" ]]; then
        shopt -s nullglob
        for f in "$HOME/.local/share/fonts/"*; do
            local base
            base="$(basename "$f")"
            copy "$f" "$home/.local/share/fonts/$base"
        done
        shopt -u nullglob
    fi

    info "Copying .local/bin/ scripts..."
    if [[ -d "$HOME/.local/bin" ]]; then
        shopt -s nullglob
        for f in "$HOME/.local/bin/"*; do
            local base
            base="$(basename "$f")"
            copy "$f" "$home/.local/bin/$base"
        done
        shopt -u nullglob
    fi

    info "Copying SSH config (public keys only)..."
    if [[ -f "$HOME/.ssh/config" ]]; then
        copy "$HOME/.ssh/config" "$home/.ssh/config"
    fi
    if [[ -f "$HOME/.ssh/authorized_keys" ]]; then
        copy "$HOME/.ssh/authorized_keys" "$home/.ssh/authorized_keys"
    fi
    for f in "$HOME/.ssh/"*.pub; do
        [[ -f "$f" ]] && copy "$f" "$home/.ssh/"
    done
}

# ── iNiR overlays (modified files in the cloned repo) ────────────────────────
pack_inir_overlays() {
    local overlay_dir="$DOTFILES_DIR/packages/inir-overlays"

    if [[ ! -d "$HOME/.config/quickshell/inir/.git" ]]; then
        skip "iNiR repo not found — skipping overlays"
        return
    fi

    info "Capturing local iNiR modifications..."
    rm -rf "$overlay_dir"
    mkdir -p "$overlay_dir"

    local count=0
    while IFS= read -r -d '' f; do
        local rel="${f#$HOME/.config/quickshell/inir/}"
        local dst="$overlay_dir/$rel"
        mkdir -p "$(dirname "$dst")"
        cp "$f" "$dst"
        count=$((count + 1))
    done < <(cd "$HOME/.config/quickshell/inir" && {
        git diff --name-only -z
        git ls-files --others --exclude-standard -z
    })

    if [[ "$count" -gt 0 ]]; then
        ok "Captured $count modified iNiR overlay files"
    else
        skip "No local iNiR modifications found"
        rm -rf "$overlay_dir"
    fi
}

# ── iNiR state + wallpapers ──────────────────────────────────────────────────
pack_inir_state() {
    local state_dir="$DOTFILES_DIR/packages/inir-state"
    local wall_dir="$DOTFILES_DIR/packages/wallpapers"

    info "Capturing iNiR CLI config..."
    mkdir -p "$state_dir"
    if [[ -f "$HOME/.config/inir/config.json" ]]; then
        cp "$HOME/.config/inir/config.json" "$state_dir/"
        ok "Captured iNiR CLI config"
    else
        skip "No iNiR config found"
    fi

    info "Capturing theme metadata..."
    if [[ -f "$HOME/.local/state/quickshell/user/generated/theme-meta.json" ]]; then
        cp "$HOME/.local/state/quickshell/user/generated/theme-meta.json" "$state_dir/"
        ok "Captured theme metadata"
    fi

    info "Capturing active wallpaper path..."
    if [[ -f "$HOME/.local/state/quickshell/user/generated/wallpaper/path.txt" ]]; then
        cp "$HOME/.local/state/quickshell/user/generated/wallpaper/path.txt" "$state_dir/wallpaper-path.txt"
        ok "Captured wallpaper path"
    fi

    info "Capturing runtime state..."
    for f in todo.json notepad-tabs.json; do
        if [[ -f "$HOME/.local/state/quickshell/user/$f" ]]; then
            cp "$HOME/.local/state/quickshell/user/$f" "$state_dir/$f"
        fi
    done

    info "Capturing custom wallpapers..."
    if [[ -d "$HOME/Pictures/Wallpapers" ]]; then
        mkdir -p "$wall_dir"
        # Only copy wallpapers not in the upstream iNiR repo
        local upstream="$HOME/.config/quickshell/inir/assets/wallpapers"
        local count=0
        for f in "$HOME/Pictures/Wallpapers/"*; do
            local base
            base="$(basename "$f")"
            if [[ ! -f "$upstream/$base" ]]; then
                cp "$f" "$wall_dir/"
                count=$((count + 1))
            fi
        done
        if [[ "$count" -gt 0 ]]; then
            ok "Captured $count custom wallpapers"
        else
            skip "No custom wallpapers to capture"
            rmdir "$wall_dir" 2>/dev/null || true
        fi
    else
        skip "No wallpapers directory found"
    fi
}

# ── system info ──────────────────────────────────────────────────────────────
pack_system_info() {
    local dir="$DOTFILES_DIR/packages"
    mkdir -p "$dir"

    info "Saving system info..."
    cat /etc/os-release > "$dir/os-release" 2>/dev/null || true
    hostname > "$dir/hostname" 2>/dev/null || true
    localectl status > "$dir/locale.txt" 2>/dev/null || true
    timedatectl show --property=Timezone 2>/dev/null | cut -d= -f2 > "$dir/timezone.txt" || true

    info "Saving enabled systemd services..."
    systemctl list-unit-files --type=service --state=enabled --no-legend 2>/dev/null \
        | awk '{print $1}' | sort > "$dir/systemd-services.txt" || true

    info "Saving user groups..."
    groups > "$dir/user-groups.txt" 2>/dev/null || true
}

# ── main ─────────────────────────────────────────────────────────────────────
main() {
    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        cat <<EOF
Usage: ./pack.sh [--apply] [--dry-run]

Snapshots your current system configs into $DOTFILES_DIR.

Flags:
  --apply      Actually copy files (default: dry-run only)
  --dry-run    Show what would be done (default)
  --help       Show this help

Then commit and push to GitHub:
  cd $DOTFILES_DIR
  git add -A
  git commit -m "Snapshot configs $(date +%Y-%m-%d)"
  git push
EOF
        exit 0
    fi

    if [[ "${1:-}" == "--apply" ]]; then
        DRY_RUN=0
    else
        DRY_RUN=1
        warn "DRY-RUN mode — no files will be copied"
        warn "Run with --apply to actually copy files"
        echo ""
    fi

    info "Packing system configs into $DOTFILES_DIR"
    echo ""

    check_prereqs || { warn "Install missing prerequisites and retry"; exit 1; }

    pack_package_lists
    echo ""
    pack_dotfiles
    echo ""
    pack_inir_overlays
    echo ""
    pack_inir_state
    echo ""
    pack_system_info
    echo ""

    if dry; then
        ok "Dry-run complete. Run with --apply to copy files."
    else
        ok "System snapshot saved to $DOTFILES_DIR"
        info "Review, then commit and push:"
        echo "  cd $DOTFILES_DIR"
        echo "  git init"
        echo "  git add -A"
        echo '  git commit -m "Initial dotfiles snapshot"'
        echo "  git remote add origin git@github.com:leeparky04/dotfiles.git"
        echo "  git push -u origin main"
    fi
}

main "$@"
