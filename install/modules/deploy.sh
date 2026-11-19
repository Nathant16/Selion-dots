#!/usr/bin/env bash

EXTRA_CONFIGS=(
    "kitty"
    "fastfetch"
    "fish"
    "starship.toml"
)

render_wallpaper_progress() {
    local current="$1"
    local total="$2"
    local label="${3:-Installing wallpapers}"
    local bar_width=30
    local percent=0
    if [ "$total" -gt 0 ]; then
        percent=$(( current * 100 / total ))
    fi
    local filled=0
    if [ "$total" -gt 0 ]; then
        filled=$(( current * bar_width / total ))
    fi
    local empty=$(( bar_width - filled ))
    local bar_fill=""
    local bar_empty=""
    if [ "$filled" -gt 0 ]; then
        bar_fill=$(printf "%*s" "$filled" "" | tr ' ' '=')
    fi
    if [ "$empty" -gt 0 ]; then
        bar_empty=$(printf "%*s" "$empty" "" | tr ' ' ' ')
    fi
    printf "\r\e[36m[ INFO ]\e[0m %s \e[32m[%s%s]\e[0m %3d%% (%d/%d)" "$label" "$bar_fill" "$bar_empty" "$percent" "$current" "$total"
}

get_wallpaper_dir() {
    local cfg_dir=""
    local settings_file="$HOME/.config/serpantinum/settings.json"
    if [ -f "$settings_file" ] && command -v jq >/dev/null 2>&1; then
        cfg_dir="$(jq -r '.wallpaperDir // .wallpaper_dir // empty' "$settings_file" 2>/dev/null || true)"
        if [[ -n "$cfg_dir" && "$cfg_dir" != "null" ]]; then
            cfg_dir="${cfg_dir/#\~/$HOME}"
            echo "$cfg_dir"
            return 0
        fi
    fi

    if [ -n "$WALLPAPER_DIR" ]; then
        echo "${WALLPAPER_DIR/#\~/$HOME}"
        return 0
    fi

    local user_pics=""
    if [ -f "$HOME/.config/user-dirs.dirs" ]; then
        user_pics=$(grep '^XDG_PICTURES_DIR' "$HOME/.config/user-dirs.dirs" 2>/dev/null | cut -d= -f2 | tr -d '"' | sed "s|\$HOME|$HOME|g")
    fi
    if [[ -z "$user_pics" || "$user_pics" == "$HOME" ]]; then
        if command -v xdg-user-dir &>/dev/null; then
            user_pics="$(xdg-user-dir PICTURES 2>/dev/null || true)"
        fi
    fi
    if [[ -z "$user_pics" || "$user_pics" == "$HOME" ]]; then
        user_pics="$HOME/Pictures"
    fi
    user_pics="${user_pics%/}"

    # Prefer existing wallpaper directory (Wallpapers vs Wallpaper)
    if [ -d "$user_pics/Wallpapers" ]; then
        echo "$user_pics/Wallpapers"
        return 0
    elif [ -d "$user_pics/Wallpaper" ]; then
        echo "$user_pics/Wallpaper"
        return 0
    elif [ -d "$HOME/Pictures/Wallpapers" ]; then
        echo "$HOME/Pictures/Wallpapers"
        return 0
    elif [ -d "$HOME/Pictures/Wallpaper" ]; then
        echo "$HOME/Pictures/Wallpaper"
        return 0
    fi

    echo "$user_pics/Wallpapers"
}

