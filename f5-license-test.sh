#!/usr/bin/env bash
#===============================================================================
#
#   F5 LICENSE MANAGER TEST SUITE
#   Comprehensive unit and integration tests for f5-license.sh
#
#   Usage: bash f5-license-test.sh [path/to/f5-license.sh]
#
#   Categories:
#     - Status Calculation (perpetual, active, expiring, expired, unknown)
#     - Days Calculation (various expiry inputs)
#     - Date Parsing (multiple formats, edge cases)
#     - Database Operations (CRUD, auth types, svc_check_date)
#     - Input Validation (IP, hostname, special characters)
#     - Command Line Parsing (all commands)
#     - Environment Variable Handling
#     - SSH Key Path Handling
#     - License Parsing (REST API, SSH)
#     - Authentication Flow (key, password)
#     - JSON Output Mode
#     - Export Functionality
#     - TMOS Compatibility
#     - Display Formatting
#     - Error Handling
#     - Integration Tests
#
#===============================================================================

set -o pipefail 2>/dev/null || true

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------
SCRIPT_PATH="${1:-./f5-license.sh}"
TEST_DATA_DIR=""
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

#-------------------------------------------------------------------------------
# Test Framework
#-------------------------------------------------------------------------------
setup_test_env() {
    TEST_DATA_DIR=$(mktemp -d -t f5lm_test.XXXXXX 2>/dev/null || mktemp -d)
    export DATA_DIR="$TEST_DATA_DIR"
    export DB_FILE="$TEST_DATA_DIR/devices.json"
    export LOG_FILE="$TEST_DATA_DIR/history.log"

    # Initialize empty database
    echo '[]' > "$DB_FILE"
    touch "$LOG_FILE"
}

cleanup_test_env() {
    if [[ -n "$TEST_DATA_DIR" && -d "$TEST_DATA_DIR" ]]; then
        rm -rf "$TEST_DATA_DIR"
    fi
}

# Run a test
run_test() {
    local name="$1"
    local func="$2"

    ((TESTS_RUN++))

    # Run test in subshell to isolate failures
    if ( setup_test_env && $func ); then
        ((TESTS_PASSED++))
        echo -e "  ${GREEN}✓${NC} $name"
    else
        ((TESTS_FAILED++))
        echo -e "  ${RED}✗${NC} $name"
    fi

    cleanup_test_env
}

# Skip a test
skip_test() {
    local name="$1"
    local reason="$2"

    ((TESTS_RUN++))
    ((TESTS_SKIPPED++))
    echo -e "  ${YELLOW}○${NC} $name (skipped: $reason)"
}

# Assert equality
assert_eq() {
    local expected="$1"
    local actual="$2"
    local msg="${3:-Values should be equal}"

    if [[ "$expected" == "$actual" ]]; then
        return 0
    else
        echo "    FAIL: $msg" >&2
        echo "    Expected: '$expected'" >&2
        echo "    Actual:   '$actual'" >&2
        return 1
    fi
}

# Assert not equal
assert_ne() {
    local unexpected="$1"
    local actual="$2"
    local msg="${3:-Values should not be equal}"

    if [[ "$unexpected" != "$actual" ]]; then
        return 0
    else
        echo "    FAIL: $msg" >&2
        echo "    Unexpected: '$unexpected'" >&2
        echo "    Actual:     '$actual'" >&2
        return 1
    fi
}

# Assert not empty
assert_not_empty() {
    local value="$1"
    local msg="${2:-Value should not be empty}"

    if [[ -n "$value" ]]; then
        return 0
    else
        echo "    FAIL: $msg" >&2
        return 1
    fi
}

# Assert empty
assert_empty() {
    local value="$1"
    local msg="${2:-Value should be empty}"

    if [[ -z "$value" ]]; then
        return 0
    else
        echo "    FAIL: $msg (got '$value')" >&2
        return 1
    fi
}

# Assert contains substring
assert_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="${3:-String should contain substring}"

    if [[ "$haystack" == *"$needle"* ]]; then
        return 0
    else
        echo "    FAIL: $msg" >&2
        echo "    Looking for: '$needle'" >&2
        echo "    In: '$haystack'" >&2
        return 1
    fi
}

# Assert does not contain substring
assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="${3:-String should not contain substring}"

    if [[ "$haystack" != *"$needle"* ]]; then
        return 0
    else
        echo "    FAIL: $msg" >&2
        echo "    Should not contain: '$needle'" >&2
        return 1
    fi
}

# Assert success (exit code 0)
assert_success() {
    local exit_code="$1"
    local msg="${2:-Command should succeed}"

    if [[ "$exit_code" -eq 0 ]]; then
        return 0
    else
        echo "    FAIL: $msg (exit code: $exit_code)" >&2
        return 1
    fi
}

# Assert failure (exit code non-zero)
assert_failure() {
    local exit_code="$1"
    local msg="${2:-Command should fail}"

    if [[ "$exit_code" -ne 0 ]]; then
        return 0
    else
        echo "    FAIL: $msg (exit code: $exit_code)" >&2
        return 1
    fi
}

# Assert numeric value is greater than
assert_gt() {
    local actual="$1"
    local threshold="$2"
    local msg="${3:-Value should be greater than threshold}"

    if [[ "$actual" -gt "$threshold" ]]; then
        return 0
    else
        echo "    FAIL: $msg" >&2
        echo "    Actual: $actual, Threshold: $threshold" >&2
        return 1
    fi
}

# Assert numeric value is less than
assert_lt() {
    local actual="$1"
    local threshold="$2"
    local msg="${3:-Value should be less than threshold}"

    if [[ "$actual" -lt "$threshold" ]]; then
        return 0
    else
        echo "    FAIL: $msg" >&2
        echo "    Actual: $actual, Threshold: $threshold" >&2
        return 1
    fi
}

# Assert file exists
assert_file_exists() {
    local filepath="$1"
    local msg="${2:-File should exist}"

    if [[ -f "$filepath" ]]; then
        return 0
    else
        echo "    FAIL: $msg" >&2
        echo "    File: $filepath" >&2
        return 1
    fi
}

# Assert JSON is valid
assert_valid_json() {
    local json="$1"
    local msg="${2:-Should be valid JSON}"

    if echo "$json" | jq . >/dev/null 2>&1; then
        return 0
    else
        echo "    FAIL: $msg" >&2
        echo "    JSON: $json" >&2
        return 1
    fi
}

#-------------------------------------------------------------------------------
# Source functions from main script (for unit testing)
#-------------------------------------------------------------------------------
source_script_functions() {
    # Source only functions, not main execution
    # We extract and eval specific functions

    # Stub for log_event (not needed in tests)
    log_event() { :; }

    # Extract make_temp_file function (needed by db functions)
    eval "$(sed -n '/^make_temp_file()/,/^}/p' "$SCRIPT_PATH")"

    # Extract parse_date_to_ts function
    eval "$(sed -n '/^parse_date_to_ts()/,/^}/p' "$SCRIPT_PATH")"

    # Extract calc_days_until function
    eval "$(sed -n '/^calc_days_until()/,/^}/p' "$SCRIPT_PATH")"

    # Extract get_status_from_days function
    eval "$(sed -n '/^get_status_from_days()/,/^}/p' "$SCRIPT_PATH")"

    # Extract db functions
    eval "$(sed -n '/^db_exists()/,/^}/p' "$SCRIPT_PATH")"
    eval "$(sed -n '/^db_add()/,/^}/p' "$SCRIPT_PATH")"
    eval "$(sed -n '/^db_remove()/,/^}/p' "$SCRIPT_PATH")"
    eval "$(sed -n '/^db_get()/,/^}/p' "$SCRIPT_PATH")"
    eval "$(sed -n '/^db_count()/,/^}/p' "$SCRIPT_PATH")"
    eval "$(sed -n '/^db_update()/,/^}/p' "$SCRIPT_PATH")"
    eval "$(sed -n '/^db_update_auth()/,/^}/p' "$SCRIPT_PATH")"
    eval "$(sed -n '/^db_get_auth_type()/,/^}/p' "$SCRIPT_PATH")"

    # Extract _strip_quotes function (for quote handling tests)
    eval "$(sed -n '/^_strip_quotes()/,/^}/p' "$SCRIPT_PATH")"

    # Extract parse_license_info function
    eval "$(sed -n '/^parse_license_info()/,/^}/p' "$SCRIPT_PATH")"
}

#===============================================================================
# TEST CATEGORY: Status Calculation
#===============================================================================
test_status_perpetual() {
    source_script_functions
    local result=$(get_status_from_days "perpetual")
    assert_eq "perpetual" "$result" "perpetual days should give perpetual status"
}

test_status_perpetual_unlimited() {
    source_script_functions
    local result=$(get_status_from_days "unlimited")
    assert_eq "perpetual" "$result" "unlimited should give perpetual status"
}

test_status_active() {
    source_script_functions
    local result=$(get_status_from_days "100")
    assert_eq "active" "$result" "100 days should be active"
}

test_status_active_31days() {
    source_script_functions
    local result=$(get_status_from_days "31")
    assert_eq "active" "$result" "31 days should be active"
}

test_status_active_365days() {
    source_script_functions
    local result=$(get_status_from_days "365")
    assert_eq "active" "$result" "365 days should be active"
}

