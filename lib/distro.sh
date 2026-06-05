#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# Andrux — distro.sh
# Distribution installation, base system setup, and user creation.
#
# Provides:
#   • Distro alias/name mapping tables
#   • proot-distro install / remove / list wrappers
#   • Base system bootstrapping (packages, locale, timezone)
#   • Non-root user creation with password and sudo
#
# This file is sourced by the main `andrux` script and depends on common.sh
# being loaded first.
# ==============================================================================

# Guard against double-sourcing
[[ -n "${_ANDRUX_DISTRO_LOADED:-}" ]] && return 0
_ANDRUX_DISTRO_LOADED=1

# ==============================================================================
# Distro Maps
# ==============================================================================
# proot-distro v5.1.4+ uses Docker Hub image references for installation
# and container names for login/remove.
#
# Install:  proot-distro install <IMAGE_REF>
# Login:    proot-distro login <CONTAINER_NAME> [--user USER] -- CMD
# Remove:   proot-distro remove <CONTAINER_NAME>

# Docker image reference used for `proot-distro install`
declare -A DISTRO_IMAGE=(
    [debian]="debian:stable"
    [ubuntu]="ubuntu:24.04"
    [arch]="danhunsaker/archlinuxarm:latest"
    [fedora]="fedora:latest"
)

# Container name that proot-distro assigns after install
# (derived from the image name, without tag/registry prefix)
declare -A DISTRO_CONTAINER=(
    [debian]="debian"
    [ubuntu]="ubuntu"
    [arch]="archlinuxarm"
    [fedora]="fedora"
)

declare -A DISTRO_NAMES=(
    [debian]="Debian"
    [ubuntu]="Ubuntu"
    [arch]="Arch Linux ARM"
    [fedora]="Fedora"
)

# ==============================================================================
# Distro Installation
# ==============================================================================

# check_distro_installed CONTAINER_NAME
# Returns 0 if a proot container with the given name exists.
check_distro_installed() {
    local container="$1"
    if [[ -z "$container" ]]; then
        log_error "check_distro_installed: no container name provided"
        return 1
    fi

    # proot-distro list shows container names, one per section.
    # We check if the container directory exists directly.
    local pd_dir="/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs"
    if [[ -d "${pd_dir}/${container}" ]]; then
        return 0
    fi

    # Fallback: parse `proot-distro list` output
    if proot-distro list 2>/dev/null | grep -q "^${container}\b"; then
        return 0
    fi

    return 1
}

# install_distro DISTRO_KEY
# Installs a distribution via proot-distro using Docker image references.
# DISTRO_KEY is one of: debian, ubuntu, arch, fedora.
install_distro() {
    local key="$1"

    if [[ -z "$key" ]]; then
        log_error "install_distro: no distro key provided"
        log_error "Valid keys: ${!DISTRO_IMAGE[*]}"
        return 1
    fi

    local image="${DISTRO_IMAGE[$key]:-}"
    local container="${DISTRO_CONTAINER[$key]:-}"
    local name="${DISTRO_NAMES[$key]:-}"

    if [[ -z "$image" ]]; then
        log_error "install_distro: unknown distro key '$key'"
        log_error "Valid keys: ${!DISTRO_IMAGE[*]}"
        return 1
    fi

    # Check if already installed.
    if check_distro_installed "$container"; then
        log_info "$name ($container) is already installed."
        DISTRO_ALIAS="$container"
        DISTRO_NAME="$name"
        return 0
    fi

    log_step "Installing $name via proot-distro (image: $image)..."
    if ! proot-distro install "$image"; then
        log_error "Failed to install $name."
        log_error "Check your internet connection and available storage."
        return 1
    fi

    DISTRO_ALIAS="$container"
    DISTRO_NAME="$name"
    log_success "$name installed successfully."
}

