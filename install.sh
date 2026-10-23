#!/usr/bin/env bash
# ==============================================================================
# Script Name: VPS Optimizer & BBR Tuner (Debian, Ubuntu, & AlmaLinux Compatible)
# Description: Applies production-grade network and BBR congestion control tuning
# ==============================================================================

set -euo pipefail

# Check root privileges
if [[ $EUID -ne 0 ]]; then
   echo "[-] Error: This script must be run as root." 
   exit 1
fi

echo "[+] Detecting Operating System..."
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS=$ID
    VERSION_ID=${VERSION_ID:-}
else
    echo "[-] Error: /etc/os-release not found. Unsupported distribution."
    exit 1
fi

echo "[+] Detected OS: $NAME ($OS)"

# Handle package manager updates and dependency checks if required
echo "[+] Ensuring core networking tools are available..."
case "$OS" in
    ubuntu|debian)
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -yqq
        apt-get install -yqq procps iproute2 kmod
        ;;
    almalinux|rocky|centos|rhel)
        dnf install -y -q procps-ng iproute kmod
        ;;
    *)
        echo "[!] Warning: Unrecognized distribution ($OS). Proceeding with standard paths..."
        ;;
esac

# 1. Kernel Version Check (BBR requires >= 4.9)
echo "[+] Checking Linux kernel version..."
KERNEL_VERSION=$(uname -r | cut -d'.' -f1-2)
REQUIRED_MAJOR=4
REQUIRED_MINOR=9

CURRENT_MAJOR=$(echo "$KERNEL_VERSION" | cut -d'.' -f1)
CURRENT_MINOR=$(echo "$KERNEL_VERSION" | cut -d'.' -f2)

if (( CURRENT_MAJOR < REQUIRED_MAJOR )) || { (( CURRENT_MAJOR == REQUIRED_MAJOR )) && (( CURRENT_MINOR < REQUIRED_MINOR )); }; then
    echo "[-] Error: Linux kernel version 4.9+ is required for BBR. Current version: $(uname -r)"
    exit 1
fi

# 2. Ensure BBR Module is available and loaded
echo "[+] Loading BBR kernel module..."
modprobe tcp_bbr || true
if ! grep -q "tcp_bbr" /proc/modules; then
    echo "[-] Warning: tcp_bbr module could not be loaded dynamically. Proceeding with sysctl enforcement..."
fi

# 3. Write Optimized Parameters to sysctl.d
CONFIG_FILE="/etc/sysctl.d/99-vps-optimizer.conf"
echo "[+] Writing performance parameters to $CONFIG_FILE..."

cat << 'EOF' > "$CONFIG_FILE"
# --- Core BBR & Queue Discipline ---
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# --- Socket Memory & Buffer Limits ---
net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 65536 33554432
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432

# --- Backlog Queues ---
net.core.somaxconn = 16384
net.ipv4.tcp_max_syn_backlog = 8192
net.core.netdev_max_backlog = 16384

# --- Port Management & Timers ---
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15

# --- Keepalive Tuning ---
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_keepalive_probes = 3
EOF

# 4. Apply sysctl settings safely
echo "[+] Applying kernel parameters..."
sysctl --system

# 5. Verify Configuration
ACTIVE_CC=$(sysctl -n net.ipv4.tcp_congestion_control)
ACTIVE_QDISC=$(sysctl -n net.core.default_qdisc)

echo "=========================================="
echo "[+] Optimization Complete!"
echo "    - Operating System:   $NAME"
echo "    - Congestion Control: $ACTIVE_CC"
echo "    - Queue Discipline:   $ACTIVE_QDISC"
echo "=========================================="

if [[ "$ACTIVE_CC" == "bbr" && "$ACTIVE_QDISC" == "fq" ]]; then
    echo "[✔] BBR is successfully active and paired with fq!"
else
    echo "[!] Notice: Settings applied, but verify virtualization limits (OpenVZ/LXC environments often restrict kernel sysctl adjustments)."
fi
