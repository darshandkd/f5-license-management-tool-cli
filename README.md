# F5 License Manager (f5lm)

A powerful, interactive CLI tool for F5 BIG-IP license lifecycle management. Manage licenses across multiple F5 devices from a single terminal interface.

![Version](https://img.shields.io/badge/version-3.3.1-blue.svg)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20BSD%20%7C%20WSL-lightgrey.svg)
![Bash](https://img.shields.io/badge/bash-3.2%2B-green.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

## Features

- 🖥️ **Interactive CLI** - Rich terminal interface with command history and readline support
- 📋 **Device Inventory** - Track multiple F5 devices in one place
- 🔍 **License Monitoring** - Check license status across all devices
- ⚡ **Auto-Check on Add** - Automatically checks license status when adding devices
- 🔄 **License Renewal** - Apply new licenses via REST API with automatic verification
- 📝 **Dossier Generation** - Generate dossiers via REST API or SSH fallback
- 🎯 **One-Step License Application** - Paste or upload license directly from the tool
- 🔐 **Secure** - Credentials never stored, used only for active session
- 📊 **Export** - Export device inventory to CSV
- 🌍 **Cross-Platform** - Works on Linux, macOS, FreeBSD, WSL, Cygwin

## Compatibility

| Platform | Tested | Notes |
|----------|--------|-------|
| Ubuntu/Debian | ✅ | Full support |
| RHEL/CentOS/Fedora | ✅ | Full support |
| Alpine Linux | ✅ | Full support |
| macOS (Intel/Apple Silicon) | ✅ | Full support |
| FreeBSD | ✅ | Full support |
| WSL/WSL2 | ✅ | Full support |
| Cygwin/MSYS2 | ✅ | Full support |
| Git Bash | ✅ | Limited (no SSH) |

**Terminal Support:**
- Works with or without UTF-8 (automatic fallback to ASCII)
- Works with or without color support (automatic detection)
- Respects `NO_COLOR` environment variable
- Works in dumb terminals (e.g., CI/CD pipelines)

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
# or
sudo dnf install curl jq sshpass

# Alpine Linux
apk add curl jq openssh-client sshpass

# Arch Linux
pacman -S curl jq sshpass

# macOS (Homebrew)
brew install curl jq
brew install hudochenkov/sshpass/sshpass  # Optional - expect is pre-installed

# FreeBSD
pkg install curl jq sshpass
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

## Interface

```
  ███████╗███████╗   License Manager v3.3.1
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

  #   IP ADDRESS         EXPIRES        DAYS       STATUS
  --------------------------------------------------------------
  1   192.168.1.100      2026/06/15     152        ● active
  2   10.0.0.50          2025/02/10     27         ● expiring
  3   172.16.0.10        2024/12/01     -44        ● expired
  4   40.90.199.87       -              ?          ○ new

  f5lm > _
```

---

## Commands Reference

### Device Management

#### `add <ip>`
Add a single F5 device to the inventory. **Automatically checks license status** if credentials are available.

```bash
f5lm > add 192.168.1.100

  [OK] Added 192.168.1.100
  >>> Checking license status...
  192.168.1.100        ● 152 days
```

#### `add-multi`
Add multiple devices interactively. **Automatically checks all added devices** after input is complete.

```bash
f5lm > add-multi

  ADD MULTIPLE DEVICES
  Enter IPs, one per line. Empty line to finish.

  IP: 192.168.1.100
  [OK] Added 192.168.1.100
  IP: 192.168.1.101
  [OK] Added 192.168.1.101
  IP: 192.168.1.102
  [OK] Added 192.168.1.102
  IP: 

  [OK] Added 3 device(s)

  Checking license status...

  Enter F5 Credentials
  (credentials are never stored)

  Username: admin
  Password: 

  192.168.1.100        ● 152 days
  192.168.1.101        ● 365 days
  192.168.1.102        ! 25 days

  [OK] Checked 3 device(s)
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

  #   IP ADDRESS         EXPIRES        DAYS       STATUS
  --------------------------------------------------------------
  1   192.168.1.100      2026/06/15     152        ● active
  2   10.0.0.50          2025/02/10     27         ● expiring
  3   172.16.0.10        2024/12/01     -44        ● expired
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

  WARNING
  License renewal will restart services on the device.
  This may cause brief traffic interruption.
  Recommended: Perform during maintenance window.

  Proceed? [y/N]: y

  >>> Connecting to 10.0.0.50...
  >>> Installing license...
  [OK] License installed!

  >>> Device applying license (services restarting)...
  Waiting for device (up to 120s)...
  Checking... (30s/120s)
  [OK] Device is back online

  LICENSE STATUS
  10.0.0.50            ● 365 days (exp: 2026/01/15)
```

#### `reload <ip>`
Reload the license file on a device via SSH (after manually copying license to `/config/bigip.license`).

```bash
f5lm > reload 10.0.0.50

  WARNING
  License reload will restart services.
  Recommended: Perform during maintenance window.

  Proceed? [y/N]: y

  >>> Reloading license on 10.0.0.50...
  [OK] License reload initiated

  >>> Device applying license...
  Waiting for device (up to 120s)...
  Checking... (20s/120s)
  [OK] Device is back online

  LICENSE STATUS
  10.0.0.50            ● 365 days (exp: 2026/01/15)
```

#### `dossier <ip> [registration-key]`
Generate a dossier for license activation. After generating the dossier, you can **apply the license directly** from within the tool - no need to SSH separately!

```bash
f5lm > dossier 192.168.1.100

  >>> Connecting to 192.168.1.100...
  >>> Retrieving registration key...
  [OK] Found registration key: ABCDE-FGHIJ-KLMNO-PQRST-UVWXYZZ
  >>> Generating dossier via REST API...
  [WARN] REST API not available (Public URI path not registered)
  >>> Trying SSH method...
  [OK] Dossier retrieved via SSH

  DOSSIER
  Registration Key: ABCDE-FGHIJ-KLMNO-PQRST-UVWXYZZ

  ------------------------------------------------------------
  4abb9dc68daa958e8396f7a39ea4ad4f6caa6e594c557d9c1ebab059e9
  ef43dbf4fb9502ea42045aabfc35923b72f6c6612a633c01955e520aae
  ...
  ------------------------------------------------------------

  Saved to: /Users/you/.f5lm/dossier_192_168_1_100.txt

  ╔═════════════════════════════════════════════════════════════════╗
  ║  APPLY LICENSE                                                  ║
  ╠═════════════════════════════════════════════════════════════════╣
  ║  1. Open F5 license portal and get license                      ║
  ║     https://activate.f5.com/license/dossier.jsp                 ║
  ║                                                                 ║
  ║  After getting the license, choose how to apply it:            ║
  ║                                                                 ║
  ║  [P] Paste license content here                                ║
  ║  [F] Upload license from local file                            ║
  ║  [S] Skip - apply license manually later                       ║
  ╚═════════════════════════════════════════════════════════════════╝

  Choice [P/F/S]: P

  ┌─────────────────────────────────────────────────────────────────┐
  │  PASTE LICENSE CONTENT                                          │
  │  (Paste the license text, then press Enter twice to finish)     │
  └─────────────────────────────────────────────────────────────────┘

  [paste license content here...]


  [OK] License content loaded (127 lines)

  WARNING
  This will overwrite the existing license and restart services.
  A backup will be created at /var/tmp/bigip.license.backup.*

  Proceed? [y/N]: y

  >>> Establishing SSH connection...
  (root@192.168.1.100) Password: ****

  >>> Backing up existing license...
    Backup: /var/tmp/bigip.license.backup.20250115_143022
  >>> Writing license to device...
  [OK] License written to device

  >>> Reloading license configuration...
  [OK] License reload initiated

  >>> Waiting for services to restart...
  Checking... (30s/120s)
  [OK] Device is back online

  LICENSE STATUS
  192.168.1.100        ● 365 days (exp: 2026/01/15)
```

> **Note:** Only one password prompt is required. SSH connection multiplexing reuses the authenticated connection for backup, upload, and reload operations.

**Upload from file instead of pasting:**
```bash
  Choice [P/F/S]: F

  Enter path to license file: ~/Downloads/bigip.license
  
  >>> Reading license from file...
  [OK] License content loaded (127 lines)
  ...
```

#### `apply-license <ip> [license-file]`
Apply a license file or content to a device. Use this if you already have the license and want to apply it without generating a new dossier.

```bash
# Apply by pasting content
f5lm > apply-license 10.0.0.50

  APPLY LICENSE
  Target device: 10.0.0.50

  How would you like to provide the license?

    [P] Paste license content
    [F] Load from file

  Choice [P/F]: P
  ...

# Or directly from file
f5lm > apply-license 10.0.0.50 ~/Downloads/license.txt

  APPLY LICENSE
  Target device: 10.0.0.50

  >>> Reading license from file: /home/user/Downloads/license.txt
  [OK] License content loaded (127 lines)

  WARNING
  This will:
    • Backup existing license to /var/tmp/bigip.license.backup.*
    • Overwrite /config/bigip.license
    • Restart F5 services (brief traffic interruption)

  Proceed? [y/N]: y
  ...
```

#### `activate <ip>`
Interactive license activation wizard that guides you through the process.

```bash
f5lm > activate 192.168.1.100

  LICENSE ACTIVATION WIZARD
  Activate license on 192.168.1.100

  Step 1: Get Dossier
  The dossier identifies your device.

  Retrieve dossier now? [Y/n]: y
  ...

  Step 2: Get License from F5

  1. Visit: https://activate.f5.com/license
  2. Paste your dossier
  3. Enter registration key
  4. Download license

  Step 3: Apply License

  Enter registration key (or Enter to skip): XXXXX-XXXXX-XXXXX-XXXXX-XXXXXXX
  ...
```

---

### Utilities

#### `export`
Export all device data to CSV.

```bash
f5lm > export

  [OK] Exported to /Users/you/.f5lm/export_20250115_143022.csv
```

#### `history`
Show recent action history.

```bash
f5lm > history

  RECENT HISTORY

  [2025-01-15 14:30:22] ADDED 192.168.1.100
  [2025-01-15 14:30:22] CHECKED 192.168.1.100: active (152 days)
  [2025-01-15 14:30:45] ADDED 192.168.1.101
  [2025-01-15 14:30:45] CHECKED 192.168.1.101: active (365 days)
  [2025-01-15 14:31:02] RENEWED 10.0.0.50 with XXXXX-XXXXX...
  [2025-01-15 14:35:18] DOSSIER 172.16.0.10 (ZZZZZ-XXXXX)
```

#### `refresh`
Clear screen and refresh the display.

#### `help`
Display command help.

#### `quit`
Exit the tool.

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
| `◌ unreachable` | Unreachable | Cannot connect to device |

---

## Environment Variables

| Variable | Description |
|----------|-------------|
| `F5_USER` | F5 username (avoids interactive prompt) |
| `F5_PASS` | F5 password (avoids interactive prompt) |
| `NO_COLOR` | Disable color output |
| `F5LM_NO_COLOR` | Disable color output (alternative) |
| `XDG_DATA_HOME` | Custom data directory (default: `~/.f5lm`) |

**Example for automation:**
```bash
export F5_USER=admin
export F5_PASS=mypassword
./f5lm add 192.168.1.100    # Auto-checks immediately
./f5lm check all
```

**CI/CD Pipeline Example:**
```bash
#!/bin/bash
export F5_USER="$F5_USERNAME"
export F5_PASS="$F5_PASSWORD"
export NO_COLOR=1

./f5lm add 10.0.0.50
./f5lm add 10.0.0.51
./f5lm check all
./f5lm export
```

---

## Data Storage

All data is stored locally in `~/.f5lm/` (or `$XDG_DATA_HOME/f5lm/`):

| File | Description |
|------|-------------|
| `devices.json` | Device inventory |
| `history.log` | Action history |
| `.cmd_history` | Command history (readline) |
| `dossier_*.txt` | Generated dossiers |
| `export_*.csv` | Exported data |

**Note:** Credentials are **never** stored.

---

## Complete License Renewal Workflow

### Option 1: Direct Renewal (device has internet access)

```bash
# 1. Add device (auto-checks license)
f5lm > add 10.0.0.50

  [OK] Added 10.0.0.50
  >>> Checking license status...
  10.0.0.50            ● 30 days

# 2. Renew with new registration key
f5lm > renew 10.0.0.50 XXXXX-XXXXX-XXXXX-XXXXX-XXXXXXX

  [OK] License installed!
  [OK] Device is back online
  10.0.0.50            ● 365 days
```

### Option 2: Manual Activation (air-gapped devices)

```bash
# 1. Generate dossier
f5lm > dossier 10.0.0.50

  [OK] Dossier retrieved via SSH
  ... (copy dossier output)

# 2. Go to https://activate.f5.com/license/dossier.jsp
#    - Paste dossier
#    - Click Next
#    - Download license file

# 3. Copy license to device
scp license.txt admin@10.0.0.50:/config/bigip.license

# 4. Reload license
f5lm > reload 10.0.0.50

  [OK] License reload initiated
  [OK] Device is back online
  10.0.0.50            ● 365 days
```

---

## Non-Interactive Mode

Run commands directly from the shell:

```bash
# Add device (with auto-check if credentials set)
export F5_USER=admin
export F5_PASS=password
./f5lm add 192.168.1.100

# Check all devices
./f5lm check all

# Export inventory
./f5lm export

# Show version
./f5lm --version
./f5lm -v

# Show help
./f5lm --help
./f5lm -h
```

---

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `↑` / `↓` | Browse command history |
| `←` / `→` | Move cursor in line |
| `Ctrl+A` | Jump to start of line |
| `Ctrl+E` | Jump to end of line |
| `Ctrl+W` | Delete word |
| `Ctrl+U` | Clear line |
| `Ctrl+C` | Cancel current input |
| `Ctrl+D` | Exit |

**Command Shortcuts:**
| Short | Command |
|-------|---------|
| `a` | `add` |
| `am` | `add-multi` |
| `r` | `remove` |
| `c` | `check` |
| `d` | `details` |
| `l` | `list` |
| `h` | `history` |
| `q` | `quit` |

---

## Troubleshooting

### Authentication Failed / Restarting
```
10.0.0.50        ◌ restarting (services may be reloading)
```
- Device may be restarting after license change
- Wait 1-2 minutes and try again
- The tool automatically waits up to 120 seconds after renew/reload

### SSH Dossier Failed
```
[WARN] sshpass not installed - trying without password automation
```
The tool tries multiple SSH methods in order:
1. **sshpass** (if installed) - Best for automation
2. **expect** (if installed) - Good fallback (pre-installed on macOS)
3. **SSH keys** - If key-based auth is configured

Install sshpass for best results:
```bash
# macOS
brew install hudochenkov/sshpass/sshpass

# Ubuntu/Debian
sudo apt-get install sshpass

# RHEL/CentOS
sudo yum install sshpass

# Alpine
apk add sshpass
```

### REST API Not Available
```
[WARN] REST API not available (Public URI path not registered)
```
- Some F5 versions don't support dossier via REST API
- Tool automatically falls back to SSH method
- This is normal behavior

### No Colors in Terminal
The tool automatically detects terminal capabilities. To force disable colors:
```bash
export NO_COLOR=1
./f5lm
```

### Unicode Characters Not Displaying
If you see garbled characters, your terminal may not support UTF-8:
```bash
# Check current locale
locale

# Set UTF-8 locale (Linux)
export LANG=en_US.UTF-8

# The tool will automatically use ASCII fallback if UTF-8 is not available
```

### Database Corrupted
If you see "Database corrupted, creating backup":
- The tool automatically recovers
- Your old data is saved to `~/.f5lm/devices.json.bak.<timestamp>`
- You can restore manually if needed

### Bash Version Too Old
```
Error: Bash 3.2+ required
```
Upgrade bash:
```bash
# macOS (ships with bash 3.2, which is sufficient)
brew install bash

# Linux - bash 3.2+ is standard on all modern distros
```

---

## Version History

### v3.3.1 (Current)
- **SSH connection multiplexing** - Single password prompt for all license operations (backup, upload, reload)
- **Fixed license paste** - Header text no longer included in license file content
- **Cleaner output** - UI prompts sent to stderr, only data captured in variables

### v3.3.0
- **Integrated license application** - Apply license directly from dossier command (paste or file upload)
- **New `apply-license` command** - Standalone command to apply license file/content
- **Automatic license backup** - Creates backup at `/var/tmp/bigip.license.backup.*` before overwriting
- **License validation** - Basic validation of license content before applying
- **Streamlined workflow** - Complete license renewal without leaving the tool

### v3.2.1
- **Auto-check on add** - Automatically checks license status when adding devices
- **Improved add-multi** - Checks all devices after batch add with single credential prompt
- **Better SSH fallback** - Uses sshpass, expect, or SSH keys in order of preference
- **Interactive SSH option** - Offers to open SSH session if dossier generation fails
- **Better error messages** - Distinguishes "auth failed" from "unreachable" and "restarting"

### v3.2.0
- **Cross-platform hardening** - Works on bash 3.2+ (macOS compatible)
- **Portable date handling** - GNU and BSD date support
- **Safe credential handling** - JSON escaping for special characters
- **Automatic terminal detection** - UTF-8/ASCII, color/no-color
- **Signal handling** - Clean exit on Ctrl+C
- **Temp file cleanup** - Automatic cleanup on exit
- **Timeout fallback** - Works without `timeout` command

### v3.1.0
- SSH-based dossier generation fallback
- License reload command
- Maintenance window warnings
- Post-renewal verification with retry

### v3.0.0
- Initial public release
- Interactive CLI interface
- REST API integration
- Device inventory management

---

## License

MIT License - See [LICENSE](LICENSE) for details.

---

## Contributing

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

**Code Style:**
- Use `printf` instead of `echo -e` for portability
- Avoid bash 4+ specific features (for macOS compatibility)
- Test on both Linux and macOS
- Include shellcheck compliance

---

## Support

- Create an issue for bugs or feature requests
- Check existing issues before creating new ones
