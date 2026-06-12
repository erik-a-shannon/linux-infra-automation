#!/usr/bin/env bash
# =============================================================================
# ol_patch_rollback.sh
# Security Patch Rollback for Oracle Linux / RHEL 7, 8, and 9
#
# Author: Erik Shannon
# GitHub: github.com/erik-a-shannon
#
# Features:
#   - Auto-detects OL7 vs OL8/OL9 and selects yum/dnf accordingly
#   - Lists available rollback points (yum/dnf history transactions)
#   - Interactive selection: rollback by transaction ID or to a specific date
#   - Dry-run mode: preview what would be rolled back before committing
#   - Full audit logging to /var/log/patching/
#   - Detects if reboot is required post-rollback
#   - Confirmation prompt before any destructive action
#
# Requirements:
#   OL7:    sudo yum -y install yum-utils
#   OL8/9:  sudo dnf -y install dnf-utils
#
# IMPORTANT:
#   Patch rollback reverts package versions but does NOT undo configuration
#   changes, file modifications, or kernel boot entries automatically.
#   Always test in a non-production environment first.
# =============================================================================

# ── USER CONTROL ──────────────────────────────────────────────────────────────
DRY_RUN=false       # Set to true to preview rollback without applying
MAX_HISTORY=20      # Number of recent transactions to display
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

HOST="$(hostname -f 2>/dev/null || hostname)"
TS="$(date +'%Y%m%d_%H%M%S')"
LOG_DIR="/var/log/patching"
LOG_FILE="${LOG_DIR}/patch_rollback_${HOST}_${TS}.log"

mkdir -p "$LOG_DIR"

# ── Color helpers ─────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

# ── Logging helpers ───────────────────────────────────────────────────────────
log()  { echo "[$(date +'%F %T')] $*" | tee -a "$LOG_FILE"; }
info() { echo -e "${CYAN}[INFO]${RESET}  $*" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[WARN]${RESET}  $*" | tee -a "$LOG_FILE"; }
err()  { echo -e "${RED}[ERROR]${RESET} $*" | tee -a "$LOG_FILE"; }
ok()   { echo -e "${GREEN}[OK]${RESET}    $*" | tee -a "$LOG_FILE"; }

# ── Root check ────────────────────────────────────────────────────────────────
require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "ERROR: This script must be run as root." >&2
    exit 1
  fi
}

# ── OS version detection ──────────────────────────────────────────────────────
detect_major_version() {
  local ver=""
  [[ -f /etc/os-release ]] && ver="$(. /etc/os-release; echo "${VERSION_ID:-}")"
  [[ -z "$ver" && -f /etc/redhat-release ]] && \
    ver="$(grep -oE '[0-9]+' /etc/redhat-release | head -n1 || true)"
  echo "${ver%%.*}"
}

pkg_mgr_for_version() {
  [[ "$1" == "8" || "$1" == "9" ]] && echo "dnf" && return
  [[ "$1" == "7" ]]                && echo "yum" && return
  command -v dnf &>/dev/null       && echo "dnf" && return
  command -v yum &>/dev/null       && echo "yum" && return
  echo "unknown"
}

# ── Display transaction history ───────────────────────────────────────────────
show_history() {
  local pkgmgr="$1"
  echo ""
  echo -e "${BOLD}Recent Package Transactions (last $MAX_HISTORY):${RESET}"
  echo "──────────────────────────────────────────────────"
  "$pkgmgr" history list | head -n $(( MAX_HISTORY + 2 ))
  echo ""
}

# ── Show what a transaction changed ──────────────────────────────────────────
show_transaction_info() {
  local pkgmgr="$1" txn_id="$2"
  echo ""
  echo -e "${BOLD}Transaction #${txn_id} details:${RESET}"
  echo "──────────────────────────────────────────────────"
  "$pkgmgr" history info "$txn_id" 2>/dev/null || warn "Could not retrieve details for transaction $txn_id"
  echo ""
}

