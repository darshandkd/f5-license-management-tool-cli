#!/usr/bin/env bash
#===============================================================================
#
#   F5 LICENSE MANAGER (f5lm)
#   Interactive CLI for F5 BIG-IP License Lifecycle Management
#
#   Version:       3.2.0
#   Compatibility: Linux, macOS, FreeBSD, WSL, Cygwin
#   Requirements:  bash 3.2+, curl, jq
#   Optional:      sshpass (for SSH password automation)
#
#   License:       MIT
#   Repository:    https://github.com/your-repo/f5lm
#
#===============================================================================

#-------------------------------------------------------------------------------
# STRICT MODE & ERROR HANDLING
#-------------------------------------------------------------------------------
# Note: We don't use 'set -e' because we handle errors explicitly
# Note: We don't use 'set -u' because we check variables explicitly
set -o pipefail 2>/dev/null || true

# Script metadata
readonly F5LM_VERSION="3.8.6"
readonly F5LM_NAME="F5 License Manager"

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1
readonly EXIT_USAGE=2
readonly EXIT_DEPENDENCY=3

#-------------------------------------------------------------------------------
# GLOBAL VARIABLES (set by init functions)
#-------------------------------------------------------------------------------
PLATFORM=""
BASH_MAJOR=""
BASH_MODERN=0
IS_TTY=0
HAS_UTF8=0
IS_SMART_TERM=0
HAS_SSHPASS=0
HAS_TIMEOUT=0
DATA_DIR=""
DB_FILE=""
LOG_FILE=""
HIST_FILE=""
LOCK_FILE=""
TEMP_FILES=()

# Colors (initialized by setup_colors)
R="" G="" Y="" B="" C="" W="" D="" BD="" RS=""

# Symbols (initialized by setup_symbols)
SYM_OK="" SYM_WARN="" SYM_ERR="" SYM_PENDING="" SYM_WAIT="" SYM_ARROW=""

# Credentials (from environment or prompt)
F5_USER="${F5_USER:-}"
F5_PASS="${F5_PASS:-}"

#-------------------------------------------------------------------------------
# CLEANUP & SIGNAL HANDLING
#-------------------------------------------------------------------------------
cleanup() {
    local exit_code=$?
    
    # Remove temp files
    local f
    for f in "${TEMP_FILES[@]}"; do
        [[ -f "$f" ]] && rm -f "$f" 2>/dev/null
    done
    
    # Remove lock file if we own it
    if [[ -n "${LOCK_FILE:-}" && -f "$LOCK_FILE" ]]; then
        rm -f "$LOCK_FILE" 2>/dev/null
    fi
    
    exit $exit_code
}

# Set up signal handlers
trap cleanup EXIT
trap 'echo; exit 130' INT      # Ctrl+C
trap 'exit 143' TERM           # kill

#-------------------------------------------------------------------------------
# UTILITY: Safe temp file creation
#-------------------------------------------------------------------------------
make_temp_file() {
    local template="${1:-f5lm.XXXXXX}"
    local tmpfile
    
    if command -v mktemp >/dev/null 2>&1; then
        tmpfile=$(mktemp -t "$template" 2>/dev/null) || tmpfile=$(mktemp 2>/dev/null)
    else
        # Fallback for systems without mktemp
        tmpfile="${TMPDIR:-/tmp}/${template}.$$.$RANDOM"
        : > "$tmpfile" || return 1
    fi
    
    TEMP_FILES+=("$tmpfile")
    echo "$tmpfile"
}

#-------------------------------------------------------------------------------
# PLATFORM DETECTION
#-------------------------------------------------------------------------------
detect_platform() {
    local uname_out
    uname_out="$(uname -s 2>/dev/null)" || uname_out="unknown"
    
    case "$uname_out" in
        Linux*)     PLATFORM="linux" ;;
        Darwin*)    PLATFORM="macos" ;;
        FreeBSD*)   PLATFORM="freebsd" ;;
        OpenBSD*)   PLATFORM="openbsd" ;;
        NetBSD*)    PLATFORM="netbsd" ;;
        SunOS*)     PLATFORM="solaris" ;;
        CYGWIN*)    PLATFORM="cygwin" ;;
        MINGW*|MSYS*) PLATFORM="mingw" ;;
        *)          PLATFORM="unknown" ;;
    esac
    
    # Detect bash version safely
    if [[ -n "${BASH_VERSION:-}" ]]; then
        BASH_MAJOR="${BASH_VERSION%%.*}"
        local minor="${BASH_VERSION#*.}"
        BASH_MINOR="${minor%%.*}"
    else
        BASH_MAJOR=3
        BASH_MINOR=0
    fi
    
    # Modern bash check (4.0+ has associative arrays, better readline)
    if [[ "$BASH_MAJOR" -ge 4 ]]; then
        BASH_MODERN=1
    else
        BASH_MODERN=0
    fi
    
    # Check for timeout command
    if command -v timeout >/dev/null 2>&1; then
        HAS_TIMEOUT=1
    elif command -v gtimeout >/dev/null 2>&1; then
        # GNU timeout on macOS via coreutils
        HAS_TIMEOUT=1
        alias timeout='gtimeout' 2>/dev/null || true
    else
        HAS_TIMEOUT=0
    fi
    
    # Check for sshpass
    if command -v sshpass >/dev/null 2>&1; then
        HAS_SSHPASS=1
    else
        HAS_SSHPASS=0
    fi
}

#-------------------------------------------------------------------------------
# TERMINAL DETECTION
#-------------------------------------------------------------------------------
detect_terminal() {
    # Check if stdout is a terminal
    if [[ -t 1 ]]; then
        IS_TTY=1
    else
        IS_TTY=0
    fi
    
    # Check for UTF-8 support
    HAS_UTF8=0
    local locale_vars="${LANG:-}${LC_ALL:-}${LC_CTYPE:-}"
    case "$locale_vars" in
        *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) HAS_UTF8=1 ;;
    esac
    
    # Double-check with locale command if available
    if [[ "$HAS_UTF8" -eq 0 ]] && command -v locale >/dev/null 2>&1; then
        if locale charmap 2>/dev/null | grep -qi "utf-\?8"; then
            HAS_UTF8=1
        fi
    fi
    
    # Check terminal type
    case "${TERM:-dumb}" in
        dumb|unknown|"")
            IS_SMART_TERM=0
            ;;
        linux|cons*|vt100|vt220)
            # Basic terminals - limited capability
            IS_SMART_TERM=1
            HAS_UTF8=0  # These often don't handle UTF-8 well
            ;;
        *)
            IS_SMART_TERM=1
            ;;
    esac
}

#-------------------------------------------------------------------------------
# COLOR SETUP (portable)
#-------------------------------------------------------------------------------
setup_colors() {
    # Start with no colors
    R="" G="" Y="" B="" C="" W="" D="" BD="" RS=""
    
    # Skip colors if:
    # - Not a TTY
    # - TERM is dumb
    # - NO_COLOR environment variable is set (standard)
    # - F5LM_NO_COLOR is set (our own)
    if [[ "$IS_TTY" -eq 0 || "$IS_SMART_TERM" -eq 0 ]]; then
        return
    fi
    
    if [[ -n "${NO_COLOR:-}" || -n "${F5LM_NO_COLOR:-}" ]]; then
        return
    fi
    
    # Method 1: Try tput (most portable)
    if command -v tput >/dev/null 2>&1; then
        local ncolors
        ncolors=$(tput colors 2>/dev/null) || ncolors=0
        
        if [[ "$ncolors" -ge 8 ]]; then
            R=$(tput setaf 1 2>/dev/null) || R=""
            G=$(tput setaf 2 2>/dev/null) || G=""
            Y=$(tput setaf 3 2>/dev/null) || Y=""
            B=$(tput setaf 4 2>/dev/null) || B=""
            C=$(tput setaf 6 2>/dev/null) || C=""
            W=$(tput setaf 7 2>/dev/null) || W=""
            BD=$(tput bold 2>/dev/null) || BD=""
            D=$(tput dim 2>/dev/null) || D=""  # May not be available
            RS=$(tput sgr0 2>/dev/null) || RS=""
            return
        fi
    fi
    
    # Method 2: ANSI escape codes (fallback)
    # Using printf to avoid issues with echo -e variations
    R=$(printf '\033[31m')
    G=$(printf '\033[32m')
    Y=$(printf '\033[33m')
    B=$(printf '\033[34m')
    C=$(printf '\033[36m')
    W=$(printf '\033[37m')
    BD=$(printf '\033[1m')
    D=$(printf '\033[2m')
    RS=$(printf '\033[0m')
}

#-------------------------------------------------------------------------------
# SYMBOL SETUP (ASCII fallback for non-UTF8)
#-------------------------------------------------------------------------------
setup_symbols() {
    if [[ "$HAS_UTF8" -eq 1 && "$IS_SMART_TERM" -eq 1 ]]; then
        # Unicode symbols
        SYM_OK="●"
        SYM_WARN="●"
        SYM_ERR="●"
        SYM_PENDING="○"
        SYM_WAIT="◌"
        SYM_ARROW=">>>"
    else
        # ASCII fallback - works everywhere
        SYM_OK="*"
        SYM_WARN="!"
        SYM_ERR="x"
        SYM_PENDING="o"
        SYM_WAIT="~"
        SYM_ARROW=">>>"
    fi
}

#-------------------------------------------------------------------------------
# DATA DIRECTORY SETUP
#-------------------------------------------------------------------------------
setup_data_dir() {
    # Respect XDG Base Directory Specification
    if [[ -n "${XDG_DATA_HOME:-}" ]]; then
        DATA_DIR="${XDG_DATA_HOME}/f5lm"
    elif [[ -n "${HOME:-}" ]]; then
        DATA_DIR="${HOME}/.f5lm"
    else
        DATA_DIR="/tmp/f5lm.$$"
    fi
    
    DB_FILE="${DATA_DIR}/devices.json"
    LOG_FILE="${DATA_DIR}/history.log"
    HIST_FILE="${DATA_DIR}/.cmd_history"
    LOCK_FILE="${DATA_DIR}/.lock"
}

#-------------------------------------------------------------------------------
# OUTPUT FUNCTIONS
#-------------------------------------------------------------------------------
# Safe echo - handles special characters
out() {
    printf '%s\n' "$*"
}

# Formatted messages
msg()      { printf '%b\n' "$1"; }
msg_ok()   { printf '  %b[OK]%b %s\n' "$G" "$RS" "$1"; }
msg_err()  { printf '  %b[ERROR]%b %s\n' "$R" "$RS" "$1" >&2; }
msg_warn() { printf '  %b[WARN]%b %s\n' "$Y" "$RS" "$1"; }
msg_info() { printf '  %b%s%b %s\n' "$C" "$SYM_ARROW" "$RS" "$1"; }

# Fatal error and exit
die() {
    msg_err "$1"
    exit "${2:-$EXIT_ERROR}"
}

# Draw horizontal line (pure ASCII)
draw_line() {
    local width="${1:-70}"
    printf '  '
    local i=0
    while [[ $i -lt $width ]]; do
        printf '-'
        i=$((i + 1))
    done
    printf '\n'
}

# Log event with timestamp
log_event() {
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null) || ts="$(date)"
    printf '[%s] %s\n' "$ts" "$1" >> "$LOG_FILE" 2>/dev/null || true
}

#-------------------------------------------------------------------------------
# DEPENDENCY CHECKS
#-------------------------------------------------------------------------------
check_bash_version() {
    if [[ -z "${BASH_VERSION:-}" ]]; then
        echo "Error: This script requires bash" >&2
        echo "Current shell: $0" >&2
        exit $EXIT_DEPENDENCY
    fi
    
    local major="${BASH_VERSION%%.*}"
    if [[ "$major" -lt 3 ]]; then
        echo "Error: Bash 3.2+ required (found: $BASH_VERSION)" >&2
        exit $EXIT_DEPENDENCY
    fi
    
    # Warn about very old bash
    if [[ "$major" -eq 3 ]]; then
        : # Old bash - some features may be limited
    fi
}

check_dependencies() {
    local missing=""
    local cmd
    
    # Required commands
    for cmd in curl jq; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing="${missing} $cmd"
        fi
    done
    
    if [[ -n "$missing" ]]; then
        die "Missing required tools:$missing

Install with:
  Debian/Ubuntu: sudo apt-get install$missing
  RHEL/CentOS:   sudo yum install$missing
  Fedora:        sudo dnf install$missing
  macOS:         brew install$missing
  Alpine:        apk add$missing
  Arch:          pacman -S$missing" $EXIT_DEPENDENCY
    fi
    
    # Optional: sshpass for SSH automation
    if ! command -v sshpass >/dev/null 2>&1; then
        HAS_SSHPASS=0
    else
        HAS_SSHPASS=1
    fi
}

#-------------------------------------------------------------------------------
# DATA INITIALIZATION
#-------------------------------------------------------------------------------
init_data() {
    # Create data directory
    if ! mkdir -p "$DATA_DIR" 2>/dev/null; then
        die "Cannot create directory: $DATA_DIR"
    fi
    
    # Check directory is writable
    if [[ ! -w "$DATA_DIR" ]]; then
        die "Directory not writable: $DATA_DIR"
    fi
    
    # Initialize database file
    if [[ ! -f "$DB_FILE" ]]; then
        printf '[]' > "$DB_FILE" || die "Cannot create: $DB_FILE"
    fi
    
    # Validate JSON - recover if corrupted
    if ! jq empty "$DB_FILE" 2>/dev/null; then
        msg_warn "Database corrupted, creating backup"
        local backup="${DB_FILE}.bak.$(date +%s)"
        cp "$DB_FILE" "$backup" 2>/dev/null || true
        printf '[]' > "$DB_FILE"
        msg_warn "Backup saved to: $backup"
    fi
    
    # Create other files
    touch "$LOG_FILE" 2>/dev/null || true
    touch "$HIST_FILE" 2>/dev/null || true
}

#-------------------------------------------------------------------------------
# DATABASE FUNCTIONS
#-------------------------------------------------------------------------------
db_count() {
    jq 'if type == "array" then length else 0 end' "$DB_FILE" 2>/dev/null || echo "0"
}

db_exists() {
    local ip="$1"
    [[ -z "$ip" ]] && return 1
    jq -e --arg ip "$ip" 'if type == "array" then .[] | select(.ip == $ip) else empty end' \
        "$DB_FILE" >/dev/null 2>&1
}

db_get() {
    local ip="$1"
    [[ -z "$ip" ]] && return 1
    jq --arg ip "$ip" '.[] | select(.ip == $ip)' "$DB_FILE" 2>/dev/null
}

