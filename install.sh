#!/usr/bin/env bash
#
# VPS Optimizer - Installer
# Optimizes Linux for high-speed streaming, ZIVPN, and Mobile LTE/H+
#
set -euo pipefail

REPO_RAW="${VPS_OPTIMIZER_REPO:-https://raw.githubusercontent.com/OfficialOnePesewa/vps-optimizer/main}"
INSTALL_DIR="/usr/local/lib/vps-optimizer"
CONFIG_DIR="/etc/vps-optimizer"
BIN_LINK="/usr/local/bin/op-optimizer"

if [[ -t 1 ]]; then
    C_RED='\033[0;31m'; C_GRN='\033[0;32m'; C_YLW='\033[1;33m'
    C_BLU='\033[0;34m'; C_BLD='\033[1m'; C_NC='\033[0m'
else
    C_RED=''; C_GRN=''; C_YLW=''; C_BLU=''; C_BLD=''; C_NC=''
fi
log()  { printf "${C_BLU}[INFO]${C_NC} %s\n" "$*"; }
ok()   { printf "${C_GRN}[ OK ]${C_NC} %s\n" "$*"; }
warn() { printf "${C_YLW}[WARN]${C_NC} %s\n" "$*"; }
die()  { printf "${C_RED}[FAIL]${C_NC} %s\n" "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root:  sudo bash install.sh"

detect_os() {
    [[ -r /etc/os-release ]] || die "/etc/os-release missing"
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_VER="${VERSION_ID:-unknown}"
    log "Detected: ${OS_ID} ${OS_VER}  (kernel $(uname -r))"
}

install_deps() {
    local base=(curl wget iproute2 procps ca-certificates python3 build-essential cmake)
    case "$OS_ID" in
        ubuntu|debian|linuxmint|pop)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq
            apt-get install -y -qq "${base[@]}" >/dev/null
            ;;
        centos|rhel|almalinux|rocky|fedora)
            ( yum install -y -q curl wget iproute procps-ng ca-certificates python3 gcc gcc-c++ make cmake >/dev/null 2>&1 \
              || dnf install -y -q curl wget iproute procps-ng ca-certificates python3 gcc gcc-c++ make cmake >/dev/null 2>&1 ) || true
            ;;
    esac
    ok "Dependencies ready"
}

fetch() {
    local rel="$1" dst="$2"
    curl -fsSL --retry 3 --retry-delay 2 \
         --connect-timeout 10 --max-time 60 \
         "$REPO_RAW/$rel" -o "$dst" \
      || die "Failed to download $rel"
    [[ -s "$dst" ]] || die "Downloaded $rel is empty"
    
    # CRITICAL FIX: Self-heal Windows CRLF line endings automatically
    sed -i 's/\r$//' "$dst"
}

install_files() {
    log "Installing files into $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR" "$CONFIG_DIR"
    chmod 755 "$INSTALL_DIR"

    fetch "bin/op-optimizer" "$INSTALL_DIR/op-optimizer"
    fetch "lib/common.sh"    "$INSTALL_DIR/common.sh"
    fetch "config/badvpn.env" "$INSTALL_DIR/badvpn.env"
    fetch "systemd/badvpn@.service" "$INSTALL_DIR/badvpn@.service"

    chmod 755 "$INSTALL_DIR/op-optimizer"
    chmod 644 "$INSTALL_DIR/common.sh" "$INSTALL_DIR/badvpn.env" "$INSTALL_DIR/badvpn@.service"

    ln -sfn "$INSTALL_DIR/op-optimizer" "$BIN_LINK"
    ok "Files installed"
}

install_badvpn_unit() {
    if [[ -f "$INSTALL_DIR/badvpn@.service" && ! -f /etc/systemd/system/badvpn@.service ]]; then
        cp "$INSTALL_DIR/badvpn@.service" /etc/systemd/system/badvpn@.service
        systemctl daemon-reload
        ok "BadVPN systemd unit installed (disabled by default)"
    fi
}

apply_tuning() {
    log "Applying mobile/LTE network tuning..."
    "$BIN_LINK" apply
}

main() {
    printf "${C_BLD}╔══════════════════════════════════════════════════╗${C_NC}\n"
    printf "${C_BLD}║   VPS Optimizer — LTE/H+ & ZIVPN Edition         ║${C_NC}\n"
    printf "${C_BLD}║   BBR • fq • MTU Probing • Mbps Speedtest        ║${C_NC}\n"
    printf "${C_BLD}╚══════════════════════════════════════════════════╝${C_NC}\n\n"

    detect_os
    install_deps
    install_files
    install_badvpn_unit
    apply_tuning

    echo
    ok "Installation complete."
    printf "  ${C_BLD}Next steps:${C_NC}\n"
    printf "    sudo op-optimizer status\n"
    printf "    sudo op-optimizer speedtest\n"
    echo
}

main "$@"