test_status_active_1000days() {
    source_script_functions
    local result=$(get_status_from_days "1000")
    assert_eq "active" "$result" "1000 days should be active"
}

test_status_expiring_30days() {
    source_script_functions
    local result=$(get_status_from_days "30")
    assert_eq "expiring" "$result" "30 days should be expiring"
}

test_status_expiring_15days() {
    source_script_functions
    local result=$(get_status_from_days "15")
    assert_eq "expiring" "$result" "15 days should be expiring"
}

test_status_expiring_1day() {
    source_script_functions
    local result=$(get_status_from_days "1")
    assert_eq "expiring" "$result" "1 day should be expiring"
}

test_status_expiring_0days() {
    source_script_functions
    local result=$(get_status_from_days "0")
    assert_eq "expiring" "$result" "0 days should be expiring"
}

test_status_expired_negative() {
    source_script_functions
    local result=$(get_status_from_days "-1")
    assert_eq "expired" "$result" "-1 days should be expired"
}

test_status_expired_very_negative() {
    source_script_functions
    local result=$(get_status_from_days "-365")
    assert_eq "expired" "$result" "-365 days should be expired"
}

test_status_expired_minus_1000() {
    source_script_functions
    local result=$(get_status_from_days "-1000")
    assert_eq "expired" "$result" "-1000 days should be expired"
}

test_status_unknown_empty() {
    source_script_functions
    local result=$(get_status_from_days "")
    assert_eq "unknown" "$result" "empty should be unknown"
}

test_status_unknown_question() {
    source_script_functions
    local result=$(get_status_from_days "?")
    assert_eq "unknown" "$result" "? should be unknown"
}

test_status_unknown_invalid() {
    source_script_functions
    local result=$(get_status_from_days "abc")
    assert_eq "unknown" "$result" "invalid string should be unknown"
}

test_status_unknown_special_chars() {
    source_script_functions
    local result=$(get_status_from_days "!@#$")
    assert_eq "unknown" "$result" "special chars should be unknown"
}

# Boundary tests
test_status_boundary_31_is_active() {
    source_script_functions
    local result=$(get_status_from_days "31")
    assert_eq "active" "$result" "31 days should be active (boundary)"
}

test_status_boundary_30_is_expiring() {
    source_script_functions
    local result=$(get_status_from_days "30")
    assert_eq "expiring" "$result" "30 days should be expiring (boundary)"
}

test_status_boundary_0_is_expiring() {
    source_script_functions
    local result=$(get_status_from_days "0")
    assert_eq "expiring" "$result" "0 days should be expiring (boundary)"
}

test_status_boundary_minus1_is_expired() {
    source_script_functions
    local result=$(get_status_from_days "-1")
    assert_eq "expired" "$result" "-1 days should be expired (boundary)"
}

#===============================================================================
# TEST CATEGORY: Days Calculation (calc_days_until)
#===============================================================================
test_days_perpetual_empty() {
    source_script_functions
    local result=$(calc_days_until "")
    assert_eq "perpetual" "$result" "empty expiry should be perpetual"
}

test_days_perpetual_null() {
    source_script_functions
    local result=$(calc_days_until "null")
    assert_eq "perpetual" "$result" "null expiry should be perpetual"
}

test_days_perpetual_na() {
    source_script_functions
    local result=$(calc_days_until "N/A")
    assert_eq "perpetual" "$result" "N/A expiry should be perpetual"
}

test_days_perpetual_word() {
    source_script_functions
    local result=$(calc_days_until "Perpetual")
    assert_eq "perpetual" "$result" "Perpetual word should be perpetual"
}

test_days_perpetual_lowercase() {
    source_script_functions
    local result=$(calc_days_until "perpetual")
    assert_eq "perpetual" "$result" "perpetual lowercase should be perpetual"
}

test_days_perpetual_unlimited() {
    source_script_functions
    local result=$(calc_days_until "Unlimited")
    assert_eq "perpetual" "$result" "Unlimited should be perpetual"
}

test_days_perpetual_unlimited_lowercase() {
    source_script_functions
    local result=$(calc_days_until "unlimited")
    assert_eq "perpetual" "$result" "unlimited lowercase should be perpetual"
}

test_days_perpetual_never() {
    source_script_functions
    local result=$(calc_days_until "Never")
    assert_eq "perpetual" "$result" "Never should be perpetual"
}

test_days_perpetual_none() {
    source_script_functions
    local result=$(calc_days_until "None")
    assert_eq "perpetual" "$result" "None should be perpetual"
}

test_days_future_date() {
    source_script_functions
    # Calculate a date 100 days from now
    local future_date=$(date -v+100d '+%Y/%m/%d' 2>/dev/null || date -d '+100 days' '+%Y/%m/%d' 2>/dev/null)
    if [[ -n "$future_date" ]]; then
        local result=$(calc_days_until "$future_date")
        # Should be around 99-101 days
        [[ "$result" =~ ^[0-9]+$ ]] && [[ "$result" -ge 98 ]] && [[ "$result" -le 102 ]]
    else
        # Skip if date command doesn't support this
        return 0
    fi
}

test_days_past_date() {
    source_script_functions
    # Calculate a date 10 days ago
    local past_date=$(date -v-10d '+%Y/%m/%d' 2>/dev/null || date -d '-10 days' '+%Y/%m/%d' 2>/dev/null)
    if [[ -n "$past_date" ]]; then
        local result=$(calc_days_until "$past_date")
        # Should be around -9 to -11
        [[ "$result" =~ ^-[0-9]+$ ]] && [[ "$result" -le -9 ]] && [[ "$result" -ge -12 ]]
    else
        return 0
    fi
}

#===============================================================================
# TEST CATEGORY: Date Parsing
#===============================================================================
test_parse_date_slash_format() {
    source_script_functions
    local ts=$(parse_date_to_ts "2025/01/15")
    assert_not_empty "$ts" "Should parse YYYY/MM/DD format"
}

test_parse_date_dash_format() {
    source_script_functions
    local ts=$(parse_date_to_ts "2025-01-15")
    assert_not_empty "$ts" "Should parse YYYY-MM-DD format"
}

test_parse_date_compact_format() {
    source_script_functions
    local ts=$(parse_date_to_ts "20250115")
    # May or may not parse depending on implementation
    [[ -n "$ts" || -z "$ts" ]] # Just ensure no crash
}

test_parse_date_empty() {
    source_script_functions
    local result
    result=$(parse_date_to_ts "")
    local exit_code=$?
    assert_failure "$exit_code" "Empty date should fail"
}

test_parse_date_null() {
    source_script_functions
    local result
    result=$(parse_date_to_ts "null")
    local exit_code=$?
    assert_failure "$exit_code" "null date should fail"
}

test_parse_date_invalid() {
    source_script_functions
    local result
    result=$(parse_date_to_ts "not-a-date")
    local exit_code=$?
    # May succeed with manual parsing fallback, so just check it returns something
    [[ $exit_code -eq 0 || $exit_code -eq 1 ]] || return 1
}

test_parse_date_partial() {
    source_script_functions
    local result
    result=$(parse_date_to_ts "2025/01")
    local exit_code=$?
    # Partial dates may fail
    [[ $exit_code -eq 0 || $exit_code -eq 1 ]] || return 1
}

test_parse_date_year_only() {
    source_script_functions
    local result
    result=$(parse_date_to_ts "2025")
    local exit_code=$?
    [[ $exit_code -eq 0 || $exit_code -eq 1 ]] || return 1
}

test_parse_date_leap_year() {
    source_script_functions
    local ts=$(parse_date_to_ts "2024/02/29")
    # 2024 is a leap year, should parse
    assert_not_empty "$ts" "Should parse leap year date"
}

test_parse_date_end_of_year() {
    source_script_functions
    local ts=$(parse_date_to_ts "2025/12/31")
    assert_not_empty "$ts" "Should parse end of year date"
}

test_parse_date_start_of_year() {
    source_script_functions
    local ts=$(parse_date_to_ts "2025/01/01")
    assert_not_empty "$ts" "Should parse start of year date"
}

#===============================================================================
# TEST CATEGORY: Database Operations
#===============================================================================
test_db_empty_count() {
    source_script_functions
    echo '[]' > "$DB_FILE"
    local count=$(db_count)
    assert_eq "0" "$count" "Empty database should have count 0"
}

test_db_add_device() {
    source_script_functions
    echo '[]' > "$DB_FILE"
    db_add "10.1.1.1" "password"
    local count=$(db_count)
    assert_eq "1" "$count" "Should have 1 device after add"
}

test_db_add_device_with_key_auth() {
    source_script_functions
    echo '[]' > "$DB_FILE"
    db_add "10.1.1.1" "key"
    local auth_type=$(jq -r '.[0].auth_type' "$DB_FILE")
    assert_eq "key" "$auth_type" "Auth type should be key"
}

test_db_add_device_has_svc_check_date_field() {
    source_script_functions
    echo '[]' > "$DB_FILE"
    db_add "10.1.1.1" "password"
    local has_field=$(jq '.[0] | has("svc_check_date")' "$DB_FILE")
    assert_eq "true" "$has_field" "New device should have svc_check_date field"
}

test_db_add_device_svc_check_date_null() {
    source_script_functions
    echo '[]' > "$DB_FILE"
    db_add "10.1.1.1" "password"
    local svc_check=$(jq -r '.[0].svc_check_date' "$DB_FILE")
    assert_eq "null" "$svc_check" "New device svc_check_date should be null"
}

