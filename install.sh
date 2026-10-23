#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  OP VPS Optimizer – Streaming Edition
#  High-resolution streaming + VoIP optimized
#  curl -fsSL https://raw.githubusercontent.com/OfficialOnePesewa/vps-optimizer/main/install.sh | sudo bash
#  Flags: --no-tune  --no-badvpn  --ports "7100 7200 7300"
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

REPO_RAW="${OP_REPO_RAW:-https://raw.githubusercontent.com/OfficialOnePesewa/vps-optimizer/main}"
DEST="/opt/op-optimizer"

FILES=(
  bin/op-optimizer
  bin/op-badvpn
  bin/op-keepalive
  config/sysctl-streaming.conf
  config/badvpn.env
  config/keepalive.env
  systemd/badvpn@.service
  systemd/op-optimizer-net.service
  systemd/op-keepalive.service
  systemd/op-keepalive.timer
  uninstall.sh
)

DO_TUNE=1
DO_BADVPN=1
PORTS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --no-tune)   DO_TUNE=0 ;;
    --no-badvpn) DO_BADVPN=0 ;;
    --ports)
      shift
      PORTS="${1:-}"
      ;;
  esac
  shift || true
done

# Colors
G='\033[1;32m'
R='\033[1;31m'
Y='\033[1;33m'
C='\033[1;36m'
B='\033[1;34m'
N='\033[0m'

ok()   { echo -e "\( {G}[ OK ] \){N} $*"; }
warn() { echo -e "\( {Y}[WARN] \){N} $*"; }
die()  { echo -e "\( {R}[FAIL] \){N} $*"; exit 1; }
info() { echo -e "\( {B}[ >> ] \){N} $*"; }

[ "$(id -u)" -eq 0 ] || die "Run as root: curl ... | sudo bash"

# ---------- Detect package manager ----------
PKG=""
if command -v apt-get >/dev/null 2>&1; then
  PKG="apt"
elif command -v dnf >/dev/null 2>&1; then
  PKG="dnf"
elif command -v yum >/dev/null 2>&1; then
  PKG="yum"
elif command -v apk >/dev/null 2>&1; then
  PKG="apk"
elif command -v pacman >/dev/null 2>&1; then
  PKG="pacman"
else
  die "Unsupported OS. Supported: Debian/Ubuntu, RHEL/CentOS/Alma/Rocky, Fedora, Alpine, Arch"
fi

install_base() {
  info "Installing base tools ($PKG)..."
  case "$PKG" in
    apt)
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -y -qq || warn "apt update had warnings"
      apt-get install -y -qq curl ca-certificates iproute2 procps ethtool irqbalance \
        iputils-ping util-linux coreutils sed gawk bc || die "Failed to install base packages"
      ;;
    dnf|yum)
      $PKG install -y -q curl ca-certificates iproute procps-ng ethtool irqbalance \
        iputils util-linux coreutils sed gawk bc || die "Failed to install base packages"
      ;;
    apk)
      apk add --no-cache curl ca-certificates iproute2 procps ethtool irqbalance \
        iputils util-linux coreutils sed gawk bc || die "Failed to install base packages"
      ;;
    pacman)
      pacman -Sy --noconfirm curl ca-certificates iproute2 procps-ng ethtool irqbalance \
        iputils util-linux coreutils sed gawk bc || die "Failed to install base packages"
      ;;
  esac
}

echo -e "${C}"
echo "  ██████╗ ██████╗     ██╗   ██╗██████╗ ███████╗"
echo " ██╔═══██╗██╔══██╗    ██║   ██║██╔══██╗██╔════╝"
echo " ██║   ██║██████╔╝    ██║   ██║██████╔╝███████╗"
echo " ██║   ██║██╔═══╝     ╚██╗ ██╔╝██╔═══╝ ╚════██║"
echo " ╚██████╔╝██║          ╚████╔╝ ██║     ███████║"
echo "  ╚═════╝ ╚═╝           ╚═══╝  ╚═╝     ╚══════╝"
echo -e "${N}          Streaming Edition  •  by @OfficialOnePesewa"
echo

install_base
ok "Base packages ready"

# ---------- Download files ----------
SRC_DIR=""
if [ -n "\( {BASH_SOURCE[0]:-}" ] && [ -f " \){BASH_SOURCE[0]}" ]; then
  SRC_DIR="\( (cd " \)(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

info "Installing files to $DEST ..."
for f in "${FILES[@]}"; do
  mkdir -p "\( DEST/ \)(dirname "$f")"
  if [ -n "$SRC_DIR" ] && [ -f "$SRC_DIR/$f" ]; then
    cp -f "$SRC_DIR/$f" "$DEST/$f"
  else
    curl -fsSL "$REPO_RAW/$f" -o "$DEST/$f" || die "Failed to download $f"
  fi
done

chmod +x "$DEST"/bin/* "$DEST/uninstall.sh"
ln -sf "$DEST/bin/op-optimizer"  /usr/local/bin/op-optimizer
ln -sf "$DEST/bin/op-badvpn"     /usr/local/bin/op-badvpn
ln -sf "$DEST/bin/op-keepalive"  /usr/local/bin/op-keepalive
ok "Binaries linked"

# ---------- Apply ----------
if [ "$DO_TUNE" -eq 1 ]; then
  info "Applying streaming optimizations..."
  /usr/local/bin/op-optimizer apply
fi

if [ "$DO_BADVPN" -eq 1 ]; then
  info "Installing dual-bind BadVPN (0.0.0.0 + 127.0.0.1)..."
  if [ -n "$PORTS" ]; then
    /usr/local/bin/op-badvpn install $PORTS
  else
    /usr/local/bin/op-badvpn install
  fi
fi

echo
/usr/local/bin/op-optimizer status || true
echo
ok "Installation complete!"
echo -e "  Commands:  \( {C}op-optimizer \){N}  |  \( {C}op-badvpn status \){N}  |  \( {C}op-badvpn restart \){N}"
warn "Reboot once for full effect →  reboot"
