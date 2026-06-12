#!/usr/bin/env bash
# =============================================================================
# rotate_passwords.sh
# Bulk password rotation across multiple Oracle Linux / RHEL hosts
#
# Author: Erik Shannon
# GitHub: github.com/erik-a-shannon
#
# Features:
#   - Rotates a target user's password across an entire fleet simultaneously
#   - Generates a single secure 14-character random password applied uniformly
#   - Supports both key-based and password-based SSH in mixed environments
#   - Prompts for SSH credentials at runtime (no hardcoded secrets)
#   - Compatible with OL7, OL8, OL9 (uses chpasswd)
#   - Works with or without sshpass installed
#   - Color-coded output: green = success, red = failed, yellow = warning
#   - Displays results summary with per-host status
#
# Requirements:
#   - sshpass (for password-based SSH hosts)
#     OL/RHEL: sudo yum -y install sshpass  OR  sudo dnf -y install sshpass
#   - SSH client on the machine running this script
#   - The SSH user must have sudo rights on each target host
# =============================================================================

# ── CONFIGURATION — edit before use ──────────────────────────────────────────
TARGET_USER="YOUR_USERNAME_HERE"    # Account whose password will be rotated
SSH_USER="YOUR_SSH_USER_HERE"       # User used to connect to remote hosts
SSH_TIMEOUT=10                      # Connection timeout in seconds
# ─────────────────────────────────────────────────────────────────────────────

# ── HOST LIST ─────────────────────────────────────────────────────────────────
# Format: "hostname|auth_type|ssh_password"
#   auth_type = "key"      → uses your default SSH key
#   auth_type = "password" → uses sshpass with the provided ssh_password
# For key-based hosts, use "-" as the ssh_password placeholder
# ─────────────────────────────────────────────────────────────────────────────
HOSTS=(
  "server01.example.com|key|-"
  "server02.example.com|key|-"
  "server03.example.com|password|CHANGEME"
  "server04.example.com|password|CHANGEME"
  "server05.example.com|key|-"
  # Add additional hosts here following the same format
)

# =============================================================================

set -euo pipefail

# ── Color helpers ─────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[FAIL]${RESET}  $*"; }

# ── Preflight checks ──────────────────────────────────────────────────────────
preflight() {
  if [[ "$TARGET_USER" == "YOUR_USERNAME_HERE" ]]; then
    echo "ERROR: Set TARGET_USER in the CONFIGURATION section before running." >&2
    exit 1
  fi
  if [[ "$SSH_USER" == "YOUR_SSH_USER_HERE" ]]; then
    echo "ERROR: Set SSH_USER in the CONFIGURATION section before running." >&2
    exit 1
  fi
  if ! command -v ssh &>/dev/null; then
    echo "ERROR: ssh client not found." >&2
    exit 1
  fi
}

# ── Generate a secure random 14-character password ───────────────────────────
generate_password() {
  local charset='A-Za-z0-9!@#$%^&*()-_=+'
  tr -dc "$charset" </dev/urandom | head -c 14
  echo ""
}

# ── SSH wrapper — handles both key and password auth ─────────────────────────
remote_exec() {
  local host="$1" auth_type="$2" ssh_pass="$3"
  shift 3
  local cmd="$*"

  local ssh_opts="-o StrictHostKeyChecking=no -o ConnectTimeout=${SSH_TIMEOUT} -o BatchMode=no"

  if [[ "$auth_type" == "key" ]]; then
    ssh $ssh_opts "${SSH_USER}@${host}" "$cmd" 2>/dev/null
  elif [[ "$auth_type" == "password" ]]; then
    if command -v sshpass &>/dev/null; then
      sshpass -p "$ssh_pass" ssh $ssh_opts "${SSH_USER}@${host}" "$cmd" 2>/dev/null
    else
      warn "sshpass not found for $host — attempting key-based fallback"
      ssh $ssh_opts "${SSH_USER}@${host}" "$cmd" 2>/dev/null
    fi
  fi
}

# ── Rotate password on a single host ─────────────────────────────────────────
rotate_on_host() {
  local host="$1" auth_type="$2" ssh_pass="$3" new_pass="$4"

  remote_exec "$host" "$auth_type" "$ssh_pass" \
    "echo '${TARGET_USER}:${new_pass}' | sudo chpasswd" \
    && return 0 || return 1
}

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
  preflight

  echo ""
  echo -e "${BOLD}╔══════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}║        Bulk Password Rotation Tool           ║${RESET}"
  echo -e "${BOLD}║        Oracle Linux / RHEL Fleet             ║${RESET}"
  echo -e "${BOLD}╚══════════════════════════════════════════════╝${RESET}"
  echo ""

  info "Target user  : $TARGET_USER"
  info "SSH user     : $SSH_USER"
  info "Total hosts  : ${#HOSTS[@]}"
  echo ""

  # Generate the new password
  local NEW_PASS
  NEW_PASS="$(generate_password)"

  info "Generated new password (display only — not logged to disk):"
  echo -e "  ${BOLD}New password: ${NEW_PASS}${RESET}"
  echo ""

  # Confirm before proceeding
  read -rp "Proceed with rotation across all ${#HOSTS[@]} hosts? [y/N]: " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
  echo ""

  # Track results
  local pass_count=0 fail_count=0
  declare -A results

  for entry in "${HOSTS[@]}"; do
    IFS='|' read -r host auth_type ssh_pass <<< "$entry"

    echo -n "  Rotating on $host ... "
    if rotate_on_host "$host" "$auth_type" "$ssh_pass" "$NEW_PASS"; then
      success "done"
      results["$host"]="OK"
      ((pass_count++))
    else
      error "FAILED"
      results["$host"]="FAILED"
      ((fail_count++))
    fi
  done

  # Summary
  echo ""
  echo -e "${BOLD}══════════════════════════════════════════════${RESET}"
  echo -e "${BOLD}  Results Summary${RESET}"
  echo -e "${BOLD}══════════════════════════════════════════════${RESET}"
  echo -e "  ${GREEN}Succeeded: $pass_count${RESET}"
  echo -e "  ${RED}Failed:    $fail_count${RESET}"
  echo ""

  if [[ $fail_count -gt 0 ]]; then
    echo -e "${YELLOW}  Failed hosts:${RESET}"
    for host in "${!results[@]}"; do
      [[ "${results[$host]}" == "FAILED" ]] && echo "    - $host"
    done
    echo ""
  fi

  echo -e "${BOLD}  Remember to record the new password in your password manager.${RESET}"
  echo ""
}

main "$@"