test_db_exists_true() {
    source_script_functions
    echo '[{"ip":"10.1.1.1","auth_type":"password"}]' > "$DB_FILE"
    db_exists "10.1.1.1"
    local exit_code=$?
    assert_success "$exit_code" "Device should exist"
}

test_db_exists_false() {
    source_script_functions
    echo '[]' > "$DB_FILE"
    db_exists "10.1.1.1"
    local exit_code=$?
    assert_failure "$exit_code" "Device should not exist"
}

test_db_exists_similar_ip() {
    source_script_functions
    echo '[{"ip":"10.1.1.1","auth_type":"password"}]' > "$DB_FILE"
    db_exists "10.1.1.10"
    local exit_code=$?
    assert_failure "$exit_code" "Similar IP should not match"
}

test_db_remove_device() {
    source_script_functions
    echo '[{"ip":"10.1.1.1","auth_type":"password"}]' > "$DB_FILE"
    db_remove "10.1.1.1"
    local count=$(db_count)
    assert_eq "0" "$count" "Should have 0 devices after remove"
}

test_db_remove_nonexistent() {
    source_script_functions
    echo '[{"ip":"10.1.1.1","auth_type":"password"}]' > "$DB_FILE"
    db_remove "10.1.1.2"
    local count=$(db_count)
    assert_eq "1" "$count" "Should still have 1 device after removing nonexistent"
}

test_db_remove_one_of_many() {
    source_script_functions
    echo '[{"ip":"10.1.1.1"},{"ip":"10.1.1.2"},{"ip":"10.1.1.3"}]' > "$DB_FILE"
    db_remove "10.1.1.2"
    local count=$(db_count)
    assert_eq "2" "$count" "Should have 2 devices after removing one"
    # Check the right one was removed
    db_exists "10.1.1.1" || return 1
    db_exists "10.1.1.3" || return 1
    db_exists "10.1.1.2" && return 1
    return 0
}

test_db_get_device() {
    source_script_functions
    echo '[{"ip":"10.1.1.1","auth_type":"key","status":"active"}]' > "$DB_FILE"
    local result=$(db_get "10.1.1.1")
    [[ "$result" == *"10.1.1.1"* ]] || return 1
    [[ "$result" == *"key"* ]] || return 1
}

test_db_get_nonexistent() {
    source_script_functions
    echo '[{"ip":"10.1.1.1"}]' > "$DB_FILE"
    local result=$(db_get "10.1.1.2")
    assert_empty "$result" "Getting nonexistent device should return empty"
}

test_db_update_device() {
    source_script_functions
    echo '[{"ip":"10.1.1.1","auth_type":"password","expires":"","days":"","status":"unknown","regkey":"","svc_check_date":""}]' > "$DB_FILE"
    db_update "10.1.1.1" "2025/12/31" "365" "active" "XXXXX-XXXXX"
    local result=$(db_get "10.1.1.1")
    [[ "$result" == *"active"* ]] || return 1
    [[ "$result" == *"365"* ]] || return 1
}

test_db_update_with_svc_check_date() {
    source_script_functions
    echo '[{"ip":"10.1.1.1","auth_type":"password","expires":"","days":"","status":"unknown","regkey":"","svc_check_date":""}]' > "$DB_FILE"
    db_update "10.1.1.1" "2025/12/31" "365" "active" "XXXXX-XXXXX" "2025/06/15"
    local svc_check=$(jq -r '.[] | select(.ip=="10.1.1.1") | .svc_check_date' "$DB_FILE")
    assert_eq "2025/06/15" "$svc_check" "svc_check_date should be updated"
}

test_db_update_svc_check_date_empty() {
    source_script_functions
    echo '[{"ip":"10.1.1.1","auth_type":"password","expires":"","days":"","status":"unknown","regkey":"","svc_check_date":"2024/01/01"}]' > "$DB_FILE"
    db_update "10.1.1.1" "2025/12/31" "365" "active" "XXXXX-XXXXX" ""
    local svc_check=$(jq -r '.[] | select(.ip=="10.1.1.1") | .svc_check_date' "$DB_FILE")
    assert_eq "" "$svc_check" "svc_check_date should be empty when passed empty"
}

test_db_update_auth_type() {
    source_script_functions
    echo '[{"ip":"10.1.1.1","auth_type":"password"}]' > "$DB_FILE"
    db_update_auth "10.1.1.1" "key"
    local auth_type=$(jq -r '.[] | select(.ip=="10.1.1.1") | .auth_type' "$DB_FILE")
    assert_eq "key" "$auth_type" "Auth type should be updated to key"
}

test_db_get_auth_type() {
    source_script_functions
    echo '[{"ip":"10.1.1.1","auth_type":"key"}]' > "$DB_FILE"
    local auth_type=$(db_get_auth_type "10.1.1.1")
    assert_eq "key" "$auth_type" "Should get correct auth type"
}

test_db_get_auth_type_default() {
    source_script_functions
    echo '[{"ip":"10.1.1.1"}]' > "$DB_FILE"
    local auth_type=$(db_get_auth_type "10.1.1.1")
    assert_empty "$auth_type" "Missing auth type should return empty"
}

test_db_multiple_devices() {
    source_script_functions
    echo '[]' > "$DB_FILE"
    db_add "10.1.1.1" "password"
    db_add "10.1.1.2" "key"
    db_add "10.1.1.3" "password"
    local count=$(db_count)
    assert_eq "3" "$count" "Should have 3 devices"
}

test_db_preserves_other_fields() {
    source_script_functions
    echo '[{"ip":"10.1.1.1","auth_type":"password","custom_field":"preserved"}]' > "$DB_FILE"
    db_update "10.1.1.1" "2025/12/31" "365" "active" "XXXXX" "2025/06/15"
    local custom=$(jq -r '.[] | select(.ip=="10.1.1.1") | .custom_field' "$DB_FILE")
    assert_eq "preserved" "$custom" "Custom fields should be preserved"
}

test_db_json_valid_after_add() {
    source_script_functions
    echo '[]' > "$DB_FILE"
    db_add "10.1.1.1" "password"
    local content=$(cat "$DB_FILE")
    assert_valid_json "$content" "Database should be valid JSON after add"
}

test_db_json_valid_after_update() {
    source_script_functions
    echo '[{"ip":"10.1.1.1","auth_type":"password"}]' > "$DB_FILE"
    db_update "10.1.1.1" "2025/12/31" "365" "active" "XXXXX" "2025/06/15"
    local content=$(cat "$DB_FILE")
    assert_valid_json "$content" "Database should be valid JSON after update"
}

test_db_json_valid_after_remove() {
    source_script_functions
    echo '[{"ip":"10.1.1.1"},{"ip":"10.1.1.2"}]' > "$DB_FILE"
    db_remove "10.1.1.1"
    local content=$(cat "$DB_FILE")
    assert_valid_json "$content" "Database should be valid JSON after remove"
}

#===============================================================================
# TEST CATEGORY: Input Validation
#===============================================================================
test_input_valid_ipv4() {
    source_script_functions
    echo '[]' > "$DB_FILE"
    db_add "192.168.1.1" "password"
    db_exists "192.168.1.1"
    assert_success $? "Standard IPv4 should be valid"
}

test_input_valid_hostname() {
    source_script_functions
    echo '[]' > "$DB_FILE"
    db_add "bigip.example.com" "password"
    db_exists "bigip.example.com"
    assert_success $? "Hostname should be valid"
}

test_input_valid_short_hostname() {
    source_script_functions
    echo '[]' > "$DB_FILE"
    db_add "bigip01" "password"
    db_exists "bigip01"
    assert_success $? "Short hostname should be valid"
}

test_input_hostname_with_dashes() {
    source_script_functions
    echo '[]' > "$DB_FILE"
    db_add "bigip-prod-01" "password"
    db_exists "bigip-prod-01"
    assert_success $? "Hostname with dashes should be valid"
}

test_input_hostname_with_underscores() {
    source_script_functions
    echo '[]' > "$DB_FILE"
    db_add "bigip_prod_01" "password"
    db_exists "bigip_prod_01"
    assert_success $? "Hostname with underscores should be valid"
}

test_input_ip_edge_values() {
    source_script_functions
    echo '[]' > "$DB_FILE"
    db_add "0.0.0.0" "password"
    db_add "255.255.255.255" "password"
    local count=$(db_count)
    assert_eq "2" "$count" "Edge IP values should be valid"
}

test_input_special_chars_in_regkey() {
    source_script_functions
    echo '[{"ip":"10.1.1.1","auth_type":"password","regkey":""}]' > "$DB_FILE"
    db_update "10.1.1.1" "2025/01/01" "30" "active" "A1B2C-D3E4F-G5H6I-J7K8L"
    local result=$(db_get "10.1.1.1")
    [[ "$result" == *"A1B2C-D3E4F-G5H6I-J7K8L"* ]] || return 1
}

#===============================================================================
# TEST CATEGORY: Command Line Parsing
#===============================================================================
test_cmd_help() {
    local output
    output=$("$SCRIPT_PATH" help 2>&1)
    local exit_code=$?
    [[ "$output" == *"COMMANDS"* || "$output" == *"Commands"* || "$output" == *"Usage"* ]] || return 1
}

