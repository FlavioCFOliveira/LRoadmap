# Data Formats

## Fundamental Principle

### Output (Responses)

**All application responses are in JSON, without exceptions.**

Including:
- Successes
- Errors
- Listings
- Help commands (structured)

### Input

**All application inputs are via CLI parameters, without exceptions.**

- No JSON input
- No stdin input
- No configuration files
- No interactive input

**Accepted formats:**
- Positional parameters: `rmp task create <name>`
- Short flags: `-r <name>`, `-p 5`
- Long flags: `--roadmap <name>`, `--priority 5`
- Comma-separated lists: `1,2,3`

---

## Response Structure

### Success Response

```json
{
  "success": true,
  "data": { /* command-specific payload */ }
}
```

### Error Response

```json
{
  "success": false,
  "error": {
    "code": "ERROR_CODE",
    "message": "Human-readable error description",
    "details": { /* optional, additional info */ }
  }
}
```

### Common Error Codes

| Code | Description |
|------|-------------|
| `INVALID_INPUT` | Invalid or missing arguments |
| `ROADMAP_NOT_FOUND` | Specified roadmap does not exist |
| `ROADMAP_EXISTS` | Attempt to create duplicate roadmap |
| `INVALID_SQLITE_FILE` | File is not valid SQLite |
| `TASK_NOT_FOUND` | Specified task(s) do not exist |
| `SPRINT_NOT_FOUND` | Specified sprint does not exist |
| `INVALID_STATUS` | Invalid status for operation |
| `INVALID_PRIORITY` | Priority outside 0-9 range |
| `INVALID_DATE_FORMAT` | Date not in ISO 8601 format |
| `INVALID_ENTITY_TYPE` | Entity type not TASK or SPRINT |
| `INVALID_OPERATION` | Invalid operation type for filter |
| `DB_ERROR` | Internal SQLite error |
| `SYSTEM_ERROR` | System error (permissions, I/O) |

---

## Dates - ISO 8601 with UTC

### Exact Format

```
YYYY-MM-DDTHH:mm:ss.sssZ
```

**Example:**
```
2026-03-12T14:30:25.123Z
```

### Rules

1. **Always UTC**: All dates are converted to UTC
2. **With milliseconds**: 3 digits after the dot
3. **Z suffix**: Explicit UTC indicator
4. **T separator**: Between date and time

### Example Values

| Context | Example |
|---------|---------|
| created_at | `2026-03-12T14:30:00.000Z` |
| started_at | `2026-03-12T15:00:00.000Z` |
| completed_at | `2026-03-12T18:45:30.123Z` |
| closed_at | `null` (when not applicable) |

### Null Values

Date fields not set are represented as `null` in JSON (not empty string).

```json
{
  "created_at": "2026-03-12T10:00:00.000Z",
  "completed_at": null
}
```

---

## Data Types

### Task

```json
{
  "id": 1,
  "priority": 9,
  "severity": 0,
  "status": "BACKLOG",
  "description": "Implement JWT authentication system",
  "specialists": "zig-developer,security-expert",
  "action": "Create authentication module with JWT token support",
  "expected_result": "Functional login with 24h valid tokens",
  "created_at": "2026-03-12T10:00:00.000Z",
  "completed_at": null
}
```

| Field | JSON Type | Description |
|-------|-----------|-------------|
| id | number | Unique task ID (integer) |
| priority | number | 0-9 (9 = highest priority). Urgency/Pertinence: 0 = low urgency, 9 = maximum urgency. |
| severity | number | 0-9 (9 = highest severity). Technical impact: 0 = minimal impact, 9 = critical impact. |
| status | string | One of: BACKLOG, SPRINT, DOING, TESTING, COMPLETED |
| description | string | Task description |
| specialists | string | Comma-separated list (can be empty) |
| action | string | Technical action description |
| expected_result | string | How to measure success |
| created_at | string | ISO 8601 UTC |
| completed_at | string/null | ISO 8601 UTC or null |

#### Priority vs Severity

Although both use scale 0-9, these fields represent distinct dimensions:

| Field | Dimension | 0 means | 9 means | Who defines |
|-------|-----------|---------|---------|-------------|
| **priority** | Urgency / Pertinence | Low urgency | Maximum urgency | Product Owner / Manager |
| **severity** | Technical Impact | Minimal impact | Critical impact | Dev Team / Tech Lead |

**Practical example:**
- A critical bug may have `severity: 9` (grave technical impact) but `priority: 3` (can wait)
- A marketing task may have `priority: 9` (urgent for launch) but `severity: 1` (technically simple)

### Sprint

