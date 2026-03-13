# CLI Commands

## Naming Conventions

- Commands: lowercase, kebab-case (`list`, `create`)
- Flags: double-dash for long (`--help`), single-dash for short (`-h`)
- Subcommands: clear hierarchy (`rmp roadmap list`)

## Command Structure

```
rmp [command] [subcommand] [arguments] [options]
```

## Error Handling

Errors follow typical CLI conventions (NOT JSON format):

### Default Behavior
- Error messages are written explicitly to **stderr**
- Plain text format (human-readable)
- Uses standard Unix exit codes

### Input-Related Errors
When errors are related to inputs, the help for that command is displayed after the error:

**Input errors include:**
- Missing required parameters
- Invalid argument types or formats
- Unknown commands or subcommands
- Invalid flag combinations
- Missing required flags

**Example - General error (not input-related):**
```
$ rmp task get -r project1 999
Error: Task with ID 999 not found in roadmap 'project1'
```

**Example - Input error (shows help):**
```
$ rmp task create -r project1
Error: Missing required parameters: --description, --action, --expected-result

Usage: rmp task create [OPTIONS]

Creates a new task in the roadmap

Required:
  -d, --description <text>    Task description
  -a, --action <text>         Technical action to execute
  -e, --expected-result <text>  Expected result

Optional:
  -r, --roadmap <name>        Roadmap name
  -p, --priority <0-9>        Priority (default: 0)
  --severity <0-9>            Severity (default: 0)

Examples:
  rmp task create -r project1 -d "Fix bug" -a "Patch module" -e "Tests pass"
```

## Global Commands

### Help

```bash
rmp --help
rmp -h
```

Displays general help with available commands.

### Version

```bash
rmp --version
rmp -v
```

Displays application version.

---

## Roadmap Management

Command: `rmp roadmap` (alias: `rmp road`)

### List Roadmaps

```bash
rmp roadmap list
rmp road ls
```

**Description:** Lists all existing roadmaps in the `.roadmaps` directory.

**JSON Output:**
```json
{
  "success": true,
  "data": {
    "count": 3,
    "roadmaps": [
      {"name": "project1", "path": "~/.roadmaps/project1.db", "size": 24576},
      {"name": "project2", "path": "~/.roadmaps/project2.db", "size": 8192}
    ]
  }
}
```

### Create Roadmap

```bash
rmp roadmap create <name>
rmp roadmap new <name>
rmp roadmap create <name> --force
```

**Arguments:**
- `name`: Roadmap identifier (used in filename)

**Rules:**
- Alphanumeric, hyphens, and underscores only
- Maximum 50 characters
- Error if already exists (without `--force`)

**JSON Output (success):**
```json
{
  "success": true,
  "data": {
    "name": "project1",
    "path": "~/.roadmaps/project1.db",
    "created_at": "2026-03-12T14:30:00.000Z"
  }
}
```

**Error Output:**
```
Error: Roadmap 'project1' already exists at ~/.roadmaps/project1.db
```

### Remove Roadmap

```bash
rmp roadmap remove <name>
rmp roadmap rm <name>
rmp roadmap delete <name>
```

**Validation:** Verifies if valid SQLite before removing.

**JSON Output:**
```json
{
  "success": true,
  "data": {
    "name": "project1",
    "removed_at": "2026-03-12T14:35:00.000Z"
  }
}
```

### Select Roadmap (Optional)

```bash
rmp roadmap use <name>
rmp road use project1
```

Sets roadmap as default for subsequent commands.

---

## Task Management

Command: `rmp task` (alias: `rmp task`)

**Note:** Requires `--roadmap <name>` or pre-selected roadmap.

### List Tasks

```bash
rmp task list --roadmap <name>
rmp task ls -r <name>

# Filter
rmp task list --roadmap <name> --status BACKLOG
rmp task list -r <name> -s DOING
```

**Options:**
- `-r, --roadmap <name>`: Roadmap (required)
- `-s, --status <state>`: BACKLOG, SPRINT, DOING, TESTING, COMPLETED
- `-p, --priority <n>`: Minimum priority
- `-l, --limit <n>`: Limit results

**JSON Output:**
```json
{
  "success": true,
  "data": {
    "roadmap": "project1",
    "count": 5,
    "tasks": [
      {
        "id": 1,
        "priority": 9,
        "severity": 3,
        "status": "BACKLOG",
        "description": "Implement authentication",
        "action": "Create JWT auth system",
        "expected_result": "Functional login",
        "created_at": "2026-03-12T10:00:00.000Z",
        "completed_at": null
      }
    ]
  }
}
```

