# Technical Specification - LRoadmap

## Overview

This directory contains the complete technical specification for LRoadmap - a CLI tool for managing technical roadmaps in agentic workflows.

## Specification Structure

| File | Description |
|------|-------------|
| [ARCHITECTURE.md](./ARCHITECTURE.md) | System architecture, file structure, and design philosophy |
| [COMMANDS.md](./COMMANDS.md) | CLI commands, subcommands, arguments, and options |
| [DATABASE.md](./DATABASE.md) | SQLite schema, tables, indexes, and relationships |
| [DATA_FORMATS.md](./DATA_FORMATS.md) | JSON output formats, ISO 8601 date conventions, and data types |
| [COMMANDS_REFERENCE.md](./COMMANDS_REFERENCE.md) | Complete command reference with examples |

## Technology Stack

- **Language**: Zig (exclusively)
- **Database**: SQLite (individual `.db` files)
- **Input**: CLI arguments and options only (no JSON, no stdin, no config files)
- **Output Format**: JSON (exclusively)
- **Dates**: ISO 8601 with UTC

## Design Principles

1. **Performance**: Fast execution, minimal overhead
2. **Resources**: Efficient usage, only what is necessary
3. **Security**: Strict validation, protection against invalid data
4. **Consistency**: Always JSON responses, always UTC dates

## Specification Versioning

- Current version: 1.0.0-draft
- Date: 2026-03-12