```json
{
  "id": 1,
  "status": "OPEN",
  "description": "Sprint 1 - Setup and architecture",
  "tasks": [1, 2, 3, 5],
  "task_count": 4,
  "created_at": "2026-03-12T09:00:00.000Z",
  "started_at": "2026-03-12T10:00:00.000Z",
  "closed_at": null
}
```

| Field | JSON Type | Description |
|-------|-----------|-------------|
| id | number | Unique sprint ID |
| status | string | One of: PENDING, OPEN, CLOSED |
| description | string | Sprint description |
| tasks | array | Array of task IDs (via sprint_tasks) |
| task_count | number | Number of tasks in sprint |
| created_at | string | ISO 8601 UTC |
| started_at | string/null | ISO 8601 UTC or null |
| closed_at | string/null | ISO 8601 UTC or null |

### Sprint_Task (Relationship)

Represents association between sprint and task.

```json
{
  "sprint_id": 1,
  "task_id": 42,
  "added_at": "2026-03-12T15:00:00.000Z"
}
```

| Field | JSON Type | Description |
|-------|-----------|-------------|
| sprint_id | number | Sprint ID |
| task_id | number | Task ID |
| added_at | string | ISO 8601 UTC - when added to sprint |

### Sprint Tasks List Response

Response from `rmp sprint tasks` command. Tasks are ordered by **priority DESC, severity DESC** (highest urgency/impact first).

```json
{
  "success": true,
  "data": {
    "roadmap": "project1",
    "sprint_id": 1,
    "count": 3,
    "tasks": [
      {
        "id": 10,
        "priority": 9,
        "severity": 8,
        "status": "DOING",
        "description": "Critical security fix",
        "specialists": "security-expert",
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
        "specialists": null,
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
        "specialists": "dba",
        "action": "Add indexes",
        "expected_result": "Queries < 100ms",
        "created_at": "2026-03-11T14:00:00.000Z",
        "completed_at": null
      }
    ]
  }
}
```

**Ordering Logic:**
- Primary sort: `priority` descending (9 → 0)
- Secondary sort: `severity` descending (9 → 0)

This ensures the most urgent AND technically impactful tasks appear first in the sprint view.

### Audit Entry

Operation log for tasks and sprints.

```json
{
  "id": 1,
  "operation": "TASK_STATUS_CHANGE",
  "entity_type": "TASK",
  "entity_id": 42,
  "performed_at": "2026-03-12T15:30:00.000Z"
}
```

| Field | JSON Type | Description |
|-------|-----------|-------------|
| id | number | Unique audit entry ID |
| operation | string | One of: TASK_CREATE, TASK_UPDATE, TASK_DELETE, TASK_STATUS_CHANGE, TASK_PRIORITY_CHANGE, TASK_SEVERITY_CHANGE, SPRINT_CREATE, SPRINT_UPDATE, SPRINT_DELETE, SPRINT_GET, SPRINT_STATS, SPRINT_LIST_TASKS, SPRINT_START, SPRINT_CLOSE, SPRINT_REOPEN, SPRINT_ADD_TASK, SPRINT_REMOVE_TASK, SPRINT_MOVE_TASK |
| entity_type | string | `'TASK'` or `'SPRINT'` |
| entity_id | number | Affected entity ID |
| performed_at | string | ISO 8601 UTC - when executed |

### Audit Operations

| Operation | Entity | Description |
|-----------|--------|-------------|
| `TASK_CREATE` | TASK | New task created |
| `TASK_UPDATE` | TASK | Task updated (generic) |
| `TASK_DELETE` | TASK | Task deleted |
| `TASK_STATUS_CHANGE` | TASK | Status change |
| `TASK_PRIORITY_CHANGE` | TASK | Priority change |
| `TASK_SEVERITY_CHANGE` | TASK | Severity change |
| `SPRINT_CREATE` | SPRINT | New sprint created |
| `SPRINT_UPDATE` | SPRINT | Sprint updated (generic) |
| `SPRINT_DELETE` | SPRINT | Sprint deleted |
| `SPRINT_GET` | SPRINT | Sprint retrieved |
| `SPRINT_STATS` | SPRINT | Sprint statistics retrieved |
| `SPRINT_LIST_TASKS` | SPRINT | Sprint tasks listed |
| `SPRINT_START` | SPRINT | Sprint started (OPEN) |
| `SPRINT_CLOSE` | SPRINT | Sprint closed (CLOSED) |
| `SPRINT_REOPEN` | SPRINT | Sprint reopened |
| `SPRINT_ADD_TASK` | SPRINT | Task added to sprint |
| `SPRINT_REMOVE_TASK` | SPRINT | Task removed from sprint |
| `SPRINT_MOVE_TASK` | SPRINT | Task moved between sprints |