### Create Task

```bash
rmp task create --roadmap <name> \
  --description <desc> \
  --action <action> \
  --expected-result <result> \
  [--priority <0-9>] \
  [--severity <0-9>] \
  [--specialists <list>]
```

**Required:**
- `-r, --roadmap <name>`
- `-d, --description <text>`
- `-a, --action <text>`
- `-e, --expected-result <text>`

**Optional:**
- `--priority <0-9>`: Default 0
- `--severity <0-9>`: Default 0
- `--specialists <list>`: Comma-separated

**JSON Output:**
```json
{
  "success": true,
  "data": {
    "id": 42,
    "priority": 5,
    "severity": 3,
    "status": "BACKLOG",
    "description": "New feature",
    "action": "Implement X",
    "expected_result": "Y works",
    "created_at": "2026-03-12T15:00:00.000Z",
    "completed_at": null
  }
}
```

### Get Task(s)

```bash
# Single task
rmp task get --roadmap <name> <id>
rmp task get -r <name> 42

# Multiple tasks
rmp task get --roadmap <name> <id1,id2,id3>
rmp task get -r <name> 1,2,3,10,15
```

**Note:** IDs separated by comma, no spaces.

### Change Status (stat)

```bash
# Single task
rmp task set-status --roadmap <name> <id> <state>
rmp task stat -r <name> 42 DOING

# Multiple tasks (batch)
rmp task set-status --roadmap <name> <id1,id2,id3> <state>
rmp task stat -r <name> 1,2,3,5 DOING
rmp task stat -r <name> 5,8,12 COMPLETED
```

**States:** BACKLOG, SPRINT, DOING, TESTING, COMPLETED

**JSON Output (multiple):**
```json
{
  "success": true,
  "results": [
    {
      "success": true,
      "data": {
        "id": 1,
        "previous_status": "SPRINT",
        "new_status": "DOING",
        "changed_at": "2026-03-13T00:08:56.000Z"
      }
    },
    {
      "success": true,
      "data": {
        "id": 2,
        "previous_status": "SPRINT",
        "new_status": "DOING",
        "changed_at": "2026-03-13T00:08:56.000Z"
      }
    }
  ]
}
```

### Change Priority (Bulk Support)

```bash
# Single task
rmp task set-priority --roadmap <name> <id> <priority>
rmp task prio -r <name> 42 9

# Multiple tasks
rmp task set-priority --roadmap <name> <id1,id2,id3> <priority>
rmp task prio -r <name> 1,2,3,10 5
```

**Priority:** 0-9. Urgency/Pertinence: 0 = low urgency, 9 = maximum urgency.

**JSON Output (bulk):**
Same nested `results` format as status change for multiple IDs.

### Change Severity (Bulk Support)

```bash
# Single task
rmp task set-severity --roadmap <name> <id> <severity>
rmp task sev -r <name> 42 5

# Multiple tasks
rmp task set-severity --roadmap <name> <id1,id2,id3> <severity>
rmp task sev -r <name> 1,2,3,10 9
```

**Severity:** 0-9. Technical impact: 0 = minimal impact, 9 = critical impact.

**JSON Output (bulk):**
Same nested `results` format as status change for multiple IDs.

### Remove Task(s)

```bash
# Single task
rmp task remove --roadmap <name> <id>
rmp task rm -r <name> 42

# Multiple tasks
rmp task remove --roadmap <name> <id1,id2,id3>
rmp task rm -r <name> 1,2,3
```

---

## Sprint Management

Command: `rmp sprint` (alias: `rmp sprint`)

### List Sprints

```bash
rmp sprint list --roadmap <name>
rmp sprint ls -r <name>
rmp sprint ls -r <name> --status OPEN
```

### Create Sprint

```bash
rmp sprint create --roadmap <name> --description <desc>
rmp sprint new -r <name> -d "Sprint 2"
rmp sprint new -r <name> -d "Initial setup"
```

### Get Sprint

```bash
rmp sprint get --roadmap <name> <id>
rmp sprint get -r <name> 1
```

**JSON Output:**
```json
{
  "success": true,
  "data": {
    "id": 1,
    "status": "OPEN",
    "description": "Sprint 1 - Setup",
    "tasks": [1, 2, 3],
    "task_count": 3,
    "created_at": "2026-03-12T09:00:00.000Z",
    "started_at": "2026-03-12T10:00:00.000Z",
    "closed_at": null
  }
}
```