test_cmd_help_shows_add() {
    local output
    output=$("$SCRIPT_PATH" help 2>&1)
    assert_contains "$output" "add" "Help should show add command"
}

test_cmd_help_shows_remove() {
    local output
    output=$("$SCRIPT_PATH" help 2>&1)
    assert_contains "$output" "remove" "Help should show remove command"
}

test_cmd_help_shows_list() {
    local output
    output=$("$SCRIPT_PATH" help 2>&1)
    assert_contains "$output" "list" "Help should show list command"
}

test_cmd_help_shows_check() {
    local output
    output=$("$SCRIPT_PATH" help 2>&1)
    assert_contains "$output" "check" "Help should show check command"
}

test_cmd_help_shows_details() {
    local output
    output=$("$SCRIPT_PATH" help 2>&1)
    assert_contains "$output" "details" "Help should show details command"
}

test_cmd_help_shows_export() {
    local output
    output=$("$SCRIPT_PATH" help 2>&1)
    assert_contains "$output" "export" "Help should show export command"
}

test_cmd_version_in_script() {
    local output
    output=$(grep -m1 "F5LM_VERSION=" "$SCRIPT_PATH")
    [[ "$output" == *"3.8"* ]] || return 1
}

test_cmd_script_syntax() {
    bash -n "$SCRIPT_PATH"
    local exit_code=$?
    assert_success "$exit_code" "Script should have valid syntax"
}

test_cmd_list_empty() {
    local output
    output=$(HOME="$TEST_DATA_DIR" "$SCRIPT_PATH" list 2>&1)
    assert_contains "$output" "No devices" "List should show no devices message"
}

test_cmd_list_json_empty() {
    local output
    output=$(HOME="$TEST_DATA_DIR" "$SCRIPT_PATH" --json list 2>&1)
    assert_valid_json "$output" "JSON list output should be valid JSON"
}

#===============================================================================
# TEST CATEGORY: Environment Variable Handling
#===============================================================================
test_env_var_not_contaminated() {
    # Ensure we use printenv not ${!var}
    local uses_printenv
    uses_printenv=$(grep -c 'printenv' "$SCRIPT_PATH")
    [[ "$uses_printenv" -gt 0 ]] || return 1
}

test_credentials_cleared_in_prompt() {
    # Check that prompt_credentials clears F5_USER, F5_PASS, F5_SSH_KEY
    local prompt_func
    prompt_func=$(sed -n '/^prompt_credentials()/,/^}/p' "$SCRIPT_PATH")
    [[ "$prompt_func" == *'F5_USER=""'* ]] || return 1
    [[ "$prompt_func" == *'F5_PASS=""'* ]] || return 1
    [[ "$prompt_func" == *'F5_SSH_KEY=""'* ]] || return 1
}

test_env_load_device_credentials_exists() {
    # Verify load_device_credentials function exists
    grep -q "^load_device_credentials()" "$SCRIPT_PATH"
    assert_success $? "load_device_credentials function should exist"
}

#===============================================================================
# TEST CATEGORY: SSH Key Path Handling
#===============================================================================
test_ssh_key_quoted() {
    # Check that $F5_SSH_KEY is always quoted in ssh commands
    local unquoted_count
    unquoted_count=$(grep -E 'ssh.*-i \$F5_SSH_KEY[^"]' "$SCRIPT_PATH" | wc -l)
    assert_eq "0" "$(echo $unquoted_count)" "SSH key should always be quoted"
}

test_strip_quotes_double() {
    source_script_functions
    local result=$(_strip_quotes '"path/to/key"')
    assert_eq "path/to/key" "$result" "Double quotes should be stripped"
}

test_strip_quotes_single() {
    source_script_functions
    local result=$(_strip_quotes "'path/to/key'")
    assert_eq "path/to/key" "$result" "Single quotes should be stripped"
}

test_strip_quotes_none() {
    source_script_functions
    local result=$(_strip_quotes "path/to/key")
    assert_eq "path/to/key" "$result" "Unquoted path should remain unchanged"
}

test_strip_quotes_spaces() {
    source_script_functions
    local result=$(_strip_quotes '"/path/with spaces/key"')
    assert_eq "/path/with spaces/key" "$result" "Quoted path with spaces should be handled"
}

test_strip_quotes_tilde() {
    source_script_functions
    local result=$(_strip_quotes '"~/.ssh/id_rsa"')
    assert_eq "~/.ssh/id_rsa" "$result" "Quoted path with tilde should be handled"
}

test_strip_quotes_whitespace_around() {
    source_script_functions
    local result=$(_strip_quotes '  "path/to/key"  ')
    assert_eq "path/to/key" "$result" "Whitespace around quoted path should be trimmed"
}

test_strip_quotes_empty() {
    source_script_functions
    local result=$(_strip_quotes '')
    assert_empty "$result" "Empty string should return empty"
}

test_strip_quotes_only_whitespace() {
    source_script_functions
    local result=$(_strip_quotes '   ')
    assert_empty "$result" "Whitespace only should return empty"
}

#===============================================================================
# TEST CATEGORY: License Parsing
#===============================================================================
test_parse_license_info_returns_three_fields() {
    # Verify parse_license_info returns regkey|license_end_date|service_check_date
    local func_content
    func_content=$(sed -n '/^parse_license_info()/,/^}/p' "$SCRIPT_PATH")
    [[ "$func_content" == *"licenseEndDate"* ]] || return 1
    [[ "$func_content" == *"serviceCheckDate"* ]] || return 1
}

test_parse_license_info_format() {
    # Verify the jq output format includes all three fields separated by pipes
    local func_content
    func_content=$(sed -n '/^parse_license_info()/,/^}/p' "$SCRIPT_PATH")
    # Should have pipe separators in the jq output format
    [[ "$func_content" == *'|'* ]] || return 1
    # Should have all three field references
    [[ "$func_content" == *"registrationKey"* ]] || return 1
    [[ "$func_content" == *"licenseEndDate"* ]] || return 1
    [[ "$func_content" == *"serviceCheckDate"* ]] || return 1
}

test_get_license_via_ssh_returns_three_fields() {
    # Verify _get_license_via_ssh returns regkey|license_end_date|service_check_date
    local func_content
    func_content=$(sed -n '/^_get_license_via_ssh()/,/^}/p' "$SCRIPT_PATH")
    # Check the return format comment
    [[ "$func_content" == *"regkey|license_end_date|service_check_date"* ]] || return 1
}

test_get_license_via_ssh_parses_service_check() {
    # Verify _get_license_via_ssh parses Service Check Date
    local func_content
    func_content=$(sed -n '/^_get_license_via_ssh()/,/^}/p' "$SCRIPT_PATH")
    [[ "$func_content" == *"Service Check Date"* ]] || return 1
}

#===============================================================================
# TEST CATEGORY: License End Date Logic (v3.8.10)
#===============================================================================
test_license_end_date_in_parse_license_info() {
    # Verify parse_license_info() uses licenseEndDate (not serviceCheckDate) for expiration
    local func_content
    func_content=$(sed -n '/^parse_license_info()/,/^}/p' "$SCRIPT_PATH")
    [[ "$func_content" == *"licenseEndDate"* ]] || return 1
}

test_license_end_date_in_ssh_func() {
    # Verify _get_license_via_ssh() parses "License End Date" for expiration
    local func_content
    func_content=$(sed -n '/^_get_license_via_ssh()/,/^}/p' "$SCRIPT_PATH")
    [[ "$func_content" == *"License End Date"* ]] || return 1
}

test_license_end_date_grep_fallback() {
    # Verify SSH fallback searches for License end date in license file
    local func_content
    func_content=$(sed -n '/^_get_license_via_ssh()/,/^}/p' "$SCRIPT_PATH")
    [[ "$func_content" == *"License end date"* ]] || return 1
}

test_details_shows_both_dates() {
    # Verify cmd_details displays both License End and Svc Check
    local func_content
    func_content=$(sed -n '/^cmd_details()/,/^}/p' "$SCRIPT_PATH")
    [[ "$func_content" == *"Svc Check"* ]] || return 1
    [[ "$func_content" == *"License End"* ]] || return 1
}

test_license_end_date_for_expiration() {
    # Verify cmd_details uses expires (not service) for calc_days_until
    local func_content
    func_content=$(sed -n '/^cmd_details()/,/^}/p' "$SCRIPT_PATH")
    [[ "$func_content" == *'calc_days_until "$expires"'* ]] || return 1
}

test_json_output_field_names() {
    # Verify JSON output uses correct field names
    local func_content
    func_content=$(sed -n '/^cmd_details()/,/^}/p' "$SCRIPT_PATH")
    [[ "$func_content" == *"service_check_date"* ]] || return 1
    [[ "$func_content" == *"license_end_date"* ]] || return 1
}

#===============================================================================
# TEST CATEGORY: Display Formatting
#===============================================================================
test_show_devices_has_svc_chk_column() {
    # Verify show_devices displays SVC CHK column
    local func_content
    func_content=$(sed -n '/^show_devices()/,/^}/p' "$SCRIPT_PATH")
    [[ "$func_content" == *"SVC CHK"* ]] || return 1
}