# remove_distro CONTAINER_NAME
# Removes an installed proot container.
remove_distro() {
    local container="$1"

    if [[ -z "$container" ]]; then
        log_error "remove_distro: no container name provided"
        return 1
    fi

    if ! check_distro_installed "$container"; then
        log_warn "Container '$container' is not installed — nothing to remove."
        return 0
    fi

    log_step "Removing container '$container'..."

    if ! proot-distro remove "$container"; then
        log_error "Failed to remove container '$container'."
        return 1
    fi

    # Clear global state if the removed distro was the active one.
    if [[ "$DISTRO_ALIAS" == "$container" ]]; then
        DISTRO_ALIAS=""
        DISTRO_NAME=""
    fi

    log_success "Container '$container' removed."
}

# list_installed_distros
# Prints a list of currently installed proot containers.
list_installed_distros() {
    log_step "Installed proot containers:"
    printf "\n" >&2

    proot-distro list 2>/dev/null >&2 || log_info "No containers are currently installed."

    printf "\n" >&2
}

# ==============================================================================
# Base System Setup
# ==============================================================================
# These functions run *inside* the proot environment (via run_proot_cmd).

# setup_base_system
# Updates the package manager and installs essential packages, then configures
# locale and timezone.
setup_base_system() {
    if [[ -z "$DISTRO_ALIAS" ]]; then
        log_error "setup_base_system: no distro installed (DISTRO_ALIAS is empty)"
        return 1
    fi

    local pm
    pm="$(get_proot_pkg_manager)" || return 1

    # --- Step 1: Update package manager ---
    log_step "Updating package manager inside $DISTRO_ALIAS..."
    local update_cmd
    update_cmd="$(get_proot_update_cmd)" || return 1

    if ! run_proot_cmd "$update_cmd"; then
        log_error "Package manager update failed inside the proot environment."
        return 1
    fi
    log_success "Package manager updated."

    # --- Step 2: Install base packages ---
    log_step "Installing base packages..."
    local install_cmd
    install_cmd="$(get_proot_install_cmd)" || return 1

    local base_packages=""

    case "$pm" in
        apt)
            base_packages="sudo wget curl nano vim git locales dbus dbus-x11"
            ;;
        pacman)
            base_packages="sudo wget curl nano vim git glibc dbus"
            ;;
        dnf)
            base_packages="sudo wget curl nano vim git glibc-langpack-en dbus dbus-x11"
            ;;
    esac

    if ! run_proot_cmd "$install_cmd $base_packages"; then
        log_error "Failed to install some base packages."
        log_warn "Continuing anyway — some packages may not be available."
    else
        log_success "Base packages installed."
    fi

    # --- Step 3: Configure locale ---
    log_step "Configuring locale (en_US.UTF-8)..."
    _setup_locale "$pm"

    # --- Step 4: Set timezone ---
    log_step "Setting timezone..."
    _setup_timezone

    log_success "Base system setup complete."
}

# _setup_locale PM
# Internal: generates and sets the en_US.UTF-8 locale.
_setup_locale() {
    local pm="$1"

    case "$pm" in
        apt)
            # Debian/Ubuntu: uncomment locale in /etc/locale.gen, then generate.
            run_proot_cmd "
                sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen 2>/dev/null || true
                locale-gen en_US.UTF-8 2>/dev/null || true
                update-locale LANG=en_US.UTF-8 2>/dev/null || true
                echo 'LANG=en_US.UTF-8' > /etc/default/locale 2>/dev/null || true
            " || log_warn "Locale generation may have partially failed"
            ;;
        pacman)
            # Arch: same pattern.
            run_proot_cmd "
                sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen 2>/dev/null || true
                locale-gen 2>/dev/null || true
                echo 'LANG=en_US.UTF-8' > /etc/locale.conf 2>/dev/null || true
            " || log_warn "Locale generation may have partially failed"
            ;;
        dnf)
            # Fedora: glibc-langpack-en provides the locale; just set it.
            run_proot_cmd "
                echo 'LANG=en_US.UTF-8' > /etc/locale.conf 2>/dev/null || true
                localectl set-locale LANG=en_US.UTF-8 2>/dev/null || true
            " || log_warn "Locale configuration may have partially failed"
            ;;
    esac
}