### List Sprint Tasks

```bash
rmp sprint tasks --roadmap <name> <sprint-id>
rmp sprint tasks -r <name> 1
rmp sprint tasks -r <name> 1 --status DOING
rmp sprint tasks -r <name> 1 -s COMPLETED
```

**Description:** Returns all tasks belonging to a specific sprint, automatically ordered by **priority (descending)** and **severity (descending)**.

**JSON Output:**
```json
{
  "success": true,
  "data": {
    "roadmap": "project1",
    "sprint_id": 1,
    "count": 5,
    "tasks": [
      {
        "id": 10,
        "priority": 9,
        "severity": 8,
        "status": "DOING",
        "description": "Critical security fix",
        "action": "Patch vulnerability",
        "expected_result": "System secure",
        "created_at": "2026-03-12T10:00:00.000Z",
        "completed_at": null
      },
      {
        "id": 5,
        "priority": 9,
        "severity": 5,
        "status": "SPRINT",
        "description": "Feature A",
        "action": "Implement core logic",
        "expected_result": "Tests pass",
        "created_at": "2026-03-12T09:00:00.000Z",
        "completed_at": null
      },
      {
        "id": 3,
        "priority": 7,
        "severity": 9,
        "status": "DOING",
        "description": "Database optimization",
        "action": "Add indexes",
        "expected_result": "Queries < 100ms",
        "created_at": "2026-03-11T14:00:00.000Z",
        "completed_at": null
      }
    ]
  }
}
```

**Ordering:** Tasks are sorted by `priority DESC`, then `severity DESC` (highest urgency/impact first).

### Add Tasks to Sprint

```bash
rmp sprint add-tasks --roadmap <name> <sprint-id> <task-ids...>
rmp sprint add -r <name> 1 10,11,12
```

**Note:** Tasks automatically change to SPRINT state.

### Remove Tasks from Sprint

```bash
rmp sprint remove-tasks --roadmap <name> <sprint-id> <task-ids...>
rmp sprint rm-tasks -r <name> 1 10,11,12
```

**Note:** Removed tasks return to BACKLOG state.

### Move Tasks Between Sprints

```bash
rmp sprint move-tasks --roadmap <name> <from-sprint> <to-sprint> <task-ids...>
rmp sprint mv-tasks -r <name> 1 2 10,11,12
```

**Note:** Tasks maintain SPRINT state, only change sprint.

### Update Sprint

```bash
rmp sprint update --roadmap <name> <id> --description <new-desc>
rmp sprint upd -r <name> 1 -d "Sprint 1 - Setup and Configuration"
```

### Start Sprint

```bash
rmp sprint start --roadmap <name> <id>
rmp sprint start -r <name> 1
```

### Close Sprint

```bash
rmp sprint close --roadmap <name> <id>
rmp sprint close -r <name> 1
```

### Reopen Sprint

```bash
rmp sprint reopen --roadmap <name> <id>
rmp sprint reopen -r <name> 1
```

**Note:** Changes state from CLOSED to OPEN. Useful for corrections.

### Sprint Statistics

```bash
rmp sprint stats --roadmap <name> <id>
rmp sprint stats -r <name> 1
```

**JSON Output:**
```json
{
  "success": true,
  "data": {
    "sprint_id": 1,
    "description": "Sprint 1 - Setup",
    "status": "OPEN",
    "total_tasks": 10,
    "by_status": {
      "BACKLOG": 0,
      "SPRINT": 2,
      "DOING": 3,
      "TESTING": 2,
      "COMPLETED": 3
    },
    "completion_percentage": 30,
    "created_at": "2026-03-12T09:00:00.000Z",
    "started_at": "2026-03-12T10:00:00.000Z",
    "closed_at": null
  }
}
```

### Remove Sprint

```bash
rmp sprint remove --roadmap <name> <id>
```

**Note:** Associated tasks return to BACKLOG.

---

## Audit Log Management

Command: `rmp audit`

### List Audit Log

