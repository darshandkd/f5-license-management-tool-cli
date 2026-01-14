#!/usr/bin/env bash
###############################################################################
#
#   F5 LICENSE MANAGER
#   Interactive CLI for F5 BIG-IP License Lifecycle Management
#   Version 3.0
#
###############################################################################

set -uo pipefail

readonly VERSION="3.0"
readonly DATA_DIR="${HOME}/.f5lm"
readonly DB_FILE="${DATA_DIR}/devices.json"
readonly LOG_FILE="${DATA_DIR}/history.log"

# -----------------------------------------------------------------------------
# COLORS (auto-disabled for non-interactive)
# -----------------------------------------------------------------------------
if [[ -t 1 ]]; then
    R=$'\e[31m'      # Red
    G=$'\e[32m'      # Green  
    Y=$'\e[33m'      # Yellow
    B=$'\e[34m'      # Blue
    C=$'\e[36m'      # Cyan
    W=$'\e[37m'      # White
    D=$'\e[2m'       # Dim
    BD=$'\e[1m'      # Bold
    RS=$'\e[0m'      # Reset
else
    R='' G='' Y='' B='' C='' W='' D='' BD='' RS=''
fi

# -----------------------------------------------------------------------------
# HELPERS
# -----------------------------------------------------------------------------
msg()     { echo -e "$1"; }
msg_ok()  { echo -e "  ${G}[OK]${RS} $1"; }
msg_err() { echo -e "  ${R}[ERROR]${RS} $1" >&2; }
msg_warn(){ echo -e "  ${Y}[WARN]${RS} $1"; }
msg_info(){ echo -e "  ${C}>>>${RS} $1"; }

die() { msg_err "$1"; exit 1; }

log_event() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

line() {
    printf '  %*s\n' "${1:-70}" '' | tr ' ' '-'
}

# -----------------------------------------------------------------------------
# DEPENDENCY CHECK
# -----------------------------------------------------------------------------
check_deps() {
    local missing=""
    command -v curl >/dev/null || missing="curl $missing"
    command -v jq >/dev/null || missing="jq $missing"
    
    if [[ -n "$missing" ]]; then
        die "Missing: $missing
  Install with:
    macOS:  brew install $missing
    Ubuntu: sudo apt install $missing
    RHEL:   sudo yum install $missing"
    fi
}

# -----------------------------------------------------------------------------
# DATA LAYER
# -----------------------------------------------------------------------------
init_db() {
    mkdir -p "$DATA_DIR"
    [[ -f "$DB_FILE" ]] || echo '[]' > "$DB_FILE"
    touch "$LOG_FILE"
}

db_list() {
    cat "$DB_FILE"
}

db_count() {
    jq 'length' "$DB_FILE"
}

db_get() {
    local ip="$1"
    jq -e --arg ip "$ip" '.[] | select(.ip == $ip)' "$DB_FILE" 2>/dev/null
}

db_exists() {
    local ip="$1"
    jq -e --arg ip "$ip" '.[] | select(.ip == $ip)' "$DB_FILE" >/dev/null 2>&1
}

db_add() {
    local ip="$1"
    local ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    jq --arg ip "$ip" --arg ts "$ts" \
        '. += [{"ip":$ip,"added":$ts,"checked":null,"expires":null,"days":null,"status":"new","regkey":null}]' \
        "$DB_FILE" > "${DB_FILE}.tmp" && mv "${DB_FILE}.tmp" "$DB_FILE"
    
    log_event "ADDED $ip"
}

db_update() {
    local ip="$1" expires="$2" days="$3" status="$4" regkey="$5"
    local ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    jq --arg ip "$ip" --arg ts "$ts" --arg exp "$expires" --arg d "$days" --arg st "$status" --arg rk "$regkey" \
        '(.[] | select(.ip == $ip)) |= . + {checked:$ts, expires:$exp, days:$d, status:$st, regkey:$rk}' \
        "$DB_FILE" > "${DB_FILE}.tmp" && mv "${DB_FILE}.tmp" "$DB_FILE"
}

db_remove() {
    local ip="$1"
    jq --arg ip "$ip" 'del(.[] | select(.ip == $ip))' "$DB_FILE" > "${DB_FILE}.tmp" && mv "${DB_FILE}.tmp" "$DB_FILE"
    log_event "REMOVED $ip"
}

# -----------------------------------------------------------------------------
# CREDENTIALS
# -----------------------------------------------------------------------------
F5_USER="${F5_USER:-}"
F5_PASS="${F5_PASS:-}"

prompt_creds() {
    if [[ -n "$F5_USER" && -n "$F5_PASS" ]]; then
        return 0
    fi
    
    echo
    msg "  ${C}Enter F5 Credentials${RS}"
    msg "  ${D}(credentials are never stored)${RS}"
    echo
    read -rp "  Username: " F5_USER
    read -rsp "  Password: " F5_PASS
    echo
    echo
    
    [[ -n "$F5_USER" && -n "$F5_PASS" ]] || { msg_err "Credentials required"; return 1; }
}

