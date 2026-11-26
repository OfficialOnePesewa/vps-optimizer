#!/usr/bin/env bash
# VPS Optimizer - Full uninstall
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run as root." >&2; exit 1; }

echo "[1/4] Stopping and removing BadVPN services..."
for p in 7100 7200 7300; do
    systemctl stop    "badvpn@$p" 2>/dev/null || true
    systemctl disable "badvpn@$p" 2>/dev/null || true
done
rm -f /etc/systemd/system/badvpn@.service
rm -f /etc/systemd/system/multi-user.target.wants/badvpn@*.service
systemctl daemon-reload || true

echo "[2/4] Removing binaries and library..."
rm -f  /usr/local/bin/op-optimizer
rm -rf /usr/local/lib/vps-optimizer

echo "[3/4] Removing config and sysctl overrides..."
rm -f  /etc/sysctl.d/99-vps-optimizer.conf
rm -f  /etc/security/limits.d/99-vps-optimizer.conf
rm -rf /etc/vps-optimizer

echo "[4/4] Reloading sysctl..."
sysctl --system >/dev/null 2>&1 || true

echo "Uninstall complete."