db_add() {
    local ip="$1"
    local auth_type="${2:-}"  # "key" or "password"
    local ts
    ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null) || ts=$(date '+%Y-%m-%dT%H:%M:%SZ')
    
    local tmp
    tmp=$(make_temp_file "f5lm_db") || return 1
    
    if jq --arg ip "$ip" --arg ts "$ts" --arg auth "${auth_type:-}" \
        'if type == "array" then . else [] end | 
         . + [{"ip":$ip,"added":$ts,"checked":null,"expires":null,"days":null,"status":"new","regkey":null,"auth_type":$auth}]' \
        "$DB_FILE" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$DB_FILE" && log_event "ADDED $ip" && return 0
    fi
    
    rm -f "$tmp" 2>/dev/null
    return 1
}

# Update device auth settings
db_update_auth() {
    local ip="$1"
    local auth_type="$2"
    
    local tmp
    tmp=$(make_temp_file "f5lm_db") || return 1
    
    if jq --arg ip "$ip" --arg auth "$auth_type" \
        '(.[] | select(.ip == $ip)) |= . + {auth_type:$auth}' \
        "$DB_FILE" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$DB_FILE" && return 0
    fi
    
    rm -f "$tmp" 2>/dev/null
    return 1
}

# Get device auth type
db_get_auth_type() {
    local ip="$1"
    jq -r --arg ip "$ip" '.[] | select(.ip == $ip) | .auth_type // ""' "$DB_FILE" 2>/dev/null
}

db_update() {
    local ip="$1" expires="$2" days="$3" status="$4" regkey="$5"
    local ts
    ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null) || ts=$(date '+%Y-%m-%dT%H:%M:%SZ')
    
    local tmp
    tmp=$(make_temp_file "f5lm_db") || return 1
    
    if jq --arg ip "$ip" --arg ts "$ts" --arg exp "$expires" \
          --arg d "$days" --arg st "$status" --arg rk "$regkey" \
        '(.[] | select(.ip == $ip)) |= . + {checked:$ts, expires:$exp, days:$d, status:$st, regkey:$rk}' \
        "$DB_FILE" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$DB_FILE" && return 0
    fi
    
    rm -f "$tmp" 2>/dev/null
    return 1
}

db_remove() {
    local ip="$1"
    
    local tmp
    tmp=$(make_temp_file "f5lm_db") || return 1
    
    if jq --arg ip "$ip" 'del(.[] | select(.ip == $ip))' "$DB_FILE" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$DB_FILE" && log_event "REMOVED $ip" && return 0
    fi
    
    rm -f "$tmp" 2>/dev/null
    return 1
}

#-------------------------------------------------------------------------------
# CREDENTIAL HANDLING
#-------------------------------------------------------------------------------
#-------------------------------------------------------------------------------
# PER-DEVICE CREDENTIAL MANAGEMENT
#-------------------------------------------------------------------------------
# Supports per-device credentials via environment variables:
#   F5_USER_<IP_WITH_UNDERSCORES>=username
#   F5_PASS_<IP_WITH_UNDERSCORES>=password
#   F5_SSH_KEY_<IP_WITH_UNDERSCORES>=path/to/key
#
# Falls back to global: F5_USER, F5_PASS, F5_SSH_KEY
# Then prompts interactively if not found

# Convert IP to env var suffix (replace . and : with _)
_ip_to_env_suffix() {
    local ip="$1"
    echo "${ip//[.:]/_}"
}

# Get credential for a specific device (checks per-device, then global, then returns empty)
_get_device_credential() {
    local ip="$1"
    local var_name="$2"  # USER, PASS, or SSH_KEY
    
    local suffix
    suffix=$(_ip_to_env_suffix "$ip")
    
    # Check per-device variable first (from actual environment)
    local per_device_var="F5_${var_name}_${suffix}"
    local value
    value=$(printenv "$per_device_var" 2>/dev/null)
    
    if [[ -n "$value" ]]; then
        echo "$value"
        return 0
    fi
    
    # Fall back to global variable (from actual environment)
    local global_var="F5_${var_name}"
    value=$(printenv "$global_var" 2>/dev/null)
    
    if [[ -n "$value" ]]; then
        echo "$value"
        return 0
    fi
    
    return 1
}

# Load credentials for a specific device into F5_USER, F5_PASS, F5_SSH_KEY
# Returns 0 if credentials found (from env), 1 if need to prompt
# Only checks actual environment variables, not current shell variables
load_device_credentials() {
    local ip="$1"
    
    # Try to get per-device or global credentials from actual env vars only
    local env_user env_pass env_key
    env_user=$(_get_device_credential "$ip" "USER")
    env_pass=$(_get_device_credential "$ip" "PASS")
    env_key=$(_get_device_credential "$ip" "SSH_KEY")
    
    # Check if we found credentials in environment
    if [[ -n "$env_user" ]]; then
        F5_USER="$env_user"
        F5_PASS="$env_pass"
        F5_SSH_KEY="$env_key"
        return 0
    fi
    
    # No credentials found in environment
    return 1
}

# Check if device has credentials configured (env vars only)
has_device_credentials() {
    local ip="$1"
    local user
    user=$(_get_device_credential "$ip" "USER")
    [[ -n "$user" ]]
}

prompt_credentials() {
    local context="${1:-}"
    local ip="${context:-}"
    
    # Clear any stale credentials from previous operations
    F5_USER=""
    F5_PASS=""
    F5_SSH_KEY=""
    
    # Try to load credentials from env vars first
    if [[ -n "$ip" ]] && load_device_credentials "$ip"; then
        return 0
    fi
    
    # Get stored auth type for this device
    local db_auth_type=""
    if [[ -n "$ip" ]]; then
        db_auth_type=$(db_get_auth_type "$ip")
    fi
    
    printf '\n'
    msg "  ${C}Enter F5 Credentials${RS}"
    if [[ -n "$context" ]]; then
        msg "  ${D}For: ${context}${RS}"
    fi
    
    # Show auth type if stored
    if [[ "$db_auth_type" == "key" ]]; then
        msg "  ${D}Auth: SSH Key${RS}"
    elif [[ "$db_auth_type" == "password" ]]; then
        msg "  ${D}Auth: Password${RS}"
    fi
    printf '\n'
    
    # Always prompt for username
    printf '  Username: '
    read -r F5_USER
    
    if [[ -z "$F5_USER" ]]; then
        msg_err "Username required"
        return 1
    fi
    
    # If stored auth type is key, prompt for key path
    if [[ "$db_auth_type" == "key" ]]; then
        F5_PASS=""
        local default_key="$HOME/.ssh/id_rsa"
        printf '  SSH Key [%s]: ' "$default_key"
        read -r F5_SSH_KEY
        [[ -z "$F5_SSH_KEY" ]] && F5_SSH_KEY="$default_key"
        
        # Expand ~ if present
        F5_SSH_KEY="${F5_SSH_KEY/#\~/$HOME}"
        
        if [[ ! -f "$F5_SSH_KEY" ]]; then
            msg_err "SSH key not found: $F5_SSH_KEY"
            return 1
        fi
        
        msg "  ${D}Using SSH key: $F5_SSH_KEY${RS}"
        printf '\n'
        return 0
    fi
    
    # If stored auth type is password, prompt for password
    if [[ "$db_auth_type" == "password" ]]; then
        F5_SSH_KEY=""
        printf '  Password: '
        read -rs F5_PASS
        printf '\n\n'
        if [[ -z "$F5_PASS" ]]; then
            msg_err "Password required"
            return 1
        fi
        return 0
    fi
    
    # No stored auth type - allow either (leave password empty for key auth)
    msg "  ${D}(Leave password empty for SSH key authentication)${RS}"
    printf '  Password: '
    read -rs F5_PASS
    printf '\n'
    
    if [[ -z "$F5_PASS" ]]; then
        # Key auth - prompt for key path
        local default_key="$HOME/.ssh/id_rsa"
        printf '  SSH Key [%s]: ' "$default_key"
        read -r F5_SSH_KEY
        [[ -z "$F5_SSH_KEY" ]] && F5_SSH_KEY="$default_key"
        
        # Expand ~ if present
        F5_SSH_KEY="${F5_SSH_KEY/#\~/$HOME}"
        
        if [[ ! -f "$F5_SSH_KEY" ]]; then
            msg_err "SSH key not found: $F5_SSH_KEY"
            return 1
        fi
        
        msg "  ${D}Using SSH key: $F5_SSH_KEY${RS}"
    fi
    printf '\n'
    
    return 0
}

# JSON-escape a string (handle special characters in passwords)
json_escape() {
    local str="$1"
    # Escape backslash, double quote, and control characters
    str="${str//\\/\\\\}"      # Backslash
    str="${str//\"/\\\"}"      # Double quote
    str="${str//$'\n'/\\n}"    # Newline
    str="${str//$'\r'/\\r}"    # Carriage return
    str="${str//$'\t'/\\t}"    # Tab
    printf '%s' "$str"
}

#-------------------------------------------------------------------------------
# DATE HANDLING (Cross-platform)
#-------------------------------------------------------------------------------
# Convert date string to Unix timestamp
parse_date_to_ts() {
    local date_str="$1"
    local ts
    
    # Handle empty/null
    [[ -z "$date_str" || "$date_str" == "null" ]] && return 1
    
    # Normalize: replace / with -
    local normalized="${date_str//\//-}"
    
    # Method 1: GNU date (Linux)
    ts=$(date -d "$normalized" '+%s' 2>/dev/null) && printf '%s' "$ts" && return 0
    
    # Method 2: BSD date (macOS, FreeBSD)
    ts=$(date -j -f "%Y-%m-%d" "$normalized" '+%s' 2>/dev/null) && printf '%s' "$ts" && return 0
    
    # Method 3: BSD date with original format
    ts=$(date -j -f "%Y/%m/%d" "$date_str" '+%s' 2>/dev/null) && printf '%s' "$ts" && return 0
    
    # Method 4: Parse manually (YYYY-MM-DD or YYYY/MM/DD)
    if [[ "$date_str" =~ ^([0-9]{4})[-/]([0-9]{2})[-/]([0-9]{2})$ ]]; then
        local year="${BASH_REMATCH[1]}"
        local month="${BASH_REMATCH[2]}"
        local day="${BASH_REMATCH[3]}"
        # Approximate calculation (not accounting for leap years precisely)
        local days_since_epoch=$(( (year - 1970) * 365 + (year - 1969) / 4 + (month - 1) * 30 + day ))
        ts=$((days_since_epoch * 86400))
        printf '%s' "$ts"
        return 0
    fi
    
    return 1
}

# Calculate days until expiry
calc_days_until() {
    local expiry="$1"
    
    # Handle special cases - empty or null means perpetual
    if [[ -z "$expiry" || "$expiry" == "null" || "$expiry" == "N/A" ]]; then
        printf 'perpetual'
        return
    fi
    
    # Perpetual license indicators
    case "$expiry" in
        [Pp]erpetual|[Uu]nlimited|[Nn]ever|[Nn]one)
            printf 'perpetual'
            return
            ;;
    esac
    
    local exp_ts now_ts
    
    exp_ts=$(parse_date_to_ts "$expiry") || { printf '?'; return; }
    now_ts=$(date '+%s' 2>/dev/null) || { printf '?'; return; }
    
    printf '%s' "$(( (exp_ts - now_ts) / 86400 ))"
}

# Get status from days remaining
get_status_from_days() {
    local days="$1"
    
    case "$days" in
        "perpetual"|"unlimited")
            printf 'perpetual'
            return
            ;;
        "?"|"")
            printf 'unknown'
            return
            ;;
    esac
    
    # Validate numeric
    case "$days" in
        -[0-9]*|[0-9]*)
            : # Valid number
            ;;
        *)
            printf 'unknown'
            return
            ;;
    esac
    
    if [[ "$days" -lt 0 ]]; then
        printf 'expired'
    elif [[ "$days" -le 30 ]]; then
        printf 'expiring'
    else
        printf 'active'
    fi
}

#-------------------------------------------------------------------------------
# PORTABLE TIMEOUT WRAPPER
#-------------------------------------------------------------------------------
run_with_timeout() {
    local seconds="$1"
    shift
    
    if [[ "$HAS_TIMEOUT" -eq 1 ]]; then
        timeout "$seconds" "$@"
    else
        # Fallback: just run without timeout
        # Note: This is less ideal but maintains compatibility
        "$@"
    fi
}

#-------------------------------------------------------------------------------
# F5 REST API FUNCTIONS
#-------------------------------------------------------------------------------
f5_auth() {
    local ip="$1"
    local timeout_sec="${2:-20}"
    
    local user_escaped pass_escaped
    user_escaped=$(json_escape "$F5_USER")
    pass_escaped=$(json_escape "$F5_PASS")
    
    local payload="{\"username\":\"${user_escaped}\",\"password\":\"${pass_escaped}\",\"loginProviderName\":\"tmos\"}"
    
    run_with_timeout "$timeout_sec" \
        curl -sk -X POST "https://${ip}/mgmt/shared/authn/login" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>/dev/null
}

f5_get_license() {
    local ip="$1"
    local token="$2"
    local timeout_sec="${3:-20}"
    
    run_with_timeout "$timeout_sec" \
        curl -sk "https://${ip}/mgmt/tm/sys/license" \
        -H "X-F5-Auth-Token: $token" 2>/dev/null
}

f5_get_dossier() {
    local ip="$1"
    local token="$2"
    local regkey="$3"
    local timeout_sec="${4:-30}"
    
    local regkey_escaped
    regkey_escaped=$(json_escape "$regkey")
    
    run_with_timeout "$timeout_sec" \
        curl -sk -X POST "https://${ip}/mgmt/tm/shared/licensing/dossier" \
        -H "Content-Type: application/json" \
        -H "X-F5-Auth-Token: $token" \
        -d "{\"registrationKey\":\"${regkey_escaped}\"}" 2>/dev/null
}

f5_install_license() {
    local ip="$1"
    local token="$2"
    local regkey="$3"
    local timeout_sec="${4:-60}"
    
    local regkey_escaped
    regkey_escaped=$(json_escape "$regkey")
    
    run_with_timeout "$timeout_sec" \
        curl -sk -X POST "https://${ip}/mgmt/tm/sys/license" \
        -H "Content-Type: application/json" \
        -H "X-F5-Auth-Token: $token" \
        -d "{\"command\":\"install\",\"registrationKey\":\"${regkey_escaped}\"}" 2>/dev/null
}

# Parse license JSON response
parse_license_info() {
    local json="$1"
    printf '%s' "$json" | jq -r '
        .entries | to_entries[] | select(.key | contains("/license/")) |
        .value.nestedStats.entries |
        "\(.registrationKey.description // "")|\(.licenseEndDate.description // "")"
    ' 2>/dev/null | head -1
}

#-------------------------------------------------------------------------------
# SSH OPERATIONS (Key-based and Password-based authentication)
#-------------------------------------------------------------------------------

# Global SSH auth mode: "key", "password", or "auto"
SSH_AUTH_MODE="${SSH_AUTH_MODE:-auto}"

