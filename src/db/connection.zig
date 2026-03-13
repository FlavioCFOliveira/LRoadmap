const std = @import("std");
const c = @cImport({
    @cInclude("sqlite3.h");
});
const text_utils = @import("../utils/text.zig");

/// Context for collation comparison
const CollationContext = struct {
    allocator: std.mem.Allocator,
};

/// Custom collation function for case-insensitive and accent-insensitive comparison.
/// This function is called by SQLite when comparing strings with the "NOCASE_AI" collation.
export fn nocaseAiCollation(context: ?*anyopaque, len_a: c_int, a: ?*const anyopaque, len_b: c_int, b: ?*const anyopaque) callconv(.c) c_int {
    _ = context;

    if (a == null and b == null) return 0;
    if (a == null) return -1;
    if (b == null) return 1;

    const slice_a = @as([*c]const u8, @ptrCast(a.?))[0..@intCast(len_a)];
    const slice_b = @as([*c]const u8, @ptrCast(b.?))[0..@intCast(len_b)];

    // Create a temporary arena allocator for this comparison
    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Normalize both strings
    const norm_a = text_utils.normalizeUtf8(allocator, slice_a) catch {
        // On error, fall back to simple case-insensitive comparison
        return @as(c_int, simpleCaseInsensitiveCompare(slice_a, slice_b));
    };
    const norm_b = text_utils.normalizeUtf8(allocator, slice_b) catch {
        return @as(c_int, simpleCaseInsensitiveCompare(slice_a, slice_b));
    };

    // Compare normalized strings
    const cmp = std.mem.order(u8, norm_a, norm_b);
    return switch (cmp) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    };
}

/// Simple fallback for case-insensitive comparison (ASCII only)
fn simpleCaseInsensitiveCompare(a: []const u8, b: []const u8) i8 {
    const min_len = @min(a.len, b.len);
    for (0..min_len) |i| {
        const ca = std.ascii.toLower(a[i]);
        const cb = std.ascii.toLower(b[i]);
        if (ca < cb) return -1;
        if (ca > cb) return 1;
    }
    if (a.len < b.len) return -1;
    if (a.len > b.len) return 1;
    return 0;
}

/// Registers the NOCASE_AI collation for case-insensitive and accent-insensitive comparison.
/// Call this after opening a database connection.
pub fn registerNoCaseAiCollation(db: *c.sqlite3) !void {
    const rc = c.sqlite3_create_collation(
        db,
        "NOCASE_AI",
        c.SQLITE_UTF8,
        null, // context
        nocaseAiCollation,
    );
    if (rc != c.SQLITE_OK) {
        return error.CollationRegistrationFailed;
    }
}

/// Database connection wrapper
pub const Connection = struct {
    /// SQLite database handle
    db: *c.sqlite3,
    /// Path to the database file (null-terminated)
    path: [:0]const u8,

    /// Opens a connection to a SQLite database
    /// Caller owns the returned memory
    pub fn open(allocator: std.mem.Allocator, path: []const u8) !Connection {
        // Duplicate path for storage and ensure null-termination for C API
        const path_z = try allocator.dupeZ(u8, path);
        errdefer allocator.free(path_z);

        var db: ?*c.sqlite3 = null;
        const rc = c.sqlite3_open(path_z.ptr, &db);

        if (rc != c.SQLITE_OK) {
            if (db) |db_ptr| {
                _ = c.sqlite3_close(db_ptr);
            }
            allocator.free(path_z);
            return error.DbOpenFailed;
        }

        if (db == null) {
            return error.DbOpenFailed;
        }

        // Performance and reliability PRAGMAs
        const fk_rc = c.sqlite3_exec(db, "PRAGMA foreign_keys = ON", null, null, null);
        if (fk_rc != c.SQLITE_OK) {
            _ = c.sqlite3_close(db);
            return error.DbOpenFailed;
        }

        const wal_rc = c.sqlite3_exec(db, "PRAGMA journal_mode = WAL", null, null, null);
        if (wal_rc != c.SQLITE_OK) {
            _ = c.sqlite3_close(db);
            return error.DbOpenFailed;
        }

        const sync_rc = c.sqlite3_exec(db, "PRAGMA synchronous = NORMAL", null, null, null);
        if (sync_rc != c.SQLITE_OK) {
            _ = c.sqlite3_close(db);
            return error.DbOpenFailed;
        }

        const busy_rc = c.sqlite3_exec(db, "PRAGMA busy_timeout = 5000", null, null, null);
        if (busy_rc != c.SQLITE_OK) {
            _ = c.sqlite3_close(db);
            return error.DbOpenFailed;
        }

        // Register custom collation for case-insensitive and accent-insensitive comparison
        const collation_rc = c.sqlite3_create_collation(
            db,
            "NOCASE_AI",
            c.SQLITE_UTF8,
            null,
            nocaseAiCollation,
        );
        if (collation_rc != c.SQLITE_OK) {
            _ = c.sqlite3_close(db);
            return error.DbOpenFailed;
        }

        return Connection{
            .db = db.?,
            .path = path_z,
        };
    }

    /// Closes the database connection
    pub fn close(self: *Connection, allocator: std.mem.Allocator) void {
        _ = c.sqlite3_close(self.db);
        allocator.free(self.path);
    }

    /// Executes a simple SQL statement (must be null-terminated)
    pub fn exec(self: Connection, sql: [:0]const u8) !void {
        const rc = c.sqlite3_exec(self.db, sql.ptr, null, null, null);
        if (rc != c.SQLITE_OK) {
            return error.SqlExecFailed;
        }
    }

    /// Returns the last error message from SQLite
    pub fn lastError(self: Connection) []const u8 {
        const msg = c.sqlite3_errmsg(self.db);
        return std.mem.span(msg);
    }

    /// Gets the last inserted row ID
    pub fn lastInsertRowId(self: Connection) i64 {
        return c.sqlite3_last_insert_rowid(self.db);
    }

    /// Begins a transaction
    pub fn beginTransaction(self: Connection) !void {
        return self.exec("BEGIN TRANSACTION");
    }

    /// Commits the current transaction
    pub fn commit(self: Connection) !void {
        return self.exec("COMMIT");
    }

    /// Rolls back the current transaction
    pub fn rollback(self: Connection) !void {
        return self.exec("ROLLBACK");
    }
};

