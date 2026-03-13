# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

LRoadmap is a Local Roadmap Manager CLI for agentic workflows, written in **Zig** exclusively. It manages technical roadmaps, tasks, and sprints through a command-line interface with JSON output.

## Technology Stack

- **Language**: Zig (exclusively)
- **Database**: SQLite (individual `.db` files per roadmap)
- **Input**: CLI arguments only (no JSON, no stdin, no config files)
- **Output**: JSON for success, plain text for errors (typical CLI behavior)
- **Dates**: ISO 8601 with UTC (`2026-03-12T14:30:00.000Z`)

## Build Commands

```bash
# Build the project
zig build

# Build and run
zig build run

# Run tests
zig build test

# Install binary
zig build install

# Clean build artifacts
zig build clean
```

## Project Structure

```
LRoadmap/
├── build.zig              # Zig build system
├── build.zig.zon          # Package manifest
├── src/
│   ├── main.zig           # Entry point, CLI parsing
│   ├── commands/
│   │   ├── roadmap.zig    # Roadmap subcommands
│   │   ├── task.zig       # Task subcommands
│   │   └── sprint.zig     # Sprint subcommands
│   ├── db/
│   │   ├── connection.zig # SQLite connection management
│   │   ├── schema.zig     # DDL, structure creation
│   │   └── queries.zig    # Parameterized SQL queries
│   ├── models/
│   │   ├── task.zig       # Task structs, enums
│   │   ├── sprint.zig     # Sprint structs, enums
│   │   └── roadmap.zig    # Roadmap structures
│   └── utils/
│       ├── json.zig       # JSON serialization
│       ├── time.zig       # ISO 8601 date handling
│       └── path.zig       # Cross-platform path resolution
└── SPEC/                  # Technical specification
    ├── ARCHITECTURE.md
    ├── COMMANDS.md
    ├── DATABASE.md
    ├── DATA_FORMATS.md
    └── COMMANDS_REFERENCE.md
```

## Data Storage

Roadmaps are stored in `~/.roadmaps/` as individual SQLite files:
- Each `.db` file is an independent roadmap
- Database schema includes: `tasks`, `sprints`, `sprint_tasks`, `audit`, `_metadata`
- All dates stored as ISO 8601 UTC

## Command Structure

```
rmp [command] [subcommand] [arguments] [options]
```

### Main Commands

| Command | Alias | Description |
|---------|-------|-------------|
| `rmp roadmap` | `rmp road` | Roadmap management |
| `rmp task` | `rmp task` | Task management |
| `rmp sprint` | `rmp sprint` | Sprint management |

### Unix Conventions Used

| Convention | Command | Usage |
|------------|---------|-------|
| `ls` | list | All groups |
| `new` | create | All groups (Git-style) |
| `rm` | remove | All groups (per Unix semantics) |
| `get` | retrieve | Task/sprint retrieval |
| `stat` | status | Change task status |
| `prio` | priority | Change task priority |
| `sev` | severity | Change task severity |

### Common Flags

- `-r, --roadmap <name>` - Specify roadmap (required for most commands)
- `-d, --description <text>` - Description
- `-a, --action <text>` - Technical action
- `-e, --expected-result <text>` - Expected result
- `-s, --status <state>` - Filter by status
- `-p, --priority <n>` - Priority (0-9)
- `-l, --limit <n>` - Limit results

### Bulk Operations

Most commands support multiple IDs (comma-separated, no spaces):
```bash
rmp task get -r project1 1,2,3,10
rmp task stat -r project1 1,2,3 DOING
rmp task prio -r project1 5,6,7 9
```

## Key Design Principles

1. **Local-First**: All data in individual SQLite files (`~/.roadmaps/*.db`)
2. **JSON Output**: Success responses in JSON; errors in plain text (typical CLI behavior)
3. **No Interactive Input**: CLI arguments only, no stdin, no config files
4. **Unix Conventions**: Standard CLI patterns (`ls`, `rm`, `new`, etc.)
5. **Complete Audit**: Full history logged in `audit` table

## Error Response Format

Errors follow typical CLI behavior (NOT JSON):

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

**Example - General error:**
```
$ rmp task get -r project1 999
Error: Task with ID 999 not found in roadmap 'project1'
```

**Example - Input error (shows help):**
```
$ rmp task create -r project1
Error: Missing required parameters: --description, --action, --expected-result

Usage: rmp task create [OPTIONS]
...
```

Common error codes: `INVALID_INPUT`, `ROADMAP_NOT_FOUND`, `ROADMAP_EXISTS`, `TASK_NOT_FOUND`, `SPRINT_NOT_FOUND`, `INVALID_STATUS`, `DB_ERROR`

## Task Status Flow

```
BACKLOG → SPRINT → DOING → TESTING → COMPLETED
```

## Sprint Status Flow

```
PENDING → OPEN → CLOSED
```

Tasks can be reopened from CLOSED to OPEN.

## Priority vs Severity

Both are 0-9 scales but represent different dimensions:

- **Priority**: Urgency/Pertinence (Product Owner) - 0 = low urgency, 9 = maximum urgency
- **Severity**: Technical impact (Dev Team) - 0 = minimal impact, 9 = critical impact

## Reference Documentation

All commands, data formats, and SQL queries are fully specified in the `SPEC/` directory:
- `SPEC/ARCHITECTURE.md` - System architecture and module responsibilities
- `SPEC/COMMANDS.md` - Complete CLI command reference
- `SPEC/DATABASE.md` - SQLite schema and queries
- `SPEC/DATA_FORMATS.md` - JSON output formats and enums
- `SPEC/COMMANDS_REFERENCE.md` - Quick command reference with examples

## Zig 0.15 API Changes

When working with this codebase, note these Zig 0.15 changes:

### ArrayList (Unmanaged Pattern)
```zig
// OLD: Managed ArrayList
var list = std.ArrayList(T).init(allocator);
defer list.deinit();
try list.append(item);

// NEW: Unmanaged ArrayList
var list: std.array_list.Aligned(T, null) = .empty;
defer list.deinit(allocator);
try list.append(allocator, item);
```

### Error Handling
```zig
// When error value is not used
catch { /* handle error */ }

// When error value is used
catch |err| {
    if (err == error.FileNotFound) { ... }
}
```

### SQLite C Bindings
Always use `@ptrCast` when passing connection to C functions:
```zig
const rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), ...);
```
