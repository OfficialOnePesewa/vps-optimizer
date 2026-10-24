#!/usr/bin/env bash
# ==============================================================================
# Script Name: VPS Optimizer & BBR Tuner (v2.3)
# Description: Production-grade network tuning for max speed, low latency,
#              and connection stability. Optional --aggressive mode for
#              high-traffic VPS (1000+ concurrent connections).
# Compatible : Debian 11+, Ubuntu 20.04+, AlmaLinux 8+, Rocky 8+, CentOS 8+,
#              RHEL 8+, Fedora 36+
# Usage      : bash install.sh [--normal|--aggressive]
# ==============================================================================

# ---- CRLF self-heal --------------------------------------------------------
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
# Parse args
# ----------------------------
MODE="normal"
for arg in "$@"; do
  case "$arg" in
    --aggressive) MODE="aggressive" ;;
    --normal)     MODE="normal" ;;
    -h|--help)
      cat << 'HLP'
Usage: bash install.sh [OPTIONS]

Options:
  --normal       Standard tuning (default). 64–256 MB buffers. Safe for 512 MB+.
  --aggressive   High-traffic tuning. 128–512 MB buffers. Requires 2 GB+ RAM.
  -h, --help     Show this help.
HLP
      exit 0
      ;;
    *) echo "Unknown option: $arg (try --help)" >&2; exit 1 ;;
  esac
done

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
# Kernel check
# ----------------------------
log "Checking kernel version..."
KVER=$(uname -r)
KMAJ=$(echo "$KVER" | cut -d'.' -f1)
KMIN=$(echo "$KVER" | cut -d'.' -f2)
if (( KMAJ < 4 )) || { (( KMAJ == 4 )) && (( KMIN < 9 )); }; then
  err "Kernel $KVER is too old for BBR (need 4.9+)."
  exit 1
fi
if (( KMAJ < 5 )); then
  warn "Kernel $KVER works, but 5.10+ is recommended."
fi

# ----------------------------
# Load BBR
# ----------------------------
log "Loading BBR kernel module..."
modprobe tcp_bbr 2>/dev/null || warn "Could not modprobe tcp_bbr (may be built-in or restricted)."

AVAILABLE_CC=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || echo "")
if [[ "$AVAILABLE_CC" != *"bbr"* ]]; then
  warn "BBR not available — falling back to cubic + fq_codel."
  FALLBACK=1
else
  FALLBACK=0
fi

# ----------------------------
# RAM detection & MODE-aware sizing
# ----------------------------
TOTAL_MEM_MB=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)

if [[ "$MODE" == "aggressive" ]]; then
  if (( TOTAL_MEM_MB < 2048 )); then
    err "--aggressive requires >= 2 GB RAM (detected ${TOTAL_MEM_MB} MB)."
    err "Re-run without the flag, or use: bash speed.sh"
    exit 1
  fi
  BUF_MAX_MB=$(( TOTAL_MEM_MB * 12 / 100 ))
  (( BUF_MAX_MB < 128 )) && BUF_MAX_MB=128
  (( BUF_MAX_MB > 512 )) && BUF_MAX_MB=512
  UDP_MEM_PAGES="262144 524288 1048576"
  UDP_RMEM_MIN=32768
  UDP_WMEM_MIN=32768
  SOMAXCONN=131072
  NETDEV_BACKLOG=262144
  SYN_BACKLOG=262144
  TW_BUCKETS=1048576
  MAX_ORPHANS=262144
  KA_TIME=90; KA_INTVL=10; KA_PROBES=5
  FIN_TIMEOUT=10
  RETRIES2=6
  UDP_RMEM_MAX=$(( 64 * 1024 * 1024 ))
  UDP_WMEM_MAX=$(( 64 * 1024 * 1024 ))
  UDP_RMEM_DEFAULT=$(( 4 * 1024 * 1024 ))
  UDP_WMEM_DEFAULT=$(( 4 * 1024 * 1024 ))
