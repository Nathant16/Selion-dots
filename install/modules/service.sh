#!/usr/bin/env bash

detect_init_system() {
    if [[ -d /run/systemd/system ]] || command -v systemctl &>/dev/null; then
        echo "systemd"
    elif command -v openrc-init &>/dev/null || [[ -d /run/openrc ]]; then
        echo "openrc"
    elif command -v dinit &>/dev/null || [[ -d /etc/dinit.d ]]; then
        echo "dinit"
    elif command -v runit &>/dev/null || [[ -d /run/runit ]]; then
        echo "runit"
    elif command -v s6-svscan &>/dev/null; then
        echo "s6"
    else
        echo "generic"
    fi
}

enable_system_service() {
    local svc="$1"
    local init_sys="$2"

    case "$init_sys" in
        systemd)
            if [[ "$svc" =~ ^(sddm|gdm|gdm3|lightdm|lxdm|ly|greetd)$ ]]; then
                sudo systemctl enable "$svc.service" 2>/dev/null || sudo systemctl enable -f "$svc.service" 2>/dev/null || sudo systemctl enable "$svc" 2>/dev/null || true
            else
                sudo systemctl enable --now "$svc.service" 2>/dev/null || sudo systemctl enable -f "$svc.service" 2>/dev/null || sudo systemctl enable "$svc.service" 2>/dev/null || true
            fi
            ;;
        openrc)
            sudo rc-update add "$svc" default 2>/dev/null || true
            if [[ ! "$svc" =~ ^(sddm|gdm|gdm3|lightdm|lxdm|ly|greetd)$ ]]; then
                sudo rc-service "$svc" start 2>/dev/null || true
            fi
            ;;
        dinit)
            sudo dinitctl enable "$svc" 2>/dev/null || sudo dinitctl start "$svc" 2>/dev/null || true
            ;;
        runit)
            if [ -d "/etc/sv/$svc" ]; then
                sudo ln -sf "/etc/sv/$svc" /var/service/ 2>/dev/null || true
            fi
            ;;
        s6)
            sudo s6-rc-bundle-update -b add default "$svc" 2>/dev/null || true
            ;;
        *)
            true
            ;;
    esac
}

disable_system_service() {
    local svc="$1"
    local init_sys="$2"

    case "$init_sys" in
        systemd)
            sudo systemctl disable --now "$svc.service" 2>/dev/null || sudo systemctl disable "$svc.service" 2>/dev/null || sudo systemctl disable "$svc" 2>/dev/null || true
            ;;
        openrc)
            sudo rc-service "$svc" stop 2>/dev/null || true
            sudo rc-update del "$svc" default 2>/dev/null || true
            ;;
        dinit)
            sudo dinitctl stop "$svc" 2>/dev/null || true
            sudo dinitctl disable "$svc" 2>/dev/null || true
            ;;
        runit)
            if [ -L "/var/service/$svc" ] || [ -d "/var/service/$svc" ]; then
                sudo rm -f "/var/service/$svc" 2>/dev/null || true
            fi
            ;;
        s6)
            sudo s6-rc-bundle-update -b del default "$svc" 2>/dev/null || true
            ;;
        *)
            true
            ;;
    esac
}

enable_user_service() {
    local svc="$1"
    local init_sys="$2"

    case "$init_sys" in
        systemd)
            systemctl --user daemon-reload 2>/dev/null || true
            systemctl --user enable --now "$svc.service" 2>/dev/null || systemctl --user enable "$svc.service" 2>/dev/null || true
            ;;
        dinit)
            dinitctl --user enable "$svc" 2>/dev/null || dinitctl --user start "$svc" 2>/dev/null || true
            ;;
        *)
            true
            ;;
    esac
}

configure_bluetooth() {
    local init_sys="$1"

    sudo mkdir -p /etc/bluetooth 2>/dev/null || true
    sudo chmod 755 /etc/bluetooth 2>/dev/null || true

    if [ -f /etc/bluetooth/main.conf ]; then
        if grep -q "^\[Policy\]" /etc/bluetooth/main.conf; then
            if grep -qE "^#?AutoEnable" /etc/bluetooth/main.conf; then
                sudo sed -i 's/^#\?AutoEnable=.*/AutoEnable=true/' /etc/bluetooth/main.conf
            else
                sudo sed -i '/^\[Policy\]/a AutoEnable=true' /etc/bluetooth/main.conf
            fi
        else
            printf "\n[Policy]\nAutoEnable=true\n" | sudo tee -a /etc/bluetooth/main.conf >/dev/null
        fi
    else
        printf "[Policy]\nAutoEnable=true\n" | sudo tee /etc/bluetooth/main.conf >/dev/null
    fi

    if command -v rfkill &>/dev/null; then
        sudo rfkill unblock bluetooth 2>/dev/null || true
    fi

    enable_system_service "bluetooth" "$init_sys"
    enable_system_service "bluetoothd" "$init_sys"

    if [[ "$init_sys" == "systemd" ]]; then
        sudo systemctl enable --now bluetooth.service 2>/dev/null || sudo systemctl start bluetooth.service 2>/dev/null || true
    fi

    if command -v bluetoothctl &>/dev/null; then
        (sleep 1 && bluetoothctl power on 2>/dev/null || true) &
    fi
}