install_wallpapers() {
    local full_pack="${1:-true}"
    local wallpaper_dir
    wallpaper_dir=$(get_wallpaper_dir)
    local selion_dir="$wallpaper_dir/Selion"
    local wallpaper_repo="https://github.com/Nathant16/Selion-dots.git"
    local wallpaper_branch="wallpapers"
    local clone_dir="${XDG_CACHE_HOME:-"$HOME/.cache"}/serpantinum-wallpapers"

    mkdir -p "$wallpaper_dir" "$selion_dir"

    # Clean up redundant legacy symlink ~/Pictures/Wallpaper -> Wallpapers
    local pics_parent="$(dirname "$wallpaper_dir")"
    if [ -L "$pics_parent/Wallpaper" ]; then
        local link_target
        link_target="$(readlink "$pics_parent/Wallpaper" 2>/dev/null || true)"
        if [ "$link_target" = "Wallpapers" ] || [ "$link_target" = "$wallpaper_dir" ] || [ "$link_target" = "Wallpapers/" ]; then
            rm -f "$pics_parent/Wallpaper"
        fi
    fi

    local sync_success=false
    local legacy_marker="${XDG_STATE_HOME:-"$HOME/.local/state"}/serpantinum/legacy_wallpapers_cleaned"
    mkdir -p "$(dirname "$legacy_marker")"

    if [ -d "$clone_dir/.git" ]; then
        local current_origin current_branch
        current_origin=$(git -C "$clone_dir" remote get-url origin 2>/dev/null || true)
        current_branch=$(git -C "$clone_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || true)

        if [[ "$current_origin" != "$wallpaper_repo" || "$current_branch" != "$wallpaper_branch" ]]; then
            # Clean up only files copied from the legacy upstream wallpaper repo, leaving user files untouched
            if [[ "$current_origin" == *"shell-wallpapers"* ]]; then
                while IFS= read -r -d '' old_file; do
                    local old_name="${old_file##*/}"
                    if [ -f "$wallpaper_dir/$old_name" ]; then
                        rm -f "$wallpaper_dir/$old_name"
                    fi
                done < <(find "$clone_dir" -type f ! -path '*/.git/*' \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.webp" \) -print0 2>/dev/null)
                touch "$legacy_marker"
            fi
            rm -rf "$clone_dir"
        elif git -C "$clone_dir" fetch --depth 1 origin "$wallpaper_branch" 2>/dev/null; then
            if git -C "$clone_dir" reset --hard FETCH_HEAD 2>/dev/null || \
               git -C "$clone_dir" reset --hard "origin/$wallpaper_branch" 2>/dev/null; then
                sync_success=true
            fi
        fi
    fi

    if [ ! -f "$legacy_marker" ]; then
        if [ -n "$(find "$wallpaper_dir" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.webp" \) -print -quit 2>/dev/null)" ]; then
            if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
                local legacy_tree
                legacy_tree="$(curl -fsSL --connect-timeout 5 "https://api.github.com/repos/ilyamiro/shell-wallpapers/git/trees/HEAD?recursive=1" 2>/dev/null || true)"
                if [ -n "$legacy_tree" ]; then
                    while IFS= read -r legacy_rel; do
                        [[ -z "$legacy_rel" ]] && continue
                        local legacy_name="${legacy_rel##*/}"
                        [ -f "$wallpaper_dir/$legacy_name" ] && rm -f "$wallpaper_dir/$legacy_name"
                    done < <(printf '%s' "$legacy_tree" | jq -r '.tree[]? | select(.type=="blob") | .path | select(test("\\.(jpg|jpeg|png|gif|webp)$"; "i"))' 2>/dev/null || true)
                fi
            fi
        fi
        touch "$legacy_marker"
    fi

    if [ "$sync_success" != true ]; then
        rm -rf "$clone_dir"
        echo -e "\n\e[36m[ INFO ]\e[0m Cloning wallpapers repository..."
        if ! git clone --depth 1 --branch "$wallpaper_branch" --single-branch --progress "$wallpaper_repo" "$clone_dir"; then
            echo -e "\e[33m[ WARN ]\e[0m Failed to clone wallpapers repository. Retrying..."
            sleep 2
            git clone --depth 1 --branch "$wallpaper_branch" --single-branch --progress "$wallpaper_repo" "$clone_dir" || true
        fi
    fi

    local src_dir="$clone_dir"
    if [ -d "$clone_dir/images" ]; then
        src_dir="$clone_dir/images"
    fi

    if [ ! -d "$src_dir" ]; then
        echo -e "\e[33m[ WARN ]\e[0m Wallpapers could not be downloaded. You can install them later."
        return 0
    fi

    if [ "$full_pack" = true ]; then
        local files=()
        declare -A expected_names=()
        while IFS= read -r -d '' f; do
            [[ -n "$f" ]] || continue
            files+=("$f")
            expected_names["${f##*/}"]=1
        done < <(find "$src_dir" -type f ! -path '*/.git/*' \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.webp" \) -print0 2>/dev/null)

        local total=${#files[@]}
        local count=0

        if [ "$total" -gt 0 ]; then
            # Remove stale wallpapers inside Selion/ that are no longer in the upstream wallpapers branch
            while IFS= read -r -d '' existing; do
                local ex_name="${existing##*/}"
                if [[ -z "${expected_names[$ex_name]:-}" ]]; then
                    rm -f "$existing"
                fi
            done < <(find "$selion_dir" -maxdepth 1 -type f -print0 2>/dev/null)

            for file in "${files[@]}"; do
                local dest_file="$selion_dir/${file##*/}"
                if [ ! -f "$dest_file" ] || ! cmp -s "$file" "$dest_file" 2>/dev/null; then
                    cp -f "$file" "$dest_file" 2>/dev/null || true
                fi
                count=$((count + 1))
                render_wallpaper_progress "$count" "$total" "Installing wallpapers"
            done
            echo ""
        fi
    else
        if [ -z "$(ls -A "$selion_dir" 2>/dev/null | grep -iE '\.(jpg|jpeg|png|gif|webp)$')" ]; then
            local random_pics=()
            while IFS= read -r pic; do
                [[ -n "$pic" ]] && random_pics+=("$pic")
            done < <(find "$src_dir" -type f ! -path '*/.git/*' \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.webp" \) 2>/dev/null | shuf -n 3)

            local total=${#random_pics[@]}
            local count=0

            if [ "$total" -gt 0 ]; then
                for pic in "${random_pics[@]}"; do
                    cp -f "$pic" "$selion_dir/" 2>/dev/null || true
                    count=$((count + 1))
                    render_wallpaper_progress "$count" "$total" "Installing wallpapers"
                done
                echo ""
            fi
        fi
    fi

    local cache_dir="${XDG_CACHE_HOME:-"$HOME/.cache"}/serpantinum/wallpaper"
    mkdir -p "$cache_dir"

    # Clean up legacy duplicate files in wallpaper_dir root
    if [ -d "$selion_dir" ]; then
        [ -f "$wallpaper_dir/default.png" ] && rm -f "$wallpaper_dir/default.png"
        for root_img in "$wallpaper_dir"/*; do
            [ -f "$root_img" ] || continue
            local fname="$(basename "$root_img")"
            if [ -f "$selion_dir/$fname" ]; then
                if cmp -s "$root_img" "$selion_dir/$fname" 2>/dev/null; then
                    rm -f "$root_img"
                fi
            fi
        done
    fi

    # Pre-index wallpapers for fast loading in WallpaperPicker
    local run_dir="${XDG_RUNTIME_DIR:-"/run/user/$(id -u)"}/serpantinum/wallpaper"
    mkdir -p "$run_dir"
    local p_root="${PROJECT_ROOT:-"$HOME/.local/share/serpantinum"}"
    local indexer_script="$p_root/src/scripts/wallpaper/recursive_index.py"
    if [ ! -f "$indexer_script" ]; then
        indexer_script="$HOME/.local/share/serpantinum/src/scripts/wallpaper/recursive_index.py"
    fi
    if [ -f "$indexer_script" ]; then
        echo -e "\e[36m[ INFO ]\e[0m Pre-indexing wallpapers..."
        python3 "$indexer_script" "$wallpaper_dir" "$cache_dir" "$run_dir" "1" >/dev/null 2>&1 || true
    fi

    # Ensure a default wallpaper state exists so first boot never renders a black screen
    local default_wp="$selion_dir/1.png"
    if [ ! -f "$default_wp" ]; then
        default_wp="$(find "$selion_dir" "$wallpaper_dir" "$pics_parent/Wallpapers" -maxdepth 2 -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.webp" \) 2>/dev/null | sort -V | head -n 1)"
    fi
    if [ -n "$default_wp" ] && [ -f "$default_wp" ]; then
        local def_state="$cache_dir/current_default"
        printf '%s' "$default_wp" > "$def_state"
        printf '%s\n' "${default_wp##*/}" > "${def_state}_name"
        for cur_link in /sys/class/drm/card*-*/status; do
            if [ -f "$cur_link" ] && grep -q '^connected$' "$cur_link" 2>/dev/null; then
                local conn_dir
                conn_dir="$(dirname "$cur_link")"
                local out_name
                out_name="$(basename "$conn_dir" | sed -E 's/^card[0-9]+-//')"
                if [ -n "$out_name" ]; then
                    local out_file="$cache_dir/current_$out_name"
                    if [ ! -f "$out_file" ] || [ ! -s "$out_file" ]; then
                        printf '%s' "$default_wp" > "$out_file"
                        printf '%s\n' "${default_wp##*/}" > "${out_file}_name"
                    fi
                fi
            fi
        done
    fi
}

resolve_sddm_backend() {
    local requested_wayland="${1:-false}"
    local wayland_cmd="" bin

    if bin="$(find_sddm_binary weston)"; then
        wayland_cmd="$bin --shell=kiosk"
    elif bin="$(find_sddm_binary kwin_wayland)"; then
        wayland_cmd="$bin --no-global-shortcuts --no-lockscreen --locale1"
    fi

    local has_xorg=false
    if sddm_has_xorg; then
        has_xorg=true
    fi

    if [ "$requested_wayland" = true ]; then
        if [ -n "$wayland_cmd" ]; then
            printf 'wayland\n%s\n' "$wayland_cmd"
            return 0
        elif [ "$has_xorg" = true ]; then
            echo -e "  \e[33m[ WARN ]\e[0m $(t "installer.deploy.sddm_no_wayland_compositor")" >&2
            echo "x11"
            return 0
        fi
    else
        if [ "$has_xorg" = true ]; then
            echo "x11"
            return 0
        elif [ -n "$wayland_cmd" ]; then
            echo -e "  \e[33m[ WARN ]\e[0m $(t "installer.deploy.sddm_no_xorg" "compositor=${wayland_cmd%% *}")" >&2
            printf 'wayland\n%s\n' "$wayland_cmd"
            return 0
        fi
    fi

    echo -e "  \e[31m[ ERROR ]\e[0m $(t "installer.deploy.sddm_no_backend")" >&2
    return 1
}

configure_sddm_cursor() {
    local conf="$1" theme=""
    if [ -d /usr/share/icons/Windows-11M-Dark/cursors ] || [ -d "$TARGET_BASE/src/assets/cursors/Windows-11M-Dark/cursors" ]; then
        theme="Windows-11M-Dark"
    elif [ -d /usr/share/icons/Adwaita/cursors ]; then
        theme="Adwaita"
    else
        theme="$(find /usr/share/icons -mindepth 2 -maxdepth 2 -type d -name cursors 2>/dev/null | head -n 1 | xargs -r dirname | xargs -r basename)"
    fi
    [ -n "$theme" ] || return 0
    [ -f "$conf" ] || return 0
    if sudo grep -q "^CursorTheme=" "$conf" 2>/dev/null; then
        sudo sed -i "s/^CursorTheme=.*/CursorTheme=$theme/" "$conf" 2>/dev/null || true
    else
        sudo sed -i -e "/^ThemeDir=/a CursorTheme=$theme" "$conf" 2>/dev/null || true
    fi
    if sudo grep -q "^CursorSize=" "$conf" 2>/dev/null; then
        sudo sed -i "s/^CursorSize=.*/CursorSize=32/" "$conf" 2>/dev/null || true
    else
        sudo sed -i -e "/^ThemeDir=/a CursorSize=32" "$conf" 2>/dev/null || true
    fi
}

setup_sddm() {
    local project_root="$1"
    local install_state="${2:-$INSTALL_STATE}"
    local is_reinstall="${3:-$IS_REINSTALL}"

    if [ "$OPT_SDDM" != true ]; then
        return 0
    fi

    local sddm_display_server=""
    local sddm_compositor_cmd=""
    local backend_output=""
    if ! backend_output=$(resolve_sddm_backend "$SDDM_WAYLAND"); then
        echo -e "  \e[33m[ WARN ]\e[0m $(t "installer.deploy.sddm_skipped")" >&2
        return 0
    fi

    {
        read -r sddm_display_server
        read -r sddm_compositor_cmd || true
    } <<< "$backend_output"

    local is_update=false
    if [[ "$install_state" == "current" && "$is_reinstall" != "true" ]]; then
        is_update=true
    fi

    local init_sys="generic"
    if declare -f detect_init_system >/dev/null; then
        init_sys=$(detect_init_system)
    fi

    echo -e "\n\e[36m[ INFO ]\e[0m $(t "installer.deploy.configuring_sddm")"

    if [ "$is_update" != true ] && [ "$REPLACE_DM" = true ]; then
        local dms=("gdm" "gdm3" "lightdm" "lxdm" "lxdm-gtk3" "ly" "greetd" "emptty")
        for dm in "${dms[@]}"; do
            if declare -f pm_disable_display_manager >/dev/null; then
                pm_disable_display_manager "$dm" "$init_sys"
            elif declare -f disable_system_service >/dev/null; then
                disable_system_service "$dm" "$init_sys"
            fi
            if pm_is_installed "$dm"; then
                echo "  $(t "installer.deploy.disabling_dm" "dm=$dm")"
                pm_remove_pkg "$dm"
            fi
        done
    fi

    sudo rm -rf /usr/share/sddm/themes/matugen-minimal
    sudo rm -rf /usr/share/sddm/themes/material-you
    sudo rm -f /etc/sddm.conf.d/*matugen*.conf
    sudo rm -f /etc/sddm.conf.d/*material-you*.conf
    sudo rm -f /etc/sddm.conf.d/*autologin*.conf

    if [ "$is_update" != true ] && [ -f /etc/sddm.conf ]; then
        sudo cp -a /etc/sddm.conf "/etc/sddm.conf.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
        sudo rm -f /etc/sddm.conf
    fi

    local sddm_theme_src="$project_root/config/sddm/themes/material-you"
    local sddm_theme_dest="/usr/share/sddm/themes/material-you"

    if [ -d "$sddm_theme_src" ]; then
        sudo mkdir -p "$sddm_theme_dest"
        sudo cp -r "$sddm_theme_src/." "$sddm_theme_dest/"
        sudo chmod -R 755 "$sddm_theme_dest"
        if [ -d "$sddm_theme_src/font" ]; then
            sudo mkdir -p /usr/share/fonts/TTF
            sudo cp -r "$sddm_theme_src/font/"*.ttf /usr/share/fonts/TTF/ 2>/dev/null || true
            fc-cache -f /usr/share/fonts >/dev/null 2>&1 || true
        fi
    fi

    sudo mkdir -p /etc/sddm.conf.d

    if [ "$sddm_display_server" = "wayland" ]; then
        cat <<EOF | sudo tee /etc/sddm.conf.d/10-material-you.conf > /dev/null
[Theme]
Current=material-you
ThemeDir=/usr/share/sddm/themes

[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_DISABLE_WINDOWDECORATION=1
InputMethod=

[Wayland]
CompositorCommand=$sddm_compositor_cmd
EOF
    else
        cat <<EOF | sudo tee /etc/sddm.conf.d/10-material-you.conf > /dev/null
[Theme]
Current=material-you
ThemeDir=/usr/share/sddm/themes

[General]
DisplayServer=x11
InputMethod=
EOF
    fi

    if [ "$PM_SDDM_CURSOR_FIX" = true ]; then
        configure_sddm_cursor /etc/sddm.conf.d/10-material-you.conf
    fi

    if declare -f pm_configure_sddm_session >/dev/null; then
        pm_configure_sddm_session /etc/sddm.conf.d/10-material-you.conf
    fi

    if declare -f pm_enable_display_manager >/dev/null; then
        pm_enable_display_manager "sddm" "$init_sys"
    elif [[ "$init_sys" == "systemd" ]]; then
        sudo systemctl enable sddm.service 2>/dev/null || sudo systemctl enable -f sddm.service 2>/dev/null || sudo systemctl enable sddm 2>/dev/null || true
    elif declare -f enable_system_service >/dev/null; then
        enable_system_service "sddm" "$init_sys"
    else
        case "$init_sys" in
            systemd)
                sudo systemctl enable sddm.service 2>/dev/null || sudo systemctl enable -f sddm.service 2>/dev/null || sudo systemctl enable sddm 2>/dev/null || true
                ;;
            openrc)
                sudo rc-update add sddm default 2>/dev/null || true
                ;;
            dinit)
                sudo dinitctl enable sddm 2>/dev/null || true
                ;;
            runit)
                if [ -d "/etc/sv/sddm" ]; then
                    sudo ln -sf "/etc/sv/sddm" /var/service/ 2>/dev/null || true
                fi
                ;;
            s6)
                sudo s6-rc-bundle-update -b add default sddm 2>/dev/null || true
                ;;
            *)
                sudo systemctl enable sddm.service -f 2>/dev/null || true
                ;;
        esac
    fi

    echo -e "  \e[32m$(t "installer.deploy.sddm_success")\e[0m"
}

setup_pam_service() {
    local pam_dir="/etc/pam.d"
    local target="$pam_dir/serpantinum"
    local base=""

    [ -d "$pam_dir" ] || return 0
    [ -e /etc/NIXOS ] && return 0

    for candidate in system-auth common-auth login; do
        if [ -f "$pam_dir/$candidate" ]; then
            base="$candidate"
            break
        fi
    done
    [ -n "$base" ] || return 0

    # Serpantinum lockscreen uses parallel PamContext sessions in Quickshell:
    # fpPam strictly requires dedicated biometric authentication (pam_fprintd + pam_deny, no password prompts).
    local content=""
    content+="-auth       sufficient   pam_fprintd.so"$'\n'
    content+="auth        required     pam_deny.so"$'\n'
    content+="account     include      $base"$'\n'

    if [ ! -f "$target" ] || [ "$(cat "$target" 2>/dev/null)" != "${content%$'\n'}" ]; then
        printf '%s' "$content" | sudo tee "$target" >/dev/null 2>&1 || true
        sudo chmod 644 "$target" 2>/dev/null || true
    fi

    # Also deploy serpantinum-nofp as standard password-only PAM service (no biometric hooks)
    local nofp_target="$pam_dir/serpantinum-nofp"
    local nofp_content=""
    nofp_content+="auth        include      $base"$'\n'
    nofp_content+="account     include      $base"$'\n'

    if [ ! -f "$nofp_target" ] || [ "$(cat "$nofp_target" 2>/dev/null)" != "${nofp_content%$'\n'}" ]; then
        printf '%s' "$nofp_content" | sudo tee "$nofp_target" >/dev/null 2>&1 || true
        sudo chmod 644 "$nofp_target" 2>/dev/null || true
    fi

    # Fix existing installations where grosshack was erroneously written to serpantinum
    if [ -f "$target" ] && grep -qs "pam_fprintd_grosshack" "$target"; then
        sudo sed -i 's/pam_fprintd_grosshack\.so/pam_fprintd.so/g' "$target" 2>/dev/null || true
    fi

    local fp_mod="pam_fprintd.so"
    if [ -f /usr/lib/security/pam_fprintd_grosshack.so ]; then
        fp_mod="pam_fprintd_grosshack.so"
    fi

    # Ensure fprintd service is enabled
    if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl enable fprintd.service 2>/dev/null || true
    fi

    # Configure sudo: allow typing password OR scanning fingerprint simultaneously
    if [ -f "$pam_dir/sudo" ]; then
        if [ "$fp_mod" = "pam_fprintd_grosshack.so" ]; then
            if grep -qs "pam_fprintd" "$pam_dir/sudo"; then
                sudo sed -i -E "s/pam_fprintd(_grosshack)?\.so/pam_fprintd_grosshack.so/g" "$pam_dir/sudo" 2>/dev/null || true
            else
                sudo sed -i "1s/^/-auth\t\tsufficient\tpam_fprintd_grosshack.so\n/" "$pam_dir/sudo" 2>/dev/null || true
            fi
        else
            # Standard pam_fprintd blocks terminal input without password prompt; remove it from sudo
            sudo sed -i '/pam_fprintd/d' "$pam_dir/sudo" 2>/dev/null || true
        fi
    fi

    # Configure polkit-1: allow typing password OR scanning fingerprint simultaneously (always standard pam_fprintd to avoid conversation errors)
    if [ ! -f "$pam_dir/polkit-1" ] && [ -f "/usr/lib/pam.d/polkit-1" ]; then
        sudo cp "/usr/lib/pam.d/polkit-1" "$pam_dir/polkit-1" 2>/dev/null || true
    fi
    if [ -f "$pam_dir/polkit-1" ]; then
        if grep -qs "pam_fprintd" "$pam_dir/polkit-1"; then
            sudo sed -i -E "s/pam_fprintd(_grosshack)?\.so/pam_fprintd.so/g" "$pam_dir/polkit-1" 2>/dev/null || true
        else
            sudo sed -i "1s/^/-auth       sufficient  pam_fprintd.so\n/" "$pam_dir/polkit-1" 2>/dev/null || true
        fi
    fi

    # Configure system-local-login
    if [ ! -f "$pam_dir/system-local-login" ] && [ -f "/usr/lib/pam.d/system-local-login" ]; then
        sudo cp "/usr/lib/pam.d/system-local-login" "$pam_dir/system-local-login" 2>/dev/null || true
    fi
    if [ -f "$pam_dir/system-local-login" ]; then
        if grep -qs "pam_fprintd" "$pam_dir/system-local-login"; then
            sudo sed -i -E "s/pam_fprintd(_grosshack)?\.so/$fp_mod/g" "$pam_dir/system-local-login" 2>/dev/null || true
        else
            sudo sed -i "1s/^/-auth      sufficient $fp_mod\n/" "$pam_dir/system-local-login" 2>/dev/null || true
        fi
    fi
}

configure_keyboard_layout() {
    local layout="${1:-${KEYBOARD_LAYOUT:-us,ru}}"
    local toggle="${2:-${KEYBOARD_TOGGLE:-alt_shift}}"

    local xkb_opts="grp:alt_shift_toggle,grp:ctrl_shift_toggle"
    case "$toggle" in
        ctrl_shift)
            xkb_opts="grp:ctrl_shift_toggle,grp:alt_shift_toggle"
            ;;
        win_space)
            xkb_opts="grp:win_space_toggle"
            ;;
        caps_lock)
            xkb_opts="grp:caps_toggle"
            ;;
        *)
            xkb_opts="grp:alt_shift_toggle,grp:ctrl_shift_toggle"
            ;;
    esac

    echo -e "\e[36m[ INFO ]\e[0m Configuring keyboard layout ($layout, $toggle)..."

    # Hyprland
    local hypr_input="$HOME/.config/hypr/default/input.lua"
    if [ -f "$hypr_input" ]; then
        sed -i -E "s/kb_layout = \"[^\"]*\"/kb_layout = \"$layout\"/" "$hypr_input" 2>/dev/null || true
        sed -i -E "s/kb_options = \"[^\"]*\"/kb_options = \"$xkb_opts\"/" "$hypr_input" 2>/dev/null || true
    fi

    # Sway
    local sway_input="$HOME/.config/sway/default/input"
    if [ -f "$sway_input" ]; then
        sed -i -E "s/xkb_layout \"[^\"]*\"/xkb_layout \"$layout\"/" "$sway_input" 2>/dev/null || true
        sed -i -E "s/xkb_options \"[^\"]*\"/xkb_options \"$xkb_opts\"/" "$sway_input" 2>/dev/null || true
    fi

    # Niri
    local niri_input="$HOME/.config/niri/default/input.kdl"
    if [ -f "$niri_input" ]; then
        sed -i -E "s/layout \"[^\"]*\"/layout \"$layout\"/" "$niri_input" 2>/dev/null || true
        sed -i -E "s/options \"[^\"]*\"/options \"$xkb_opts\"/" "$niri_input" 2>/dev/null || true
    fi

    # Mango
    local mango_input="$HOME/.config/mango/default/input.conf"
    if [ -f "$mango_input" ]; then
        sed -i -E "s/xkb_rules_layout=[^[:space:]]*/xkb_rules_layout=$layout/" "$mango_input" 2>/dev/null || true
        sed -i -E "s/xkb_rules_options=[^[:space:]]*/xkb_rules_options=$xkb_opts/" "$mango_input" 2>/dev/null || true
    fi

    # DriftWM
    local drift_config="$HOME/.config/driftwm/config.toml"
    if [ -f "$drift_config" ]; then
        sed -i -E "s/^layout = \"[^\"]*\"/layout = \"$layout\"/" "$drift_config" 2>/dev/null || true
        if ! grep -q '"shift+alt"' "$drift_config" 2>/dev/null; then
            sed -i '/"alt+shift" = "switch-layout next"/a "shift+alt" = "switch-layout next"' "$drift_config" 2>/dev/null || true
        fi
        if ! grep -q '"shift+ctrl"' "$drift_config" 2>/dev/null; then
            sed -i '/"ctrl+shift" = "switch-layout next"/a "shift+ctrl" = "switch-layout next"' "$drift_config" 2>/dev/null || true
        fi
    fi
}

configure_driftwm_bookmarks() {
    local compositors=("$@")
    if [[ " ${compositors[*]} " != *" driftwm "* ]]; then
        return 0
    fi

    local step=2500

    # Running DriftWM: move the live bookmarks into the Selion row 1..9.
    if command -v driftwm >/dev/null 2>&1 && timeout 3 driftwm msg bookmark --json >/dev/null 2>&1; then
        for i in 1 2 3 4 5 6 7 8 9; do
            driftwm msg bookmark "$i" "$(( (i - 1) * step ))" 0 >/dev/null 2>&1 || true
        done
        return 0
    fi

    # Not running: repair the durable session so the next DriftWM start
    # restores the row instead of the four default corners.
    local session_file="$HOME/.local/state/driftwm/session.json"
    [[ -f "$session_file" ]] || return 0

    python3 - "$session_file" "$step" <<'PY' 2>/dev/null || true
import json
import sys

path = sys.argv[1]
step = int(sys.argv[2])
try:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    sys.exit(0)
if not isinstance(data, dict):
    sys.exit(0)
data["bookmarks"] = {str(i): [(i - 1) * step, 0] for i in range(1, 10)}
try:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
except Exception:
    pass
PY
}

remove_settings_desktop_entry() {
    local data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
    local apps_dir="$data_home/applications"
    local icons_dir="$data_home/icons/hicolor"

    if [ -f "$apps_dir/serpantinum-settings.desktop" ]; then
        rm -f "$apps_dir/serpantinum-settings.desktop"
        if command -v update-desktop-database >/dev/null 2>&1; then
            update-desktop-database "$apps_dir" >/dev/null 2>&1 || true
        fi
    fi

    if [ -f "$icons_dir/scalable/apps/serpantinum-settings.svg" ]; then
        rm -f "$icons_dir/scalable/apps/serpantinum-settings.svg"
        if command -v gtk-update-icon-cache >/dev/null 2>&1; then
            gtk-update-icon-cache -qf "$icons_dir" >/dev/null 2>&1 || true
        fi
    fi
}

deploy_package() {
    local REPO_ROOT="$1"
    local OLD_COMMIT="$2"
    local NEW_COMMIT="$3"
    local IS_REINSTALL="$4"
    local INSTALL_STATE="$5"
    shift 5
    local COMPOSITORS=("$@")

    local TARGET_BASE="$HOME/.local/share/serpantinum"
    local BIN_DIR="$HOME/.local/bin"

    local is_update=false
    if [[ "$INSTALL_STATE" == "current" && "$IS_REINSTALL" != "true" ]]; then
        is_update=true
    fi

    local do_full_deploy=true

    if [ "$IS_REINSTALL" != "true" ] && [ -n "$OLD_COMMIT" ] && [ "$OLD_COMMIT" != "unknown" ] && [ -d "$REPO_ROOT/.git" ]; then
        if git -C "$REPO_ROOT" cat-file -e "$OLD_COMMIT" 2>/dev/null; then
            do_full_deploy=false
        fi
    fi

    if [ "$do_full_deploy" = true ]; then
        rm -rf "$TARGET_BASE"
        mkdir -p "$TARGET_BASE/bin" "$TARGET_BASE/src" "$BIN_DIR"

        if [ -d "$REPO_ROOT/bin" ] && [ "$(ls -A "$REPO_ROOT/bin" 2>/dev/null)" ]; then
            cp -r "$REPO_ROOT/bin/." "$TARGET_BASE/bin/"
            chmod +x "$TARGET_BASE/bin/"* 2>/dev/null || true
        fi

        if [ -d "$REPO_ROOT/src" ] && [ "$(ls -A "$REPO_ROOT/src" 2>/dev/null)" ]; then
            cp -r "$REPO_ROOT/src/." "$TARGET_BASE/src/"
            find "$TARGET_BASE/src/scripts" -type f \( -name "*.sh" -o -name "*.py" \) -exec chmod +x {} + 2>/dev/null || true
        fi

        for cfg in "${EXTRA_CONFIGS[@]}"; do
            local src_cfg="$REPO_ROOT/config/$cfg"
            local dest_cfg="$HOME/.config/$cfg"
            if [ "$is_update" != "true" ] || [ ! -e "$dest_cfg" ]; then
                if [ -d "$src_cfg" ]; then
                    mkdir -p "$dest_cfg"
                    cp -r "$src_cfg/." "$dest_cfg/"
                elif [ -f "$src_cfg" ]; then
                    mkdir -p "$(dirname "$dest_cfg")"
                    cp "$src_cfg" "$dest_cfg"
                fi
            fi
        done

        for comp in "${COMPOSITORS[@]}"; do
            local target_config_name
            case "$comp" in
                hyprland) target_config_name="hypr" ;;
                driftwm) target_config_name="driftwm" ;;
                niri) target_config_name="niri" ;;
                sway) target_config_name="sway" ;;
                mango) target_config_name="mango" ;;
                *) target_config_name="$comp" ;;
            esac

            local TARGET_CONFIG_DIR="$HOME/.config/$target_config_name"
            local SRC_COMP_DIR=""
            if [ -d "$REPO_ROOT/compositors/$comp" ] && [ "$(ls -A "$REPO_ROOT/compositors/$comp" 2>/dev/null)" ]; then
                SRC_COMP_DIR="$REPO_ROOT/compositors/$comp"
            elif [ -d "$REPO_ROOT/compositor/$comp" ] && [ "$(ls -A "$REPO_ROOT/compositor/$comp" 2>/dev/null)" ]; then
                SRC_COMP_DIR="$REPO_ROOT/compositor/$comp"
            fi

            if [ -n "$SRC_COMP_DIR" ]; then
                mkdir -p "$TARGET_CONFIG_DIR"

                if [ "$is_update" = "true" ]; then
                    # During update: copy updated repo files, strictly preserving userprefs
                    find "$SRC_COMP_DIR" -type f | while IFS= read -r src_file; do
                        local rel_path="${src_file#$SRC_COMP_DIR/}"
                        if [[ "$rel_path" == *userprefs* ]]; then
                            if [ ! -e "$TARGET_CONFIG_DIR/$rel_path" ]; then
                                mkdir -p "$(dirname "$TARGET_CONFIG_DIR/$rel_path")"
                                cp "$src_file" "$TARGET_CONFIG_DIR/$rel_path"
                            fi
                            continue
                        fi
                        mkdir -p "$(dirname "$TARGET_CONFIG_DIR/$rel_path")"
                        cp "$src_file" "$TARGET_CONFIG_DIR/$rel_path"
                    done
                else
                    # Fresh install or reinstall:
                    cp -r "$SRC_COMP_DIR/." "$TARGET_CONFIG_DIR/"

                    find "$TARGET_CONFIG_DIR" -type f -o -type l | while IFS= read -r dest_file; do
                        local rel_path="${dest_file#$TARGET_CONFIG_DIR/}"
                        if [[ "$rel_path" == *userprefs* || "$rel_path" == *custom* ]]; then
                            continue
                        fi
                        if [ ! -e "$SRC_COMP_DIR/$rel_path" ] && [ ! -L "$SRC_COMP_DIR/$rel_path" ]; then
                            rm -f "$dest_file"
                        fi
                    done

                    find "$TARGET_CONFIG_DIR" -depth -type d -empty ! -path "$TARGET_CONFIG_DIR" -delete 2>/dev/null || true
                fi
            fi
        done
    else
        mkdir -p "$TARGET_BASE/bin" "$TARGET_BASE/src" "$BIN_DIR"

        local changed_files=""
        local deleted_files=""

        if [ "$OLD_COMMIT" != "$NEW_COMMIT" ]; then
            changed_files=$(git -C "$REPO_ROOT" diff --name-only --no-renames --diff-filter=AM "$OLD_COMMIT" "$NEW_COMMIT" 2>/dev/null || true)
            deleted_files=$(git -C "$REPO_ROOT" diff --name-only --no-renames --diff-filter=D "$OLD_COMMIT" "$NEW_COMMIT" 2>/dev/null || true)
        fi

        if [ -n "$deleted_files" ]; then
            while IFS= read -r file; do
                [[ -z "$file" ]] && continue
                if [[ "$file" == bin/* ]]; then
                    rm -f "$TARGET_BASE/$file"
                elif [[ "$file" == src/* ]]; then
                    rm -f "$TARGET_BASE/$file"
                elif [[ "$file" == config/* ]]; then
                    if [ "$is_update" != "true" ]; then
                        local rel_cfg="${file#config/}"
                        local cfg_name="${rel_cfg%%/*}"
                        for cfg in "${EXTRA_CONFIGS[@]}"; do
                            if [[ "$cfg" == "$cfg_name" ]]; then
                                rm -f "$HOME/.config/$rel_cfg"
                            fi
                        done
                    fi
                elif [[ "$file" == compositors/* || "$file" == compositor/* ]]; then
                    if [ "$is_update" != "true" ]; then
                        local comp_part="${file#compositor*/}"
                        local comp_name="${comp_part%%/*}"
                        local comp_file="${comp_part#*/}"
                        for comp in "${COMPOSITORS[@]}"; do
                            if [[ "$comp" == "$comp_name" ]]; then
                                local target_config_name
                                case "$comp" in
                                    hyprland) target_config_name="hypr" ;;
                                    driftwm) target_config_name="driftwm" ;;
                                    niri) target_config_name="niri" ;;
                                    sway) target_config_name="sway" ;;
                                    mango) target_config_name="mango" ;;
                                    *) target_config_name="$comp" ;;
                                esac
                                rm -f "$HOME/.config/$target_config_name/$comp_file"
                            fi
                        done
                    fi
                fi
            done <<< "$deleted_files"
        fi

        if [ -n "$changed_files" ]; then
            while IFS= read -r file; do
                [[ -z "$file" ]] && continue
                if [[ "$file" == bin/* ]]; then
                    mkdir -p "$(dirname "$TARGET_BASE/$file")"
                    cp "$REPO_ROOT/$file" "$TARGET_BASE/$file"
                    chmod +x "$TARGET_BASE/$file" 2>/dev/null || true
                elif [[ "$file" == src/* ]]; then
                    mkdir -p "$(dirname "$TARGET_BASE/$file")"
                    cp "$REPO_ROOT/$file" "$TARGET_BASE/$file"
                    if [[ "$file" == *.sh || "$file" == *.py ]]; then
                        chmod +x "$TARGET_BASE/$file" 2>/dev/null || true
                    fi
                elif [[ "$file" == config/* ]]; then
                    local rel_cfg="${file#config/}"
                    local cfg_name="${rel_cfg%%/*}"
                    for cfg in "${EXTRA_CONFIGS[@]}"; do
                        if [[ "$cfg" == "$cfg_name" ]]; then
                            local dest_file="$HOME/.config/$rel_cfg"
                            if [ "$is_update" != "true" ] || [ ! -e "$dest_file" ]; then
                                mkdir -p "$(dirname "$dest_file")"
                                cp "$REPO_ROOT/$file" "$dest_file"
                            fi
                        fi
                    done
                elif [[ "$file" == compositors/* || "$file" == compositor/* ]]; then
                    local comp_part="${file#compositor*/}"
                    local comp_name="${comp_part%%/*}"
                    local comp_file="${comp_part#*/}"
                    for comp in "${COMPOSITORS[@]}"; do
                        if [[ "$comp" == "$comp_name" ]]; then
                            local target_config_name
                            case "$comp" in
                                hyprland) target_config_name="hypr" ;;
                                driftwm) target_config_name="driftwm" ;;
                                niri) target_config_name="niri" ;;
                                sway) target_config_name="sway" ;;
                                mango) target_config_name="mango" ;;
                                *) target_config_name="$comp" ;;
                            esac
                            local dest_target="$HOME/.config/$target_config_name/$comp_file"
                            if [[ "$comp_file" != *userprefs* ]] || [ ! -e "$dest_target" ]; then
                                mkdir -p "$(dirname "$dest_target")"
                                cp "$REPO_ROOT/$file" "$dest_target"
                            fi
                        fi
                    done
                fi
            done <<< "$changed_files"
        fi
    fi

    if [ -f "$REPO_ROOT/version.txt" ]; then
        rm -f "$TARGET_BASE/src/version.txt"
        cp "$REPO_ROOT/version.txt" "$TARGET_BASE/src/version.txt"
    fi

    if [ -f "$TARGET_BASE/bin/serpantinum" ]; then
        ln -sf "$TARGET_BASE/bin/serpantinum" "$BIN_DIR/serpantinum"
        sudo ln -sf "$TARGET_BASE/bin/serpantinum" /usr/local/bin/serpantinum 2>/dev/null || true
    fi

    if [ -f "$TARGET_BASE/bin/serpantinumd" ]; then
        ln -sf "$TARGET_BASE/bin/serpantinumd" "$BIN_DIR/serpantinumd"
        sudo ln -sf "$TARGET_BASE/bin/serpantinumd" /usr/local/bin/serpantinumd 2>/dev/null || true
    fi

    if [ -f "$TARGET_BASE/bin/serpantinum_theme_sync.py" ]; then
        ln -sf "$TARGET_BASE/bin/serpantinum_theme_sync.py" "$BIN_DIR/serpantinum_theme_sync.py"
        sudo ln -sf "$TARGET_BASE/bin/serpantinum_theme_sync.py" /usr/local/bin/serpantinum_theme_sync.py 2>/dev/null || true
        chmod +x "$TARGET_BASE/bin/serpantinum_theme_sync.py" "$BIN_DIR/serpantinum_theme_sync.py" 2>/dev/null || true
        python3 "$TARGET_BASE/bin/serpantinum_theme_sync.py" 2>/dev/null || true
    fi

    # Ensure kitty.conf base settings (font_size 13.0, JetBrainsMono, fish) are present
    local kitty_dest="$HOME/.config/kitty/kitty.conf"
    local kitty_src="$REPO_ROOT/config/kitty/kitty.conf"
    if [ -f "$kitty_src" ]; then
        if [ ! -f "$kitty_dest" ] || ! grep -q "font_size" "$kitty_dest"; then
            mkdir -p "$HOME/.config/kitty"
            local existing_theme=""
            if [ -f "$kitty_dest" ]; then
                existing_theme="$(grep -E "include themes/serpantinum.conf" "$kitty_dest" 2>/dev/null || true)"
            fi
            cp "$kitty_src" "$kitty_dest"
            if [ -n "$existing_theme" ] && ! grep -q "include themes/serpantinum.conf" "$kitty_dest"; then
                echo -e "\n# >>> serpantinum theme >>>\ninclude themes/serpantinum.conf\n# <<< serpantinum theme <<<" >> "$kitty_dest"
            fi
        fi
    fi
    if [ -f "$kitty_dest" ]; then
        if ! grep -q "JetBrainsMono Nerd Font" "$kitty_dest"; then
            sed -i 's/font_family[[:space:]]\+JetBrains Mono/font_family      JetBrainsMono Nerd Font/' "$kitty_dest" 2>/dev/null || true
        fi
        if grep -qE "font_size[[:space:]]+16(\.0)?" "$kitty_dest"; then
            sed -i -E 's/font_size[[:space:]]+16(\.0)?/font_size        13.0/' "$kitty_dest" 2>/dev/null || true
        fi
        if grep -q "background_opacity" "$kitty_dest"; then
            sed -i -E 's/background_opacity[[:space:]]+[0-9.]+/background_opacity 1.0/' "$kitty_dest" 2>/dev/null || true
        fi
        if ! grep -q "shell.*fish" "$kitty_dest" && command -v fish >/dev/null 2>&1; then
            echo -e "\nshell $(command -v fish)" >> "$kitty_dest"
        fi
    fi

    # Set default user shell to fish if installed
    if command -v fish >/dev/null 2>&1; then
        local fish_bin
        fish_bin="$(command -v fish)"
        if [ "$SHELL" != "$fish_bin" ]; then
            if grep -Fxq "$fish_bin" /etc/shells 2>/dev/null; then
                sudo chsh -s "$fish_bin" "$USER" 2>/dev/null || chsh -s "$fish_bin" 2>/dev/null || true
            fi
        fi
    fi

    # Deploy battery & power optimization tools
    if [ -f "$TARGET_BASE/src/scripts/system/apply-power-profile.sh" ]; then
        sudo cp "$TARGET_BASE/src/scripts/system/apply-power-profile.sh" /usr/local/bin/apply-power-profile.sh 2>/dev/null || true
        sudo chmod 755 /usr/local/bin/apply-power-profile.sh 2>/dev/null || true
    fi
    if [ -f "$TARGET_BASE/src/scripts/system/battery" ]; then
        sudo cp "$TARGET_BASE/src/scripts/system/battery" /usr/local/bin/battery 2>/dev/null || true
        sudo chmod 755 /usr/local/bin/battery 2>/dev/null || true
        sudo ln -sf /usr/local/bin/battery /usr/local/bin/power 2>/dev/null || true
    fi
    if [ -f "$TARGET_BASE/src/scripts/system/monitor_manager.py" ]; then
        sudo cp "$TARGET_BASE/src/scripts/system/monitor_manager.py" /usr/local/bin/serpantinum-monitor 2>/dev/null || true
        sudo chmod 755 /usr/local/bin/serpantinum-monitor 2>/dev/null || true
    fi

    # Deploy sudoers rule for hardware power optimizations
    if [ -d /etc/sudoers.d ]; then
        echo "%wheel ALL=(ALL) NOPASSWD: /usr/local/bin/apply-power-profile.sh, /usr/bin/sysctl, /usr/bin/iw, /usr/bin/tee" | sudo tee /etc/sudoers.d/99-serpantinum-power >/dev/null 2>&1 || true
        sudo chmod 0440 /etc/sudoers.d/99-serpantinum-power 2>/dev/null || true
    fi

    # Deploy USB mouse power rules (disable autosuspend on mice/receivers)
    if [ -f "$TARGET_BASE/src/assets/udev/50-usb-mouse-power.rules" ]; then
        sudo mkdir -p /etc/udev/rules.d 2>/dev/null || true
        sudo cp "$TARGET_BASE/src/assets/udev/50-usb-mouse-power.rules" /etc/udev/rules.d/50-usb-mouse-power.rules 2>/dev/null || true
        sudo udevadm control --reload-rules 2>/dev/null || true
        sudo udevadm trigger --subsystem-match=usb 2>/dev/null || true
    fi

    # Deploy battery threshold rules for laptops
    if [ -f "$TARGET_BASE/src/assets/udev/51-battery-threshold.rules" ]; then
        sudo mkdir -p /etc/udev/rules.d 2>/dev/null || true
        sudo cp "$TARGET_BASE/src/assets/udev/51-battery-threshold.rules" /etc/udev/rules.d/51-battery-threshold.rules 2>/dev/null || true
        sudo udevadm control --reload-rules 2>/dev/null || true
        sudo udevadm trigger --subsystem-match=power_supply 2>/dev/null || true
    fi

    # Deploy power & sysfs sudoers rules for battery thresholds and performance tuning
    if [ -f "$TARGET_BASE/src/assets/sudoers/99-serpantinum-power" ]; then
        sudo mkdir -p /etc/sudoers.d 2>/dev/null || true
        sudo cp "$TARGET_BASE/src/assets/sudoers/99-serpantinum-power" /etc/sudoers.d/99-serpantinum-power 2>/dev/null || true
        sudo chmod 440 /etc/sudoers.d/99-serpantinum-power 2>/dev/null || true
    fi

    # Deploy polkit rules for reboot/poweroff, powerprofilesctl, and fprintd passwordless management
    if [ -f "$TARGET_BASE/src/assets/polkit/48-selion-reboot.rules" ]; then
        sudo mkdir -p /etc/polkit-1/rules.d 2>/dev/null || true
        sudo cp "$TARGET_BASE/src/assets/polkit/48-selion-reboot.rules" /etc/polkit-1/rules.d/48-selion-reboot.rules 2>/dev/null || true
        sudo chmod 644 /etc/polkit-1/rules.d/48-selion-reboot.rules 2>/dev/null || true
    fi
    if [ -f "$TARGET_BASE/src/assets/polkit/49-power-profiles.rules" ]; then
        sudo mkdir -p /etc/polkit-1/rules.d 2>/dev/null || true
        sudo cp "$TARGET_BASE/src/assets/polkit/49-power-profiles.rules" /etc/polkit-1/rules.d/49-power-profiles.rules 2>/dev/null || true
        sudo chmod 644 /etc/polkit-1/rules.d/49-power-profiles.rules 2>/dev/null || true
    fi
    if [ -f "$TARGET_BASE/src/assets/polkit/50-net.reactivated.fprint.rules" ]; then
        sudo mkdir -p /etc/polkit-1/rules.d 2>/dev/null || true
        sudo cp "$TARGET_BASE/src/assets/polkit/50-net.reactivated.fprint.rules" /etc/polkit-1/rules.d/50-net.reactivated.fprint.rules 2>/dev/null || true
        sudo chmod 644 /etc/polkit-1/rules.d/50-net.reactivated.fprint.rules 2>/dev/null || true
    fi

    # Deploy logind clamshell configuration: ignore lid switch when external monitor is connected
    if [ -d "/etc/systemd" ]; then
        sudo mkdir -p /etc/systemd/logind.conf.d 2>/dev/null || true
        printf '[Login]\nHandleLidSwitch=suspend\nHandleLidSwitchDocked=ignore\n' | sudo tee /etc/systemd/logind.conf.d/99-serpantinum-clamshell.conf >/dev/null 2>&1 || true
    fi

    # Deploy Twemoji fontconfig and ensure emoji font availability
    if [ -f "$TARGET_BASE/src/assets/fontconfig/75-twemoji.conf" ]; then
        local fontconfig_avail="/usr/share/fontconfig/conf.avail"
        [ -d "$fontconfig_avail" ] || fontconfig_avail="/etc/fonts/conf.avail"
        sudo mkdir -p "$fontconfig_avail" /etc/fonts/conf.d 2>/dev/null || true
        sudo cp "$TARGET_BASE/src/assets/fontconfig/75-twemoji.conf" "$fontconfig_avail/75-twemoji.conf" 2>/dev/null || true
        sudo ln -sf "$fontconfig_avail/75-twemoji.conf" /etc/fonts/conf.d/75-twemoji.conf 2>/dev/null || true
    fi
    if ! fc-list : family 2>/dev/null | grep -qi "Twitter Color Emoji"; then
        sudo mkdir -p /usr/share/fonts/twemoji 2>/dev/null || true
        curl -fsSL "https://raw.githubusercontent.com/quarrel/broken-flag-emojis-win11-twemoji/main/Twemoji-16.0.1-SVG-COLR1.ttf" -o /tmp/Twemoji.ttf 2>/dev/null && \
        sudo mv /tmp/Twemoji.ttf /usr/share/fonts/twemoji/Twemoji.ttf 2>/dev/null && \
        sudo fc-cache -f 2>/dev/null || true
    fi

    # Ensure driftwm session desktop entry is accessible to display managers
    if [ -f "/usr/local/share/wayland-sessions/driftwm.desktop" ] && [ ! -f "/usr/share/wayland-sessions/driftwm.desktop" ]; then
        sudo ln -sf /usr/local/share/wayland-sessions/driftwm.desktop /usr/share/wayland-sessions/driftwm.desktop 2>/dev/null || true
    fi
    if [ -f "/usr/local/share/xdg-desktop-portal/driftwm-portals.conf" ] && [ ! -f "/usr/share/xdg-desktop-portal/driftwm-portals.conf" ]; then
        sudo ln -sf /usr/local/share/xdg-desktop-portal/driftwm-portals.conf /usr/share/xdg-desktop-portal/driftwm-portals.conf 2>/dev/null || true
    fi

    remove_settings_desktop_entry

    # Deploy custom Windows-11M-Dark cursor theme
    local cursor_src="$TARGET_BASE/src/assets/cursors/Windows-11M-Dark"
    if [ -d "$cursor_src" ]; then
        local user_icons="$HOME/.local/share/icons"
        local legacy_icons="$HOME/.icons"
        mkdir -p "$user_icons" "$legacy_icons" "$legacy_icons/default" 2>/dev/null || true
        rm -rf "$user_icons/Windows-11M-Dark" "$legacy_icons/Windows-11M-Dark" 2>/dev/null || true
        cp -r "$cursor_src" "$user_icons/"
        ln -sf "$user_icons/Windows-11M-Dark" "$legacy_icons/Windows-11M-Dark" 2>/dev/null || true

        cat << 'EOF_CUR' > "$legacy_icons/default/index.theme"
