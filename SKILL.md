---
name: roadmap
description: A Claude Code skill for agentic task and sprint management workflows via LRoadmap CLI
type: cli
version: 1.0.0
requirements:
  - LRoadmap CLI (rmp) installed and available on PATH
  - ~/.roadmaps/ directory accessible for roadmap storage
modes:
  - sprint_orchestrator
  - task_manager
  - sprint_analyst
---

# LRoadmap Skill

A Claude Code skill for agentic task and sprint management workflows.

## Overview

This skill transforms Claude Code into an orchestrator specialized in coordinating tasks organized by sprints. Claude gains the ability to:

- Manage roadmaps, tasks, and sprints via CLI commands
- Orchestrate complete development workflows
- Coordinate task state transitions with validation
- Analyze sprint progress and statistics
- Maintain complete audit trail of all operations

This skill is automatically loaded when working in a repository that contains the LRoadmap CLI tool.

## Operating Modes

The skill operates in three main modes:

### Mode 1: Sprint Orchestrator (Default)

Claude acts as a sprint coordinator, managing the complete task flow from backlog to completion.

**Capabilities:**
- Create and configure sprints
- Add tasks to sprints with prioritization
- Monitor progress in real-time
- Coordinate state transitions
- Generate completion reports

**Activation command:**
```
Act as sprint orchestrator for roadmap <name>
```

### Mode 2: Task Manager

Focus on creating and maintaining individual tasks, regardless of sprints.

**Capabilities:**
- Create detailed tasks with technical action and expected result
- Adjust priority and severity
- Transition states with validation
- Query change history

**Activation command:**
```
Manage tasks in roadmap <name>
```

### Mode 3: Sprint Analyst

Analyze sprint data and statistics for decision-making.

**Capabilities:**
- Completion statistics
- Audit trail analysis
- Productivity reports
- Bottleneck identification

**Activation command:**
```
Analyze sprint <id> in roadmap <name>
```

## Workflows

### Workflow 1: Task Lifecycle in Sprint (Step-by-Step)

The complete lifecycle of a task from backlog to completion within a sprint:

```
BACKLOG → SPRINT → DOING → TESTING → COMPLETED
   ↑                                    │
   └────────────────────────────────────┘ (reopen)
```

#### Step 1: Create Task in Backlog
```bash
# Create the task with full specification
rmp task new -r <roadmap> \
  -d "Implement user authentication" \
  -a "Create JWT-based auth middleware" \
  -e "All protected endpoints require valid JWT token" \
  -p 9 \
  --severity 8

# Note the returned task ID (e.g., ID: 5)
```

#### Step 2: Add Task to Sprint
```bash
# First, identify available sprints
rmp sprint ls -r <roadmap> -s OPEN

# Add task to sprint (changes status to SPRINT automatically)
rmp sprint add -r <roadmap> <sprint-id> <task-id>

# Verify task is now in sprint
rmp task get -r <roadmap> <task-id>
```

#### Step 3: Start Working on Task
```bash
# Transition to DOING
rmp task stat -r <roadmap> <task-id> DOING

# Verify transition
rmp task get -r <roadmap> <task-id>
```

#### Step 4: Move to Testing
```bash
# When implementation is complete, transition to TESTING
rmp task stat -r <roadmap> <task-id> TESTING

# Run tests (if applicable)
# [Execute test suite]
```

#### Step 5: Complete Task
```bash
# After tests pass, mark as COMPLETED
rmp task stat -r <roadmap> <task-id> COMPLETED

# Verify completion timestamp is set
rmp task get -r <roadmap> <task-id>
```

#### Step 6: Reopen if Needed
```bash
# If issues are found after completion, reopen to BACKLOG
rmp task stat -r <roadmap> <task-id> BACKLOG
```

---

### Workflow 2: Sprint Setup and Management

Complete process for setting up a new sprint:

#### Phase 1: Sprint Creation
```bash
# Step 1: Check existing sprints
rmp sprint ls -r <roadmap>

# Step 2: Create new sprint with description
rmp sprint new -r <roadmap> -d "Sprint 3 - Authentication Features"

# Step 3: Note the sprint ID (e.g., ID: 3)
rmp sprint get -r <roadmap> <sprint-id>
```

#### Phase 2: Task Planning
```bash
# Step 4: List available backlog tasks
rmp task ls -r <roadmap> -s BACKLOG

# Step 5: Review high priority tasks first
rmp task ls -r <roadmap> -s BACKLOG -p 7

# Step 6: Select tasks for sprint
# (Typically select 5-10 tasks based on capacity)
```

