#!/usr/bin/env bash
[ "$(id -u)" -eq 0 ] || { echo "Run as root"; exit 1; }
/usr/local/bin/op-badvpn remove 2>/dev/null
/usr/local/bin/op-optimizer restore 2>/dev/null
rm -f /usr/local/bin/op-optimizer /usr/local/bin/op-badvpn
rm -rf /opt/op-optimizer /etc/op-optimizer
echo "OP VPS Optimizer fully removed. Reboot recommended."
