--  █▀▀█  █▀▀█  █  █ 　  █▀▀▄  █▀▀▀ ▀▀█▀▀  █▀▀▀  █▀▀█ ▀▀█▀▀
--  █ ▄▄  █▄▄█  █  █ 　  █  █  █▀▀▀   █    █▀▀▀  █      █
--  █▄▄█  █     ▀▄▄▀ 　  █▄▄▀  █▄▄▄   █    █▄▄▄  █▄▄█   █

-- GPU Auto-detection
local function detect_gpu_setup()
    local override = os.getenv("GPU_SETUP")
    if override and override ~= "" then
        return override
    end

    local handle = io.popen([[
        has_nvidia=0; has_nouveau=0; has_amd=0; has_intel=0
        for d in /sys/bus/pci/devices/*; do
            [ -r "$d/class" ] || continue
            read -r cls < "$d/class"
            case "$cls" in
                0x03*)
                    [ -r "$d/vendor" ] || continue
                    read -r ven < "$d/vendor"
                    drv=""
                    if [ -L "$d/driver" ]; then
                        drv_path=$(readlink "$d/driver" 2>/dev/null)
                        drv="${drv_path##*/}"
                    fi
                    case "$ven" in
                        0x10de)
                            if [ "$drv" = "nouveau" ]; then
                                has_nouveau=1
                            else
                                has_nvidia=1
                            fi
                            ;;
                        0x1002) has_amd=1 ;;
                        0x8086) has_intel=1 ;;
                    esac
                    ;;
            esac
        done
        if [ "$has_nvidia" -eq 1 ]; then
            if [ "$has_intel" -eq 1 ]; then echo "hybrid-intel-nvidia"
            elif [ "$has_amd" -eq 1 ]; then echo "hybrid-amd-nvidia"
            else echo "nvidia-only"
            fi
        elif [ "$has_amd" -eq 1 ] && [ "$has_intel" -eq 1 ]; then
            echo "hybrid-amd-intel"
        elif [ "$has_amd" -eq 1 ]; then
            echo "amd-only"
        elif [ "$has_nouveau" -eq 1 ]; then
            if [ "$has_intel" -eq 1 ]; then echo "hybrid-intel-nouveau"
            elif [ "$has_amd" -eq 1 ]; then echo "hybrid-amd-nouveau"
            else echo "nouveau-only"
            fi
        elif [ "$has_intel" -eq 1 ]; then
            echo "intel-only"
        else
            echo "unknown"
        fi
    ]])
    if handle then
        local result = handle:read("*l")
        handle:close()
        if result and result ~= "" then
            return result
        end
    end
    return "unknown"
end

local function has_nvidia_vaapi()
    for _, path in ipairs({
        "/usr/lib/dri/nvidia_drv_video.so",
        "/usr/lib64/dri/nvidia_drv_video.so",
    }) do
        local f = io.open(path, "r")
        if f then
            f:close()
            return true
        end
    end
    return false
end

local gpu_setup = detect_gpu_setup()
local env_vars = {}
_G.SELION_GPU_NO_HW_CURSOR = false

if gpu_setup == "nvidia-only" then
    -- Proprietary NVIDIA (single GPU)
    env_vars = {
        { "LIBVA_DRIVER_NAME", "nvidia" },
        { "__GLX_VENDOR_LIBRARY_NAME", "nvidia" }, -- Disable in gpu-env.lua / userprefs if screensharing breaks
        { "__GL_VRR_ALLOWED", "1" },
        -- { "GBM_BACKEND", "nvidia-drm" }, -- Legacy fallback; may crash Firefox on modern drivers
    }
    if has_nvidia_vaapi() then
        table.insert(env_vars, { "NVD_BACKEND", "direct" }) -- Requires libva-nvidia-driver
    end
    _G.SELION_GPU_NO_HW_CURSOR = true
elseif gpu_setup == "hybrid-intel-nvidia" or gpu_setup == "hybrid-amd-nvidia" then
    -- Hybrid iGPU + NVIDIA
    env_vars = {
        { "__GLX_VENDOR_LIBRARY_NAME", "nvidia" },
        { "VK_LAYER_NV_optimus", "1" },
    }
    if has_nvidia_vaapi() then
        table.insert(env_vars, { "NVD_BACKEND", "direct" })
    end
    _G.SELION_GPU_NO_HW_CURSOR = true
end

for _, pair in ipairs(env_vars) do
    hl.env(pair[1], pair[2])
end

-- Optional user overrides (~/.config/hypr/gpu-env.lua)
local override_path = (os.getenv("HOME") or "") .. "/.config/hypr/gpu-env.lua"
local f = io.open(override_path, "r")
if f then
    f:close()
    pcall(dofile, override_path)
end
