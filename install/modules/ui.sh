#!/usr/bin/env bash

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
SELECTED_COMPOSITORS=()
DETECTED_COMPOSITOR_LABEL=""
MULTIPLE_COMPOSITORS_DETECTED=false
UNSUPPORTED_COMPOSITOR_DETECTED=false
IS_REINSTALL=false

OPT_SDDM=true
REPLACE_DM=false
SDDM_WAYLAND="$PM_SDDM_WAYLAND_DEFAULT"

USER_NAME="${USER:-$(whoami)}"
OS_NAME=$(grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
[[ -z "$OS_NAME" ]] && OS_NAME="$(t "installer.os.default_os")"
CPU_INFO=$(grep -m 1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || true)
[[ -z "$CPU_INFO" ]] && CPU_INFO="$(t "installer.os.unknown_cpu")"

GPU_RAW=$(lspci -nn 2>/dev/null | grep -iE 'vga|3d|display' || true)
GPU_INFO=$(echo "$GPU_RAW" | sed -E 's/^[^:]+:[^:]+: //; s/ \[[0-9a-f]{4}:[0-9a-f]{4}\]//g; s/ \(rev [0-9a-f]+\)//g' | paste -sd ', ' - | xargs)
[[ -z "$GPU_INFO" ]] && GPU_INFO="$(t "installer.os.unknown_gpu")"

cleanup_terminal() {
    printf "\e[?25h" 2>/dev/null || true
    stty echo icanon 2>/dev/null || true
}
trap cleanup_terminal EXIT INT TERM

read_key() {
    local key=""
    local rest=""
    IFS= read -rsn1 key 2>/dev/null
    if [[ "$key" == $'\x1b' ]]; then
        read -rsn2 -t 0.05 rest 2>/dev/null
        if [[ "$rest" == "[A" || "$rest" == "OA" ]]; then
            echo "UP"
            return
        elif [[ "$rest" == "[B" || "$rest" == "OB" ]]; then
            echo "DOWN"
            return
        elif [[ "$rest" == "[C" || "$rest" == "OC" ]]; then
            echo "RIGHT"
            return
        elif [[ "$rest" == "[D" || "$rest" == "OD" ]]; then
            echo "LEFT"
            return
        elif [[ "$rest" == *"["* ]]; then
            local trailing=""
            while read -rsn1 -t 0.05 trailing 2>/dev/null; do
                [[ -z "$trailing" ]] && break
            done
            echo "ESC"
            return
        elif [[ -z "$rest" ]]; then
            echo "ESC"
            return
        fi
        echo "ESC"
        return
    elif [[ -z "$key" || "$key" == $'\n' || "$key" == $'\r' ]]; then
        echo "ENTER"
        return
    elif [[ "$key" == " " ]]; then
        echo "SPACE"
        return
    fi
    echo "$key"
}

init_compositor_detection() {
    local installed=()
    for comp in hyprland driftwm niri sway mango; do
        if command -v "$comp" &>/dev/null || pm_is_installed "$(compositor_package_name "$comp")"; then
            installed+=("$comp")
        fi
    done

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
    fi

    if [ -n "$running" ]; then
        SELECTED_COMPOSITORS=("$running")
        DETECTED_COMPOSITOR_LABEL="$running"
    elif [ -f "$HOME/.local/state/serpantinum/version" ]; then
        local saved_comps
        saved_comps=$(awk -F= '/^SELECTED_COMPOSITORS=/{gsub(/"/, "", $2); print $2}' "$HOME/.local/state/serpantinum/version" 2>/dev/null || true)
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

_pad_label() {
    local text="$1"
    local width="${2:-18}"
    local pad=$(( width - ${#text} ))
    (( pad < 1 )) && pad=1
    printf "%s%*s" "$text" "$pad" ""
}

draw_banner() {
    clear 2>/dev/null || true
    printf "%s%s" "$BOLD" "$C_CYAN"
    cat << "EOF"
███████╗███████╗██╗     ██╗ ██████╗ ███╗   ██╗
██╔════╝██╔════╝██║     ██║██╔═══██╗████╗  ██║
███████╗█████╗  ██║     ██║██║   ██║██╔██╗ ██║
╚════██║██╔══╝  ██║     ██║██║   ██║██║╚██╗██║
███████║███████╗███████╗██║╚██████╔╝██║ ╚████║
╚══════╝╚══════╝╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═══╝
EOF
    printf "%s\n" "$RESET"

    local OSC8_GH=$'\e]8;;https://github.com/'"${REPO_SLUG}"$'\a'
    local OSC8_TG=$'\e]8;;https://t.me/Nathant16\a'
    local OSC8_END=$'\e]8;;\a'

    local lbl_gh="$(t "installer.ui.github")"
    local lbl_tg="$(t "installer.ui.telegram")"
    local lbl_user="$(t "installer.ui.user")"
    local lbl_os="$(t "installer.ui.os")"
    local lbl_cpu="$(t "installer.ui.cpu")"
    local lbl_gpu="$(t "installer.ui.gpu")"
    local lbl_ver="$(t "installer.ui.target_version")"
    local lbl_mode="$(t "installer.ui.install_mode")"

    local col_w=18
    for lbl in "$lbl_gh" "$lbl_tg" "$lbl_user" "$lbl_os" "$lbl_cpu" "$lbl_gpu" "$lbl_ver" "$lbl_mode"; do
        (( ${#lbl} + 2 > col_w )) && col_w=$(( ${#lbl} + 2 ))
    done

    printf "\033[K%s--------------------------------------------------------------------------------%s\n" "$C_BLUE" "$RESET"
    printf "\033[K%s%s %s%s%shttps://github.com/%s%s\n" "$BOLD" "$C_GREEN" "$(_pad_label "$lbl_gh" "$col_w")" "$RESET" "$OSC8_GH" "$REPO_SLUG" "$OSC8_END"
    printf "\033[K%s%s %s%s%shttps://t.me/Nathant16%s\n" "$BOLD" "$C_CYAN" "$(_pad_label "$lbl_tg" "$col_w")" "$RESET" "$OSC8_TG" "$OSC8_END"
    printf "\033[K%s--------------------------------------------------------------------------------%s\n" "$C_BLUE" "$RESET"
    printf "\033[K%s %s%s%s\n" "$BOLD" "$(_pad_label "$lbl_user" "$col_w")" "$RESET" "$USER_NAME"
    printf "\033[K%s %s%s%s\n" "$BOLD" "$(_pad_label "$lbl_os" "$col_w")" "$RESET" "$OS_NAME"
    printf "\033[K%s %s%s%s\n" "$BOLD" "$(_pad_label "$lbl_cpu" "$col_w")" "$RESET" "$CPU_INFO"
    printf "\033[K%s %s%s%s\n" "$BOLD" "$(_pad_label "$lbl_gpu" "$col_w")" "$RESET" "$GPU_INFO"
    printf "\033[K%s--------------------------------------------------------------------------------%s\n" "$C_BLUE" "$RESET"
    printf "\033[K%s %s%s%s (%s)\n" "$BOLD" "$(_pad_label "$lbl_ver" "$col_w")" "$RESET" "$TARGET_VERSION" "$TARGET_COMMIT"
    printf "\033[K%s %s%s%s\n" "$BOLD" "$(_pad_label "$lbl_mode" "$col_w")" "$RESET" "$INSTALL_STATE"
    printf "\033[K%s================================================================================%s\n\n" "$C_BLUE" "$RESET"
}

draw_status_bar() {
    local left="${1:-}"
    local right="${2:-}"
    if [ -n "$right" ]; then
        printf "\033[K%s%s%s %s(%s)%s\n" "$C_CYAN" "$left" "$RESET" "$DIM" "$right" "$RESET"
    elif [ -n "$left" ]; then
        printf "\033[K%s%s%s\n" "$C_CYAN" "$left" "$RESET"
    fi
}

show_package_overview() {
    local target_list=("${REQUIRED_PKGS[@]}")
    for comp in "${SELECTED_COMPOSITORS[@]}"; do
        target_list+=("$comp")
    done
    if [ "$OPT_SDDM" = true ]; then
        local sddm_pkgs=()
        mapfile -t sddm_pkgs < <(sddm_packages)
        target_list+=("${sddm_pkgs[@]}")
    fi
    target_list+=("${PM_EXTRA_PKGS[@]}")

    local missing_raw
    missing_raw=$(pm_missing_pkgs "${target_list[@]}")

    declare -A is_missing
    while IFS= read -r p; do
        [[ -n "$p" ]] && is_missing["$p"]=1
    done <<< "$missing_raw"

    local overview_items=()
    for pkg in "${target_list[@]}"; do
        if [[ -n "${is_missing[$pkg]}" ]]; then
            overview_items+=("$(t "installer.ui.package_missing" "pkg=$pkg")")
        else
            overview_items+=("$(t "installer.ui.package_installed" "pkg=$pkg")")
        fi
    done

    cleanup_terminal
    printf "%s\n" "${overview_items[@]}" | fzf \
        --ansi \
        --layout=reverse \
        --border=rounded \
        --margin=1,2 \
        --height=25 \
        --prompt="$(t "installer.ui.packages_prompt")" \
        --header="$(t "installer.ui.packages_header")" > /dev/null || true
    stty -echo icanon 2>/dev/null || true
    printf "\e[?25l"
}

remove_compositor() {
    local target="$1"
    local updated=()
    for c in "${SELECTED_COMPOSITORS[@]}"; do
        if [[ "$c" != "$target" ]]; then
            updated+=("$c")
        fi
    done
    SELECTED_COMPOSITORS=("${updated[@]}")
}

manage_compositors_menu() {
    draw_banner
    stty -echo 2>/dev/null || true
    printf "\e[?25l"
    printf "%s%s$(t "installer.ui.compositors_title")%s\n\n" "$BOLD" "$C_CYAN" "$RESET"

    local cursor=0
    local rendered_lines=0

    while true; do
        local status_hypr="$(t "installer.ui.not_installed")"
        local status_drift="$(t "installer.ui.not_installed")"
        local status_niri="$(t "installer.ui.not_installed")"
        local status_sway="$(t "installer.ui.not_installed")"
        local status_mango="$(t "installer.ui.not_installed")"

        if command -v hyprland &>/dev/null || pm_is_installed hyprland; then
            status_hypr="$(t "installer.ui.installed")"
        fi
        if command -v driftwm &>/dev/null || pm_is_installed driftwm; then
            status_drift="$(t "installer.ui.installed")"
        fi
        if command -v niri &>/dev/null || pm_is_installed niri; then
            status_niri="$(t "installer.ui.installed")"
        fi
        if command -v sway &>/dev/null || pm_is_installed sway; then
            status_sway="$(t "installer.ui.installed")"
        fi
        if command -v mango &>/dev/null || pm_is_installed "$(compositor_package_name mango)"; then
            status_mango="$(t "installer.ui.installed")"
        fi

        local S_HYPR="${DIM}[ ]${RESET}"
        local S_DRIFT="${DIM}[ ]${RESET}"
        local S_NIRI="${DIM}[ ]${RESET}"
        local S_SWAY="${DIM}[ ]${RESET}"
        local S_MANGO="${DIM}[ ]${RESET}"

        [[ " ${SELECTED_COMPOSITORS[*]} " =~ " hyprland " ]] && S_HYPR="${C_GREEN}[✓]${RESET}"
        [[ " ${SELECTED_COMPOSITORS[*]} " =~ " driftwm " ]] && S_DRIFT="${C_GREEN}[✓]${RESET}"
        [[ " ${SELECTED_COMPOSITORS[*]} " =~ " niri " ]] && S_NIRI="${C_GREEN}[✓]${RESET}"
        [[ " ${SELECTED_COMPOSITORS[*]} " =~ " sway " ]] && S_SWAY="${C_GREEN}[✓]${RESET}"
        [[ " ${SELECTED_COMPOSITORS[*]} " =~ " mango " ]] && S_MANGO="${C_GREEN}[✓]${RESET}"

        local items=(
            "1. $S_HYPR Hyprland $status_hypr"
            "2. $S_DRIFT DriftWM $status_drift"
            "3. $S_NIRI Niri $status_niri"
            "4. $S_SWAY Sway $status_sway"
            "5. $S_MANGO Mango $status_mango"
            "6. ${BOLD}${C_GREEN}$(t "installer.ui.done")${RESET}"
        )

        if [ "$rendered_lines" -gt 0 ]; then
            printf "\033[%dA" "$rendered_lines"
        fi

        for i in "${!items[@]}"; do
            if [ "$i" -eq "$cursor" ]; then
                printf "\r\033[K%s%s ▸ %s%s\n" "$BOLD" "$C_CYAN" "$RESET" "${items[$i]}"
            else
                printf "\r\033[K    %s\n" "${items[$i]}"
            fi
        done
        rendered_lines=${#items[@]}

        local key
        key=$(read_key)

        case "$key" in
            UP|[kK])
                if [ "$cursor" -gt 0 ]; then
                    cursor=$(( cursor - 1 ))
                else
                    cursor=$(( ${#items[@]} - 1 ))
                fi
                ;;
            DOWN|[jJ])
                if [ "$cursor" -lt $(( ${#items[@]} - 1 )) ]; then
                    cursor=$(( cursor + 1 ))
                else
                    cursor=0
                fi
                ;;
            "1")
                if [[ " ${SELECTED_COMPOSITORS[*]} " =~ " hyprland " ]]; then
                    remove_compositor "hyprland"
                else
                    SELECTED_COMPOSITORS+=("hyprland")
                fi
                ;;
            "2")
                if [[ " ${SELECTED_COMPOSITORS[*]} " =~ " driftwm " ]]; then
                    remove_compositor "driftwm"
                else
                    SELECTED_COMPOSITORS+=("driftwm")
                fi
                ;;
            "3")
                if [[ " ${SELECTED_COMPOSITORS[*]} " =~ " niri " ]]; then
                    remove_compositor "niri"
                else
                    SELECTED_COMPOSITORS+=("niri")
                fi
                ;;
            "4")
                if [[ " ${SELECTED_COMPOSITORS[*]} " =~ " sway " ]]; then
                    remove_compositor "sway"
                else
                    SELECTED_COMPOSITORS+=("sway")
                fi
                ;;
            "5")
                if [[ " ${SELECTED_COMPOSITORS[*]} " =~ " mango " ]]; then
                    remove_compositor "mango"
                else
                    SELECTED_COMPOSITORS+=("mango")
                fi
                ;;
            "6"|ESC|[qQ])
                break
                ;;
            ENTER|SPACE)
                case "$cursor" in
                    0)
                        if [[ " ${SELECTED_COMPOSITORS[*]} " =~ " hyprland " ]]; then
                            remove_compositor "hyprland"
                        else
                            SELECTED_COMPOSITORS+=("hyprland")
                        fi
                        ;;
                    1)
                        if [[ " ${SELECTED_COMPOSITORS[*]} " =~ " driftwm " ]]; then
                            remove_compositor "driftwm"
                        else
                            SELECTED_COMPOSITORS+=("driftwm")
                        fi
                        ;;
                    2)
                        if [[ " ${SELECTED_COMPOSITORS[*]} " =~ " niri " ]]; then
                            remove_compositor "niri"
                        else
                            SELECTED_COMPOSITORS+=("niri")
                        fi
                        ;;
                    3)
                        if [[ " ${SELECTED_COMPOSITORS[*]} " =~ " sway " ]]; then
                            remove_compositor "sway"
                        else
                            SELECTED_COMPOSITORS+=("sway")
                        fi
                        ;;
                    4)
                        if [[ " ${SELECTED_COMPOSITORS[*]} " =~ " mango " ]]; then
                            remove_compositor "mango"
                        else
                            SELECTED_COMPOSITORS+=("mango")
                        fi
                        ;;
                    5)
                        break
                        ;;
                esac
                ;;
        esac
    done
}

manage_sddm_menu() {
    draw_banner
    stty -echo 2>/dev/null || true
    printf "\e[?25l"
    printf "%s%s$(t "installer.ui.sddm_title")%s\n\n" "$BOLD" "$C_CYAN" "$RESET"

    local current_dm=""
    local dms=("gdm" "gdm3" "lightdm" "sddm" "lxdm" "lxdm-gtk3" "ly")
    for dm in "${dms[@]}"; do
        if systemctl is-enabled "$dm.service" &>/dev/null || systemctl is-active "$dm.service" &>/dev/null; then
            current_dm="$dm"
            break
        fi
    done

    if [ -n "$current_dm" ]; then
        printf "$(t "installer.ui.sddm_detected_active" "dm=${BOLD}${C_YELLOW}%s${RESET}")\n\n" "$current_dm"
    else
        printf "%s\n\n" "$(t "installer.ui.sddm_detected_none")"
    fi

    local cursor=0
    local rendered_lines=0

    while true; do
        local S_SDDM="${DIM}[Disabled]${RESET}"
        local S_RDM="${DIM}[No]${RESET}"
        local S_WAY="${DIM}[X11/Default]${RESET}"

        [ "$OPT_SDDM" = true ] && S_SDDM="${C_GREEN}[Enabled]${RESET}"
        [ "$REPLACE_DM" = true ] && S_RDM="${C_GREEN}[Yes]${RESET}"
        [ "$SDDM_WAYLAND" = true ] && S_WAY="${C_GREEN}[Wayland]${RESET}"

        local items=()
        items+=("1. $(t "installer.ui.sddm_opt_install") $S_SDDM")
        if [ -n "$current_dm" ] && [ "$current_dm" != "sddm" ]; then
            items+=("2. $(t "installer.ui.sddm_opt_disable" "dm=$current_dm") $S_RDM")
        fi
        items+=("3. $(t "installer.ui.sddm_opt_wayland") $S_WAY")
        items+=("4. ${BOLD}${C_GREEN}$(t "installer.ui.done")${RESET}")

        if [ "$rendered_lines" -gt 0 ]; then
            printf "\033[%dA" "$rendered_lines"
        fi

        for i in "${!items[@]}"; do
            if [ "$i" -eq "$cursor" ]; then
                printf "\r\033[K%s%s ▸ %s%s\n" "$BOLD" "$C_CYAN" "$RESET" "${items[$i]}"
            else
                printf "\r\033[K    %s\n" "${items[$i]}"
            fi
        done
        rendered_lines=${#items[@]}

        local key
        key=$(read_key)

        case "$key" in
            UP|[kK])
                if [ "$cursor" -gt 0 ]; then
                    cursor=$(( cursor - 1 ))
                else
                    cursor=$(( ${#items[@]} - 1 ))
                fi
                ;;
            DOWN|[jJ])
                if [ "$cursor" -lt $(( ${#items[@]} - 1 )) ]; then
                    cursor=$(( cursor + 1 ))
                else
                    cursor=0
                fi
                ;;
            ENTER|SPACE)
                local selected_str="${items[$cursor]}"
                case "$selected_str" in
                    *"1."*)
                        OPT_SDDM=$([ "$OPT_SDDM" = true ] && echo false || echo true)
                        if [ "$OPT_SDDM" = true ] && [ -n "$current_dm" ] && [ "$current_dm" != "sddm" ]; then
                            REPLACE_DM=true
                        fi
                        ;;
                    *"2."*)
                        REPLACE_DM=$([ "$REPLACE_DM" = true ] && echo false || echo true)
                        ;;
                    *"3."*)
                        SDDM_WAYLAND=$([ "$SDDM_WAYLAND" = true ] && echo false || echo true)
                        ;;
                    *"4."*)
                        break
                        ;;
                esac
                ;;
            ESC|[qQ])
                break
                ;;
        esac
    done
}

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
    "deckcraft:DeckCraft (Native Microsoft PowerPoint alternative)"
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
SELECTED_ADDITIONAL_PKGS=()

toggle_additional_pkg() {
    local target="$1"
    local updated=()
    local found=false
    for p in "${SELECTED_ADDITIONAL_PKGS[@]}"; do
        if [ "$p" == "$target" ]; then
            found=true
        else
            updated+=("$p")
        fi
    done
    if [ "$found" = false ]; then
        updated+=("$target")
    fi
    SELECTED_ADDITIONAL_PKGS=("${updated[@]}")
}

count_selected_in_category() {
    local -n arr="$1"
    local count=0
    for entry in "${arr[@]}"; do
        local pkg="${entry%%:*}"
        if [[ " ${SELECTED_ADDITIONAL_PKGS[*]} " =~ " ${pkg} " ]]; then
            count=$(( count + 1 ))
        fi
    done
    echo "$count"
}

category_items_menu() {
    local cat_title="$1"
    local -n cat_pkgs="$2"
    local cursor=0

    draw_banner
    draw_status_bar " Additional packages > $cat_title " " Toggle packages, then select Back "
    stty -echo 2>/dev/null || true
    printf "\e[?25l"
    printf "\n%s%s=== $cat_title ===%s\n\n" "$BOLD" "$C_CYAN" "$RESET"

    local rendered_lines=0

    while true; do
        local items=()
        for idx in "${!cat_pkgs[@]}"; do
            local entry="${cat_pkgs[$idx]}"
            local pkg="${entry%%:*}"
            local label="${entry#*:}"
            local check="${DIM}[ ]${RESET}"
            if [[ " ${SELECTED_ADDITIONAL_PKGS[*]} " =~ " ${pkg} " ]]; then
                check="${C_GREEN}[✓]${RESET}"
            fi
            local num=$(( idx + 1 ))
            items+=("$num. $check $label")
        done
        local done_num=$(( ${#cat_pkgs[@]} + 1 ))
        items+=("$done_num. ${BOLD}${C_GREEN}$(t "installer.ui.done" "Back to Categories")${RESET}")

        if [ "$rendered_lines" -gt 0 ]; then
            printf "\033[%dA" "$rendered_lines"
        fi

        for i in "${!items[@]}"; do
            if [ "$i" -eq "$cursor" ]; then
                printf "\r\033[K%s%s ▸ %s%s\n" "$BOLD" "$C_CYAN" "$RESET" "${items[$i]}"
            else
                printf "\r\033[K    %s\n" "${items[$i]}"
            fi
        done
        rendered_lines=${#items[@]}

        local key
        key=$(read_key)

        case "$key" in
            UP|[kK])
                if [ "$cursor" -gt 0 ]; then
                    cursor=$(( cursor - 1 ))
                else
                    cursor=$(( ${#items[@]} - 1 ))
                fi
                ;;
            DOWN|[jJ])
                if [ "$cursor" -lt $(( ${#items[@]} - 1 )) ]; then
                    cursor=$(( cursor + 1 ))
                else
                    cursor=0
                fi
                ;;
            ESC|[qQ])
                break
                ;;
            ENTER|SPACE)
                if [ "$cursor" -eq ${#cat_pkgs[@]} ]; then
                    break
                else
                    local chosen_entry="${cat_pkgs[$cursor]}"
                    local chosen_pkg="${chosen_entry%%:*}"
                    toggle_additional_pkg "$chosen_pkg"
                fi
                ;;
            *)
                if [[ "$key" =~ ^[0-9]+$ ]]; then
                    local sel_idx=$(( key - 1 ))
                    if [ "$sel_idx" -ge 0 ] && [ "$sel_idx" -lt ${#cat_pkgs[@]} ]; then
                        local chosen_entry="${cat_pkgs[$sel_idx]}"
                        local chosen_pkg="${chosen_entry%%:*}"
                        toggle_additional_pkg "$chosen_pkg"
                    elif [ "$sel_idx" -eq ${#cat_pkgs[@]} ]; then
                        break
                    fi
                fi
                ;;
        esac
    done
}

additional_packages_menu() {
    local cursor=0

    while true; do
        draw_banner
        draw_status_bar "$(t "installer.ui.additional_pkgs_prompt" " Additional packages > ")" "$(t "installer.ui.additional_pkgs_header" " Select category, then choose packages ")"
        stty -echo 2>/dev/null || true
        printf "\e[?25l"
        printf "\n%s%s$(t "installer.ui.additional_pkgs_title" "=== Select package categories ===")%s\n\n" "$BOLD" "$C_CYAN" "$RESET"

        local rendered_lines=0

        while true; do
            local c_dev; c_dev=$(count_selected_in_category PKGS_DEVELOPMENT)
            local c_soc; c_soc=$(count_selected_in_category PKGS_SOCIAL)
            local c_brw; c_brw=$(count_selected_in_category PKGS_BROWSERS)
            local c_gam; c_gam=$(count_selected_in_category PKGS_GAMES)
            local c_off; c_off=$(count_selected_in_category PKGS_OFFICE)
            local c_med; c_med=$(count_selected_in_category PKGS_MEDIA)

            local s_dev="${DIM}[None]${RESET}"; [ "$c_dev" -gt 0 ] && s_dev="${C_GREEN}[$c_dev Selected]${RESET}"
            local s_soc="${DIM}[None]${RESET}"; [ "$c_soc" -gt 0 ] && s_soc="${C_GREEN}[$c_soc Selected]${RESET}"
            local s_brw="${DIM}[None]${RESET}"; [ "$c_brw" -gt 0 ] && s_brw="${C_GREEN}[$c_brw Selected]${RESET}"
            local s_gam="${DIM}[None]${RESET}"; [ "$c_gam" -gt 0 ] && s_gam="${C_GREEN}[$c_gam Selected]${RESET}"
            local s_off="${DIM}[None]${RESET}"; [ "$c_off" -gt 0 ] && s_off="${C_GREEN}[$c_off Selected]${RESET}"
            local s_med="${DIM}[None]${RESET}"; [ "$c_med" -gt 0 ] && s_med="${C_GREEN}[$c_med Selected]${RESET}"

            local items=()
            items+=("1. Development $s_dev")
            items+=("2. Social Media $s_soc")
            items+=("3. Web Browsers $s_brw")
            items+=("4. Games $s_gam")
            items+=("5. Office $s_off")
            items+=("6. Media & Entertainment $s_med")
            items+=("7. ${BOLD}${C_GREEN}$(t "installer.ui.done" "Done")${RESET}")

            if [ "$rendered_lines" -gt 0 ]; then
                printf "\033[%dA" "$rendered_lines"
            fi

            for i in "${!items[@]}"; do
                if [ "$i" -eq "$cursor" ]; then
                    printf "\r\033[K%s%s ▸ %s%s\n" "$BOLD" "$C_CYAN" "$RESET" "${items[$i]}"
                else
                    printf "\r\033[K    %s\n" "${items[$i]}"
                fi
            done
            rendered_lines=${#items[@]}

            local key
            key=$(read_key)

            case "$key" in
                UP|[kK])
                    if [ "$cursor" -gt 0 ]; then
                        cursor=$(( cursor - 1 ))
                    else
                        cursor=$(( ${#items[@]} - 1 ))
                    fi
                    ;;
                DOWN|[jJ])
                    if [ "$cursor" -lt $(( ${#items[@]} - 1 )) ]; then
                        cursor=$(( cursor + 1 ))
                    else
                        cursor=0
                    fi
                    ;;
                ESC|[qQ])
                    return 0
                    ;;
                ENTER|SPACE)
                    case "$cursor" in
                        0) category_items_menu "Development Packages" PKGS_DEVELOPMENT; break ;;
                        1) category_items_menu "Social Media Packages" PKGS_SOCIAL; break ;;
                        2) category_items_menu "Web Browsers" PKGS_BROWSERS; break ;;
                        3) category_items_menu "Game Packages" PKGS_GAMES; break ;;
                        4) category_items_menu "Office Packages" PKGS_OFFICE; break ;;
                        5) category_items_menu "Media & Entertainment" PKGS_MEDIA; break ;;
                        6) return 0 ;;
                    esac
                    ;;
                *)
                    case "$key" in
                        1) category_items_menu "Development Packages" PKGS_DEVELOPMENT; break ;;
                        2) category_items_menu "Social Media Packages" PKGS_SOCIAL; break ;;
                        3) category_items_menu "Web Browsers" PKGS_BROWSERS; break ;;
                        4) category_items_menu "Game Packages" PKGS_GAMES; break ;;
                        5) category_items_menu "Office Packages" PKGS_OFFICE; break ;;
                        6) category_items_menu "Media & Entertainment" PKGS_MEDIA; break ;;
                        7) return 0 ;;
                    esac
                    ;;
            esac
        done
    done
}

manage_keyboard_menu() {
    draw_banner
    stty -echo 2>/dev/null || true
    printf "\e[?25l"
    printf "%s%s=== Keyboard Layout & Switch Shortcut ===%s\n\n" "$BOLD" "$C_CYAN" "$RESET"

    local cursor=0
    local rendered_lines=0

    while true; do
        local S_TOGGLE="Alt+Shift / Shift+Alt [Recommended]"
        case "$KEYBOARD_TOGGLE" in
            alt_shift)  S_TOGGLE="Alt+Shift / Shift+Alt [Recommended]" ;;
            ctrl_shift) S_TOGGLE="Ctrl+Shift / Shift+Ctrl" ;;
            win_space)  S_TOGGLE="Super+Space / Win+Space" ;;
            caps_lock)  S_TOGGLE="Caps Lock" ;;
        esac

        local items=()
        items+=("1. Switch Shortcut: ${BOLD}${C_GREEN}[$S_TOGGLE]${RESET}")
        items+=("2. Layouts: ${BOLD}${C_GREEN}[$KEYBOARD_LAYOUT]${RESET}")
        items+=("3. ${BOLD}${C_GREEN}$(t "installer.ui.done" "Back to Main Menu")${RESET}")

        if [ "$rendered_lines" -gt 0 ]; then
            printf "\033[%dA" "$rendered_lines"
        fi

        for i in "${!items[@]}"; do
            if [ "$i" -eq "$cursor" ]; then
                printf "\r\033[K%s%s ▸ %s%s\n" "$BOLD" "$C_CYAN" "$RESET" "${items[$i]}"
            else
                printf "\r\033[K    %s\n" "${items[$i]}"
            fi
        done
        rendered_lines=${#items[@]}

        local key
        key=$(read_key)

        case "$key" in
            UP|[kK])
                if [ "$cursor" -gt 0 ]; then
                    cursor=$(( cursor - 1 ))
                else
                    cursor=$(( ${#items[@]} - 1 ))
                fi
                ;;
            DOWN|[jJ])
                if [ "$cursor" -lt $(( ${#items[@]} - 1 )) ]; then
                    cursor=$(( cursor + 1 ))
                else
                    cursor=0
                fi
                ;;
            ENTER|SPACE)
                local selected_str="${items[$cursor]}"
                case "$selected_str" in
                    *"1."*)
                        case "$KEYBOARD_TOGGLE" in
                            alt_shift)  KEYBOARD_TOGGLE="ctrl_shift" ;;
                            ctrl_shift) KEYBOARD_TOGGLE="win_space" ;;
                            win_space)  KEYBOARD_TOGGLE="caps_lock" ;;
                            caps_lock)  KEYBOARD_TOGGLE="alt_shift" ;;
                            *)          KEYBOARD_TOGGLE="alt_shift" ;;
                        esac
                        ;;
                    *"2."*)
                        case "$KEYBOARD_LAYOUT" in
                            "us,ru") KEYBOARD_LAYOUT="us" ;;
                            "us")    KEYBOARD_LAYOUT="us,ua" ;;
                            "us,ua") KEYBOARD_LAYOUT="us,by" ;;
                            "us,by") KEYBOARD_LAYOUT="us,kz" ;;
                            "us,kz") KEYBOARD_LAYOUT="us,de" ;;
                            *)       KEYBOARD_LAYOUT="us,ru" ;;
                        esac
                        ;;
                    *"3."*)
                        break
                        ;;
                esac
                ;;
            "1")
                case "$KEYBOARD_TOGGLE" in
                    alt_shift)  KEYBOARD_TOGGLE="ctrl_shift" ;;
                    ctrl_shift) KEYBOARD_TOGGLE="win_space" ;;
                    win_space)  KEYBOARD_TOGGLE="caps_lock" ;;
                    caps_lock)  KEYBOARD_TOGGLE="alt_shift" ;;
                    *)          KEYBOARD_TOGGLE="alt_shift" ;;
                esac
                ;;
            "2")
                case "$KEYBOARD_LAYOUT" in
                    "us,ru") KEYBOARD_LAYOUT="us" ;;
                    "us")    KEYBOARD_LAYOUT="us,ua" ;;
                    "us,ua") KEYBOARD_LAYOUT="us,by" ;;
                    "us,by") KEYBOARD_LAYOUT="us,kz" ;;
                    "us,kz") KEYBOARD_LAYOUT="us,de" ;;
                    *)       KEYBOARD_LAYOUT="us,ru" ;;
                esac
                ;;
            "3"|ESC|[qQ])
                break
                ;;
        esac
    done
}

