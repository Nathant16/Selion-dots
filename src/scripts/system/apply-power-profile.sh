#!/usr/bin/env bash
# ==============================================================================
# Universal Battery & Power Optimizer (Adapted from SelionOS + ThinkPad T14)
# ==============================================================================

PROFILE="${1:-balanced}"
case "$PROFILE" in
    performance|balanced|power-saver) ;;
    perf) PROFILE="performance" ;;
    bal)  PROFILE="balanced" ;;
    save) PROFILE="power-saver" ;;
    *) echo "Usage: $0 [performance|balanced|power-saver]" >&2; exit 1 ;;
esac

# ------------------------------------------------------------------------------
# 1. Native power-profiles-daemon (D-Bus)
# ------------------------------------------------------------------------------
if command -v powerprofilesctl >/dev/null 2>&1; then
    powerprofilesctl set "$PROFILE" 2>/dev/null
fi

case "$PROFILE" in
    performance)
        CPU_EPP="performance"
        CPU_GOV="performance"
        ACPI_PROF="performance"
        ;;
    power-saver)
        CPU_EPP="power"
        CPU_GOV="powersave"
        ACPI_PROF="low-power"
        ;;
    balanced|*)
        CPU_EPP="balance_performance"
        CPU_GOV="powersave"
        ACPI_PROF="balanced"
        ;;
esac

# ------------------------------------------------------------------------------
# 2. CPU EPP & Scaling Governors
# ------------------------------------------------------------------------------
for p in /sys/devices/system/cpu/cpufreq/policy*/energy_performance_preference; do
    [ -w "$p" ] && echo "$CPU_EPP" > "$p" 2>/dev/null
done

for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    [ -w "$g" ] && echo "$CPU_GOV" > "$g" 2>/dev/null
done

# ACPI platform_profile (ThinkPad DYTC)
if [ -w /sys/firmware/acpi/platform_profile ]; then
    echo "$ACPI_PROF" > /sys/firmware/acpi/platform_profile 2>/dev/null
fi

# ------------------------------------------------------------------------------
# 3. CPU Turbo Boost Control (AMD Ryzen 4750U)
# ------------------------------------------------------------------------------
case "$PROFILE" in
    power-saver)
        if [ -e /sys/devices/system/cpu/cpufreq/boost ]; then
            if [ -w /sys/devices/system/cpu/cpufreq/boost ]; then
                echo 0 > /sys/devices/system/cpu/cpufreq/boost 2>/dev/null
            elif command -v sudo >/dev/null 2>&1; then
                sudo -n sh -c 'echo 0 > /sys/devices/system/cpu/cpufreq/boost' 2>/dev/null || true
            fi
        fi
        for pb in /sys/devices/system/cpu/cpufreq/policy*/boost; do
            [ -w "$pb" ] && echo 0 > "$pb" 2>/dev/null
        done
        ;;
    balanced|performance)
        if [ -e /sys/devices/system/cpu/cpufreq/boost ]; then
            if [ -w /sys/devices/system/cpu/cpufreq/boost ]; then
                echo 1 > /sys/devices/system/cpu/cpufreq/boost 2>/dev/null
            elif command -v sudo >/dev/null 2>&1; then
                sudo -n sh -c 'echo 1 > /sys/devices/system/cpu/cpufreq/boost' 2>/dev/null || true
            fi
        fi
        for pb in /sys/devices/system/cpu/cpufreq/policy*/boost; do
            [ -w "$pb" ] && echo 1 > "$pb" 2>/dev/null
        done
        ;;
esac

# ------------------------------------------------------------------------------
# 4. PCIe ASPM (Active State Power Management)
# ------------------------------------------------------------------------------
ASPM_PARAM="/sys/module/pcie_aspm/parameters/policy"
if [ -w "$ASPM_PARAM" ]; then
    case "$PROFILE" in
        power-saver) echo powersupersave > "$ASPM_PARAM" 2>/dev/null ;;
        performance) echo performance > "$ASPM_PARAM" 2>/dev/null ;;
        balanced|*)  echo default > "$ASPM_PARAM" 2>/dev/null ;;
    esac
