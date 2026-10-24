#!/usr/bin/env bash
# ==============================================================================
# VPS Optimizer — Verification
# Notes: Safe against CRLF line endings; self-heals if piped via curl.
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

echo "═══════════════════════════════════════════════"
echo " VPS Optimizer — Verification"
echo "═══════════════════════════════════════════════"
echo

echo "=== TCP Stack Status ==="
CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
QDISC=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "unknown")
printf '%-30s : %s\n' "Congestion Control" "$CC"
printf '%-30s : %s\n' "Queue Discipline"   "$QDISC"
printf '%-30s : %s\n' "Available CCs"      "$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || echo n/a)"
echo

if [[ "$CC" == "bbr" && "$QDISC" == "fq" ]]; then
  ok "BBR + fq active (optimal)"
elif [[ "$CC" == "cubic" && "$QDISC" == "fq_codel" ]]; then
  info "Fallback mode active (cubic + fq_codel)"
else
  bad "Unexpected config — check /etc/sysctl.d/99-vps-optimizer.conf"
fi
echo

echo "=== Buffer Sizes ==="
printf '%-30s : %s\n' "tcp_rmem"      "$(sysctl -n net.ipv4.tcp_rmem 2>/dev/null || echo n/a)"
printf '%-30s : %s\n' "tcp_wmem"      "$(sysctl -n net.ipv4.tcp_wmem 2>/dev/null || echo n/a)"
printf '%-30s : %s\n' "rmem_max"      "$(sysctl -n net.core.rmem_max 2>/dev/null || echo n/a)"
printf '%-30s : %s\n' "wmem_max"      "$(sysctl -n net.core.wmem_max 2>/dev/null || echo n/a)"
printf '%-30s : %s\n' "optmem_max"    "$(sysctl -n net.core.optmem_max 2>/dev/null || echo n/a)"
echo

echo "=== Latency / Reconnection ==="
printf '%-30s : %s\n' "keepalive_time"    "$(sysctl -n net.ipv4.tcp_keepalive_time 2>/dev/null || echo n/a)"
printf '%-30s : %s\n' "keepalive_intvl"   "$(sysctl -n net.ipv4.tcp_keepalive_intvl 2>/dev/null || echo n/a)"
printf '%-30s : %s\n' "keepalive_probes"  "$(sysctl -n net.ipv4.tcp_keepalive_probes 2>/dev/null || echo n/a)"
printf '%-30s : %s\n' "fin_timeout"       "$(sysctl -n net.ipv4.tcp_fin_timeout 2>/dev/null || echo n/a)"
printf '%-30s : %s\n' "tcp_fastopen"      "$(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null || echo n/a)"
printf '%-30s : %s\n' "mtu_probing"       "$(sysctl -n net.ipv4.tcp_mtu_probing 2>/dev/null || echo n/a)"
printf '%-30s : %s\n' "notsent_lowat"     "$(sysctl -n net.ipv4.tcp_notsent_lowat 2>/dev/null || echo n/a)"
echo

echo "=== Backlog / Queues ==="
printf '%-30s : %s\n' "somaxconn"             "$(sysctl -n net.core.somaxconn 2>/dev/null || echo n/a)"
printf '%-30s : %s\n' "netdev_max_backlog"    "$(sysctl -n net.core.netdev_max_backlog 2>/dev/null || echo n/a)"
printf '%-30s : %s\n' "tcp_max_syn_backlog"   "$(sysctl -n net.ipv4.tcp_max_syn_backlog 2>/dev/null || echo n/a)"
echo

echo "=== Conntrack (if loaded) ==="
if [[ -f /proc/sys/net/netfilter/nf_conntrack_max ]]; then
  printf '%-30s : %s\n' "nf_conntrack_max" "$(sysctl -n net.netfilter.nf_conntrack_max 2>/dev/null || echo n/a)"
  printf '%-30s : %s\n' "current count"    "$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || echo 0)"
else
  info "nf_conntrack not loaded"
fi
echo

echo "=== Live TCP congestion sample ==="
if command -v ss >/dev/null 2>&1; then
  ss -ti 2>/dev/null | grep -m5 -E "bbr|cubic" || info "(no active TCP flows to inspect)"
else
  info "ss not available"
fi

echo
echo "═══════════════════════════════════════════════"
