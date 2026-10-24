#!/usr/bin/env bash
# ==============================================================================
# Script Name: VPS Optimizer & BBR Tuner (v2.1)
# Description: Production-grade network tuning for max speed, low latency
#              (non-buffering), and connection stability.
# Compatible : Debian 11+, Ubuntu 20.04+, AlmaLinux 8+, Rocky 8+, CentOS 8+,
#              RHEL 8+, Fedora 36+
# Notes       : Safe against CRLF line endings; self-heals if piped via curl.
# ==============================================================================

# ---- CRLF self-heal (works even if the file was saved on Windows) ----------
# If this script was fetched with CRLF endings, re-exec through sed to strip
# \r before bash parses it. Guard prevents infinite recursion.
if [[ "${VPS_OPT_LF_FIXED:-0}" != "1" ]] && grep -q $'\r' "${BASH_SOURCE[0]}" 2>/dev/null; then
  export VPS_OPT_LF_FIXED=1
  TMP=$(mktemp)
  sed 's/\r$//' "${BASH_SOURCE[0]}" > "$TMP"
  chmod +x "$TMP"
  bash "$TMP" "$@"
  EXIT_CODE=$?
  rm -f "$TMP"
  exit $EXIT_CODE
fi

set -euo pipefail

# ----------------------------
# Colors & logging
# ----------------------------
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { printf '%b[+]%b %s\n' "$GREEN" "$NC" "$*"; }
warn() { printf '%b[!]%b %s\n' "$YELLOW" "$NC" "$*"; }
err()  { printf '%b[-]%b %s\n' "$RED" "$NC" "$*" >&2; }

# ----------------------------
# Root check
# ----------------------------
if [[ $EUID -ne 0 ]]; then
  err "This script must be run as root."
  exit 1
fi

# ----------------------------
# OS detection
# ----------------------------
log "Detecting operating system..."
if [[ -f /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  OS=$ID
  NAME=${PRETTY_NAME:-$NAME}
else
  err "/etc/os-release not found. Unsupported distribution."
  exit 1
fi
log "Detected: $NAME ($OS)"

# ----------------------------
# Dependencies
# ----------------------------
log "Ensuring core networking tools are installed..."
case "$OS" in
  ubuntu|debian)
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -yqq
    apt-get install -yqq procps iproute2 kmod ethtool curl
    ;;
  almalinux|rocky|centos|rhel|fedora)
    dnf install -y -q procps-ng iproute kmod ethtool curl
    ;;
  *)
    warn "Unrecognized distribution ($OS). Proceeding with available tools..."
    ;;
esac

# ----------------------------
# Kernel version check
# ----------------------------
log "Checking kernel version..."
KVER=$(uname -r)
KMAJ=$(echo "$KVER" | cut -d'.' -f1)
KMIN=$(echo "$KVER" | cut -d'.' -f2)
if (( KMAJ < 4 )) || { (( KMAJ == 4 )) && (( KMIN < 9 )); }; then
  err "Kernel $KVER is too old for BBR. Please upgrade to 4.9+ (5.10+ recommended)."
  exit 1
fi
if (( KMAJ < 5 )); then
  warn "Kernel $KVER works, but 5.10+ is recommended for full BBRv2 + fq_codel benefits."
fi

# ----------------------------
# Load BBR module
# ----------------------------
log "Loading BBR kernel module..."
modprobe tcp_bbr 2>/dev/null || warn "Could not modprobe tcp_bbr (may be built-in or restricted by LXC/OpenVZ)."

AVAILABLE_CC=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || echo "")
if [[ "$AVAILABLE_CC" != *"bbr"* ]]; then
  warn "BBR not available in this kernel/container. Falling back to cubic + fq_codel."
  FALLBACK=1
else
  FALLBACK=0
fi

# ----------------------------
# RAM-scaled buffers
# ----------------------------
TOTAL_MEM_MB=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)
BUF_MAX_MB=$(( TOTAL_MEM_MB * 5 / 100 ))
(( BUF_MAX_MB < 64 ))  && BUF_MAX_MB=64
(( BUF_MAX_MB > 256 )) && BUF_MAX_MB=256
BUF_MAX_BYTES=$(( BUF_MAX_MB * 1024 * 1024 ))
BUF_DEFAULT=$(( BUF_MAX_MB * 1024 * 1024 / 4 ))
log "RAM: ${TOTAL_MEM_MB} MB → max buffer: ${BUF_MAX_MB} MB"

