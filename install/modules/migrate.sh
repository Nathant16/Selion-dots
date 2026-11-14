#!/usr/bin/env bash

get_compositor_config_dir_name() {
    local comp="$1"
    case "$comp" in
        hyprland) echo "hypr" ;;
        driftwm) echo "driftwm" ;;
        niri) echo "niri" ;;
        sway) echo "sway" ;;
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
            ((backed_up_count++))
        fi
    done

    # 2. Managed extra config directories
    local extra_managed_dirs=("kitty" "fastfetch" "fish" "serpantinum")
    for d in "${extra_managed_dirs[@]}"; do
        local src_dir="$HOME/.config/$d"
        if [ -d "$src_dir" ] && [ "$(ls -A "$src_dir" 2>/dev/null)" ]; then
            mkdir -p "$BACKUP_ROOT/$d"
            cp -a "$src_dir/." "$BACKUP_ROOT/$d/" 2>/dev/null || true
            ((backed_up_count++))
        fi
    done

    # 3. Managed single files
    local extra_managed_files=("starship.toml")
    for f in "${extra_managed_files[@]}"; do
        local src_file="$HOME/.config/$f"
        if [ -f "$src_file" ]; then
            cp -a "$src_file" "$BACKUP_ROOT/" 2>/dev/null || true
            ((backed_up_count++))
        fi
    done

    if [ "$backed_up_count" -gt 0 ]; then
        echo "[backup] Backed up $backed_up_count managed configuration(s) to $BACKUP_ROOT"
    fi
}

backup_compositors() {
    backup_managed_configs "$@"
}

migrate_legacy() {
    local compositors=("$@")
    pkill -f "settings_watcher.sh" 2>/dev/null || true
    pkill -f "hypr/scripts/quickshell" 2>/dev/null || true

    pm_remove_conflicting_pkg "quickshell-git"

    backup_compositors "${compositors[@]}"

    if [ -f "$HOME/.local/state/imperative-dots-version" ]; then
        mkdir -p "$HOME/.config/hypr_backup"
        mv "$HOME/.local/state/imperative-dots-version" "$HOME/.config/hypr_backup/imperative-dots-version.bak" 2>/dev/null || true
    fi
}
