#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# Andrux — common.sh
# Shared utilities library for the Andrux desktop-on-Android installer.
#
# Provides:
#   • ANSI color constants
#   • Logging functions (info, success, warn, error, step)
#   • Progress / spinner helpers
#   • Interactive prompts
#   • System & package checks
#   • proot-distro wrappers
#   • Configuration persistence
#
# This file is sourced by the main `andrux` script — it should NEVER be
# executed directly.
# ==============================================================================

# Guard against double-sourcing
[[ -n "${_ANDRUX_COMMON_LOADED:-}" ]] && return 0
_ANDRUX_COMMON_LOADED=1

# ==============================================================================
# ANSI Color Constants
# ==============================================================================
# These are intentionally exported so that any child script or function
# inheriting this environment can use them without re-declaration.
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
BOLD='\033[1m'
RESET='\033[0m'

# ==============================================================================
# Project-wide path & state variables
# ==============================================================================

# ANDRUX_DIR — resolved absolute path to the directory containing the main
# script (the one that sourced us).  We walk BASH_SOURCE to find the lib/
# directory, then go one level up.
if [[ -z "$ANDRUX_DIR" ]]; then
    ANDRUX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

# Configuration directory lives in the user's home.
ANDRUX_CONFIG="${HOME}/.andrux"

# These are populated at runtime by detection / installation routines.
DISTRO_ALIAS=""
DISTRO_NAME=""
DESKTOP_ENV=""
USERNAME=""
GPU_TYPE=""
GPU_METHOD=""

# ==============================================================================
# Logging
# ==============================================================================
# All log functions write to stderr so that stdout remains clean for machine-
# readable output when needed.

# log_info "message" — informational, blue [*]
log_info() {
    printf "${BLUE}[*]${RESET} %s\n" "$1" >&2
}

# log_success "message" — success, green [✓]
log_success() {
    printf "${GREEN}[✓]${RESET} %s\n" "$1" >&2
}

# log_warn "message" — warning, yellow [!]
log_warn() {
    printf "${YELLOW}[!]${RESET} %s\n" "$1" >&2
}

# log_error "message" — error, red [✗]
log_error() {
    printf "${RED}[✗]${RESET} %s\n" "$1" >&2
}

# log_step "message" — progress step, cyan [→]
log_step() {
    printf "${CYAN}[→]${RESET} %s\n" "$1" >&2
}

# ==============================================================================
# Progress Helpers
# ==============================================================================

# show_spinner PID "message"
# Displays a braille-pattern spinner while the process identified by PID is
# still running.  The spinner is printed on a single line that is continuously
# overwritten.
show_spinner() {
    local pid="$1"
    local message="${2:-Working...}"
    local spin_chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0

    # Hide cursor for a cleaner look.
    tput civis 2>/dev/null || true

    while kill -0 "$pid" 2>/dev/null; do
        local char="${spin_chars:i++%${#spin_chars}:1}"
        printf "\r${CYAN}%s${RESET} %s" "$char" "$message" >&2
        sleep 0.1
    done

    # Restore cursor and clear the spinner line.
    tput cnorm 2>/dev/null || true
    printf "\r%-$((${#message} + 4))s\r" "" >&2
}

# show_progress "message"
# Prints a simple progress message with an animated ellipsis.  This is a
# *non-blocking* single-shot print — call it before starting a long operation.
show_progress() {
    local message="${1:-Processing...}"
    printf "\r${CYAN}[→]${RESET} %s..." "$message" >&2
}

# ==============================================================================
# Interactive Prompts
# ==============================================================================

# confirm "message"
# Prompts the user with a yes/no question.
# Returns 0 (true) for yes, 1 (false) for no.
confirm() {
    local message="${1:-Are you sure?}"
    local reply

    while true; do
        printf "${YELLOW}[?]${RESET} %s [y/N]: " "$message" >&2
        read -r reply
        case "${reply,,}" in          # ${,,} lowercases in bash 4+
            y|yes) return 0 ;;
            n|no|"") return 1 ;;      # default is No
            *) log_warn "Please answer y or n." ;;
        esac
    done
}

# ==============================================================================
# System / Package Checks
# ==============================================================================

# check_command "cmd"
# Returns 0 if the command is found in PATH, 1 otherwise.
check_command() {
    local cmd="$1"
    if [[ -z "$cmd" ]]; then
        log_error "check_command: no command name provided"
        return 1
    fi
    command -v "$cmd" &>/dev/null
}

# check_package "pkg"
# Returns 0 if a Termux package is currently installed.
# Uses dpkg-query which is available in Termux's apt implementation.
check_package() {
    local pkg="$1"
    if [[ -z "$pkg" ]]; then
        log_error "check_package: no package name provided"
        return 1
    fi
    dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"
}

# ensure_root_not
# Exits the script immediately if the effective UID is 0.
# Termux must NOT be run as root — proot-distro will not work correctly.
ensure_root_not() {
    if [[ "$(id -u)" -eq 0 ]]; then
        log_error "Andrux must NOT be run as root."
        log_error "Please run this from a normal Termux session (no su/sudo)."
        exit 1
    fi
}

# ==============================================================================
# proot-distro Helpers
# ==============================================================================
# These wrappers centralise every interaction with proot-distro so that flags
# like --shared-tmp are never accidentally omitted.

