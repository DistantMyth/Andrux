#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# Andrux — audio.sh
# PulseAudio TCP bridge between Termux (host) and proot-distro (guest).
#
# Architecture:
#   Termux runs PulseAudio as a TCP server on 127.0.0.1:4713.
#   Inside proot, applications connect to that server via the loopback
#   interface, which proot forwards transparently.  This is the ONLY
#   reliable audio path in a proot environment (no Unix sockets across
#   the proot boundary, no pipewire socket sharing).
#
# Provides:
#   setup_audio  — full setup (Termux server config + proot client config)
#   start_audio  — start the PulseAudio TCP server on the Termux host
#   stop_audio   — stop the PulseAudio server
#   test_audio   — verify the audio bridge from inside proot
#
# Depends on (sourced before this file):
#   common.sh → log_*, run_proot_cmd, run_proot_cmd_user,
#               get_proot_pkg_manager, get_proot_install_cmd,
#               USERNAME, ANDRUX_DIR, ANDRUX_CONFIG
# =============================================================================

# Default PulseAudio TCP port
readonly _PA_PORT=4713

# -----------------------------------------------------------------------------
# setup_audio
#   Complete audio setup:
#     1. Ensure PulseAudio is installed in Termux
#     2. Write the Termux-side PulseAudio config (default.pa)
#     3. Install PulseAudio client inside proot
#     4. Write the proot-side client.conf
# -----------------------------------------------------------------------------
setup_audio() {
    log_step "Setting up PulseAudio TCP audio bridge…"

    # ---- 1. Termux-side PulseAudio ----
    log_info "Ensuring PulseAudio is installed in Termux…"
    if ! command -v pulseaudio >/dev/null 2>&1; then
        pkg install -y pulseaudio 2>/dev/null || {
            log_error "Failed to install PulseAudio in Termux."
            return 1
        }
    fi
    log_info "PulseAudio $(pulseaudio --version 2>/dev/null || echo '(version unknown)') available in Termux."

    # ---- 2. Termux PulseAudio configuration ----
    _write_termux_pa_config || return 1

    # ---- 3. Install PulseAudio client inside proot ----
    _install_proot_pa_client || return 1

    # ---- 4. Proot-side client configuration ----
    _write_proot_pa_client_config || return 1

    log_success "Audio bridge setup complete."
}

# -----------------------------------------------------------------------------
# _write_termux_pa_config   (internal)
#   Creates $ANDRUX_CONFIG/pulse/default.pa with modules needed for:
#     • TCP listener on loopback (for proot clients)
#     • Unix socket (for local Termux clients)
#     • SLES sink (Android OpenSL ES audio output)
# -----------------------------------------------------------------------------
_write_termux_pa_config() {
    local pa_dir="${ANDRUX_CONFIG}/pulse"

    log_info "Writing Termux PulseAudio config → ${pa_dir}/default.pa"
    mkdir -p "${pa_dir}" || {
        log_error "Cannot create directory: ${pa_dir}"
        return 1
    }

    cat > "${pa_dir}/default.pa" << 'PAEOF'
#!/data/data/com.termux/files/usr/bin/pulseaudio -nF
#
# Andrux — Termux-side PulseAudio configuration
# Accepts connections from proot over TCP loopback.

# ---- Protocol modules ----
# TCP on loopback — the proot guest connects here.
load-module module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1

# Unix socket — for any Termux-local PA clients.
load-module module-native-protocol-unix

# ---- Sink modules ----
# SLES sink — routes audio to Android's OpenSL ES backend.
load-module module-sles-sink

# Null sink — fallback so PA always has at least one sink available.
load-module module-null-sink sink_name=auto_null

# ---- Auto-detect ----
.ifexists module-detect.so
load-module module-detect
.endif
PAEOF

    log_info "Termux PA config written."
}

# -----------------------------------------------------------------------------
# _install_proot_pa_client   (internal)
#   Installs the PulseAudio client package inside proot.
# -----------------------------------------------------------------------------
_install_proot_pa_client() {
    # If a PA provider is already installed (e.g. pipewire-pulse installed by KDE),
    # pactl will be available. We can skip installation to avoid conflicts.
    if run_proot_cmd "which pactl" >/dev/null 2>&1; then
        log_info "PulseAudio client tools already installed (skipping)."
        return 0
    fi

    local pkg_mgr
    pkg_mgr="$(get_proot_pkg_manager)"
    local packages=""

    case "${pkg_mgr}" in
        apt)    packages="pulseaudio" ;;
        pacman) packages="pulseaudio" ;;
        dnf)    packages="pulseaudio" ;;
        *)
            log_error "Unsupported package manager '${pkg_mgr}' for PulseAudio."
            return 1
            ;;
    esac

    log_info "Installing PulseAudio client inside proot…"
    run_proot_cmd "$(get_proot_install_cmd) ${packages}" || {
        log_error "PulseAudio installation failed inside proot."
        return 1
    }
}

