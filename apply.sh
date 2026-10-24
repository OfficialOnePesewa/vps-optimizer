#!/usr/bin/env bash
# ==============================================================================
# Script Name: apply.sh — One-liner installer/updater for VPS Optimizer
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/OfficialOnePesewa/vps-optimizer/main/apply.sh | sudo bash
#   curl -fsSL .../apply.sh | sudo bash -s -- install
#   curl -fsSL .../apply.sh | sudo bash -s -- verify
#   curl -fsSL .../apply.sh | sudo bash -s -- hardening
#   curl -fsSL .../apply.sh | sudo bash -s -- uninstall
#   curl -fsSL .../apply.sh | sudo bash -s -- all
# ==============================================================================

# ---- CRLF self-heal (works even when piped) --------------------------------
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
# Config
# ----------------------------
REPO="OfficialOnePesewa/vps-optimizer"
BRANCH="main"
BASE_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
WORKDIR="/tmp/vps-optimizer-$$"

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
# Action (default = install)
# ----------------------------
ACTION="${1:-install}"

cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

mkdir -p "$WORKDIR"

# ----------------------------
# Fetch a script, strip CRLF, verify
# ----------------------------
fetch_script() {
  local name="$1"
  local dest="${WORKDIR}/${name}"

  log "Fetching ${name} ..."
  if ! curl -fsSL "${BASE_URL}/${name}" -o "$dest"; then
    err "Failed to download ${name}"
    return 1
  fi

  # Strip CRLF (idempotent — safe if already LF)
  sed -i 's/\r$//' "$dest"

  # Quick sanity check
  if ! head -n1 "$dest" | grep -q '^#!.*bash'; then
    warn "${name} does not start with a bash shebang — check the repo."
  fi

  chmod +x "$dest"
  return 0
}

# ----------------------------
# Dispatch
# ----------------------------
run_install() {
  fetch_script install.sh || exit 1
  log "Running install.sh ..."
  bash "${WORKDIR}/install.sh"
}

run_verify() {
  fetch_script verify.sh || exit 1
  log "Running verify.sh ..."
  bash "${WORKDIR}/verify.sh"
}

run_hardening() {
  fetch_script hardening.sh || exit 1
  log "Running hardening.sh ..."
  bash "${WORKDIR}/hardening.sh"
}

run_uninstall() {
  fetch_script uninstall.sh || exit 1
  log "Running uninstall.sh ..."
  bash "${WORKDIR}/uninstall.sh"
}

run_all() {
  run_install
  echo
  run_verify
  echo
  warn "To also apply security hardening, run:"
  warn "  curl -fsSL ${BASE_URL}/apply.sh | sudo bash -s -- hardening"
}

# ----------------------------
# Main
# ----------------------------
case "$ACTION" in
  install)    run_install ;;
  verify)     run_verify ;;
  hardening)  run_hardening ;;
  uninstall)  run_uninstall ;;
  all)        run_all ;;
  *)
    err "Unknown action: $ACTION"
    echo "Usage: $0 [install|verify|hardening|uninstall|all]"
    exit 1
    ;;
esac

echo
log "apply.sh finished — action: $ACTION"
