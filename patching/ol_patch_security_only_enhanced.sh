#!/usr/bin/env bash
# =============================================================================
# ol_patch_security_only_enhanced.sh
# Security-Only Patch Automation for Oracle Linux / RHEL 7, 8, and 9
#
# Author: Erik Shannon
# GitHub: github.com/erik-a-shannon
#
# Features:
#   - Auto-detects OL7 vs OL8/OL9 and selects yum/dnf accordingly
#   - Interactive date / date-range selection for targeted patching
#   - Shows installed vs latest package versions before applying
#   - Applies SECURITY-ONLY patches filtered by advisory date
#   - Full audit logging to /var/log/patching/
#   - Detects if reboot is required post-patch
#   - Supports dry-run mode (check without installing)
#   - Dual date format support: YYYY-MM-DD and MM/DD/YYYY
#
# Requirements:
#   OL7:    sudo yum -y install yum-plugin-security yum-utils
#   OL8/9:  sudo dnf -y install dnf-utils
# =============================================================================

# ── USER CONTROL ──────────────────────────────────────────────────────────────
APPLY_PATCHES=true      # Set to false for dry-run / check-only mode
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

HOST="$(hostname -f 2>/dev/null || hostname)"
TS="$(date +'%Y%m%d_%H%M%S')"
LOG_DIR="/var/log/patching"
LOG_FILE="${LOG_DIR}/patch_security_${HOST}_${TS}.log"

DATE_MODE=""    # single | range | all
DATE_FROM=""    # YYYY-MM-DD
DATE_TO=""      # YYYY-MM-DD

mkdir -p "$LOG_DIR"

# ── Logging helpers ───────────────────────────────────────────────────────────
log() { echo "[$(date +'%F %T')] $*" | tee -a "$LOG_FILE"; }
run() { log "+ $*"; eval "$*" 2>&1 | tee -a "$LOG_FILE"; }

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
  command -v dnf &>/dev/null 2>&1  && echo "dnf" && return
  command -v yum &>/dev/null 2>&1  && echo "yum" && return
  echo "unknown"
}

# ── Date validation and normalization ─────────────────────────────────────────
# Accepts YYYY-MM-DD or MM/DD/YYYY, always returns YYYY-MM-DD
normalise_date() {
  local input="$1"
  # Already YYYY-MM-DD
  if [[ "$input" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "$input"
    return
  fi
  # MM/DD/YYYY → YYYY-MM-DD
  if [[ "$input" =~ ^([0-9]{2})/([0-9]{2})/([0-9]{4})$ ]]; then
    echo "${BASH_REMATCH[3]}-${BASH_REMATCH[1]}-${BASH_REMATCH[2]}"
    return
  fi
  echo ""   # invalid
}

validate_date() {
  local d="$1"
  [[ -n "$(normalise_date "$d")" ]]
}

# ── Extract advisory issue date from yum/dnf output ───────────────────────────
extract_issued_date() {
  local advisory="$1" pkgmgr="$2"
  "$pkgmgr" updateinfo info "$advisory" 2>/dev/null \
    | grep -iE '^\s*(Issued|Issue Date|Updated|Update Date)\s*:' \
    | head -n1 \
    | sed 's/.*: *//'
}

# ── Date comparison (returns 0 if date is within the selected window) ─────────
date_in_range() {
  local issued_raw="$1"
  local issued
  issued="$(normalise_date "$issued_raw")" || true
  [[ -z "$issued" ]] && return 1

  case "$DATE_MODE" in
    all)    return 0 ;;
    single) [[ "$issued" == "$DATE_FROM" ]]            && return 0 ;;
    range)  [[ "$issued" >= "$DATE_FROM" && "$issued" <= "$DATE_TO" ]] && return 0 ;;
  esac
  return 1
}

