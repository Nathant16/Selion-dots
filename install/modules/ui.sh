#!/usr/bin/env bash

if ! declare -f os_release_get >/dev/null; then
    source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/os_release.sh"
fi

RESET=$'\e[0m'
BOLD=$'\e[1m'
DIM=$'\e[2m'
C_BLUE=$'\e[34m'
C_CYAN=$'\e[36m'
C_GREEN=$'\e[32m'
C_YELLOW=$'\e[33m'
C_RED=$'\e[31m'
C_MAGENTA=$'\e[35m'

ENABLE_TELEMETRY=true
INSTALL_FULL_WALLPAPERS=true
KEYBOARD_LAYOUT="us,ru"
KEYBOARD_TOGGLE="alt_shift"
OPT_FAST_REPOS=false
SELECTED_COMPOSITORS=()
SELECTED_ADDITIONAL_PKGS=()
DETECTED_COMPOSITOR_LABEL=""
MULTIPLE_COMPOSITORS_DETECTED=false
UNSUPPORTED_COMPOSITOR_DETECTED=false
IS_REINSTALL=false
DO_UNINSTALL=false
TUI_HANDLED=false

OPT_SDDM=true
REPLACE_DM=false
SDDM_WAYLAND="$PM_SDDM_WAYLAND_DEFAULT"

USER_NAME="${USER:-$(whoami)}"
OS_NAME="$(os_release_get PRETTY_NAME || true)"
[[ -z "$OS_NAME" ]] && OS_NAME="$(os_release_get NAME || true)"
[[ -z "$OS_NAME" ]] && OS_NAME="$(t "installer.os.default_os")"
CPU_INFO=$(grep -m 1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed -E 's/^[ \t]+|[ \t]+$//' || true)
[[ -z "$CPU_INFO" ]] && CPU_INFO="$(t "installer.os.unknown_cpu")"

GPU_RAW=$(lspci -nn 2>/dev/null | grep -iE 'vga|3d|display' || true)
GPU_INFO=""
if [ -n "$GPU_RAW" ]; then
    GPU_INFO=$(printf '%s\n' "$GPU_RAW" | sed -E 's/^[^:]+:[^:]+: //; s/ \[[0-9a-f]{4}:[0-9a-f]{4}\]//g; s/ \(rev [0-9a-f]+\)//g' | awk 'NR==1{out=$0} NR>1{out=out ", " $0} END{gsub(/^[ \t]+|[ \t]+$/, "", out); print out}' || true)
fi
[[ -z "$GPU_INFO" ]] && GPU_INFO="$(t "installer.os.unknown_gpu")"

PKGS_DEVELOPMENT=(
    "visual-studio-code-bin:Visual Studio Code (Microsoft official build)"
    "neovim:Neovim (Vim-fork focused on extensibility)"
    "zed:Zed Editor (High-performance Rust editor)"
    "lazygit:Lazygit (Terminal UI for Git)"
    "docker:Docker (Container application platform)"
    "docker-compose:Docker Compose"
    "postman-bin:Postman (API development platform)"
    "dbeaver:DBeaver (Universal database manager)"
    "github-cli:GitHub CLI (Command line tool for GitHub)"
    "nodejs:Node.js & npm (JavaScript runtime and package manager)"
    "rust:Rust toolchain"
)

PKGS_SOCIAL=(
    "discord:Discord (Official chat client)"
    "vesktop-bin:Vesktop (Discord Wayland client with screenshare fixes)"
    "telegram-desktop:Telegram Desktop (Official client)"
    "ayugram-desktop-bin:AyuGram Desktop (Privacy-oriented Telegram client)"
)

PKGS_BROWSERS=(
    "zen-browser-bin:Zen Browser (Firefox fork with vertical tabs)"
    "brave-bin:Brave Browser (Chromium privacy)"
    "firefox:Mozilla Firefox"
    "google-chrome:Google Chrome"
)