# _setup_timezone
# Internal: sets the proot timezone to match the Android host.
_setup_timezone() {
    # Try to read the timezone from Android properties.
    local tz
    tz="$(getprop persist.sys.timezone 2>/dev/null || true)"

    if [[ -z "$tz" ]]; then
        tz="UTC"
        log_warn "Could not detect Android timezone; defaulting to UTC."
    fi

    run_proot_cmd "
        ln -sf /usr/share/zoneinfo/${tz} /etc/localtime 2>/dev/null || true
        echo '${tz}' > /etc/timezone 2>/dev/null || true
    " || log_warn "Timezone setup may have partially failed"

    log_info "Timezone set to: $tz"
}

# ==============================================================================
# User Creation
# ==============================================================================

# create_user USERNAME [PASSWORD]
# Creates a regular (non-root) user inside the proot environment with:
#   • Home directory
#   • bash shell
#   • Passwordless sudo
#   • Membership in audio, video, and other useful groups
# If PASSWORD is provided, it will be used directly. Otherwise the user
# is prompted interactively.
create_user() {
    local username="$1"
    local password="${2:-}"

    if [[ -z "$username" ]]; then
        log_error "create_user: no username provided"
        return 1
    fi

    # Basic username validation (POSIX portable filename chars, starts with letter).
    if [[ ! "$username" =~ ^[a-z][a-z0-9_-]{0,30}$ ]]; then
        log_error "create_user: invalid username '$username'"
        log_error "Username must start with a lowercase letter and contain only"
        log_error "lowercase letters, digits, hyphens, or underscores (max 31 chars)."
        return 1
    fi

    if [[ -z "$DISTRO_ALIAS" ]]; then
        log_error "create_user: no distro installed (DISTRO_ALIAS is empty)"
        return 1
    fi

    # Check if user already exists.
    if run_proot_cmd "id '$username'" &>/dev/null; then
        log_info "User '$username' already exists."
        USERNAME="$username"
        return 0
    fi

    log_step "Creating user '$username'..."

    # --- Step 1: Create user with home dir and bash shell ---
    if ! run_proot_cmd "useradd -m -s /bin/bash '$username'"; then
        log_error "Failed to create user '$username'."
        return 1
    fi

    # --- Step 2: Add to groups ---
    # We try several common groups; not all will exist on every distro, so
    # failures are silently ignored.
    run_proot_cmd "
        for g in audio video sudo wheel input render; do
            usermod -aG \"\$g\" '$username' 2>/dev/null || true
        done
    "
    log_info "User added to available groups (audio, video, sudo, wheel, ...)"

    # --- Step 3: Configure passwordless sudo ---
    run_proot_cmd "
        mkdir -p /etc/sudoers.d
        echo '$username ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/$username
        chmod 0440 /etc/sudoers.d/$username
    "
    log_info "Passwordless sudo configured for '$username'"

    # --- Step 4: Set password ---
    # If no password was provided as argument, prompt interactively.
    if [[ -z "$password" ]]; then
        log_step "Set a password for '$username'."

        local password_confirm
        while true; do
            printf "${YELLOW}[?]${RESET} Enter password: " >&2
            read -rs password
            printf "\n" >&2

            if [[ -z "$password" ]]; then
                log_warn "Password cannot be empty. Try again."
                continue
            fi

            printf "${YELLOW}[?]${RESET} Confirm password: " >&2
            read -rs password_confirm
            printf "\n" >&2

            if [[ "$password" != "$password_confirm" ]]; then
                log_warn "Passwords do not match. Try again."
                continue
            fi

            break
        done
    fi

    if ! run_proot_cmd "echo '${username}:${password}' | chpasswd"; then
        log_warn "Failed to set password via chpasswd."
        log_warn "You can set it later inside the distro: passwd $username"
    else
        log_success "Password set for '$username'."
    fi

    USERNAME="$username"
    log_success "User '$username' created successfully."
}
