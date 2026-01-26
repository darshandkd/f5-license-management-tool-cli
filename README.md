# F5 License Manager (f5lm)

A powerful, interactive CLI tool for F5 BIG-IP license lifecycle management. Manage licenses across multiple F5 devices from a single terminal interface.

![Version](https://img.shields.io/badge/version-3.8.12-blue.svg)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20BSD%20%7C%20WSL-lightgrey.svg)
![Bash](https://img.shields.io/badge/bash-3.2%2B-green.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

## Features

- **Interactive CLI** - Rich terminal interface with command history and readline support
- **Device Inventory** - Track multiple F5 devices in one place
- **License Monitoring** - Check license status across all devices
- **Auto-Check on Add** - Automatically checks license status when adding devices
- **License Renewal** - Apply new licenses via REST API with automatic verification
- **Dossier Generation** - Generate dossiers via REST API or SSH fallback
- **Add-on Key Application** - Apply add-on registration keys to existing licensed devices
- **One-Step License Application** - Paste or upload license directly from the tool
- **License Transfer** - Transfer VE licenses between virtual BIG-IP systems
- **Flexible SSH Auth** - Supports both SSH key and password authentication
- **Secure** - Credentials never stored, used only for active session
- **Export** - Export device inventory to CSV
- **Cross-Platform** - Works on Linux, macOS, FreeBSD, WSL, Cygwin

> **Note:** For detailed examples, workflows, and troubleshooting, see [User-guide-and-examples.txt](User-guide-and-examples.txt)

---

## Requirements

**Required:**
- **bash** 3.2 or later (macOS default works!)
- **curl**
- **jq**

**Optional (for SSH operations):**
- **sshpass** - For SSH password authentication
- **expect** - Alternative for SSH password authentication (pre-installed on macOS)

### Installation of Dependencies

```bash
# Debian/Ubuntu
sudo apt-get install curl jq sshpass

# RHEL/CentOS/Fedora
sudo yum install curl jq sshpass

# macOS (Homebrew)
brew install curl jq
brew install hudochenkov/sshpass/sshpass  # Optional
```

---

## Installation

```bash
# Download
curl -O https://raw.githubusercontent.com/your-repo/f5lm/main/f5lm

# Make executable
chmod +x f5lm

# Optional: Move to PATH
sudo mv f5lm /usr/local/bin/
```

---

## Quick Start

```bash
# Launch interactive mode
./f5lm

# Or run single commands
./f5lm add 192.168.1.100
./f5lm check all
```

---

## SSH Authentication

The tool supports both **SSH key-based** and **password-based** authentication.

### Basic Usage

```bash
# Using environment variables (recommended for automation)
export F5_USER=admin
export F5_PASS=password
./f5lm check all

# Or interactively - leave password empty for SSH key auth
f5lm > check 192.168.1.100
Username: root
Password: [Enter for SSH key auth]
Using SSH key authentication
```

### Per-Device Credentials

```bash
# Different credentials per device (replace dots with underscores)
export F5_USER_192_168_1_100=admin
export F5_PASS_192_168_1_100=pass1
export F5_USER_10_0_0_50=root
export F5_SSH_KEY_10_0_0_50=~/.ssh/f5_key
```

> **Note:** See [User-guide-and-examples.txt](User-guide-and-examples.txt) for complete authentication documentation.

---

## Interface

```
  ███████╗███████╗   License Manager v3.8.10
  ██╔════╝██╔════╝   F5 BIG-IP License Lifecycle Tool
  █████╗  ███████╗
  ██╔══╝  ╚════██║   Type help for commands
  ██║     ███████║
  ╚═╝     ╚══════╝

  DEVICES

  #   IP ADDRESS         EXPIRES        DAYS       STATUS
  --------------------------------------------------------------
  1   192.168.1.100      2026/06/15     152        ● active
  2   10.0.0.50          2025/02/10     27         ● expiring
  3   172.16.0.10        -              ∞          ● perpetual

  f5lm > _
```

---

## Commands Reference

### Device Management

| Command | Description |
|---------|-------------|
| `add <ip>` | Add device (prompts for auth type, auto-checks license) |
| `add-multi` | Add multiple devices interactively |
| `remove <ip>` | Remove device from inventory |
| `list` | Display all devices with status |

**Example - Add Device:**
```bash
f5lm > add 192.168.1.100

  SSH Authentication for 192.168.1.100
  [1] SSH Key (passwordless)
  [2] Password

  Auth type [1/2]: 1
  [OK] Added 192.168.1.100 (key auth)
  >>> Checking license status...
  192.168.1.100        ● 152 days
```

### License Operations

| Command | Description |
|---------|-------------|
| `check [ip\|all]` | Check license status for one or all devices |
| `details <ip>` | Show detailed license information |
| `renew <ip> <key>` | Apply registration key via REST API |
| `reload <ip>` | Reload license file via SSH |
| `dossier <ip>` | Generate dossier + optional license apply |
| `addon <ip> <addon-key> [base-key]` | Apply add-on key to licensed device |
| `apply-license <ip>` | Apply license file/content to device |
| `activate <ip>` | Interactive license activation wizard |
| `transfer <ip> [--to]` | Transfer VE license to new system (VE only) |

**Example - Check All:**
```bash
f5lm > check all
  192.168.1.100        ● 152 days (exp: 2026/06/15)
  10.0.0.50            ● 27 days (exp: 2025/02/10)
  172.16.0.10          ● perpetual (no expiration)
```

**Example - Generate Dossier:**
```bash
f5lm > dossier 192.168.1.100
  [OK] Dossier retrieved via SSH
  Saved to: ~/.f5lm/dossier_192_168_1_100.txt

  [P] Paste license content here
  [F] Upload license from local file
  [S] Skip - apply license manually later
```

**Example - Apply Add-on Key:**
```bash
f5lm > addon 192.168.1.100 ABCDE-FGHIJ-KLMNO-PQRST
  [OK] Found base registration key: XXXXX-XXXXX-XXXXX-XXXXX-XXXXXXX
  [INFO] Generating dossier with base + add-on keys...
  [OK] Dossier generated via SSH

  DOSSIER (with add-on key)
  Base Key: XXXXX-XXXXX-XXXXX-XXXXX-XXXXXXX
  Add-on Key: ABCDE-FGHIJ-KLMNO-PQRST

  ──────────────────────────────────────────────────────
  [hex dossier content...]
  ──────────────────────────────────────────────────────

  [O] Online activation (device has internet)
  [M] Manual activation (via F5 portal)
  [P] Paste license content here
  [F] Upload license from local file
  [S] Skip - apply license manually later
```

**Example - Renew License:**
```bash
f5lm > renew 10.0.0.50 XXXXX-XXXXX-XXXXX-XXXXX-XXXXXXX
  [OK] License installed!
  [OK] Device is back online
  10.0.0.50            ● 365 days
```

### Utilities

| Command | Description |
|---------|-------------|
| `export` | Export device inventory to CSV |
| `history` | Show recent operation log |
| `help` | Display command help |
| `quit` | Exit the tool |

---

## Status Indicators

| Symbol | Status | Description |
|--------|--------|-------------|
| `● active` | Active | License valid, more than 30 days remaining |
| `● expiring` | Expiring | License valid, 30 days or less remaining |
| `● perpetual` | Perpetual | License has no expiration date |
| `● EXPIRED` | Expired | License has expired |
| `○ new` | New | Device added, not yet checked |
| `○ unknown` | Unknown | Unable to determine license status |

---

## License Date Tracking (v3.8.10)

The tool tracks license expiration using **License End Date**, per official F5 documentation (K7727, K000151595, K9245):

| Date | Purpose | Used For |
|------|---------|----------|
| **License End Date** | When the license expires and device stops traffic | **Expiration tracking** |
| **Service Check Date** | Software upgrade eligibility | Upgrade planning only |

**License Types:**
- **Time-limited licenses** (subscription/eval/trial) - Have a License End Date, device stops working when expired
- **Perpetual licenses** - No License End Date, device runs forever (upgrade still requires valid Service Check Date)

**Example `details` output:**
```
+--------------------------------------------------------------+
| IP:            10.1.1.1                                      |
| Status:        ACTIVE (31 days)                              |
+--------------------------------------------------------------+
| License End:   2026/02/20 (used for expiration)              |
| Svc Check:     2026/01/20 (upgrade eligibility)              |
| Licensed On:   2026/01/20                                    |
| Platform:      Z100                                          |
+--------------------------------------------------------------+
```

---

## TMOS/Bash Shell Compatibility

The tool works regardless of which shell you land in when connecting to F5 devices:
- **TMOS shell**: `admin@(bigip)(tmos)#`
- **Bash shell**: `[admin@bigip:Active:Standalone] ~ #`

All commands (including bash-only commands like `reloadlic`, `get_dossier`) automatically detect the shell and use appropriate fallback methods.

---

## Environment Variables

| Variable | Description |
|----------|-------------|
| `F5_USER` | Default username for all devices |
| `F5_PASS` | Default password (omit for SSH key auth) |
| `F5_SSH_KEY` | Path to SSH private key |
| `NO_COLOR` | Disable color output |

---

## Data Storage

All data is stored locally in `~/.f5lm/`:
- `devices.json` - Device inventory
- `history.log` - Action history
- `dossier_*.txt` - Generated dossiers

**Note:** Credentials are **never** stored.

---

## License Transfer (v3.8.11)

Transfer a BIG-IP VE license from one virtual instance to another. Based on F5 Knowledge Base article K41458656.

**Important:** License transfer only works for BIG-IP **Virtual Edition (VE)** systems, not physical appliances.

### Requirements

- BIG-IP VE version 12.1.3.3+ or 13.1.0.2+
- Source system must have network access to `activate.f5.com` on TCP port 443
- Admin credentials for the source device

### Usage

```bash
# Revoke license from source device (VE only)
f5lm > transfer 192.168.1.100

# Revoke and immediately activate on new device
f5lm > transfer 192.168.1.100 --to 192.168.1.200
```

### What Happens

1. **Verification** - Tool checks that the device is a Virtual Edition (platform Z100, Z101, etc.)
2. **Warning** - Displays explicit warning about consequences
3. **Confirmation** - Requires typing "REVOKE" to confirm
4. **Revocation** - Contacts F5 license server to revoke the license
5. **Registration Key** - Displays the key for reactivation on another system

### Example

```bash
f5lm > transfer 10.1.1.1

  LICENSE TRANSFER
  Transfer license from BIG-IP VE to another system

  >>> Checking if 10.1.1.1 is a Virtual Edition...
  [OK] Platform verified: Z100 (Virtual Edition)

  ╔══════════════════════════════════════════════════════════════════╗
  ║                         ⚠ WARNING ⚠                              ║
  ╠══════════════════════════════════════════════════════════════════╣
  ║  Revoking the license will:                                      ║
  ║  • IMMEDIATELY disable traffic management                        ║
  ║  • Return the device to an UNLICENSED state                      ║
  ║  • Stop all BIG-IP services                                      ║
  ╚══════════════════════════════════════════════════════════════════╝

  Type "REVOKE" to confirm: REVOKE

  >>> Revoking license on 10.1.1.1...
  [OK] License revoked successfully!

  Registration Key: XXXXX-XXXXX-XXXXX-XXXXX-XXXXXXX
  This key can now be activated on another BIG-IP VE system.
```

### References

- [K41458656: Reusing a BIG-IP VE license](https://my.f5.com/manage/s/article/K41458656)
- [How to move a BIG-IP VE license - DevCentral](https://community.f5.com/kb/technicalarticles/how-to-move-a-big-ip-ve-license/342893)

---

## Version History

### v3.8.12 (Current)
- **Add-on Key Application** - Apply add-on registration keys to existing licensed F5 BIG-IP devices:
  - New `addon` command for add-on key application
  - Generates dossier with both base and add-on keys using `get_dossier -b <base> -a <addon>`
  - Supports both TMOS and bash shell modes automatically
  - Handles online/offline scenarios with connectivity detection
  - Provides multiple license application options (online, manual, paste, file)
  - Automatically retrieves base registration key from device if not provided
  - Comprehensive error handling and manual fallback instructions

### v3.8.11
- **License Transfer** - Transfer VE licenses between virtual BIG-IP systems (per K41458656):
  - New `transfer` command to revoke license from source VE
  - Optional `--to` flag to immediately activate on target device
  - Platform detection to ensure only VE systems are used
  - Requires explicit confirmation (type "REVOKE") for safety
- **Platform Detection** - Detects Virtual Edition (Z100, Z101, etc.) vs hardware platforms

### v3.8.10
- **License End Date for expiration tracking** - Per F5 KB articles K7727, K000151595, K9245:
  - **License End Date** = When device stops processing traffic (used for expiration tracking)
  - **Service Check Date** = Upgrade eligibility only (NOT for license expiration)
  - **Perpetual License** = No License End Date (device runs forever)
- **TMOS shell compatibility** - All bash-only commands (reloadlic, get_dossier, etc.) now work regardless of whether user lands in TMOS or Bash shell
- **Display both dates** - `details` command shows License End Date (for expiration) and Service Check Date (for upgrades)

### v3.8.9 (Superseded)
- Incorrectly used Service Check Date for expiration (fixed in v3.8.10)

### v3.8.8
- **Auth type back-navigation** - Switch from SSH key to password auth if needed (press `[p]` when SSH key not found)
- **SSH key path quote handling** - Handles quoted paths correctly
- **Improved auth prompts** - Better options when SSH key validation fails

### v3.8.7
- Fixed credential loading order
- Improved perpetual license handling
- Auto-detect env credentials on add

### v3.8.6
- Fixed password auth without sshpass
- Interactive password prompts when sshpass not installed

### v3.8.5
- Perpetual license support

> **Note:** See [User-guide-and-examples.txt](User-guide-and-examples.txt) for complete version history.

---

## Troubleshooting

**Device shows "restarting":**
- Wait 1-2 minutes after license changes

**SSH dossier failed:**
- Install `sshpass` for best results, or use SSH keys

**REST API not available:**
- Normal behavior - tool falls back to SSH method automatically

> **Note:** See [User-guide-and-examples.txt](User-guide-and-examples.txt) for complete troubleshooting guide.

---

## License

MIT License - See [LICENSE](LICENSE) for details.

---

## Contributing

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

---

## Support

- Create an issue for bugs or feature requests
- F5 License Portal: https://activate.f5.com/license/dossier.jsp
