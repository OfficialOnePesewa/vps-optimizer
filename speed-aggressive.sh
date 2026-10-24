#!/bin/bash
# ==========================================================
# OPUDP EXTREME SPEED — AGGRESSIVE MODE
# Target: 1000+ concurrent connections, 1080p/4K streaming,
#         heavy VoIP + ZiVPN + HTTP Custom workloads
# Requires: >= 2 GB RAM (will refuse to run on smaller VPS)
# ==========================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { printf '%b[+]%b %s\n' "$GREEN" "$NC" "$*"; }
warn() { printf '%b[!]%b %s\n' "$YELLOW" "$NC" "$*"; }
err()  { printf '%b[-]%b %s\n' "$RED" "$NC" "$*" >&2; }

if [[ $EUID -ne 0 ]]; then
  err "Run as root."
  exit 1
fi

# ---- Safety: refuse on small VPS -------------------------------------------
TOTAL_MEM_MB=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)
if (( TOTAL_MEM_MB < 2048 )); then
  err "Aggressive mode requires >= 2 GB RAM (detected ${TOTAL_MEM_MB} MB)."
  err "Use speed.sh (normal mode) instead."
  exit 1
fi
log "RAM: ${TOTAL_MEM_MB} MB — OK for aggressive mode."

# ---- RAM-scaled aggressive buffers -----------------------------------------
# 12% of RAM, clamped 128 MB – 512 MB
BUF_MAX_MB=$(( TOTAL_MEM_MB * 12 / 100 ))
(( BUF_MAX_MB < 128 )) && BUF_MAX_MB=128
(( BUF_MAX_MB > 512 )) && BUF_MAX_MB=512
BUF_MAX_BYTES=$(( BUF_MAX_MB * 1024 * 1024 ))
log "Buffer max: ${BUF_MAX_MB} MB"

# ---- Conntrack scaling (if loaded) -----------------------------------------
CONNTRACK_LINE=""
if [[ -f /proc/sys/net/netfilter/nf_conntrack_max ]]; then
  CT_MAX=$(( TOTAL_MEM_MB * 128 ))
  (( CT_MAX < 262144 ))  && CT_MAX=262144
  (( CT_MAX > 4194304 )) && CT_MAX=4194304
  CONNTRACK_LINE="net.netfilter.nf_conntrack_max = $CT_MAX"
  log "Conntrack max: $CT_MAX"
fi

# ---- Backup + write config -------------------------------------------------
CONFIG="/etc/sysctl.d/99-speed-aggressive.conf"
if [[ -f "$CONFIG" ]]; then
  cp "$CONFIG" "${CONFIG}.bak.$(date +%s)"
  log "Backed up existing $CONFIG"
fi

log "Writing $CONFIG ..."
cat > "$CONFIG" << SYS
# ==============================================================
# OPUDP EXTREME SPEED — AGGRESSIVE (generated $(date -u +"%Y-%m-%dT%H:%M:%SZ"))
# ==============================================================

# --- BBR + fq -------------------------------------------------
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# --- Global socket caps (shared TCP+UDP, ${BUF_MAX_MB} MB) ----
net.core.rmem_max = $BUF_MAX_BYTES
net.core.wmem_max = $BUF_MAX_BYTES
net.core.rmem_default = 4194304
net.core.wmem_default = 4194304
net.core.optmem_max = 131072

# --- TCP buffer (${BUF_MAX_MB} MB) ----------------------------
net.ipv4.tcp_rmem = 8192 262144 $BUF_MAX_BYTES
net.ipv4.tcp_wmem = 8192 262144 $BUF_MAX_BYTES

# --- UDP buffer (VoIP / ZiVPN / HTTP Custom heavy) ------------
net.ipv4.udp_mem = 262144 524288 1048576
net.ipv4.udp_rmem_min = 32768
net.ipv4.udp_wmem_min = 32768

# --- Backlog & queues (high concurrency) ----------------------
net.core.netdev_max_backlog = 262144
net.core.somaxconn = 131072
net.ipv4.tcp_max_syn_backlog = 262144
net.ipv4.tcp_max_tw_buckets = 1048576
net.ipv4.tcp_max_orphans = 262144

# --- Throughput & latency -------------------------------------
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_moderate_rcvbuf = 1
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_notsent_lowat = 16384

# --- Reconnection resilience ----------------------------------
net.ipv4.tcp_keepalive_time = 90
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_retries2 = 6
net.ipv4.tcp_syn_retries = 3

# --- Port range (max) -----------------------------------------
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.ip_local_reserved_ports = 32768-60999

# --- Misc stability -------------------------------------------
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# --- Conntrack (if loaded) ------------------------------------
$CONNTRACK_LINE
SYS

# ---- Apply -------------------------------------------------
log "Applying sysctl ..."
if ! sysctl --system > /tmp/sysctl_aggressive.log 2>&1; then
  warn "sysctl warnings — see /tmp/sysctl_aggressive.log"
fi

# ---- Verify ------------------------------------------------
CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "?")
QD=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "?")
RM=$(sysctl -n net.core.rmem_max 2>/dev/null || echo 0)
UM=$(sysctl -n net.ipv4.udp_mem 2>/dev/null || echo "?")

echo
echo "==============================================="
echo " AGGRESSIVE Speed Tuning Applied"
echo "-----------------------------------------------"
echo " Congestion Ctrl : $CC"
echo " Queue Discipline: $QD"
echo " rmem_max        : $RM ($(( RM / 1024 / 1024 )) MB)"
echo " udp_mem         : $UM"
echo " Conntrack       : ${CONNTRACK_LINE:-not loaded}"
echo "==============================================="

if [[ "$CC" == "bbr" && "$QD" == "fq" ]]; then
  log "BBR + fq active."
else
  warn "BBR/fq not fully active — check kernel/container."
fi

echo
log "No reboot required — settings are live."
log "Rollback: rm $CONFIG && sysctl --system"
warn "Monitor UDP drops with: nstat -az UdpRcvbufErrors UdpInErrors"