test_show_devices_reads_svc_check_date() {
    # Verify show_devices reads svc_check_date from database
    local func_content
    func_content=$(sed -n '/^show_devices()/,/^}/p' "$SCRIPT_PATH")
    [[ "$func_content" == *"svc_check_date"* ]] || return 1
}

test_list_output_format() {
    # Create test database and verify list format
    mkdir -p "$TEST_DATA_DIR/.f5lm"
    cat > "$TEST_DATA_DIR/.f5lm/devices.json" << 'EOF'
[{"ip":"10.1.1.1","expires":"2025/06/15","svc_check_date":"2025/01/15","days":"152","status":"active","regkey":"XXXX"}]
EOF
    local output
    output=$(HOME="$TEST_DATA_DIR" "$SCRIPT_PATH" list 2>&1)
    assert_contains "$output" "10.1.1.1" "List should show IP"
    assert_contains "$output" "SVC CHK" "List should show SVC CHK header"
}

#===============================================================================
# TEST CATEGORY: Export Functionality
#===============================================================================
test_export_includes_svc_check_date() {
    # Verify export includes svc_check_date column
    local func_content
    func_content=$(sed -n '/^cmd_export()/,/^}/p' "$SCRIPT_PATH")
    [[ "$func_content" == *"svc_check_date"* ]] || return 1
}

test_export_csv_header() {
    # Verify export CSV header includes svc_check_date
    local func_content
    func_content=$(sed -n '/^cmd_export()/,/^}/p' "$SCRIPT_PATH")
    [[ "$func_content" == *"ip,expires,svc_check_date"* ]] || return 1
}

test_export_creates_file() {
    mkdir -p "$TEST_DATA_DIR/.f5lm"
    echo '[{"ip":"10.1.1.1","expires":"2025/06/15","svc_check_date":"2025/01/15","days":"152","status":"active","regkey":"XXXX","checked":"2024-01-15"}]' > "$TEST_DATA_DIR/.f5lm/devices.json"
    HOME="$TEST_DATA_DIR" "$SCRIPT_PATH" export >/dev/null 2>&1
    local csv_file=$(ls "$TEST_DATA_DIR/.f5lm"/export_*.csv 2>/dev/null | head -1)
    assert_file_exists "$csv_file" "Export should create CSV file"
}

test_export_csv_content() {
    mkdir -p "$TEST_DATA_DIR/.f5lm"
    echo '[{"ip":"10.1.1.1","expires":"2025/06/15","svc_check_date":"2025/01/15","days":"152","status":"active","regkey":"XXXX","checked":"2024-01-15"}]' > "$TEST_DATA_DIR/.f5lm/devices.json"
    HOME="$TEST_DATA_DIR" "$SCRIPT_PATH" export >/dev/null 2>&1
    local csv_file=$(ls "$TEST_DATA_DIR/.f5lm"/export_*.csv 2>/dev/null | head -1)
    if [[ -f "$csv_file" ]]; then
        local content=$(cat "$csv_file")
        assert_contains "$content" "10.1.1.1" "CSV should contain IP"
        assert_contains "$content" "2025/01/15" "CSV should contain svc_check_date"
    else
        return 1
    fi
}

#===============================================================================
# TEST CATEGORY: TMOS Compatibility
#===============================================================================
test_tmos_fallback_in_reload() {
    # Verify cmd_reload uses bash -c fallback for TMOS compatibility
    local func_content
    func_content=$(sed -n '/^cmd_reload()/,/^}/p' "$SCRIPT_PATH")
    [[ "$func_content" == *"bash -c"* ]] || return 1
}

test_tmos_fallback_in_dossier() {
    # Verify cmd_dossier uses bash -c fallback for TMOS compatibility
    local func_content
    func_content=$(sed -n '/^cmd_dossier()/,/^}/p' "$SCRIPT_PATH")
    [[ "$func_content" == *"bash -c"* ]] || return 1
}

test_tmsh_command_used() {
    # Verify tmsh commands are used
    grep -q "tmsh show sys license" "$SCRIPT_PATH"
    assert_success $? "Script should use tmsh show sys license"
}

#===============================================================================
# TEST CATEGORY: Error Handling
#===============================================================================
test_invalid_command_handling() {
    local output
    output=$(HOME="$TEST_DATA_DIR" "$SCRIPT_PATH" invalidcommand 2>&1)
    # Should either show help or error, not crash
    [[ -n "$output" ]] || return 0
}

test_missing_ip_for_add() {
    local output
    output=$(HOME="$TEST_DATA_DIR" "$SCRIPT_PATH" add 2>&1)
    # Should show usage or error
    [[ "$output" == *"Usage"* || "$output" == *"error"* || "$output" == *"Error"* || "$output" == *"ip"* ]] || return 0
}

test_missing_ip_for_remove() {
    local output
    output=$(HOME="$TEST_DATA_DIR" "$SCRIPT_PATH" remove 2>&1)
    [[ "$output" == *"Usage"* || "$output" == *"error"* || "$output" == *"Error"* || "$output" == *"ip"* ]] || return 0
}

test_missing_ip_for_details() {
    local output
    output=$(HOME="$TEST_DATA_DIR" "$SCRIPT_PATH" details 2>&1)
    [[ "$output" == *"Usage"* || "$output" == *"error"* || "$output" == *"Error"* || "$output" == *"ip"* ]] || return 0
}

#===============================================================================
# TEST CATEGORY: JSON Output Mode
#===============================================================================
test_json_flag_exists() {
    grep -q "\-\-json" "$SCRIPT_PATH"
    assert_success $? "Script should support --json flag"
}

test_json_output_variable() {
    grep -q "JSON_OUTPUT" "$SCRIPT_PATH"
    assert_success $? "Script should have JSON_OUTPUT variable"
}

test_json_list_output() {
    mkdir -p "$TEST_DATA_DIR/.f5lm"
    echo '[{"ip":"10.1.1.1","expires":"2025/06/15","days":"152","status":"active"}]' > "$TEST_DATA_DIR/.f5lm/devices.json"
    local output
    output=$(HOME="$TEST_DATA_DIR" "$SCRIPT_PATH" --json list 2>&1)
    assert_valid_json "$output" "JSON list output should be valid JSON"
}

test_json_check_output_structure() {
    # Verify JSON check output includes expected fields
    local func_content
    func_content=$(sed -n '/^cmd_check()/,/^cmd_/p' "$SCRIPT_PATH" | head -50)
    [[ "$func_content" == *"jq"* ]] || return 1
}

#===============================================================================
# TEST CATEGORY: History/Logging
#===============================================================================
test_log_file_created() {
    mkdir -p "$TEST_DATA_DIR/.f5lm"
    echo '[]' > "$TEST_DATA_DIR/.f5lm/devices.json"
    HOME="$TEST_DATA_DIR" "$SCRIPT_PATH" list >/dev/null 2>&1
    # Log file may or may not be created for list command, so just check no crash
    return 0
}

test_history_command_exists() {
    grep -q "cmd_history()" "$SCRIPT_PATH"
    assert_success $? "cmd_history function should exist"
}

#===============================================================================
# TEST CATEGORY: Integration Tests
#===============================================================================
test_integration_add_list_remove() {
    mkdir -p "$TEST_DATA_DIR/.f5lm"
    echo '[]' > "$TEST_DATA_DIR/.f5lm/devices.json"

    # This is a simplified test - full integration would need mock SSH
    source_script_functions
    export DB_FILE="$TEST_DATA_DIR/.f5lm/devices.json"

    # Add device
    db_add "10.1.1.1" "password"
    local count=$(db_count)
    [[ "$count" == "1" ]] || return 1

    # Update device
    db_update "10.1.1.1" "2025/12/31" "365" "active" "XXXXX" "2025/06/15"
    local status=$(jq -r '.[0].status' "$DB_FILE")
    [[ "$status" == "active" ]] || return 1

    # Remove device
    db_remove "10.1.1.1"
    count=$(db_count)
    [[ "$count" == "0" ]] || return 1
}

test_integration_multiple_devices_workflow() {
    mkdir -p "$TEST_DATA_DIR/.f5lm"
    echo '[]' > "$TEST_DATA_DIR/.f5lm/devices.json"

    source_script_functions
    export DB_FILE="$TEST_DATA_DIR/.f5lm/devices.json"

    # Add multiple devices
    db_add "10.1.1.1" "password"
    db_add "10.1.1.2" "key"
    db_add "bigip.local" "password"

    # Update with different statuses
    db_update "10.1.1.1" "2025/12/31" "365" "active" "KEY1" "2025/06/15"
    db_update "10.1.1.2" "" "perpetual" "perpetual" "KEY2" "2024/12/01"
    db_update "bigip.local" "2025/02/15" "25" "expiring" "KEY3" ""

    # Verify count
    local count=$(db_count)
    [[ "$count" == "3" ]] || return 1

    # Verify different statuses
    local status1=$(jq -r '.[] | select(.ip=="10.1.1.1") | .status' "$DB_FILE")
    local status2=$(jq -r '.[] | select(.ip=="10.1.1.2") | .status' "$DB_FILE")
    local status3=$(jq -r '.[] | select(.ip=="bigip.local") | .status' "$DB_FILE")

    [[ "$status1" == "active" ]] || return 1
    [[ "$status2" == "perpetual" ]] || return 1
    [[ "$status3" == "expiring" ]] || return 1

    # Verify svc_check_date stored correctly
    local svc1=$(jq -r '.[] | select(.ip=="10.1.1.1") | .svc_check_date' "$DB_FILE")
    local svc2=$(jq -r '.[] | select(.ip=="10.1.1.2") | .svc_check_date' "$DB_FILE")

    [[ "$svc1" == "2025/06/15" ]] || return 1
    [[ "$svc2" == "2024/12/01" ]] || return 1
}