#### Phase 3: Populate Sprint
```bash
# Step 7: Add selected tasks to sprint
rmp sprint add -r <roadmap> <sprint-id> <task-id-1,task-id-2,task-id-3>

# Step 8: Verify tasks were added
rmp sprint tasks -r <roadmap> <sprint-id>
```

#### Phase 4: Sprint Start
```bash
# Step 9: Start the sprint
rmp sprint start -r <roadmap> <sprint-id>

# Step 10: Verify sprint status changed to OPEN
rmp sprint get -r <roadmap> <sprint-id>
```

#### Phase 5: Daily Monitoring
```bash
# Check sprint statistics
rmp sprint stats -r <roadmap> <sprint-id>

# List tasks by status
rmp sprint tasks -r <roadmap> <sprint-id> -s DOING
rmp sprint tasks -r <roadmap> <sprint-id> -s TESTING
rmp sprint tasks -r <roadmap> <sprint-id> -s COMPLETED
```

#### Phase 6: Sprint Closure
```bash
# Step 11: When all tasks completed, close sprint
rmp sprint close -r <roadmap> <sprint-id>

# Step 12: Generate final report
rmp sprint stats -r <roadmap> <sprint-id>
rmp audit stats -r <roadmap> --since <sprint-start-date>
```

---

### Workflow 3: Daily Development Cycle

Typical daily workflow for working on sprint tasks:

#### Morning: Plan the Day
```bash
# Step 1: Check sprint status
rmp sprint stats -r <roadmap> <sprint-id>

# Step 2: List tasks ready for work (SPRINT status)
rmp sprint tasks -r <roadmap> <sprint-id> -s SPRINT

# Step 3: Identify highest priority/severity task
# (Tasks are auto-ordered by priority DESC, severity DESC)
```

#### During Day: Work on Tasks
```bash
# Step 4: Select next task
rmp task get -r <roadmap> <task-id>

# Step 5: Transition to DOING
rmp task stat -r <roadmap> <task-id> DOING

# Step 6: [Perform technical work following the 'action' field]

# Step 7: When ready for testing
rmp task stat -r <roadmap> <task-id> TESTING

# Step 8: [Run tests based on 'expected_result' field]

# Step 9: If tests pass, complete
rmp task stat -r <roadmap> <task-id> COMPLETED
```

#### Evening: Report Progress
```bash
# Step 10: Check daily progress
rmp sprint stats -r <roadmap> <sprint-id>

# Step 11: Review audit of today's changes
rmp audit ls -r <roadmap> --since $(date -u +%Y-%m-%dT00:00:00.000Z)
```

---

### Workflow 4: Backlog Grooming

Regular maintenance of the task backlog:

#### Step 1: Review All Tasks
```bash
# List all tasks
rmp task ls -r <roadmap>

# Filter by status
rmp task ls -r <roadmap> -s BACKLOG
rmp task ls -r <roadmap> -s COMPLETED
```

#### Step 2: Identify Issues
```bash
# Find low priority but high severity tasks (technical debt)
rmp task ls -r <roadmap> -s BACKLOG | grep -E '("priority": [0-3]|"severity": [7-9])'

# Find old DOING tasks (potentially blocked)
rmp task ls -r <roadmap> -s DOING
```

#### Step 3: Adjust Priorities
```bash
# Update priority based on business needs
rmp task prio -r <roadmap> <task-id> <new-priority>

# Update severity based on technical assessment
rmp task sev -r <roadmap> <task-id> <new-severity>

# Bulk update multiple tasks
rmp task prio -r <roadmap> <id1,id2,id3> 7
```

#### Step 4: Clean Up
```bash
# Remove obsolete tasks
rmp task rm -r <roadmap> <obsolete-task-id>

# Move tasks between sprints if needed
rmp sprint mv-tasks -r <roadmap> <from-sprint> <to-sprint> <task-ids>
```

---

### Workflow 5: Sprint Review and Retrospective

Analyze completed sprint:

#### Step 1: Sprint Statistics
```bash
# Get sprint overview
rmp sprint stats -r <roadmap> <sprint-id>

# List all sprint tasks with final status
rmp sprint tasks -r <roadmap> <sprint-id>
```

#### Step 2: Completion Analysis
```bash
# Count tasks by status
rmp sprint tasks -r <roadmap> <sprint-id> -s COMPLETED | wc -l
rmp sprint tasks -r <roadmap> <sprint-id> -s BACKLOG | wc -l

# Calculate completion rate
# (From sprint stats output)
```

