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
When errors are related to inputs (misuse of commands or subcommands), the **specific help for that command or subcommand** is displayed after the error:

**Input errors include:**
- Missing required parameters
- Invalid argument types or formats
- Unknown commands or subcommands
- Invalid flag combinations
- Missing required flags

---

## Global Commands

### Help

```bash
rmp --help
rmp -h
```

**Description:** Displays general help with available commands in **plain text**. This is also the default behavior when no command is provided.

### Version

```bash
rmp --version
rmp -v
```

**Description:** Displays application version.

---

## Roadmap Management

Command: `rmp roadmap` (alias: `rmp road`)

### List Roadmaps

```bash
rmp roadmap list
rmp road ls
```

**Description:** Lists all existing roadmaps.

**JSON Output:**
```json
[
  {"name": "project1", "path": "~/.roadmaps/project1.db", "size": 24576},
  {"name": "project2", "path": "~/.roadmaps/project2.db", "size": 8192}
]
```

### Create Roadmap

```bash
rmp roadmap create <name>
rmp road new <name>
```

**Output (success):** `{"name": "project1"}`, exit code 0.

### Remove Roadmap

```bash
rmp roadmap remove <name>
rmp road rm <name>
```

**Output (success):** No output, exit code 0.

---

## Task Management

Command: `rmp task` (alias: `rmp task`)

### List Tasks

```bash
rmp task list --roadmap <name>
rmp task ls -r <name>
```

**JSON Output:**
```json
[{
  "id": 1,
  "priority": 9,
  "severity": 3,
  "status": "BACKLOG",
  "description": "...",
  ...
}]
```

### Create Task

```bash
rmp task create --roadmap <name> --description <desc> --action <a> --expected-result <e>
```

**Output (success):** `{"id": 42}`, exit code 0.

### Get Task(s)

```bash
rmp task get --roadmap <name> <id1,id2>
```

**JSON Output:**
```json
[{ "id": 1, ... }, { "id": 2, ... }]
```

### Change Status (stat)

```bash
rmp task stat -r <name> <id> <state>
```

**Output (success):** No output, exit code 0.

---

## Sprint Management

Command: `rmp sprint` (alias: `rmp sprint`)

### List Sprints

```bash
rmp sprint list -r <name>
```

**JSON Output:** Array of sprint objects.

### Create Sprint

```bash
rmp sprint create -r <name> -d "Description"
```

**Output (success):** `{"id": 1}`, exit code 0.

### Get Sprint

```bash
rmp sprint get -r <name> <id>
```

**JSON Output:** Single sprint object.

### Sprint Statistics

```bash
rmp sprint stats -r <name> <id>
```

**JSON Output:** Statistics object.

### Start/Close/Reopen Sprint

```bash
rmp sprint start -r <name> <id>
rmp sprint close -r <name> <id>
rmp sprint reopen -r <name> <id>
```

**Output (success):** No output, exit code 0.

### Add/Remove/Move Tasks

```bash
rmp sprint add -r <name> <sprint-id> <task-ids>
rmp sprint rm-tasks -r <name> <sprint-id> <task-ids>
rmp sprint mv-tasks -r <name> <from-id> <to-id> <task-ids>
```

**Output (success):** No output, exit code 0.

---

## Audit Log Management

Command: `rmp audit` (alias: `aud`)

### List Audit Log / History / Stats

**JSON Output:** Audit entries, history, or statistics objects.