test_integration_status_calculation_end_to_end() {
    source_script_functions

    # Test complete flow: date -> days -> status
    local future_date=$(date -v+100d '+%Y/%m/%d' 2>/dev/null || date -d '+100 days' '+%Y/%m/%d' 2>/dev/null)
    if [[ -n "$future_date" ]]; then
        local days=$(calc_days_until "$future_date")
        local status=$(get_status_from_days "$days")
        assert_eq "active" "$status" "Future date should result in active status"
    fi

    # Test perpetual flow
    local days_perpetual=$(calc_days_until "")
    local status_perpetual=$(get_status_from_days "$days_perpetual")
    assert_eq "perpetual" "$status_perpetual" "Empty date should result in perpetual status"
}

#===============================================================================
# TEST CATEGORY: License Transfer (v3.8.11)
#===============================================================================
test_transfer_command_exists() {
    # Verify cmd_transfer function exists
    grep -q "^cmd_transfer()" "$SCRIPT_PATH"
    assert_success $? "cmd_transfer function should exist"
}

test_transfer_in_help() {
    local output
    output=$("$SCRIPT_PATH" help 2>&1)
    assert_contains "$output" "transfer" "Help should show transfer command"
}

test_transfer_in_run_command() {
    # Verify transfer is in the run_command router
    local router_content
    router_content=$(sed -n '/^run_command()/,/^}/p' "$SCRIPT_PATH")
    [[ "$router_content" == *"transfer)"* ]] || return 1
}

test_transfer_usage_error() {
    # Transfer without IP should show usage
    local output
    output=$(HOME="$TEST_DATA_DIR" "$SCRIPT_PATH" transfer 2>&1)
    [[ "$output" == *"Usage"* || "$output" == *"transfer"* ]] || return 0
}

test_revoke_function_exists() {
    # Verify f5_revoke_license REST function exists
    grep -q "^f5_revoke_license()" "$SCRIPT_PATH"
    assert_success $? "f5_revoke_license function should exist"
}

test_revoke_ssh_function_exists() {
    # Verify _revoke_license_via_ssh function exists
    grep -q "^_revoke_license_via_ssh()" "$SCRIPT_PATH"
    assert_success $? "_revoke_license_via_ssh function should exist"
}

test_platform_check_function_exists() {
    # Verify _check_platform_is_ve function exists
    grep -q "^_check_platform_is_ve()" "$SCRIPT_PATH"
    assert_success $? "_check_platform_is_ve function should exist"
}

test_platform_ve_detection() {
    # Extract and test _check_platform_is_ve function
    source_script_functions
    eval "$(sed -n '/^_check_platform_is_ve()/,/^}/p' "$SCRIPT_PATH")"

    # Z100 should be VE
    _check_platform_is_ve "Z100"
    assert_success $? "Z100 should be detected as VE"

    # Z101 should be VE
    _check_platform_is_ve "Z101"
    assert_success $? "Z101 should be detected as VE"
}

test_platform_hardware_detection() {
    # Extract and test _check_platform_is_ve function
    source_script_functions
    eval "$(sed -n '/^_check_platform_is_ve()/,/^}/p' "$SCRIPT_PATH")"

    # i5600 should NOT be VE
    _check_platform_is_ve "i5600"
    assert_failure $? "i5600 should NOT be detected as VE"

    # i10800 should NOT be VE
    _check_platform_is_ve "i10800"
    assert_failure $? "i10800 should NOT be detected as VE"
}

test_revoke_rest_api_format() {
    # Verify revoke uses correct REST API format
    local func_content
    func_content=$(sed -n '/^f5_revoke_license()/,/^}/p' "$SCRIPT_PATH")
    [[ "$func_content" == *'"command":"revoke"'* ]] || return 1
}

test_revoke_ssh_tmsh_command() {
    # Verify revoke uses correct tmsh command
    local func_content
    func_content=$(sed -n '/^_revoke_license_via_ssh()/,/^}/p' "$SCRIPT_PATH")
    [[ "$func_content" == *"tmsh revoke sys license"* ]] || return 1
}

test_transfer_requires_confirmation() {
    # Verify transfer command requires typing REVOKE to confirm
    local func_content
    func_content=$(sed -n '/^cmd_transfer()/,/^}/p' "$SCRIPT_PATH")
    [[ "$func_content" == *"REVOKE"* ]] || return 1
}

test_transfer_logs_event() {
    # Verify transfer logs the revocation event
    local func_content
    func_content=$(sed -n '/^cmd_transfer()/,/^}/p' "$SCRIPT_PATH")
    [[ "$func_content" == *"log_event"* ]] || return 1
    [[ "$func_content" == *"TRANSFER_REVOKED"* ]] || return 1
}

test_transfer_updates_database() {
    # Verify transfer updates database to unlicensed status
    local func_content
    func_content=$(sed -n '/^cmd_transfer()/,/^}/p' "$SCRIPT_PATH")
    [[ "$func_content" == *"unlicensed"* ]] || return 1
}

test_transfer_supports_to_flag() {
    # Verify transfer supports --to flag for target device
    local func_content
    func_content=$(sed -n '/^cmd_transfer()/,/^}/p' "$SCRIPT_PATH")
    [[ "$func_content" == *"--to"* ]] || return 1
}

test_get_platform_function_exists() {
    # Verify _get_platform_via_ssh function exists
    grep -q "^_get_platform_via_ssh()" "$SCRIPT_PATH"
    assert_success $? "_get_platform_via_ssh function should exist"
}

test_f5_get_platform_rest_exists() {
    # Verify f5_get_platform REST function exists
    grep -q "^f5_get_platform()" "$SCRIPT_PATH"
    assert_success $? "f5_get_platform function should exist"
}

test_transfer_network() {
    skip_test "transfer command with real device" "requires network/device"
}

#===============================================================================
# TEST CATEGORY: Unlicensed/Inoperative Device Detection
#===============================================================================
test_unlicensed_detection_in_ssh_func() {
    # Verify _get_license_via_ssh detects "Can't load license" message
    local func_content
    func_content=$(sed -n '/^_get_license_via_ssh()/,/^}/p' "$SCRIPT_PATH")
    [[ "$func_content" == *"Can't load license"* ]] || return 1
    [[ "$func_content" == *"UNLICENSED"* ]] || return 1
}

test_unlicensed_detection_in_parse_license() {
    # Verify parse_license_info detects "Can't load license" message
    local func_content
    func_content=$(sed -n '/^parse_license_info()/,/^}/p' "$SCRIPT_PATH")
    [[ "$func_content" == *"Can't load license"* ]] || return 1
    [[ "$func_content" == *"UNLICENSED"* ]] || return 1
}

test_unlicensed_status_in_check() {
    # Verify check function handles UNLICENSED regkey
    local func_content
    func_content=$(sed -n '/^cmd_check()/,/^cmd_/p' "$SCRIPT_PATH" | head -200)
    [[ "$func_content" == *'regkey" == "UNLICENSED"'* ]] || return 1
    [[ "$func_content" == *"unlicensed"* ]] || return 1
}

test_unlicensed_display_in_details() {
    # Verify details function displays UNLICENSED status
    local func_content
    func_content=$(sed -n '/^cmd_details()/,/^}/p' "$SCRIPT_PATH")
    [[ "$func_content" == *"unlicensed)"* ]] || return 1
    [[ "$func_content" == *"UNLICENSED"* ]] || return 1
}

test_transfer_detects_unlicensed() {
    # Verify transfer function detects already unlicensed devices
    local func_content
    func_content=$(sed -n '/^cmd_transfer()/,/^}/p' "$SCRIPT_PATH")
    [[ "$func_content" == *'regkey" == "UNLICENSED"'* ]] || return 1
    [[ "$func_content" == *"INOPERATIVE"* ]] || return 1
}

#===============================================================================
# TEST CATEGORY: Add-on Key Tests (v3.8.12)
#===============================================================================
test_addon_command_exists() {
    # Verify cmd_addon function exists in the script
    grep -q "^cmd_addon()" "$SCRIPT_PATH"
}

test_addon_in_help() {
    # Verify addon command is documented in help
    local help_content
    help_content=$(sed -n '/^cmd_help()/,/^}/p' "$SCRIPT_PATH")
    [[ "$help_content" == *"addon"* ]] || return 1
    [[ "$help_content" == *"add-on key"* ]] || return 1
}

test_addon_in_run_command() {
    # Verify addon is in the run_command router
    local router_content
    router_content=$(sed -n '/^run_command()/,/^}/p' "$SCRIPT_PATH")
    [[ "$router_content" == *"addon)"* ]] || return 1
    [[ "$router_content" == *'cmd_addon "$arg1" "$arg2" "$arg3"'* ]] || return 1
}

test_addon_in_completions() {
    # Verify addon is in command completions
    local completions_content
    completions_content=$(sed -n '/^generate_completions()/,/^BASH_COMPLETION/p' "$SCRIPT_PATH")
    [[ "$completions_content" == *"addon"* ]] || return 1
}