# -----------------------------------------------------------------------------
# SSH EXECUTION
# -----------------------------------------------------------------------------
ssh_has_sshpass() {
    command -v sshpass >/dev/null 2>&1
}

ssh_exec() {
    local ip="$1"
    local cmd="$2"
    local timeout="${3:-30}"
    
    # SSH options for non-interactive use
    local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10"
    
    if ssh_has_sshpass; then
        # Use sshpass for password authentication
        sshpass -p "$F5_PASS" ssh $ssh_opts -T "$F5_USER@$ip" "$cmd" 2>/dev/null
    else
        # Try SSH with expect-like approach using heredoc
        # This works if SSH keys are set up, otherwise will fail
        ssh $ssh_opts -T "$F5_USER@$ip" "$cmd" 2>/dev/null
    fi
}

ssh_exec_with_pty() {
    local ip="$1"
    local cmd="$2"
    
    # For commands that might need a PTY, use expect if available
    if command -v expect >/dev/null 2>&1; then
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
    elif ssh_has_sshpass; then
        sshpass -p "$F5_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -tt "$F5_USER@$ip" "$cmd" 2>/dev/null
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

# -----------------------------------------------------------------------------
# F5 API
# -----------------------------------------------------------------------------
f5_auth() {
    local ip="$1"
    curl -sk -m 20 -X POST "https://${ip}/mgmt/shared/authn/login" \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"$F5_USER\",\"password\":\"$F5_PASS\",\"loginProviderName\":\"tmos\"}" 2>/dev/null
}

f5_get_license() {
    local ip="$1" token="$2"
    curl -sk -m 20 "https://${ip}/mgmt/tm/sys/license" \
        -H "X-F5-Auth-Token: $token" 2>/dev/null
}

f5_get_dossier() {
    local ip="$1" token="$2" regkey="$3"
    # Dossier requires POST with registration key
    curl -sk -m 30 -X POST "https://${ip}/mgmt/tm/shared/licensing/dossier" \
        -H "Content-Type: application/json" \
        -H "X-F5-Auth-Token: $token" \
        -d "{\"registrationKey\":\"${regkey}\"}" 2>/dev/null
}

f5_install_license() {
    local ip="$1" token="$2" regkey="$3"
    curl -sk -m 60 -X POST "https://${ip}/mgmt/tm/sys/license" \
        -H "Content-Type: application/json" \
        -H "X-F5-Auth-Token: $token" \
        -d "{\"command\":\"install\",\"registrationKey\":\"$regkey\"}" 2>/dev/null
}

parse_license() {
    local json="$1"
    echo "$json" | jq -r '
        .entries | to_entries[] | select(.key | contains("/license/")) |
        .value.nestedStats.entries | 
        "\(.registrationKey.description // "")|\(.licenseEndDate.description // "")"
    ' 2>/dev/null | head -1
}

calc_days() {
    local expiry="$1"
    [[ -z "$expiry" ]] && echo "?" && return
    
    local exp_ts now_ts
    exp_ts=$(date -d "${expiry//\//-}" +%s 2>/dev/null) || exp_ts=$(date -j -f "%Y/%m/%d" "$expiry" +%s 2>/dev/null) || { echo "?"; return; }
    now_ts=$(date +%s)
    echo $(( (exp_ts - now_ts) / 86400 ))
}

get_status() {
    local days="$1"
    [[ "$days" == "?" ]] && echo "unknown" && return
    if (( days < 0 )); then echo "expired"
    elif (( days <= 30 )); then echo "expiring"
    else echo "active"
    fi
}

# -----------------------------------------------------------------------------
# UI - HEADER
# -----------------------------------------------------------------------------
show_header() {
    command -v clear >/dev/null && clear 2>/dev/null || printf '\033c'
    echo
    echo -e "  ${R}███████╗${RS}${BD}███████╗${RS}   ${C}License Manager${RS} ${D}v${VERSION}${RS}"
    echo -e "  ${R}██╔════╝${RS}${BD}██╔════╝${RS}   ${D}F5 BIG-IP License Lifecycle Tool${RS}"
    echo -e "  ${R}█████╗  ${RS}${BD}███████╗${RS}"
    echo -e "  ${R}██╔══╝  ${RS}${BD}╚════██║${RS}   ${D}Type ${RS}help${D} for commands${RS}"
    echo -e "  ${R}██║     ${RS}${BD}███████║${RS}"
    echo -e "  ${R}╚═╝     ${RS}${BD}╚══════╝${RS}"
    echo
    line 74
}

# -----------------------------------------------------------------------------
# UI - DASHBOARD
# -----------------------------------------------------------------------------
show_stats() {
    local total=$(jq 'length' "$DB_FILE")
    local active=$(jq '[.[] | select(.status=="active")] | length' "$DB_FILE")
    local expiring=$(jq '[.[] | select(.status=="expiring")] | length' "$DB_FILE")
    local expired=$(jq '[.[] | select(.status=="expired")] | length' "$DB_FILE")
    
    echo
    echo -e "  ${BD}OVERVIEW${RS}"
    echo
    printf "  %-12s %-12s %-12s %-12s\n" "TOTAL" "ACTIVE" "EXPIRING" "EXPIRED"
    printf "  ${BD}%-12s${RS} ${G}%-12s${RS} ${Y}%-12s${RS} ${R}%-12s${RS}\n" "$total" "$active" "$expiring" "$expired"
    echo
}

# -----------------------------------------------------------------------------
# UI - DEVICE LIST
# -----------------------------------------------------------------------------
show_devices() {
    local count=$(db_count)
    
    echo -e "  ${BD}DEVICES${RS}"
    echo
    
    if [[ "$count" -eq 0 ]]; then
        echo -e "  ${D}No devices yet. Use ${RS}add <ip>${D} to add one.${RS}"
        echo
        return
    fi
    
    printf "  ${D}%-3s %-18s %-14s %-8s %-10s${RS}\n" "#" "IP ADDRESS" "EXPIRES" "DAYS" "STATUS"
    line 60
    
    local i=0
    while [[ $i -lt $count ]]; do
        local ip=$(jq -r ".[$i].ip" "$DB_FILE")
        local expires=$(jq -r ".[$i].expires // \"-\"" "$DB_FILE")
        local days=$(jq -r ".[$i].days // \"?\"" "$DB_FILE")
        local status=$(jq -r ".[$i].status // \"new\"" "$DB_FILE")
        
        [[ "$expires" == "null" ]] && expires="-"
        [[ "$days" == "null" ]] && days="?"
        
        local status_fmt
        case "$status" in
            active)   status_fmt="${G}● active${RS}" ;;
            expiring) status_fmt="${Y}● expiring${RS}" ;;
            expired)  status_fmt="${R}● expired${RS}" ;;
            *)        status_fmt="${D}○ $status${RS}" ;;
        esac
        
        printf "  %-3s %-18s %-14s %-8s %b\n" "$((i+1))" "$ip" "$expires" "$days" "$status_fmt"
        ((i++))
    done
    echo
}