# Custom SSH key path (optional)
F5_SSH_KEY="${F5_SSH_KEY:-}"

ssh_has_sshpass() {
    command -v sshpass >/dev/null 2>&1
}

# Check if SSH key authentication is available for a host
ssh_has_key_auth() {
    local ip="$1"
    local user="${F5_USER:-root}"
    local key_opts=""
    
    # Add custom key if specified
    if [[ -n "$F5_SSH_KEY" && -f "$F5_SSH_KEY" ]]; then
        key_opts="-i $F5_SSH_KEY"
    fi
    
    # Try SSH with BatchMode (fails immediately if key auth not available)
    # Using a short timeout and checking exit status
    ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        -o ConnectTimeout=5 \
        -o BatchMode=yes \
        -o PasswordAuthentication=no \
        $key_opts \
        "$user@$ip" "echo ok" 2>/dev/null
    
    return $?
}

# Test SSH key authentication (for display/info)
ssh_test_key_auth() {
    local ip="$1"
    local user="${F5_USER:-root}"
    
    if ssh_has_key_auth "$ip"; then
        return 0
    fi
    return 1
}

# Get SSH options based on auth mode
# Returns options as an array-safe string
_ssh_get_opts() {
    echo "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10"
}

# Get SSH key option if key is specified
_ssh_get_key_opt() {
    if [[ -n "$F5_SSH_KEY" && -f "$F5_SSH_KEY" ]]; then
        echo "-i"
        echo "$F5_SSH_KEY"
    fi
}

#-------------------------------------------------------------------------------
# SSH COMMAND WRAPPER FOR TMOS/BASH SHELL HANDLING
#-------------------------------------------------------------------------------
# F5 devices can drop users into either:
#   TMOS prompt: azadmin@(bigip-v21)(cfg-sync Standalone)(Active)(/Common)(tmos)#
#   Bash prompt: [azadmin@bigip-v21:Active:Standalone] ~ #
#
# Commands like tmsh, get_dossier, reloadlic need to run in bash context.
# This wrapper ensures commands work regardless of which shell the user lands in.

# SSH command for key-based authentication
# Handles TMOS/bash shell by running command directly (F5 executes via bash anyway)
_f5_ssh_cmd() {
    local ip="$1"
    local cmd="$2"
    local timeout_sec="${3:-15}"
    
    local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10 -o BatchMode=yes -o PasswordAuthentication=no"
    
    local result=""
    local rc=0
    
    if command -v timeout >/dev/null 2>&1; then
        if [[ -n "$F5_SSH_KEY" && -f "$F5_SSH_KEY" ]]; then
            result=$(timeout "$timeout_sec" ssh $ssh_opts -i "$F5_SSH_KEY" "$F5_USER@$ip" "$cmd" 2>&1)
            rc=$?
        else
            result=$(timeout "$timeout_sec" ssh $ssh_opts "$F5_USER@$ip" "$cmd" 2>&1)
            rc=$?
        fi
    else
        if [[ -n "$F5_SSH_KEY" && -f "$F5_SSH_KEY" ]]; then
            result=$(ssh $ssh_opts -i "$F5_SSH_KEY" "$F5_USER@$ip" "$cmd" 2>&1)
            rc=$?
        else
            result=$(ssh $ssh_opts "$F5_USER@$ip" "$cmd" 2>&1)
            rc=$?
        fi
    fi
    
    # Filter out SSH warnings/errors from result, but keep command output
    echo "$result" | grep -v "^Warning:" | grep -v "^Permission denied"
    return $rc
}

# SSH command for password auth (uses sshpass if available)
_f5_ssh_cmd_pass() {
    local ip="$1"
    local cmd="$2"
    local timeout_sec="${3:-15}"
    
    local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10"
    
    local result=""
    local rc=0
    
    if command -v timeout >/dev/null 2>&1; then
        if ssh_has_sshpass && [[ -n "$F5_PASS" ]]; then
            result=$(timeout "$timeout_sec" sshpass -p "$F5_PASS" ssh $ssh_opts "$F5_USER@$ip" "$cmd" 2>&1)
            rc=$?
        else
            result=$(timeout "$timeout_sec" ssh $ssh_opts "$F5_USER@$ip" "$cmd" 2>&1)
            rc=$?
        fi
    else
        if ssh_has_sshpass && [[ -n "$F5_PASS" ]]; then
            result=$(sshpass -p "$F5_PASS" ssh $ssh_opts "$F5_USER@$ip" "$cmd" 2>&1)
            rc=$?
        else
            result=$(ssh $ssh_opts "$F5_USER@$ip" "$cmd" 2>&1)
            rc=$?
        fi
    fi
    
    echo "$result" | grep -v "^Warning:" | grep -v "^Permission denied"
    return $rc
}

# Execute SSH command with automatic auth method selection
ssh_exec() {
    local ip="$1"
    local cmd="$2"
    local timeout="${3:-30}"
    
    local ssh_opts
    ssh_opts=$(_ssh_get_opts)
    
    # Determine auth method
    local use_key=0
    
    if [[ "$SSH_AUTH_MODE" == "key" ]]; then
        use_key=1
    elif [[ "$SSH_AUTH_MODE" == "password" ]]; then
        use_key=0
    else
        # Auto mode: try key first if no password provided, or test key auth
        if [[ -z "$F5_PASS" ]] || ssh_has_key_auth "$ip" 2>/dev/null; then
            use_key=1
        fi
    fi
    
    if [[ $use_key -eq 1 ]]; then
        # Key-based authentication
        ssh $ssh_opts -o BatchMode=yes -o PasswordAuthentication=no -T "$F5_USER@$ip" "$cmd" 2>/dev/null
    elif ssh_has_sshpass && [[ -n "$F5_PASS" ]]; then
        # Password authentication with sshpass
        sshpass -p "$F5_PASS" ssh $ssh_opts -T "$F5_USER@$ip" "$cmd" 2>/dev/null
    elif [[ -n "$F5_PASS" ]]; then
        # Try without sshpass (will prompt or use key)
        ssh $ssh_opts -T "$F5_USER@$ip" "$cmd" 2>/dev/null
    else
        # No password, try key auth
        ssh $ssh_opts -o BatchMode=yes -T "$F5_USER@$ip" "$cmd" 2>/dev/null
    fi
}

ssh_exec_with_pty() {
    local ip="$1"
    local cmd="$2"
    
    local ssh_opts
    ssh_opts=$(_ssh_get_opts)
    
    # Try key auth first
    if [[ -z "$F5_PASS" ]] || [[ "$SSH_AUTH_MODE" == "key" ]]; then
        ssh $ssh_opts -o BatchMode=yes -tt "$F5_USER@$ip" "$cmd" 2>/dev/null
        [[ $? -eq 0 ]] && return 0
    fi
    
    # Fall back to password auth
    if command -v expect >/dev/null 2>&1 && [[ -n "$F5_PASS" ]]; then
        expect -c "
            log_user 0
            set timeout 30
            spawn ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR $F5_USER@$ip
            expect {
                \"*assword*\" { send \"$F5_PASS\r\"; exp_continue }
                \"*#*\" { send \"$cmd\r\" }
                \"*>*\" { send \"$cmd\r\" }
                timeout { exit 1 }
            }
            expect {
                \"*#*\" { }
                \"*>*\" { }
                timeout { exit 1 }
            }
            log_user 1
            puts \$expect_out(buffer)
        " 2>/dev/null
    elif ssh_has_sshpass && [[ -n "$F5_PASS" ]]; then
        sshpass -p "$F5_PASS" ssh $ssh_opts -tt "$F5_USER@$ip" "$cmd" 2>/dev/null
    else
        return 1
    fi
}

# Run command on F5 bash shell
f5_ssh_bash() {
    local ip="$1"
    local bash_cmd="$2"
    
    # The command needs to run in bash context on F5
    # F5 drops you into tmsh by default for admin, so we need to call bash -c
    ssh_exec "$ip" "bash -c '$bash_cmd'"
}

# Get dossier via SSH
f5_ssh_dossier() {
    local ip="$1"
    local regkey="$2"
    
    # Run get_dossier command
    f5_ssh_bash "$ip" "get_dossier -b $regkey 2>/dev/null"
}

#-------------------------------------------------------------------------------
# UI: HEADER
#-------------------------------------------------------------------------------
show_header() {
    # Clear screen if possible
    if [[ "$IS_SMART_TERM" -eq 1 ]]; then
        # Try multiple methods
        clear 2>/dev/null || printf '\033[2J\033[H' 2>/dev/null || printf '\n\n\n'
    fi
    
    printf '\n'
    
    if [[ "$HAS_UTF8" -eq 1 && "$IS_SMART_TERM" -eq 1 ]]; then
        # Unicode header
        printf '  %b███████╗%b%b███████╗%b   %bLicense Manager%b %bv%s%b\n' \
            "$R" "$RS" "$BD" "$RS" "$C" "$RS" "$D" "$F5LM_VERSION" "$RS"
        printf '  %b██╔════╝%b%b██╔════╝%b   %bF5 BIG-IP License Lifecycle Tool%b\n' \
            "$R" "$RS" "$BD" "$RS" "$D" "$RS"
        printf '  %b█████╗  %b%b███████╗%b\n' "$R" "$RS" "$BD" "$RS"
        printf '  %b██╔══╝  %b%b╚════██║%b   %bType %bhelp%b for commands%b\n' \
            "$R" "$RS" "$BD" "$RS" "$D" "$RS" "$D" "$RS"
        printf '  %b██║     %b%b███████║%b\n' "$R" "$RS" "$BD" "$RS"
        printf '  %b╚═╝     %b%b╚══════╝%b\n' "$R" "$RS" "$BD" "$RS"
    else
        # ASCII header
        printf '  ======================================\n'
        printf '   F5 LICENSE MANAGER v%s\n' "$F5LM_VERSION"
        printf '   F5 BIG-IP License Lifecycle Tool\n'
        printf '  --------------------------------------\n'
        printf '   Type "help" for commands\n'
        printf '  ======================================\n'
    fi
    
    printf '\n'
    draw_line 74
}

#-------------------------------------------------------------------------------
# UI: DASHBOARD
#-------------------------------------------------------------------------------
show_stats() {
    local total active expiring expired
    
    total=$(jq 'length' "$DB_FILE" 2>/dev/null) || total=0
    active=$(jq '[.[] | select(.status=="active")] | length' "$DB_FILE" 2>/dev/null) || active=0
    expiring=$(jq '[.[] | select(.status=="expiring")] | length' "$DB_FILE" 2>/dev/null) || expiring=0
    expired=$(jq '[.[] | select(.status=="expired")] | length' "$DB_FILE" 2>/dev/null) || expired=0
    
    printf '\n'
    printf '  %bOVERVIEW%b\n' "$BD" "$RS"
    printf '\n'
    printf '  %-12s %-12s %-12s %-12s\n' "TOTAL" "ACTIVE" "EXPIRING" "EXPIRED"
    printf '  %b%-12s%b %b%-12s%b %b%-12s%b %b%-12s%b\n' \
        "$BD" "$total" "$RS" "$G" "$active" "$RS" "$Y" "$expiring" "$RS" "$R" "$expired" "$RS"
    printf '\n'
}

#-------------------------------------------------------------------------------
# UI: DEVICE LIST
#-------------------------------------------------------------------------------
show_devices() {
    local count
    count=$(db_count)
    
    printf '  %bDEVICES%b\n' "$BD" "$RS"
    printf '\n'
    
    if [[ "$count" -eq 0 || "$count" == "0" ]]; then
        printf '  %bNo devices yet. Use %badd <ip>%b to add one.%b\n' "$D" "$RS" "$D" "$RS"
        printf '\n'
        return
    fi
    
    printf '  %b%-3s %-18s %-14s %-10s %-12s%b\n' "$D" "#" "IP ADDRESS" "EXPIRES" "DAYS" "STATUS" "$RS"
    draw_line 60
    
    local i=0
    while [[ "$i" -lt "$count" ]]; do
        local ip expires days status
        local status_sym status_color days_display
        
        ip=$(jq -r ".[$i].ip // \"\"" "$DB_FILE" 2>/dev/null)
        expires=$(jq -r ".[$i].expires // \"-\"" "$DB_FILE" 2>/dev/null)
        days=$(jq -r ".[$i].days // \"?\"" "$DB_FILE" 2>/dev/null)
        status=$(jq -r ".[$i].status // \"new\"" "$DB_FILE" 2>/dev/null)
        
        # Handle null strings
        [[ "$expires" == "null" ]] && expires="-"
        [[ "$days" == "null" ]] && days="?"
        [[ "$status" == "null" ]] && status="new"
        
        # Status formatting
        case "$status" in
            perpetual) status_sym="$SYM_OK"; status_color="$G"; days_display="∞" ;;
            active)    status_sym="$SYM_OK"; status_color="$G"; days_display="$days" ;;
            expiring)  status_sym="$SYM_WARN"; status_color="$Y"; days_display="$days" ;;
            expired)   status_sym="$SYM_ERR"; status_color="$R"; days_display="$days" ;;
            *)         status_sym="$SYM_PENDING"; status_color="$D"; days_display="?" ;;
        esac
        
        printf '  %-3s %-18s %-14s %-10s %b%s %s%b\n' \
            "$((i+1))" "$ip" "${expires:--}" "$days_display" "$status_color" "$status_sym" "$status" "$RS"
        
        i=$((i + 1))
    done
    printf '\n'
}

#-------------------------------------------------------------------------------
# UI: PROMPT
#-------------------------------------------------------------------------------
show_prompt() {
    printf '  %bf5lm%b > ' "$C" "$RS"
}