PKGS_GAMES=(
    "steam:Steam (Official gaming client) [Recommended]"
    "gamemode:GameMode (Game performance optimization service) [Recommended]"
    "mangohud:MangoHud (Overlay for FPS, temperatures & hardware stats)"
    "portproton:PortProton (Windows games launcher & presets) [Recommended]"
    "prismlauncher:Prism Launcher (Custom Minecraft launcher with instance manager)"
)

PKGS_OFFICE=(
    "onlyoffice-bin:ONLYOFFICE Desktop (Collaborative office suite) [Recommended]"
    "libreoffice-fresh:LibreOffice Fresh (Comprehensive open-source office suite)"
    "wordcraft-bin:WordCraft (Native Microsoft Word alternative)"
    "gridcraft-bin:GridCraft (Native Microsoft Excel alternative)"
    "deckcraft-bin:DeckCraft (Native Microsoft PowerPoint alternative)"
)

PKGS_MEDIA=(
    "spotify:Spotify Music"
    "obsidian:Obsidian (Markdown notes & knowledge base)"
    "obs-studio:OBS Studio (Screen recorder & live streaming)"
)

AVAILABLE_ADDITIONAL_PKGS=(
    "${PKGS_DEVELOPMENT[@]}"
    "${PKGS_SOCIAL[@]}"
    "${PKGS_BROWSERS[@]}"
    "${PKGS_GAMES[@]}"
    "${PKGS_OFFICE[@]}"
    "${PKGS_MEDIA[@]}"
)

cleanup_terminal() {
    printf "\e[?25h" 2>/dev/null || true
    stty echo icanon 2>/dev/null || true
}
trap cleanup_terminal EXIT INT TERM

is_compositor_installed() {
    local comp="$1"
    case "$comp" in
        hyprland)
            command -v Hyprland &>/dev/null || command -v hyprland &>/dev/null || pm_is_installed hyprland
            ;;
        driftwm)
            command -v driftwm &>/dev/null || pm_is_installed driftwm || pm_is_installed driftwm-bin
            ;;
        niri)
            command -v niri &>/dev/null || pm_is_installed niri
            ;;
        sway)
            command -v sway &>/dev/null || pm_is_installed sway
            ;;
        mango)
            command -v mango &>/dev/null || command -v mangowm &>/dev/null || command -v mangowc &>/dev/null || pm_is_installed mangowm || pm_is_installed mangowc || pm_is_installed mango
            ;;
        umbriel)
            command -v umbriel &>/dev/null || pm_is_installed "$(compositor_package_name umbriel)"
            ;;
        *)
            command -v "$comp" &>/dev/null || pm_is_installed "$comp"
            ;;
    esac
}

