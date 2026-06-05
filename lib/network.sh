#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# Andrux — network.sh
# Networking configuration for proot-distro.
#
# proot-distro inherits the Android host's network stack via system-call
# translation, so sockets, TCP, and UDP work out of the box.  The only
# thing we need to configure is DNS resolution (/etc/resolv.conf) and a
# sane /etc/hosts file.
#
# Provides:
#   setup_network  — write resolv.conf + /etc/hosts inside proot
#   test_network   — verify DNS and HTTP from inside proot
#   fix_dns        — emergency DNS repair
#
# Depends on (sourced before this file):
#   common.sh → log_*, run_proot_cmd, DISTRO_NAME
# =============================================================================

# Public DNS servers used by default.
# Google primary/secondary — widely reachable and fast.
readonly _DNS_PRIMARY="8.8.8.8"
readonly _DNS_SECONDARY="8.8.4.4"

# -----------------------------------------------------------------------------
# setup_network
#   Configures DNS and /etc/hosts inside the proot distro.
#   Also prevents common Linux daemons (dhclient, NetworkManager, systemd-
#   resolved) from overwriting our resolv.conf.
# -----------------------------------------------------------------------------
setup_network() {
    log_step "Configuring networking inside proot…"

    # ---- 1. Write /etc/resolv.conf ----
    _write_resolv_conf || return 1

    # ---- 2. Protect resolv.conf from being overwritten ----
    _protect_resolv_conf

    # ---- 3. Write /etc/hosts ----
    _write_etc_hosts || return 1

    log_success "Network configuration complete."
}

# -----------------------------------------------------------------------------
# _write_resolv_conf   (internal)
#   Creates a static /etc/resolv.conf with known-good public DNS servers.
# -----------------------------------------------------------------------------
_write_resolv_conf() {
    log_info "Writing /etc/resolv.conf (DNS: ${_DNS_PRIMARY}, ${_DNS_SECONDARY})…"

    run_proot_cmd "cat > /etc/resolv.conf << 'DNSEOF'
# Andrux — static DNS configuration
# proot does not run a DHCP client, so we set resolvers manually.
nameserver ${_DNS_PRIMARY}
nameserver ${_DNS_SECONDARY}
DNSEOF" || {
        log_error "Failed to write /etc/resolv.conf."
        return 1
    }
}

# -----------------------------------------------------------------------------
# _protect_resolv_conf   (internal)
#   Makes resolv.conf immutable (where possible) and disables services that
#   would overwrite it.  In proot we cannot use chattr, but we can remove
#   symlinks and disable known culprits.
# -----------------------------------------------------------------------------
_protect_resolv_conf() {
    log_info "Protecting /etc/resolv.conf from being overwritten…"

    # If resolv.conf is a symlink (e.g. to ../run/systemd/resolve/stub-resolv.conf),
    # replace it with a regular file.
    run_proot_cmd "if [ -L /etc/resolv.conf ]; then
        rm -f /etc/resolv.conf
        cat > /etc/resolv.conf << 'DNSEOF'
nameserver ${_DNS_PRIMARY}
nameserver ${_DNS_SECONDARY}
DNSEOF
    fi"

    # Disable systemd-resolved if it exists (it cannot work in proot anyway).
    run_proot_cmd "if command -v systemctl >/dev/null 2>&1; then
        systemctl disable systemd-resolved 2>/dev/null || true
        systemctl mask systemd-resolved 2>/dev/null || true
    fi" 2>/dev/null

    # Disable resolvconf / openresolv hook if present.
    run_proot_cmd "if [ -f /etc/resolvconf.conf ]; then
        echo 'resolv_conf=/dev/null' >> /etc/resolvconf.conf 2>/dev/null
    fi" 2>/dev/null

    # Prevent dhclient from clobbering resolv.conf (Debian/Ubuntu).
    run_proot_cmd "if [ -d /etc/dhcp/dhclient-enter-hooks.d ]; then
        cat > /etc/dhcp/dhclient-enter-hooks.d/no-resolv << 'DHEOF'
#!/bin/sh
# Andrux — prevent dhclient from overwriting resolv.conf
make_resolv_conf() { :; }
DHEOF
        chmod +x /etc/dhcp/dhclient-enter-hooks.d/no-resolv
    fi" 2>/dev/null
}

