#!/usr/bin/env bash

get_compositor_config_dir_name() {
    local comp="$1"
    case "$comp" in
        hyprland) echo "hypr" ;;
        driftwm) echo "driftwm" ;;
        niri) echo "niri" ;;
        sway) echo "sway" ;;
        mango) echo "mango" ;;
        umbriel) echo "umbriel" ;;
        *) echo "$comp" ;;
    esac
}

backup_managed_configs() {
    local compositors=("$@")
    local backup_date
    backup_date="$(date +%Y-%m-%d_%H-%M-%S)"
    local BACKUP_ROOT="$HOME/Update/Backups/$backup_date/.config"

    mkdir -p "$BACKUP_ROOT" 2>/dev/null || true

    local backed_up_count=0

    # 1. Managed compositors (only those we install/manage)
    for comp in "${compositors[@]}"; do
        local dir_name
        dir_name=$(get_compositor_config_dir_name "$comp")
        local comp_dir="$HOME/.config/$dir_name"
        if [ -d "$comp_dir" ] && [ "$(ls -A "$comp_dir" 2>/dev/null)" ]; then
            mkdir -p "$BACKUP_ROOT/$dir_name"
            cp -a "$comp_dir/." "$BACKUP_ROOT/$dir_name/" 2>/dev/null || true
            backed_up_count=$((backed_up_count + 1))
        fi
    done

    # 2. Managed extra config directories
    local extra_managed_dirs=("kitty" "fastfetch" "fish" "serpantinum")
    for d in "${extra_managed_dirs[@]}"; do
        local src_dir="$HOME/.config/$d"
        if [ -d "$src_dir" ] && [ "$(ls -A "$src_dir" 2>/dev/null)" ]; then
            mkdir -p "$BACKUP_ROOT/$d"
            cp -a "$src_dir/." "$BACKUP_ROOT/$d/" 2>/dev/null || true
            backed_up_count=$((backed_up_count + 1))
        fi
    done

    # 3. Managed single files
    local extra_managed_files=("starship.toml")
    for f in "${extra_managed_files[@]}"; do
        local src_file="$HOME/.config/$f"
        if [ -f "$src_file" ]; then
            cp -a "$src_file" "$BACKUP_ROOT/" 2>/dev/null || true
            backed_up_count=$((backed_up_count + 1))
        fi
    done

    if [ "$backed_up_count" -gt 0 ]; then
        echo "[backup] Backed up $backed_up_count managed configuration(s) to $BACKUP_ROOT"
    else
        rmdir "$BACKUP_ROOT" 2>/dev/null || true
    fi
}

backup_compositors() {
    backup_managed_configs "$@"
}

migrate_legacy() {
    local compositors=("$@")
    local state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
    local config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
    local backup_dir="$config_home/hypr_backup"

    pkill -f "settings_watcher.sh" 2>/dev/null || true
    pkill -f "hypr/scripts/quickshell" 2>/dev/null || true

    pm_remove_conflicting_pkg "quickshell-git"

    backup_compositors "${compositors[@]}"

    if [ -f "$state_home/imperative-dots-version" ]; then
        mkdir -p "$backup_dir"
        mv "$state_home/imperative-dots-version" "$backup_dir/imperative-dots-version.bak" 2>/dev/null || true
    fi

    if [ -f "$config_home/hypr/scripts/settings_watcher.sh" ]; then
        mkdir -p "$backup_dir"
        mv "$config_home/hypr/scripts/settings_watcher.sh" "$backup_dir/settings_watcher.sh.bak" 2>/dev/null || true
    fi
}
