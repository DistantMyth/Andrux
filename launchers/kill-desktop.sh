#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# Andrux - Desktop Kill Script
# =============================================================================
# Cleanly shuts down all Andrux desktop services.
# Usage: kill-desktop
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

log_info()    { echo -e "${CYAN}[*]${RESET} $1"; }
log_success() { echo -e "${GREEN}[✓]${RESET} $1"; }
log_warn()    { echo -e "${YELLOW}[!]${RESET} $1"; }

echo ""
echo -e "${BOLD}${RED}╔══════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${RED}║      🛑 Andrux Desktop Shutdown          ║${RESET}"
echo -e "${BOLD}${RED}╚══════════════════════════════════════════╝${RESET}"
echo ""

# Kill desktop environment processes
log_info "Stopping desktop environment..."
pkill -f "startxfce4" 2>/dev/null && log_success "XFCE stopped." || true
pkill -f "startplasma" 2>/dev/null && log_success "KDE stopped." || true
pkill -f "gnome-session" 2>/dev/null && log_success "GNOME stopped." || true
pkill -f "gnome-shell" 2>/dev/null || true
pkill -f "xfwm4" 2>/dev/null || true
pkill -f "xfce4-session" 2>/dev/null || true
pkill -f "xfce4-panel" 2>/dev/null || true
pkill -f "kwin" 2>/dev/null || true
pkill -f "plasmashell" 2>/dev/null || true

# Kill dbus sessions
log_info "Stopping dbus sessions..."
pkill -f "dbus-daemon --session" 2>/dev/null || true
pkill -f "dbus-run-session" 2>/dev/null || true

# Kill VirGL server
log_info "Stopping GPU acceleration server..."
if pkill -f "virgl_test_server" 2>/dev/null; then
    log_success "VirGL server stopped."
else
    log_info "VirGL server was not running."
fi

# Kill PulseAudio
log_info "Stopping audio server..."
if pulseaudio --kill 2>/dev/null; then
    log_success "PulseAudio stopped."
else
    log_info "PulseAudio was not running."
fi

# Kill Termux:X11 server
log_info "Stopping display server..."
if pkill -f "termux-x11" 2>/dev/null; then
    log_success "Termux:X11 server stopped."
else
    log_info "Termux:X11 server was not running."
fi

# Kill any remaining proot sessions
log_info "Stopping proot sessions..."
pkill -f "proot --" 2>/dev/null || true
pkill -f "proot-distro" 2>/dev/null || true

echo ""
log_success "All Andrux desktop services have been stopped."
echo ""