fi

# ------------------------------------------------------------------------------
# 5. AMD RADEON GPU (amdgpu DPM & Power Profile Mode)
# ------------------------------------------------------------------------------
case "$PROFILE" in
    performance)
        AMD_DPM="high"
        AMD_PROF_MODE=1 # 3D_FULL_SCREEN
        ;;
    power-saver)
        AMD_DPM="low"
        AMD_PROF_MODE=2 # POWER_SAVING
        ;;
    balanced|*)
        AMD_DPM="auto"
        AMD_PROF_MODE=0 # DEFAULT
        ;;
esac

for dpm in /sys/class/drm/card*/device/power_dpm_force_performance_level; do
    [ -w "$dpm" ] && echo "$AMD_DPM" > "$dpm" 2>/dev/null
done

for pm in /sys/class/drm/card*/device/pp_power_profile_mode; do
    [ -w "$pm" ] && echo "$AMD_PROF_MODE" > "$pm" 2>/dev/null
done

# ------------------------------------------------------------------------------
# 6. WI-FI POWER SAVE (Intel AX200 / iw)
# ------------------------------------------------------------------------------
if command -v iw >/dev/null 2>&1; then
    WIFI_MODE="on"
    [ "$PROFILE" = "performance" ] && WIFI_MODE="off"
    for w in /sys/class/net/*/wireless; do
        if [ -d "$w" ]; then
            wdev=$(basename "$(dirname "$w")")
            iw dev "$wdev" set power_save "$WIFI_MODE" 2>/dev/null || \
                sudo -n iw dev "$wdev" set power_save "$WIFI_MODE" 2>/dev/null || true
        fi
    done
fi

# ------------------------------------------------------------------------------
# 7. BLUETOOTH SLEEP
# ------------------------------------------------------------------------------
if command -v bluetoothctl >/dev/null 2>&1; then
    if [ "$PROFILE" = "power-saver" ]; then
        BT_CONN=$(bluetoothctl devices Connected 2>/dev/null)
        if [ -z "$BT_CONN" ]; then
            bluetoothctl power off >/dev/null 2>&1 || true
        fi
    else
        bluetoothctl power on >/dev/null 2>&1 || true
    fi
fi

# ------------------------------------------------------------------------------
# 8. AUDIO CODEC POWER SAVE (snd_hda_intel)
# ------------------------------------------------------------------------------
for snd in /sys/module/snd_hda_intel/parameters/power_save; do
    if [ -w "$snd" ]; then
        case "$PROFILE" in
            power-saver|balanced) echo 1 > "$snd" 2>/dev/null ;;
            performance) echo 0 > "$snd" 2>/dev/null ;;
        esac
    fi
done
for snd_c in /sys/module/snd_hda_intel/parameters/power_save_controller; do
    [ -w "$snd_c" ] && echo Y > "$snd_c" 2>/dev/null
done

# ------------------------------------------------------------------------------
# 9. NVMe & USB RUNTIME POWER MANAGEMENT (Protected for Input Devices)
# ------------------------------------------------------------------------------
case "$PROFILE" in
    power-saver)
        for ctrl in /sys/bus/pci/devices/*/power/control; do
            pci_dir=$(dirname "$ctrl")
            if [ -f "$pci_dir/class" ]; then
                pci_class=$(cat "$pci_dir/class" 2>/dev/null)
                if [[ "$pci_class" =~ ^0x0c03 ]]; then
                    [ -w "$ctrl" ] && echo on > "$ctrl" 2>/dev/null
                    continue
                fi
            fi
            [ -w "$ctrl" ] && echo auto > "$ctrl" 2>/dev/null
        done
        for uctrl in /sys/bus/usb/devices/*/power/control; do
            udev_dir=$(dirname "$uctrl")
            prod=$(cat "$udev_dir/product" 2>/dev/null || cat "$udev_dir/../product" 2>/dev/null)
            vendor=$(cat "$udev_dir/idVendor" 2>/dev/null || cat "$udev_dir/../idVendor" 2>/dev/null)
            if [[ "$prod" =~ (Receiver|Mouse|Keyboard) ]] || [ "$vendor" = "046d" ]; then
                [ -w "$uctrl" ] && echo on > "$uctrl" 2>/dev/null
                [ -w "$udev_dir/autosuspend_delay_ms" ] && echo -1 > "$udev_dir/autosuspend_delay_ms" 2>/dev/null
            else
                [ -w "$uctrl" ] && echo auto > "$uctrl" 2>/dev/null
            fi
        done
        ;;
    balanced|performance)
        for ctrl in /sys/bus/pci/devices/*/power/control; do
            [ -w "$ctrl" ] && echo on > "$ctrl" 2>/dev/null
        done
        for uctrl in /sys/bus/usb/devices/*/power/control; do
            [ -w "$uctrl" ] && echo on > "$uctrl" 2>/dev/null
        done
        ;;
esac

# ------------------------------------------------------------------------------
# 10. DISK WRITEBACK CENTISECS
# ------------------------------------------------------------------------------
DIRTY_PARAM="/proc/sys/vm/dirty_writeback_centisecs"
if [ -w "$DIRTY_PARAM" ]; then
    if [ "$PROFILE" = "power-saver" ]; then
        echo 6000 > "$DIRTY_PARAM" 2>/dev/null
    else
        echo 500 > "$DIRTY_PARAM" 2>/dev/null
    fi
elif command -v sysctl >/dev/null 2>&1; then
    VAL=$([ "$PROFILE" = "power-saver" ] && echo 6000 || echo 500)
    sudo -n sysctl -q -w "vm.dirty_writeback_centisecs=$VAL" 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 11. NMI WATCHDOG (CPU Deep C-States)
# ------------------------------------------------------------------------------
NMI_PARAM="/proc/sys/kernel/nmi_watchdog"
if [ -w "$NMI_PARAM" ]; then
    if [ "$PROFILE" = "power-saver" ]; then
        echo 0 > "$NMI_PARAM" 2>/dev/null
    else
        echo 1 > "$NMI_PARAM" 2>/dev/null
    fi
elif command -v sysctl >/dev/null 2>&1; then
    VAL=$([ "$PROFILE" = "power-saver" ] && echo 0 || echo 1)
    sudo -n sysctl -q -w "kernel.nmi_watchdog=$VAL" 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 12. DRIFTWM ANIMATED BACKGROUND SHADER TOGGLE
# ------------------------------------------------------------------------------
DRIFT_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/driftwm/config.toml"
if [ -f "$DRIFT_CONF" ] && command -v driftwm >/dev/null 2>&1; then
    if [ "$PROFILE" = "power-saver" ]; then
        if grep -q '^type = "shader"' "$DRIFT_CONF" 2>/dev/null; then
            sed -i 's/^type = "shader"/type = "default"/' "$DRIFT_CONF"
            driftwm msg action reload-config >/dev/null 2>&1 || true
        fi
    else
        if grep -q '^type = "default"' "$DRIFT_CONF" 2>/dev/null; then
            sed -i 's/^type = "default"/type = "shader"/' "$DRIFT_CONF"
            driftwm msg action reload-config >/dev/null 2>&1 || true
        fi
    fi
fi

# ------------------------------------------------------------------------------
# 13. USER SAVED POWER OPTIMIZATIONS OVERRIDE
# ------------------------------------------------------------------------------
OPTS_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/serpantinum/power_optimizations.json"
if [ -f "$OPTS_CONF" ]; then
    BATTERY_SCRIPT="${SERPANTINUM_DIR:-$HOME/.local/share/serpantinum/src}/scripts/system/battery"
    if [ -f "$BATTERY_SCRIPT" ]; then
        python3 "$BATTERY_SCRIPT" apply-opts >/dev/null 2>&1 || true
    elif command -v battery >/dev/null 2>&1; then
        battery apply-opts >/dev/null 2>&1 || true
    fi
fi

exit 0
