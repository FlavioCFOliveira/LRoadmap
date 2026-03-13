# Complete Command Reference

## Global

```bash
# Help
rmp --help
rmp -h

# Version
rmp --version
rmp -v
```

---

## Roadmap Management

### List roadmaps
```bash
rmp roadmap list
rmp road ls
```

### Create roadmap
```bash
rmp roadmap create <name>
rmp roadmap new <name>
rmp road new project1
rmp roadmap create <name> --force
```

### Remove roadmap
```bash
rmp roadmap remove <name>
rmp roadmap rm <name>
rmp roadmap delete <name>
rmp road rm project1
```

### Select roadmap (default)
```bash
rmp roadmap use <name>
rmp road use project1
```

---

## Task Management

### List tasks
```bash
# All tasks
rmp task list --roadmap <name>
rmp task ls -r <name>

# With filters
rmp task list --roadmap <name> --status BACKLOG
rmp task list -r <name> -s DOING
rmp task list -r <name> -s COMPLETED
rmp task list -r <name> -p 5              # priority >= 5
rmp task list -r <name> --severity 3      # severity >= 3
rmp task list -r <name> -l 10             # limit to 10
rmp task list -r <name> -p 5 -l 20        # combined filters
```

### Create task
```bash
# Full command
rmp task create --roadmap <name> \
  --description <desc> \
  --action <action> \
  --expected-result <result> \
  [--priority <0-9>] \
  [--severity <0-9>] \
  [--specialists <list>]

# Short form
rmp task new -r <name> -d <desc> -a <action> -e <result>

# Examples
rmp task new -r project1 -d "Implement auth" -a "Create JWT" -e "Login works" --priority 9 --severity 3 --specialists "dev,security"
rmp task new -r project1 -d "Fix bug" -a "Fix memory leak" -e "No leaks"
rmp task new -r project1 -d "Update docs" -a "Write README" -e "Docs complete" --priority 5
```

### Get task(s)
```bash
# Single task
rmp task get --roadmap <name> <id>
rmp task get -r <name> 42

# Multiple tasks
rmp task get --roadmap <name> <id1,id2,id3>
rmp task get -r <name> 1,2,3,10,15
```

### Change status (stat)
```bash
# Single task
rmp task set-status --roadmap <name> <id> <state>
rmp task stat -r <name> 42 DOING

# Multiple tasks (bulk)
rmp task set-status --roadmap <name> <id1,id2,id3> <state>
rmp task stat -r <name> 1,2,3 DOING
rmp task stat -r <name> 5,8,12 COMPLETED
rmp task stat -r <name> 10,11,15,20 TESTING
rmp task stat -r <name> 1,2,3,4,5 BACKLOG
```

**States:** BACKLOG, SPRINT, DOING, TESTING, COMPLETED

### Change priority
```bash
# Single task
rmp task set-priority --roadmap <name> <id> <priority>
rmp task prio -r <name> 42 9

# Multiple tasks
rmp task set-priority --roadmap <name> <id1,id2,id3> <priority>
rmp task prio -r <name> 1,2,3 5
rmp task prio -r <name> 10,11,12 9
```

**Priority:** 0-9. Urgency/Pertinence: 0 = low urgency, 9 = maximum urgency.

### Change severity
```bash
# Single task
rmp task set-severity --roadmap <name> <id> <severity>
rmp task sev -r <name> 42 5

# Multiple tasks
rmp task set-severity --roadmap <name> <id1,id2,id3> <severity>
rmp task sev -r <name> 1,2,3 9
rmp task sev -r <name> 10,20,30 0
```

**Severity:** 0-9. Technical impact: 0 = minimal impact, 9 = critical impact.

### Remove task(s)
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

### List sprints
```bash
rmp sprint list --roadmap <name>
rmp sprint ls -r <name>
rmp sprint ls -r <name> --status OPEN
rmp sprint ls -r <name> -s CLOSED
```

### Get sprint
```bash
rmp sprint get --roadmap <name> <id>
rmp sprint get -r <name> 1
```

### List sprint tasks
```bash
rmp sprint tasks --roadmap <name> <sprint-id>
rmp sprint tasks -r <name> 1
rmp sprint tasks -r <name> 1 --status DOING
rmp sprint tasks -r <name> 1 -s COMPLETED
```

### Create sprint
```bash
rmp sprint create --roadmap <name> --description <desc>
rmp sprint new -r <name> -d "Sprint 2 - Features"
rmp sprint new -r <name> -d "Initial setup"
```

