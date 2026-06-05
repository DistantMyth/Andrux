#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# Andrux — detect.sh
# Hardware & environment detection library.
#
# Provides:
#   • GPU detection and acceleration method selection
#   • SoC / CPU identification
#   • RAM and storage queries
#   • DRI node and Vulkan availability checks
#   • A pretty-printed device info summary
#
# This file is sourced by the main `andrux` script and depends on common.sh
# being loaded first.
# ==============================================================================

# Guard against double-sourcing
[[ -n "$_ANDRUX_DETECT_LOADED" ]] && return 0
_ANDRUX_DETECT_LOADED=1

# ==============================================================================
# GPU Detection
# ==============================================================================

# detect_gpu
# Identifies the GPU vendor and sets the global GPU_TYPE variable.
# Detection order:
#   1. Android system properties (Vulkan / EGL driver names)
#   2. Vendor EGL library filenames under /vendor/lib64/egl/
#   3. Fallback: "unknown"
detect_gpu() {
    local vulkan_prop egl_prop vendor_libs

    # --- Method 1: system properties ---
    vulkan_prop="$(getprop ro.hardware.vulkan 2>/dev/null || true)"
    egl_prop="$(getprop ro.hardware.egl 2>/dev/null || true)"

    # Normalise to lowercase for matching.
    vulkan_prop="${vulkan_prop,,}"
    egl_prop="${egl_prop,,}"

    if [[ "$vulkan_prop" == *mali* || "$egl_prop" == *mali* ]]; then
        GPU_TYPE="mali"
        log_info "GPU detected via system props: Mali"
        return 0
    elif [[ "$vulkan_prop" == *adreno* || "$egl_prop" == *adreno* ]]; then
        GPU_TYPE="adreno"
        log_info "GPU detected via system props: Adreno"
        return 0
    elif [[ "$vulkan_prop" == *powervr* || "$egl_prop" == *powervr* ||
            "$vulkan_prop" == *pvr*     || "$egl_prop" == *pvr* ]]; then
        GPU_TYPE="powervr"
        log_info "GPU detected via system props: PowerVR"
        return 0
    fi

    # --- Method 2: vendor EGL libraries ---
    # On many devices the EGL driver shared objects contain the vendor name.
    vendor_libs=""
    if [[ -d /vendor/lib64/egl ]]; then
        vendor_libs="$(ls /vendor/lib64/egl/ 2>/dev/null || true)"
    elif [[ -d /vendor/lib/egl ]]; then
        # ARM32 fallback path
        vendor_libs="$(ls /vendor/lib/egl/ 2>/dev/null || true)"
    fi

    vendor_libs="${vendor_libs,,}"

    if [[ "$vendor_libs" == *mali* ]]; then
        GPU_TYPE="mali"
        log_info "GPU detected via vendor libs: Mali"
        return 0
    elif [[ "$vendor_libs" == *adreno* ]]; then
        GPU_TYPE="adreno"
        log_info "GPU detected via vendor libs: Adreno"
        return 0
    elif [[ "$vendor_libs" == *powervr* || "$vendor_libs" == *pvr* ]]; then
        GPU_TYPE="powervr"
        log_info "GPU detected via vendor libs: PowerVR"
        return 0
    fi

    # --- Fallback ---
    GPU_TYPE="unknown"
    log_warn "GPU type could not be determined — defaulting to 'unknown'"
}

