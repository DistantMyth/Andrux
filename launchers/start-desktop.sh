#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# Andrux - Desktop Launcher
# =============================================================================
# This script starts the full Linux desktop environment.
# It is generated/configured by the Andrux installer.
#
# Usage: start-desktop [--no-gpu] [--no-audio]
# =============================================================================

set -e

# ---- Configuration (set by installer) ----
ANDRUX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDRUX_CONFIG="$HOME/.andrux"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

log_info()    { echo -e "${BLUE}[*]${RESET} $1"; }
log_success() { echo -e "${GREEN}[✓]${RESET} $1"; }
log_warn()    { echo -e "${YELLOW}[!]${RESET} $1"; }
log_error()   { echo -e "${RED}[✗]${RESET} $1"; }

# ---- Load Configuration ----
if [ ! -f "$ANDRUX_CONFIG/config" ]; then
    log_error "Andrux is not configured. Run 'andrux' first to install."
    exit 1
fi

source "$ANDRUX_CONFIG/config"

# Validate config
if [ -z "$DISTRO_ALIAS" ] || [ -z "$DESKTOP_ENV" ] || [ -z "$USERNAME" ]; then
    log_error "Invalid configuration. Please reinstall with 'andrux'."
    exit 1
fi

# ---- Parse Arguments ----
USE_GPU=true
USE_AUDIO=true

for arg in "$@"; do
    case "$arg" in
        --no-gpu)   USE_GPU=false ;;
        --no-audio) USE_AUDIO=false ;;
        --help|-h)
            echo "Usage: start-desktop [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --no-gpu     Disable GPU acceleration (use software rendering)"
            echo "  --no-audio   Disable audio support"
            echo "  --help       Show this help message"
            exit 0
            ;;
    esac
done

# ---- Cleanup Function ----
cleanup() {
    log_info "Shutting down desktop environment..."

    # Kill VirGL server
    pkill -f virgl_test_server 2>/dev/null || true

    # Kill PulseAudio
    pulseaudio --kill 2>/dev/null || true

    # Kill Termux:X11 server
    pkill -f "termux-x11" 2>/dev/null || true

    log_success "Desktop environment stopped."
}

# ---- Check if already running ----
if pgrep -f "termux-x11.*:0" > /dev/null 2>&1; then
    log_warn "A desktop session appears to be already running."
    echo -n "Kill existing session and start fresh? [y/N] "
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        cleanup
        sleep 2
    else
        log_info "Exiting."
        exit 0
    fi
fi

# ---- Start Services ----
echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║        🐧 Andrux Desktop Launcher       ║${RESET}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  Distro:  ${BOLD}${DISTRO_NAME:-$DISTRO_ALIAS}${RESET}"
echo -e "  Desktop: ${BOLD}${DESKTOP_ENV^^}${RESET}"
echo -e "  User:    ${BOLD}${USERNAME}${RESET}"
echo -e "  GPU:     ${BOLD}${GPU_METHOD:-software}${RESET}"
echo ""

# Trap for cleanup on exit
trap cleanup EXIT

# Step 1: Start PulseAudio
if [ "$USE_AUDIO" = true ]; then
    log_info "Starting PulseAudio audio server..."
    pulseaudio --kill 2>/dev/null || true
    sleep 0.5

    pulseaudio --start \
        --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" \
        --exit-idle-time=-1 2>/dev/null

    if pulseaudio --check 2>/dev/null; then
        log_success "PulseAudio server started."
    else
        log_warn "PulseAudio failed to start. Audio may not work."
    fi
else
    log_info "Audio disabled (--no-audio)."
fi

# Step 2: Start VirGL GPU server
if [ "$USE_GPU" = true ] && [ -n "$GPU_METHOD" ] && [ "$GPU_METHOD" != "llvmpipe" ]; then
    log_info "Starting GPU acceleration server (${GPU_METHOD})..."
    pkill -f virgl_test_server 2>/dev/null || true
    sleep 0.5

    case "$GPU_METHOD" in
        angle-vulkan)
            virgl_test_server_android --angle-vulkan &
            ;;
        turnip-zink)
            MESA_VK_WSI_PRESENT_MODE=fifo virgl_test_server_android &
            ;;
        virgl)
            virgl_test_server_android &
            ;;
    esac

    VIRGL_PID=$!
    sleep 1

    if kill -0 "$VIRGL_PID" 2>/dev/null; then
        log_success "VirGL server started (PID: $VIRGL_PID)."
    else
        log_warn "VirGL server failed to start. Falling back to software rendering."
        USE_GPU=false
    fi
else
    if [ "$USE_GPU" = false ]; then
        log_info "GPU acceleration disabled (--no-gpu)."
    else
        log_info "Using software rendering (${GPU_METHOD:-llvmpipe})."
    fi
fi

# Step 3: Start Termux:X11 server
log_info "Starting Termux:X11 display server..."
pkill -f "termux-x11" 2>/dev/null || true
sleep 0.5

export DISPLAY=:0
termux-x11 :0 &
X11_PID=$!
sleep 2

if kill -0 "$X11_PID" 2>/dev/null; then
    log_success "Termux:X11 server started on display :0."
else
    log_error "Termux:X11 server failed to start!"
    log_error "Make sure the Termux:X11 app is installed and the termux-x11-nightly package is installed."
    exit 1
fi

