#!/usr/bin/env bash
# Quick verification of VPS Optimizer settings
set -uo pipefail

echo "=== TCP Stack Status ==="
printf "%-30s : %s\n" "Congestion Control" "$(sysctl -n net.ipv4.tcp_congestion_control)"
printf "%-30s : %s\n" "Queue Discipline"   "$(sysctl -n net.core.default_qdisc)"
printf "%-30s : %s\n" "Available CCs"      "$(sysctl -n net.ipv4.tcp_available_congestion_control)"

echo
echo "=== Buffer Sizes ==="
printf "%-30s : %s\n" "tcp_rmem"  "$(sysctl -n net.ipv4.tcp_rmem)"
printf "%-30s : %s\n" "tcp_wmem"  "$(sysctl -n net.ipv4.tcp_wmem)"
printf "%-30s : %s\n" "rmem_max"  "$(sysctl -n net.core.rmem_max)"
printf "%-30s : %s\n" "wmem_max"  "$(sysctl -n net.core.wmem_max)"

echo
echo "=== Latency / Reconnection ==="
printf "%-30s : %s\n" "keepalive_time"  "$(sysctl -n net.ipv4.tcp_keepalive_time)"
printf "%-30s : %s\n" "fin_timeout"     "$(sysctl -n net.ipv4.tcp_fin_timeout)"
printf "%-30s : %s\n" "tcp_fastopen"    "$(sysctl -n net.ipv4.tcp_fastopen)"
printf "%-30s : %s\n" "mtu_probing"     "$(sysctl -n net.ipv4.tcp_mtu_probing)"

echo
echo "=== Live BBR usage (sample) ==="
ss -ti 2>/dev/null | grep -m5 -E "bbr|cubic" || echo "(no active TCP flows to inspect)"