else
  BUF_MAX_MB=$(( TOTAL_MEM_MB * 5 / 100 ))
  (( BUF_MAX_MB < 64 ))  && BUF_MAX_MB=64
  (( BUF_MAX_MB > 256 )) && BUF_MAX_MB=256
  UDP_MEM_PAGES="131072 262144 524288"
  UDP_RMEM_MIN=16384
  UDP_WMEM_MIN=16384
  SOMAXCONN=65535
  NETDEV_BACKLOG=65535
  SYN_BACKLOG=65535
  TW_BUCKETS=262144
  MAX_ORPHANS=65536
  KA_TIME=120; KA_INTVL=15; KA_PROBES=5
  FIN_TIMEOUT=15
  RETRIES2=8
  UDP_RMEM_MAX=$(( 32 * 1024 * 1024 ))
  UDP_WMEM_MAX=$(( 32 * 1024 * 1024 ))
  UDP_RMEM_DEFAULT=$(( 2 * 1024 * 1024 ))
  UDP_WMEM_DEFAULT=$(( 2 * 1024 * 1024 ))
fi

BUF_MAX_BYTES=$(( BUF_MAX_MB * 1024 * 1024 ))
BUF_DEFAULT=$(( BUF_MAX_MB * 1024 * 1024 / 4 ))
log "Mode: ${MODE} | RAM: ${TOTAL_MEM_MB} MB → TCP buffer max: ${BUF_MAX_MB} MB"

# ----------------------------
# Conntrack (scaled by mode)
# ----------------------------
CONNTRACK_LINE=""
if [[ -f /proc/sys/net/netfilter/nf_conntrack_max ]]; then
  if [[ "$MODE" == "aggressive" ]]; then
    CT_MAX=$(( TOTAL_MEM_MB * 128 ))
    (( CT_MAX < 262144 ))  && CT_MAX=262144
    (( CT_MAX > 4194304 )) && CT_MAX=4194304
  else
    CT_MAX=$(( TOTAL_MEM_MB * 64 ))
    (( CT_MAX < 65536 ))   && CT_MAX=65536
    (( CT_MAX > 1048576 )) && CT_MAX=1048576
  fi
  CONNTRACK_LINE="net.netfilter.nf_conntrack_max = $CT_MAX"
  log "Conntrack max: $CT_MAX"
fi

# ----------------------------
# Backup existing config
# ----------------------------
CONFIG_FILE="/etc/sysctl.d/99-vps-optimizer.conf"
if [[ -f "$CONFIG_FILE" ]]; then
  BACKUP="${CONFIG_FILE}.bak.$(date +%s)"
  cp "$CONFIG_FILE" "$BACKUP"
  log "Backed up existing config to $BACKUP"
fi

# ----------------------------
# CC + qdisc
# ----------------------------
if (( FALLBACK == 1 )); then
  CC="cubic"; QDISC="fq_codel"
else
  CC="bbr"; QDISC="fq"
fi

# Global caps (shared TCP+UDP)
GLOBAL_RMEM_MAX=$BUF_MAX_BYTES
GLOBAL_WMEM_MAX=$BUF_MAX_BYTES
(( UDP_RMEM_MAX > GLOBAL_RMEM_MAX )) && GLOBAL_RMEM_MAX=$UDP_RMEM_MAX
(( UDP_WMEM_MAX > GLOBAL_WMEM_MAX )) && GLOBAL_WMEM_MAX=$UDP_WMEM_MAX

log "Writing tuning parameters to $CONFIG_FILE ..."
cat > "$CONFIG_FILE" << EOF
# ==============================================================
# VPS Optimizer v2.3 — mode=${MODE}
# generated $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# ==============================================================

# --- Congestion Control & Queue Discipline --------------------
net.core.default_qdisc = $QDISC
net.ipv4.tcp_congestion_control = $CC

