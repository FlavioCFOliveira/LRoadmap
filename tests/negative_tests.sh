#!/bin/bash

# LRoadmap Negative Tests Battery
# Tests validation of types, parameter counts, and edge cases.

set -e

EXE="./zig-out/bin/rmp"
TEST_RM="negative_test_roadmap"
DB_PATH="$HOME/.roadmaps/$TEST_RM.db"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Starting Negative Tests Battery...${NC}"

# Clean up
rm -f "$DB_PATH"
rm -f "$HOME/.roadmaps/.current"

# Helper to assert error code
assert_error() {
    local cmd="$1"
    local expected_code="$2"
    local message="$3"

    local out=$($cmd 2>&1)
    # Error responses now have .code directly (no .error wrapper)
    local actual_code=$(echo "$out" | jq -r ".code")

    if [ "$actual_code" == "$expected_code" ]; then
        echo -e "  [${GREEN}PASS${NC}] $message"
    else
        echo -e "  [${RED}FAIL${NC}] $message (Expected: $expected_code, Actual: $actual_code)"
        echo "  Output: $out"
        # exit 1
    fi
}

# Helper function to assert JSON field
assert_json() {
    local json="$1"
    local query="$2"
    local expected="$3"
    local message="$4"

    local actual=$(echo "$json" | jq -r "$query")
    if [ "$actual" == "$expected" ]; then
        echo -e "  [${GREEN}PASS${NC}] $message"
    else
        echo -e "  [${RED}FAIL${NC}] $message (Expected: $expected, Actual: $actual)"
        exit 1
    fi
}

# Helper to assert success: true
assert_success() {
    local out="$1"
    local message="$2"
    local actual=$(echo "$out" | jq -r ".success")
    if [ "$actual" == "true" ]; then
        echo -e "  [${GREEN}PASS${NC}] $message"
    else
        echo -e "  [${RED}FAIL${NC}] $message (Expected: true, Actual: $actual)"
        echo "  Output: $out"
        exit 1
    fi
}

# 1. Roadmap Validation
echo "1. Testing Roadmap Validation..."
assert_error "$EXE roadmap create" "INVALID_INPUT" "Missing roadmap name"
assert_error "$EXE roadmap create very_long_name_that_exceeds_the_fifty_character_limit_for_roadmap_names" "INVALID_INPUT" "Roadmap name too long"
assert_error "$EXE roadmap create project@#$" "INVALID_INPUT" "Roadmap name with special characters"
assert_error "$EXE roadmap use non_existent_roadmap" "ROADMAP_NOT_FOUND" "Use non-existent roadmap"

# Create a valid roadmap for further tests
$EXE roadmap create $TEST_RM > /dev/null
$EXE roadmap use $TEST_RM > /dev/null

# 2. Task Validation
echo "2. Testing Task Validation..."
assert_error "$EXE task add" "INVALID_INPUT" "Add task with no arguments"
assert_error "$EXE task add -d 'Desc' -a 'Action'" "INVALID_INPUT" "Add task with missing required fields (expected)"
assert_error "$EXE task add -d 'Desc' -a 'Action' -e 'Result' -p 10" "INVALID_PRIORITY" "Priority > 9"
assert_error "$EXE task add -d 'Desc' -a 'Action' -e 'Result' -p -1" "INVALID_PRIORITY" "Priority < 0"
assert_error "$EXE task add -d 'Desc' -a 'Action' -e 'Result' -p invalid" "INVALID_INPUT" "Priority non-numeric"
assert_error "$EXE task add -d 'Desc' -a 'Action' -e 'Result' -s 15" "INVALID_INPUT" "Severity > 9"

assert_error "$EXE task get" "INVALID_INPUT" "Get task without ID"
assert_error "$EXE task get abc" "INVALID_INPUT" "Get task with non-numeric ID"
assert_error "$EXE task get 999999" "TASK_NOT_FOUND" "Get non-existent task"

# 3. Sprint Validation
echo "3. Testing Sprint Validation..."
assert_error "$EXE sprint get" "INVALID_INPUT" "Get sprint without ID"
assert_error "$EXE sprint get abc" "INVALID_INPUT" "Get sprint with non-numeric ID"
assert_error "$EXE sprint add" "INVALID_INPUT" "Add sprint without description"

# 4. Global Flags
echo "4. Testing Global Flags..."
assert_error "$EXE -r non_existent roadmap list" "ROADMAP_NOT_FOUND" "Global roadmap flag with non-existent roadmap"

# 5. Type Validation and Overflow
echo "5. Testing Type Validation and Overflow..."
assert_error "$EXE task get 9223372036854775808" "INVALID_INPUT" "Task ID overflow (i64 max + 1)"

# 6. Quantity of Parameters
echo "6. Testing Quantity of Parameters..."
assert_error "$EXE task get 1 2" "INVALID_INPUT" "Too many arguments for task get"
assert_error "$EXE task status 1 DOING extra" "INVALID_INPUT" "Too many arguments for task status"

# 7. Audit Commands Validation
echo "7. Testing Audit Commands Validation..."
assert_error "$EXE audit list --since invalid-date" "INVALID_INPUT" "Invalid since date format"
assert_error "$EXE audit list --until invalid-date" "INVALID_INPUT" "Invalid until date format"

# Create a roadmap for audit tests
$EXE roadmap create $TEST_RM > /dev/null
$EXE roadmap use $TEST_RM > /dev/null

# Test invalid date ranges
assert_error "$EXE audit list --since 2024-12-31T00:00:00.000Z --until 2024-01-01T00:00:00.000Z" "INVALID_DATE_RANGE" "Since date after until date"
assert_error "$EXE audit stats --since 2025-01-01T00:00:00.000Z --until 2024-01-01T00:00:00.000Z" "INVALID_DATE_RANGE" "Stats with invalid date range"

# Test invalid operation type (should work but return empty results, not error)
OUT=$($EXE audit list --operation INVALID_OPERATION)
assert_success "$OUT" "Invalid operation type returns empty results"
assert_json "$OUT" ".data.count" "0" "Empty results for invalid operation"

# Cleanup
$EXE roadmap remove $TEST_RM > /dev/null

echo -e "\n${GREEN}Negative Tests Battery Completed!${NC}"