# ----------------------------
# Conntrack scaling (only if already loaded)
# ----------------------------
CONNTRACK_LINE=""
if [[ -f /proc/sys/net/netfilter/nf_conntrack_max ]]; then
  CT_MAX=$(( TOTAL_MEM_MB * 64 ))
  (( CT_MAX < 65536 ))   && CT_MAX=65536
  (( CT_MAX > 1048576 )) && CT_MAX=1048576
  CONNTRACK_LINE="net.netfilter.nf_conntrack_max = $CT_MAX"
  log "Conntrack max will be set to $CT_MAX"
fi

# ----------------------------
# Backup existing config
# ----------------------------
CONFIG_FILE="/etc/sysctl.d/99-vps-optimizer.conf"
BACKUP_FILE="${CONFIG_FILE}.bak.$(date +%s)"

if [[ -f "$CONFIG_FILE" ]]; then
  log "Backing up existing config to $BACKUP_FILE"
  cp "$CONFIG_FILE" "$BACKUP_FILE"
fi

# ----------------------------
# Choose CC + qdisc
# ----------------------------
if (( FALLBACK == 1 )); then
  CC="cubic"
  QDISC="fq_codel"
else
  CC="bbr"
  QDISC="fq"
fi

log "Writing tuning parameters to $CONFIG_FILE ..."

cat > "$CONFIG_FILE" << EOF
# ==============================================================
# VPS Optimizer v2.1 — generated $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# ==============================================================

# --- Congestion Control & Queue Discipline --------------------
net.core.default_qdisc = $QDISC
net.ipv4.tcp_congestion_control = $CC

# --- Socket buffer memory (scaled to ${BUF_MAX_MB} MB) --------
net.ipv4.tcp_rmem = 4096 131072 $BUF_MAX_BYTES
net.ipv4.tcp_wmem = 4096 65536  $BUF_MAX_BYTES
net.core.rmem_max = $BUF_MAX_BYTES
net.core.wmem_max = $BUF_MAX_BYTES
net.core.rmem_default = $BUF_DEFAULT
net.core.wmem_default = $BUF_DEFAULT
net.core.optmem_max = 65536

# --- Backlog & connection queues (anti-bufferbloat) -----------
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_max_tw_buckets = 262144
net.ipv4.tcp_max_orphans = 65536

# --- TCP throughput & latency --------------------------------
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_fack = 1
net.ipv4.tcp_dsack = 1
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_moderate_rcvbuf = 1
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_ecn = 0
net.ipv4.tcp_notsent_lowat = 16384

# --- Reconnection resilience / keepalive ----------------------
net.ipv4.tcp_keepalive_time = 120
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_retries2 = 8
net.ipv4.tcp_syn_retries = 3
net.ipv4.tcp_synack_retries = 2

# --- Port range ----------------------------------------------
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.ip_local_reserved_ports = 32768-60999

# --- Misc stability ------------------------------------------
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0

# --- IP forwarding (kept off by default; uncomment if needed)
# net.ipv4.ip_forward = 1

$CONNTRACK_LINE
EOF

# ----------------------------
# Apply sysctl
# ----------------------------
log "Applying sysctl settings..."
if ! sysctl --system > /tmp/sysctl_apply.log 2>&1; then
  warn "sysctl reported warnings (see /tmp/sysctl_apply.log). Continuing..."
fi

# ----------------------------
# Verification
# ----------------------------
ACTIVE_CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
ACTIVE_QDISC=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "unknown")

echo
echo "==============================================="
echo " VPS Optimization Complete"
echo "-----------------------------------------------"
echo " OS               : $NAME"
echo " Kernel           : $KVER"
echo " Congestion Ctrl  : $ACTIVE_CC"
echo " Queue Discipline : $ACTIVE_QDISC"
echo " Buffer Max       : ${BUF_MAX_MB} MB"
echo "==============================================="

if [[ "$ACTIVE_CC" == "bbr" && "$ACTIVE_QDISC" == "fq" ]]; then
  log "BBR + fq is active. Optimal low-latency TCP stack enabled."
elif [[ "$ACTIVE_CC" == "cubic" && "$ACTIVE_QDISC" == "fq_codel" ]]; then
  warn "Running in fallback mode (cubic + fq_codel). Works well but BBR is faster on lossy links."
else
  warn "Settings applied, but not active. If you are on OpenVZ/LXC, the host must permit these sysctls."
fi

echo
log "Done. Reboot is NOT required — settings are live."
