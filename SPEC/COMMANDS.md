# CLI Commands

## Naming Conventions

- Commands: lowercase, kebab-case (`list`, `create`)
- Flags: double-dash for long (`--help`), single-dash for short (`-h`)
- Subcommands: clear hierarchy (`rmp roadmap list`)

## Command Structure

```
rmp [command] [subcommand] [arguments] [options]
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

**JSON Output (error):**
```json
{
  "success": false,
  "error": {
    "code": "ROADMAP_EXISTS",
    "message": "Roadmap 'project1' already exists"
  }
}
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

**JSON Output:** Task list (same format as `task list`).

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
| `use` | select | Specific context |

**Entity aliases:**
- `road` - roadmap (avoids `rm` conflict)
- `task` - task (full word, clear)
- `sprint` - sprint (full word, clear)

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
