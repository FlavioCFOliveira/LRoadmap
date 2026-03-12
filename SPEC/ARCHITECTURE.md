# System Architecture

## High-Level Overview

LRoadmap is a CLI application distributed as a single binary executable. The architecture follows principles of simplicity, performance, and data isolation.

```
+-------------------------------------+
|           CLI Interface             |
|         (Zig, argument parsing)      |
+------------------+------------------+
                   |
+------------------v------------------+
|         Command Router            |
|   (roadmap | task | sprint)       |
+------------------+------------------+
                   |
+------------------v------------------+
|         Business Logic              |
|   (validation, business rules)    |
+------------------+------------------+
                   |
+------------------v------------------+
|         SQLite Layer                |
|   (queries, transactions, schema)   |
+------------------+------------------+
                   |
+------------------v------------------+
|         Filesystem                  |
|   (~/.roadmaps/*.db)                |
+-------------------------------------+
```

## Directory Structure

```
~/.roadmaps/              # User data directory
├── project1.db          # Individual roadmap (SQLite)
├── project2.db
└── ...
```

### Location Rules

1. The `.roadmaps` directory is located in the **user home directory**
2. Directory name: exactly `.roadmaps` (dot prefix, lowercase)
3. Each `.db` file represents an independent roadmap
4. Only files with `.db` extension are considered

## Source Code Structure

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
    ├── README.md
    ├── ARCHITECTURE.md
    ├── COMMANDS.md
    ├── DATABASE.md
    ├── DATA_FORMATS.md
    └── COMMANDS_REFERENCE.md
```

## Modules and Responsibilities

### 1. main.zig
- Parse command-line arguments
- Route to appropriate handlers
- Top-level error handling
- Consistent JSON output

### 2. commands/
Each module implements:
- Argument validation
- Specific business logic
- Data layer calls
- Response formatting

### 3. db/
- **connection.zig**: Connection pooling, safe open/close
- **schema.zig**: Structure creation/updates
- **queries.zig**: Parameterized SQL, injection prevention

### 4. models/
- Zig struct definitions
- Enums for states (TaskStatus, SprintStatus)
- JSON serialization/deserialization

### 5. utils/
- **json.zig**: Consistent JSON output wrapper
- **time.zig**: UTC conversion, ISO 8601 formatting
- **path.zig**: Cross-platform path resolution

## Command Lifecycle

```
1. CLI Input → Parse arguments
2. Validation → Verify syntax and values
3. Routing → Determine handler
4. Execution → Business logic + DB
5. Formatting → Structure result
6. Output → JSON to stdout
```

## Error Handling

### Error Categories

| Category | Example | Response |
|-----------|---------|----------|
| Invalid input | Missing parameter | JSON with descriptive error |
| Resource not found | Roadmap not found | JSON with descriptive error |
| Conflict | Duplicate name | JSON with error, no data changes |
| SQLite | Query error | JSON with error, rollback if needed |
| System | No permissions | JSON with descriptive error |

### Error Format

```json
{
  "success": false,
  "error": {
    "code": "ROADMAP_EXISTS",
    "message": "Roadmap 'project1' already exists"
  }
}
```

## Performance Considerations

1. **Lazy loading**: SQLite connections only opened when needed
2. **Prepared statements**: Pre-compiled SQLite queries
3. **Minimal allocations**: Use stack where possible
4. **Streams**: Use JSON streaming for large lists
