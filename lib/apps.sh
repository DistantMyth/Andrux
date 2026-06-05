#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# Andrux — apps.sh
# Default and optional application installation inside proot-distro.
#
# Philosophy:  install a lean but usable set of apps by default, and let the
# user opt-in to heavier packages (LibreOffice, VLC) interactively.
#
# Provides:
#   install_default_apps  — core + DE-specific apps
#   install_app           — install a single package by name
#   install_browser       — install Firefox (handles distro naming quirks)
#
# Depends on (sourced before this file):
#   common.sh → log_*, run_proot_cmd, get_proot_pkg_manager,
#               get_proot_install_cmd, DISTRO_NAME, DESKTOP_ENV
# =============================================================================

# -----------------------------------------------------------------------------
# install_default_apps
#   Installs a curated set of applications:
#     • Core utilities  (always installed)
#     • DE-specific apps (auto-selected based on DESKTOP_ENV)
#     • Browser         (Firefox, with distro-appropriate package name)
# -----------------------------------------------------------------------------
install_default_apps() {
    log_step "Installing default applications…"

    local pkg_mgr
    pkg_mgr="$(get_proot_pkg_manager)"

    # ---- Core utilities (every setup gets these) ----
    local core_packages=""
    case "${pkg_mgr}" in
        apt)    core_packages="htop neofetch wget curl" ;;
        pacman) core_packages="htop neofetch wget curl" ;;
        dnf)    core_packages="htop neofetch wget curl" ;;
    esac

    log_info "Installing core utilities: ${core_packages}"
    run_proot_cmd "$(get_proot_install_cmd) ${core_packages}" || {
        log_warn "Some core utilities may not have installed correctly."
    }

    # ---- DE-specific apps ----
    _install_de_apps "${pkg_mgr}"

    # ---- Browser ----
    install_browser

    log_success "Default applications installed."
}

# -----------------------------------------------------------------------------
# _install_de_apps   (internal)
#   Installs apps that complement the selected desktop environment.
#   Many of these ship with the DE meta-package, but we list them
#   explicitly to guarantee they are present.
# -----------------------------------------------------------------------------
_install_de_apps() {
    local pkg_mgr="$1"
    local de_packages=""

    log_info "Installing ${DESKTOP_ENV^^}-specific applications…"

    case "${DESKTOP_ENV}" in
        xfce)
            case "${pkg_mgr}" in
                apt)
                    de_packages="thunar mousepad ristretto xfce4-taskmanager"
                    ;;
                pacman)
                    de_packages="thunar mousepad ristretto xfce4-taskmanager"
                    ;;
                dnf)
                    de_packages="thunar mousepad ristretto xfce4-taskmanager"
                    ;;
            esac
            ;;
        kde)
            # Dolphin, Konsole, Kate ship with kde-plasma-desktop /
            # @kde-desktop-environment, but we ensure kate is present.
            case "${pkg_mgr}" in
                apt)
                    de_packages="kate gwenview okular"
                    ;;
                pacman)
                    de_packages="kate gwenview okular"
                    ;;
                dnf)
                    de_packages="kate gwenview okular"
                    ;;
            esac
            ;;
        gnome)
            # Nautilus and gnome-text-editor ship with the GNOME session
            # packages, but we add eog (image viewer) and file-roller.
            case "${pkg_mgr}" in
                apt)
                    de_packages="eog file-roller gnome-calculator"
                    ;;
                pacman)
                    de_packages="eog file-roller gnome-calculator"
                    ;;
                dnf)
                    de_packages="eog file-roller gnome-calculator"
                    ;;
            esac
            ;;
        *)
            log_warn "Unknown DE '${DESKTOP_ENV}' — skipping DE-specific apps."
            return 0
            ;;
    esac

    if [ -n "${de_packages}" ]; then
        log_info "Packages: ${de_packages}"
        run_proot_cmd "$(get_proot_install_cmd) ${de_packages}" || {
            log_warn "Some DE-specific apps may not have installed correctly."
        }
    fi
}