#-------------------------------------------------------------------------------
# COMMANDS: HELP
#-------------------------------------------------------------------------------
cmd_help() {
    printf '\n'
    printf '  %bCOMMANDS%b\n' "$BD" "$RS"
    printf '\n'
    printf '  %bDevice Management%b\n' "$C" "$RS"
    printf '    %badd%b <ip>              Add device\n' "$BD" "$RS"
    printf '    %badd-multi%b             Add multiple devices\n' "$BD" "$RS"
    printf '    %bremove%b <ip>           Remove device\n' "$BD" "$RS"
    printf '    %blist%b                  Show all devices\n' "$BD" "$RS"
    printf '\n'
    printf '  %bLicense Operations%b\n' "$C" "$RS"
    printf '    %bcheck%b [ip|all]        Check license status\n' "$BD" "$RS"
    printf '    %bdetails%b <ip>          Full license info\n' "$BD" "$RS"
    printf '    %brenew%b <ip> <key>      Apply registration key\n' "$BD" "$RS"
    printf '    %breload%b <ip>           Reload license (SSH)\n' "$BD" "$RS"
    printf '    %bdossier%b <ip> [key]    Generate dossier + apply license\n' "$BD" "$RS"
    printf '    %bapply-license%b <ip>    Apply license file/content\n' "$BD" "$RS"
    printf '    %bactivate%b <ip>         Activation wizard\n' "$BD" "$RS"
    printf '\n'
    printf '  %bUtilities%b\n' "$C" "$RS"
    printf '    %bexport%b                Export to CSV\n' "$BD" "$RS"
    printf '    %bhistory%b               Action log\n' "$BD" "$RS"
    printf '    %brefresh%b               Refresh display\n' "$BD" "$RS"
    printf '    %bhelp%b                  This help\n' "$BD" "$RS"
    printf '    %bquit%b                  Exit\n' "$BD" "$RS"
    printf '\n'
    printf '  %bShortcuts: a=add, r=remove, c=check, d=details, q=quit%b\n' "$D" "$RS"
    printf '\n'
    printf '  %bEnvironment Variables%b\n' "$C" "$RS"
    printf '    %bF5_USER%b               SSH/API username\n' "$BD" "$RS"
    printf '    %bF5_PASS%b               SSH/API password (omit for key auth)\n' "$BD" "$RS"
    printf '    %bF5_SSH_KEY%b            Path to SSH private key\n' "$BD" "$RS"
    printf '    %bSSH_AUTH_MODE%b         Force auth: key, password, or auto\n' "$BD" "$RS"
    printf '\n'
    printf '  %bPer-Device Credentials%b (format: VAR_<IP_WITH_UNDERSCORES>)\n' "$C" "$RS"
    printf '    %bF5_USER_10_0_0_1%b      Username for 10.0.0.1\n' "$BD" "$RS"
    printf '    %bF5_PASS_10_0_0_1%b      Password for 10.0.0.1\n' "$BD" "$RS"
    printf '    %bF5_SSH_KEY_10_0_0_1%b   SSH key for 10.0.0.1\n' "$BD" "$RS"
    printf '\n'
}

#-------------------------------------------------------------------------------
# COMMANDS: ADD
#-------------------------------------------------------------------------------

# Get license info via SSH (for key-based auth)
# Uses direct SSH commands - handles both TMOS and bash shell prompts
# For TMOS: tmsh commands work directly
# For Bash: tmsh commands also work directly
_get_license_via_ssh() {
    local ip="$1"
    
    # Try tmsh command first (works from both TMOS and bash)
    local lic_output
    lic_output=$(_f5_ssh_cmd "$ip" "tmsh show sys license" 15)
    local rc=$?
    
    # Check if SSH succeeded
    if [[ $rc -ne 0 ]]; then
        return 1
    fi
    
    # If tmsh failed (might be in bash without tmsh in path), try with full path
    if [[ -z "$lic_output" ]] || echo "$lic_output" | grep -qi "command not found\|not found"; then
        lic_output=$(_f5_ssh_cmd "$ip" "/usr/bin/tmsh show sys license" 15)
    fi
    
    # Parse registration key
    local regkey=""
    regkey=$(echo "$lic_output" | grep -i "Registration Key" | awk '{print $NF}' | head -1)
    
    # Parse expiration date
    local expires=""
    expires=$(echo "$lic_output" | grep -i "Service Check Date" | awk '{print $NF}' | head -1)
    
    # If no expiration from tmsh, try license file directly
    if [[ -z "$expires" ]]; then
        local expires_output
        expires_output=$(_f5_ssh_cmd "$ip" "grep -i 'Service check date' /config/bigip.license" 10)
        expires=$(echo "$expires_output" | sed 's/.*[Ss]ervice [Cc]heck [Dd]ate[: ]*//' | awk '{print $1}')
    fi
    
    # Return in format: regkey|expires
    echo "${regkey}|${expires}"
}

# Internal function to check a single device (no credential prompt)
# Supports both REST API (password) and SSH (key) authentication
_check_single_device() {
    local ip="$1"
    
    printf '  %-20s ' "$ip"
    
    # Check if this device uses key auth
    local db_auth_type
    db_auth_type=$(db_get_auth_type "$ip")
    
    local regkey="" expires=""
    
    if [[ "$db_auth_type" == "key" && -n "$F5_SSH_KEY" && -z "$F5_PASS" ]]; then
        # Use SSH to get license info
        local ssh_result
        ssh_result=$(_get_license_via_ssh "$ip")
        
        if [[ -z "$ssh_result" || "$ssh_result" == "|" ]]; then
            printf '%b%s SSH failed%b\n' "$R" "$SYM_ERR" "$RS"
            return 1
        fi
        
        regkey="${ssh_result%%|*}"
        expires="${ssh_result##*|}"
    else
        # Use REST API (password auth)
        local auth_resp token
        auth_resp=$(f5_auth "$ip" 10)
        token=$(echo "$auth_resp" | jq -r '.token.token // empty' 2>/dev/null)
        
        if [[ -z "$token" ]]; then
            # Determine the reason for failure
            if [[ -z "$auth_resp" ]]; then
                printf '%b%s unreachable%b\n' "$R" "$SYM_ERR" "$RS"
            elif printf '%s' "$auth_resp" | grep -qi "unauthorized\|Authentication failed\|invalid.*credentials\|401"; then
                printf '%b%s auth failed%b\n' "$R" "$SYM_ERR" "$RS"
            else
                printf '%b%s failed%b\n' "$R" "$SYM_ERR" "$RS"
            fi
            return 1
        fi
        
        local lic_json parsed
        lic_json=$(f5_get_license "$ip" "$token" 10)
        parsed=$(parse_license_info "$lic_json")
        regkey="${parsed%%|*}"
        expires="${parsed##*|}"
    fi
    
    if [[ -z "$expires" ]]; then
        printf '%b%s no license data%b\n' "$Y" "$SYM_WAIT" "$RS"
        return 1
    fi
    
    local days status
    days=$(calc_days_until "$expires")
    status=$(get_status_from_days "$days")
    
    db_update "$ip" "$expires" "$days" "$status" "$regkey"
    log_event "CHECKED $ip: $status ($days)"
    
    case "$status" in
        perpetual) printf '%b%s perpetual%b\n' "$G" "$SYM_OK" "$RS" ;;
        active)    printf '%b%s %s days%b\n' "$G" "$SYM_OK" "$days" "$RS" ;;
        expiring)  printf '%b%s %s days%b\n' "$Y" "$SYM_WARN" "$days" "$RS" ;;
        expired)   printf '%b%s EXPIRED%b\n' "$R" "$SYM_ERR" "$RS" ;;
        *)         printf '%b%s unknown%b\n' "$D" "$SYM_PENDING" "$RS" ;;
    esac
    return 0
}

cmd_add() {
    local ip="$1"
    
    # Clean input
    ip="${ip#https://}"
    ip="${ip#http://}"
    ip="${ip%%/*}"
    ip="${ip%%:*}"
    
    if [[ -z "$ip" ]]; then
        msg_err "Usage: add <ip>"
        return 1
    fi
    
    # Basic validation (alphanumeric, dots, dashes)
    if [[ ! "$ip" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        msg_err "Invalid IP/hostname: $ip"
        return 1
    fi
    
    if db_exists "$ip"; then
        msg_warn "$ip already exists"
        return 1
    fi
    
    # Prompt for SSH authentication type
    printf '\n'
    printf '  %bSSH Authentication for %b%s%b\n' "$C" "$BD" "$ip" "$RS"
    printf '\n'
    printf '  %b[1]%b SSH Key (passwordless)\n' "$BD" "$RS"
    printf '  %b[2]%b Password\n' "$BD" "$RS"
    printf '\n'
    printf '  Auth type [1/2]: '
    local auth_choice
    read -r auth_choice
    
    local auth_type
    case "$auth_choice" in
        2)
            auth_type="password"
            ;;
        *)
            auth_type="key"
            ;;
    esac
    
    printf '\n'
    
    if db_add "$ip" "$auth_type"; then
        msg_ok "Added ${BD}$ip${RS} (${auth_type} auth)"
        
        # Prompt for credentials first
        printf '\n'
        printf '  Username: '
        read -r F5_USER
        
        if [[ -z "$F5_USER" ]]; then
            printf '      %bRun "check %s" to fetch license info%b\n' "$D" "$ip" "$RS"
            F5_USER="" F5_PASS="" F5_SSH_KEY=""
            return 0
        fi
        
        if [[ "$auth_type" == "key" ]]; then
            F5_PASS=""
            # Prompt for SSH key path
            local default_key="$HOME/.ssh/id_rsa"
            printf '  SSH Key [%s]: ' "$default_key"
            read -r F5_SSH_KEY
            [[ -z "$F5_SSH_KEY" ]] && F5_SSH_KEY="$default_key"
            
            # Expand ~ if present
            F5_SSH_KEY="${F5_SSH_KEY/#\~/$HOME}"
            
            if [[ ! -f "$F5_SSH_KEY" ]]; then
                msg_err "SSH key not found: $F5_SSH_KEY"
                printf '      %bRun "check %s" to fetch license info%b\n' "$D" "$ip" "$RS"
                F5_USER="" F5_PASS="" F5_SSH_KEY=""
                return 0
            fi
            
            msg "  ${D}Using SSH key: $F5_SSH_KEY${RS}"
        else
            printf '  Password: '
            read -rs F5_PASS
            printf '\n'
            
            if [[ -z "$F5_PASS" ]]; then
                printf '      %bRun "check %s" to fetch license info%b\n' "$D" "$ip" "$RS"
                F5_USER="" F5_PASS="" F5_SSH_KEY=""
                return 0
            fi
        fi
        
        # Now show checking message and perform check
        printf '\n'
        msg_info "Checking license status..."
        _check_single_device "$ip"
        
        # Clear credentials after check
        F5_USER="" F5_PASS="" F5_SSH_KEY=""
    else
        msg_err "Failed to add $ip"
        return 1
    fi
}

cmd_add_multi() {
    printf '\n'
    printf '  %bADD MULTIPLE DEVICES%b\n' "$BD" "$RS"
    printf '  %bEnter IPs, one per line. Empty line to finish.%b\n' "$D" "$RS"
    printf '\n'
    
    local count=0
    local ip
    local added_ips=""
    
    while true; do
        printf "  IP: "; read -r ip
        [[ -z "$ip" ]] && break
        
        # Clean
        ip="${ip#https://}"
        ip="${ip#http://}"
        ip="${ip%%/*}"
        ip="${ip%%:*}"
        
        if db_exists "$ip"; then
            msg_warn "$ip already exists"
            continue
        fi
        
        # Prompt for auth type only
        printf '    Auth [1=key, 2=password]: '
        local auth_choice
        read -r auth_choice
        local auth_type="key"
        [[ "$auth_choice" == "2" ]] && auth_type="password"
        
        if db_add "$ip" "$auth_type"; then
            msg_ok "Added $ip ($auth_type auth)"
            added_ips="$added_ips $ip"
            count=$((count + 1))
        else
            msg_err "Failed: $ip"
        fi
    done
    
    printf '\n'
    
    if [[ $count -eq 0 ]]; then
        msg_warn "No devices added"
        return
    fi
    
    msg_ok "Added $count device(s)"
    
    # Auto-check all added devices
    printf '\n'
    printf '  %bChecking license status...%b\n' "$BD" "$RS"
    printf '\n'
    
    local ok=0 fail=0 skipped=0
    local current_user="" current_pass="" current_key=""
    
    for ip in $added_ips; do
        local db_auth_type
        db_auth_type=$(db_get_auth_type "$ip")
        
        # Always prompt for username
        printf '  %bCredentials for %s (%s auth)%b\n' "$D" "$ip" "$db_auth_type" "$RS"
        printf '    Username: '
        read -r current_user
        
        if [[ -z "$current_user" ]]; then
            printf '  %-20s %b%s skipped%b\n' "$ip" "$Y" "$SYM_WAIT" "$RS"
            skipped=$((skipped + 1))
            continue
        fi
        
        if [[ "$db_auth_type" == "key" ]]; then
            current_pass=""
            local default_key="$HOME/.ssh/id_rsa"
            printf '    SSH Key [%s]: ' "$default_key"
            read -r current_key
            [[ -z "$current_key" ]] && current_key="$default_key"
            
            # Expand ~ if present
            current_key="${current_key/#\~/$HOME}"
            
            if [[ ! -f "$current_key" ]]; then
                msg_err "SSH key not found: $current_key"
                printf '  %-20s %b%s skipped%b\n' "$ip" "$Y" "$SYM_WAIT" "$RS"
                skipped=$((skipped + 1))
                continue
            fi
            msg "    ${D}Using SSH key: $current_key${RS}"
        else
            current_key=""
            printf '    Password: '
            read -rs current_pass
            printf '\n'
            
            if [[ -z "$current_pass" ]]; then
                printf '  %-20s %b%s skipped%b\n' "$ip" "$Y" "$SYM_WAIT" "$RS"
                skipped=$((skipped + 1))
                continue
            fi
        fi
        
        printf '  %-20s ' "$ip"
        
        # Temporarily set credentials for API calls
        local saved_user="$F5_USER" saved_pass="$F5_PASS" saved_key="$F5_SSH_KEY"
        F5_USER="$current_user"
        F5_PASS="$current_pass"
        F5_SSH_KEY="$current_key"
        
        local auth_resp token
        auth_resp=$(f5_auth "$ip" 10)
        token=$(echo "$auth_resp" | jq -r '.token.token // empty' 2>/dev/null)
        
        if [[ -z "$token" ]]; then
            # Determine the reason for failure
            if [[ -z "$auth_resp" ]]; then
                printf '%b%s unreachable%b\n' "$R" "$SYM_ERR" "$RS"
            elif printf '%s' "$auth_resp" | grep -qi "unauthorized\|Authentication failed\|invalid.*credentials\|401"; then
                printf '%b%s auth failed%b\n' "$R" "$SYM_ERR" "$RS"
            else
                printf '%b%s failed%b\n' "$R" "$SYM_ERR" "$RS"
            fi
            fail=$((fail + 1))
            F5_USER="$saved_user"
            F5_PASS="$saved_pass"
            F5_SSH_KEY="$saved_key"
            continue
        fi
        
        local lic_json parsed regkey expires days status
        lic_json=$(f5_get_license "$ip" "$token" 10)
        parsed=$(parse_license_info "$lic_json")
        regkey="${parsed%%|*}"
        expires="${parsed##*|}"
        
        # Restore credentials
        F5_USER="$saved_user"
        F5_PASS="$saved_pass"
        F5_SSH_KEY="$saved_key"
        
        if [[ -z "$expires" ]]; then
            printf '%b%s no license data%b\n' "$Y" "$SYM_WAIT" "$RS"
            fail=$((fail + 1))
            continue
        fi
        
        days=$(calc_days_until "$expires")
        status=$(get_status_from_days "$days")
        
        db_update "$ip" "$expires" "$days" "$status" "$regkey"
        log_event "CHECKED $ip: $status ($days)"
        
        case "$status" in
            perpetual) printf '%b%s perpetual%b\n' "$G" "$SYM_OK" "$RS" ;;
            active)    printf '%b%s %s days%b\n' "$G" "$SYM_OK" "$days" "$RS" ;;
            expiring)  printf '%b%s %s days%b\n' "$Y" "$SYM_WARN" "$days" "$RS" ;;
            expired)   printf '%b%s EXPIRED%b\n' "$R" "$SYM_ERR" "$RS" ;;
            *)         printf '%b%s unknown%b\n' "$D" "$SYM_PENDING" "$RS" ;;
        esac
        ok=$((ok + 1))
    done
    
    printf '\n'
    [[ $ok -gt 0 ]] && msg_ok "Checked $ok device(s)"
    [[ $fail -gt 0 ]] && msg_warn "$fail device(s) unreachable"
    [[ $skipped -gt 0 ]] && msg_warn "$skipped device(s) skipped (no credentials)"
}