#### Step 3: Audit Trail Review
```bash
# Review all sprint operations
rmp audit ls -r <roadmap> -e SPRINT --entity-id <sprint-id>

# Review task operations during sprint
rmp audit ls -r <roadmap> --since <sprint-start> --until <sprint-end>
```

#### Step 4: Identify Patterns
```bash
# Check for status change patterns
rmp audit hist -r <roadmap> -e TASK <task-id>

# Review time spent in each state
# (Analyze performed_at timestamps in audit log)
```

---

### Workflow 6: Task Recovery and Correction

Handle mistakes or changes:

#### Reopen Completed Task
```bash
# Step 1: Verify task is COMPLETED
rmp task get -r <roadmap> <task-id>

# Step 2: Transition back to BACKLOG
rmp task stat -r <roadmap> <task-id> BACKLOG

# Step 3: Add to current sprint if needed
rmp sprint add -r <roadmap> <current-sprint-id> <task-id>
```

#### Move Task Between Sprints
```bash
# Step 1: Remove from current sprint
rmp sprint rm-tasks -r <roadmap> <current-sprint-id> <task-id>
# (Task returns to BACKLOG automatically)

# Step 2: Add to new sprint
rmp sprint add -r <roadmap> <new-sprint-id> <task-id>
```

#### Correct Wrong Status
```bash
# If task was moved to wrong status, go back to previous
# Check audit history first
rmp audit hist -r <roadmap> -e TASK <task-id>

# Then apply correct status
rmp task stat -r <roadmap> <task-id> <correct-status>
```

---

### Workflow 7: Multi-Task Operations

Efficient bulk operations:

#### Start Multiple Tasks
```bash
# Step 1: Select tasks from sprint
rmp sprint tasks -r <roadmap> <sprint-id> -s SPRINT

# Step 2: Transition all to DOING
rmp task stat -r <roadmap> <id1,id2,id3> DOING
```

#### Complete Multiple Tasks
```bash
# Step 1: Identify tasks in TESTING
rmp sprint tasks -r <roadmap> <sprint-id> -s TESTING

# Step 2: Bulk complete after verification
rmp task stat -r <roadmap> <id1,id2,id3> COMPLETED
```

#### Adjust Priorities in Bulk
```bash
# Step 1: Review current priorities
rmp sprint tasks -r <roadmap> <sprint-id>

# Step 2: Set new priority for group
rmp task prio -r <roadmap> <id1,id2,id3,id4> 8
```

## Available CLI Commands

### Roadmap Management

| Action | Command |
|--------|---------|
| List roadmaps | `rmp roadmap list` / `rmp road ls` |
| Create roadmap | `rmp roadmap new <name>` / `rmp road new <name>` |
| Remove roadmap | `rmp roadmap rm <name>` / `rmp road rm <name>` |
| Select roadmap | `rmp roadmap use <name>` / `rmp road use <name>` |

### Task Management

| Action | Command |
|--------|---------|
| List tasks | `rmp task ls -r <roadmap> [-s <status>] [-p <min-priority>] [-l <limit>]` |
| Create task | `rmp task new -r <roadmap> -d <desc> -a <action> -e <result> [-p <0-9>] [--severity <0-9>]` |
| Get task(s) | `rmp task get -r <roadmap> <id1,id2,id3>` |
| Change status | `rmp task stat -r <roadmap> <id1,id2,id3> <BACKLOG/SPRINT/DOING/TESTING/COMPLETED>` |
| Change priority | `rmp task prio -r <roadmap> <id1,id2,id3> <0-9>` |
| Change severity | `rmp task sev -r <roadmap> <id1,id2,id3> <0-9>` |
| Remove task(s) | `rmp task rm -r <roadmap> <id1,id2,id3>` |

### Sprint Management