[Icon Theme]
Name=Default
Comment=Default Cursor Theme
Inherits=Windows-11M-Dark
EOF_CUR

        if [ -w /usr/share/icons ] || sudo -n true 2>/dev/null; then
            sudo rm -rf /usr/share/icons/Windows-11M-Dark 2>/dev/null || true
            sudo cp -r "$cursor_src" /usr/share/icons/ 2>/dev/null || true
        fi

        if command -v gsettings &>/dev/null; then
            gsettings set org.gnome.desktop.interface cursor-theme 'Windows-11M-Dark' 2>/dev/null || true
            gsettings set org.gnome.desktop.interface cursor-size 32 2>/dev/null || true
        fi
        for gtk_dir in "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"; do
            mkdir -p "$gtk_dir" 2>/dev/null || true
            local ini="$gtk_dir/settings.ini"
            if [ -f "$ini" ]; then
                sed -i 's/^gtk-cursor-theme-name=.*/gtk-cursor-theme-name=Windows-11M-Dark/' "$ini" 2>/dev/null || true
                sed -i 's/^gtk-cursor-theme-size=.*/gtk-cursor-theme-size=32/' "$ini" 2>/dev/null || true
                grep -q "gtk-cursor-theme-name" "$ini" || echo "gtk-cursor-theme-name=Windows-11M-Dark" >> "$ini"
                grep -q "gtk-cursor-theme-size" "$ini" || echo "gtk-cursor-theme-size=32" >> "$ini"
            else
                cat << 'EOF_GTK' > "$ini"