# -----------------------------------------------------------------------------
# UI - PROMPT
# -----------------------------------------------------------------------------
show_prompt() {
    echo -ne "  ${C}f5lm${RS} > "
}

# -----------------------------------------------------------------------------
# COMMANDS
# -----------------------------------------------------------------------------
cmd_help() {
    echo
    echo -e "  ${BD}COMMANDS${RS}"
    echo
    echo -e "  ${C}Managing Devices${RS}"
    echo -e "    ${BD}add${RS} <ip>              Add single device"
    echo -e "    ${BD}add-multi${RS}            Add multiple devices"
    echo -e "    ${BD}remove${RS} <ip>          Remove device"
    echo -e "    ${BD}list${RS}                 Show all devices"
    echo
    echo -e "  ${C}License Operations${RS}"
    echo -e "    ${BD}check${RS} [ip|all]       Check license status"
    echo -e "    ${BD}details${RS} <ip>         Show full license info"
    echo -e "    ${BD}renew${RS} <ip> <key>     Apply registration key (REST API)"
    echo -e "    ${BD}reload${RS} <ip>          Reload license file (SSH)"
    echo -e "    ${BD}activate${RS} <ip>        License activation wizard"
    echo -e "    ${BD}dossier${RS} <ip> [key]   Generate device dossier (REST or SSH)"
    echo
    echo -e "  ${C}Utilities${RS}"
    echo -e "    ${BD}export${RS}               Export to CSV"
    echo -e "    ${BD}history${RS}              Show action log"
    echo -e "    ${BD}refresh${RS}              Refresh display"
    echo -e "    ${BD}help${RS}                 This help"
    echo -e "    ${BD}quit${RS}                 Exit"
    echo
    echo -e "  ${C}Shortcuts${RS}"
    echo -e "    ${D}a=add, r=remove, c=check, d=details, q=quit${RS}"
    echo
    echo -e "  ${C}Keyboard${RS}"
    echo -e "    ${D}↑/↓        Command history${RS}"
    echo -e "    ${D}←/→        Move cursor in line${RS}"
    echo -e "    ${D}Ctrl+A/E   Start/end of line${RS}"
    echo -e "    ${D}Ctrl+W     Delete word${RS}"
    echo -e "    ${D}Ctrl+C     Cancel current input${RS}"
    echo
}

cmd_add() {
    local ip="$1"
    
    # Clean input
    ip="${ip#https://}"
    ip="${ip#http://}"
    ip="${ip%/}"
    
    if [[ -z "$ip" ]]; then
        msg_err "Usage: add <ip>"
        return 1
    fi
    
    if db_exists "$ip"; then
        msg_warn "$ip already exists"
        return 1
    fi
    
    db_add "$ip"
    msg_ok "Added ${BD}$ip${RS}"
    msg "      ${D}Run 'check $ip' to fetch license info${RS}"
}