### Add tasks to sprint
```bash
rmp sprint add-tasks --roadmap <name> <sprint-id> <task-ids...>
rmp sprint add -r <name> 1 10,11,12
rmp sprint add -r <name> 2 5,6,7,8
```

### Remove tasks from sprint
```bash
rmp sprint remove-tasks --roadmap <name> <sprint-id> <task-ids...>
rmp sprint rm-tasks -r <name> 1 10,11,12
rmp sprint rm-tasks -r <name> 1 5,6
```

### Move tasks between sprints
```bash
rmp sprint move-tasks --roadmap <name> <from-sprint> <to-sprint> <task-ids...>
rmp sprint mv-tasks -r <name> 1 2 10,11,12
rmp sprint mv-tasks -r <name> 2 3 5,6,7
```

### Start sprint
```bash
rmp sprint start --roadmap <name> <id>
rmp sprint start -r <name> 1
```

### Close sprint
```bash
rmp sprint close --roadmap <name> <id>
rmp sprint close -r <name> 1
```

### Reopen sprint
```bash
rmp sprint reopen --roadmap <name> <id>
rmp sprint reopen -r <name> 1
```

### Update sprint
```bash
rmp sprint update --roadmap <name> <id> --description <new-desc>
rmp sprint upd -r <name> 1 -d "Sprint 1 - Setup and Config"
```

### Sprint statistics
```bash
rmp sprint stats --roadmap <name> <id>
rmp sprint stats -r <name> 1
```

### Remove sprint
```bash
rmp sprint remove --roadmap <name> <id>
rmp sprint rm -r <name> 1
```

---

## Audit Log Management

### List audit entries
```bash
# All entries (most recent first)
rmp audit list --roadmap <name>
rmp audit ls -r <name>

# With filters
rmp audit list -r <name> --operation TASK_STATUS_CHANGE
rmp audit list -r <name> -o SPRINT_START
rmp audit list -r <name> --entity-type TASK
rmp audit list -r <name> -e SPRINT
rmp audit list -r <name> --entity-id 42
rmp audit list -r <name> --since 2026-03-01T00:00:00.000Z
rmp audit list -r <name> --until 2026-03-12T23:59:59.000Z

# Combined filters
rmp audit list -r <name> -e TASK -o TASK_STATUS_CHANGE -l 50
rmp audit list -r <name> --since 2026-03-01T00:00:00.000Z --until 2026-03-10T00:00:00.000Z -l 100
```

### Get entity history
```bash
# Task history
rmp audit history --roadmap <name> --entity-type TASK <id>
rmp audit hist -r <name> -e TASK 42

# Sprint history
rmp audit history -r <name> --entity-type SPRINT <id>
rmp audit hist -r <name> -e SPRINT 1
```

### Audit statistics
```bash
# All time statistics
rmp audit stats --roadmap <name>
rmp audit stats -r <name>

# Period statistics
rmp audit stats -r <name> --since 2026-03-01T00:00:00.000Z
rmp audit stats -r <name> --since 2026-03-01T00:00:00.000Z --until 2026-03-31T23:59:59.000Z
```

---

## Syntax Patterns

### Multiple IDs (bulk)
- Format: `id1,id2,id3` (comma-separated, no spaces)
- Supported in: `get`, `set-status`, `set-priority`, `set-severity`, `remove`

### Common flags
- `-r, --roadmap <name>` - specify roadmap
- `-s, --status <state>` - filter by status
- `-p, --priority <n>` - filter/change priority
- `-l, --limit <n>` - limit results
- `-d, --description <text>` - description
- `-a, --action <text>` - technical action
- `-e, --expected-result <text>` - expected result

### Audit flags
- `-o, --operation <type>` - filter by operation type
- `--entity-type <type>` - filter by entity type (TASK, SPRINT)
- `--entity-id <id>` - filter by entity ID
- `--since <date>` - include entries from this date (ISO 8601)
- `--until <date>` - include entries until this date (ISO 8601)
- `--offset <n>` - pagination offset

### Unix Conventions
| Command | Meaning | Usage |
|---------|---------|-------|
| `ls` | list | all groups |
| `new` | create | all groups |
| `rm` | remove | all groups |
| `get` | get/retrieve | task get, sprint get |
| `stat` | status | task stat |
| `prio` | priority | task prio |
| `sev` | severity | task sev |
| `hist` | history | audit hist |
| `add` | add | sprint add |
| `rm-tasks` | remove tasks | sprint rm-tasks |
| `mv-tasks` | move tasks | sprint mv-tasks |
| `upd` | update | sprint upd |
| `use` | select | road use |