```bash
# List all audit entries (most recent first)
rmp audit list --roadmap <name>
rmp audit ls -r <name>

# Filter by operation type
rmp audit list -r <name> --operation TASK_STATUS_CHANGE
rmp audit ls -r <name> -o SPRINT_START

# Filter by entity type
rmp audit list -r <name> --entity-type TASK
rmp audit ls -r <name> -e SPRINT

# Filter by entity ID
rmp audit list -r <name> --entity-id 42
rmp audit ls -r <name> --entity-id 1

# Filter by date range (ISO 8601)
rmp audit list -r <name> --since 2026-03-01T00:00:00.000Z
rmp audit list -r <name> --until 2026-03-12T23:59:59.000Z
rmp audit list -r <name> --since 2026-03-01T00:00:00.000Z --until 2026-03-10T00:00:00.000Z

# Combined filters
rmp audit list -r <name> --entity-type TASK --operation TASK_STATUS_CHANGE --limit 50
```

**Options:**
- `-r, --roadmap <name>`: Roadmap (required)
- `-o, --operation <type>`: Filter by operation type
- `-e, --entity-type <type>`: Filter by entity type (TASK, SPRINT)
- `--entity-id <id>`: Filter by specific entity ID
- `--since <date>`: Include entries from this date (ISO 8601)
- `--until <date>`: Include entries until this date (ISO 8601)
- `-l, --limit <n>`: Limit results (default: 100, max: 1000)
- `--offset <n>`: Offset for pagination (default: 0)

**JSON Output:**
```json
{
  "success": true,
  "data": {
    "roadmap": "project1",
    "count": 3,
    "total": 150,
    "filters": {
      "operation": null,
      "entity_type": null,
      "entity_id": null,
      "since": null,
      "until": null
    },
    "entries": [
      {
        "id": 152,
        "operation": "TASK_STATUS_CHANGE",
        "entity_type": "TASK",
        "entity_id": 42,
        "performed_at": "2026-03-13T10:30:00.000Z"
      },
      {
        "id": 151,
        "operation": "SPRINT_START",
        "entity_type": "SPRINT",
        "entity_id": 1,
        "performed_at": "2026-03-13T09:00:00.000Z"
      },
      {
        "id": 150,
        "operation": "TASK_CREATE",
        "entity_type": "TASK",
        "entity_id": 42,
        "performed_at": "2026-03-13T08:45:00.000Z"
      }
    ]
  }
}
```

### Get Entity History

```bash
# Get complete history of a specific task
rmp audit history --roadmap <name> --entity-type TASK <id>
rmp audit hist -r <name> -e TASK 42

# Get complete history of a specific sprint
rmp audit history -r <name> --entity-type SPRINT <id>
rmp audit hist -r <name> -e SPRINT 1
```

**Arguments:**
- `id`: Entity ID (required)

**Options:**
- `-r, --roadmap <name>`: Roadmap (required)
- `-e, --entity-type <type>`: Entity type (TASK, SPRINT) - required

**JSON Output:**
```json
{
  "success": true,
  "data": {
    "roadmap": "project1",
    "entity_type": "TASK",
    "entity_id": 42,
    "count": 5,
    "entries": [
      {
        "id": 152,
        "operation": "TASK_STATUS_CHANGE",
        "performed_at": "2026-03-13T10:30:00.000Z"
      },
      {
        "id": 148,
        "operation": "TASK_PRIORITY_CHANGE",
        "performed_at": "2026-03-12T16:00:00.000Z"
      },
      {
        "id": 145,
        "operation": "TASK_SEVERITY_CHANGE",
        "performed_at": "2026-03-12T14:30:00.000Z"
      },
      {
        "id": 143,
        "operation": "SPRINT_ADD_TASK",
        "performed_at": "2026-03-12T11:00:00.000Z"
      },
      {
        "id": 150,
        "operation": "TASK_CREATE",
        "performed_at": "2026-03-13T08:45:00.000Z"
      }
    ]
  }
}
```

### Audit Statistics

```bash
# Get audit statistics for a roadmap
rmp audit stats --roadmap <name>
rmp audit stats -r <name>

# Statistics for specific period
rmp audit stats -r <name> --since 2026-03-01T00:00:00.000Z
rmp audit stats -r <name> --since 2026-03-01T00:00:00.000Z --until 2026-03-31T23:59:59.000Z
```

**Options:**
- `-r, --roadmap <name>`: Roadmap (required)
- `--since <date>`: Start date for period
- `--until <date>`: End date for period

