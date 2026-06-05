#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# Andrux — gpu.sh
# GPU acceleration setup for hardware-accelerated OpenGL inside proot-distro.
#
# Supported acceleration methods (set in $GPU_METHOD):
#   angle-vulkan  — Mali GPUs via ANGLE's Vulkan backend + virglrenderer
#   turnip-zink   — Adreno 6xx/7xx via Turnip (Vulkan) + Zink (GL-on-VK)
#   virgl         — Generic virglrenderer (software host-side GL)
#   llvmpipe      — Pure software rasterisation (no GPU needed)
#
# Provides:
#   setup_gpu_acceleration  — install & configure the chosen method
#   get_virgl_start_command — command to start the host-side VirGL server
#   get_gpu_env_vars        — env-var exports for inside proot
#   test_gpu                — quick smoke-test (glxinfo / glxgears)
#
# Depends on (sourced before this file):
#   common.sh → log_*, run_proot_cmd, run_proot_cmd_user,
#               get_proot_pkg_manager, get_proot_install_cmd,
#               GPU_TYPE, GPU_METHOD, DISTRO_NAME
# =============================================================================

# ---------- internal helpers -------------------------------------------------

# _install_termux_gpu_packages
#   Ensures the Termux host has the VirGL server and (optionally) ANGLE libs.
_install_termux_gpu_packages() {
    local method="$1"

    log_info "Installing Termux-side GPU packages for method '${method}'…"

    # virglrenderer-android is needed for angle-vulkan, virgl, and
    # optionally for turnip-zink when using virgl as a transport.
    case "${method}" in
        angle-vulkan)
            pkg install -y virglrenderer-android angle-android 2>/dev/null || {
                log_error "Failed to install virglrenderer-android / angle-android in Termux."
                log_error "Make sure the x11-repo is enabled:  pkg install x11-repo"
                return 1
            }
            ;;
        turnip-zink)
            # Turnip uses the phone's Vulkan ICD directly; virglrenderer is
            # only needed if we decide to tunnel through virgl (uncommon).
            pkg install -y virglrenderer-android 2>/dev/null || {
                log_warn "virglrenderer-android not installed — Turnip+Zink may still work without it."
            }
            ;;
        virgl)
            pkg install -y virglrenderer-android 2>/dev/null || {
                log_error "Failed to install virglrenderer-android in Termux."
                return 1
            }
            ;;
        llvmpipe)
            # No host-side packages required for software rendering.
            log_info "Software rendering selected — no Termux GPU packages needed."
            ;;
    esac
}

# _install_proot_mesa_packages
#   Installs the Mesa OpenGL stack inside the proot distro so that
#   applications can use libGL / libEGL.
_install_proot_mesa_packages() {
    local pkg_mgr
    pkg_mgr="$(get_proot_pkg_manager)"
    local packages=""

    case "${pkg_mgr}" in
        apt)
            packages="mesa-utils libgl1-mesa-glx libegl1-mesa"
            ;;
        pacman)
            packages="mesa-utils mesa"
            ;;
        dnf)
            packages="mesa-dri-drivers mesa-libGL glx-utils"
            ;;
        *)
            log_error "Unsupported package manager '${pkg_mgr}' for Mesa install."
            return 1
            ;;
    esac

    log_info "Installing Mesa packages inside proot: ${packages}"
    run_proot_cmd "$(get_proot_install_cmd) ${packages}" || {
        log_error "Mesa package installation failed inside proot."
        return 1
    }
}

# ---------- public API -------------------------------------------------------

# -----------------------------------------------------------------------------
# setup_gpu_acceleration
#   Main entry point.  Installs everything needed for the GPU_METHOD that was
#   detected (or chosen) earlier by the hardware-detection phase.
# -----------------------------------------------------------------------------
setup_gpu_acceleration() {
    log_step "Setting up GPU acceleration (method: ${GPU_METHOD}, GPU: ${GPU_TYPE})…"

    # 1. Install host-side (Termux) packages
    _install_termux_gpu_packages "${GPU_METHOD}" || return 1

    # 2. Install guest-side (proot) Mesa/GL packages
    _install_proot_mesa_packages || return 1

    # 3. Method-specific configuration inside proot
    case "${GPU_METHOD}" in
        angle-vulkan)
            _configure_angle_vulkan
            ;;
        turnip-zink)
            _configure_turnip_zink
            ;;
        virgl)
            _configure_virgl
            ;;
        llvmpipe)
            _configure_llvmpipe
            ;;
        *)
            log_error "Unknown GPU method: '${GPU_METHOD}'."
            return 1
            ;;
    esac

    log_success "GPU acceleration setup complete (${GPU_METHOD})."
}

# -- Per-method configuration helpers -----------------------------------------

_configure_angle_vulkan() {
    log_info "Configuring ANGLE-Vulkan pipeline (Mali GPU)…"

    # The VirGL server on the Termux side uses ANGLE's Vulkan backend to
    # translate OpenGL → Vulkan.  Inside the proot guest, Mesa's virpipe
    # Gallium driver talks to that server over a Unix socket.
    _write_gpu_env_file
}

_configure_turnip_zink() {
    log_info "Configuring Turnip + Zink pipeline (Adreno GPU)…"

    # Turnip is a Vulkan ICD for Adreno 6xx/7xx.  Zink is a Gallium
    # driver that translates OpenGL calls into Vulkan, using Turnip.
    # This provides near-native GL performance on supported Adreno GPUs.
    _write_gpu_env_file
}