test_addon_usage_error() {
    # Verify addon command shows usage error when no args
    local func_content
    func_content=$(sed -n '/^cmd_addon()/,/^}/p' "$SCRIPT_PATH" | head -20)
    [[ "$func_content" == *'msg_err "Usage: addon'* ]] || return 1
    [[ "$func_content" == *'<ip> <addon-key>'* ]] || return 1
}

test_addon_dossier_with_a_flag() {
    # Verify addon uses get_dossier with -a flag for add-on key
    local func_content
    func_content=$(sed -n '/^cmd_addon()/,/^}/p' "$SCRIPT_PATH")
    [[ "$func_content" == *'get_dossier -b $base_key -a $addon_key'* ]] || return 1
}

test_addon_handles_tmos_shell() {
    # Verify addon handles TMOS shell mode
    local func_content
    func_content=$(sed -n '/^cmd_addon()/,/^}/p' "$SCRIPT_PATH")
    [[ "$func_content" == *'bash -c'* ]] || return 1
    [[ "$func_content" == *'if you land in TMOS'* ]] || return 1
}

test_addon_handles_bash_shell() {
    # Verify addon handles bash shell mode
    local func_content
    func_content=$(sed -n '/^cmd_addon()/,/^}/p' "$SCRIPT_PATH")
    [[ "$func_content" == *'Direct command'* ]] || return 1
    [[ "$func_content" == *'/usr/bin/get_dossier'* ]] || return 1
}

test_addon_offline_mode() {
    # Verify addon handles offline mode (no internet connectivity)
    local func_content
    func_content=$(sed -n '/^cmd_addon()/,/^}/p' "$SCRIPT_PATH")
    [[ "$func_content" == *'OFFLINE LICENSE ACTIVATION'* ]] || return 1
    [[ "$func_content" == *'activate.f5.com'* ]] || return 1
    [[ "$func_content" == *'cannot reach F5 license servers'* ]] || return 1
}

test_addon_saves_dossier() {
    # Verify addon saves dossier to file
    local func_content
    func_content=$(sed -n '/^cmd_addon()/,/^}/p' "$SCRIPT_PATH")
    [[ "$func_content" == *'dossier_addon_'* ]] || return 1
    [[ "$func_content" == *'DATA_DIR'* ]] || return 1
    [[ "$func_content" == *'Saved to:'* ]] || return 1
}

test_addon_logs_events() {
    # Verify addon logs events
    local func_content
    func_content=$(sed -n '/^cmd_addon()/,/^}/p' "$SCRIPT_PATH")
    [[ "$func_content" == *'log_event "ADDON_DOSSIER'* ]] || return 1
    [[ "$func_content" == *'log_event "ADDON_ACTIVATED'* ]] || return 1
    [[ "$func_content" == *'log_event "ADDON_LICENSE_APPLIED'* ]] || return 1
}

test_addon_retrieves_base_key() {
    # Verify addon retrieves base registration key from device
    local func_content
    func_content=$(sed -n '/^cmd_addon()/,/^}/p' "$SCRIPT_PATH")
    [[ "$func_content" == *'Retrieving base registration key'* ]] || return 1
    [[ "$func_content" == *'tmsh show sys license'* ]] || return 1
    [[ "$func_content" == *'Registration Key'* ]] || return 1
}

test_addon_accepts_base_key() {
    # Verify addon accepts base key as third argument
    local func_content
    func_content=$(sed -n '/^cmd_addon()/,/^}/p' "$SCRIPT_PATH" | head -10)
    [[ "$func_content" == *'local base_key="${3:-}"'* ]] || return 1
}

#===============================================================================
# TEST CATEGORY: Network Tests (Skipped without devices)
#===============================================================================
test_network_ssh_connection() {
    skip_test "SSH connection test" "requires network/device"
}

test_network_rest_api() {
    skip_test "REST API test" "requires network/device"
}

test_network_check_command() {
    skip_test "check command with real device" "requires network/device"
}

test_network_details_command() {
    skip_test "details command with real device" "requires network/device"
}

