const std = @import("std");
const Connection = @import("connection.zig").Connection;

/// Schema version
pub const SCHEMA_VERSION = "1.0.0";

/// Creates all database tables
pub fn createSchema(conn: Connection) !void {
    // Create tables in order
    try conn.exec(CREATE_TASKS_TABLE);
    try conn.exec(CREATE_SPRINTS_TABLE);
    try conn.exec(CREATE_SPRINT_TASKS_TABLE);
    try conn.exec(CREATE_AUDIT_TABLE);
    try conn.exec(CREATE_METADATA_TABLE);

    // Create indexes for performance
    try conn.exec(CREATE_INDEX_TASKS_STATUS);
    try conn.exec(CREATE_INDEX_TASKS_PRIORITY);
    try conn.exec(CREATE_INDEX_TASKS_CREATED_AT);
    try conn.exec(CREATE_INDEX_TASKS_DESCRIPTION);
    try conn.exec(CREATE_INDEX_TASKS_ACTION);
    try conn.exec(CREATE_INDEX_TASKS_EXPECTED_RESULT);
    try conn.exec(CREATE_INDEX_TASKS_SPECIALISTS);
    try conn.exec(CREATE_INDEX_SPRINTS_STATUS);
    try conn.exec(CREATE_INDEX_SPRINTS_CREATED_AT);
    try conn.exec(CREATE_INDEX_SPRINTS_DESCRIPTION);
    try conn.exec(CREATE_INDEX_SPRINT_TASKS_TASK_ID);
    try conn.exec(CREATE_INDEX_AUDIT_ENTITY);
    try conn.exec(CREATE_INDEX_AUDIT_OPERATION);
    try conn.exec(CREATE_INDEX_AUDIT_PERFORMED_AT);

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

/// Gets the schema version from the database
pub fn getSchemaVersion(conn: Connection, allocator: std.mem.Allocator) ![]const u8 {
    const c = @cImport({
        @cInclude("sqlite3.h");
    });

    const sql = "SELECT value FROM _metadata WHERE key = 'schema_version' LIMIT 1";
    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), sql.ptr, @intCast(sql.len), &stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    const step_rc = c.sqlite3_step(stmt);
    if (step_rc != c.SQLITE_ROW) return error.NotFound;

    const value = std.mem.span(c.sqlite3_column_text(stmt, 0));
    return allocator.dupe(u8, value);
}

/// Gets the application name from the database
pub fn getApplication(conn: Connection, allocator: std.mem.Allocator) ![]const u8 {
    const c = @cImport({
        @cInclude("sqlite3.h");
    });

    const sql = "SELECT value FROM _metadata WHERE key = 'application' LIMIT 1";
    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), sql.ptr, @intCast(sql.len), &stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    const step_rc = c.sqlite3_step(stmt);
    if (step_rc != c.SQLITE_ROW) return error.NotFound;

    const value = std.mem.span(c.sqlite3_column_text(stmt, 0));
    return allocator.dupe(u8, value);
}

/// DDL for tasks table
/// Uses COLLATE NOCASE for case-insensitive text comparison
pub const CREATE_TASKS_TABLE =
    \\CREATE TABLE IF NOT EXISTS tasks (
    \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
    \\    priority INTEGER NOT NULL DEFAULT 0 CHECK(priority >= 0 AND priority <= 9),
    \\    severity INTEGER NOT NULL DEFAULT 0 CHECK(severity >= 0 AND severity <= 9),
    \\    status TEXT NOT NULL DEFAULT 'BACKLOG' CHECK(status IN ('BACKLOG', 'SPRINT', 'DOING', 'TESTING', 'COMPLETED')),
    \\    description TEXT NOT NULL COLLATE NOCASE,
    \\    specialists TEXT COLLATE NOCASE,
    \\    action TEXT NOT NULL COLLATE NOCASE,
    \\    expected_result TEXT NOT NULL COLLATE NOCASE,
    \\    created_at TEXT NOT NULL,
    \\    completed_at TEXT
    \\)