#-------------------------------------------------------------------------------
# COMMANDS: REMOVE
#-------------------------------------------------------------------------------
cmd_remove() {
    local ip="$1"
    
    if [[ -z "$ip" ]]; then
        msg_err "Usage: remove <ip>"
        return 1
    fi
    
    if ! db_exists "$ip"; then
        msg_err "Device $ip not found"
        return 1
    fi
    
    printf "  Remove %s? [y/N]: " "$ip"; read -r confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        if db_remove "$ip"; then
            msg_ok "Removed $ip"
        else
            msg_err "Failed to remove $ip"
        fi
    else
        printf '  Cancelled\n'
    fi
}

#-------------------------------------------------------------------------------
# COMMANDS: LIST
#-------------------------------------------------------------------------------
cmd_list() {
    show_devices
}

#-------------------------------------------------------------------------------
# COMMANDS: CHECK
#-------------------------------------------------------------------------------
cmd_check() {
    local target="${1:-all}"
    local ips=""
    
    if [[ "$target" == "all" ]]; then
        ips=$(jq -r '.[]?.ip // empty' "$DB_FILE" 2>/dev/null)
        if [[ -z "$ips" ]]; then
            msg_warn "No devices to check"
            return 0
        fi
    else
        if ! db_exists "$target"; then
            msg_err "Device $target not found"
            return 1
        fi
        ips="$target"
    fi
    
    printf '\n'
    printf '  %bCHECKING LICENSES%b\n' "$BD" "$RS"
    printf '\n'
    
    local ok=0 fail=0 restarting=0 skipped=0
    local ip
    local current_user="" current_pass="" current_key=""
    
    # Convert to array to avoid subshell issues with read
    local ip_array=()
    while IFS= read -r ip; do
        [[ -n "$ip" ]] && ip_array+=("$ip")
    done <<< "$ips"
    
    # Process each IP
    for ip in "${ip_array[@]}"; do
        [[ -z "$ip" ]] && continue
        
        # Get stored auth type
        local db_auth_type
        db_auth_type=$(db_get_auth_type "$ip")
        
        # Try to load per-device credentials first
        if load_device_credentials "$ip"; then
            # Got credentials from environment (per-device or global)
            current_user="$F5_USER"
            current_pass="$F5_PASS"
            current_key="$F5_SSH_KEY"
        else
            # Prompt for this specific device - read from /dev/tty
            printf '  %bCredentials for %s (%s auth)%b\n' "$D" "$ip" "${db_auth_type:-password}" "$RS"
            printf '  Username: '
            read -r current_user </dev/tty
            
            if [[ -z "$current_user" ]]; then
                printf '  %-20s %b%s skipped%b %b(no credentials)%b\n' \
                    "$ip" "$Y" "$SYM_WAIT" "$RS" "$D" "$RS"
                skipped=$((skipped + 1))
                continue
            fi
            
            if [[ "$db_auth_type" == "key" ]]; then
                current_pass=""
                local default_key="$HOME/.ssh/id_rsa"
                printf '  SSH Key [%s]: ' "$default_key" 
                read -r current_key </dev/tty
                [[ -z "$current_key" ]] && current_key="$default_key"
                current_key="${current_key/#\~/$HOME}"
                
                if [[ ! -f "$current_key" ]]; then
                    printf '  %b[ERROR] SSH key not found: %s%b\n' "$R" "$current_key" "$RS"
                    printf '  %-20s %b%s skipped%b\n' "$ip" "$Y" "$SYM_WAIT" "$RS"
                    skipped=$((skipped + 1))
                    continue
                fi
                printf '  %bUsing SSH key: %s%b\n' "$D" "$current_key" "$RS"
            else
                printf '  Password: '
                read -rs current_pass </dev/tty
                printf '\n'
                
                if [[ -z "$current_pass" ]]; then
                    printf '  %-20s %b%s skipped%b %b(no password)%b\n' \
                        "$ip" "$Y" "$SYM_WAIT" "$RS" "$D" "$RS"
                    skipped=$((skipped + 1))
                    continue
                fi
                current_key=""
            fi
        fi
        
        printf '  %-20s ' "$ip"
        
        # Temporarily set credentials for API calls
        local saved_user="$F5_USER" saved_pass="$F5_PASS" saved_key="$F5_SSH_KEY"
        F5_USER="$current_user"
        F5_PASS="$current_pass"
        F5_SSH_KEY="$current_key"
        
        local regkey="" expires=""
        
        # Use SSH for key auth, REST API for password auth
        if [[ "$db_auth_type" == "key" && -n "$current_key" && -z "$current_pass" ]]; then
            # Use SSH to get license info
            local ssh_result
            ssh_result=$(_get_license_via_ssh "$ip")
            
            if [[ -z "$ssh_result" || "$ssh_result" == "|" ]]; then
                printf '%b%s SSH failed%b %b(check key permissions)%b\n' \
                    "$R" "$SYM_ERR" "$RS" "$D" "$RS"
                fail=$((fail + 1))
                F5_USER="$saved_user"
                F5_PASS="$saved_pass"
                F5_SSH_KEY="$saved_key"
                continue
            fi
            
            regkey="${ssh_result%%|*}"
            expires="${ssh_result##*|}"
        else
            # Use REST API (password auth)
            local auth_resp token auth_error
            auth_resp=$(f5_auth "$ip" 15)
            token=$(printf '%s' "$auth_resp" | jq -r '.token.token // empty' 2>/dev/null)
            
            if [[ -z "$token" ]]; then
                # Determine the reason for failure
                if [[ -z "$auth_resp" ]]; then
                    # Empty response = connection failure / unreachable
                    printf '%b%s unreachable%b %b(connection failed)%b\n' \
                        "$R" "$SYM_ERR" "$RS" "$D" "$RS"
                elif printf '%s' "$auth_resp" | grep -qi "unauthorized\|Authentication failed\|invalid.*credentials\|401"; then
                    # Auth failure - wrong username/password
                    printf '%b%s auth failed%b %b(invalid credentials)%b\n' \
                        "$R" "$SYM_ERR" "$RS" "$D" "$RS"
                elif printf '%s' "$auth_resp" | grep -qi "service unavailable\|503\|connection refused"; then
                    # Service unavailable - device may be restarting
                    printf '%b%s restarting%b %b(services may be reloading)%b\n' \
                        "$Y" "$SYM_WAIT" "$RS" "$D" "$RS"
                    restarting=$((restarting + 1))
                else
                    # Unknown error - show generic message
                    auth_error=$(printf '%s' "$auth_resp" | jq -r '.message // .error // empty' 2>/dev/null)
                    if [[ -n "$auth_error" ]]; then
                        printf '%b%s failed%b %b(%s)%b\n' \
                            "$R" "$SYM_ERR" "$RS" "$D" "$auth_error" "$RS"
                    else
                        printf '%b%s failed%b %b(unknown error)%b\n' \
                            "$R" "$SYM_ERR" "$RS" "$D" "$RS"
                    fi
                fi
                fail=$((fail + 1))
                # Restore credentials
                F5_USER="$saved_user"
                F5_PASS="$saved_pass"
                F5_SSH_KEY="$saved_key"
                continue
            fi
            
            local lic_json parsed
            lic_json=$(f5_get_license "$ip" "$token" 15)
            parsed=$(parse_license_info "$lic_json")
            regkey="${parsed%%|*}"
            expires="${parsed##*|}"
        fi
        
        # Restore credentials
        F5_USER="$saved_user"
        F5_PASS="$saved_pass"
        F5_SSH_KEY="$saved_key"
        
        if [[ -z "$expires" ]]; then
            printf '%b%s pending%b %b(license data not ready)%b\n' \
                "$Y" "$SYM_WAIT" "$RS" "$D" "$RS"
            restarting=$((restarting + 1))
            fail=$((fail + 1))
            continue
        fi
        
        local days status
        days=$(calc_days_until "$expires")
        status=$(get_status_from_days "$days")
        
        db_update "$ip" "$expires" "$days" "$status" "$regkey"
        log_event "CHECKED $ip: $status ($days)"
        
        case "$status" in
            perpetual)
                printf '%b%s perpetual%b %b(no expiration)%b\n' "$G" "$SYM_OK" "$RS" "$D" "$RS"
                ;;
            active)
                printf '%b%s %s days%b %b(exp: %s)%b\n' "$G" "$SYM_OK" "$days" "$RS" "$D" "$expires" "$RS"
                ;;
            expiring)
                printf '%b%s %s days%b %b(exp: %s)%b\n' "$Y" "$SYM_WARN" "$days" "$RS" "$D" "$expires" "$RS"
                ;;
            expired)
                printf '%b%s EXPIRED%b %b(%s)%b\n' "$R" "$SYM_ERR" "$RS" "$D" "$expires" "$RS"
                ;;
            *)
                printf '%b%s unknown%b\n' "$D" "$SYM_PENDING" "$RS"
                ;;
        esac
        ok=$((ok + 1))
    done
    
    printf '\n'
    [[ $ok -gt 0 ]] && msg_ok "Checked $ok device(s)"
    [[ $skipped -gt 0 ]] && msg_warn "$skipped device(s) skipped"
    if [[ $restarting -gt 0 ]]; then
        msg_warn "$restarting device(s) restarting - retry in 1-2 minutes"
    elif [[ $fail -gt 0 ]]; then
        msg_warn "$fail device(s) unreachable"
    fi
}

#-------------------------------------------------------------------------------
# VERIFY WITH RETRY (after renew/reload)
#-------------------------------------------------------------------------------
verify_with_retry() {
    local ip="$1"
    local max_wait="${2:-120}"
    local interval=10
    local elapsed=0
    
    printf '  %bWaiting for device (up to %ds)...%b\n' "$D" "$max_wait" "$RS"
    
    # Check auth type
    local db_auth_type
    db_auth_type=$(db_get_auth_type "$ip")
    
    while [[ $elapsed -lt $max_wait ]]; do
        printf '\r  %bChecking... (%ds/%ds)%b   ' "$C" "$elapsed" "$max_wait" "$RS"
        
        local expires="" regkey=""
        
        if [[ "$db_auth_type" == "key" && -n "$F5_SSH_KEY" && -z "$F5_PASS" ]]; then
            # Use SSH for key auth
            local ssh_result
            ssh_result=$(_get_license_via_ssh "$ip" 2>/dev/null)
            if [[ -n "$ssh_result" && "$ssh_result" != "|" ]]; then
                regkey="${ssh_result%%|*}"
                expires="${ssh_result##*|}"
            fi
        else
            # Use REST API
            local auth_resp token
            auth_resp=$(f5_auth "$ip" 10 2>/dev/null)
            token=$(printf '%s' "$auth_resp" | jq -r '.token.token // empty' 2>/dev/null)
            
            if [[ -n "$token" ]]; then
                local lic_json parsed
                lic_json=$(f5_get_license "$ip" "$token" 10 2>/dev/null)
                parsed=$(parse_license_info "$lic_json")
                regkey="${parsed%%|*}"
                expires="${parsed##*|}"
            fi
        fi
        
        if [[ -n "$expires" ]]; then
            printf '\r%60s\r' ""
            msg_ok "Device is back online"
            printf '\n'
            
            local days status
            days=$(calc_days_until "$expires")
            status=$(get_status_from_days "$days")
            db_update "$ip" "$expires" "$days" "$status" "$regkey"
            
            printf '  %bLICENSE STATUS%b\n' "$BD" "$RS"
            printf '  %-20s ' "$ip"
            case "$status" in
                perpetual)
                    printf '%b%s perpetual%b %b(no expiration)%b\n' "$G" "$SYM_OK" "$RS" "$D" "$RS"
                    ;;
                active)
                    printf '%b%s %s days%b %b(exp: %s)%b\n' "$G" "$SYM_OK" "$days" "$RS" "$D" "$expires" "$RS"
                    ;;
                expiring)
                    printf '%b%s %s days%b %b(exp: %s)%b\n' "$Y" "$SYM_WARN" "$days" "$RS" "$D" "$expires" "$RS"
                    ;;
                expired)
                    printf '%b%s EXPIRED%b %b(%s)%b\n' "$R" "$SYM_ERR" "$RS" "$D" "$expires" "$RS"
                    ;;
                *)
                    printf '%b%s unknown%b\n' "$D" "$SYM_PENDING" "$RS"
                    ;;
            esac
            printf '\n'
            return 0
        fi
        
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done
    
    printf '\r%60s\r' ""
    msg_warn "Device not ready after ${max_wait}s"
    printf '  %bTry: %bcheck %s%b in a few minutes%b\n' "$D" "$BD" "$ip" "$D" "$RS"
    printf '\n'
    return 1
}

#-------------------------------------------------------------------------------
# COMMANDS: DETAILS
#-------------------------------------------------------------------------------
# Get detailed license info via SSH
# Works from both TMOS and bash shell prompts
_get_license_details_via_ssh() {
    local ip="$1"
    
    # tmsh works from both TMOS and bash
    local lic_output
    lic_output=$(_f5_ssh_cmd "$ip" "tmsh show sys license" 15)
    
    # If tmsh not in path, try full path
    if [[ -z "$lic_output" ]] || echo "$lic_output" | grep -qi "command not found"; then
        lic_output=$(_f5_ssh_cmd "$ip" "/usr/bin/tmsh show sys license" 15)
    fi
    
    if [[ -z "$lic_output" ]]; then
        return 1
    fi
    
    echo "$lic_output"
}