# -----------------------------------------------------------------------------
# install_browser
#   Installs Firefox with the correct package name for each distro.
#
#   Naming quirks:
#     • Debian / Ubuntu ship "firefox-esr" (Extended Support Release).
#       Regular "firefox" may exist but is a Snap stub on Ubuntu — unusable
#       in proot.  We use firefox-esr which is a real .deb.
#     • Arch ships "firefox" in the [extra] repo.
#     • Fedora ships "firefox" in the base repo.
# -----------------------------------------------------------------------------
install_browser() {
    log_info "Installing web browser (Firefox)…"

    local pkg_mgr
    pkg_mgr="$(get_proot_pkg_manager)"
    local browser_pkg=""

    case "${pkg_mgr}" in
        apt)
            browser_pkg="firefox-esr"
            ;;
        pacman)
            browser_pkg="firefox"
            ;;
        dnf)
            browser_pkg="firefox"
            ;;
        *)
            log_error "Unsupported package manager '${pkg_mgr}' for browser install."
            return 1
            ;;
    esac

    log_info "Browser package: ${browser_pkg}"
    run_proot_cmd "$(get_proot_install_cmd) ${browser_pkg}" || {
        log_error "Browser installation failed."
        log_error "You can install it manually later:"
        log_error "  proot-distro login ${DISTRO_ALIAS} -- $(get_proot_install_cmd) ${browser_pkg}"
        return 1
    }

    log_success "Firefox installed successfully."
}

# -----------------------------------------------------------------------------
# install_app
#   Installs a single application by name using the distro's package manager.
#
#   Usage:  install_app <package_name>
#
#   This is a convenience wrapper so other scripts (or the user via CLI)
#   don't need to figure out the install command themselves.
# -----------------------------------------------------------------------------
install_app() {
    local app_name="$1"

    if [ -z "${app_name}" ]; then
        log_error "install_app: no package name provided."
        log_error "Usage: install_app <package_name>"
        return 1
    fi

    log_info "Installing package '${app_name}'…"
    run_proot_cmd "$(get_proot_install_cmd) ${app_name}" || {
        log_error "Failed to install '${app_name}'."
        return 1
    }

    log_success "'${app_name}' installed."
}

# -----------------------------------------------------------------------------
# install_optional_apps
#   Interactively offers to install heavier optional packages.
#   Called at the end of the setup wizard if the user wants extras.
#
#   Current offerings:
#     • vlc   — full-featured media player
#     • mpv   — lightweight media player (alternative to VLC)
#     • libreoffice — office suite
# -----------------------------------------------------------------------------
install_optional_apps() {
    log_step "Optional applications"

    local pkg_mgr
    pkg_mgr="$(get_proot_pkg_manager)"

    # ---- Media player ----
    echo ""
    echo "  Would you like to install a media player?"
    echo "    1) VLC          — full-featured, large download"
    echo "    2) mpv          — lightweight, keyboard-driven"
    echo "    3) Skip"
    echo ""
    read -r -p "  Choice [3]: " media_choice
    media_choice="${media_choice:-3}"

    case "${media_choice}" in
        1)
            log_info "Installing VLC…"
            local vlc_pkg="vlc"
            run_proot_cmd "$(get_proot_install_cmd) ${vlc_pkg}" || {
                log_warn "VLC installation failed — you can try again later."
            }
            ;;
        2)
            log_info "Installing mpv…"
            run_proot_cmd "$(get_proot_install_cmd) mpv" || {
                log_warn "mpv installation failed — you can try again later."
            }
            ;;
        3|*)
            log_info "Skipping media player."
            ;;
    esac

    # ---- Office suite ----
    echo ""
    echo "  Would you like to install LibreOffice? (large download, ~500 MB)"
    echo "    1) Yes"
    echo "    2) No"
    echo ""
    read -r -p "  Choice [2]: " office_choice
    office_choice="${office_choice:-2}"

    case "${office_choice}" in
        1)
            log_info "Installing LibreOffice — this may take a while…"
            local lo_pkg=""
            case "${pkg_mgr}" in
                apt)    lo_pkg="libreoffice" ;;
                pacman) lo_pkg="libreoffice-fresh" ;;
                dnf)    lo_pkg="libreoffice" ;;
            esac
            run_proot_cmd "$(get_proot_install_cmd) ${lo_pkg}" || {
                log_warn "LibreOffice installation failed — you can try again later."
            }
            ;;
        2|*)
            log_info "Skipping LibreOffice."
            ;;
    esac

    log_success "Optional app selection complete."
}
