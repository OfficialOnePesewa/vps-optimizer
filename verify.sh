#!/usr/bin/env bash
# ==============================================================================
# VPS Optimizer — Verification (v2.2)
# Notes: Safe against CRLF line endings; self-heals if piped via curl.
#        v2.2 adds UDP / QUIC / Hysteria2 reporting.
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

set -uo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { printf '%b✔%b %s\n' "$GREEN" "$NC" "$*"; }
bad()  { printf '%b✘%b %s\n' "$RED" "$NC" "$*"; }
info() { printf '%bℹ%b %s\n' "$YELLOW" "$NC" "$*"; }
row()  { printf '%-30s : %s\n' "$1" "$2"; }

echo "═══════════════════════════════════════════════"
echo " VPS Optimizer — Verification (v2.2)"
echo "═══════════════════════════════════════════════"
echo

# ---------------------------------------------------------------------------
# 1. TCP stack
# ---------------------------------------------------------------------------
echo "=== TCP Stack Status ==="
CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
QDISC=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "unknown")
row "Congestion Control" "$CC"
row "Queue Discipline"   "$QDISC"
row "Available CCs"      "$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || echo n/a)"
echo

if [[ "$CC" == "bbr" && "$QDISC" == "fq" ]]; then
  ok "BBR + fq active (optimal)"
elif [[ "$CC" == "cubic" && "$QDISC" == "fq_codel" ]]; then
  info "Fallback mode active (cubic + fq_codel)"
else
  bad "Unexpected config — check /etc/sysctl.d/99-vps-optimizer.conf"
fi
echo

# ---------------------------------------------------------------------------
# 2. Shared global buffer caps (affect both TCP and UDP)
# ---------------------------------------------------------------------------
echo "=== Global Buffer Caps (shared TCP + UDP) ==="
RMEM_MAX=$(sysctl -n net.core.rmem_max 2>/dev/null || echo 0)
WMEM_MAX=$(sysctl -n net.core.wmem_max 2>/dev/null || echo 0)
row "rmem_max"      "$RMEM_MAX ($(( RMEM_MAX / 1024 / 1024 )) MB)"
row "wmem_max"      "$WMEM_MAX ($(( WMEM_MAX / 1024 / 1024 )) MB)"
row "rmem_default"  "$(sysctl -n net.core.rmem_default 2>/dev/null || echo n/a)"
row "wmem_default"  "$(sysctl -n net.core.wmem_default 2>/dev/null || echo n/a)"
row "optmem_max"    "$(sysctl -n net.core.optmem_max 2>/dev/null || echo n/a)"

# Warn if UDP would be starved
if (( RMEM_MAX < 16777216 )); then
  bad "rmem_max < 16 MB — UDP/QUIC sockets may be capped"
else
  ok "rmem_max large enough for QUIC/Hysteria2 (≥ 16 MB)"
fi
echo

# ---------------------------------------------------------------------------
# 3. TCP buffer details
# ---------------------------------------------------------------------------
echo "=== TCP Buffer Sizes ==="
row "tcp_rmem"      "$(sysctl -n net.ipv4.tcp_rmem 2>/dev/null || echo n/a)"
row "tcp_wmem"      "$(sysctl -n net.ipv4.tcp_wmem 2>/dev/null || echo n/a)"
row "tcp_moderate_rcvbuf" "$(sysctl -n net.ipv4.tcp_moderate_rcvbuf 2>/dev/null || echo n/a)"
echo

# ---------------------------------------------------------------------------
# 4. UDP / QUIC / Hysteria2 (NEW in v2.2)
# ---------------------------------------------------------------------------
echo "=== UDP / QUIC / Hysteria2 ==="
UDP_MEM=$(sysctl -n net.ipv4.udp_mem 2>/dev/null || echo "n/a")
UDP_RMEM_MIN=$(sysctl -n net.ipv4.udp_rmem_min 2>/dev/null || echo "n/a")
UDP_WMEM_MIN=$(sysctl -n net.ipv4.udp_wmem_min 2>/dev/null || echo "n/a")
row "udp_mem (min/pressure/max pages)" "$UDP_MEM"
row "udp_rmem_min"   "$UDP_RMEM_MIN"
row "udp_wmem_min"   "$UDP_WMEM_MIN"

# Live kernel UDP memory usage (Linux ≥ 4.6 exposes this)
if [[ -f /proc/net/sockstat ]]; then
  UDP_LINE=$(grep '^UDP:' /proc/net/sockstat 2>/dev/null || echo "")
  if [[ -n "$UDP_LINE" ]]; then
    row "sockstat (live UDP)" "$UDP_LINE"
    echo "$UDP_LINE" | grep -q 'mem [0-9]\+' && \
      info "If 'mem' is growing close to the max page count, consider raising udp_mem."
  fi