cmd_details() {
    local ip="$1"
    
    if [[ -z "$ip" ]]; then
        msg_err "Usage: details <ip>"
        return 1
    fi
    
    prompt_credentials "$ip" || return 1
    
    printf '\n'
    msg_info "Fetching details for $ip..."
    
    # Check auth type
    local db_auth_type
    db_auth_type=$(db_get_auth_type "$ip")
    
    local regkey="" expires="" service="" licensed="" platform=""
    
    if [[ "$db_auth_type" == "key" && -n "$F5_SSH_KEY" && -z "$F5_PASS" ]]; then
        # Use SSH to get license details
        local lic_output
        lic_output=$(_get_license_details_via_ssh "$ip")
        
        if [[ -z "$lic_output" ]]; then
            msg_err "SSH connection failed"
            return 1
        fi
        
        # Parse tmsh output
        regkey=$(echo "$lic_output" | grep -i "Registration Key" | awk '{print $NF}' | head -1)
        expires=$(echo "$lic_output" | grep -i "License End Date" | awk '{print $NF}' | head -1)
        service=$(echo "$lic_output" | grep -i "Service Check Date" | awk '{print $NF}' | head -1)
        licensed=$(echo "$lic_output" | grep -i "Licensed On" | awk '{print $NF}' | head -1)
        platform=$(echo "$lic_output" | grep -i "Platform ID" | awk '{print $NF}' | head -1)
        
        if [[ -z "$regkey" && -z "$expires" ]]; then
            msg_err "Could not parse license from SSH output"
            return 1
        fi
    else
        # Use REST API
        local auth_resp token
        auth_resp=$(f5_auth "$ip")
        token=$(printf '%s' "$auth_resp" | jq -r '.token.token // empty' 2>/dev/null)
        
        if [[ -z "$token" ]]; then
            msg_err "Authentication failed"
            return 1
        fi
        
        local lic_json
        lic_json=$(f5_get_license "$ip" "$token")
        
        # Parse all fields
        local info
        info=$(printf '%s' "$lic_json" | jq -r '
            .entries | to_entries[] | select(.key | contains("/license/")) |
            .value.nestedStats.entries |
            "regkey:\(.registrationKey.description // "N/A")\nexpires:\(.licenseEndDate.description // "N/A")\nservice:\(.serviceCheckDate.description // "N/A")\nlicensed:\(.licensedOnDate.description // "N/A")\nplatform:\(.platformId.description // "N/A")"
        ' 2>/dev/null | head -5)
        
        if [[ -z "$info" ]]; then
            msg_err "Could not parse license"
            return 1
        fi
        
        # Extract fields (portable grep)
        regkey=$(printf '%s' "$info" | grep '^regkey:' | cut -d: -f2-)
        expires=$(printf '%s' "$info" | grep '^expires:' | cut -d: -f2-)
        service=$(printf '%s' "$info" | grep '^service:' | cut -d: -f2-)
        licensed=$(printf '%s' "$info" | grep '^licensed:' | cut -d: -f2-)
        platform=$(printf '%s' "$info" | grep '^platform:' | cut -d: -f2-)
    fi
    
    local days status
    days=$(calc_days_until "$expires")
    status=$(get_status_from_days "$days")
    
    db_update "$ip" "$expires" "$days" "$status" "$regkey"
    
    local status_display days_display
    case "$status" in
        perpetual)
            status_display="${G}PERPETUAL${RS}"
            days_display="no expiration"
            ;;
        active)
            status_display="${G}ACTIVE${RS}"
            days_display="$days days"
            ;;
        expiring)
            status_display="${Y}EXPIRING${RS}"
            days_display="$days days"
            ;;
        expired)
            status_display="${R}EXPIRED${RS}"
            days_display="$days days"
            ;;
        *)
            status_display="${D}UNKNOWN${RS}"
            days_display="?"
            ;;
    esac
    
    printf '\n'
    printf '  %bLICENSE DETAILS%b\n' "$BD" "$RS"
    printf '\n'
    printf '  +--------------------------------------------------------------+\n'
    printf '  | %-14s %-45s |\n' "IP:" "$ip"
    printf '  | %-14s %-45b |\n' "Status:" "$status_display ($days_display)"
    printf '  +--------------------------------------------------------------+\n'
    printf '  | %-14s %-45s |\n' "Expires:" "${expires:-Perpetual}"
    printf '  | %-14s %-45s |\n' "Service Date:" "${service:-N/A}"
    printf '  | %-14s %-45s |\n' "Licensed On:" "${licensed:-N/A}"
    printf '  | %-14s %-45s |\n' "Platform:" "${platform:-N/A}"
    printf '  +--------------------------------------------------------------+\n'
    printf '  | %-14s %-45s |\n' "Reg Key:" "${regkey:-N/A}"
    printf '  +--------------------------------------------------------------+\n'
    printf '\n'
}

#-------------------------------------------------------------------------------
# COMMANDS: RENEW
#-------------------------------------------------------------------------------
cmd_renew() {
    local ip="$1"
    local regkey="$2"
    
    if [[ -z "$ip" ]]; then
        msg_err "Usage: renew <ip> <registration-key>"
        return 1
    fi
    
    if [[ -z "$regkey" ]]; then
        msg_err "Registration key required"
        return 1
    fi
    
    # Warning
    printf '\n'
    printf '  %bWARNING%b\n' "$Y" "$RS"
    printf '  %bLicense renewal will restart services on the device.%b\n' "$D" "$RS"
    printf '  %bThis may cause brief traffic interruption.%b\n' "$D" "$RS"
    printf '  %bRecommended: Perform during maintenance window.%b\n' "$BD" "$RS"
    printf '\n'
    local confirm
    printf "  Proceed? [y/N]: "; read -r confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        printf '  Cancelled\n'
        return 0
    fi
    
    prompt_credentials "$ip" || return 1
    
    printf '\n'
    msg_info "Connecting to $ip..."
    
    # Check auth type
    local db_auth_type
    db_auth_type=$(db_get_auth_type "$ip")
    
    if [[ "$db_auth_type" == "key" && -n "$F5_SSH_KEY" && -z "$F5_PASS" ]]; then
        # For SSH key auth, use SOAPLicenseClient via SSH
        msg_info "Installing license via SSH..."
        
        # SOAPLicenseClient is a bash command
        local result
        result=$(_f5_ssh_cmd "$ip" "SOAPLicenseClient --basekey $regkey" 30)
        
        # If that failed (might be in TMOS), try via bash explicitly
        if [[ -z "$result" ]] || echo "$result" | grep -qi "syntax error\|unknown"; then
            result=$(_f5_ssh_cmd "$ip" "bash -c 'SOAPLicenseClient --basekey $regkey'" 30)
        fi
        
        if echo "$result" | grep -qi "error\|fail"; then
            msg_err "Failed to install license: $result"
            return 1
        fi
        
        msg_ok "License installed!"
    else
        # Use REST API for password auth
        local auth_resp token
        auth_resp=$(f5_auth "$ip")
        token=$(printf '%s' "$auth_resp" | jq -r '.token.token // empty' 2>/dev/null)
        
        if [[ -z "$token" ]]; then
            msg_err "Authentication failed"
            return 1
        fi
        
        msg_info "Installing license..."
        
        local result
        result=$(f5_install_license "$ip" "$token" "$regkey")
        
        if printf '%s' "$result" | jq -e '.code' >/dev/null 2>&1; then
            local errmsg
            errmsg=$(printf '%s' "$result" | jq -r '.message // "Unknown error"')
            msg_err "Failed: $errmsg"
            return 1
        fi
        
        msg_ok "License installed!"
    fi
    
    log_event "RENEWED $ip with ${regkey:0:10}..."
    
    printf '\n'
    msg_info "Device applying license (services restarting)..."
    verify_with_retry "$ip" 120
}

#-------------------------------------------------------------------------------
# COMMANDS: RELOAD
#-------------------------------------------------------------------------------
cmd_reload() {
    local ip="$1"
    
    if [[ -z "$ip" ]]; then
        msg_err "Usage: reload <ip>"
        return 1
    fi
    
    # Warning
    printf '\n'
    printf '  %bWARNING%b\n' "$Y" "$RS"
    printf '  %bLicense reload will restart services.%b\n' "$D" "$RS"
    printf '  %bRecommended: Perform during maintenance window.%b\n' "$BD" "$RS"
    printf '\n'
    local confirm
    printf "  Proceed? [y/N]: "; read -r confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        printf '  Cancelled\n'
        return 0
    fi
    
    prompt_credentials "$ip" || return 1
    
    printf '\n'
    msg_info "Reloading license on $ip..."
    
    local result rc
    local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=15"
    
    if [[ -z "$F5_PASS" ]]; then
        # Key-based authentication
        msg "  ${D}Using SSH key authentication${RS}"
        if [[ -n "$F5_SSH_KEY" && -f "$F5_SSH_KEY" ]]; then
            result=$(ssh $ssh_opts -o BatchMode=yes -o PasswordAuthentication=no -i "$F5_SSH_KEY" "$F5_USER@$ip" "reloadlic" 2>&1)
        else
            result=$(ssh $ssh_opts -o BatchMode=yes -o PasswordAuthentication=no "$F5_USER@$ip" "reloadlic" 2>&1)
        fi
        rc=$?
    elif ssh_has_sshpass; then
        # Password authentication with sshpass (non-interactive)
        msg "  ${D}Using password authentication${RS}"
        result=$(sshpass -p "$F5_PASS" ssh $ssh_opts "$F5_USER@$ip" "reloadlic" 2>&1)
        rc=$?
    else
        # Password authentication without sshpass - run interactively
        msg "  ${D}Using password authentication (interactive)${RS}"
        msg "  ${D}You will be prompted for the password...${RS}"
        printf '\n'
        ssh $ssh_opts "$F5_USER@$ip" "reloadlic"
        rc=$?
        result=""
    fi
    
    if [[ $rc -eq 0 ]]; then
        msg_ok "License reload initiated"
        log_event "RELOAD $ip"
        printf '\n'
        msg_info "Device applying license..."
        verify_with_retry "$ip" 120
    else
        msg_err "Failed to reload license"
        [[ -n "$result" ]] && printf '  %b%s%b\n' "$D" "$result" "$RS"
        printf '\n'
        printf '  %bTry manually:%b\n' "$D" "$RS"
        printf '    %bssh %s@%s%b\n' "$BD" "$F5_USER" "$ip" "$RS"
        printf '    %breloadlic%b\n' "$BD" "$RS"
    fi
}

#-------------------------------------------------------------------------------
# COMMANDS: APPLY-LICENSE (standalone license application)
#-------------------------------------------------------------------------------
cmd_apply_license() {
    local ip="$1"
    local source="${2:-}"
    
    if [[ -z "$ip" ]]; then
        msg_err "Usage: apply-license <ip> [license-file]"
        printf '      %bOr run without file to paste license content%b\n' "$D" "$RS"
        return 1
    fi
    
    prompt_credentials "$ip" || return 1
    
    printf '\n'
    printf '  %bAPPLY LICENSE%b\n' "$BD" "$RS"
    printf '  %bTarget device: %s%b\n' "$D" "$ip" "$RS"
    printf '\n'
    
    local license_content=""
    
    if [[ -n "$source" ]]; then
        # Source provided - check if it's a file
        local license_file="${source/#\~/$HOME}"
        
        if [[ -f "$license_file" ]]; then
            msg_info "Reading license from file: $license_file"
            license_content=$(cat "$license_file")
        else
            msg_err "File not found: $license_file"
            return 1
        fi
    else
        # No source - prompt for choice
        printf '  %bHow would you like to provide the license?%b\n' "$D" "$RS"
        printf '\n'
        printf '    %b[P]%b Paste license content\n' "$BD" "$RS"
        printf '    %b[F]%b Load from file\n' "$BD" "$RS"
        printf '\n'
        printf '  Choice [P/F]: '
        
        local choice
        read -r choice
        
        case "$choice" in
            [Ff])
                printf '  Enter path to license file: '
                local license_file
                read -r license_file
                license_file="${license_file/#\~/$HOME}"
                
                if [[ ! -f "$license_file" ]]; then
                    msg_err "File not found: $license_file"
                    return 1
                fi
                
                license_content=$(cat "$license_file")
                ;;
                
            [Pp]|"")
                license_content=$(_read_license_content)
                ;;
                
            *)
                msg_err "Invalid choice"
                return 1
                ;;
        esac
    fi
    
    if [[ -z "$license_content" ]]; then
        msg_err "No license content provided"
        return 1
    fi
    
    # Validate
    if ! _validate_license_content "$license_content"; then
        msg_warn "License content may be incomplete or invalid"
        printf '  Continue anyway? [y/N]: '
        local cont
        read -r cont
        if [[ ! "$cont" =~ ^[Yy]$ ]]; then
            msg "  ${D}Cancelled${RS}"
            return 0
        fi
    fi
    
    # Show preview
    local line_count
    line_count=$(echo "$license_content" | wc -l | tr -d ' ')
    msg_ok "License content loaded ($line_count lines)"
    
    printf '\n'
    printf '  %bWARNING%b\n' "$Y" "$RS"
    printf '  %bThis will:%b\n' "$D" "$RS"
    printf '  %b  • Backup existing license to /var/tmp/bigip.license.backup.*%b\n' "$D" "$RS"
    printf '  %b  • Overwrite /config/bigip.license%b\n' "$D" "$RS"
    printf '  %b  • Restart F5 services (brief traffic interruption)%b\n' "$D" "$RS"
    printf '\n'
    printf '  Proceed? [y/N]: '
    local proceed
    read -r proceed
    
    if [[ ! "$proceed" =~ ^[Yy]$ ]]; then
        msg "  ${D}Cancelled${RS}"
        return 0
    fi
    
    printf '\n'
    if _write_license_content "$ip" "$license_content"; then
        log_event "LICENSE_APPLIED $ip"
        printf '\n'
        msg_info "Waiting for services to restart..."
        verify_with_retry "$ip" 120
    else
        msg_err "Failed to apply license"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# COMMANDS: DOSSIER (Enhanced with license application)
#-------------------------------------------------------------------------------

# SSH connection multiplexing for multiple operations with single auth
# Creates a control socket for connection reuse
_ssh_control_path() {
    local ip="$1"
    echo "/tmp/f5lm-ssh-${ip//[.:]/_}-$$"
}

# Start SSH control master connection (supports both key and password auth)
_ssh_start_control() {
    local ip="$1"
    local control_path
    control_path=$(_ssh_control_path "$ip")
    
    local ssh_base_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10"
    ssh_base_opts="$ssh_base_opts -o ControlMaster=yes -o ControlPath=$control_path -o ControlPersist=60"
    
    # Determine auth method and start control master
    # Use timeout to prevent hanging
    local timeout_cmd=""
    if command -v timeout >/dev/null 2>&1; then
        timeout_cmd="timeout 15"
    fi
    
    local rc=0
    if [[ -z "$F5_PASS" ]]; then
        # Key-based authentication (no password)
        if [[ -n "$F5_SSH_KEY" && -f "$F5_SSH_KEY" ]]; then
            $timeout_cmd ssh $ssh_base_opts -i "$F5_SSH_KEY" -o BatchMode=yes -o PasswordAuthentication=no -f -N "$F5_USER@$ip" 2>/dev/null
        else
            $timeout_cmd ssh $ssh_base_opts -o BatchMode=yes -o PasswordAuthentication=no -f -N "$F5_USER@$ip" 2>/dev/null
        fi
        rc=$?
    elif ssh_has_sshpass; then
        # Password authentication with sshpass
        $timeout_cmd sshpass -p "$F5_PASS" ssh $ssh_base_opts -f -N "$F5_USER@$ip" 2>/dev/null
        rc=$?
    else
        # Try without sshpass (will prompt interactively or use key)
        $timeout_cmd ssh $ssh_base_opts -f -N "$F5_USER@$ip" 2>/dev/null
        rc=$?
    fi
    
    # Wait a moment for control socket to be created
    sleep 0.5
    
    # Verify control socket exists
    if [[ ! -S "$control_path" ]]; then
        return 1
    fi
    
    return $rc
}