init_compositor_detection() {
    local supported_compositors=("hyprland" "driftwm" "niri" "sway" "mango" "umbriel")
    local installed=()
    local state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
    local version_file="$state_home/serpantinum/version"

    for comp in "${supported_compositors[@]}"; do
        if is_compositor_installed "$comp"; then
            installed+=("$comp")
        fi
    done

    local is_update=false
    if [[ "$INSTALL_STATE" == "current" || "$INSTALL_STATE" == "legacy" || -f "$version_file" || -f "$state_home/imperative-dots-version" ]]; then
        is_update=true
    fi

    if [ "$is_update" = true ]; then
        if [ ${#installed[@]} -gt 0 ]; then
            SELECTED_COMPOSITORS=("${installed[@]}")
            DETECTED_COMPOSITOR_LABEL="$(IFS=, ; echo "${SELECTED_COMPOSITORS[*]}")"
            MULTIPLE_COMPOSITORS_DETECTED=false
            UNSUPPORTED_COMPOSITOR_DETECTED=false
            return 0
        elif [ -f "$version_file" ]; then
            local saved_comps
            saved_comps=$(awk -F= '/^SELECTED_COMPOSITORS=/{gsub(/"/, "", $2); print $2}' "$version_file" 2>/dev/null || true)
            if [ -n "$saved_comps" ]; then
                read -r -a SELECTED_COMPOSITORS <<< "$saved_comps"
                DETECTED_COMPOSITOR_LABEL="$(IFS=, ; echo "${SELECTED_COMPOSITORS[*]}")"
                MULTIPLE_COMPOSITORS_DETECTED=false
                UNSUPPORTED_COMPOSITOR_DETECTED=false
                return 0
            fi
        fi
    fi

    local running=""
    local de="${XDG_CURRENT_DESKTOP,,}"
    local session="${DESKTOP_SESSION,,}"

    if [[ -n "$MANGO_INSTANCE_SIGNATURE" ]] || pgrep -x "mango" &>/dev/null || [[ "$de" == *"mango"* ]] || [[ "$session" == *"mango"* ]]; then
        running="mango"
    elif [[ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]] || pgrep -x "Hyprland" &>/dev/null || pgrep -x "hyprland" &>/dev/null || [[ "$de" == *"hyprland"* ]] || [[ "$session" == *"hyprland"* ]]; then
        running="hyprland"
    elif [[ -n "$DRIFTWM_SOCKET" ]] || pgrep -x "driftwm" &>/dev/null || [[ "$de" == *"drift"* ]] || [[ "$session" == *"drift"* ]]; then
        running="driftwm"
    elif [[ -n "$SWAYSOCK" ]] || pgrep -x "sway" &>/dev/null || [[ "$de" == *"sway"* ]] || [[ "$session" == *"sway"* ]]; then
        running="sway"
    elif pgrep -x "niri" &>/dev/null || [[ "$de" == *"niri"* ]] || [[ "$session" == *"niri"* ]]; then
        running="niri"
    elif [[ -n "$UMBRIEL_SOCKET" ]] || pgrep -x "umbriel" &>/dev/null || [[ "$de" == *"umbriel"* ]] || [[ "$session" == *"umbriel"* ]]; then
        running="umbriel"
    fi

    if [ -n "$running" ]; then
        SELECTED_COMPOSITORS=("$running")
        DETECTED_COMPOSITOR_LABEL="$running"
    elif [ -f "$version_file" ]; then
        local saved_comps
        saved_comps=$(awk -F= '/^SELECTED_COMPOSITORS=/{gsub(/"/, "", $2); print $2}' "$version_file" 2>/dev/null || true)
        if [ -n "$saved_comps" ]; then
            read -r -a SELECTED_COMPOSITORS <<< "$saved_comps"
            DETECTED_COMPOSITOR_LABEL="$(IFS=, ; echo "${SELECTED_COMPOSITORS[*]}")"
        fi
    fi

    if [ ${#SELECTED_COMPOSITORS[@]} -eq 0 ]; then
        if [ ${#installed[@]} -gt 1 ]; then
            MULTIPLE_COMPOSITORS_DETECTED=true
            SELECTED_COMPOSITORS=()
        elif [ ${#installed[@]} -eq 1 ]; then
            SELECTED_COMPOSITORS=("${installed[0]}")
            DETECTED_COMPOSITOR_LABEL="${installed[0]}"
        else
            UNSUPPORTED_COMPOSITOR_DETECTED=true
            DETECTED_COMPOSITOR_LABEL="$(t "installer.ui.unsupported_compositor")"
            SELECTED_COMPOSITORS=()
        fi
    fi
}

detect_current_dm() {
    if declare -f pm_detect_current_dm >/dev/null; then
        local pm_dm
        pm_dm="$(pm_detect_current_dm)"
        if [ -n "$pm_dm" ]; then
            echo "$pm_dm"
            return 0
        fi
    fi

    local dms=("gdm" "gdm3" "lightdm" "sddm" "lxdm" "lxdm-gtk3" "ly" "greetd" "emptty")
    local dm
    for dm in "${dms[@]}"; do
        if command -v systemctl &>/dev/null; then
            if systemctl is-enabled "$dm.service" &>/dev/null || systemctl is-active "$dm.service" &>/dev/null; then
                echo "$dm"
                return 0
            fi
        elif [ -L "/var/service/$dm" ] || [ -d "/var/service/$dm" ]; then
            echo "$dm"
            return 0
        elif command -v rc-service &>/dev/null && rc-service "$dm" status &>/dev/null; then
            echo "$dm"
            return 0
        fi
    done
    echo ""
}

run_installer_ui() {
    if [ "${NONINTERACTIVE:-0}" = "1" ] || [ "${AUTO_INSTALL:-0}" = "1" ]; then
        if [ ${#SELECTED_COMPOSITORS[@]} -eq 0 ]; then
            SELECTED_COMPOSITORS=("hyprland" "driftwm" "niri" "sway" "mango" "umbriel")
        fi
        OPT_SDDM="${OPT_SDDM:-true}"
        INSTALL_FULL_WALLPAPERS="${INSTALL_FULL_WALLPAPERS:-true}"
        ENABLE_TELEMETRY="${ENABLE_TELEMETRY:-false}"
        OPT_FAST_REPOS="${OPT_FAST_REPOS:-false}"
        KEYBOARD_LAYOUT="${KEYBOARD_LAYOUT:-us,ru}"
        KEYBOARD_TOGGLE="${KEYBOARD_TOGGLE:-alt_shift}"
        TUI_HANDLED=false
        return 0
    fi

    local current_dm
    current_dm="$(detect_current_dm)"

    local comp_installed_pairs=""
    local comp pkg
    for comp in hyprland driftwm niri sway mango umbriel; do
        if is_compositor_installed "$comp"; then
            comp_installed_pairs+="${comp}=1"$'\n'
        else
            comp_installed_pairs+="${comp}=0"$'\n'
        fi
    done

    local base_sddm_pkgs=(sddm qt6-declarative qt6-svg "${PM_SDDM_EXTRA_PKGS[@]}")
    local sddm_needs_weston=false
    if ! find_sddm_binary kwin_wayland >/dev/null && ! find_sddm_binary weston >/dev/null; then
        sddm_needs_weston=true
    fi

    local all_candidates=("${REQUIRED_PKGS[@]}" "${base_sddm_pkgs[@]}" "${PM_EXTRA_PKGS[@]}" "weston")
    for comp in hyprland driftwm niri sway mango umbriel; do
        all_candidates+=("$(compositor_package_name "$comp")")
    done
    local entry
    for entry in "${AVAILABLE_ADDITIONAL_PKGS[@]}"; do
        all_candidates+=("${entry%%:*}")
    done

    local missing_raw
    missing_raw="$(pm_missing_pkgs "${all_candidates[@]}")"

    local ctx_file res_file
    ctx_file="$(mktemp)"
    res_file="$(mktemp)"

    CTX_FILE="$ctx_file" \
    CTX_PROJECT_ROOT="$PROJECT_ROOT" \
    CTX_MODULES_DIR="$MODULES_DIR" \
    CTX_REPO_SLUG="$REPO_SLUG" \
    CTX_INSTALL_STATE="$INSTALL_STATE" \
    CTX_OLD_VERSION="$OLD_VERSION" \
    CTX_TARGET_VERSION="$TARGET_VERSION" \
    CTX_TARGET_COMMIT="$TARGET_COMMIT" \
    CTX_OLD_COMMIT="$OLD_COMMIT" \
    CTX_USER_NAME="$USER_NAME" \
    CTX_OS_NAME="$OS_NAME" \
    CTX_CPU_INFO="$CPU_INFO" \
    CTX_GPU_INFO="$GPU_INFO" \
    CTX_TELEMETRY_ID="$TELEMETRY_ID" \
    CTX_ENABLE_TELEMETRY="$ENABLE_TELEMETRY" \
    CTX_OPT_SDDM="$OPT_SDDM" \
    CTX_REPLACE_DM="$REPLACE_DM" \
    CTX_SDDM_WAYLAND="$SDDM_WAYLAND" \
    CTX_INSTALL_FULL_WALLPAPERS="$INSTALL_FULL_WALLPAPERS" \
    CTX_KEYBOARD_LAYOUT="${KEYBOARD_LAYOUT:-us,ru}" \
    CTX_KEYBOARD_TOGGLE="${KEYBOARD_TOGGLE:-alt_shift}" \
    CTX_OPT_FAST_REPOS="${OPT_FAST_REPOS:-false}" \
    CTX_SELECTED_COMPOSITORS="$(printf '%s\n' "${SELECTED_COMPOSITORS[@]}")" \
    CTX_SELECTED_ADDITIONAL_PKGS="$(printf '%s\n' "${SELECTED_ADDITIONAL_PKGS[@]}")" \
    CTX_DETECTED_COMPOSITOR_LABEL="$DETECTED_COMPOSITOR_LABEL" \
    CTX_MULTIPLE_COMPOSITORS="$MULTIPLE_COMPOSITORS_DETECTED" \
    CTX_UNSUPPORTED_COMPOSITOR="$UNSUPPORTED_COMPOSITOR_DETECTED" \
    CTX_CURRENT_DM="$current_dm" \
    CTX_COMP_INSTALLED="$comp_installed_pairs" \
    CTX_REQUIRED_PKGS="$(printf '%s\n' "${REQUIRED_PKGS[@]}")" \
    CTX_PM_EXTRA_PKGS="$(printf '%s\n' "${PM_EXTRA_PKGS[@]}")" \
    CTX_SDDM_PKGS="$(printf '%s\n' "${base_sddm_pkgs[@]}")" \
    CTX_SDDM_NEEDS_WESTON="$sddm_needs_weston" \
    CTX_ALL_CANDIDATES="$(printf '%s\n' "${all_candidates[@]}")" \
    CTX_MISSING_PKGS="$missing_raw" \
    CTX_PKGS_DEV="$(printf '%s\n' "${PKGS_DEVELOPMENT[@]}")" \
    CTX_PKGS_SOC="$(printf '%s\n' "${PKGS_SOCIAL[@]}")" \
    CTX_PKGS_BRW="$(printf '%s\n' "${PKGS_BROWSERS[@]}")" \
    CTX_PKGS_GAM="$(printf '%s\n' "${PKGS_GAMES[@]}")" \
    CTX_PKGS_OFF="$(printf '%s\n' "${PKGS_OFFICE[@]}")" \
    CTX_PKGS_MED="$(printf '%s\n' "${PKGS_MEDIA[@]}")" \
    python3 -c '
import json, os

def lines(name):
    return [x for x in os.environ.get(name, "").splitlines() if x]

def to_bool(name):
    return os.environ.get(name, "").lower() == "true"

def parse_cat(cid, title, env_name):
    items = []
    for raw in lines(env_name):
        pkg, _, label = raw.partition(":")
        items.append({"pkg": pkg, "label": label or pkg})
    return {"id": cid, "title": title, "items": items}

missing = set(lines("CTX_MISSING_PKGS"))
pkg_status = {p: (p not in missing) for p in lines("CTX_ALL_CANDIDATES")}

comp_installed = {}
for item in lines("CTX_COMP_INSTALLED"):
    if "=" in item:
        k, v = item.split("=", 1)
        comp_installed[k] = (v == "1")

if comp_installed.get("driftwm"):
    pkg_status["driftwm-bin"] = True

payload = {
    "project_root": os.environ["CTX_PROJECT_ROOT"],
    "modules_dir": os.environ["CTX_MODULES_DIR"],
    "repo_slug": os.environ["CTX_REPO_SLUG"],
    "install_state": os.environ["CTX_INSTALL_STATE"],
    "old_version": os.environ["CTX_OLD_VERSION"],
    "target_version": os.environ["CTX_TARGET_VERSION"],
    "target_commit": os.environ["CTX_TARGET_COMMIT"],
    "old_commit": os.environ["CTX_OLD_COMMIT"],
    "user_name": os.environ["CTX_USER_NAME"],
    "os_name": os.environ["CTX_OS_NAME"],
    "cpu_info": os.environ["CTX_CPU_INFO"],
    "gpu_info": os.environ["CTX_GPU_INFO"],
    "telemetry_id": os.environ["CTX_TELEMETRY_ID"],
    "enable_telemetry": to_bool("CTX_ENABLE_TELEMETRY"),
    "opt_sddm": to_bool("CTX_OPT_SDDM"),
    "replace_dm": to_bool("CTX_REPLACE_DM"),
    "sddm_wayland": to_bool("CTX_SDDM_WAYLAND"),
    "install_full_wallpapers": to_bool("CTX_INSTALL_FULL_WALLPAPERS"),
    "keyboard_layout": os.environ["CTX_KEYBOARD_LAYOUT"],
    "keyboard_toggle": os.environ["CTX_KEYBOARD_TOGGLE"],
    "opt_fast_repos": to_bool("CTX_OPT_FAST_REPOS"),
    "selected_compositors": lines("CTX_SELECTED_COMPOSITORS"),
    "selected_additional_pkgs": lines("CTX_SELECTED_ADDITIONAL_PKGS"),
    "detected_compositor_label": os.environ["CTX_DETECTED_COMPOSITOR_LABEL"],
    "multiple_compositors_detected": to_bool("CTX_MULTIPLE_COMPOSITORS"),
    "unsupported_compositor_detected": to_bool("CTX_UNSUPPORTED_COMPOSITOR"),
    "current_dm": os.environ["CTX_CURRENT_DM"],
    "compositor_installed": comp_installed,
    "required_pkgs": lines("CTX_REQUIRED_PKGS"),
    "pm_extra_pkgs": lines("CTX_PM_EXTRA_PKGS"),
    "sddm_pkgs": lines("CTX_SDDM_PKGS"),
    "sddm_needs_weston": to_bool("CTX_SDDM_NEEDS_WESTON"),
    "package_installed": pkg_status,
    "additional_pkg_categories": [
        parse_cat("dev", "Development", "CTX_PKGS_DEV"),
        parse_cat("social", "Social Media", "CTX_PKGS_SOC"),
        parse_cat("browsers", "Web Browsers", "CTX_PKGS_BRW"),
        parse_cat("games", "Games", "CTX_PKGS_GAM"),
        parse_cat("office", "Office", "CTX_PKGS_OFF"),
        parse_cat("media", "Media & Entertainment", "CTX_PKGS_MED"),
    ],
}

with open(os.environ["CTX_FILE"], "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
'

    local tui_status=0
    python3 "$INSTALL_DIR/tui.py" --context "$ctx_file" --result "$res_file" || tui_status=$?

    local action="exit"
    if [ -s "$res_file" ]; then
        action="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1])).get("action", "exit"))' "$res_file" 2>/dev/null || echo "exit")"
    fi

    rm -f "$ctx_file" "$res_file"
    TUI_HANDLED=true

    if [ "$tui_status" -ne 0 ]; then
        exit "$tui_status"
    fi

    if [ "$action" = "reboot" ]; then
        sudo reboot now
    fi
}

draw_completion_screen() {
    local target_ver="$1"
    local target_commit="$2"
    cleanup_terminal
    printf "%s%s%s\n" "$C_GREEN" "$(t "installer.ui.installed_success" "ver=$target_ver" "commit=$target_commit")" "$RESET"
    if [ ${#FAILED_PKGS[@]} -gt 0 ]; then
        printf "\n%s%s%s%s\n" "$BOLD" "$C_RED" "$(t "installer.ui.failed_packages")" "$RESET"
        for fp in "${FAILED_PKGS[@]}"; do
            printf "  - %s%s%s\n" "$C_YELLOW" "$fp" "$RESET"
        done
    fi
    printf "%s\n" "$(t "installer.ui.restart_prompt")"

    if [ "${NONINTERACTIVE:-0}" = "1" ] || [ "${AUTO_INSTALL:-0}" = "1" ]; then
        return 0
    fi

    local restart_choice=""
    local prompt_msg
    prompt_msg="$(t "installer.ui.ask_reboot")"
    if [ -t 0 ]; then
        read -r -p "$prompt_msg" restart_choice
    elif [ -e /dev/tty ]; then
        read -r -p "$prompt_msg" restart_choice < /dev/tty
    fi
    if [[ "$restart_choice" =~ ^[Yy]$ ]]; then
        sudo reboot now
    fi
}