**JSON Output:**
```json
{
  "success": true,
  "data": {
    "roadmap": "project1",
    "period": {
      "since": "2026-03-01T00:00:00.000Z",
      "until": "2026-03-13T23:59:59.000Z"
    },
    "total_entries": 150,
    "by_operation": {
      "TASK_CREATE": 25,
      "TASK_STATUS_CHANGE": 45,
      "TASK_PRIORITY_CHANGE": 12,
      "TASK_SEVERITY_CHANGE": 8,
      "TASK_DELETE": 3,
      "SPRINT_CREATE": 5,
      "SPRINT_START": 4,
      "SPRINT_CLOSE": 3,
      "SPRINT_ADD_TASK": 30,
      "SPRINT_REMOVE_TASK": 15,
      "SPRINT_REOPEN": 1
    },
    "by_entity_type": {
      "TASK": 93,
      "SPRINT": 57
    },
    "first_entry": "2026-03-01T09:00:00.000Z",
    "last_entry": "2026-03-13T18:30:00.000Z"
  }
}
```

---

## Command Summary

| Command | Alias | Description |
|---------|-------|-------------|
| `rmp --help` | `-h` | General help |
| `rmp --version` | `-v` | Version |
| **Roadmap** | | |
| `rmp roadmap list` | `rmp road ls` | List roadmaps |
| `rmp roadmap create <n>` | `rmp road new` | Create roadmap |
| `rmp roadmap remove <n>` | `rmp road rm` | Remove roadmap |
| `rmp roadmap use <n>` | `rmp road use` | Select roadmap |
| **Task** | | |
| `rmp task list` | `rmp task ls` | List tasks |
| `rmp task create` | `rmp task new` | Create task |
| `rmp task get <id>` | `rmp task get` | Get task(s) |
| `rmp task set-status` | `rmp task stat` | Change status |
| `rmp task set-priority` | `rmp task prio` | Change priority |
| `rmp task set-severity` | `rmp task sev` | Change severity |
| `rmp task remove <id>` | `rmp task rm` | Remove task (Unix: rm) |
| **Sprint** | | |
| `rmp sprint list` | `rmp sprint ls` | List sprints |
| `rmp sprint get <id>` | `rmp sprint get` | Get sprint |
| `rmp sprint tasks <id>` | `rmp sprint tasks` | List sprint tasks |
| `rmp sprint create` | `rmp sprint new` | Create sprint |
| `rmp sprint add-tasks` | `rmp sprint add` | Add tasks |
| `rmp sprint remove-tasks` | `rmp sprint rm-tasks` | Remove tasks |
| `rmp sprint move-tasks` | `rmp sprint mv-tasks` | Move tasks |
| `rmp sprint start <id>` | `rmp sprint start` | Start sprint |
| `rmp sprint close <id>` | `rmp sprint close` | Close sprint |
| `rmp sprint reopen <id>` | `rmp sprint reopen` | Reopen sprint |
| `rmp sprint update <id>` | `rmp sprint upd` | Update sprint |
| `rmp sprint stats <id>` | `rmp sprint stats` | Sprint statistics |
| `rmp sprint remove <id>` | `rmp sprint rm` | Remove sprint (Unix: rm) |
| **Audit** | | |
| `rmp audit list` | `rmp audit ls` | List audit log |
| `rmp audit history <id>` | `rmp audit hist` | Entity history |
| `rmp audit stats` | `rmp audit stats` | Audit statistics |

### Applied Unix/Linux Conventions

**Principles:**
| Convention | Meaning | Used in |
|------------|---------|---------|
| `ls` | list (Unix `ls`) | All groups |
| `new` | create (Git-style) | All groups |
| `rm` | remove (Unix `rm`) | **Removals** - per Unix semantics |
| `get` | get/retrieve | Retrieve |
| `stat` | status | **Status changes** |
| `prio` | priority | Change priority |
| `sev` | severity | Change severity |
| `hist` | history | Entity history |
| `use` | select | Specific context |

**Entity aliases:**
- `road` - roadmap (avoids `rm` conflict)
- `task` - task (full word, clear)
- `sprint` - sprint (full word, clear)
- `audit` - audit log (full word, clear)
- `aud` - audit (optional shorter form)

**Unix-compliant examples:**
```bash
# Remove (rm = remove - Unix convention)
rmp road rm project1          # roadmap remove
rmp task rm 42                # task remove
rmp sprint rm 1               # sprint remove

# Change status (stat = status)
rmp task stat 42 DOING          # task set-status DOING
rmp task stat 1,2,3 COMPLETED   # multiple tasks

# Get (get = retrieve)
rmp task get 42               # task get 42
rmp sprint get 1              # sprint get 1
```