| Action | Command |
|--------|---------|
| List sprints | `rmp sprint ls -r <roadmap> [-s <PENDING/OPEN/CLOSED>]` |
| Create sprint | `rmp sprint new -r <roadmap> -d "<description>"` |
| Get sprint | `rmp sprint get -r <roadmap> <id>` |
| List sprint tasks | `rmp sprint tasks -r <roadmap> <sprint-id> [-s <status>]` |
| Add tasks | `rmp sprint add -r <roadmap> <sprint-id> <task-ids>` |
| Remove tasks | `rmp sprint rm-tasks -r <roadmap> <sprint-id> <task-ids>` |
| Move tasks | `rmp sprint mv-tasks -r <roadmap> <from> <to> <task-ids>` |
| Start sprint | `rmp sprint start -r <roadmap> <sprint-id>` |
| Close sprint | `rmp sprint close -r <roadmap> <sprint-id>` |
| Reopen sprint | `rmp sprint reopen -r <roadmap> <sprint-id>` |
| Update sprint | `rmp sprint upd -r <roadmap> <sprint-id> -d "<new-desc>"` |
| Statistics | `rmp sprint stats -r <roadmap> <sprint-id>` |
| Remove sprint | `rmp sprint rm -r <roadmap> <sprint-id>` |

### Audit Log

| Action | Command |
|--------|---------|
| List audit | `rmp audit ls -r <roadmap> [-o <operation>] [-e <entity-type>] [--entity-id <id>] [--since <date>] [--until <date>] [-l <limit>]` |
| Entity history | `rmp audit hist -r <roadmap> -e <TASK/SPRINT> <id>` |
| Audit statistics | `rmp audit stats -r <roadmap> [--since <date>] [--until <date>]` |

## States and Transitions

### Task States

```
BACKLOG → SPRINT → DOING → TESTING → COMPLETED
   ↑                                    │
   └────────────────────────────────────┘ (reopen)
```

### Sprint States

```
PENDING → OPEN → CLOSED
            ↑      │
            └──────┘ (reopen)
```

## Usage Conventions

### Multiple IDs (Bulk Operations)

Use commas without spaces for batch operations:

```bash
rmp task stat -r project1 1,2,3,5 DOING
rmp task prio -r project1 10,11,12 9
rmp task rm -r project1 20,21,22
```

### Priority vs Severity

- **Priority (0-9)**: Urgency/Pertinence (Product Owner)
  - 0 = low urgency
  - 9 = maximum urgency

- **Severity (0-9)**: Technical impact (Dev Team)
  - 0 = minimal impact
  - 9 = critical impact

### Date Format

ISO 8601 UTC: `YYYY-MM-DDTHH:mm:ss.sssZ`

Example: `2026-03-12T14:30:00.000Z`

## Interaction Patterns

### Pattern 1: Structured Task Creation

When creating tasks, Claude should:

1. **Description**: Clear and concise objective
2. **Action**: Specific technical steps
3. **Expected Result**: Measurable acceptance criteria
4. **Priority**: Business urgency (0-9)
5. **Severity**: Technical impact (0-9)

**Example:**
```bash
rmp task new -r api-project \
  -d "Implement JWT authentication" \
  -a "Create authentication middleware with JWT token verification" \
  -e "Protected endpoints return 401 without valid token, 200 with valid token" \
  -p 9 \
  --severity 7
```

### Pattern 2: State Transition with Validation

Before transitioning, Claude should:

1. Check current task state
2. Validate if transition is allowed
3. Execute the change
4. Confirm new state

**Flow:**
```
Check state → Validate transition → Execute → Confirm
```

### Pattern 3: Progress Reports

Claude can generate periodic reports:

```bash
# Current sprint statistics
rmp sprint stats -r <roadmap> <sprint-id>

# Tasks by state
rmp task ls -r <roadmap> -s DOING
rmp task ls -r <roadmap> -s TESTING

# Recent operations audit
rmp audit ls -r <roadmap> -l 20
```

## Agentic Workflow Integration

## Usage Examples

### Example 1: Complete Sprint Setup from Scratch

**User:** "I want to start a new sprint for the authentication feature"

**Claude's Step-by-Step Execution:**

```
Step 1: Verify roadmap exists
   Command: rmp road ls
   Output: ["api-project", "web-client"]

Step 2: Create sprint with description
   Command: rmp sprint new -r api-project -d "Sprint 1 - Authentication"
   Output: {"id": 3, "status": "PENDING", "description": "Sprint 1 - Authentication"}

Step 3: Create structured tasks
   Task 1 (Setup):
   Command: rmp task new -r api-project -d "Setup JWT library" -a "Add jwt-go dependency" -e "Library ready" -p 9 --severity 5
   Output: {"id": 10, "status": "BACKLOG", ...}

   Task 2 (Middleware):
   Command: rmp task new -r api-project -d "Create auth middleware" -a "Implement JWT verification" -e "Validates tokens" -p 9 --severity 8
   Output: {"id": 11, "status": "BACKLOG", ...}

   Task 3 (Endpoint):
   Command: rmp task new -r api-project -d "Add login endpoint" -a "POST /auth/login" -e "Returns JWT" -p 8 --severity 6
   Output: {"id": 12, "status": "BACKLOG", ...}

Step 4: Add tasks to sprint
   Command: rmp sprint add -r api-project 3 10,11,12
   Output: Tasks 10, 11, 12 added to sprint 3

Step 5: Start sprint
   Command: rmp sprint start -r api-project 3
   Output: Sprint 3 status: OPEN

Step 6: Report summary
   "Sprint 1 - Authentication started with 3 tasks.
    Priorities: 9, 9, 8 | Severities: 5, 8, 6
    Sprint ready for development."
```

