[READ_ME.md](https://github.com/user-attachments/files/29619357/READ_ME.md)
# linux-infra-automation

Production-tested Bash automation scripts for Oracle Linux and RHEL enterprise environments. Built and iterated across OL7, OL8, and OL9 fleets supporting large-scale infrastructure operations including security patching, credential management, rollback procedures, and system administration workflows.

---

## Scripts

### 🔐 patching/ol_patch_security_only_enhanced.sh

**Security-only patch automation with interactive date filtering**

Automates the application of security advisories on Oracle Linux and RHEL systems. Designed for enterprise environments where change control requires precise control over which patches are applied and when.

**Key features:**
- Auto-detects OL7 vs OL8/OL9 and selects `yum` or `dnf` accordingly
- Interactive menu to apply patches by single date, date range, or all available
- Accepts dual date formats: `YYYY-MM-DD` and `MM/DD/YYYY`
- Filters advisories by issue date before applying — no unintended patches
- Full audit log written to `/var/log/patching/` for change record compliance
- Post-patch reboot detection via `needs-restarting`
- Dry-run mode: set `APPLY_PATCHES=false` to check without installing

**Requirements:**
```bash
# OL7
sudo yum -y install yum-plugin-security yum-utils

# OL8 / OL9
sudo dnf -y install dnf-utils
```

**Usage:**
```bash
sudo chmod +x ol_patch_security_only_enhanced.sh
sudo ./ol_patch_security_only_enhanced.sh
```

**Example interaction:**
```
╔══════════════════════════════════════════╗
║   Security Patch Date Filter             ║
╠══════════════════════════════════════════╣
║  1) Apply all available security patches ║
║  2) Apply patches from a specific date   ║
║  3) Apply patches within a date range    ║
╚══════════════════════════════════════════╝

Select an option [1-3]: 3
Start date (YYYY-MM-DD or MM/DD/YYYY): 2025-01-01
End date   (YYYY-MM-DD or MM/DD/YYYY): 2025-03-31
```

---

### ↩️ rollback/ol_patch_rollback.sh

**Security patch rollback using yum/dnf transaction history**

Reverts security patches applied by `ol_patch_security_only_enhanced.sh` or any `yum`/`dnf` transaction. Uses the native package manager transaction log to precisely undo changes — roll back a specific transaction or the last N transactions.

**Key features:**
- Displays full transaction history so you can identify exactly what to revert
- Roll back a specific transaction ID or the last N transactions
- Dry-run mode: preview what would be rolled back before committing
- Requires typed `YES` confirmation before any destructive action
- Post-rollback reboot detection
- Full audit log written to `/var/log/patching/`

**Requirements:**
```bash
# OL7
sudo yum -y install yum-utils

# OL8 / OL9
sudo dnf -y install dnf-utils
```

**Usage:**
```bash
sudo chmod +x ol_patch_rollback.sh
sudo ./ol_patch_rollback.sh
```

**Example interaction:**
```
╔══════════════════════════════════════════════╗
║         Patch Rollback Options               ║
╠══════════════════════════════════════════════╣
║  1) Roll back a specific transaction ID      ║
║  2) Roll back the last N transactions        ║
║  3) View transaction history only (no action)║
╚══════════════════════════════════════════════╝

Select an option [1-3]: 1
Enter the Transaction ID to roll back: 42
```

> **Note:** Set `DRY_RUN=true` at the top of the script to preview changes without applying them.

---

### 🔑 credential-management/rotate_passwords.sh

**Bulk password rotation across a Linux server fleet**

Rotates a target user account's password across multiple remote hosts simultaneously. Built for environments where a shared service account password must be rotated uniformly across dozens of servers.

**Key features:**
- Generates a single secure 14-character random password applied across all hosts
- Supports mixed SSH environments: key-based and password-based auth in the same run
- Runtime credential prompting — no secrets hardcoded in the script
- Compatible with OL7, OL8, OL9 using `chpasswd`
- Works with or without `sshpass` installed (falls back gracefully)
- Color-coded per-host output and final pass/fail summary
- Confirmation prompt before execution to prevent accidental runs

**Requirements:**
```bash
# Required for password-based SSH hosts
sudo yum -y install sshpass   # OL7
sudo dnf -y install sshpass   # OL8/OL9
```

**Setup:**
1. Edit the `CONFIGURATION` section at the top of the script
2. Populate the `HOSTS` array with your server list
3. Run as a user with sudo access on the target hosts

```bash
sudo chmod +x rotate_passwords.sh
./rotate_passwords.sh
```

**Host entry format:**
```bash
HOSTS=(
  "server01.example.com|key|-"           # Key-based auth
  "server02.example.com|password|PASS"   # Password-based auth
)
```

---

### 🔄 rollback/rotate_passwords_rollback.sh

**Password rotation rollback across a Linux server fleet**

Restores a previous password or sets a recovery password across the fleet when a rotation needs to be reversed. Handles two real-world scenarios since Linux does not store passwords in a recoverable format.

**Key features:**
- **Scenario A** — You have the previous password: re-applies it uniformly across all hosts
- **Scenario B** — Previous password is unknown: sets a new recovery password you define
- Runtime password entry — nothing stored on disk
- Confirmation prompt before executing across fleet
- Color-coded per-host output with pass/fail summary
- Flags failed hosts with manual remediation instructions
- Compatible with OL7, OL8, OL9

**Important note:**
> Linux stores only a one-way password hash in `/etc/shadow` — the original value cannot be retrieved cryptographically. This script restores **access** to the account, not the original credential value. Always record passwords in a secure password manager immediately after rotation.

**Usage:**
```bash
sudo chmod +x rotate_passwords_rollback.sh
./rotate_passwords_rollback.sh
```

**Example interaction:**
```
Select rollback scenario:
  1) I have the previous password — restore it across the fleet
  2) I do NOT have the previous password — set a new recovery password

Select [1-2]: 1
  Previous password: ********
```

---

### 🗑️ user-management/remove_users.sh

**Local interactive user account removal with audit logging**

Runs directly on each target server (not over SSH) to remove one or more local user accounts interactively. Built to replace an inconsistent manual `userdel` process with a standardized, repeatable workflow across the fleet.

**Key features:**
- Interactively prompts for one or more usernames to remove
- Optional removal of home directories alongside the account
- Dry-run mode to preview which accounts would be removed before taking action
- Requires explicit confirmation before executing any removal
- Per-run timestamped log written to `/var/log/user_removal_<timestamp>.log`
- Cumulative CSV audit report appended at `/var/log/user_removal_report.csv` for tracking removals over time across runs
- Reports success, skip, and not-found cases clearly per account

**Usage:**
```bash
sudo chmod +x remove_users.sh
sudo ./remove_users.sh
```

> **Note:** Deploy to `/usr/local/sbin/remove_users.sh` on each server. If the script was transferred from Windows, strip CRLF line endings before running: `sed -i 's/\r$//' /usr/local/sbin/remove_users.sh`

---

### 👥 user-management/remove_group_members.sh

**Bulk removal of users from specific groups (accounts remain intact)**

Removes users from one or more groups without deleting the underlying user accounts — useful for access reviews and privilege cleanup where the account itself should remain active.

**Key features:**
- Removes group membership via `gpasswd -d`, leaving the user account untouched
- Accepts pasted `groupname username` pairs for fast bulk input
- Per-run timestamped log written to `/var/log/group_removal_<timestamp>.log`
- Cumulative CSV audit report appended at `/var/log/group_removal_report.csv`
- Reports success, skip, and not-found cases per group/user pair

**Usage:**
```bash
sudo chmod +x remove_group_members.sh
sudo ./remove_group_members.sh
```

---

### 🚀 user-management/deploy_remove_users.sh

**Fleet-wide deployment helper for remove_users.sh and remove_group_members.sh**

Pushes the local user-management scripts out to multiple servers so they're staged and ready to run locally on each host.

**Key features:**
- Deploys scripts via `scp` followed by `sudo mv` / `chown` / `chmod` on the target host
- Accepts a server list inline or from a file
- Standardizes script placement at `/usr/local/sbin/` across the fleet

**Usage:**
```bash
sudo chmod +x deploy_remove_users.sh
./deploy_remove_users.sh
```

---

## Repository Structure

```
linux-infra-automation/
├── README.md
├── patching/
│   └── ol_patch_security_only_enhanced.sh
├── rollback/
│   ├── ol_patch_rollback.sh
│   └── rotate_passwords_rollback.sh
├── credential-management/
│   └── rotate_passwords.sh
└── user-management/
    ├── remove_users.sh
    ├── remove_group_members.sh
    └── deploy_remove_users.sh
```

---

## Environment Compatibility

| Script | OL7 | OL8 | OL9 | RHEL 7 | RHEL 8 | RHEL 9 |
|---|---|---|---|---|---|---|
| ol_patch_security_only_enhanced.sh | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| ol_patch_rollback.sh | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| rotate_passwords.sh | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| rotate_passwords_rollback.sh | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| remove_users.sh | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| remove_group_members.sh | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| deploy_remove_users.sh | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

---

## Security Notes

- No credentials are hardcoded in any script — all sensitive values are prompted at runtime or use placeholder variables
- `rotate_passwords.sh` never writes generated passwords to disk — displayed on screen only
- SSH connections use `StrictHostKeyChecking=no` for fleet automation — recommended for internal trusted networks only
- All patching and rollback activity is logged to `/var/log/patching/` for audit trail compliance
- User and group removal activity is logged per-run to `/var/log/user_removal_<timestamp>.log` and `/var/log/group_removal_<timestamp>.log`, with cumulative CSV reports at `/var/log/user_removal_report.csv` and `/var/log/group_removal_report.csv`
- Always run rollback scripts in dry-run mode first when available to preview changes before applying

---

## Recommended Workflow

```
Patch    →  ol_patch_security_only_enhanced.sh
Rollback →  ol_patch_rollback.sh

Rotate   →  rotate_passwords.sh
Rollback →  rotate_passwords_rollback.sh

Deploy      →  deploy_remove_users.sh
Remove user →  remove_users.sh
Remove group membership →  remove_group_members.sh
```

---

## Author

**Erik Shannon** — Senior Systems Engineer  
📧 shannonerik7@gmail.com  
🔗 [linkedin.com/in/erik-shannon1b51aa154](https://www.linkedin.com/in/erik-shannon1b51aa154)  
🐙 [github.com/erik-a-shannon](https://github.com/erik-a-shannon)

---

## License

MIT License — free to use, modify, and distribute with attribution.