# -----------------------------------------------------------------------------
# _write_etc_hosts   (internal)
#   Writes a minimal /etc/hosts with loopback entries.
# -----------------------------------------------------------------------------
_write_etc_hosts() {
    log_info "Writing /etc/hosts…"

    run_proot_cmd "cat > /etc/hosts << 'HOSTEOF'
# Andrux — static /etc/hosts
127.0.0.1   localhost
::1         localhost
HOSTEOF" || {
        log_error "Failed to write /etc/hosts."
        return 1
    }
}

# -----------------------------------------------------------------------------
# test_network
#   Runs a multi-stage connectivity check from inside proot:
#     1. DNS resolution test
#     2. HTTPS connectivity test
#   Returns 0 if all tests pass, 1 otherwise.
# -----------------------------------------------------------------------------
test_network() {
    log_step "Testing network connectivity from inside proot…"

    local all_passed=true

    # ---- 1. DNS resolution ----
    log_info "Test 1/2 — DNS resolution…"

    local dns_ok=false
    local dns_output=""

    # Try several DNS tools in order of likelihood of being installed.
    for dns_tool in "getent hosts google.com" "nslookup google.com" "host google.com"; do
        dns_output="$(run_proot_cmd "${dns_tool}" 2>&1)" && {
            dns_ok=true
            break
        }
    done

    if "${dns_ok}"; then
        log_success "DNS resolution works."
        log_info "  ${dns_output}" | head -2
    else
        log_error "DNS resolution failed."
        log_error "  None of getent/nslookup/host could resolve google.com."
        all_passed=false
    fi

    # ---- 2. HTTPS connectivity ----
    log_info "Test 2/2 — HTTPS connectivity…"

    local http_output
    http_output="$(run_proot_cmd "curl -sI --connect-timeout 10 https://example.com 2>&1")" || true

    if echo "${http_output}" | grep -qi "^HTTP/"; then
        local status_line
        status_line="$(echo "${http_output}" | grep -i "^HTTP/" | head -1)"
        log_success "HTTPS connectivity works."
        log_info "  ${status_line}"
    else
        # curl might not be installed — try wget
        http_output="$(run_proot_cmd "wget -q --spider --timeout=10 https://example.com 2>&1")" && {
            log_success "HTTPS connectivity works (via wget)."
        } || {
            log_error "HTTPS connectivity failed."
            log_error "  Neither curl nor wget could reach https://example.com."
            all_passed=false
        }
    fi

    # ---- Summary ----
    if "${all_passed}"; then
        log_success "All network tests passed."
        return 0
    else
        log_error "Some network tests failed.  Run 'andrux fix-dns' if DNS is broken."
        return 1
    fi
}

# -----------------------------------------------------------------------------
# fix_dns
#   Emergency DNS repair.  Nukes existing resolv.conf and rewrites it.
#   Useful when a package update or hook has clobbered the file.
# -----------------------------------------------------------------------------
fix_dns() {
    log_step "Emergency DNS fix — rewriting /etc/resolv.conf…"

    # Remove whatever is there (file, symlink, broken link)
    run_proot_cmd "rm -f /etc/resolv.conf" 2>/dev/null

    _write_resolv_conf || {
        log_error "Emergency DNS fix failed.  Manual intervention required:"
        log_error "  proot-distro login ${DISTRO_ALIAS}"
        log_error "  echo 'nameserver 8.8.8.8' > /etc/resolv.conf"
        return 1
    }

    _protect_resolv_conf

    log_success "DNS fixed.  Testing connectivity…"
    test_network
}