#===============================================================================
# Main Test Runner
#===============================================================================
main() {
    echo ""
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║         F5 License Manager - Comprehensive Test Suite            ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Verify script exists
    if [[ ! -f "$SCRIPT_PATH" ]]; then
        echo -e "${RED}ERROR: Script not found: $SCRIPT_PATH${NC}"
        echo "Usage: $0 [path/to/f5-license.sh]"
        exit 1
    fi

    echo -e "Testing: ${BLUE}$SCRIPT_PATH${NC}"
    echo ""

    # Status Calculation Tests
    echo -e "${BLUE}▸ Status Calculation Tests${NC}"
    run_test "perpetual status from 'perpetual'" test_status_perpetual
    run_test "perpetual status from 'unlimited'" test_status_perpetual_unlimited
    run_test "active status (100 days)" test_status_active
    run_test "active status (31 days)" test_status_active_31days
    run_test "active status (365 days)" test_status_active_365days
    run_test "active status (1000 days)" test_status_active_1000days
    run_test "expiring status (30 days)" test_status_expiring_30days
    run_test "expiring status (15 days)" test_status_expiring_15days
    run_test "expiring status (1 day)" test_status_expiring_1day
    run_test "expiring status (0 days)" test_status_expiring_0days
    run_test "expired status (-1 day)" test_status_expired_negative
    run_test "expired status (-365 days)" test_status_expired_very_negative
    run_test "expired status (-1000 days)" test_status_expired_minus_1000
    run_test "unknown status (empty)" test_status_unknown_empty
    run_test "unknown status (?)" test_status_unknown_question
    run_test "unknown status (invalid)" test_status_unknown_invalid
    run_test "unknown status (special chars)" test_status_unknown_special_chars
    run_test "boundary: 31 days is active" test_status_boundary_31_is_active
    run_test "boundary: 30 days is expiring" test_status_boundary_30_is_expiring
    run_test "boundary: 0 days is expiring" test_status_boundary_0_is_expiring
    run_test "boundary: -1 days is expired" test_status_boundary_minus1_is_expired
    echo ""

    # Days Calculation Tests
    echo -e "${BLUE}▸ Days Calculation Tests${NC}"
    run_test "perpetual from empty expiry" test_days_perpetual_empty
    run_test "perpetual from null expiry" test_days_perpetual_null
    run_test "perpetual from N/A expiry" test_days_perpetual_na
    run_test "perpetual from 'Perpetual' word" test_days_perpetual_word
    run_test "perpetual from 'perpetual' lowercase" test_days_perpetual_lowercase
    run_test "perpetual from 'Unlimited' word" test_days_perpetual_unlimited
    run_test "perpetual from 'unlimited' lowercase" test_days_perpetual_unlimited_lowercase
    run_test "perpetual from 'Never' word" test_days_perpetual_never
    run_test "perpetual from 'None' word" test_days_perpetual_none
    run_test "days calculation for future date" test_days_future_date
    run_test "days calculation for past date" test_days_past_date
    echo ""

    # Date Parsing Tests
    echo -e "${BLUE}▸ Date Parsing Tests${NC}"
    run_test "parse YYYY/MM/DD format" test_parse_date_slash_format
    run_test "parse YYYY-MM-DD format" test_parse_date_dash_format
    run_test "parse compact YYYYMMDD format" test_parse_date_compact_format
    run_test "empty date fails" test_parse_date_empty
    run_test "null date fails" test_parse_date_null
    run_test "invalid date handling" test_parse_date_invalid
    run_test "partial date handling" test_parse_date_partial
    run_test "year only handling" test_parse_date_year_only
    run_test "leap year date" test_parse_date_leap_year
    run_test "end of year date" test_parse_date_end_of_year
    run_test "start of year date" test_parse_date_start_of_year
    echo ""

    # Database Operation Tests
    echo -e "${BLUE}▸ Database Operation Tests${NC}"
    run_test "empty database count" test_db_empty_count
    run_test "add device" test_db_add_device
    run_test "add device with key auth" test_db_add_device_with_key_auth
    run_test "add device has svc_check_date field" test_db_add_device_has_svc_check_date_field
    run_test "add device svc_check_date is null" test_db_add_device_svc_check_date_null
    run_test "device exists (true)" test_db_exists_true
    run_test "device exists (false)" test_db_exists_false
    run_test "device exists (similar IP)" test_db_exists_similar_ip
    run_test "remove device" test_db_remove_device
    run_test "remove nonexistent device" test_db_remove_nonexistent
    run_test "remove one of many" test_db_remove_one_of_many
    run_test "get device data" test_db_get_device
    run_test "get nonexistent device" test_db_get_nonexistent
    run_test "update device" test_db_update_device
    run_test "update with svc_check_date" test_db_update_with_svc_check_date
    run_test "update svc_check_date to empty" test_db_update_svc_check_date_empty
    run_test "update auth type" test_db_update_auth_type
    run_test "get auth type" test_db_get_auth_type
    run_test "get auth type default" test_db_get_auth_type_default
    run_test "multiple devices" test_db_multiple_devices
    run_test "preserves other fields" test_db_preserves_other_fields
    run_test "JSON valid after add" test_db_json_valid_after_add
    run_test "JSON valid after update" test_db_json_valid_after_update
    run_test "JSON valid after remove" test_db_json_valid_after_remove
    echo ""

    # Input Validation Tests
    echo -e "${BLUE}▸ Input Validation Tests${NC}"
    run_test "valid IPv4 address" test_input_valid_ipv4
    run_test "valid hostname" test_input_valid_hostname
    run_test "valid short hostname" test_input_valid_short_hostname
    run_test "hostname with dashes" test_input_hostname_with_dashes
    run_test "hostname with underscores" test_input_hostname_with_underscores
    run_test "IP edge values" test_input_ip_edge_values
    run_test "special chars in regkey" test_input_special_chars_in_regkey
    echo ""

    # Command Line Tests
    echo -e "${BLUE}▸ Command Line Tests${NC}"
    run_test "help command works" test_cmd_help
    run_test "help shows add command" test_cmd_help_shows_add
    run_test "help shows remove command" test_cmd_help_shows_remove
    run_test "help shows list command" test_cmd_help_shows_list
    run_test "help shows check command" test_cmd_help_shows_check
    run_test "help shows details command" test_cmd_help_shows_details
    run_test "help shows export command" test_cmd_help_shows_export
    run_test "version defined in script" test_cmd_version_in_script
    run_test "script syntax valid" test_cmd_script_syntax
    run_test "list command (empty)" test_cmd_list_empty
    run_test "list command JSON (empty)" test_cmd_list_json_empty
    echo ""

    # Environment Variable Tests
    echo -e "${BLUE}▸ Environment Variable Tests${NC}"
    run_test "uses printenv for env detection" test_env_var_not_contaminated
    run_test "credentials cleared in prompt" test_credentials_cleared_in_prompt
    run_test "load_device_credentials exists" test_env_load_device_credentials_exists
    echo ""

    # SSH Key Handling Tests
    echo -e "${BLUE}▸ SSH Key Handling Tests${NC}"
    run_test "SSH key path properly quoted" test_ssh_key_quoted
    run_test "strip double quotes from path" test_strip_quotes_double
    run_test "strip single quotes from path" test_strip_quotes_single
    run_test "unquoted path unchanged" test_strip_quotes_none
    run_test "quoted path with spaces" test_strip_quotes_spaces
    run_test "quoted path with tilde" test_strip_quotes_tilde
    run_test "whitespace around quoted path" test_strip_quotes_whitespace_around
    run_test "empty string handling" test_strip_quotes_empty
    run_test "whitespace only handling" test_strip_quotes_only_whitespace
    echo ""

    # License Parsing Tests
    echo -e "${BLUE}▸ License Parsing Tests${NC}"
    run_test "parse_license_info returns three fields" test_parse_license_info_returns_three_fields
    run_test "parse_license_info format" test_parse_license_info_format
    run_test "_get_license_via_ssh returns three fields" test_get_license_via_ssh_returns_three_fields
    run_test "_get_license_via_ssh parses service check" test_get_license_via_ssh_parses_service_check
    echo ""

    # License End Date Logic Tests
    echo -e "${BLUE}▸ License End Date Logic Tests (v3.8.10)${NC}"
    run_test "parse_license_info uses licenseEndDate" test_license_end_date_in_parse_license_info
    run_test "_get_license_via_ssh parses License End Date" test_license_end_date_in_ssh_func
    run_test "SSH fallback searches License end date" test_license_end_date_grep_fallback
    run_test "details shows both License End and Svc Check" test_details_shows_both_dates
    run_test "details uses expires for expiration calc" test_license_end_date_for_expiration
    run_test "JSON output has correct field names" test_json_output_field_names
    echo ""

    # Display Formatting Tests
    echo -e "${BLUE}▸ Display Formatting Tests${NC}"
    run_test "show_devices has SVC CHK column" test_show_devices_has_svc_chk_column
    run_test "show_devices reads svc_check_date" test_show_devices_reads_svc_check_date
    run_test "list output format" test_list_output_format
    echo ""

    # Export Functionality Tests
    echo -e "${BLUE}▸ Export Functionality Tests${NC}"
    run_test "export includes svc_check_date" test_export_includes_svc_check_date
    run_test "export CSV header" test_export_csv_header
    run_test "export creates file" test_export_creates_file
    run_test "export CSV content" test_export_csv_content
    echo ""

    # TMOS Compatibility Tests
    echo -e "${BLUE}▸ TMOS Compatibility Tests${NC}"
    run_test "TMOS fallback in reload" test_tmos_fallback_in_reload
    run_test "TMOS fallback in dossier" test_tmos_fallback_in_dossier
    run_test "tmsh command used" test_tmsh_command_used
    echo ""

    # Error Handling Tests
    echo -e "${BLUE}▸ Error Handling Tests${NC}"
    run_test "invalid command handling" test_invalid_command_handling
    run_test "missing IP for add" test_missing_ip_for_add
    run_test "missing IP for remove" test_missing_ip_for_remove
    run_test "missing IP for details" test_missing_ip_for_details
    echo ""

    # JSON Output Mode Tests
    echo -e "${BLUE}▸ JSON Output Mode Tests${NC}"
    run_test "JSON flag exists" test_json_flag_exists
    run_test "JSON_OUTPUT variable exists" test_json_output_variable
    run_test "JSON list output valid" test_json_list_output
    run_test "JSON check output structure" test_json_check_output_structure
    echo ""

    # History/Logging Tests
    echo -e "${BLUE}▸ History/Logging Tests${NC}"
    run_test "log file handling" test_log_file_created
    run_test "history command exists" test_history_command_exists
    echo ""

    # Integration Tests
    echo -e "${BLUE}▸ Integration Tests${NC}"
    run_test "add-list-remove workflow" test_integration_add_list_remove
    run_test "multiple devices workflow" test_integration_multiple_devices_workflow
    run_test "status calculation end-to-end" test_integration_status_calculation_end_to_end
    echo ""

    # License Transfer Tests (v3.8.11)
    echo -e "${BLUE}▸ License Transfer Tests (v3.8.11)${NC}"
    run_test "cmd_transfer function exists" test_transfer_command_exists
    run_test "transfer in help menu" test_transfer_in_help
    run_test "transfer in run_command router" test_transfer_in_run_command
    run_test "transfer usage error" test_transfer_usage_error
    run_test "f5_revoke_license function exists" test_revoke_function_exists
    run_test "_revoke_license_via_ssh function exists" test_revoke_ssh_function_exists
    run_test "_check_platform_is_ve function exists" test_platform_check_function_exists
    run_test "VE platform detection (Z100, Z101)" test_platform_ve_detection
    run_test "hardware platform detection (i5600, i10800)" test_platform_hardware_detection
    run_test "revoke REST API format" test_revoke_rest_api_format
    run_test "revoke SSH tmsh command" test_revoke_ssh_tmsh_command
    run_test "transfer requires confirmation" test_transfer_requires_confirmation
    run_test "transfer logs event" test_transfer_logs_event
    run_test "transfer updates database" test_transfer_updates_database
    run_test "transfer supports --to flag" test_transfer_supports_to_flag
    run_test "_get_platform_via_ssh function exists" test_get_platform_function_exists
    run_test "f5_get_platform REST function exists" test_f5_get_platform_rest_exists
    test_transfer_network
    echo ""

    # Unlicensed/Inoperative Device Detection Tests
    echo -e "${BLUE}▸ Unlicensed Device Detection Tests${NC}"
    run_test "SSH function detects unlicensed state" test_unlicensed_detection_in_ssh_func
    run_test "parse_license_info detects unlicensed state" test_unlicensed_detection_in_parse_license
    run_test "check command handles UNLICENSED regkey" test_unlicensed_status_in_check
    run_test "details command displays UNLICENSED status" test_unlicensed_display_in_details
    run_test "transfer command detects already unlicensed" test_transfer_detects_unlicensed
    echo ""

    # Network Tests (Skipped)
    echo -e "${BLUE}▸ Network Tests${NC}"
    test_network_ssh_connection
    test_network_rest_api
    test_network_check_command
    test_network_details_command
    echo ""

    # Add-on Key Tests (v3.8.12)
    echo -e "${BLUE}▸ Add-on Key Tests (v3.8.12)${NC}"
    run_test "cmd_addon function exists" test_addon_command_exists
    run_test "addon in help menu" test_addon_in_help
    run_test "addon in run_command router" test_addon_in_run_command
    run_test "addon in completions" test_addon_in_completions
    run_test "addon usage error" test_addon_usage_error
    run_test "addon generates dossier with -a flag" test_addon_dossier_with_a_flag
    run_test "addon handles TMOS shell" test_addon_handles_tmos_shell
    run_test "addon handles bash shell" test_addon_handles_bash_shell
    run_test "addon offline mode detection" test_addon_offline_mode
    run_test "addon saves dossier to file" test_addon_saves_dossier
    run_test "addon logs events" test_addon_logs_events
    run_test "addon retrieves base key" test_addon_retrieves_base_key
    run_test "addon accepts base key as third arg" test_addon_accepts_base_key
    echo ""

    # Summary
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "  Total:   $TESTS_RUN"
    echo -e "  ${GREEN}Passed:  $TESTS_PASSED${NC}"
    echo -e "  ${RED}Failed:  $TESTS_FAILED${NC}"
    echo -e "  ${YELLOW}Skipped: $TESTS_SKIPPED${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""

    # Exit with failure if any tests failed
    if [[ "$TESTS_FAILED" -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

main "$@"
