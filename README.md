# F5 License Manager (f5lm)

A powerful, interactive CLI tool for F5 BIG-IP license lifecycle management. Manage licenses across multiple F5 devices from a single terminal interface.

![Version](https://img.shields.io/badge/version-3.0-blue.svg)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20WSL-lightgrey.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

## Features

- 🖥️ **Interactive CLI** - Rich terminal interface with command history and tab completion
- 📋 **Device Inventory** - Track multiple F5 devices in one place
- 🔍 **License Monitoring** - Check license status across all devices
- 🔄 **License Renewal** - Apply new licenses via REST API
- 📝 **Dossier Generation** - Generate dossiers via REST API or SSH
- 🔐 **Secure** - Credentials never stored, used only for active session
- 📊 **Export** - Export device inventory to CSV

## Requirements

- **bash** (4.0+)
- **curl**
- **jq**
- **sshpass** (optional, for SSH-based operations)

### Installation of Dependencies

```bash
# macOS
brew install curl jq
brew install hudochenkov/sshpass/sshpass  # Optional

# Ubuntu/Debian
sudo apt install curl jq sshpass

# RHEL/CentOS
sudo yum install curl jq sshpass
```

## Installation

```bash
# Download
curl -O https://raw.githubusercontent.com/your-repo/f5lm/main/f5lm

# Make executable
chmod +x f5lm

# Optional: Move to PATH
sudo mv f5lm /usr/local/bin/
```

## Quick Start

```bash
# Launch interactive mode
./f5lm

# Or run single commands
./f5lm add 192.168.1.100
./f5lm check all
```

## Interface

```
  ███████╗███████╗   License Manager v3.0
  ██╔════╝██╔════╝   F5 BIG-IP License Lifecycle Tool
  █████╗  ███████╗
  ██╔══╝  ╚════██║   Type help for commands
  ██║     ███████║
  ╚═╝     ╚══════╝

  --------------------------------------------------------------------------

  OVERVIEW

  TOTAL        ACTIVE       EXPIRING     EXPIRED
  4            2            1            1

  DEVICES

  #   IP ADDRESS         EXPIRES        DAYS     STATUS
  --------------------------------------------------------------
  1   192.168.1.100      2026/06/15     152      ● active
  2   10.0.0.50          2025/02/10     27       ● expiring
  3   172.16.0.10        2024/12/01     -44      ● expired
  4   40.90.199.87       Perpetual      ∞        ● active

  f5lm > _
```

---

## Commands Reference

### Device Management

#### `add <ip> [label]`
Add a single F5 device to the inventory.

```bash
f5lm > add 192.168.1.100

  [OK] Added 192.168.1.100
       Run 'check 192.168.1.100' to fetch license info
```

With optional label:
```bash
f5lm > add 10.0.0.50 production-ltm

  [OK] Added 10.0.0.50
       Run 'check 10.0.0.50' to fetch license info
```

#### `add-multi`
Add multiple devices interactively.

```bash
f5lm > add-multi

  ADD MULTIPLE DEVICES
  Enter IP addresses, one per line. Empty line to finish.

  IP: 192.168.1.100
  [OK] Added 192.168.1.100
  IP: 192.168.1.101
  [OK] Added 192.168.1.101
  IP: 192.168.1.102
  [OK] Added 192.168.1.102
  IP: 

  [OK] Added 3 device(s)
```

#### `remove <ip>`
Remove a device from the inventory.

```bash
f5lm > remove 192.168.1.102

  Remove 192.168.1.102? [y/N]: y
  [OK] Removed 192.168.1.102
```

#### `list`
Display all devices in the inventory.

```bash
f5lm > list

  DEVICES

  #   IP ADDRESS         EXPIRES        DAYS     STATUS
  --------------------------------------------------------------
  1   192.168.1.100      2026/06/15     152      ● active
  2   10.0.0.50          2025/02/10     27       ● expiring
  3   172.16.0.10        2024/12/01     -44      ● expired
```

---

### License Operations

#### `check [ip|all]`
Check license status for one or all devices.

**Check all devices:**
```bash
f5lm > check all

  Enter F5 Credentials
  (credentials are never stored)

  Username: admin
  Password: 

  CHECKING LICENSES

  192.168.1.100        ● 152 days (exp: 2026/06/15)
  10.0.0.50            ● 27 days (exp: 2025/02/10)
  172.16.0.10          ● EXPIRED (2024/12/01)

  [OK] Checked 3 device(s)
```

**Check single device:**
```bash
f5lm > check 192.168.1.100

  CHECKING LICENSES

  192.168.1.100        ● 152 days (exp: 2026/06/15)

  [OK] Checked 1 device(s)
```

**Device restarting (after license renewal):**
```bash
f5lm > check 10.0.0.50

  CHECKING LICENSES

  10.0.0.50            ◌ restarting (services may be reloading)

  [WARN] 1 device(s) restarting - retry in 1-2 minutes
```

#### `details <ip>`
Show detailed license information for a device.

```bash
f5lm > details 192.168.1.100

  >>> Fetching details for 192.168.1.100...

  LICENSE DETAILS

  +--------------------------------------------------------------+
  | IP:             192.168.1.100                                |
  | Status:         ACTIVE (152 days)                            |
  +--------------------------------------------------------------+
  | Expires:        2026/06/15                                   |
  | Service Date:   2025/06/15                                   |
  | Licensed On:    2024/06/15                                   |
  | Platform:       Z100                                         |
  +--------------------------------------------------------------+
  | Reg Key:        ABCDE-FGHIJ-KLMNO-PQRST-UVWXYZZ              |
  +--------------------------------------------------------------+
```

#### `renew <ip> <registration-key>`
Apply a new license using a registration key via REST API.

> ⚠️ **Warning**: This operation restarts services on the device and may cause brief traffic interruption.

```bash
f5lm > renew 10.0.0.50 XXXXX-XXXXX-XXXXX-XXXXX-XXXXXXX

  ⚠ WARNING
  License renewal will restart services on the device.
  This may cause brief traffic interruption.
  Recommended: Perform during maintenance window.

  Proceed with license renewal? [y/N]: y

  >>> Connecting to 10.0.0.50...
  >>> Installing license...
  [OK] License installed successfully!

  >>> Device is applying license (services restarting)...
  Waiting for device to become available (up to 120s)...
  ⏳ Checking... (30s/120s)
  [OK] Device is back online

  LICENSE STATUS
  10.0.0.50            ● 365 days (exp: 2026/01/15)
```

#### `reload <ip>`
Reload the license file on a device via SSH (after manually copying license to `/config/bigip.license`).

```bash
f5lm > reload 10.0.0.50

  ⚠ WARNING
  License reload will restart services on the device.
  Recommended: Perform during maintenance window.

  Proceed? [y/N]: y

  >>> Reloading license on 10.0.0.50...
  [OK] License reload initiated

  >>> Device is applying license (services restarting)...
  Waiting for device to become available (up to 120s)...
  ⏳ Checking... (20s/120s)
  [OK] Device is back online

  LICENSE STATUS
  10.0.0.50            ● 365 days (exp: 2026/01/15)
```

#### `dossier <ip> [registration-key]`
Generate a dossier for manual license activation. Tries REST API first, falls back to SSH.

```bash
f5lm > dossier 192.168.1.100

  >>> Connecting to 192.168.1.100...
  >>> Retrieving registration key...
  [OK] Found registration key: ABCDE-FGHIJ-KLMNO-PQRST-UVWXYZZ
  >>> Generating dossier via REST API...
  [WARN] REST API not available
  >>> Trying SSH method...
  [OK] Dossier retrieved via SSH

  DOSSIER
  Registration Key: ABCDE-FGHIJ-KLMNO-PQRST-UVWXYZZ

  ------------------------------------------------------------
  4abb9dc68daa958e8396f7a39ea4ad4f6caa6e594c557d9c1ebab059e9
  ef43dbf4fb9502ea42045aabfc35923b72f6c6612a633c01955e520aae
  5f51143b8affbf8a019622c8ecc7842af452fb948b668a1bfebeec350e
  0fcf26d85e7769c1551aa08f908d17cf54397afc0982575deb452201240
  ------------------------------------------------------------

  NEXT STEPS
  1. Copy the dossier above
  2. Go to: https://activate.f5.com/license/dossier.jsp
  3. Paste the dossier and click Next
  4. Download license file, or copy content to /config/bigip.license
  5. Reload the license: reload 192.168.1.100 (or SSH: reloadlic)

  Saved to: /home/user/.f5lm/dossier_192_168_1_100.txt
```

With explicit registration key:
```bash
f5lm > dossier 192.168.1.100 XXXXX-XXXXX-XXXXX-XXXXX-XXXXXXX
```

#### `activate <ip>`
Interactive license activation wizard.

```bash
f5lm > activate 192.168.1.100

  LICENSE ACTIVATION WIZARD
  Follow these steps to activate a license on 192.168.1.100

  Step 1: Get Dossier
  The dossier uniquely identifies your F5 device.

  Retrieve dossier now? [Y/n]: y
  
  [dossier output...]

  Step 2: Get License from F5

  1. Visit: https://activate.f5.com/license
  2. Paste your dossier string
  3. Enter your base registration key
  4. Download or copy the license

  Step 3: Apply License

  Enter registration key (or press Enter to skip): XXXXX-XXXXX-XXXXX-XXXXX
  
  [renewal process...]
```

---

### Utilities

#### `export`
Export device inventory to CSV file.

```bash
f5lm > export

  [OK] Exported to /home/user/.f5lm/export_20250115_143022.csv
```

CSV format:
```csv
ip,expires,days,status,regkey,checked
"192.168.1.100","2026/06/15","152","active","ABCDE-XXXXX","2025-01-15T14:30:22Z"
"10.0.0.50","2025/02/10","27","expiring","FGHIJ-XXXXX","2025-01-15T14:30:22Z"
```

#### `history`
Show recent action history.

```bash
f5lm > history

  RECENT HISTORY

  [2025-01-15 14:30:22] ADDED 192.168.1.100
  [2025-01-15 14:30:45] CHECKED 192.168.1.100: active (152 days)
  [2025-01-15 14:31:02] RENEWED 10.0.0.50 with XXXXX-XXXXX...
  [2025-01-15 14:35:18] DOSSIER 172.16.0.10 (ZZZZZ-XXXXX)
```

#### `refresh`
Clear screen and refresh the display.

```bash
f5lm > refresh
```

#### `help`
Display command help.

```bash
f5lm > help

  COMMANDS

  Managing Devices
    add <ip>              Add single device
    add-multi             Add multiple devices
    remove <ip>           Remove device
    list                  Show all devices

  License Operations
    check [ip|all]        Check license status
    details <ip>          Show full license info
    renew <ip> <key>      Apply registration key (REST API)
    reload <ip>           Reload license file (SSH)
    activate <ip>         License activation wizard
    dossier <ip> [key]    Generate device dossier (REST or SSH)

  Utilities
    export                Export to CSV
    history               Show action log
    refresh               Refresh display
    help                  This help
    quit                  Exit

  Shortcuts
    a=add, r=remove, c=check, d=details, q=quit

  Keyboard
    ↑/↓        Command history
    ←/→        Move cursor in line
    Ctrl+A/E   Start/end of line
    Ctrl+W     Delete word
    Ctrl+C     Cancel current input
```

#### `quit`
Exit the tool.

```bash
f5lm > quit

  Goodbye!
```

---

## Status Indicators

| Symbol | Status | Description |
|--------|--------|-------------|
| `● active` | Active | License valid, more than 30 days remaining |
| `● expiring` | Expiring | License valid, 30 days or less remaining |
| `● EXPIRED` | Expired | License has expired |
| `◌ restarting` | Restarting | Device temporarily unavailable (services reloading) |
| `◌ pending` | Pending | Connected but license data not ready |
| `○ new` | New | Device added, not yet checked |
| `○ unknown` | Unknown | Unable to determine license status |

---

## Environment Variables

| Variable | Description |
|----------|-------------|
| `F5_USER` | F5 username (avoids interactive prompt) |
| `F5_PASS` | F5 password (avoids interactive prompt) |

**Example for automation:**
```bash
export F5_USER=admin
export F5_PASS=mypassword
./f5lm check all
```

---

## Data Storage

All data is stored locally in `~/.f5lm/`:

| File | Description |
|------|-------------|
| `devices.json` | Device inventory |
| `history.log` | Action history |
| `.history` | Command history |
| `dossier_*.txt` | Generated dossiers |
| `export_*.csv` | Exported data |

**Note:** Credentials are **never** stored.

---

## Complete License Renewal Workflow

### Option 1: Direct Renewal (if device has internet access)

```bash
# 1. Add device
f5lm > add 10.0.0.50

# 2. Check current license
f5lm > check 10.0.0.50

# 3. Renew with new registration key
f5lm > renew 10.0.0.50 XXXXX-XXXXX-XXXXX-XXXXX-XXXXXXX
```

### Option 2: Manual Activation (air-gapped devices)

```bash
# 1. Generate dossier
f5lm > dossier 10.0.0.50

# 2. Go to https://activate.f5.com/license/dossier.jsp
#    - Paste dossier
#    - Click Next
#    - Download license file

# 3. Copy license to device
scp license.txt admin@10.0.0.50:/config/bigip.license

# 4. Reload license
f5lm > reload 10.0.0.50
```

---

## Non-Interactive Mode

Run commands directly from the shell:

```bash
# Add device
./f5lm add 192.168.1.100

# Check all devices (requires F5_USER and F5_PASS)
export F5_USER=admin
export F5_PASS=password
./f5lm check all

# Export inventory
./f5lm export

# Show help
./f5lm --help
./f5lm -h
```

---

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `Tab` | Auto-complete commands and IPs |
| `↑` / `↓` | Browse command history |
| `←` / `→` | Move cursor in line |
| `Ctrl+A` | Jump to start of line |
| `Ctrl+E` | Jump to end of line |
| `Ctrl+W` | Delete word |
| `Ctrl+U` | Clear line |
| `Ctrl+C` | Cancel current input |
| `Ctrl+D` | Exit |

---

## Troubleshooting

### Authentication Failed
```
10.0.0.50        ◌ restarting (services may be reloading)
```
- Device may be restarting after license change
- Wait 1-2 minutes and try again

### SSH Dossier Failed
```
[WARN] sshpass not installed
```
Install sshpass for password-based SSH:
```bash
# macOS
brew install hudochenkov/sshpass/sshpass

# Ubuntu
sudo apt install sshpass
```

### REST API Not Available
```
[WARN] REST API not available (Public URI path not registered)
```
- Some F5 versions don't support dossier via REST
- Tool automatically falls back to SSH method

---

## License

MIT License - See [LICENSE](LICENSE) for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## Support

- Create an issue for bugs or feature requests
- Check existing issues before creating new ones
