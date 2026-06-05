#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# Andrux — prereqs.sh
# Prerequisite package installation and environment verification.
#
# Provides:
#   • Termux package installation (proot-distro, termux-x11, pulseaudio, etc.)
#   • Android companion app checks (Termux:X11, Termux:API)
#   • Termux properties configuration
#   • Aggregate prerequisite checks
#
# This file is sourced by the main `andrux` script and depends on common.sh
# being loaded first.
# ==============================================================================

# Guard against double-sourcing
[[ -n "$_ANDRUX_PREREQS_LOADED" ]] && return 0
_ANDRUX_PREREQS_LOADED=1

# ==============================================================================
# Package Lists
# ==============================================================================
# All Termux packages required for Andrux to function.  Grouped logically.
readonly _ANDRUX_TERMUX_PACKAGES=(
    # --- Core proot infrastructure ---
    proot-distro

    # --- Display server ---
    termux-x11-nightly

    # --- Audio ---
    pulseaudio

    # --- GPU acceleration ---
    virglrenderer-android
    angle-android
    vulkan-loader-android

    # --- Termux integration ---
    termux-api

    # --- TUI / utilities ---
    dialog
    wget
    curl
    git
)

# ==============================================================================
# Package Installation
# ==============================================================================

# install_termux_packages
# Installs every package in _ANDRUX_TERMUX_PACKAGES via `pkg`.
# Packages that are already installed are skipped by pkg automatically, so
# this is safe to re-run.
install_termux_packages() {
    log_step "Updating Termux package repositories..."
    if ! pkg update -y 2>&1; then
        log_error "Failed to update package repositories."
        log_error "Check your internet connection and try again."
        return 1
    fi

    log_step "Installing required Termux packages..."

    local failed_packages=()
    local pkg_name

    for pkg_name in "${_ANDRUX_TERMUX_PACKAGES[@]}"; do
        if check_package "$pkg_name"; then
            log_info "Already installed: $pkg_name"
            continue
        fi

        log_step "Installing $pkg_name..."
        if ! pkg install -y "$pkg_name" 2>&1; then
            log_warn "Failed to install: $pkg_name"
            failed_packages+=("$pkg_name")
        else
            log_success "Installed: $pkg_name"
        fi
    done

    # Report results.
    if [[ ${#failed_packages[@]} -gt 0 ]]; then
        log_error "The following packages failed to install:"
        for pkg_name in "${failed_packages[@]}"; do
            log_error "  • $pkg_name"
        done
        log_warn "Some packages may not be available in your Termux repository."
        log_warn "Try updating your repos:  pkg update && pkg upgrade"
        return 1
    fi

    log_success "All required Termux packages are installed."
    return 0
}

# ==============================================================================
# Companion App Checks
# ==============================================================================
# Several features require standalone Android apps to be installed alongside
# the Termux terminal app.

# check_termux_x11_app
# Returns 0 if the Termux:X11 companion app is installed on the device.
check_termux_x11_app() {
    if pm list packages 2>/dev/null | grep -q 'com.termux.x11'; then
        log_success "Termux:X11 app is installed"
        return 0
    fi

    log_error "Termux:X11 app is NOT installed."
    log_error "Please install it from: https://github.com/nicenyancat/termux-x11-nightly/releases"
    return 1
}

# check_termux_api_app
# Returns 0 if the Termux:API companion app is installed on the device.
check_termux_api_app() {
    if pm list packages 2>/dev/null | grep -q 'com.termux.api'; then
        log_success "Termux:API app is installed"
        return 0
    fi

    log_warn "Termux:API app is not installed."
    log_warn "Some features (clipboard, notifications) will be unavailable."
    log_warn "Install from: https://f-droid.org/packages/com.termux.api/"
    return 1
}

# ==============================================================================
# Termux Properties
# ==============================================================================

# setup_termux_properties
# Ensures termux.properties has the settings Andrux needs.
# Currently:
#   • allow-external-apps = true   (required for Termux:X11 integration)
setup_termux_properties() {
    local props_dir="$HOME/.termux"
    local props_file="${props_dir}/termux.properties"

    mkdir -p "$props_dir" || {
        log_error "Failed to create $props_dir"
        return 1
    }

    # If the file already has the setting, leave it alone.
    if [[ -f "$props_file" ]] && grep -q '^allow-external-apps[[:space:]]*=[[:space:]]*true' "$props_file"; then
        log_info "termux.properties: allow-external-apps already enabled"
        return 0
    fi

    # Append or update the property.
    if [[ -f "$props_file" ]] && grep -q '^allow-external-apps' "$props_file"; then
        # Property exists but is set to something other than true — update it.
        sed -i 's/^allow-external-apps.*/allow-external-apps = true/' "$props_file"
        log_info "termux.properties: updated allow-external-apps to true"
    else
        # Property doesn't exist — append it.
        {
            echo ""
            echo "# Added by Andrux — required for Termux:X11 integration"
            echo "allow-external-apps = true"
        } >> "$props_file"
        log_info "termux.properties: added allow-external-apps = true"
    fi

    # Notify Termux to reload properties.
    if check_command termux-reload-settings; then
        termux-reload-settings 2>/dev/null || true
        log_info "Termux settings reloaded"
    else
        log_warn "Run 'termux-reload-settings' or restart Termux for changes to take effect."
    fi
}

# ==============================================================================
# Aggregate Checks
# ==============================================================================

# check_all_prereqs
# Runs every prerequisite check and returns 0 only if ALL pass.
# Individual failures are logged but do not short-circuit — the user gets a
# full picture of what's missing.
check_all_prereqs() {
    local all_ok=0

    log_step "Checking prerequisites..."
    printf "\n" >&2

    # --- 1. Termux packages ---
    local pkg_name
    for pkg_name in "${_ANDRUX_TERMUX_PACKAGES[@]}"; do
        if check_package "$pkg_name"; then
            log_success "Package: $pkg_name"
        else
            log_error "Missing package: $pkg_name"
            all_ok=1
        fi
    done

    printf "\n" >&2

    # --- 2. Android companion apps ---
    check_termux_x11_app  || all_ok=1
    # API app is optional; warn but don't fail.
    check_termux_api_app  || true

    printf "\n" >&2

    # --- 3. Termux properties ---
    local props_file="$HOME/.termux/termux.properties"
    if [[ -f "$props_file" ]] && grep -q '^allow-external-apps[[:space:]]*=[[:space:]]*true' "$props_file"; then
        log_success "termux.properties: allow-external-apps = true"
    else
        log_error "termux.properties: allow-external-apps not set"
        all_ok=1
    fi

    printf "\n" >&2

    if [[ $all_ok -eq 0 ]]; then
        log_success "All prerequisites satisfied!"
    else
        log_error "Some prerequisites are missing.  Run 'andrux install-prereqs' to fix."
    fi

    return $all_ok
}

# install_all_prereqs
# One-shot function that installs/configures everything Andrux needs.
install_all_prereqs() {
    log_step "Installing all Andrux prerequisites..."
    printf "\n" >&2

    install_termux_packages || {
        log_error "Package installation encountered errors (see above)."
        # Don't bail — continue with the other steps.
    }

    printf "\n" >&2
    setup_termux_properties

    printf "\n" >&2
    log_step "Checking companion Android apps..."
    check_termux_x11_app || true
    check_termux_api_app || true

    printf "\n" >&2
    log_success "Prerequisite installation complete."
    log_info "Run 'andrux check-prereqs' to verify everything is in order."
}