setup_hibernation() {
    local init_sys
    init_sys=$(detect_init_system)
    [[ "$init_sys" == "systemd" ]] || return 0

    local msg="Configuring system hibernation and swapfile..."
    if command -v t &>/dev/null; then
        msg="$(t "installer.power.hibernation_setup" "$msg")"
    fi
    echo -e "\n\e[36m[ INFO ]\e[0m $msg"

    local total_ram_mb
    total_ram_mb=$(free -m | awk '/^Mem:/{print $2}')
    local total_swap_mb
    total_swap_mb=$(free -m | awk '/^Swap:/{print $2}')
    [ -n "$total_swap_mb" ] || total_swap_mb=0

    # Hibernation requires swap >= RAM. We target RAM + 2048 MB.
    local target_swap_mb=$(( total_ram_mb + 2048 ))
    if [ "$target_swap_mb" -lt 8192 ]; then
        target_swap_mb=8192
    fi

    local swap_file="/swapfile"
    if [ "$total_swap_mb" -lt "$total_ram_mb" ]; then
        local avail_root_mb
        avail_root_mb=$(df -m / | awk 'NR==2{print $4}')
        local min_required_mb=$(( target_swap_mb + 4096 ))

        if [ "$avail_root_mb" -ge "$min_required_mb" ]; then
            echo -e "\e[34m::\e[0m Creating ${target_swap_mb}MB swapfile at $swap_file..."
            if [ ! -f "$swap_file" ]; then
                sudo fallocate -l "${target_swap_mb}M" "$swap_file" 2>/dev/null || \
                sudo dd if=/dev/zero of="$swap_file" bs=1M count="$target_swap_mb" status=progress
                sudo chmod 600 "$swap_file"
                sudo mkswap -U clear "$swap_file"
            fi

            if ! grep -qs "$swap_file" /etc/fstab; then
                echo "$swap_file none swap defaults 0 0" | sudo tee -a /etc/fstab >/dev/null
            fi
            sudo swapon "$swap_file" 2>/dev/null || sudo swapon -a 2>/dev/null || true
        else
            echo -e "\e[33m[ WARN ]\e[0m Insufficient disk space on / to allocate ${target_swap_mb}MB swap for hibernation."
        fi
    fi

    # Configure resume kernel parameter for GRUB if swapfile or swap partition is active
    local root_uuid
    root_uuid=$(findmnt -no UUID -T "$swap_file" 2>/dev/null || findmnt -no UUID / 2>/dev/null || true)
    local resume_offset=""

    if [ -f "$swap_file" ] && command -v filefrag &>/dev/null; then
        resume_offset=$(sudo filefrag -v "$swap_file" 2>/dev/null | awk '{if($1=="0:"){print substr($4, 1, length($4)-2)}}')
    fi

    if [ -n "$root_uuid" ] && [ -n "$resume_offset" ]; then
        # Update GRUB configuration
        if [ -f /etc/default/grub ]; then
            if ! grep -q "resume=" /etc/default/grub; then
                echo -e "\e[34m::\e[0m Adding resume kernel parameters to GRUB..."
                sudo sed -i -E "s/(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*)/\1 resume=UUID=$root_uuid resume_offset=$resume_offset/" /etc/default/grub
                if command -v grub-mkconfig &>/dev/null; then
                    echo -e "\e[34m::\e[0m Generating /boot/grub/grub.cfg..."
                    sudo grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || true
                fi
            fi
        fi

        # Check mkinitcpio hooks for Arch Linux
        if [ -f /etc/mkinitcpio.conf ]; then
            local hooks
            hooks=$(grep '^HOOKS=' /etc/mkinitcpio.conf 2>/dev/null || true)
            # If systemd hook is NOT present and resume hook is NOT present, insert resume before filesystems
            if [[ "$hooks" != *"systemd"* && "$hooks" != *"resume"* ]]; then
                echo -e "\e[34m::\e[0m Adding resume hook to /etc/mkinitcpio.conf..."
                sudo sed -i -E 's/\b(filesystems)\b/resume \1/' /etc/mkinitcpio.conf
                if command -v mkinitcpio &>/dev/null; then
                    echo -e "\e[34m::\e[0m Rebuilding initramfs..."
                    sudo mkinitcpio -P 2>/dev/null || true
                fi
            fi
        fi
        echo -e "\e[32m[ OK ] Hibernation configured successfully\e[0m"
    fi
}

setup_services() {
    local init_sys
    init_sys=$(detect_init_system)

    sudo -v 2>/dev/null || true
    configure_bluetooth "$init_sys"

    if declare -f pm_setup_services >/dev/null; then
        pm_setup_services "$init_sys"
        return 0
    fi

    if [[ "$init_sys" == "systemd" ]]; then
        systemctl --user enable pipewire.socket pipewire-pulse.socket wireplumber.service 2>/dev/null || true
        systemctl --user start pipewire.socket pipewire-pulse.socket wireplumber.service 2>/dev/null || true
    fi

    enable_system_service "NetworkManager" "$init_sys"
    enable_system_service "power-profiles-daemon" "$init_sys"
}
