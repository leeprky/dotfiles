#!/usr/bin/env bash
#
# apply-firefox-theme.sh — Apply MaterialFox colors to Firefox-based browsers
#
# Supports: Firefox, Zen Browser, LibreWolf, Floorp, Waterfox
#
# For each installed browser, this script:
#   1. Reads profiles.ini to find all profiles
#   2. Creates/writes chrome/userChrome.css importing the generated theme
#   3. Enables toolkit.legacyUserProfileCustomizations.stylesheets in user.js
#   4. Symlinks the generated firefox-materialfox.css into each profile's chrome/

XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
STATE_DIR="$XDG_STATE_HOME/quickshell"
MATERIALFOX_SRC="$STATE_DIR/user/generated/firefox-materialfox.css"
LOG_FILE="$STATE_DIR/user/generated/firefox_theme.log"
mkdir -p "$STATE_DIR/user/generated" 2>/dev/null
: > "$LOG_FILE" 2>/dev/null

log() { echo "[firefox] $*" >> "$LOG_FILE"; }

notify_user() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send "Firefox Theme" "$1" -a "Firefox Theme"
}

# ── Browser profile discovery ─────────────────────────────────────────────────
# Each entry: browser_name|config_dir|profiles_ini_path

BROWSER_CONFIGS=(
  "firefox|$HOME/.mozilla/firefox"
  "zen|$HOME/.zen"
  "zen|$HOME/.config/zen"
  "librewolf|$HOME/.librewolf"
  "floorp|$HOME/.floorp"
  "waterfox|$HOME/.waterfox"
)

discover_profiles() {
  local config_dir="$1"
  local profiles_ini="$config_dir/profiles.ini"
  [[ -f "$profiles_ini" ]] || return 1

  # Parse profiles.ini for [Profile*] sections with Path= and Default=1
  local current_section=""
  local current_path=""
  local is_default=0
  local profiles=()

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    if [[ "$line" =~ ^\[Profile[0-9]+\] ]]; then
      # Save previous profile
      if [[ -n "$current_path" ]]; then
        profiles+=("$current_path")
      fi
      current_path=""
      is_default=0
    elif [[ "$line" =~ ^Path= ]]; then
      current_path="${line#Path=}"
    elif [[ "$line" =~ ^Default=1 ]]; then
      is_default=1
    fi
  done < "$profiles_ini"

  # Save last profile
  if [[ -n "$current_path" ]]; then
    profiles+=("$current_path")
  fi

  for profile in "${profiles[@]}"; do
    echo "$config_dir/$profile"
  done
}

# ── Ensure userChrome.css loads the theme ────────────────────────────────────

install_theme() {
  local profile_dir="$1"
  local browser_name="$2"
  local chrome_dir="$profile_dir/chrome"
  local user_chrome="$chrome_dir/userChrome.css"
  local theme_target="$chrome_dir/firefox-materialfox.css"

  mkdir -p "$chrome_dir"

  # Copy the generated MaterialFox CSS into the profile's chrome/ dir
  if [[ -f "$MATERIALFOX_SRC" ]]; then
    cp "$MATERIALFOX_SRC" "$theme_target"
    log "$browser_name: copied theme to $theme_target"
  else
    log "$browser_name: WARNING — $MATERIALFOX_SRC not found; skipping"
    return 1
  fi

  # Create or update userChrome.css to import the theme
  local import_line='@import "firefox-materialfox.css";'
  if [[ -f "$user_chrome" ]]; then
    if grep -qF 'firefox-materialfox.css' "$user_chrome"; then
      log "$browser_name: userChrome.css already imports the theme"
    else
      echo -e "\n$import_line" >> "$user_chrome"
      log "$browser_name: appended theme import to userChrome.css"
    fi
  else
    echo "$import_line" > "$user_chrome"
    log "$browser_name: created userChrome.css with theme import"
  fi
}

enable_legacy_customizations() {
  local profile_dir="$1"
  local browser_name="$2"
  local user_js="$profile_dir/user.js"

  local pref='user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);'
  if [[ -f "$user_js" ]]; then
    if grep -qF 'toolkit.legacyUserProfileCustomizations.stylesheets' "$user_js"; then
      # Ensure it's set to true
      if grep -qF 'toolkit.legacyUserProfileCustomizations.stylesheets.*false' "$user_js"; then
        log "$browser_name: WARNING — legacy stylesheets disabled in user.js"
      else
        log "$browser_name: legacy stylesheets already enabled"
      fi
    else
      echo "$pref" >> "$user_js"
      log "$browser_name: enabled legacy stylesheets in user.js"
    fi
  else
    echo "$pref" > "$user_js"
    log "$browser_name: created user.js with legacy stylesheets enabled"
  fi
}

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
  # Check config toggle
  local config_file="${XDG_CONFIG_HOME:-$HOME/.config}/inir/config.json"
  local enable
  if command -v jq &>/dev/null && [[ -f "$config_file" ]]; then
    enable=$(jq -r '.appearance.wallpaperTheming.enableFirefox // true' "$config_file" 2>/dev/null)
    [[ "$enable" != "false" ]] || { log "disabled via config"; return 0; }
  fi

  local found_any=0

  for entry in "${BROWSER_CONFIGS[@]}"; do
    IFS='|' read -r name config_dir <<< "$entry"

    if [[ ! -d "$config_dir" ]]; then
      log "$name: not installed ($config_dir not found)"
      continue
    fi

    log "$name: scanning $config_dir"

    local profile_dirs=()
    while IFS= read -r dir; do
      [[ -n "$dir" ]] && profile_dirs+=("$dir")
    done < <(discover_profiles "$config_dir")

    if [[ ${#profile_dirs[@]} -eq 0 ]]; then
      log "$name: no profiles found"
      continue
    fi

    for profile_dir in "${profile_dirs[@]}"; do
      if [[ ! -d "$profile_dir" ]]; then
        log "$name: profile dir missing: $profile_dir"
        continue
      fi

      log "$name: theming profile: $profile_dir"
      install_theme "$profile_dir" "$name"
      enable_legacy_customizations "$profile_dir" "$name"
      found_any=1
    done
  done

  if [[ $found_any -eq 0 ]]; then
    log "No Firefox-based browsers found"
    return 0
  fi

  notify_user "Theme applied to Firefox-based browsers"
  log "Done"
}

main "$@"