[Settings]
gtk-cursor-theme-name=Windows-11M-Dark
gtk-cursor-theme-size=32
EOF_GTK
            fi
        done

        mkdir -p "$HOME/.config/environment.d" 2>/dev/null || true
        cat << 'EOF_ENV' > "$HOME/.config/environment.d/10-cursor.conf"
XCURSOR_THEME=Windows-11M-Dark
XCURSOR_SIZE=32
HYPRCURSOR_THEME=Windows-11M-Dark
HYPRCURSOR_SIZE=32
EOF_ENV
        if command -v systemctl &>/dev/null; then
            systemctl --user import-environment XCURSOR_SIZE XCURSOR_THEME HYPRCURSOR_SIZE HYPRCURSOR_THEME 2>/dev/null || true
        fi
        if command -v dbus-update-activation-environment &>/dev/null; then
            dbus-update-activation-environment --systemd XCURSOR_SIZE XCURSOR_THEME HYPRCURSOR_SIZE HYPRCURSOR_THEME 2>/dev/null || true
        fi

        for sddm_conf in /etc/sddm.conf.d/*.conf /etc/sddm.conf; do
            if [ -f "$sddm_conf" ]; then
                configure_sddm_cursor "$sddm_conf" 2>/dev/null || true
            fi
        done
    fi

    # Initial theme and border synchronization for all compositors
    if [ -f "$TARGET_BASE/src/scripts/theming/sync_compositor_theme.py" ]; then
        python3 "$TARGET_BASE/src/scripts/theming/sync_compositor_theme.py" 2>/dev/null || true
    fi

    # Automatic theme, fonts and cursor integration for Flatpak sandboxed applications
    if command -v flatpak &>/dev/null; then
        flatpak override --user --filesystem=xdg-config/gtk-3.0:ro \
                                --filesystem=xdg-config/gtk-4.0:ro \
                                --filesystem=xdg-config/fontconfig:ro \
                                --filesystem=~/.icons:ro \
                                --filesystem=xdg-data/icons:ro 2>/dev/null || true
    fi

    # Default image viewer configuration
    if command -v xdg-mime >/dev/null 2>&1; then
        if command -v loupe >/dev/null 2>&1; then
            xdg-mime default org.gnome.Loupe.desktop image/png image/jpeg image/webp image/gif image/svg+xml image/bmp image/tiff 2>/dev/null || true
        fi
    fi

    configure_keyboard_layout "$KEYBOARD_LAYOUT" "$KEYBOARD_TOGGLE"
    configure_driftwm_bookmarks "${COMPOSITORS[@]}"
    setup_pam_service
}