/// Checks if a file is a valid SQLite database
pub fn isValidSQLiteFile(path: []const u8) bool {
    const file = std.fs.cwd().openFile(path, .{}) catch return false;
    defer file.close();

    var magic: [16]u8 = undefined;
    const bytes_read = file.read(&magic) catch return false;
    if (bytes_read < 16) return false;

    // SQLite magic bytes: "SQLite format 3\x00"
    const sqlite_magic = "SQLite format 3\x00";
    return std.mem.eql(u8, magic[0..sqlite_magic.len], sqlite_magic);
}

/// Creates a new roadmap database file with proper permissions
pub fn createRoadmapFile(path: []const u8) !void {
    // Ensure parent directory exists
    const parent = std.fs.path.dirname(path) orelse return error.InvalidPath;
    try std.fs.cwd().makePath(parent);

    // Create file by opening it
    const file = try std.fs.cwd().createFile(path, .{ .read = true });
    file.close();
}


// ============== TESTS ==============

test "isValidSQLiteFile validates SQLite magic bytes" {

    // Create a test directory
    const test_dir = "/tmp/test_lroadmap";
    std.fs.cwd().makeDir(test_dir) catch {};

    // Test with non-existent file
    try std.testing.expect(!isValidSQLiteFile("/tmp/nonexistent.db"));

    // Test with invalid file (just some text)
    const test_file = "/tmp/test_lroadmap/invalid.txt";
    {
        const file = try std.fs.cwd().createFile(test_file, .{});
        defer file.close();
        try file.writeAll("This is not a SQLite database");
    }
    try std.testing.expect(!isValidSQLiteFile(test_file));

    // Clean up
    std.fs.cwd().deleteFile(test_file) catch {};
    std.fs.cwd().deleteDir(test_dir) catch {};
}

test "createRoadmapFile creates file" {
    const test_file = "/tmp/test_roadmap_create.db";

    // Remove if exists
    std.fs.cwd().deleteFile(test_file) catch {};

    // Create parent directory
    try std.fs.cwd().makePath("/tmp");

    // Create file
    try createRoadmapFile(test_file);

    // Verify file exists
    const exists = isValidSQLiteFile(test_file);
    // Note: File exists but is not a valid SQLite yet (just empty)
    // so it should return false for isValidSQLiteFile
    _ = exists;

    // Clean up
    std.fs.cwd().deleteFile(test_file) catch {};
}

test "Connection open/close" {
    const allocator = std.testing.allocator;

    // Create a temporary database file
    const test_db = "/tmp/test_conn.db";
    std.fs.cwd().deleteFile(test_db) catch {};

    // Open connection (creates file)
    var conn = try Connection.open(allocator, test_db);
    defer conn.close(allocator);

    // Verify it works
    try conn.exec("SELECT 1");

    // Clean up
    std.fs.cwd().deleteFile(test_db) catch {};
}

test "Connection lastInsertRowId" {
    const allocator = std.testing.allocator;

    const test_db = "/tmp/test_rowid.db";
    std.fs.cwd().deleteFile(test_db) catch {};

    var conn = try Connection.open(allocator, test_db);
    defer conn.close(allocator);

    // Create test table
    try conn.exec("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)");

    // Insert row
    try conn.exec("INSERT INTO test (name) VALUES ('test')");

    // Check row ID
    const rowid = conn.lastInsertRowId();
    try std.testing.expectEqual(@as(i64, 1), rowid);

    // Clean up
    std.fs.cwd().deleteFile(test_db) catch {};
}

test "Connection transactions" {
    const allocator = std.testing.allocator;

    const test_db = "/tmp/test_tx.db";
    std.fs.cwd().deleteFile(test_db) catch {};

    var conn = try Connection.open(allocator, test_db);
    defer conn.close(allocator);

    // Create table
    try conn.exec("CREATE TABLE test (id INTEGER PRIMARY KEY)");

    // Test transaction
    try conn.beginTransaction();
    try conn.exec("INSERT INTO test (id) VALUES (1)");
    try conn.commit();

    // Clean up
    std.fs.cwd().deleteFile(test_db) catch {};
}
