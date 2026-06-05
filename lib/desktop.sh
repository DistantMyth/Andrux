#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# Andrux — desktop.sh
# Desktop environment installation and configuration inside proot-distro.
#
# Provides:
#   install_desktop_environment  — install the selected DE (XFCE/KDE/GNOME)
#   configure_desktop            — post-install tweaks (screensaver, dbus, etc.)
#   get_de_start_command         — return the shell command that launches the DE
#
# Depends on (sourced before this file):
#   common.sh  → log_*, run_proot_cmd, run_proot_cmd_user,
#                get_proot_pkg_manager, get_proot_install_cmd,
#                get_proot_update_cmd, DISTRO_NAME, DESKTOP_ENV,
#                USERNAME, ANDRUX_DIR
# =============================================================================

# -----------------------------------------------------------------------------
# install_desktop_environment
#   Installs the desktop environment selected by $DESKTOP_ENV inside the
#   proot distro identified by $DISTRO_ALIAS.
# -----------------------------------------------------------------------------
install_desktop_environment() {
    local pkg_mgr
    pkg_mgr="$(get_proot_pkg_manager)"

    log_step "Installing ${DESKTOP_ENV^^} desktop on ${DISTRO_NAME}…"

    # ---- Refresh package index first ----
    log_info "Updating package index inside proot…"
    run_proot_cmd "$(get_proot_update_cmd)" || {
        log_warn "Package index update had warnings — continuing anyway."
    }

    # ---- Determine package list ----
    local packages=""

    case "${DESKTOP_ENV}" in
        xfce)
            case "${pkg_mgr}" in
                apt)
                    packages="xfce4 xfce4-goodies xfce4-terminal dbus-x11 at-spi2-core librsvg2-common"
                    ;;
                pacman)
                    packages="xfce4 xfce4-goodies dbus xfce4-terminal at-spi2-core librsvg"
                    ;;
                dnf)
                    packages="@xfce-desktop-environment dbus-x11 at-spi2-core librsvg2"
                    ;;
                *)
                    log_error "Unsupported package manager '${pkg_mgr}' for XFCE."
                    return 1
                    ;;
            esac
            ;;
        kde)
            case "${pkg_mgr}" in
                apt)
                    packages="kde-plasma-desktop plasma-nm plasma-pa konsole dolphin dbus-x11 at-spi2-core"
                    ;;
                pacman)
                    packages="plasma-desktop plasma-nm plasma-pa konsole dolphin dbus at-spi2-core"
                    ;;
                dnf)
                    packages="@kde-desktop-environment dbus-x11 at-spi2-core"
                    ;;
                *)
                    log_error "Unsupported package manager '${pkg_mgr}' for KDE."
                    return 1
                    ;;
            esac
            ;;
        gnome)
            case "${pkg_mgr}" in
                apt)
                    packages="gnome-session gnome-shell gnome-terminal nautilus gnome-text-editor dbus-x11 at-spi2-core adwaita-icon-theme"
                    ;;
                pacman)
                    packages="gnome-session gnome-shell gnome-terminal nautilus gnome-text-editor dbus at-spi2-core adwaita-icon-theme"
                    ;;
                dnf)
                    packages="@gnome-desktop gnome-terminal dbus-x11 at-spi2-core"
                    ;;
                *)
                    log_error "Unsupported package manager '${pkg_mgr}' for GNOME."
                    return 1
                    ;;
            esac
            ;;
        *)
            log_error "Unknown desktop environment: '${DESKTOP_ENV}'."
            log_error "Supported values: xfce, kde, gnome."
            return 1
            ;;
    esac

    # ---- Install packages ----
    log_info "Installing packages: ${packages}"
    local install_cmd
    install_cmd="$(get_proot_install_cmd) ${packages}"

    run_proot_cmd "${install_cmd}" || {
        log_error "Desktop environment installation failed."
        log_error "Try running 'andrux install-desktop' again after checking your network."
        return 1
    }

    log_success "${DESKTOP_ENV^^} desktop environment installed successfully."

    # ---- Run post-install configuration ----
    configure_desktop
}

# -----------------------------------------------------------------------------
# configure_desktop
#   Post-install configuration:
#     1. Disable screensaver / lock screen  (critical for proot — no PAM)
#     2. Set the default terminal emulator
#     3. Fix dbus session bus setup
#     4. Create ~/.xinitrc / ~/.xsession for $USERNAME
# -----------------------------------------------------------------------------
configure_desktop() {
    log_step "Configuring ${DESKTOP_ENV^^} post-install settings…"

    local user_home="/home/${USERNAME}"

    # ------------------------------------------------------------------
    # 1. Disable screensaver and lock screen
    #    In a proot environment there is no real session manager and PAM
    #    authentication will fail, so the lock screen must be disabled.
    # ------------------------------------------------------------------
    log_info "Disabling screensaver / lock screen…"

    case "${DESKTOP_ENV}" in
        xfce)
            # xfce4-screensaver / xscreensaver — disable via xfconf
            run_proot_cmd_user "mkdir -p ${user_home}/.config/xfce4/xfconf/xfce-perchannel-xml" 2>/dev/null
            run_proot_cmd_user "cat > ${user_home}/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-screensaver.xml << 'XEOF'
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<channel name=\"xfce4-screensaver\" version=\"1.0\">
  <property name=\"saver\" type=\"empty\">
    <property name=\"enabled\" type=\"bool\" value=\"false\"/>
  </property>
  <property name=\"lock\" type=\"empty\">
    <property name=\"enabled\" type=\"bool\" value=\"false\"/>
  </property>