fi
echo

# ---------------------------------------------------------------------------
# 5. Latency / Reconnection
# ---------------------------------------------------------------------------
echo "=== Latency / Reconnection ==="
row "keepalive_time"    "$(sysctl -n net.ipv4.tcp_keepalive_time 2>/dev/null || echo n/a)"
row "keepalive_intvl"   "$(sysctl -n net.ipv4.tcp_keepalive_intvl 2>/dev/null || echo n/a)"
row "keepalive_probes"  "$(sysctl -n net.ipv4.tcp_keepalive_probes 2>/dev/null || echo n/a)"
row "fin_timeout"       "$(sysctl -n net.ipv4.tcp_fin_timeout 2>/dev/null || echo n/a)"
row "tcp_fastopen"      "$(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null || echo n/a)"
row "mtu_probing"       "$(sysctl -n net.ipv4.tcp_mtu_probing 2>/dev/null || echo n/a)"
row "notsent_lowat"     "$(sysctl -n net.ipv4.tcp_notsent_lowat 2>/dev/null || echo n/a)"
echo

# ---------------------------------------------------------------------------
# 6. Backlog / Queues
# ---------------------------------------------------------------------------
echo "=== Backlog / Queues ==="
row "somaxconn"             "$(sysctl -n net.core.somaxconn 2>/dev/null || echo n/a)"
row "netdev_max_backlog"    "$(sysctl -n net.core.netdev_max_backlog 2>/dev/null || echo n/a)"
row "tcp_max_syn_backlog"   "$(sysctl -n net.ipv4.tcp_max_syn_backlog 2>/dev/null || echo n/a)"
row "tcp_max_tw_buckets"    "$(sysctl -n net.ipv4.tcp_max_tw_buckets 2>/dev/null || echo n/a)"
echo

# ---------------------------------------------------------------------------
# 7. Conntrack
# ---------------------------------------------------------------------------
echo "=== Conntrack (if loaded) ==="
if [[ -f /proc/sys/net/netfilter/nf_conntrack_max ]]; then
  CT_MAX=$(sysctl -n net.netfilter.nf_conntrack_max 2>/dev/null || echo n/a)
  CT_CNT=$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || echo 0)
  row "nf_conntrack_max" "$CT_MAX"
  row "current count"    "$CT_CNT"
  if [[ "$CT_MAX" =~ ^[0-9]+$ && "$CT_CNT" =~ ^[0-9]+$ ]]; then
    PCT=$(( CT_CNT * 100 / CT_MAX ))
    if (( PCT > 80 )); then
      bad "Conntrack usage ${PCT}% — consider raising net.netfilter.nf_conntrack_max"
    else
      ok "Conntrack usage ${PCT}%"
    fi
  fi
else
  info "nf_conntrack not loaded"
fi
echo

# ---------------------------------------------------------------------------
# 8. Live TCP sample (BBR state)
# ---------------------------------------------------------------------------
echo "=== Live TCP congestion sample ==="
if command -v ss >/dev/null 2>&1; then
  ss -ti 2>/dev/null | grep -m5 -E "bbr|cubic" || info "(no active TCP flows to inspect)"
else
  info "ss not available"
fi
echo

# ---------------------------------------------------------------------------
# 9. Live UDP sample (QUIC / Hysteria2 / WireGuard)
# ---------------------------------------------------------------------------
echo "=== Live UDP socket sample ==="
if command -v ss >/dev/null 2>&1; then
  # Show the first 5 UDP endpoints; useful to confirm Hysteria2/QUIC/WireGuard
  UDP_SAMPLE=$(ss -unp 2>/dev/null | head -n 6)
  if [[ -n "$UDP_SAMPLE" ]]; then
    echo "$UDP_SAMPLE"
  else
    info "(no UDP sockets active)"
  fi
else
  info "ss not available"
fi
echo

# ---------------------------------------------------------------------------
# 10. Optional: quick UDP loss probe to loopback (sanity only)
# ---------------------------------------------------------------------------
echo "=== Kernel UDP error counters ==="
if [[ -f /proc/net/snmp ]]; then
  # Extract UDP InErrors / RcvbufErrors / SndbufErrors for diagnostics
  awk '
    /^Udp:/ && !hdr { hdr=1; for(i=2;i<=NF;i++) h[i]=$i; next }
    /^Udp:/ && hdr {
      for(i=2;i<=NF;i++) v[i]=$i
      for(i in h) if (h[i] ~ /InErrors|RcvbufErrors|SndbufErrors|NoPorts/)
        printf "%-30s : %s\n", h[i], v[i]
      exit
    }
  ' /proc/net/snmp 2>/dev/null || info "UDP counters unavailable"
else
  info "/proc/net/snmp not available"
fi
echo

echo "═══════════════════════════════════════════════"