# ── Interactive menu ──────────────────────────────────────────────────────────
select_rollback_target() {
  local pkgmgr="$1"
  echo ""
  echo -e "${BOLD}╔══════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}║         Patch Rollback Options               ║${RESET}"
  echo -e "${BOLD}╠══════════════════════════════════════════════╣${RESET}"
  echo -e "${BOLD}║  1) Roll back a specific transaction ID      ║${RESET}"
  echo -e "${BOLD}║  2) Roll back the last N transactions        ║${RESET}"
  echo -e "${BOLD}║  3) View transaction history only (no action)║${RESET}"
  echo -e "${BOLD}╚══════════════════════════════════════════════╝${RESET}"
  echo ""

  local choice
  read -rp "Select an option [1-3]: " choice

  case "$choice" in
    1)
      show_history "$pkgmgr"
      local txn_id
      read -rp "Enter the Transaction ID to roll back: " txn_id
      if ! [[ "$txn_id" =~ ^[0-9]+$ ]]; then
        err "Invalid transaction ID. Must be a number."
        exit 1
      fi
      show_transaction_info "$pkgmgr" "$txn_id"
      confirm_and_rollback "$pkgmgr" "undo" "$txn_id"
      ;;
    2)
      show_history "$pkgmgr"
      local n_txns
      read -rp "How many recent transactions to roll back? [1-10]: " n_txns
      if ! [[ "$n_txns" =~ ^[0-9]+$ ]] || [[ "$n_txns" -lt 1 ]] || [[ "$n_txns" -gt 10 ]]; then
        err "Invalid number. Enter a value between 1 and 10."
        exit 1
      fi
      # Get the Nth oldest transaction ID from the list
      local last_txn_id
      last_txn_id=$("$pkgmgr" history list | awk 'NR>2 && /^[[:space:]]*[0-9]/{print $1}' | head -n "$n_txns" | tail -n 1)
      info "Will roll back to before transaction #${last_txn_id}"
      confirm_and_rollback "$pkgmgr" "rollback" "$last_txn_id"
      ;;
    3)
      show_history "$pkgmgr"
      info "History displayed. No changes made."
      exit 0
      ;;
    *)
      err "Invalid option. Exiting."
      exit 1
      ;;
  esac
}

# ── Confirm and execute rollback ──────────────────────────────────────────────
confirm_and_rollback() {
  local pkgmgr="$1" action="$2" txn_id="$3"

  echo ""
  warn "══════════════════════════════════════════════"
  warn "  You are about to ROLL BACK packages."
  warn "  Action     : $action"
  warn "  Transaction: #${txn_id}"
  warn "  Host       : $HOST"
  [[ "$DRY_RUN" == true ]] && warn "  Mode       : DRY-RUN (no changes will be made)"
  warn "══════════════════════════════════════════════"
  echo ""

  read -rp "Are you sure you want to proceed? Type YES to confirm: " confirm
  if [[ "$confirm" != "YES" ]]; then
    info "Rollback cancelled by user."
    exit 0
  fi

  log "Starting rollback: action=$action txn_id=$txn_id dry_run=$DRY_RUN"

  if [[ "$DRY_RUN" == true ]]; then
    info "DRY-RUN: Simulating rollback..."
    "$pkgmgr" history "$action" "$txn_id" --assumeno 2>&1 | tee -a "$LOG_FILE" || true
    info "DRY-RUN complete. No changes were made. Set DRY_RUN=false to apply."
  else
    info "Executing rollback..."
    "$pkgmgr" history "$action" "$txn_id" -y 2>&1 | tee -a "$LOG_FILE"
    ok "Rollback complete."

    # Reboot check
    log "Checking if reboot is required..."
    if command -v needs-restarting &>/dev/null; then
      if ! needs-restarting -r &>/dev/null; then
        warn "REBOOT REQUIRED — please reboot at the next maintenance window."
      else
        ok "No reboot required."
      fi
    else
      warn "needs-restarting not available — verify manually if kernel was changed."
    fi
  fi

  log "Rollback log saved to: $LOG_FILE"
}

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
  require_root

  local OS_VER PKG_MGR
  OS_VER="$(detect_major_version)"
  PKG_MGR="$(pkg_mgr_for_version "$OS_VER")"

  if [[ "$PKG_MGR" == "unknown" ]]; then
    err "Could not detect yum or dnf." && exit 1
  fi

  log "========================================================"
  log "  Host        : $HOST"
  log "  OS Version  : OL/RHEL $OS_VER"
  log "  Package Mgr : $PKG_MGR"
  log "  Dry Run     : $DRY_RUN"
  log "========================================================"

  select_rollback_target "$PKG_MGR"
}

main "$@"