# Stop SSH control master connection
_ssh_stop_control() {
    local ip="$1"
    local control_path
    control_path=$(_ssh_control_path "$ip")
    
    # Close the control master
    ssh -o ControlPath="$control_path" -O exit "$F5_USER@$ip" 2>/dev/null
    rm -f "$control_path" 2>/dev/null
}

# Run SSH command using existing control connection
_ssh_run() {
    local ip="$1"
    local cmd="$2"
    local control_path
    control_path=$(_ssh_control_path "$ip")
    
    local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
    ssh_opts="$ssh_opts -o ControlPath=$control_path"
    
    ssh $ssh_opts "$F5_USER@$ip" "$cmd" 2>/dev/null
}

# Run SSH command with automatic shell detection (handles TMOS vs bash prompt)
# TMOS prompt: azadmin@(bigip-v21)(pid-25079)(cfg-sync Standalone)(Active)(/Common)(tmos)#
# Bash prompt: [azadmin@bigip-v21:Active:Standalone] ~ #
_ssh_run_bash() {
    local ip="$1"
    local cmd="$2"
    local control_path
    control_path=$(_ssh_control_path "$ip")
    
    local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
    ssh_opts="$ssh_opts -o ControlPath=$control_path"
    
    # Wrap command to handle both TMOS and bash shell
    # Using /bin/bash -c ensures we're in bash regardless of login shell
    # TMOS shell doesn't understand bash, but /bin/bash is the full path
    ssh $ssh_opts "$F5_USER@$ip" "/bin/bash -c '$cmd'" 2>/dev/null
}

# Run SSH command for license operations (ensures we're in bash shell)
# This handles the case where user lands in TMOS prompt instead of bash
# TMOS prompt: azadmin@(bigip-v21)(cfg-sync Standalone)(Active)(/Common)(tmos)#
# Bash prompt: [azadmin@bigip-v21:Active:Standalone] ~ #
_ssh_run_license_cmd() {
    local ip="$1"
    local cmd="$2"
    local control_path
    control_path=$(_ssh_control_path "$ip")
    
    local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
    ssh_opts="$ssh_opts -o ControlPath=$control_path"
    
    # Always wrap in /bin/bash -c to ensure we're in bash context
    # This works whether the user lands in TMOS or bash shell
    ssh $ssh_opts "$F5_USER@$ip" "/bin/bash -c '$cmd'" 2>/dev/null
}

# Run SCP using existing control connection
_scp_run() {
    local ip="$1"
    local local_file="$2"
    local remote_file="$3"
    local control_path
    control_path=$(_ssh_control_path "$ip")
    
    local scp_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
    scp_opts="$scp_opts -o ControlPath=$control_path"
    
    scp $scp_opts "$local_file" "$F5_USER@$ip:$remote_file" 2>/dev/null
}

# Apply license to device (backup, write, reload) with single SSH connection
_apply_license_to_device() {
    local ip="$1"
    local license_content="$2"
    local remote_file="/config/bigip.license"
    local backup_file="/var/tmp/bigip.license.backup.$(date +%Y%m%d_%H%M%S)"
    
    local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=15"
    local scp_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
    
    # Create temp file with license content
    local temp_file
    temp_file=$(make_temp_file "license")
    echo "$license_content" > "$temp_file"
    
    msg_info "Applying license to device..."
    
    if [[ -z "$F5_PASS" ]]; then
        # Key-based authentication
        msg "  ${D}Using SSH key authentication${RS}"
        
        local key_opt=""
        [[ -n "$F5_SSH_KEY" && -f "$F5_SSH_KEY" ]] && key_opt="-i $F5_SSH_KEY"
        
        # Backup existing license
        msg_info "Backing up existing license..."
        ssh $ssh_opts -o BatchMode=yes -o PasswordAuthentication=no $key_opt "$F5_USER@$ip" \
            "cp $remote_file $backup_file 2>/dev/null || true" 2>/dev/null
        msg "  ${D}Backup: $backup_file${RS}"
        
        # Upload license
        msg_info "Writing license to device..."
        if ! scp $scp_opts -o BatchMode=yes -o PasswordAuthentication=no $key_opt "$temp_file" "$F5_USER@$ip:$remote_file" 2>/dev/null; then
            rm -f "$temp_file" 2>/dev/null
            msg_err "Failed to write license file"
            return 1
        fi
        rm -f "$temp_file" 2>/dev/null
        
        msg_ok "License written to device"
        
        # Reload license
        printf '\n'
        msg_info "Reloading license configuration..."
        ssh $ssh_opts -o BatchMode=yes -o PasswordAuthentication=no $key_opt "$F5_USER@$ip" "reloadlic" 2>/dev/null
        
    elif ssh_has_sshpass; then
        # Password authentication with sshpass
        msg "  ${D}Using password authentication${RS}"
        
        # Backup existing license
        msg_info "Backing up existing license..."
        sshpass -p "$F5_PASS" ssh $ssh_opts "$F5_USER@$ip" \
            "cp $remote_file $backup_file 2>/dev/null || true" 2>/dev/null
        msg "  ${D}Backup: $backup_file${RS}"
        
        # Upload license
        msg_info "Writing license to device..."
        if ! sshpass -p "$F5_PASS" scp $scp_opts "$temp_file" "$F5_USER@$ip:$remote_file" 2>/dev/null; then
            rm -f "$temp_file" 2>/dev/null
            msg_err "Failed to write license file"
            return 1
        fi
        rm -f "$temp_file" 2>/dev/null
        
        msg_ok "License written to device"
        
        # Reload license
        printf '\n'
        msg_info "Reloading license configuration..."
        sshpass -p "$F5_PASS" ssh $ssh_opts "$F5_USER@$ip" "reloadlic" 2>/dev/null
        
    else
        # Password authentication without sshpass - run interactively
        msg "  ${D}Using password authentication (interactive)${RS}"
        msg "  ${D}You will be prompted for the password multiple times...${RS}"
        printf '\n'
        
        # Backup existing license
        msg_info "Backing up existing license..."
        ssh $ssh_opts "$F5_USER@$ip" "cp $remote_file $backup_file 2>/dev/null || true"
        msg "  ${D}Backup: $backup_file${RS}"
        
        # Upload license
        msg_info "Writing license to device..."
        if ! scp $scp_opts "$temp_file" "$F5_USER@$ip:$remote_file"; then
            rm -f "$temp_file" 2>/dev/null
            msg_err "Failed to write license file"
            return 1
        fi
        rm -f "$temp_file" 2>/dev/null
        
        msg_ok "License written to device"
        
        # Reload license
        printf '\n'
        msg_info "Reloading license configuration..."
        ssh $ssh_opts "$F5_USER@$ip" "reloadlic"
    fi
    
    if [[ $? -eq 0 ]]; then
        msg_ok "License reload initiated"
        return 0
    else
        msg_err "License reload may have failed"
        msg "  ${D}Try running 'reloadlic' manually on the device${RS}"
        return 1
    fi
}

# Upload license file to F5 via SSH (SCP) - with connection reuse
_upload_license_file() {
    local ip="$1"
    local local_file="$2"
    
    # Read file content and use the unified apply function
    local license_content
    license_content=$(cat "$local_file")
    
    _apply_license_to_device "$ip" "$license_content"
    return $?
}

# Write license content directly to F5 via SSH - with connection reuse
_write_license_content() {
    local ip="$1"
    local license_content="$2"
    
    _apply_license_to_device "$ip" "$license_content"
    return $?
}

# Read multi-line input (license content) from user
_read_license_content() {
    local content=""
    local line
    local line_count=0
    
    # Print header to stderr so it doesn't get captured in the output
    printf '\n' >&2
    printf '  %b┌─────────────────────────────────────────────────────────────────┐%b\n' "$C" "$RS" >&2
    printf '  %b│  PASTE LICENSE CONTENT                                          │%b\n' "$C" "$RS" >&2
    printf '  %b│  %b(Paste the license text, then press Enter twice to finish)%b     │%b\n' "$C" "$D" "$C" "$RS" >&2
    printf '  %b└─────────────────────────────────────────────────────────────────┘%b\n' "$C" "$RS" >&2
    printf '\n' >&2
    
    local empty_lines=0
    while IFS= read -r line; do
        # Two consecutive empty lines = done
        if [[ -z "$line" ]]; then
            empty_lines=$((empty_lines + 1))
            if [[ $empty_lines -ge 2 ]]; then
                break
            fi
            content="${content}${line}"$'\n'
        else
            empty_lines=0
            content="${content}${line}"$'\n'
            line_count=$((line_count + 1))
        fi
    done
    
    # Trim trailing newlines
    content="${content%$'\n'}"
    content="${content%$'\n'}"
    
    if [[ $line_count -lt 5 ]]; then
        return 1
    fi
    
    echo "$content"
}

# Validate license content looks correct
_validate_license_content() {
    local content="$1"
    
    # Basic validation - F5 licenses have specific markers
    if echo "$content" | grep -q "Auth vers"; then
        return 0
    elif echo "$content" | grep -q "Registration Key"; then
        return 0
    elif echo "$content" | grep -q "License"; then
        return 0
    fi
    
    return 1
}