# run_proot_cmd "command"
# Execute a command inside the installed proot distro as root.
run_proot_cmd() {
    local cmd="$1"
    if [[ -z "$DISTRO_ALIAS" ]]; then
        log_error "run_proot_cmd: DISTRO_ALIAS is not set. Install a distro first."
        return 1
    fi
    if [[ -z "$cmd" ]]; then
        log_error "run_proot_cmd: no command provided"
        return 1
    fi
    proot-distro login "$DISTRO_ALIAS" --shared-tmp -- /bin/bash -c "$cmd"
}

# run_proot_cmd_user "command"
# Execute a command inside the proot distro as the configured non-root user.
run_proot_cmd_user() {
    local cmd="$1"
    if [[ -z "$DISTRO_ALIAS" ]]; then
        log_error "run_proot_cmd_user: DISTRO_ALIAS is not set."
        return 1
    fi
    if [[ -z "$USERNAME" ]]; then
        log_error "run_proot_cmd_user: USERNAME is not set."
        return 1
    fi
    if [[ -z "$cmd" ]]; then
        log_error "run_proot_cmd_user: no command provided"
        return 1
    fi
    proot-distro login "$DISTRO_ALIAS" --shared-tmp --user "$USERNAME" -- /bin/bash -c "$cmd"
}

# get_proot_pkg_manager
# Echoes the name of the package manager for the currently configured distro.
# Returns: apt | pacman | dnf
get_proot_pkg_manager() {
    case "$DISTRO_ALIAS" in
        debian|ubuntu)
            echo "apt"
            ;;
        archlinux)
            echo "pacman"
            ;;
        fedora)
            echo "dnf"
            ;;
        *)
            # Fallback: try to detect inside the proot environment.
            if run_proot_cmd "command -v apt-get" &>/dev/null; then
                echo "apt"
            elif run_proot_cmd "command -v pacman" &>/dev/null; then
                echo "pacman"
            elif run_proot_cmd "command -v dnf" &>/dev/null; then
                echo "dnf"
            else
                log_error "get_proot_pkg_manager: unable to determine package manager"
                return 1
            fi
            ;;
    esac
}

# get_proot_install_cmd
# Echoes the full non-interactive install command for the distro's pkg manager.
get_proot_install_cmd() {
    local pm
    pm="$(get_proot_pkg_manager)" || return 1
    case "$pm" in
        apt)     echo "apt-get install -y" ;;
        pacman)  echo "pacman -S --noconfirm" ;;
        dnf)     echo "dnf install -y" ;;
    esac
}

# get_proot_update_cmd
# Echoes the full non-interactive update+upgrade command.
get_proot_update_cmd() {
    local pm
    pm="$(get_proot_pkg_manager)" || return 1
    case "$pm" in
        apt)     echo "apt-get update && apt-get upgrade -y" ;;
        pacman)  echo "pacman -Syu --noconfirm" ;;
        dnf)     echo "dnf update -y" ;;
    esac
}

# ==============================================================================
# Configuration Persistence
# ==============================================================================
# Config is stored as a simple KEY=VALUE file under $ANDRUX_CONFIG/config.

# save_config
# Persists the current runtime state to disk.
save_config() {
    mkdir -p "$ANDRUX_CONFIG" || {
        log_error "save_config: failed to create config directory '$ANDRUX_CONFIG'"
        return 1
    }

    cat > "${ANDRUX_CONFIG}/config" <<-EOF
	# Andrux configuration — auto-generated, do not edit manually.
	# Last saved: $(date -Iseconds 2>/dev/null || date)
	DISTRO_ALIAS="${DISTRO_ALIAS}"
	DISTRO_NAME="${DISTRO_NAME}"
	DESKTOP_ENV="${DESKTOP_ENV}"
	USERNAME="${USERNAME}"
	GPU_TYPE="${GPU_TYPE}"
	GPU_METHOD="${GPU_METHOD}"
	EOF

    log_info "Configuration saved to ${ANDRUX_CONFIG}/config"
}

# load_config
# Restores state variables from disk.  Returns 1 if no config file exists.
load_config() {
    local config_file="${ANDRUX_CONFIG}/config"
    if [[ ! -f "$config_file" ]]; then
        log_warn "load_config: no config file found at '$config_file'"
        return 1
    fi

    # Source the file in a subshell-safe way: only import known variables.
    local line key value
    while IFS='=' read -r key value || [[ -n "$key" ]]; do
        # Skip comments and blank lines.
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue

        # Strip leading/trailing whitespace from key.
        key="${key#"${key%%[![:space:]]*}"}"
        key="${key%"${key##*[![:space:]]}"}"

        # Remove surrounding quotes from value.
        value="${value#\"}"
        value="${value%\"}"

        case "$key" in
            DISTRO_ALIAS) DISTRO_ALIAS="$value" ;;
            DISTRO_NAME)  DISTRO_NAME="$value" ;;
            DESKTOP_ENV)  DESKTOP_ENV="$value" ;;
            USERNAME)     USERNAME="$value" ;;
            GPU_TYPE)     GPU_TYPE="$value" ;;
            GPU_METHOD)   GPU_METHOD="$value" ;;
        esac
    done < "$config_file"

    log_info "Configuration loaded from $config_file"
}