# --- Shared global buffer caps (TCP + UDP) --------------------
net.core.rmem_max = $GLOBAL_RMEM_MAX
net.core.wmem_max = $GLOBAL_WMEM_MAX
net.core.rmem_default = $BUF_DEFAULT
net.core.wmem_default = $BUF_DEFAULT
net.core.optmem_max = 65536

# --- TCP socket buffers (scaled to ${BUF_MAX_MB} MB) ----------
net.ipv4.tcp_rmem = 4096 131072 $BUF_MAX_BYTES
net.ipv4.tcp_wmem = 4096 65536  $BUF_MAX_BYTES

# --- UDP / QUIC / Hysteria2 / VoIP ----------------------------
net.ipv4.udp_mem = $UDP_MEM_PAGES
net.ipv4.udp_rmem_min = $UDP_RMEM_MIN
net.ipv4.udp_wmem_min = $UDP_WMEM_MIN

# --- Backlog & queues -----------------------------------------
net.core.somaxconn = $SOMAXCONN
net.core.netdev_max_backlog = $NETDEV_BACKLOG
net.ipv4.tcp_max_syn_backlog = $SYN_BACKLOG
net.ipv4.tcp_max_tw_buckets = $TW_BUCKETS
net.ipv4.tcp_max_orphans = $MAX_ORPHANS

# --- TCP throughput & latency --------------------------------
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_moderate_rcvbuf = 1
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_ecn = 0
net.ipv4.tcp_notsent_lowat = 16384

# --- Reconnection resilience ---------------------------------
net.ipv4.tcp_keepalive_time = $KA_TIME
net.ipv4.tcp_keepalive_intvl = $KA_INTVL
net.ipv4.tcp_keepalive_probes = $KA_PROBES
net.ipv4.tcp_fin_timeout = $FIN_TIMEOUT
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_retries2 = $RETRIES2
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

# --- IP forwarding OFF by default ----------------------------
# Uncomment ONLY if this VPS is a gateway AND iptables is configured.
# net.ipv4.ip_forward = 1
# net.ipv6.conf.all.forwarding = 1

$CONNTRACK_LINE
EOF

# ----------------------------
# Apply
# ----------------------------
log "Applying sysctl settings..."
if ! sysctl --system > /tmp/sysctl_apply.log 2>&1; then
  warn "sysctl warnings — see /tmp/sysctl_apply.log"
fi

# ----------------------------
# Verify
# ----------------------------
ACTIVE_CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
ACTIVE_QDISC=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "unknown")
ACTIVE_UDP_MEM=$(sysctl -n net.ipv4.udp_mem 2>/dev/null || echo "n/a")
ACTIVE_RMEM_MAX=$(sysctl -n net.core.rmem_max 2>/dev/null || echo "n/a")

echo
echo "==============================================="
echo " VPS Optimization Complete (v2.3 — mode=${MODE})"
echo "-----------------------------------------------"
echo " OS               : $NAME"
echo " Kernel           : $KVER"
echo " Congestion Ctrl  : $ACTIVE_CC"
echo " Queue Discipline : $ACTIVE_QDISC"
echo " TCP Buffer Max   : ${BUF_MAX_MB} MB"
echo " Global rmem_max  : $ACTIVE_RMEM_MAX"
echo " UDP mem pages    : $ACTIVE_UDP_MEM"
echo "==============================================="

if [[ "$ACTIVE_CC" == "bbr" && "$ACTIVE_QDISC" == "fq" ]]; then
  log "BBR + fq is active."
elif [[ "$ACTIVE_CC" == "cubic" && "$ACTIVE_QDISC" == "fq_codel" ]]; then
  warn "Fallback mode (cubic + fq_codel)."
else
  warn "Settings applied but not active — check OpenVZ/LXC limits."
fi

echo
log "Done. Reboot NOT required."
warn "MTU reminder for VoIP/ZiVPN/HTTP Custom: client MTU 1400–1420."