cmd_dossier() {
    local ip="$1"
    local regkey="${2:-}"
    
    if [[ -z "$ip" ]]; then
        msg_err "Usage: dossier <ip> [registration-key]"
        return 1
    fi
    
    prompt_credentials "$ip" || return 1
    
    msg_info "Connecting to $ip..."
    
    # Check auth type
    local db_auth_type
    db_auth_type=$(db_get_auth_type "$ip")
    
    local dossier=""
    
    if [[ "$db_auth_type" == "key" && -n "$F5_SSH_KEY" && -z "$F5_PASS" ]]; then
        # Use SSH directly for key auth
        
        # Get regkey if not provided
        if [[ -z "$regkey" ]]; then
            msg_info "Retrieving registration key via SSH..."
            local lic_output
            lic_output=$(_f5_ssh_cmd "$ip" "tmsh show sys license" 15)
            regkey=$(echo "$lic_output" | grep -i "Registration Key" | awk '{print $NF}' | head -1)
            
            if [[ -z "$regkey" ]]; then
                msg_warn "Could not retrieve registration key from device"
                printf '\n'
                printf '  %bPlease provide the registration key:%b\n' "$D" "$RS"
                printf '  Registration Key: '
                read -r regkey
                if [[ -z "$regkey" ]]; then
                    msg_err "Registration key required for dossier"
                    return 1
                fi
            else
                msg_ok "Found registration key: ${BD}$regkey${RS}"
            fi
        fi
        
        msg_info "Generating dossier via SSH..."
        
        # Generate dossier via SSH
        # get_dossier is a bash command, so it works from bash shell
        # If user lands in TMOS, we need to run it via bash
        local dossier_output
        dossier_output=$(_f5_ssh_cmd "$ip" "get_dossier -b $regkey" 30)
        
        # If that failed (might be in TMOS), try via bash explicitly
        if [[ -z "$dossier_output" ]] || echo "$dossier_output" | grep -qi "syntax error\|unknown"; then
            dossier_output=$(_f5_ssh_cmd "$ip" "bash -c 'get_dossier -b $regkey'" 30)
        fi
        
        # Extract dossier string (hex characters)
        if [[ -n "$dossier_output" ]]; then
            dossier=$(echo "$dossier_output" | grep -oE '[a-f0-9]{20,}' | head -1)
        fi
        
        if [[ -z "$dossier" ]]; then
            msg_err "SSH dossier generation failed"
            return 1
        fi
        msg_ok "Dossier generated via SSH"
    else
        # Use REST API for password auth
        local auth_resp token
        auth_resp=$(f5_auth "$ip")
        token=$(printf '%s' "$auth_resp" | jq -r '.token.token // empty' 2>/dev/null)
        
        if [[ -z "$token" ]]; then
            msg_err "Authentication failed"
            return 1
        fi
        
        # Get regkey if not provided
        if [[ -z "$regkey" ]]; then
            msg_info "Retrieving registration key..."
            local lic_json
            lic_json=$(f5_get_license "$ip" "$token")
            regkey=$(echo "$lic_json" | jq -r '
                .entries | to_entries[] | select(.key | contains("/license/")) |
                .value.nestedStats.entries.registrationKey.description // empty
            ' 2>/dev/null | head -1)
            
            if [[ -z "$regkey" || "$regkey" == "null" ]]; then
                msg_warn "Could not retrieve registration key from device"
                printf '\n'
                printf '  %bPlease provide the registration key:%b\n' "$D" "$RS"
                printf '  Registration Key: '
                read -r regkey
                if [[ -z "$regkey" ]]; then
                    msg_err "Registration key required for dossier"
                    return 1
                fi
            else
                msg_ok "Found registration key: ${BD}$regkey${RS}"
            fi
        fi
        
        msg_info "Generating dossier via REST API..."
        
        local resp
        resp=$(f5_get_dossier "$ip" "$token" "$regkey")
        dossier=$(echo "$resp" | jq -r '.dossier // empty' 2>/dev/null)
        
        # If REST fails, try SSH fallback
        if [[ -z "$dossier" || "$dossier" == "null" ]]; then
            local errmsg
            errmsg=$(echo "$resp" | jq -r '.message // empty' 2>/dev/null)
            msg_warn "REST API not available${errmsg:+ ($errmsg)}"
            
            msg_info "Trying SSH method..."
            
            local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=15"
            local dossier_output=""
            
            if [[ -z "$F5_PASS" ]]; then
                # Key auth (should have been handled above, but fallback)
                msg "  ${D}Using SSH key authentication${RS}"
                local key_opt=""
                [[ -n "$F5_SSH_KEY" && -f "$F5_SSH_KEY" ]] && key_opt="-i $F5_SSH_KEY"
                dossier_output=$(ssh $ssh_opts -o BatchMode=yes -o PasswordAuthentication=no $key_opt "$F5_USER@$ip" "get_dossier -b $regkey" 2>/dev/null)
            elif ssh_has_sshpass; then
                # Password auth with sshpass
                msg "  ${D}Using password authentication${RS}"
                dossier_output=$(sshpass -p "$F5_PASS" ssh $ssh_opts "$F5_USER@$ip" "get_dossier -b $regkey" 2>/dev/null)
            else
                # Password auth without sshpass - interactive
                msg "  ${D}Using password authentication (interactive)${RS}"
                msg "  ${D}You will be prompted for the password...${RS}"
                printf '\n'
                dossier_output=$(ssh $ssh_opts "$F5_USER@$ip" "get_dossier -b $regkey" 2>&1)
            fi
            
            # Extract dossier string (hex characters)
            if [[ -n "$dossier_output" ]]; then
                dossier=$(echo "$dossier_output" | grep -oE '[a-f0-9]{20,}' | head -1)
            fi
            
            if [[ -z "$dossier" ]]; then
                msg_err "SSH dossier generation failed"
                printf '\n'
                printf '  %bMANUAL DOSSIER GENERATION%b\n' "$BD" "$RS"
                printf '\n'
                printf '  %bSSH to the F5 device and run:%b\n' "$D" "$RS"
                printf '\n'
                printf '    %bssh %s@%s%b\n' "$BD" "$F5_USER" "$ip" "$RS"
                printf '    %bbash%b  %b(if not already in bash)%b\n' "$BD" "$RS" "$D" "$RS"
                printf '    %bget_dossier -b %s%b\n' "$BD" "$regkey" "$RS"
                printf '\n'
                return 1
            else
                msg_ok "Dossier retrieved via SSH"
            fi
        else
            msg_ok "Dossier generated via REST API"
        fi
    fi
    
    printf '\n'
    printf '  %bDOSSIER%b\n' "$BD" "$RS"
    printf '  %bRegistration Key: %s%b\n' "$D" "$regkey" "$RS"
    printf '\n'
    draw_line 60
    echo "$dossier" | fold -w 58 | sed 's/^/  /'
    draw_line 60
    printf '\n'
    
    # Save dossier to file
    local dossier_file="${DATA_DIR}/dossier_${ip//./_}.txt"
    echo "$dossier" > "$dossier_file" 2>/dev/null
    msg "  ${D}Saved to: $dossier_file${RS}"
    printf '\n'
    
    log_event "DOSSIER $ip ($regkey)"
    
    #---------------------------------------------------------------------------
    # LICENSE APPLICATION OPTIONS
    #---------------------------------------------------------------------------
    printf '  %b╔═════════════════════════════════════════════════════════════════╗%b\n' "$C" "$RS"
    printf '  %b║  APPLY LICENSE                                                  ║%b\n' "$C" "$RS"
    printf '  %b╠═════════════════════════════════════════════════════════════════╣%b\n' "$C" "$RS"
    printf '  %b║  1. Open F5 license portal and get license                      ║%b\n' "$C" "$RS"
    printf '  %b║     %bhttps://activate.f5.com/license/dossier.jsp%b                 %b║%b\n' "$C" "$BD" "$C" "$C" "$RS"
    printf '  %b║                                                                 ║%b\n' "$C" "$RS"
    printf '  %b║  After getting the license, choose how to apply it:            ║%b\n' "$C" "$RS"
    printf '  %b║                                                                 ║%b\n' "$C" "$RS"
    printf '  %b║  %b[P]%b Paste license content here                                ║%b\n' "$C" "$BD" "$C" "$RS"
    printf '  %b║  %b[F]%b Upload license from local file                            ║%b\n' "$C" "$BD" "$C" "$RS"
    printf '  %b║  %b[S]%b Skip - apply license manually later                       ║%b\n' "$C" "$BD" "$C" "$RS"
    printf '  %b║                                                                 ║%b\n' "$C" "$RS"
    printf '  %b╚═════════════════════════════════════════════════════════════════╝%b\n' "$C" "$RS"
    printf '\n'
    printf '  Choice [P/F/S]: '
    
    local choice
    read -r choice
    
    case "$choice" in
        [Pp])
            # Paste license content
            local license_content
            license_content=$(_read_license_content)
            
            if [[ -z "$license_content" ]]; then
                msg_err "No license content received"
                return 1
            fi
            
            # Validate
            if ! _validate_license_content "$license_content"; then
                msg_warn "License content may be incomplete or invalid"
                printf '  Continue anyway? [y/N]: '
                local cont
                read -r cont
                if [[ ! "$cont" =~ ^[Yy]$ ]]; then
                    msg "  ${D}Cancelled${RS}"
                    return 0
                fi
            fi
            
            printf '\n'
            printf '  %bWARNING%b\n' "$Y" "$RS"
            printf '  %bThis will overwrite the existing license and restart services.%b\n' "$D" "$RS"
            printf '  %bA backup will be created at /var/tmp/bigip.license.backup.*%b\n' "$D" "$RS"
            printf '\n'
            printf '  Proceed? [y/N]: '
            local proceed
            read -r proceed
            
            if [[ ! "$proceed" =~ ^[Yy]$ ]]; then
                msg "  ${D}Cancelled${RS}"
                return 0
            fi
            
            printf '\n'
            if _write_license_content "$ip" "$license_content"; then
                log_event "LICENSE_APPLIED $ip (paste)"
                printf '\n'
                msg_info "Waiting for services to restart..."
                verify_with_retry "$ip" 120
            else
                msg_err "Failed to apply license"
                return 1
            fi
            ;;
            
        [Ff])
            # Upload from file
            printf '\n'
            printf '  Enter path to license file: '
            local license_file
            read -r license_file
            
            # Expand ~ and handle paths
            license_file="${license_file/#\~/$HOME}"
            
            if [[ ! -f "$license_file" ]]; then
                msg_err "File not found: $license_file"
                return 1
            fi
            
            # Validate file content
            if ! _validate_license_content "$(cat "$license_file")"; then
                msg_warn "File may not contain valid license data"
                printf '  Continue anyway? [y/N]: '
                local cont
                read -r cont
                if [[ ! "$cont" =~ ^[Yy]$ ]]; then
                    msg "  ${D}Cancelled${RS}"
                    return 0
                fi
            fi
            
            printf '\n'
            printf '  %bWARNING%b\n' "$Y" "$RS"
            printf '  %bThis will overwrite the existing license and restart services.%b\n' "$D" "$RS"
            printf '  %bA backup will be created at /var/tmp/bigip.license.backup.*%b\n' "$D" "$RS"
            printf '\n'
            printf '  Proceed? [y/N]: '
            local proceed
            read -r proceed
            
            if [[ ! "$proceed" =~ ^[Yy]$ ]]; then
                msg "  ${D}Cancelled${RS}"
                return 0
            fi
            
            printf '\n'
            if _upload_license_file "$ip" "$license_file"; then
                log_event "LICENSE_APPLIED $ip (file: $license_file)"
                printf '\n'
                msg_info "Waiting for services to restart..."
                verify_with_retry "$ip" 120
            else
                msg_err "Failed to apply license"
                return 1
            fi
            ;;
            
        [Ss]|"")
            # Skip
            printf '\n'
            printf '  %bNEXT STEPS (Manual)%b\n' "$BD" "$RS"
            printf '  %b1. Copy the dossier from above (or from: %s)%b\n' "$D" "$dossier_file" "$RS"
            printf '  %b2. Go to: %bhttps://activate.f5.com/license/dossier.jsp%b\n' "$D" "$BD" "$RS"
            printf '  %b3. Paste the dossier and click Next%b\n' "$D" "$RS"
            printf '  %b4. Download or copy the license%b\n' "$D" "$RS"
            printf '  %b5. Upload to device: %bscp license.txt %s@%s:/config/bigip.license%b\n' "$D" "$BD" "$F5_USER" "$ip" "$RS"
            printf '  %b6. Reload license: %breload %s%b\n' "$D" "$BD" "$ip" "$RS"
            printf '\n'
            ;;
            
        *)
            msg_warn "Invalid choice. To apply license later, use: reload $ip"
            ;;
    esac
}

#-------------------------------------------------------------------------------
# COMMANDS: ACTIVATE (wizard)
#-------------------------------------------------------------------------------
cmd_activate() {
    local ip="$1"
    
    if [[ -z "$ip" ]]; then
        msg_err "Usage: activate <ip>"
        return 1
    fi
    
    db_exists "$ip" || db_add "$ip"
    
    printf '\n'
    printf '  %bLICENSE ACTIVATION WIZARD%b\n' "$BD" "$RS"
    printf '  %bActivate license on %s%b\n' "$D" "$ip" "$RS"
    printf '\n'
    printf '  %bStep 1: Get Dossier%b\n' "$C" "$RS"
    printf '  %bThe dossier identifies your device.%b\n' "$D" "$RS"
    printf '\n'
    local yn
    printf "  Retrieve dossier now? [Y/n]: "; read -r yn
    
    if [[ ! "$yn" =~ ^[Nn]$ ]]; then
        cmd_dossier "$ip" || return 1
    fi
    
    printf '\n'
    printf '  %bStep 2: Get License from F5%b\n' "$C" "$RS"
    printf '\n'
    printf '  %b1. Visit: %bhttps://activate.f5.com/license%b\n' "$D" "$BD" "$RS"
    printf '  %b2. Paste your dossier%b\n' "$D" "$RS"
    printf '  %b3. Enter registration key%b\n' "$D" "$RS"
    printf '  %b4. Download license%b\n' "$D" "$RS"
    printf '\n'
    printf '  %bStep 3: Apply License%b\n' "$C" "$RS"
    printf '\n'
    local regkey
    printf "  Enter registration key (or Enter to skip): "; read -r regkey
    
    if [[ -n "$regkey" ]]; then
        cmd_renew "$ip" "$regkey"
    else
        printf '\n'
        printf '  %bWhen ready: %brenew %s <key>%b\n' "$D" "$BD" "$ip" "$RS"
    fi
}

#-------------------------------------------------------------------------------
# COMMANDS: EXPORT
#-------------------------------------------------------------------------------
cmd_export() {
    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S' 2>/dev/null) || timestamp=$(date '+%Y%m%d')
    local file="${DATA_DIR}/export_${timestamp}.csv"
    
    {
        printf 'ip,expires,days,status,regkey,checked\n'
        jq -r '.[] | [.ip, .expires, .days, .status, .regkey, .checked] | @csv' "$DB_FILE" 2>/dev/null
    } > "$file"
    
    if [[ -f "$file" ]]; then
        msg_ok "Exported to $file"
    else
        msg_err "Export failed"
    fi
}

#-------------------------------------------------------------------------------
# COMMANDS: HISTORY
#-------------------------------------------------------------------------------
cmd_history() {
    printf '\n'
    printf '  %bRECENT HISTORY%b\n' "$BD" "$RS"
    printf '\n'
    
    if [[ ! -s "$LOG_FILE" ]]; then
        printf '  %bNo history yet%b\n' "$D" "$RS"
        return
    fi
    
    tail -15 "$LOG_FILE" 2>/dev/null | while IFS= read -r line; do
        printf '  %s\n' "$line"
    done
    printf '\n'
}

#-------------------------------------------------------------------------------
# COMMAND ROUTER
#-------------------------------------------------------------------------------
run_command() {
    local input="$1"
    local cmd args arg1 arg2
    
    # Trim whitespace
    input="${input#"${input%%[![:space:]]*}"}"
    input="${input%"${input##*[![:space:]]}"}"
    
    # Parse
    cmd="${input%% *}"
    args="${input#* }"
    [[ "$args" == "$cmd" ]] && args=""
    
    arg1="${args%% *}"
    arg2="${args#* }"
    [[ "$arg2" == "$arg1" ]] && arg2=""
    
    # Route
    case "$cmd" in
        add|a)              cmd_add "$arg1" ;;
        add-multi|am)       cmd_add_multi ;;
        remove|rm|r)        cmd_remove "$arg1" ;;
        list|ls|l)          cmd_list ;;
        check|c)            cmd_check "$arg1" ;;
        details|d|info|i)   cmd_details "$arg1" ;;
        renew)              cmd_renew "$arg1" "$arg2" ;;
        reload)             cmd_reload "$arg1" ;;
        dossier)            cmd_dossier "$arg1" "$arg2" ;;
        apply-license|apply) cmd_apply_license "$arg1" "$arg2" ;;
        activate)           cmd_activate "$arg1" ;;
        export)             cmd_export ;;
        history|h)          cmd_history ;;
        refresh|clear)      show_header; show_stats; show_devices ;;
        help|"?")           cmd_help ;;
        quit|exit|q)        printf '\n  %bGoodbye!%b\n\n' "$D" "$RS"; exit 0 ;;
        "")                 ;; # Empty - ignore
        *)
            # Check if it's an IP address
            if [[ "$cmd" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                cmd_details "$cmd"
            else
                msg_err "Unknown command: $cmd"
                printf '      %bType "help" for commands%b\n' "$D" "$RS"
            fi
            ;;
    esac
}

#-------------------------------------------------------------------------------
# INTERACTIVE MODE
#-------------------------------------------------------------------------------
interactive_mode() {
    show_header
    show_stats
    show_devices
    
    # Setup command history
    HISTFILE="$HIST_FILE"
    HISTSIZE=100
    HISTCONTROL="ignoredups:erasedups"
    touch "$HISTFILE" 2>/dev/null || true
    
    # Load history
    history -r "$HISTFILE" 2>/dev/null || true
    
    # Setup readline bindings (arrow keys, etc.)
    # These work on bash 3.2+ including macOS
    bind 'set show-all-if-ambiguous on' 2>/dev/null || true
    bind 'set completion-ignore-case on' 2>/dev/null || true
    bind 'set bell-style none' 2>/dev/null || true
    
    local input
    while true; do
        show_prompt
        
        # read -e enables readline (arrow keys, history, line editing)
        # Works on bash 3.2+ including macOS default bash
        if read -e -r input; then
            # Save to history if not empty
            if [[ -n "$input" ]]; then
                history -s "$input" 2>/dev/null || true
                history -w "$HISTFILE" 2>/dev/null || true
            fi
            run_command "$input"
        else
            # EOF (Ctrl+D)
            printf '\n'
            exit 0
        fi
    done
}

#-------------------------------------------------------------------------------
# MAIN
#-------------------------------------------------------------------------------
main() {
    # Pre-flight checks
    check_bash_version
    
    # Detect environment
    detect_platform
    detect_terminal
    
    # Setup
    setup_colors
    setup_symbols
    setup_data_dir
    
    # Check dependencies
    check_dependencies
    
    # Initialize data
    init_data
    
    # Handle arguments
    if [[ $# -eq 0 ]]; then
        interactive_mode
    else
        case "$1" in
            -v|--version)
                printf '%s v%s\n' "$F5LM_NAME" "$F5LM_VERSION"
                printf 'Platform: %s | Bash: %s\n' "$PLATFORM" "$BASH_VERSION"
                ;;
            -h|--help)
                show_header
                cmd_help
                ;;
            *)
                run_command "$*"
                ;;
        esac
    fi
}

# Entry point
main "$@"