cmd_add_multi() {
    echo
    echo -e "  ${BD}ADD MULTIPLE DEVICES${RS}"
    echo -e "  ${D}Enter IP addresses, one per line. Empty line to finish.${RS}"
    echo
    
    local count=0
    while true; do
        read -rp "  IP: " ip
        [[ -z "$ip" ]] && break
        
        ip="${ip#https://}"
        ip="${ip#http://}"
        ip="${ip%/}"
        
        if db_exists "$ip"; then
            msg_warn "$ip already exists"
        else
            db_add "$ip"
            msg_ok "Added $ip"
            ((count++))
        fi
    done
    
    echo
    msg_ok "Added $count device(s)"
}

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
    
    read -rp "  Remove $ip? [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        db_remove "$ip"
        msg_ok "Removed $ip"
    else
        msg "  Cancelled"
    fi
}

cmd_list() {
    show_devices
}

cmd_check() {
    local target="${1:-all}"
    local ips=""
    
    if [[ "$target" == "all" ]]; then
        ips=$(jq -r '.[].ip' "$DB_FILE")
        [[ -z "$ips" ]] && { msg_warn "No devices to check"; return; }
    else
        db_exists "$target" || { msg_err "Device $target not found"; return 1; }
        ips="$target"
    fi
    
    prompt_creds || return 1
    
    echo
    echo -e "  ${BD}CHECKING LICENSES${RS}"
    echo
    
    local ok=0 fail=0 restarting=0
    for ip in $ips; do
        printf "  %-20s " "$ip"
        
        # Get token
        local auth_resp=$(f5_auth "$ip" 2>/dev/null)
        local token=$(echo "$auth_resp" | jq -r '.token.token // empty' 2>/dev/null)
        
        if [[ -z "$token" ]]; then
            echo -e "${Y}◌ restarting${RS} ${D}(services may be reloading)${RS}"
            ((restarting++))
            ((fail++))
            continue
        fi
        
        # Get license
        local lic_json=$(f5_get_license "$ip" "$token")
        local parsed=$(parse_license "$lic_json")
        local regkey="${parsed%%|*}"
        local expires="${parsed##*|}"
        
        if [[ -z "$expires" ]]; then
            echo -e "${Y}◌ pending${RS} ${D}(license data not ready)${RS}"
            ((restarting++))
            ((fail++))
            continue
        fi
        
        local days=$(calc_days "$expires")
        local status=$(get_status "$days")
        
        db_update "$ip" "$expires" "$days" "$status" "$regkey"
        log_event "CHECKED $ip: $status ($days days)"
        
        case "$status" in
            active)   echo -e "${G}● $days days${RS} ${D}(exp: $expires)${RS}" ;;
            expiring) echo -e "${Y}● $days days${RS} ${D}(exp: $expires)${RS}" ;;
            expired)  echo -e "${R}● EXPIRED${RS} ${D}($expires)${RS}" ;;
            *)        echo -e "${D}○ unknown${RS}" ;;
        esac
        ((ok++))
    done
    
    echo
    if [[ $ok -gt 0 ]]; then
        msg_ok "Checked $ok device(s)"
    fi
    if [[ $restarting -gt 0 ]]; then
        msg_warn "$restarting device(s) restarting - retry in 1-2 minutes"
    elif [[ $fail -gt 0 ]]; then
        msg_warn "$fail device(s) unreachable"
    fi
}

# Verify license with retry - for post-renewal/reload verification
verify_license_with_retry() {
    local ip="$1"
    local max_wait="${2:-120}"
    local interval=10
    local elapsed=0
    
    echo -e "  ${D}Waiting for device to become available (up to ${max_wait}s)...${RS}"
    
    while [[ $elapsed -lt $max_wait ]]; do
        # Show progress
        printf "\r  ${C}⏳${RS} Checking... (%ds/%ds) " "$elapsed" "$max_wait"
        
        # Try to authenticate
        local auth_resp=$(f5_auth "$ip" 2>/dev/null)
        local token=$(echo "$auth_resp" | jq -r '.token.token // empty' 2>/dev/null)
        
        if [[ -n "$token" ]]; then
            # Try to get license
            local lic_json=$(f5_get_license "$ip" "$token" 2>/dev/null)
            local parsed=$(parse_license "$lic_json")
            local expires="${parsed##*|}"
            
            if [[ -n "$expires" ]]; then
                printf "\r%60s\r" ""  # Clear line
                msg_ok "Device is back online"
                echo
                
                # Update database and show result
                local regkey="${parsed%%|*}"
                local days=$(calc_days "$expires")
                local status=$(get_status "$days")
                db_update "$ip" "$expires" "$days" "$status" "$regkey"
                
                echo -e "  ${BD}LICENSE STATUS${RS}"
                printf "  %-20s " "$ip"
                case "$status" in
                    active)   echo -e "${G}● $days days${RS} ${D}(exp: $expires)${RS}" ;;
                    expiring) echo -e "${Y}● $days days${RS} ${D}(exp: $expires)${RS}" ;;
                    expired)  echo -e "${R}● EXPIRED${RS} ${D}($expires)${RS}" ;;
                    *)        echo -e "${D}○ unknown${RS}" ;;
                esac
                echo
                return 0
            fi
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    printf "\r%60s\r" ""  # Clear line
    msg_warn "Device not ready after ${max_wait}s"
    echo -e "  ${D}License refresh may still be in progress.${RS}"
    echo -e "  ${D}Try: ${RS}${BD}check $ip${RS}${D} in a few minutes.${RS}"
    echo
    return 1
}