run_installer_ui() {
    if [ "${NONINTERACTIVE:-0}" = "1" ] || [ "${AUTO_INSTALL:-0}" = "1" ]; then
        if [ ${#SELECTED_COMPOSITORS[@]} -eq 0 ]; then
            SELECTED_COMPOSITORS=("hyprland" "driftwm" "niri" "sway" "mango")
        fi
        OPT_SDDM="${OPT_SDDM:-true}"
        INSTALL_FULL_WALLPAPERS="${INSTALL_FULL_WALLPAPERS:-true}"
        ENABLE_TELEMETRY="${ENABLE_TELEMETRY:-false}"
        return 0
    fi

    local cursor=0

    while true; do
        draw_banner
        stty -echo 2>/dev/null || true
        printf "\e[?25l"

        local rendered_lines=0

        while true; do
            local COMP_MENU_ITEM=""
            if [ "$MULTIPLE_COMPOSITORS_DETECTED" = true ]; then
                if [ ${#SELECTED_COMPOSITORS[@]} -eq 0 ]; then
                    COMP_MENU_ITEM="${C_RED}$(t "installer.ui.target_compositor_none")${RESET}"
                else
                    COMP_MENU_ITEM="${C_GREEN}$(t "installer.ui.target_compositor_selected" "comps=$(IFS=, ; echo "${SELECTED_COMPOSITORS[*]}")")${RESET}"
                fi
            elif [ "$UNSUPPORTED_COMPOSITOR_DETECTED" = true ]; then
                if [ ${#SELECTED_COMPOSITORS[@]} -eq 0 ]; then
                    COMP_MENU_ITEM="${C_RED}$(t "installer.ui.target_compositor_req" "label=${DETECTED_COMPOSITOR_LABEL}")${RESET}"
                else
                    COMP_MENU_ITEM="$(t "installer.ui.target_compositor_label" "comps=$(IFS=, ; echo "${SELECTED_COMPOSITORS[*]}")")"
                fi
            else
                if [ ${#SELECTED_COMPOSITORS[@]} -eq 0 ]; then
                    COMP_MENU_ITEM="${C_RED}$(t "installer.ui.target_compositor_req" "label=${DETECTED_COMPOSITOR_LABEL}")${RESET}"
                else
                    COMP_MENU_ITEM="$(t "installer.ui.target_compositor_label" "comps=$(IFS=, ; echo "${SELECTED_COMPOSITORS[*]}")")"
                fi
            fi

            local S_SDDM="${DIM}[OFF]${RESET}"
            local S_TEL="${DIM}[OFF]${RESET}"
            local S_WP="${DIM}[3 Random]${RESET}"
            local S_ADD="${DIM}[None]${RESET}"
            local S_KB="${C_GREEN}[Alt+Shift ($KEYBOARD_LAYOUT)]${RESET}"
            case "$KEYBOARD_TOGGLE" in
                ctrl_shift) S_KB="${C_GREEN}[Ctrl+Shift ($KEYBOARD_LAYOUT)]${RESET}" ;;
                win_space)  S_KB="${C_GREEN}[Super+Space ($KEYBOARD_LAYOUT)]${RESET}" ;;
                caps_lock)  S_KB="${C_GREEN}[Caps Lock ($KEYBOARD_LAYOUT)]${RESET}" ;;
            esac

            [ "$OPT_SDDM" = true ] && S_SDDM="${C_GREEN}[ON]${RESET}"
            [ "$ENABLE_TELEMETRY" = true ] && S_TEL="${C_GREEN}[ON]${RESET}"
            [ "$INSTALL_FULL_WALLPAPERS" = true ] && S_WP="${C_GREEN}[Full Pack]${RESET}"
            [ ${#SELECTED_ADDITIONAL_PKGS[@]} -gt 0 ] && S_ADD="${C_GREEN}[${#SELECTED_ADDITIONAL_PKGS[@]} Selected]${RESET}"

            local items=()
            items+=("1. $(t "installer.ui.menu_overview" "count=${#REQUIRED_PKGS[@]}")")
            items+=("2. $COMP_MENU_ITEM")
            items+=("3. $(t "installer.ui.menu_sddm") $S_SDDM")
            items+=("4. $(t "installer.ui.menu_wallpapers") $S_WP")
            items+=("5. $(t "installer.ui.menu_additional_pkgs" "Additional Packages") $S_ADD")
            items+=("6. $(t "installer.ui.menu_keyboard" "Keyboard Layout & Shortcut") $S_KB")
            items+=("7. $(t "installer.ui.menu_telemetry") $S_TEL")

            if [[ "$INSTALL_STATE" == "current" ]]; then
                items+=("8. ${BOLD}${C_GREEN}$(t "installer.ui.menu_update")${RESET}")
                items+=("9. ${BOLD}${C_YELLOW}$(t "installer.ui.menu_reinstall")${RESET}")
                items+=("10. ${DIM}$(t "installer.ui.menu_exit")${RESET}")
            else
                items+=("8. ${BOLD}${C_GREEN}$(t "installer.ui.menu_install")${RESET}")
                items+=("9. ${DIM}$(t "installer.ui.menu_exit")${RESET}")
            fi

            if [ "$rendered_lines" -gt 0 ]; then
                printf "\033[%dA" "$rendered_lines"
            fi

            for i in "${!items[@]}"; do
                if [ "$i" -eq "$cursor" ]; then
                    printf "\r\033[K%s%s ▸ %s%s\n" "$BOLD" "$C_CYAN" "$RESET" "${items[$i]}"
                else
                    printf "\r\033[K    %s\n" "${items[$i]}"
                fi
            done
            rendered_lines=${#items[@]}

            local key
            key=$(read_key)

            case "$key" in
                UP|[kK])
                    if [ "$cursor" -gt 0 ]; then
                        cursor=$(( cursor - 1 ))
                    else
                        cursor=$(( ${#items[@]} - 1 ))
                    fi
                    ;;
                DOWN|[jJ])
                    if [ "$cursor" -lt $(( ${#items[@]} - 1 )) ]; then
                        cursor=$(( cursor + 1 ))
                    else
                        cursor=0
                    fi
                    ;;
                "1")
                    show_package_overview
                    break
                    ;;
                "2")
                    manage_compositors_menu
                    break
                    ;;
                "3")
                    manage_sddm_menu
                    break
                    ;;
                "4")
                    INSTALL_FULL_WALLPAPERS=$([ "$INSTALL_FULL_WALLPAPERS" = true ] && echo false || echo true)
                    ;;
                "5")
                    additional_packages_menu
                    break
                    ;;
                "6")
                    manage_keyboard_menu
                    break
                    ;;
                "7")
                    ENABLE_TELEMETRY=$([ "$ENABLE_TELEMETRY" = true ] && echo false || echo true)
                    ;;
                "8")
                    if [ ${#SELECTED_COMPOSITORS[@]} -eq 0 ]; then
                        printf "\n%s[!] %s%s\n" "$C_RED" "$(t "installer.ui.error_no_compositor")" "$RESET"
                        sleep 1.5
                        break
                    fi
                    IS_REINSTALL=false
                    cleanup_terminal
                    return 0
                    ;;
                "9")
                    if [[ "$INSTALL_STATE" == "current" ]]; then
                        if [ ${#SELECTED_COMPOSITORS[@]} -eq 0 ]; then
                            printf "\n%s[!] %s%s\n" "$C_RED" "$(t "installer.ui.error_no_compositor")" "$RESET"
                            sleep 1.5
                            break
                        fi
                        IS_REINSTALL=true
                        cleanup_terminal
                        return 0
                    else
                        cleanup_terminal
                        clear 2>/dev/null || true
                        exit 0
                    fi
                    ;;
                "10")
                    if [[ "$INSTALL_STATE" == "current" ]]; then
                        cleanup_terminal
                        clear 2>/dev/null || true
                        exit 0
                    fi
                    ;;
                ESC|[qQ])
                    cleanup_terminal
                    clear 2>/dev/null || true
                    exit 0
                    ;;
                ENTER|SPACE)
                    local sel="${items[$cursor]}"
                    case "$sel" in
                        *"1."*)
                            show_package_overview
                            break
                            ;;
                        *"2."*)
                            manage_compositors_menu
                            break
                            ;;
                        *"3."*)
                            manage_sddm_menu
                            break
                            ;;
                        *"4."*)
                            INSTALL_FULL_WALLPAPERS=$([ "$INSTALL_FULL_WALLPAPERS" = true ] && echo false || echo true)
                            ;;
                        *"5."*)
                            additional_packages_menu
                            break
                            ;;
                        *"6."*)
                            manage_keyboard_menu
                            break
                            ;;
                        *"7."*)
                            ENABLE_TELEMETRY=$([ "$ENABLE_TELEMETRY" = true ] && echo false || echo true)
                            ;;
                        *"8."*)
                            if [ ${#SELECTED_COMPOSITORS[@]} -eq 0 ]; then
                                printf "\n%s[!] %s%s\n" "$C_RED" "$(t "installer.ui.error_no_compositor")" "$RESET"
                                sleep 1.5
                                break
                            fi
                            IS_REINSTALL=false
                            cleanup_terminal
                            return 0
                            ;;
                        *"9."*)
                            if [[ "$INSTALL_STATE" == "current" ]]; then
                                if [ ${#SELECTED_COMPOSITORS[@]} -eq 0 ]; then
                                    printf "\n%s[!] %s%s\n" "$C_RED" "$(t "installer.ui.error_no_compositor")" "$RESET"
                                    sleep 1.5
                                    break
                                fi
                                IS_REINSTALL=true
                                cleanup_terminal
                                return 0
                            else
                                cleanup_terminal
                                clear 2>/dev/null || true
                                exit 0
                            fi
                            ;;
                        *"10."*)
                            if [[ "$INSTALL_STATE" == "current" ]]; then
                                cleanup_terminal
                                clear 2>/dev/null || true
                                exit 0
                            fi
                            ;;
                    esac
                    ;;
            esac
        done
    done
}

draw_completion_screen() {
    local target_ver="$1"
    local target_commit="$2"
    cleanup_terminal
    clear 2>/dev/null || true
    printf "%s%s" "$BOLD" "$C_GREEN"
    cat << "EOF"
 ___ _  _ ___ _____ _   _     _ _____ ___ ___  _  _    ___ ___  __  __ ___ _    ___ _____ ___ 
|_ _| \| / __|_   _/_\ | |   /_\_   _|_ _/ _ \| \| |  / __/ _ \ | \/  | _ \ |  | __|_   _| __|
 | || .` \__ \ | |/ _ \| |__| _ \| |  | | (_) | .` | | (_| (_) | |\/| |  _/ |__| _|  | | | _| 
|___|_|\_|___/ |_/_/ \_\____/_/ \_\_| |___\___/|_|\_|  \___\___/|_|  |_|_| |____|___| |_| |___|
EOF
    printf "%s\n\n" "$RESET"
    printf "%s%s  %s%s\n\n" "$BOLD" "$C_CYAN" "$(t "installer.ui.tagline")" "$RESET"
    printf "%s%s================================================================================%s\n" "$BOLD" "$C_BLUE" "$RESET"
    printf " %s%sGitHub:%s   https://github.com/%s\n" "$BOLD" "$C_GREEN" "$RESET" "$REPO_SLUG"
    printf " %s%sTelegram:%s https://t.me/Nathant16\n" "$BOLD" "$C_CYAN" "$RESET"
    printf "%s%s================================================================================%s\n\n" "$BOLD" "$C_BLUE" "$RESET"
    printf "%s%s%s\n" "$C_GREEN" "$(t "installer.ui.installed_success" "ver=$target_ver" "commit=$target_commit")" "$RESET"
    if [ ${#FAILED_PKGS[@]} -gt 0 ]; then
        printf "\n%s%s%s%s\n" "$BOLD" "$C_RED" "$(t "installer.ui.failed_packages")" "$RESET"
        for fp in "${FAILED_PKGS[@]}"; do
            printf "  - %s%s%s\n" "$C_YELLOW" "$fp" "$RESET"
        done
    fi
    printf "\n%s\n\n" "$(t "installer.ui.restart_prompt")"

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