# detect_gpu_method
# Chooses the best GPU acceleration method based on GPU_TYPE and sets
# GPU_METHOD.  Call detect_gpu first.
#
# Decision matrix:
#   mali     → angle-vulkan   (ANGLE translating GL→Vulkan, best for Mali)
#   adreno   → turnip-zink    (Adreno 6xx/7xx) or virgl (older)
#   powervr  → virgl          (no native Vulkan driver in proot)
#   unknown  → llvmpipe       (pure software fallback)
detect_gpu_method() {
    if [[ -z "$GPU_TYPE" ]]; then
        log_warn "detect_gpu_method: GPU_TYPE not set, running detect_gpu first"
        detect_gpu
    fi

    case "$GPU_TYPE" in
        mali)
            GPU_METHOD="angle-vulkan"
            log_info "GPU acceleration method: ANGLE over Vulkan (Mali)"
            ;;
        adreno)
            # Try to determine the Adreno generation.
            # Qualcomm exposes the GPU model in various props.
            local adreno_model
            adreno_model="$(getprop ro.hardware.vulkan 2>/dev/null || true)"
            # Some devices use a numeric identifier; 6xx and 7xx support Turnip.
            if _adreno_supports_turnip "$adreno_model"; then
                GPU_METHOD="turnip-zink"
                log_info "GPU acceleration method: Turnip + Zink (Adreno 6xx/7xx)"
            else
                GPU_METHOD="virgl"
                log_info "GPU acceleration method: VirGL (older Adreno)"
            fi
            ;;
        powervr)
            GPU_METHOD="virgl"
            log_info "GPU acceleration method: VirGL (PowerVR)"
            ;;
        *)
            GPU_METHOD="llvmpipe"
            log_warn "GPU acceleration method: LLVMpipe (software rendering)"
            ;;
    esac
}

# _adreno_supports_turnip "model_string"
# Internal helper — returns 0 if the Adreno GPU supports the Turnip Vulkan
# driver (broadly: Adreno 6xx and 7xx series).
_adreno_supports_turnip() {
    local model="${1,,}"

    # If we can extract a generation number (e.g. "adreno (tm) 730" → 7),
    # check if it's >= 6.
    local gen
    gen="$(echo "$model" | grep -oP '(?:adreno[^0-9]*)\K[0-9]' | head -n1)"

    if [[ -n "$gen" && "$gen" -ge 6 ]]; then
        return 0   # Turnip-compatible
    fi

    # Heuristic: if the prop just says "adreno" without a number, inspect the
    # SoC.  Snapdragon 845+ (SDM845, SM8*) generally have Adreno 6xx+.
    local soc
    soc="$(getprop ro.soc.model 2>/dev/null || true)"
    soc="${soc,,}"
    if [[ "$soc" == sm8* || "$soc" == sdm845* ]]; then
        return 0
    fi

    return 1   # Not Turnip-compatible; fall back to VirGL.
}

# ==============================================================================
# SoC / CPU Detection
# ==============================================================================

# detect_soc
# Prints a single-line SoC summary, e.g. "MediaTek Dimensity 9400".
detect_soc() {
    local manufacturer model

    manufacturer="$(getprop ro.soc.manufacturer 2>/dev/null || true)"
    model="$(getprop ro.soc.model 2>/dev/null || true)"

    if [[ -n "$manufacturer" || -n "$model" ]]; then
        echo "${manufacturer:+$manufacturer }${model:-Unknown}"
    else
        # Fallback: try /proc/cpuinfo
        local hw
        hw="$(grep -m1 'Hardware' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs)"
        echo "${hw:-Unknown SoC}"
    fi
}

# ==============================================================================
# Android Version
# ==============================================================================

# detect_android_version
# Returns the user-facing Android version number (e.g. "16").
detect_android_version() {
    local ver
    ver="$(getprop ro.build.version.release 2>/dev/null || true)"
    echo "${ver:-Unknown}"
}

# ==============================================================================
# RAM
# ==============================================================================

# detect_ram
# Returns total physical RAM in GB (integer, rounded).
detect_ram() {
    local mem_kb mem_gb

    mem_kb="$(grep -m1 '^MemTotal' /proc/meminfo 2>/dev/null | awk '{print $2}')"

    if [[ -n "$mem_kb" ]]; then
        # Integer arithmetic: add 512*1024 for rounding before dividing.
        mem_gb=$(( (mem_kb + 524288) / 1048576 ))
        echo "$mem_gb"
    else
        echo "Unknown"
    fi
}

# ==============================================================================
# Storage
# ==============================================================================