# -----------------------------------------------------------------------------
# _write_proot_pa_client_config   (internal)
#   Creates /home/$USERNAME/.config/pulse/client.conf inside proot so that
#   every PA-aware application inside proot automatically connects to the
#   Termux TCP server.
# -----------------------------------------------------------------------------
_write_proot_pa_client_config() {
    local user_home="/home/${USERNAME}"
    local conf_dir="${user_home}/.config/pulse"

    log_info "Writing proot PulseAudio client config…"

    run_proot_cmd_user "mkdir -p ${conf_dir}" || {
        log_error "Cannot create ${conf_dir} inside proot."
        return 1
    }

    run_proot_cmd_user "cat > ${conf_dir}/client.conf << 'PCEOF'
# Andrux — PulseAudio client configuration (proot guest)
# Connects to the Termux PulseAudio TCP server on loopback.
default-server = tcp:127.0.0.1:${_PA_PORT}
auto-connect-localhost = yes
autospawn = no
PCEOF"

    # Also set PULSE_SERVER in the user's profile so non-PA-native apps
    # (e.g. those using libao or SDL) pick it up through environment.
    run_proot_cmd_user "grep -q 'PULSE_SERVER' ${user_home}/.bashrc 2>/dev/null || \
        echo 'export PULSE_SERVER=tcp:127.0.0.1:${_PA_PORT}' >> ${user_home}/.bashrc"

    log_info "Proot PA client config written."
}

# -----------------------------------------------------------------------------
# start_audio
#   Starts the PulseAudio server on the Termux host.
#   If PA is already running it is killed and restarted with our config.
# -----------------------------------------------------------------------------
start_audio() {
    log_step "Starting PulseAudio server on Termux…"

    # Kill any existing instance to avoid port conflicts
    pulseaudio --check 2>/dev/null && {
        log_info "Stopping existing PulseAudio instance…"
        pulseaudio --kill 2>/dev/null
        sleep 1
    }

    pulseaudio --start \
        --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" \
        --exit-idle-time=-1 2>/dev/null

    if pulseaudio --check 2>/dev/null; then
        log_success "PulseAudio server started (TCP on 127.0.0.1:${_PA_PORT})."
    else
        log_error "PulseAudio failed to start.  Check 'pulseaudio -v' for details."
        return 1
    fi
}

# -----------------------------------------------------------------------------
# stop_audio
#   Gracefully stops the PulseAudio server.
# -----------------------------------------------------------------------------
stop_audio() {
    log_info "Stopping PulseAudio server…"

    if pulseaudio --check 2>/dev/null; then
        pulseaudio --kill 2>/dev/null
        log_success "PulseAudio stopped."
    else
        log_info "PulseAudio was not running."
    fi
}

# -----------------------------------------------------------------------------
# test_audio
#   Verifies the audio bridge by querying PulseAudio server info from inside
#   the proot guest.
# -----------------------------------------------------------------------------
test_audio() {
    log_step "Testing audio bridge…"

    # Make sure the server is actually running first
    if ! pulseaudio --check 2>/dev/null; then
        log_warn "PulseAudio server is not running on Termux.  Starting it now…"
        start_audio || return 1
    fi

    log_info "Querying PulseAudio from inside proot…"
    local pa_info
    pa_info="$(run_proot_cmd_user "PULSE_SERVER=tcp:127.0.0.1:${_PA_PORT} pactl info 2>&1")" || true

    if echo "${pa_info}" | grep -qi "server name"; then
        local server_name
        server_name="$(echo "${pa_info}" | grep -i "Server Name" | head -1)"
        local default_sink
        default_sink="$(echo "${pa_info}" | grep -i "Default Sink" | head -1)"
        log_success "Audio bridge is working!"
        log_info "  ${server_name}"
        log_info "  ${default_sink}"
    else
        log_error "Audio bridge test failed."
        log_error "pactl output: ${pa_info}"
        log_error "Troubleshooting:"
        log_error "  1. Ensure PulseAudio is running:  pulseaudio --start"
        log_error "  2. Check that port ${_PA_PORT} is not blocked"
        log_error "  3. Verify client.conf inside proot points to tcp:127.0.0.1:${_PA_PORT}"
        return 1
    fi
}