;

/// DDL for sprints table
/// Uses COLLATE NOCASE for case-insensitive text comparison
pub const CREATE_SPRINTS_TABLE =
    \\CREATE TABLE IF NOT EXISTS sprints (
    \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
    \\    status TEXT NOT NULL DEFAULT 'PENDING' CHECK(status IN ('PENDING', 'OPEN', 'CLOSED')),
    \\    description TEXT NOT NULL COLLATE NOCASE,
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

/// Collation for case-insensitive and accent-insensitive comparison.
/// Requires the custom collation "NOCASE_AI" to be registered via connection.registerNoCaseAiCollation().
/// This is used for text fields that need both case and accent insensitivity.
pub const COLLATE_NOCASE_AI = "NOCASE_AI";

// ============== INDEXES ==============

/// Index for tasks status filtering
pub const CREATE_INDEX_TASKS_STATUS =
    \\CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status)
;

/// Index for tasks priority filtering
pub const CREATE_INDEX_TASKS_PRIORITY =
    \\CREATE INDEX IF NOT EXISTS idx_tasks_priority ON tasks(priority)
;

/// Index for tasks created_at date range queries
pub const CREATE_INDEX_TASKS_CREATED_AT =
    \\CREATE INDEX IF NOT EXISTS idx_tasks_created_at ON tasks(created_at)
;

/// Index for tasks description (case-insensitive search)
pub const CREATE_INDEX_TASKS_DESCRIPTION =
    \\CREATE INDEX IF NOT EXISTS idx_tasks_description ON tasks(description COLLATE NOCASE)
;

/// Index for tasks action (case-insensitive search)
pub const CREATE_INDEX_TASKS_ACTION =
    \\CREATE INDEX IF NOT EXISTS idx_tasks_action ON tasks(action COLLATE NOCASE)
;

/// Index for tasks expected_result (case-insensitive search)
pub const CREATE_INDEX_TASKS_EXPECTED_RESULT =
    \\CREATE INDEX IF NOT EXISTS idx_tasks_expected_result ON tasks(expected_result COLLATE NOCASE)
;

/// Index for tasks specialists (case-insensitive search)
pub const CREATE_INDEX_TASKS_SPECIALISTS =
    \\CREATE INDEX IF NOT EXISTS idx_tasks_specialists ON tasks(specialists COLLATE NOCASE)
    \\WHERE specialists IS NOT NULL
;

/// Index for sprints status filtering
pub const CREATE_INDEX_SPRINTS_STATUS =
    \\CREATE INDEX IF NOT EXISTS idx_sprints_status ON sprints(status)
;

/// Index for sprints created_at date range queries
pub const CREATE_INDEX_SPRINTS_CREATED_AT =
    \\CREATE INDEX IF NOT EXISTS idx_sprints_created_at ON sprints(created_at)
;

/// Index for sprints description (case-insensitive search)
pub const CREATE_INDEX_SPRINTS_DESCRIPTION =
    \\CREATE INDEX IF NOT EXISTS idx_sprints_description ON sprints(description COLLATE NOCASE)
;

/// Index for sprint_tasks task_id lookups
pub const CREATE_INDEX_SPRINT_TASKS_TASK_ID =
    \\CREATE INDEX IF NOT EXISTS idx_sprint_tasks_task_id ON sprint_tasks(task_id)
;

/// Index for audit entity lookups (entity_type, entity_id)
pub const CREATE_INDEX_AUDIT_ENTITY =
    \\CREATE INDEX IF NOT EXISTS idx_audit_entity ON audit(entity_type, entity_id)
;

/// Index for audit operation filtering
pub const CREATE_INDEX_AUDIT_OPERATION =
    \\CREATE INDEX IF NOT EXISTS idx_audit_operation ON audit(operation)
;

/// Index for audit performed_at date range queries
pub const CREATE_INDEX_AUDIT_PERFORMED_AT =
    \\CREATE INDEX IF NOT EXISTS idx_audit_performed_at ON audit(performed_at)
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