# detect_storage
# Returns available (free) storage in GB on the Termux home partition.
detect_storage() {
    local avail_kb avail_gb

    avail_kb="$(df -k "$HOME" 2>/dev/null | awk 'NR==2{print $4}')"

    if [[ -n "$avail_kb" ]]; then
        avail_gb=$(( avail_kb / 1048576 ))
        echo "$avail_gb"
    else
        echo "Unknown"
    fi
}

# ==============================================================================
# DRI & Vulkan Checks
# ==============================================================================

# check_dri
# Returns 0 if at least one usable DRI render node exists.
check_dri() {
    if [[ -c /dev/dri/renderD128 ]]; then
        log_info "DRI render node found: /dev/dri/renderD128"
        return 0
    elif [[ -c /dev/dri/card0 ]]; then
        log_info "DRI card node found: /dev/dri/card0"
        return 0
    fi

    log_warn "No DRI nodes found — hardware acceleration may be unavailable"
    return 1
}

# check_vulkan
# Returns 0 if Vulkan appears to be functional (vulkaninfo succeeds).
check_vulkan() {
    if ! check_command vulkaninfo; then
        log_warn "vulkaninfo not found — Vulkan availability unknown"
        return 1
    fi

    if vulkaninfo --summary &>/dev/null; then
        log_info "Vulkan is available"
        return 0
    fi

    log_warn "vulkaninfo failed — Vulkan may not be functional"
    return 1
}

# ==============================================================================
# Architecture Detection
# ==============================================================================

# detect_arch
# Echoes the CPU architecture string: aarch64 or armv7l (or other).
detect_arch() {
    uname -m
}

# ==============================================================================
# Pretty-Print Device Summary
# ==============================================================================

# print_device_info
# Prints a nicely formatted table with all detected hardware information.
print_device_info() {
    local soc android_ver ram storage arch dri_status vulkan_status

    soc="$(detect_soc)"
    android_ver="$(detect_android_version)"
    ram="$(detect_ram)"
    storage="$(detect_storage)"
    arch="$(detect_arch)"

    # DRI / Vulkan status strings
    if check_dri 2>/dev/null; then
        dri_status="${GREEN}Available${RESET}"
    else
        dri_status="${RED}Not found${RESET}"
    fi

    if check_vulkan 2>/dev/null; then
        vulkan_status="${GREEN}Available${RESET}"
    else
        vulkan_status="${YELLOW}Not available${RESET}"
    fi

    # Ensure GPU_TYPE is populated.
    [[ -z "$GPU_TYPE" ]] && detect_gpu
    [[ -z "$GPU_METHOD" ]] && detect_gpu_method

    local separator="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    printf "\n" >&2
    printf "${BOLD}${CYAN}  ╔${separator}╗${RESET}\n" >&2
    printf "${BOLD}${CYAN}  ║       DEVICE INFORMATION                ║${RESET}\n" >&2
    printf "${BOLD}${CYAN}  ╠${separator}╣${RESET}\n" >&2
    printf "  ${CYAN}║${RESET}  %-18s %s\n"  "SoC:"             "$soc"             >&2
    printf "  ${CYAN}║${RESET}  %-18s %s\n"  "Architecture:"    "$arch"            >&2
    printf "  ${CYAN}║${RESET}  %-18s %s\n"  "Android:"         "$android_ver"     >&2
    printf "  ${CYAN}║${RESET}  %-18s %s GB\n" "RAM:"           "$ram"             >&2
    printf "  ${CYAN}║${RESET}  %-18s %s GB\n" "Free Storage:"  "$storage"         >&2
    printf "  ${CYAN}║${RESET}  %-18s %s\n"  "GPU:"             "$GPU_TYPE"        >&2
    printf "  ${CYAN}║${RESET}  %-18s %s\n"  "GPU Method:"      "$GPU_METHOD"      >&2
    printf "  ${CYAN}║${RESET}  %-18s %b\n"  "DRI Nodes:"       "$dri_status"      >&2
    printf "  ${CYAN}║${RESET}  %-18s %b\n"  "Vulkan:"          "$vulkan_status"   >&2
    printf "${BOLD}${CYAN}  ╚${separator}╝${RESET}\n" >&2
    printf "\n" >&2
}