</channel>
XEOF"
            # Also disable xfce4-power-manager screen blanking
            run_proot_cmd_user "cat > ${user_home}/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-power-manager.xml << 'XEOF'
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<channel name=\"xfce4-power-manager\" version=\"1.0\">
  <property name=\"xfce4-power-manager\" type=\"empty\">
    <property name=\"dpms-enabled\" type=\"bool\" value=\"false\"/>
    <property name=\"blank-on-ac\" type=\"int\" value=\"0\"/>
    <property name=\"blank-on-battery\" type=\"int\" value=\"0\"/>
  </property>
</channel>
XEOF"
            ;;
        kde)
            # KDE: disable screen locker via kscreenlockerrc
            run_proot_cmd_user "mkdir -p ${user_home}/.config" 2>/dev/null
            run_proot_cmd_user "cat > ${user_home}/.config/kscreenlockerrc << 'KEOF'
[Daemon]
Autolock=false
LockOnResume=false
KEOF"
            ;;
        gnome)
            # GNOME: disable via gsettings (requires dbus session)
            run_proot_cmd_user "dbus-run-session -- gsettings set org.gnome.desktop.screensaver lock-enabled false" 2>/dev/null
            run_proot_cmd_user "dbus-run-session -- gsettings set org.gnome.desktop.screensaver idle-activation-enabled false" 2>/dev/null
            run_proot_cmd_user "dbus-run-session -- gsettings set org.gnome.desktop.session idle-delay 0" 2>/dev/null
            ;;
    esac

    # ------------------------------------------------------------------
    # 2. Set default terminal emulator
    # ------------------------------------------------------------------
    log_info "Setting default terminal emulator…"

    case "${DESKTOP_ENV}" in
        xfce)
            # xfce4-terminal is installed with xfce4-goodies
            run_proot_cmd_user "mkdir -p ${user_home}/.config/xfce4" 2>/dev/null
            run_proot_cmd_user "cat >> ${user_home}/.config/xfce4/helpers.rc << 'TEOF'
TerminalEmulator=xfce4-terminal
TEOF"
            ;;
        kde)
            # Konsole is the KDE default — no extra config needed
            log_info "Konsole is already the KDE default terminal."
            ;;
        gnome)
            # gnome-terminal ships with GNOME — nothing to do
            log_info "GNOME Terminal is already the default."
            ;;
    esac

    # ------------------------------------------------------------------
    # 3. Fix dbus session bus
    #    proot does not run a real init, so dbus-daemon must be launched
    #    manually.  We create a wrapper that ensures DBUS_SESSION_BUS_ADDRESS
    #    is set before starting the DE.
    # ------------------------------------------------------------------
    log_info "Configuring dbus session bus…"

    # Create a machine-id if missing (some distros skip this in proot)
    run_proot_cmd "if [ ! -f /etc/machine-id ] || [ ! -s /etc/machine-id ]; then \
        dbus-uuidgen > /etc/machine-id 2>/dev/null || \
        cat /proc/sys/kernel/random/uuid | tr -d '-' > /etc/machine-id; \
    fi"

    # Ensure /run/dbus exists for the system bus socket
    run_proot_cmd "mkdir -p /run/dbus" 2>/dev/null

    # ------------------------------------------------------------------
    # 4. Create .xinitrc / .xsession for the user
    #    These are read by startx / display managers to launch the DE.
    # ------------------------------------------------------------------
    log_info "Creating session startup scripts for user '${USERNAME}'…"

    local start_cmd
    start_cmd="$(get_de_start_command)"

    run_proot_cmd_user "cat > ${user_home}/.xinitrc << SEOF
#!/bin/sh
# Andrux — auto-generated .xinitrc
# Starts the ${DESKTOP_ENV^^} desktop environment.

# Export dbus session if not already set
if [ -z \"\\\$DBUS_SESSION_BUS_ADDRESS\" ]; then
    eval \\\$(dbus-launch --sh-syntax)
    export DBUS_SESSION_BUS_ADDRESS
fi

# Disable accessibility bus errors (common in proot)
export NO_AT_BRIDGE=1

exec ${start_cmd}
SEOF"

    run_proot_cmd_user "chmod +x ${user_home}/.xinitrc"

    # .xsession is a symlink to .xinitrc for display-manager compat
    run_proot_cmd_user "ln -sf ${user_home}/.xinitrc ${user_home}/.xsession"

    log_success "Desktop configuration complete."
}

# -----------------------------------------------------------------------------
# get_de_start_command
#   Echoes the shell command used to launch the selected desktop environment.
#   GNOME requires dbus-run-session because it refuses to start without a
#   proper session bus, and proot cannot provide one via systemd/logind.
# -----------------------------------------------------------------------------
get_de_start_command() {
    case "${DESKTOP_ENV}" in
        xfce)
            echo "startxfce4"
            ;;
        kde)
            echo "startplasma-x11"
            ;;
        gnome)
            # GNOME on proot MUST use dbus-run-session; without it the
            # shell crashes immediately because it expects logind.
            echo "dbus-run-session -- gnome-session"
            ;;
        *)
            log_error "get_de_start_command: unknown DE '${DESKTOP_ENV}'"
            echo ""
            return 1
            ;;
    esac
}
