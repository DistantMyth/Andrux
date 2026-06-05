#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# Andrux - GNOME Desktop Startup Configuration
# =============================================================================
# This script is executed inside the proot distro to start GNOME

# Disable screensaver
xset s off 2>/dev/null
xset -dpms 2>/dev/null
xset s noblank 2>/dev/null

# GNOME-specific: use Xorg session type
export XDG_SESSION_TYPE=x11
export GDK_BACKEND=x11

# Start GNOME with dbus-run-session (critical for proot where dbus-daemon
# isn't running as a system service)
exec dbus-run-session -- gnome-session