### Roadmap (Reference)

```json
{
  "name": "project1",
  "path": "~/.roadmaps/project1.db",
  "size": 24576,
  "created_at": "2026-03-12T14:30:00.000Z"
}
```

### Audit List Response

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
      }
    ]
  }
}
```

### Audit History Response

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

### Audit Statistics Response

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

## Enums

### TaskStatus

| Value | Meaning |
|-------|---------|
| `BACKLOG` | Task created, awaits planning |
| `SPRINT` | Planned, associated to sprint |
| `DOING` | In development |
| `TESTING` | In testing, may have changes |
| `COMPLETED` | Developed and tested, closed |

### SprintStatus

| Value | Meaning |
|-------|---------|
| `PENDING` | Sprint created, not started |
| `OPEN` | In progress |
| `CLOSED` | Finished |

---

## Response Examples

### List Roadmaps

```json
{
  "success": true,
  "data": {
    "count": 3,
    "roadmaps": [
      {
        "name": "project1",
        "path": "/home/user/.roadmaps/project1.db",
        "size": 24576,
        "created_at": "2026-03-12T10:00:00.000Z"
      },
      {
        "name": "project2",
        "path": "/home/user/.roadmaps/project2.db",
        "size": 8192,
        "created_at": "2026-03-11T09:00:00.000Z"
      }
    ]
  }
}
```

### Create Task

```json
{
  "success": true,
  "data": {
    "id": 42,
    "priority": 5,
    "severity": 3,
    "status": "BACKLOG",
    "description": "Implement CLI parsing",
    "specialists": "zig-developer",
    "action": "Create argument parser in Zig",
    "expected_result": "CLI accepts all defined commands",
    "created_at": "2026-03-12T15:30:00.000Z",
    "completed_at": null
  }
}
```

### Error - Roadmap Exists

```json
{
  "success": false,
  "error": {
    "code": "ROADMAP_EXISTS",
    "message": "Roadmap 'project1' already exists at ~/.roadmaps/project1.db",
    "details": {
      "roadmap_name": "project1",
      "existing_path": "~/.roadmaps/project1.db"
    }
  }
}
```

### Error - Task Not Found

```json
{
  "success": false,
  "error": {
    "code": "TASK_NOT_FOUND",
    "message": "Task(s) with ID(s) [99, 100] not found in roadmap 'project1'",
    "details": {
      "roadmap": "project1",
      "missing_ids": [99, 100]
    }
  }
}
```

### Error - Audit Entity Not Found

```json
{
  "success": false,
  "error": {
    "code": "AUDIT_ENTITY_NOT_FOUND",
    "message": "No audit entries found for TASK with ID 999 in roadmap 'project1'",
    "details": {
      "roadmap": "project1",
      "entity_type": "TASK",
      "entity_id": 999
    }
  }
}
```

### Bulk Update

```json
{
  "success": true,
  "data": {
    "updated": [1, 2, 3],
    "count": 3,
    "new_status": "DOING",
    "updated_at": "2026-03-12T16:00:00.000Z"
  }
}
```

---

## Help in JSON

Even help (`--help`) is structured in JSON:

```json
{
  "success": true,
  "data": {
    "command": "task create",
    "description": "Creates a new task in the roadmap",
    "usage": "rmp task create --roadmap <name> --description <desc> --action <action> --expected-result <result>",
    "options": [
      {
        "short": "-r",
        "long": "--roadmap",
        "required": true,
        "description": "Roadmap name"
      },
      {
        "short": "-d",
        "long": "--description",
        "required": true,
        "description": "Task description"
      },
      {
        "short": "-a",
        "long": "--action",
        "required": true,
        "description": "Technical action to execute"
      },
      {
        "short": "-e",
        "long": "--expected-result",
        "required": true,
        "description": "Expected result"
      },
      {
        "long": "--priority",
        "required": false,
        "default": 0,
        "description": "Priority 0-9"
      }
    ],
    "examples": [
      "rmp task create -r project1 -d 'New feature' -a 'Implement X' -e 'Y works'"
    ]
  }
}
```

---

## Implementation Notes

1. **No extra fields**: Do not include extra fields in JSON responses
2. **Consistent order**: Maintain field order as defined in examples
3. **No pretty-print by default**: Compact JSON for efficient parsing
4. **UTF-8**: All strings in UTF-8
5. **Numbers**: Use JSON number format (not strings)
6. **Empty arrays**: Represent as `[]` (not `null`)
