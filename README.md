# LRoadmap

Local Roadmap Manager CLI for agentic workflows.

## Overview

LRoadmap is a command-line interface (CLI) application for managing technical roadmaps, tasks, and sprints. Designed for agentic workflows, it provides structured project management through a simple, fast, and resource-efficient interface.

## Key Features

- **Local-First**: All data stored in individual SQLite files
- **JSON Output**: All responses structured in JSON format
- **Unix Conventions**: Follows standard CLI patterns
- **Bulk Operations**: Support for multiple records in single commands
- **Complete Audit**: Full history of all operations
- **Agentic Workflow Support**: Claude Code skill for orchestrated sprint management ([SKILL.md](SKILL.md))

## Quick Start

```bash
# List roadmaps
rmp roadmap list

# Create a roadmap
rmp roadmap new project1

# Create a task
rmp task new -r project1 -d "Implement auth" -a "Create JWT" -e "Login works"

# List tasks
rmp task ls -r project1

# Change task status
rmp task stat -r project1 1 DOING

# Create sprint
rmp sprint new -r project1 -d "Sprint 1"

# Add tasks to sprint
rmp sprint add -r project1 1 1,2,3
```

## Technology Stack

- **Language**: [Zig](https://ziglang.org/) - exclusively
- **Database**: SQLite (individual `.db` files)
- **Input**: CLI arguments only (no JSON, no stdin, no config files)
- **Output**: JSON exclusively
- **Dates**: ISO 8601 with UTC

## Installation

### Build and Install

```bash
# Clone repository
git clone https://github.com/yourusername/LRoadmap.git
cd LRoadmap

# Build with Zig
zig build

# Install binary
zig build install
```

### Install Locations

The `zig build install` command places the `rmp` binary in different locations depending on your operating system:

#### Linux

Standard installation paths:
- **System-wide**: `/usr/local/bin/rmp` (recommended for all users)
- **User-local**: `~/.local/bin/rmp` (recommended for single user)
- **Zig default**: `zig-out/bin/rmp` (relative to project directory)

To install system-wide:
```bash
sudo cp zig-out/bin/rmp /usr/local/bin/
sudo chmod +x /usr/local/bin/rmp
```

To install user-local:
```bash
mkdir -p ~/.local/bin
cp zig-out/bin/rmp ~/.local/bin/
# Add to PATH if not already present
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

#### macOS

Standard installation paths:
- **System-wide**: `/usr/local/bin/rmp` (Intel Macs)
- **Apple Silicon**: `/opt/homebrew/bin/rmp` (recommended for M1/M2/M3)
- **User-local**: `~/.local/bin/rmp` or `~/bin/rmp`

Using Homebrew (recommended):
```bash
# After building
cp zig-out/bin/rmp /opt/homebrew/bin/  # Apple Silicon
# or
cp zig-out/bin/rmp /usr/local/bin/      # Intel Macs
```

Manual installation:
```bash
mkdir -p ~/bin
cp zig-out/bin/rmp ~/bin/
# Add to PATH
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

#### Windows

Standard installation paths:
- **System-wide**: `C:\Program Files\LRoadmap\rmp.exe`
- **User-local**: `%LOCALAPPDATA%\Programs\LRoadmap\rmp.exe`
- **Zig default**: `zig-out\bin\rmp.exe` (relative to project directory)

Manual installation (PowerShell):
```powershell
# Create directory
New-Item -ItemType Directory -Force -Path "$env:LOCALAPPDATA\Programs\LRoadmap"

# Copy binary
Copy-Item "zig-out\bin\rmp.exe" "$env:LOCALAPPDATA\Programs\LRoadmap\"

# Add to PATH (current session)
$env:PATH += ";$env:LOCALAPPDATA\Programs\LRoadmap"

# Add to PATH (permanent)
[Environment]::SetEnvironmentVariable("Path", $env:PATH + ";$env:LOCALAPPDATA\Programs\LRoadmap", "User")
```

### Verify Installation

After installation, verify the binary is accessible:

```bash
# Check if rmp is in PATH
which rmp      # Linux/macOS
where rmp      # Windows

# Verify version
rmp --version
```

### Uninstall

To remove the installed binary:

**Linux/macOS:**
```bash
rm /usr/local/bin/rmp        # System-wide
rm ~/.local/bin/rmp          # User-local
```

**Windows (PowerShell):**
```powershell
Remove-Item "$env:LOCALAPPDATA\Programs\LRoadmap\rmp.exe"
```

## Claude Code Skill

LRoadmap includes a dedicated skill for Claude Code that enables agentic workflows for task and sprint management.

### Features

- **Sprint Orchestration**: Claude acts as a sprint coordinator managing task lifecycles
- **Structured Task Creation**: Enforces best practices for task definition
- **Automated State Management**: Handles task transitions with validation
- **Progress Monitoring**: Real-time sprint statistics and reporting
- **Bulk Operations**: Efficient multi-task commands

### Quick Start with Skill

```bash
# In Claude Code, invoke the skill with /roadmap

# Create and manage sprints
"/roadmap Create a new sprint for the API authentication features"
"/roadmap Start sprint 1 and add the backlog tasks to it"

# Manage tasks
"/roadmap Create a high-priority task for implementing JWT middleware"
"/roadmap Mark tasks 1,2,3 as DOING"
"/roadmap Show me the sprint progress"

# Analyze progress
"/roadmap Show sprint statistics"
"/roadmap List all completed tasks"
```

See [SKILL.md](SKILL.md) for complete documentation including:
- Workflow patterns
- Command reference
- Usage examples
- Integration guides

## Specification

Complete technical specification available in the [`SPEC/`](SPEC/) directory:

| Document | Description |
|----------|-------------|
| [SPEC/README.md](SPEC/README.md) | Specification overview and structure |
| [SPEC/ARCHITECTURE.md](SPEC/ARCHITECTURE.md) | System architecture and design principles |
| [SPEC/COMMANDS.md](SPEC/COMMANDS.md) | Complete CLI commands reference |
| [SPEC/COMMANDS_REFERENCE.md](SPEC/COMMANDS_REFERENCE.md) | Quick command reference with examples |
| [SPEC/DATABASE.md](SPEC/DATABASE.md) | SQLite schema and SQL queries |
| [SPEC/DATA_FORMATS.md](SPEC/DATA_FORMATS.md) | JSON output formats and data types |
| [SKILL.md](SKILL.md) | Claude Code skill for agentic workflows |

## Design Principles

1. **Performance**: Fast execution with minimal overhead
2. **Resources**: Efficient usage, only what is necessary
3. **Security**: Strict validation, protection against invalid data
4. **Consistency**: Always JSON responses, always UTC dates

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

### Unix Conventions

| Convention | Command | Usage |
|------------|---------|-------|
| `ls` | list | All groups |
| `new` | create | All groups |
| `rm` | remove | All groups (per Unix semantics) |
| `get` | retrieve | Task/sprint retrieval |
| `stat` | status | Change status |
| `prio` | priority | Change priority |
| `sev` | severity | Change severity |

## Data Storage

Roadmaps are stored in `~/.roadmaps/`:

```
~/.roadmaps/
├── project1.db
├── project2.db
└── ...
```

Each `.db` file is an independent SQLite database.

## Example Workflow

```bash
# 1. Create roadmap
rmp road new myproject

# 2. Create tasks
rmp task new -r myproject -d "Setup CI/CD" -a "Configure GitHub Actions" -e "Pipeline green" --priority 9
rmp task new -r myproject -d "Implement API" -a "Create REST endpoints" -e "API responds" --priority 8

# 3. Create sprint
rmp sprint new -r myproject -d "Sprint 1 - Foundation"

# 4. Add tasks to sprint
rmp sprint add -r myproject 1 1,2

# 5. Start sprint
rmp sprint start -r myproject 1

# 6. Work on tasks
rmp task stat -r myproject 1 DOING
rmp task stat -r myproject 1 TESTING
rmp task stat -r myproject 1 COMPLETED

# 7. Sprint statistics
rmp sprint stats -r myproject 1

# 8. Close sprint
rmp sprint close -r myproject 1
```

## Agentic Workflow with Claude Code

LRoadmap includes a Claude Code skill for orchestrated task and sprint management. The skill enables Claude to act as a sprint coordinator, managing complete workflows from backlog to completion.

### Quick Start with Claude

```bash
# In Claude Code, invoke the skill with /roadmap

"/roadmap Create a new sprint for the authentication feature"
"/roadmap Show me the current sprint progress"
"/roadmap Move task 5 to testing status"
"/roadmap Generate a sprint completion report"
```

### Installation for Agentic Workflows

1. **Install LRoadmap** (see Installation section above)

2. **The skill is automatically available** when working in this repository via `CLAUDE.md`

3. **For detailed skill documentation**, see [SKILL.md](SKILL.md)

### What the Skill Enables

- **Orchestrated Sprint Management**: Complete sprint lifecycle from creation to closure
- **Structured Task Creation**: Enforces best practices (description, action, expected result)
- **Automated State Transitions**: Validates and executes status changes with full audit trail
- **Progress Monitoring**: Real-time statistics and backlog analysis
- **Bulk Operations**: Efficient multi-task management

See [SKILL.md](SKILL.md) for complete workflow patterns and examples.

## Bulk Operations

Most operations support multiple IDs:

```bash
# Get multiple tasks
rmp task get -r myproject 1,2,3,10

# Change status of multiple tasks
rmp task stat -r myproject 1,2,3 DOING

# Change priority in bulk
rmp task prio -r myproject 5,6,7 9

# Remove multiple tasks
rmp task rm -r myproject 10,11,12
```

## Output Format

All responses are JSON:

```json
{
  "success": true,
  "data": {
    "id": 1,
    "priority": 9,
    "severity": 3,
    "status": "DOING",
    "description": "Implement auth",
    "action": "Create JWT",
    "expected_result": "Login works",
    "created_at": "2026-03-12T15:00:00.000Z",
    "completed_at": null
  }
}
```

Errors:

```json
{
  "success": false,
  "error": {
    "code": "TASK_NOT_FOUND",
    "message": "Task(s) with ID(s) [99] not found"
  }
}
```

## License

MIT License - see LICENSE file for details.

## Contributing

Contributions welcome. Please read [SPEC/ARCHITECTURE.md](SPEC/ARCHITECTURE.md) for design principles before submitting changes.

---

**Version**: 1.0.0-draft
**Last Updated**: 2026-03-12