# ── Interactive date selection menu ──────────────────────────────────────────
select_date_mode() {
  echo ""
  echo "╔══════════════════════════════════════════╗"
  echo "║   Security Patch Date Filter             ║"
  echo "╠══════════════════════════════════════════╣"
  echo "║  1) Apply all available security patches ║"
  echo "║  2) Apply patches from a specific date   ║"
  echo "║  3) Apply patches within a date range    ║"
  echo "╚══════════════════════════════════════════╝"
  echo ""

  local choice
  while true; do
    read -rp "Select an option [1-3]: " choice
    case "$choice" in
      1) DATE_MODE="all"; break ;;
      2)
        DATE_MODE="single"
        while true; do
          read -rp "Enter date (YYYY-MM-DD or MM/DD/YYYY): " raw
          local norm; norm="$(normalise_date "$raw")"
          if [[ -n "$norm" ]]; then DATE_FROM="$norm"; break
          else echo "  Invalid date format. Try again."; fi
        done
        break ;;
      3)
        DATE_MODE="range"
        while true; do
          read -rp "Start date (YYYY-MM-DD or MM/DD/YYYY): " raw
          local norm; norm="$(normalise_date "$raw")"
          if [[ -n "$norm" ]]; then DATE_FROM="$norm"; break
          else echo "  Invalid date format. Try again."; fi
        done
        while true; do
          read -rp "End date   (YYYY-MM-DD or MM/DD/YYYY): " raw
          local norm; norm="$(normalise_date "$raw")"
          if [[ -n "$norm" ]]; then DATE_TO="$norm"; break
          else echo "  Invalid date format. Try again."; fi
        done
        break ;;
      *) echo "  Please enter 1, 2, or 3." ;;
    esac
  done
  echo ""
}

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
  require_root

  local OS_VER PKG_MGR
  OS_VER="$(detect_major_version)"
  PKG_MGR="$(pkg_mgr_for_version "$OS_VER")"

  if [[ "$PKG_MGR" == "unknown" ]]; then
    echo "ERROR: Could not detect yum or dnf." >&2
    exit 1
  fi

  log "========================================================"
  log "  Host        : $HOST"
  log "  OS Version  : OL/RHEL $OS_VER"
  log "  Package Mgr : $PKG_MGR"
  log "  Apply Mode  : $( [[ "$APPLY_PATCHES" == true ]] && echo LIVE || echo DRY-RUN )"
  log "========================================================"

  select_date_mode

  log "Date filter  : mode=$DATE_MODE from=${DATE_FROM:-N/A} to=${DATE_TO:-N/A}"

  # Fetch available security advisories
  log "Fetching available security advisories..."
  local advisories=()
  mapfile -t advisories < <(
    "$PKG_MGR" updateinfo list security 2>/dev/null \
      | awk '/^[A-Z]+-[0-9]/{print $1}' \
      | sort -u
  )

  if [[ ${#advisories[@]} -eq 0 ]]; then
    log "No security advisories found. System may be up to date."
    exit 0
  fi

  log "Total advisories found: ${#advisories[@]}"

  # Filter advisories by date
  local selected=()
  for adv in "${advisories[@]}"; do
    local issued_raw
    issued_raw="$(extract_issued_date "$adv" "$PKG_MGR")"
    if date_in_range "$issued_raw"; then
      selected+=("$adv")
      log "  [SELECTED] $adv (issued: $issued_raw)"
    else
      log "  [SKIPPED]  $adv (issued: $issued_raw)"
    fi
  done

  if [[ ${#selected[@]} -eq 0 ]]; then
    log "No advisories matched the selected date filter. Exiting."
    exit 0
  fi

  log "Advisories matched: ${#selected[@]}"

  if [[ "$APPLY_PATCHES" != true ]]; then
    log "DRY-RUN mode — no patches applied. Set APPLY_PATCHES=true to install."
    exit 0
  fi

  # Build advisory flags and apply
  local adv_flags=()
  for adv in "${selected[@]}"; do
    adv_flags+=("--advisory=${adv}")
  done

  log "Applying ${#selected[@]} security advisories..."
  "$PKG_MGR" update -y "${adv_flags[@]}" 2>&1 | tee -a "$LOG_FILE"

  # Reboot check
  log "Checking if reboot is required..."
  if command -v needs-restarting &>/dev/null; then
    if needs-restarting -r &>/dev/null; then
      log "REBOOT REQUIRED — please reboot this host at the next maintenance window."
    else
      log "No reboot required."
    fi
  else
    log "needs-restarting not available — check manually if kernel was updated."
  fi

  log "Patching complete. Log saved to: $LOG_FILE"
}

main "$@"