cmd_details() {
    local ip="$1"
    
    [[ -z "$ip" ]] && { msg_err "Usage: details <ip>"; return 1; }
    
    prompt_creds || return 1
    
    echo
    msg_info "Fetching details for $ip..."
    
    local auth_resp=$(f5_auth "$ip")
    local token=$(echo "$auth_resp" | jq -r '.token.token // empty' 2>/dev/null)
    
    [[ -z "$token" ]] && { msg_err "Authentication failed"; return 1; }
    
    local lic_json=$(f5_get_license "$ip" "$token")
    
    # Parse all fields
    local info=$(echo "$lic_json" | jq -r '
        .entries | to_entries[] | select(.key | contains("/license/")) |
        .value.nestedStats.entries | 
        "regkey:\(.registrationKey.description // "N/A")
expires:\(.licenseEndDate.description // "N/A")
service:\(.serviceCheckDate.description // "N/A")
licensed:\(.licensedOnDate.description // "N/A")
platform:\(.platformId.description // "N/A")"
    ' 2>/dev/null | head -5)
    
    [[ -z "$info" ]] && { msg_err "Could not parse license"; return 1; }
    
    local regkey=$(echo "$info" | grep "^regkey:" | cut -d: -f2)
    local expires=$(echo "$info" | grep "^expires:" | cut -d: -f2)
    local service=$(echo "$info" | grep "^service:" | cut -d: -f2)
    local licensed=$(echo "$info" | grep "^licensed:" | cut -d: -f2)
    local platform=$(echo "$info" | grep "^platform:" | cut -d: -f2)
    
    local days=$(calc_days "$expires")
    local status=$(get_status "$days")
    
    db_update "$ip" "$expires" "$days" "$status" "$regkey"
    
    local status_fmt
    case "$status" in
        active)   status_fmt="${G}ACTIVE${RS}" ;;
        expiring) status_fmt="${Y}EXPIRING${RS}" ;;
        expired)  status_fmt="${R}EXPIRED${RS}" ;;
        *)        status_fmt="${D}UNKNOWN${RS}" ;;
    esac
    
    echo
    echo -e "  ${BD}LICENSE DETAILS${RS}"
    echo
    echo -e "  +--------------------------------------------------------------+"
    printf "  | %-14s %-44s |\n" "IP:" "$ip"
    printf "  | %-14s %-44b |\n" "Status:" "$status_fmt ($days days)"
    echo -e "  +--------------------------------------------------------------+"
    printf "  | %-14s %-44s |\n" "Expires:" "$expires"
    printf "  | %-14s %-44s |\n" "Service Date:" "$service"
    printf "  | %-14s %-44s |\n" "Licensed On:" "$licensed"
    printf "  | %-14s %-44s |\n" "Platform:" "$platform"
    echo -e "  +--------------------------------------------------------------+"
    printf "  | %-14s %-44s |\n" "Reg Key:" "$regkey"
    echo -e "  +--------------------------------------------------------------+"
    echo
}

cmd_renew() {
    local ip="$1"
    local regkey="$2"
    
    [[ -z "$ip" ]] && { msg_err "Usage: renew <ip> <registration-key>"; return 1; }
    [[ -z "$regkey" ]] && { msg_err "Registration key required"; return 1; }
    
    # Warning before proceeding
    echo
    echo -e "  ${Y}⚠ WARNING${RS}"
    echo -e "  ${D}License renewal will restart services on the device.${RS}"
    echo -e "  ${D}This may cause brief traffic interruption.${RS}"
    echo -e "  ${BD}Recommended: Perform during maintenance window.${RS}"
    echo
    read -rp "  Proceed with license renewal? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { msg "  Cancelled"; return 0; }
    
    prompt_creds || return 1
    
    echo
    msg_info "Connecting to $ip..."
    
    local auth_resp=$(f5_auth "$ip")
    local token=$(echo "$auth_resp" | jq -r '.token.token // empty' 2>/dev/null)
    
    [[ -z "$token" ]] && { msg_err "Authentication failed"; return 1; }
    
    msg_info "Installing license..."
    
    local result=$(f5_install_license "$ip" "$token" "$regkey")
    
    if echo "$result" | jq -e '.code' >/dev/null 2>&1; then
        local errmsg=$(echo "$result" | jq -r '.message // "Unknown error"')
        msg_err "License activation failed: $errmsg"
        return 1
    fi
    
    msg_ok "License installed successfully!"
    log_event "RENEWED $ip with ${regkey:0:10}..."
    
    # Post-renewal verification with retry
    echo
    msg_info "Device is applying license (services restarting)..."
    verify_license_with_retry "$ip" 120
}

cmd_reload() {
    local ip="$1"
    
    [[ -z "$ip" ]] && { msg_err "Usage: reload <ip>"; return 1; }
    
    # Warning before proceeding
    echo
    echo -e "  ${Y}⚠ WARNING${RS}"
    echo -e "  ${D}License reload will restart services on the device.${RS}"
    echo -e "  ${BD}Recommended: Perform during maintenance window.${RS}"
    echo
    read -rp "  Proceed? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { msg "  Cancelled"; return 0; }
    
    prompt_creds || return 1
    
    echo
    msg_info "Reloading license on $ip..."
    
    if ! ssh_has_sshpass; then
        msg_warn "sshpass not installed - SSH may prompt for password"
    fi
    
    local result
    result=$(f5_ssh_bash "$ip" "reloadlic" 2>&1)
    local rc=$?
    
    if [[ $rc -eq 0 ]]; then
        msg_ok "License reload initiated"
        log_event "RELOAD $ip"
        echo
        msg_info "Device is applying license (services restarting)..."
        verify_license_with_retry "$ip" 120
    else
        msg_err "Failed to reload license"
        [[ -n "$result" ]] && msg "  ${D}$result${RS}"
        echo
        echo -e "  ${D}Try manually:${RS}"
        echo -e "    ${BD}ssh $F5_USER@$ip${RS}"
        echo -e "    ${BD}reloadlic${RS}"
    fi
}

cmd_activate() {
    local ip="$1"
    
    [[ -z "$ip" ]] && { msg_err "Usage: activate <ip>"; return 1; }
    
    db_exists "$ip" || db_add "$ip"
    
    echo
    echo -e "  ${BD}LICENSE ACTIVATION WIZARD${RS}"
    echo -e "  ${D}Follow these steps to activate a license on $ip${RS}"
    echo
    echo -e "  ${C}Step 1: Get Dossier${RS}"
    echo -e "  ${D}The dossier uniquely identifies your F5 device.${RS}"
    echo
    read -rp "  Retrieve dossier now? [Y/n]: " yn
    
    if [[ ! "$yn" =~ ^[Nn]$ ]]; then
        cmd_dossier "$ip" || return 1
    fi
    
    echo
    echo -e "  ${C}Step 2: Get License from F5${RS}"
    echo
    echo -e "  ${D}1. Visit:${RS} ${BD}https://activate.f5.com/license${RS}"
    echo -e "  ${D}2. Paste your dossier string${RS}"
    echo -e "  ${D}3. Enter your base registration key${RS}"
    echo -e "  ${D}4. Download or copy the license${RS}"
    echo
    echo -e "  ${C}Step 3: Apply License${RS}"
    echo
    read -rp "  Enter registration key (or press Enter to skip): " regkey
    
    if [[ -n "$regkey" ]]; then
        cmd_renew "$ip" "$regkey"
    else
        echo
        msg "  ${D}When ready, run:${RS} renew $ip <your-key>"
    fi
}

cmd_dossier() {
    local ip="$1"
    local regkey="${2:-}"
    
    [[ -z "$ip" ]] && { msg_err "Usage: dossier <ip> [registration-key]"; return 1; }
    
    prompt_creds || return 1
    
    msg_info "Connecting to $ip..."
    
    local auth_resp=$(f5_auth "$ip")
    local token=$(echo "$auth_resp" | jq -r '.token.token // empty' 2>/dev/null)
    
    [[ -z "$token" ]] && { msg_err "Authentication failed"; return 1; }
    
    # If no regkey provided, try to get it from the device
    if [[ -z "$regkey" ]]; then
        msg_info "Retrieving registration key..."
        local lic_json=$(f5_get_license "$ip" "$token")
        regkey=$(echo "$lic_json" | jq -r '
            .entries | to_entries[] | select(.key | contains("/license/")) |
            .value.nestedStats.entries.registrationKey.description // empty
        ' 2>/dev/null | head -1)
        
        if [[ -z "$regkey" || "$regkey" == "null" ]]; then
            msg_warn "Could not retrieve registration key from device"
            echo
            echo -e "  ${D}Please provide the registration key:${RS}"
            read -rp "  Registration Key: " regkey
            [[ -z "$regkey" ]] && { msg_err "Registration key required for dossier"; return 1; }
        else
            msg_ok "Found registration key: ${BD}${regkey}${RS}"
        fi
    fi
    
    msg_info "Generating dossier via REST API..."
    
    local resp=$(f5_get_dossier "$ip" "$token" "$regkey")
    local dossier=$(echo "$resp" | jq -r '.dossier // empty' 2>/dev/null)
    
    # If REST API fails, try SSH
    if [[ -z "$dossier" || "$dossier" == "null" ]]; then
        local errmsg=$(echo "$resp" | jq -r '.message // empty' 2>/dev/null)
        msg_warn "REST API not available${errmsg:+ ($errmsg)}"
        
        msg_info "Trying SSH method..."
        
        # Check if sshpass is available for password auth
        if ! ssh_has_sshpass; then
            msg_warn "sshpass not installed - trying without password automation"
            msg "  ${D}If SSH key auth is not set up, you may need to install sshpass:${RS}"
            msg "  ${D}  macOS:  brew install hudochenkov/sshpass/sshpass${RS}"
            msg "  ${D}  Ubuntu: sudo apt install sshpass${RS}"
            msg "  ${D}  RHEL:   sudo yum install sshpass${RS}"
            echo
        fi
        
        # Try to get dossier via SSH
        dossier=$(f5_ssh_dossier "$ip" "$regkey" 2>/dev/null)
        
        # Clean up the dossier (remove any shell prompts or extra output)
        if [[ -n "$dossier" ]]; then
            # Extract just the dossier string (base64-like characters)
            dossier=$(echo "$dossier" | grep -oE '[a-f0-9]{20,}' | head -1)
        fi
        
        if [[ -z "$dossier" ]]; then
            msg_err "SSH dossier generation failed"
            echo
            echo -e "  ${BD}MANUAL DOSSIER GENERATION${RS}"
            echo
            echo -e "  ${D}SSH to the F5 device and run:${RS}"
            echo
            echo -e "    ${BD}ssh $F5_USER@$ip${RS}"
            echo -e "    ${BD}bash${RS}  ${D}(if not already in bash)${RS}"
            echo -e "    ${BD}get_dossier -b $regkey${RS}"
            echo
            echo -e "  ${D}Then paste the dossier at:${RS}"
            echo -e "    ${BD}https://activate.f5.com/license/dossier.jsp${RS}"
            echo
            
            # Offer to try interactive SSH
            read -rp "  Try interactive SSH now? [y/N]: " try_ssh
            if [[ "$try_ssh" =~ ^[Yy]$ ]]; then
                echo
                msg_info "Opening SSH session to $ip..."
                msg "  ${D}Run: get_dossier -b $regkey${RS}"
                msg "  ${D}Then copy the output and type 'exit' to return${RS}"
                echo
                
                if ssh_has_sshpass; then
                    sshpass -p "$F5_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$F5_USER@$ip"
                else
                    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$F5_USER@$ip"
                fi
            fi
            return 1
        else
            msg_ok "Dossier retrieved via SSH"
        fi
    else
        msg_ok "Dossier generated via REST API"
    fi
    
    echo
    echo -e "  ${BD}DOSSIER${RS}"
    echo -e "  ${D}Registration Key: $regkey${RS}"
    echo
    line 60
    echo "$dossier" | fold -w 58 | sed 's/^/  /'
    line 60
    echo
    echo -e "  ${BD}NEXT STEPS${RS}"
    echo -e "  ${D}1. Copy the dossier above${RS}"
    echo -e "  ${D}2. Go to: ${RS}${BD}https://activate.f5.com/license/dossier.jsp${RS}"
    echo -e "  ${D}3. Paste the dossier and click ${RS}${BD}Next${RS}"
    echo -e "  ${D}4. Download license file, or copy content to ${RS}${BD}/config/bigip.license${RS}"
    echo -e "  ${D}5. Reload the license: ${RS}${BD}reload $ip${RS}${D} (or SSH: reloadlic)${RS}"
    echo
    
    local file="${DATA_DIR}/dossier_${ip//./_}.txt"
    echo "$dossier" > "$file"
    msg "  ${D}Saved to: $file${RS}"
    
    log_event "DOSSIER $ip ($regkey)"
}

cmd_export() {
    local file="${DATA_DIR}/export_$(date +%Y%m%d_%H%M%S).csv"
    
    echo "ip,expires,days,status,regkey,checked" > "$file"
    jq -r '.[] | [.ip, .expires, .days, .status, .regkey, .checked] | @csv' "$DB_FILE" >> "$file"
    
    msg_ok "Exported to $file"
}

cmd_history() {
    echo
    echo -e "  ${BD}RECENT HISTORY${RS}"
    echo
    
    if [[ ! -s "$LOG_FILE" ]]; then
        msg "  ${D}No history yet${RS}"
        return
    fi
    
    tail -15 "$LOG_FILE" | sed 's/^/  /'
    echo
}

# -----------------------------------------------------------------------------
# COMMAND ROUTER
# -----------------------------------------------------------------------------
run_cmd() {
    local input="$1"
    local cmd="${input%% *}"
    local args="${input#* }"
    [[ "$args" == "$cmd" ]] && args=""
    
    # Split args
    local arg1="${args%% *}"
    local arg2="${args#* }"
    [[ "$arg2" == "$arg1" ]] && arg2=""
    
    case "$cmd" in
        add|a)         cmd_add "$arg1" ;;
        add-multi|am)  cmd_add_multi ;;
        remove|rm|r)   cmd_remove "$arg1" ;;
        list|ls|l)     cmd_list ;;
        check|c)       cmd_check "$arg1" ;;
        details|d|info)cmd_details "$arg1" ;;
        renew)         cmd_renew "$arg1" "$arg2" ;;
        reload)        cmd_reload "$arg1" ;;
        activate)      cmd_activate "$arg1" ;;
        dossier)       cmd_dossier "$arg1" "$arg2" ;;
        export)        cmd_export ;;
        history|h)     cmd_history ;;
        refresh|clear) show_header; show_stats; show_devices ;;
        help|"?")      cmd_help ;;
        quit|exit|q)   echo -e "\n  ${D}Goodbye!${RS}\n"; exit 0 ;;
        "")            ;; # empty
        *)
            if [[ "$cmd" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                cmd_details "$cmd"
            else
                msg_err "Unknown command: $cmd"
                msg "      ${D}Type 'help' for commands${RS}"
            fi
            ;;
    esac
}

# -----------------------------------------------------------------------------
# READLINE & AUTO-COMPLETION
# -----------------------------------------------------------------------------
COMMANDS="add add-multi remove list check details renew reload activate dossier export history refresh help quit"
COMMANDS_SHORT="a am r rm ls l c d i h q"

# Get list of device IPs for completion
get_device_ips() {
    jq -r '.[].ip' "$DB_FILE" 2>/dev/null | tr '\n' ' '
}

# Tab completion function - called by readline
_complete_f5lm() {
    local cur="${READLINE_LINE##* }"  # Current word being typed
    local line="${READLINE_LINE}"
    local words=($line)
    local word_count=${#words[@]}
    
    # If cursor is at end and there's a trailing space, we're completing next word
    if [[ "${READLINE_LINE: -1}" == " " ]]; then
        ((word_count++))
        cur=""
    fi
    
    local completions=""
    
    if [[ $word_count -le 1 ]]; then
        # Completing command name
        for cmd in $COMMANDS $COMMANDS_SHORT; do
            if [[ "$cmd" == "$cur"* ]]; then
                completions="$completions $cmd"
            fi
        done
    else
        # Completing argument (IP address)
        local cmd="${words[0]}"
        case "$cmd" in
            remove|rm|r|check|c|details|d|info|i|renew|reload|activate|dossier)
                # Add device IPs and 'all' option
                local ips=$(get_device_ips)
                for ip in $ips all; do
                    if [[ "$ip" == "$cur"* ]]; then
                        completions="$completions $ip"
                    fi
                done
                ;;
        esac
    fi
    
    # Trim leading space
    completions="${completions# }"
    
    # Count matches
    local matches=($completions)
    local match_count=${#matches[@]}
    
    if [[ $match_count -eq 1 ]]; then
        # Single match - complete it
        if [[ $word_count -le 1 ]]; then
            READLINE_LINE="${matches[0]} "
        else
            # Replace current word
            local prefix="${READLINE_LINE% *}"
            if [[ "$prefix" == "$READLINE_LINE" ]]; then
                prefix=""
            else
                prefix="$prefix "
            fi
            READLINE_LINE="${prefix}${matches[0]} "
        fi
        READLINE_POINT=${#READLINE_LINE}
    elif [[ $match_count -gt 1 ]]; then
        # Multiple matches - show them
        echo
        echo "  $completions"
        show_prompt
        # Redraw current line
        echo -n "$READLINE_LINE"
    fi
}

# Setup readline bindings for interactive mode
setup_readline() {
    # Bind Tab to our completion function
    bind -x '"\t":"_complete_f5lm"' 2>/dev/null
    
    # Readline settings
    bind 'set show-all-if-ambiguous on' 2>/dev/null
    bind 'set completion-ignore-case on' 2>/dev/null
    bind 'set bell-style none' 2>/dev/null
    
    # Enable history search with arrow keys
    bind '"\e[A": history-search-backward' 2>/dev/null
    bind '"\e[B": history-search-forward' 2>/dev/null
}

# -----------------------------------------------------------------------------
# INTERACTIVE MODE
# -----------------------------------------------------------------------------
interactive() {
    show_header
    show_stats
    show_devices
    
    # Command history
    HISTFILE="${DATA_DIR}/.history"
    HISTSIZE=100
    HISTCONTROL=ignoredups:erasedups
    touch "$HISTFILE"
    
    # Load history
    history -r "$HISTFILE" 2>/dev/null
    
    # Setup readline with tab completion
    setup_readline
    
    while true; do
        show_prompt
        # Use read -e for readline support (arrow keys, history)
        if read -e -r input; then
            # Add to history if not empty
            if [[ -n "$input" ]]; then
                history -s "$input" 2>/dev/null
                history -w "$HISTFILE" 2>/dev/null
            fi
            run_cmd "$input"
        else
            # EOF (Ctrl+D)
            echo
            exit 0
        fi
    done
}

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------
main() {
    check_deps
    init_db
    
    if [[ $# -eq 0 ]]; then
        interactive
    else
        case "$1" in
            -v|--version) echo "F5 License Manager v$VERSION" ;;
            -h|--help)    show_header; cmd_help ;;
            *)            run_cmd "$*" ;;
        esac
    fi
}

main "$@"