---

### Example 2: Daily Development Flow

**User:** "What's the next task I should work on?"

**Claude's Execution:**

```
Step 1: Get active sprint
   Command: rmp sprint ls -r api-project -s OPEN
   Output: Sprint 3 (OPEN)

Step 2: List available tasks ordered by priority
   Command: rmp sprint tasks -r api-project 3
   Output:
     - Task 11 (P9/S8) - SPRINT status
     - Task 10 (P9/S5) - SPRINT status
     - Task 12 (P8/S6) - DOING status

Step 3: Select highest priority task
   "Recommended: Task 11 (Create auth middleware)
    Priority: 9, Severity: 8 (highest impact)"

Step 4: Get task details
   Command: rmp task get -r api-project 11
   Output: Full task specification

Step 5: Transition to DOING
   Command: rmp task stat -r api-project 11 DOING
   Output: Status changed to DOING

Step 6: Provide guidance
   "Task 11 is now active. Follow the action field:
    'Implement JWT verification'
    Expected result: 'Validates tokens'"
```

---

### Example 3: Task Completion Workflow

**User:** "I finished implementing the middleware"

**Claude's Step-by-Step:**

```
Step 1: Verify current status
   Command: rmp task get -r api-project 11
   Output: {"id": 11, "status": "DOING", ...}

Step 2: Transition to TESTING
   Command: rmp task stat -r api-project 11 TESTING
   Output: Status changed to TESTING

Step 3: Wait/provide testing guidance
   "Task now in TESTING. Verify:
    - Unit tests pass
    - Integration with JWT library works
    - Error handling for invalid tokens"

Step 4: [User confirms tests pass]

Step 5: Transition to COMPLETED
   Command: rmp task stat -r api-project 11 COMPLETED
   Output: Status changed to COMPLETED

Step 6: Update sprint view
   Command: rmp sprint stats -r api-project 3
   Output: 33% complete (1/3 tasks)

Step 7: Identify next task
   Command: rmp sprint tasks -r api-project 3 -s SPRINT
   Output: Task 10 (Setup JWT library) - P9/S5

Step 8: Report progress
   "Task 11 completed! Sprint progress: 33%
    Next recommended: Task 10 (Setup JWT library)
    Note: Consider doing Task 10 before Task 12 due to dependency"
```

---

### Example 4: Sprint Review and Retrospective

**User:** "Show me the sprint retrospective"

**Claude's Execution:**

```
Step 1: Get sprint statistics
   Command: rmp sprint stats -r api-project 3
   Output:
     - Total tasks: 3
     - Completed: 2
     - In Progress: 1
     - Completion: 66%

Step 2: List completed tasks
   Command: rmp sprint tasks -r api-project 3 -s COMPLETED
   Output: Tasks 11, 10

Step 3: List remaining tasks
   Command: rmp sprint tasks -r api-project 3 -s DOING
   Output: Task 12

Step 4: Review audit trail
   Command: rmp audit ls -r api-project --since 2026-03-01T00:00:00Z -e TASK
   Output: All task operations

Step 5: Calculate metrics
   - Average time in DOING: 2.5 days
   - Tasks completed: 2/3
   - Blockers identified: 0

Step 6: Generate report
   "Sprint 1 Retrospective:
    [COMPLETED] 2/3 tasks (66%)
    [COMPLETED] High severity tasks completed first
    [PENDING] Remaining: Task 12 (login endpoint)
    [METRIC] Average completion time: 2.5 days/task
    [RECOMMENDATION] Break Task 12 into smaller subtasks"

Step 7: If closing sprint
   Command: rmp sprint close -r api-project 3
   Output: Sprint 3 status: CLOSED
```

---

### Example 5: Backlog Grooming

**User:** "Clean up the backlog"

**Claude's Step-by-Step:**

