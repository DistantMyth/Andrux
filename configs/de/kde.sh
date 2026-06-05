#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# Andrux - KDE Plasma Desktop Startup Configuration
# =============================================================================
# This script is executed inside the proot distro to start KDE Plasma

# Fix dbus
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval "$(dbus-launch --sh-syntax)"
    export DBUS_SESSION_BUS_ADDRESS
fi

# Disable screensaver
xset s off 2>/dev/null
xset -dpms 2>/dev/null
xset s noblank 2>/dev/null

# KDE-specific: disable compositing (not useful in proot and hurts performance)
export KWIN_COMPOSE=N
export QT_QPA_PLATFORMTHEME=kde

# Start KDE Plasma
exec startplasma-x11