_configure_virgl() {
    log_info "Configuring generic VirGL pipeline…"
    _write_gpu_env_file
}

_configure_llvmpipe() {
    log_info "Configuring software rendering (llvmpipe)…"
    _write_gpu_env_file
}

# _write_gpu_env_file
#   Writes the environment variables into a sourceable file inside proot
#   so that the session launcher can simply `. /etc/andrux-gpu-env`.
_write_gpu_env_file() {
    local env_vars
    env_vars="$(get_gpu_env_vars)"

    run_proot_cmd "cat > /etc/andrux-gpu-env << 'GEOF'
# Andrux — GPU environment variables
# Source this file before starting the desktop session.
# Generated by andrux gpu.sh — do not edit manually.
${env_vars}
GEOF"

    log_info "GPU environment written to /etc/andrux-gpu-env inside proot."
}

# -----------------------------------------------------------------------------
# get_virgl_start_command
#   Returns the shell command to start the VirGL / rendering server on the
#   Termux host.  Must be run BEFORE entering proot.
# -----------------------------------------------------------------------------
get_virgl_start_command() {
    case "${GPU_METHOD}" in
        angle-vulkan)
            # --angle-vulkan tells virgl_test_server_android to use ANGLE's
            # Vulkan backend instead of the default EGL path.
            echo "virgl_test_server_android --angle-vulkan &"
            ;;
        turnip-zink)
            # For Turnip+Zink the guest drives Vulkan directly; a VirGL
            # server is optional but can be used as fallback transport.
            echo "MESA_VK_WSI_PRESENT_MODE=fifo virgl_test_server_android &"
            ;;
        virgl)
            echo "virgl_test_server_android &"
            ;;
        llvmpipe)
            # No server needed — everything is CPU-rendered.
            echo ""
            ;;
        *)
            log_warn "get_virgl_start_command: unknown method '${GPU_METHOD}'."
            echo ""
            ;;
    esac
}

# -----------------------------------------------------------------------------
# get_gpu_env_vars
#   Returns a multi-line string of export statements to be evaluated inside
#   the proot session.  These tell Mesa which Gallium driver to use.
# -----------------------------------------------------------------------------
get_gpu_env_vars() {
    case "${GPU_METHOD}" in
        angle-vulkan)
            cat <<'EOF'
export GALLIUM_DRIVER=virpipe
export MESA_GL_VERSION_OVERRIDE=4.6COMPAT
export MESA_GLES_VERSION_OVERRIDE=3.2
EOF
            ;;
        turnip-zink)
            cat <<'EOF'
export GALLIUM_DRIVER=zink
export MESA_VK_WSI_PRESENT_MODE=fifo
EOF
            ;;
        virgl)
            cat <<'EOF'
export GALLIUM_DRIVER=virpipe
EOF
            ;;
        llvmpipe)
            cat <<'EOF'
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe
EOF
            ;;
        *)
            log_warn "get_gpu_env_vars: unknown method '${GPU_METHOD}'."
            echo "# unknown GPU method"
            ;;
    esac
}

# -----------------------------------------------------------------------------
# test_gpu
#   Quick smoke-test to verify that the GPU pipeline is functional.
#   Tries glxinfo first (detailed); falls back to a simple GL query.
# -----------------------------------------------------------------------------
test_gpu() {
    log_step "Testing GPU acceleration (${GPU_METHOD})…"

    local env_prefix
    env_prefix="$(get_gpu_env_vars | tr '\n' ' ')"

    # --- Start the VirGL server if needed ---
    local virgl_cmd
    virgl_cmd="$(get_virgl_start_command)"
    local virgl_pid=""

    if [ -n "${virgl_cmd}" ]; then
        log_info "Starting VirGL server for test…"
        eval "${virgl_cmd}"
        virgl_pid="$!"
        # Give the server a moment to initialise
        sleep 2
    fi

    # --- Run glxinfo inside proot ---
    log_info "Running glxinfo inside proot…"
    local glx_output
    glx_output="$(run_proot_cmd_user "${env_prefix} glxinfo 2>&1" 2>/dev/null)" || true

    if echo "${glx_output}" | grep -qi "OpenGL renderer"; then
        local renderer
        renderer="$(echo "${glx_output}" | grep -i "OpenGL renderer" | head -1)"
        local version
        version="$(echo "${glx_output}" | grep -i "OpenGL version" | head -1)"
        log_success "GPU test passed!"
        log_info "  ${renderer}"
        log_info "  ${version}"
    else
        log_warn "glxinfo did not return renderer info."
        log_info "Attempting fallback test with glxgears…"

        # Try glxgears for 3 seconds
        run_proot_cmd_user "${env_prefix} timeout 3 glxgears -info 2>&1 | head -5" 2>/dev/null && {
            log_success "glxgears ran successfully — GPU pipeline appears functional."
        } || {
            log_error "GPU test failed.  Possible causes:"
            log_error "  • VirGL server not running or crashed"
            log_error "  • Mesa not compiled with the required Gallium driver"
            log_error "  • Missing libGL / libEGL inside proot"
        }
    fi

    # --- Clean up the VirGL server we started ---
    if [ -n "${virgl_pid}" ]; then
        kill "${virgl_pid}" 2>/dev/null
        wait "${virgl_pid}" 2>/dev/null
    fi
}
