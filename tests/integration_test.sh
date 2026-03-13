#!/bin/bash

# LRoadmap Comprehensive Integration Test
# Requires: zig, jq

set -ex

EXE="./zig-out/bin/rmp"
TEST_RM="integration_test_roadmap"
DB_PATH="$HOME/.roadmaps/$TEST_RM.db"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "Starting Integration Tests..."

# Clean up before starting
rm -f "$DB_PATH"
rm -f "$HOME/.roadmaps/.current"

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

# Helper function to assert success: true
assert_success() {
    local json="$1"
    local message="$2"
    assert_json "$json" ".success" "true" "$message"
}

# 1. Roadmap Management
echo "1. Testing Roadmap Management..."
OUT=$($EXE roadmap create $TEST_RM)
assert_success "$OUT" "Create roadmap"
assert_json "$OUT" ".data.name" "$TEST_RM" "Roadmap name matches"

OUT=$($EXE roadmap use $TEST_RM)
assert_success "$OUT" "Use roadmap"

# 2. Task Management
echo "2. Testing Task Management..."
OUT=$($EXE task add -d "Task 1" -a "Action 1" -e "Result 1" -p 5 -s 3)
assert_success "$OUT" "Add Task 1"
T1_ID=$(echo "$OUT" | jq -r ".data.id")

OUT=$($EXE task add -d "Task 2" -a "Action 2" -e "Result 2" -p 8 -s 5)
assert_success "$OUT" "Add Task 2"
T2_ID=$(echo "$OUT" | jq -r ".data.id")

OUT=$($EXE task list)
assert_success "$OUT" "List tasks"
assert_json "$OUT" ".data.count" "2" "Task count is 2"

# 3. Status Transitions
echo "3. Testing Status Transitions..."
# BACKLOG -> SPRINT
OUT=$($EXE task status $T1_ID SPRINT)
assert_success "$OUT" "Status BACKLOG -> SPRINT"

# SPRINT -> DOING
OUT=$($EXE task status $T1_ID DOING)
assert_success "$OUT" "Status SPRINT -> DOING"

# DOING -> TESTING
OUT=$($EXE task status $T1_ID TESTING)
assert_success "$OUT" "Status DOING -> TESTING"

# TESTING -> COMPLETED
OUT=$($EXE task status $T1_ID COMPLETED)
assert_success "$OUT" "Status TESTING -> COMPLETED"

# Check if completed_at is set
OUT=$($EXE task get $T1_ID)
assert_json "$OUT" ".data.status" "COMPLETED" "Status is COMPLETED"
COMPLETED_AT=$(echo "$OUT" | jq -r ".data.completed_at")
if [ "$COMPLETED_AT" != "null" ]; then
    echo -e "  [${GREEN}PASS${NC}] completed_at is set"
else
    echo -e "  [${RED}FAIL${NC}] completed_at is null"
    exit 1
fi

# 4. Sprint Management
echo "4. Testing Sprint Management..."
OUT=$($EXE sprint add "Sprint 1")
assert_success "$OUT" "Create sprint"
S1_ID=$(echo "$OUT" | jq -r ".data.id")

OUT=$($EXE sprint add-task $S1_ID $T2_ID)
assert_success "$OUT" "Add task to sprint"

OUT=$($EXE sprint start $S1_ID)
assert_success "$OUT" "Start sprint"

OUT=$($EXE sprint stats $S1_ID)
assert_success "$OUT" "Get sprint stats"
assert_json "$OUT" ".data.total_tasks" "1" "Sprint total tasks"

# 5. Bulk Operations
echo "5. Testing Bulk Operations..."
# ... (existing bulk operations)
OUT=$($EXE task delete $T3_ID,$T4_ID)
assert_success "$OUT" "Bulk delete"

# 6. Testing Sprint Task Transitions and Advanced Sprint Commands
echo "6. Testing Sprint Task Transitions..."
OUT=$($EXE task add -d "Transition Task" -a "Action" -e "Result")
TT_ID=$(echo "$OUT" | jq -r ".data.id")

# Status should be BACKLOG
OUT=$($EXE task get $TT_ID)
assert_json "$OUT" ".data.status" "BACKLOG" "Task starts in BACKLOG"

# Create new sprint
OUT=$($EXE sprint add "Transition Sprint")
S2_ID=$(echo "$OUT" | jq -r ".data.id")

# Add to sprint - should change to SPRINT
OUT=$($EXE sprint add-task $S2_ID $TT_ID)
assert_success "$OUT" "Add task to transition sprint"
OUT=$($EXE task get $TT_ID)
assert_json "$OUT" ".data.status" "SPRINT" "Task status changed to SPRINT"

# Move to another sprint
OUT=$($EXE sprint move-tasks $S2_ID $S1_ID $TT_ID)
assert_success "$OUT" "Move task between sprints"
OUT=$($EXE task get $TT_ID)
assert_json "$OUT" ".data.status" "SPRINT" "Task status remains SPRINT after move"

# Remove from sprint - should return to BACKLOG
OUT=$($EXE sprint rm-tasks $S1_ID $TT_ID)
assert_success "$OUT" "Remove task from sprint"
OUT=$($EXE task get $TT_ID)
assert_json "$OUT" ".data.status" "BACKLOG" "Task status returned to BACKLOG"

# 7. Cleanup
echo "7. Cleanup..."
OUT=$($EXE roadmap remove $TEST_RM)
assert_success "$OUT" "Remove roadmap"

if [ -f "$DB_PATH" ]; then
    echo -e "  [${RED}FAIL${NC}] Database file still exists"
    exit 1
else
    echo -e "  [${GREEN}PASS${NC}] Database file removed"
fi

echo -e "\n${GREEN}All Integration Tests Passed!${NC}"
