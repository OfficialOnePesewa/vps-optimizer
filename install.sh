#!/usr/bin/env bash
# OP VPS Optimizer installer
# curl -fsSL https://raw.githubusercontent.com/OfficialOnePesewa/vps-optimizer/main/install.sh | sudo bash
# Flags: --no-tune  --no-badvpn  --ports "7100 7200 7300"
set -euo pipefail

REPO_RAW="${OP_REPO_RAW:-https://raw.githubusercontent.com/OfficialOnePesewa/vps-optimizer/main}"
DEST="/opt/op-optimizer"
FILES=(bin/op-optimizer bin/op-badvpn config/sysctl-lowlatency.conf config/badvpn.env
       systemd/badvpn@.service systemd/op-optimizer-net.service uninstall.sh)

DO_TUNE=1; DO_BADVPN=1; PORTS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --no-tune) DO_TUNE=0 ;; --no-badvpn) DO_BADVPN=0 ;;
    --ports) shift; PORTS="${1:-}" ;;
  esac; shift
done

G='\033[1;32m'; R='\033[1;31m'; Y='\033[1;33m'; N='\033[0m'
ok(){ echo -e "${G}[ OK ]${N} $*"; }
warn(){ echo -e "${Y}[WARN]${N} $*"; }
die(){ echo -e "${R}[FAIL]${N} $*"; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run as root: ... | sudo bash"
command -v apt-get >/dev/null 2>&1 || die "Only Debian/Ubuntu supported."

export DEBIAN_FRONTEND=noninteractive
echo "==> Installing base packages"
apt-get update -y >/dev/null 2>&1 || warn "apt update had errors"
apt-get install -y curl ca-certificates iproute2 procps ethtool irqbalance >/dev/null 2>&1 \
  || die "Base packages failed"

SRC_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

echo "==> Fetching files"
for f in "${FILES[@]}"; do
  mkdir -p "$DEST/$(dirname "$f")"
  if [ -n "$SRC_DIR" ] && [ -f "$SRC_DIR/$f" ]; then cp -f "$SRC_DIR/$f" "$DEST/$f"
  else curl -fsSL "$REPO_RAW/$f" -o "$DEST/$f" || die "Download failed: $f"; fi
done
chmod +x "$DEST"/bin/* "$DEST/uninstall.sh"
ln -sf "$DEST/bin/op-optimizer" /usr/local/bin/op-optimizer
ln -sf "$DEST/bin/op-badvpn"    /usr/local/bin/op-badvpn
ok "Installed to $DEST"

[ "$DO_TUNE" -eq 1 ]   && /usr/local/bin/op-optimizer apply
[ "$DO_BADVPN" -eq 1 ] && /usr/local/bin/op-badvpn install $PORTS
echo; /usr/local/bin/op-optimizer status || true; echo
ok "Done. Commands: op-optimizer | op-badvpn status"
warn "Reboot once to fully activate:  reboot"
