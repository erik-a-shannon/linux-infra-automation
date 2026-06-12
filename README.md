[README (1).md](https://github.com/user-attachments/files/28901573/README.1.md)
# linux-infra-automation

Production-tested Bash automation scripts for Oracle Linux and RHEL enterprise environments. Built and iterated across OL7, OL8, and OL9 fleets supporting large-scale infrastructure operations including security patching, credential management, and system administration workflows.

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

## Environment Compatibility

| Script | OL7 | OL8 | OL9 | RHEL 7 | RHEL 8 | RHEL 9 |
|---|---|---|---|---|---|---|
| ol_patch_security_only_enhanced.sh | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| rotate_passwords.sh | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

---

## Security Notes

- `rotate_passwords.sh` never writes generated passwords to disk — displayed on screen only
- No credentials are hardcoded in any script — all sensitive values are prompted at runtime or configured via placeholder variables
- SSH connections use `StrictHostKeyChecking=no` for fleet automation — recommended for internal trusted networks only
- All patching activity is logged to `/var/log/patching/` for audit trail compliance

---

## Author

**Erik Shannon** — Senior Systems Engineer  
📧 shannonerik7@gmail.com  
🔗 [linkedin.com/in/erik-shannon1b51aa154](https://www.linkedin.com/in/erik-shannon1b51aa154)
🐙 [github.com/erik-a-shannon](https://github.com/erik-a-shannon)

---

## License

MIT License — free to use, modify, and distribute with attribution.