```
Step 1: Review all backlog tasks
   Command: rmp task ls -r api-project -s BACKLOG
   Output: 15 tasks

Step 2: Identify low priority items
   Command: rmp task ls -r api-project -s BACKLOG -p 3
   Output: 5 tasks with priority <= 3

Step 3: Check for obsolete tasks
   Review each task's description and action

Step 4: Remove obsolete tasks
   Command: rmp task rm -r api-project 20,21
   Output: Tasks 20, 21 removed

Step 5: Adjust priorities for upcoming sprint
   Command: rmp task prio -r api-project 22,23,24 7
   Output: Priorities updated

Step 6: Verify changes
   Command: rmp task ls -r api-project -s BACKLOG
   Output: 13 tasks (2 removed)

Step 7: Report
   "Backlog cleaned:
    - Removed: 2 obsolete tasks
    - Updated: 3 tasks prioritized to 7
    - Remaining: 13 tasks ready for sprint planning"
```

---

### Example 6: Handling Blocked Tasks

**User:** "Task 12 is blocked by a dependency"

**Claude's Response:**

```
Step 1: Check task details
   Command: rmp task get -r api-project 12
   Output: {"id": 12, "status": "DOING", ...}

Step 2: Review audit history
   Command: rmp audit hist -r api-project -e TASK 12
   Output: Status changes and timestamps

Step 3: Identify time in DOING
   Calculate: 5 days in DOING (potentially blocked)

Step 4: Return to BACKLOG or move to end
   Command: rmp task stat -r api-project 12 BACKLOG
   Output: Status changed to BACKLOG

Step 5: Select next task
   Command: rmp sprint tasks -r api-project 3 -s SPRINT
   Output: Task 15 available

Step 6: Update sprint if needed
   Command: rmp sprint rm-tasks -r api-project 3 12
   Output: Task removed from sprint

Step 7: Report action
   "Task 12 moved back to backlog due to dependency.
    Sprint updated: Task 12 removed.
    Recommended next: Task 15 (available and unblocked)"
```

## Exit Codes

| Code | Meaning | Claude Action |
|------|---------|---------------|
| 0 | Success | Continue flow |
| 1 | General error | Report error and try alternative |
| 2 | Invalid usage | Check command syntax |
| 3 | No roadmap | Request roadmap selection |
| 4 | Not found | Verify IDs and existence |
| 5 | Already exists | Suggest alternative name or use existing |
| 6 | Invalid data | Validate inputs before resending |
| 127 | Unknown command | Check rmp installation |

## JSON Response Format

All success responses are JSON. Claude should parse and present in readable format.

**Success:**
```json
{
  "id": 42,
  "priority": 9,
  "severity": 5,
  "status": "DOING",
  "description": "...",
  "action": "...",
  "expected_result": "...",
  "created_at": "2026-03-12T14:30:00.000Z",
  "completed_at": null
}
```

**Error (stderr):**
```
Error: Task with ID 999 not found in roadmap 'project1'
```

## Best Practices

1. **Always verify existence** before operating on entities
2. **Use batch operations** when possible for efficiency
3. **Maintain audit trail** - all operations are automatically logged
4. **Prioritize by urgency/impact** - use sprint ordering
5. **Validate transitions** - check if current state allows the transition
6. **Use Unix conventions** - `ls`, `rm`, `new`, `stat`, `prio`, `sev`
7. **Format dates in ISO 8601** when needed
8. **Handle errors gracefully** - parse stderr for clear messages

## Troubleshooting

### "rmp: command not found"
```bash
# Check installation
which rmp

# If not found, reinstall
zig build install

# Or add to PATH
export PATH=$PATH:/path/to/LRoadmap/zig-out/bin
```

### "Roadmap not found"
```bash
# List available roadmaps
rmp road ls

# Create if needed
rmp road new <name>
```

### "Task not found"
```bash
# Check existing IDs
rmp task ls -r <roadmap>
```

### Permission error on ~/.roadmaps
```bash
# Check permissions
ls -la ~/.roadmaps

# Fix if needed
chmod 755 ~/.roadmaps
chmod 644 ~/.roadmaps/*.db
```

## References

- [SPEC/COMMANDS.md](SPEC/COMMANDS.md) - Complete command reference
- [SPEC/DATA_FORMATS.md](SPEC/DATA_FORMATS.md) - JSON data formats
- [SPEC/DATABASE.md](SPEC/DATABASE.md) - SQLite schema and queries
- [README.md](README.md) - General project documentation
