#!/usr/bin/env bash

PM_BOOTSTRAP_TOOLS=(fzf jq curl git pciutils unzip fontconfig base-devel)
PM_AUDIO_BUILD_PKGS=(base-devel pkgconf pipewire)

get_gpu_vulkan_pkgs() {
    local pkgs=()
    local gpu
    gpu=$(lspci 2>/dev/null | grep -iE 'vga|3d|display' || true)

    if echo "$gpu" | grep -qiE 'amd|radeon|ati'; then
        pkgs+=("vulkan-radeon" "lib32-vulkan-radeon")
    elif echo "$gpu" | grep -qiE 'intel'; then
        pkgs+=("vulkan-intel" "lib32-vulkan-intel")
    elif echo "$gpu" | grep -qiE 'nvidia'; then
        pkgs+=("nvidia-utils" "lib32-nvidia-utils")
    fi
    printf '%s\n' "${pkgs[@]}"
}

PM_EXTRA_PKGS=(pam-fprint-grosshack)
for _p in $(get_gpu_vulkan_pkgs 2>/dev/null); do
    PM_EXTRA_PKGS+=("$_p")
done

pm_prepare_repos() {
    if [ -f /etc/pacman.conf ]; then
        if grep -q "^#\[multilib\]" /etc/pacman.conf; then
            sudo sed -i '/^#\[multilib\]/{s/^#//;n;s/^#//}' /etc/pacman.conf
            sudo pacman -Sy --noconfirm >/dev/null 2>&1 || true
        fi
    fi
}

pm_bootstrap_install() {
    sudo pacman -Sy --noconfirm --needed "$@"
}

pm_bootstrap_helper() {
    if ! command -v yay &>/dev/null && ! command -v paru &>/dev/null; then
        local cache_build="${XDG_CACHE_HOME:-"$HOME/.cache"}/serpantinum-yay-bin"
        rm -rf "$cache_build"
        mkdir -p "$cache_build"
        git clone https://aur.archlinux.org/yay-bin.git "$cache_build"
        (cd "$cache_build" && makepkg -si --noconfirm)
        rm -rf "$cache_build"
    fi
}

pm_full_upgrade() {
    echo -e "\n\e[36m[ INFO ]\e[0m $(t "installer.deps.syncing")"
    sudo pacman -Syyu --noconfirm
}

pm_missing_pkgs() {
    pacman -T "$@" 2>/dev/null || true
}

pm_is_installed() {
    pacman -Q "$1" &>/dev/null
}

pm_install_pkg() {
    local pkg="$1"
    local safe_jobs="$2"

    sudo -n true 2>/dev/null || sudo -v 2>/dev/null || true

    if pacman -Si "$pkg" &>/dev/null; then
        sudo pacman -S --noconfirm --needed "$pkg"
    elif command -v yay &>/dev/null; then
        env CARGO_BUILD_JOBS="$safe_jobs" MAKEFLAGS="-j$safe_jobs" yay -S --noconfirm --needed --answerclean None --answerdiff None --answeredit None --answerupgrade None "$pkg"
    elif command -v paru &>/dev/null; then
        env CARGO_BUILD_JOBS="$safe_jobs" MAKEFLAGS="-j$safe_jobs" paru -S --noconfirm --needed --skipreview "$pkg"
    else
        sudo pacman -S --noconfirm --needed "$pkg"
    fi
}

pm_upgrade_quickshell() {
    if sudo pacman -Syu --noconfirm --needed --ask=4 quickshell && quickshell_is_current; then
        return 0
    fi

    local helper
    for helper in yay paru; do
        command -v "$helper" &>/dev/null || continue
        if [ "$helper" = "yay" ]; then
            "$helper" -S --noconfirm --needed --ask=4 --answerclean None --answerdiff None --answeredit None --answerupgrade None quickshell-git && quickshell_is_current && return 0
        else
            "$helper" -S --noconfirm --needed --ask=4 --skipreview quickshell-git && quickshell_is_current && return 0
        fi
        break
    done
    return 0
}

pm_remove_pkg() {
    sudo pacman -Rns --noconfirm "$1" >/dev/null 2>&1 || true
}

pm_remove_conflicting_pkg() {
    local pkg="$1"
    if pm_is_installed "$pkg"; then
        yay -R --noconfirm "$pkg" 2>/dev/null || sudo pacman -Rdd --noconfirm "$pkg" 2>/dev/null || true
    fi
}

pm_enable_display_manager() {
    local svc="$1" init_sys="$2"
    if [ "$init_sys" = "systemd" ]; then
        sudo systemctl enable "$svc.service" 2>/dev/null || sudo systemctl enable "$svc" 2>/dev/null || true
    else
        enable_system_service "$svc" "$init_sys"
    fi
}
