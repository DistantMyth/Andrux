#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# Andrux - XFCE Desktop Startup Configuration
# =============================================================================
# This script is executed inside the proot distro to start XFCE desktop

# Fix dbus
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval "$(dbus-launch --sh-syntax)"
    export DBUS_SESSION_BUS_ADDRESS
fi

# Disable screensaver
xset s off 2>/dev/null
xset -dpms 2>/dev/null
xset s noblank 2>/dev/null

# Start XFCE
exec startxfce4