# Step 4: Open the Termux:X11 Android app
log_info "Opening Termux:X11 app..."
am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity > /dev/null 2>&1 || \
    log_warn "Could not auto-launch Termux:X11 app. Please open it manually."

sleep 1

# Step 5: Build proot environment variables
PROOT_ENV_VARS="DISPLAY=:0"

# Audio env
if [ "$USE_AUDIO" = true ]; then
    PROOT_ENV_VARS="$PROOT_ENV_VARS PULSE_SERVER=tcp:127.0.0.1:4713"
fi

# GPU env
if [ "$USE_GPU" = true ] && [ -n "$GPU_METHOD" ]; then
    case "$GPU_METHOD" in
        angle-vulkan)
            PROOT_ENV_VARS="$PROOT_ENV_VARS GALLIUM_DRIVER=virpipe"
            PROOT_ENV_VARS="$PROOT_ENV_VARS MESA_GL_VERSION_OVERRIDE=4.6COMPAT"
            PROOT_ENV_VARS="$PROOT_ENV_VARS MESA_GLES_VERSION_OVERRIDE=3.2"
            ;;
        turnip-zink)
            PROOT_ENV_VARS="$PROOT_ENV_VARS GALLIUM_DRIVER=zink"
            PROOT_ENV_VARS="$PROOT_ENV_VARS MESA_VK_WSI_PRESENT_MODE=fifo"
            ;;
        virgl)
            PROOT_ENV_VARS="$PROOT_ENV_VARS GALLIUM_DRIVER=virpipe"
            ;;
        llvmpipe|*)
            PROOT_ENV_VARS="$PROOT_ENV_VARS LIBGL_ALWAYS_SOFTWARE=1"
            PROOT_ENV_VARS="$PROOT_ENV_VARS GALLIUM_DRIVER=llvmpipe"
            ;;
    esac
fi

# Additional required env vars
PROOT_ENV_VARS="$PROOT_ENV_VARS XDG_RUNTIME_DIR=/tmp/runtime-${USERNAME}"
PROOT_ENV_VARS="$PROOT_ENV_VARS LANG=en_US.UTF-8"

# Step 6: Determine desktop start command
case "$DESKTOP_ENV" in
    xfce)  DE_CMD="startxfce4" ;;
    kde)   DE_CMD="KWIN_COMPOSE=N startplasma-x11" ;;
    gnome) DE_CMD="dbus-run-session -- gnome-session" ;;
    *)     log_error "Unknown desktop environment: $DESKTOP_ENV"; exit 1 ;;
esac

# Step 7: Launch the desktop inside proot
log_success "Launching ${DESKTOP_ENV^^} desktop environment..."
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${GREEN}  Desktop is starting! Switch to the${RESET}"
echo -e "${GREEN}  Termux:X11 app to see your desktop.${RESET}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "  Press ${BOLD}Ctrl+C${RESET} to stop the desktop session."
echo ""

# Build the full command to run inside proot
PROOT_SCRIPT="
# Create XDG runtime dir
mkdir -p /tmp/runtime-${USERNAME}
chmod 700 /tmp/runtime-${USERNAME}

# Fix for dbus inside proot
export DBUS_SESSION_BUS_ADDRESS=\$(dbus-daemon --session --fork --print-address 2>/dev/null || echo '')

# Disable screensaver and DPMS
xset s off 2>/dev/null
xset -dpms 2>/dev/null
xset s noblank 2>/dev/null

# Start the desktop environment
exec ${DE_CMD}
"

# Build proot-distro login command with all env vars
PROOT_ARGS="--shared-tmp --user ${USERNAME}"

# Add each env var
for env_var in $PROOT_ENV_VARS; do
    PROOT_ARGS="$PROOT_ARGS --bind /dev/dri:/dev/dri 2>/dev/null"
    break  # Only need bind once
done

# Run proot-distro with the desktop
# We use env to pass all variables cleanly
proot-distro login "$DISTRO_ALIAS" \
    --shared-tmp \
    --user "$USERNAME" \
    -- /bin/bash -c "
        export DISPLAY=:0
        $([ "$USE_AUDIO" = true ] && echo "export PULSE_SERVER=tcp:127.0.0.1:4713")
        $(case "$GPU_METHOD" in
            angle-vulkan)
                echo 'export GALLIUM_DRIVER=virpipe'
                echo 'export MESA_GL_VERSION_OVERRIDE=4.6COMPAT'
                echo 'export MESA_GLES_VERSION_OVERRIDE=3.2'
                ;;
            turnip-zink)
                echo 'export GALLIUM_DRIVER=zink'
                echo 'export MESA_VK_WSI_PRESENT_MODE=fifo'
                ;;
            virgl)
                echo 'export GALLIUM_DRIVER=virpipe'
                ;;
            *)
                echo 'export LIBGL_ALWAYS_SOFTWARE=1'
                echo 'export GALLIUM_DRIVER=llvmpipe'
                ;;
        esac)
        export XDG_RUNTIME_DIR=/tmp/runtime-${USERNAME}
        export LANG=en_US.UTF-8
        mkdir -p /tmp/runtime-${USERNAME}
        chmod 700 /tmp/runtime-${USERNAME}
        export DBUS_SESSION_BUS_ADDRESS=\$(dbus-daemon --session --fork --print-address 2>/dev/null || echo '')
        xset s off 2>/dev/null || true
        xset -dpms 2>/dev/null || true
        xset s noblank 2>/dev/null || true
        exec ${DE_CMD}
    "
