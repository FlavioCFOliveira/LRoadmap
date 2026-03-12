const std = @import("std");
const Connection = @import("connection.zig").Connection;

/// Schema version
pub const SCHEMA_VERSION = "1.0.0";

/// Creates all database tables
pub fn createSchema(conn: Connection) !void {
    // Enable foreign keys
    try conn.exec("PRAGMA foreign_keys = ON");

    // Create tables in order
    try conn.exec(CREATE_TASKS_TABLE);
    try conn.exec(CREATE_SPRINTS_TABLE);
    try conn.exec(CREATE_SPRINT_TASKS_TABLE);
    try conn.exec(CREATE_AUDIT_TABLE);
    try conn.exec(CREATE_METADATA_TABLE);

    // Insert schema version
    try conn.exec(INSERT_SCHEMA_VERSION);
    try conn.exec(INSERT_APPLICATION);
}

/// Checks if schema exists by looking for _metadata table
pub fn schemaExists(conn: Connection) !bool {
    // This is a simple check - just try to select from _metadata
    conn.exec("SELECT 1 FROM _metadata LIMIT 1") catch return false;
    return true;
}

// ============== DDL STATEMENTS ==============

/// DDL for tasks table
pub const CREATE_TASKS_TABLE =
    \\CREATE TABLE IF NOT EXISTS tasks (
    \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
    \\    priority INTEGER NOT NULL DEFAULT 0 CHECK(priority >= 0 AND priority <= 9),
    \\    severity INTEGER NOT NULL DEFAULT 0 CHECK(severity >= 0 AND severity <= 9),
    \\    status TEXT NOT NULL DEFAULT 'BACKLOG' CHECK(status IN ('BACKLOG', 'SPRINT', 'DOING', 'TESTING', 'COMPLETED')),
    \\    description TEXT NOT NULL,
    \\    specialists TEXT,
    \\    action TEXT NOT NULL,
    \\    expected_result TEXT NOT NULL,
    \\    created_at TEXT NOT NULL,
    \\    completed_at TEXT
    \\)
;

/// DDL for sprints table
pub const CREATE_SPRINTS_TABLE =
    \\CREATE TABLE IF NOT EXISTS sprints (
    \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
    \\    status TEXT NOT NULL DEFAULT 'PENDING' CHECK(status IN ('PENDING', 'OPEN', 'CLOSED')),
    \\    description TEXT NOT NULL,
    \\    created_at TEXT NOT NULL,
    \\    started_at TEXT,
    \\    closed_at TEXT
    \\)
;

/// DDL for sprint_tasks junction table
pub const CREATE_SPRINT_TASKS_TABLE =
    \\CREATE TABLE IF NOT EXISTS sprint_tasks (
    \\    sprint_id INTEGER NOT NULL,
    \\    task_id INTEGER NOT NULL,
    \\    added_at TEXT NOT NULL,
    \\    PRIMARY KEY (sprint_id, task_id),
    \\    FOREIGN KEY (sprint_id) REFERENCES sprints(id) ON DELETE CASCADE,
    \\    FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE
    \\)
;

/// DDL for audit table
pub const CREATE_AUDIT_TABLE =
    \\CREATE TABLE IF NOT EXISTS audit (
    \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
    \\    operation TEXT NOT NULL,
    \\    entity_type TEXT NOT NULL,
    \\    entity_id INTEGER NOT NULL,
    \\    performed_at TEXT NOT NULL
    \\)
;

/// DDL for _metadata table
pub const CREATE_METADATA_TABLE =
    \\CREATE TABLE IF NOT EXISTS _metadata (
    \\    key TEXT PRIMARY KEY,
    \\    value TEXT NOT NULL
    \\)
;

/// Insert schema version
pub const INSERT_SCHEMA_VERSION =
    \\INSERT OR REPLACE INTO _metadata (key, value) VALUES ('schema_version', '1.0.0')
;

/// Insert application name
pub const INSERT_APPLICATION =
    \\INSERT OR REPLACE INTO _metadata (key, value) VALUES ('application', 'LRoadmap')
;

// ============== TESTS ==============

test "createSchema creates all tables" {
    const allocator = std.testing.allocator;

    const test_db = "/tmp/test_schema.db";
    std.fs.cwd().deleteFile(test_db) catch {};

    var conn = try Connection.open(allocator, test_db);
    defer conn.close(allocator);

    // Create schema
    try createSchema(conn);

    // Clean up
    std.fs.cwd().deleteFile(test_db) catch {};
}

test "schemaExists" {
    const allocator = std.testing.allocator;

    const test_db = "/tmp/test_schema2.db";
    std.fs.cwd().deleteFile(test_db) catch {};

    var conn = try Connection.open(allocator, test_db);
    defer conn.close(allocator);

    // Before creating schema
    const exists_before = try schemaExists(conn);
    try std.testing.expect(!exists_before);

    // Create schema
    try createSchema(conn);

    // After creating schema
    const exists_after = try schemaExists(conn);
    try std.testing.expect(exists_after);

    // Clean up
    std.fs.cwd().deleteFile(test_db) catch {};
}
