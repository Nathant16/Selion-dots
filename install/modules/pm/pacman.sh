#!/usr/bin/env bash

PM_BOOTSTRAP_TOOLS=(python jq curl git pciutils unzip fontconfig base-devel)
PM_AUDIO_BUILD_PKGS=(base-devel pkgconf pipewire)

declare -A PM_PKG_MAP=(
    [umbriel]="umbriel-git"
)

pm_resolve_name() {
    echo "${PM_PKG_MAP[$1]:-$1}"
}

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
        local changed=false
        if grep -q "^#\[multilib\]" /etc/pacman.conf; then
            sudo sed -i '/^#\[multilib\]/{s/^#//;n;s/^#//}' /etc/pacman.conf
            changed=true
        fi
        if grep -q "^#ParallelDownloads" /etc/pacman.conf; then
            sudo sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
            changed=true
        fi
        if [ "$changed" = true ]; then
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
    local resolved=() pkg
    for pkg in "$@"; do
        resolved+=("$(pm_resolve_name "$pkg")")
    done
    pacman -T "${resolved[@]}" 2>/dev/null || true
}

pm_is_installed() {
    pacman -Q "$(pm_resolve_name "$1")" &>/dev/null
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

pm_optimize_pacman_mirrors() {
    echo -e "\n\e[36m[ INFO ]\e[0m $(t "installer.deps.ranking_pacman" "Finding and ranking fastest Pacman mirrors...")"
    if ! command -v reflector &>/dev/null; then
        sudo pacman -S --noconfirm --needed reflector 2>/dev/null || true
    fi

    if command -v reflector &>/dev/null; then
        local tmp_mirrorlist
        tmp_mirrorlist=$(mktemp)
        if sudo reflector --latest 20 --number 10 --protocol https --sort rate --download-timeout 5 --save "$tmp_mirrorlist" 2>/dev/null && [ -s "$tmp_mirrorlist" ]; then
            if [ -f /etc/pacman.d/mirrorlist ] && [ ! -f /etc/pacman.d/mirrorlist.serpantinum.bak ]; then
                sudo cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.serpantinum.bak 2>/dev/null || true
            fi
            sudo cp "$tmp_mirrorlist" /etc/pacman.d/mirrorlist
            sudo chmod 644 /etc/pacman.d/mirrorlist
            echo -e "\e[32m[ OK ]\e[0m $(t "installer.deps.pacman_ok" "Pacman mirrors updated with fastest HTTPS mirrors.")"
        else
            echo -e "\e[33m[ WARN ]\e[0m $(t "installer.deps.pacman_fallback" "Reflector timed out or failed, keeping current Pacman mirrorlist.")"
        fi
        rm -f "$tmp_mirrorlist" 2>/dev/null || true
    else
        echo -e "\e[33m[ WARN ]\e[0m $(t "installer.deps.pacman_skip" "Reflector not available, skipping Pacman mirror optimization.")"
    fi
}

pm_setup_chaotic_aur() {
    echo -e "\n\e[36m[ INFO ]\e[0m $(t "installer.deps.ranking_chaotic" "Configuring and ranking Chaotic-AUR binary repository...")"

    # Step 1: Ensure primary signing key is imported and trusted
    if ! pacman-key --list-keys 3056513887B78AEB &>/dev/null; then
        sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com 2>/dev/null || \
        sudo pacman-key --recv-key 3056513887B78AEB --keyserver keys.openpgp.org 2>/dev/null || true
        sudo pacman-key --lsign-key 3056513887B78AEB 2>/dev/null || true
    fi

    # Step 2: Install chaotic-keyring and chaotic-mirrorlist packages
    if ! pm_is_installed chaotic-keyring; then
        sudo pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' 2>/dev/null || true
    fi
    if ! pm_is_installed chaotic-mirrorlist; then
        sudo pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst' 2>/dev/null || true
    fi

    if [ ! -f /etc/pacman.d/chaotic-mirrorlist ]; then
        cat << 'EOF' | sudo tee /etc/pacman.d/chaotic-mirrorlist >/dev/null
Server = https://geo-mirror.chaotic.cx/$repo/$arch
Server = https://cdn-mirror.chaotic.cx/$repo/$arch
Server = https://de-mirror.chaotic.cx/$repo/$arch
Server = https://us-mirror.chaotic.cx/$repo/$arch
EOF
    fi

    # Step 3: Fast concurrent ranking of Chaotic-AUR mirrors
    if [ -f /etc/pacman.d/chaotic-mirrorlist ] && command -v python3 &>/dev/null; then
        sudo python3 - << 'PYEOF'
import urllib.request, time, concurrent.futures, re, sys

mirrorlist_path = "/etc/pacman.d/chaotic-mirrorlist"
try:
    with open(mirrorlist_path, "r", encoding="utf-8") as f:
        lines = f.readlines()
except Exception:
    sys.exit(0)

server_urls = []
for line in lines:
    m = re.match(r'^\s*#?\s*Server\s*=\s*(https?://\S+)', line)
    if m:
        url = m.group(1)
        if url not in server_urls:
            server_urls.append(url)

def test_mirror(raw_url):
    test_url = raw_url.replace("$repo", "chaotic-aur").replace("$arch", "x86_64") + "/chaotic-aur.db"
    req = urllib.request.Request(test_url, method="HEAD", headers={"User-Agent": "curl/8.0"})
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=3.0) as resp:
            if resp.status == 200:
                return (time.time() - t0, raw_url)
    except Exception:
        pass
    return (999.0, raw_url)

with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
    results = list(executor.map(test_mirror, server_urls))

alive = [r for r in results if r[0] < 990.0]
alive.sort(key=lambda x: x[0])

if alive:
    fastest_urls = {r[1] for r in alive[:5]}
    for r in alive:
        if "geo-mirror" in r[1] or "cdn-mirror" in r[1]:
            fastest_urls.add(r[1])

    new_lines = [
        "# Ranked and configured by Serpantinum installer\n",
        "# Top fastest Chaotic-AUR mirrors:\n"
    ]
    for r in sorted([x for x in alive if x[1] in fastest_urls], key=lambda x: x[0]):
        new_lines.append(f"# Latency: {r[0]:.2f}s\nServer = {r[1]}\n")

    new_lines.append("\n# Fallback mirrors:\n")
    for url in server_urls:
        if url not in fastest_urls:
            new_lines.append(f"#Server = {url}\n")

    try:
        with open(mirrorlist_path, "w", encoding="utf-8") as f:
            f.writelines(new_lines)
    except Exception:
        pass
PYEOF
        echo -e "\e[32m[ OK ]\e[0m $(t "installer.deps.chaotic_ok" "Chaotic-AUR mirrors ranked successfully.")"
    fi

    # Step 4: Ensure [chaotic-aur] repo is registered in /etc/pacman.conf
    if [ -f /etc/pacman.conf ] && [ -f /etc/pacman.d/chaotic-mirrorlist ]; then
        if ! grep -q "\[chaotic-aur\]" /etc/pacman.conf; then
            cat << 'EOF' | sudo tee -a /etc/pacman.conf >/dev/null

[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
EOF
        fi
    fi
}

pm_optimize_repos() {
    pm_optimize_pacman_mirrors
    pm_setup_chaotic_aur
    sudo pacman -Sy >/dev/null 2>&1 || true
}
