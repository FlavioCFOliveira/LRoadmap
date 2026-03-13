const std = @import("std");
const c = @cImport({
    @cInclude("sqlite3.h");
});
const Connection = @import("connection.zig").Connection;
const Task = @import("../models/task.zig").Task;
const TaskStatus = @import("../models/task.zig").TaskStatus;
const Sprint = @import("../models/sprint.zig").Sprint;
const SprintStatus = @import("../models/sprint.zig").SprintStatus;
const AuditEntry = @import("../models/audit.zig").AuditEntry;
const AuditStats = @import("../models/audit.zig").AuditStats;

// ============== BIND HELPER FUNCTIONS ==============

fn bindInt(stmt: ?*c.sqlite3_stmt, idx: c_int, value: c_int) !void {
    const rc = c.sqlite3_bind_int(stmt, idx, value);
    if (rc != c.SQLITE_OK) return error.BindFailed;
}

fn bindInt64(stmt: ?*c.sqlite3_stmt, idx: c_int, value: i64) !void {
    const rc = c.sqlite3_bind_int64(stmt, idx, value);
    if (rc != c.SQLITE_OK) return error.BindFailed;
}

fn bindText(stmt: ?*c.sqlite3_stmt, idx: c_int, text: []const u8) !void {
    const rc = c.sqlite3_bind_text(stmt, idx, text.ptr, @intCast(text.len), c.SQLITE_STATIC);
    if (rc != c.SQLITE_OK) return error.BindFailed;
}

fn bindNull(stmt: ?*c.sqlite3_stmt, idx: c_int) !void {
    const rc = c.sqlite3_bind_null(stmt, idx);
    if (rc != c.SQLITE_OK) return error.BindFailed;
}

// ============== TASK QUERIES ==============

pub fn insertTask(conn: Connection, task: Task) !i64 {
    const sql = "INSERT INTO tasks (priority, severity, description, specialists, action, expected_result, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)";

    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), sql.ptr, @intCast(sql.len), &stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    try bindInt(stmt, 1, task.priority);
    try bindInt(stmt, 2, task.severity);
    try bindText(stmt, 3, task.description);

    if (task.specialists) |s| {
        try bindText(stmt, 4, s);
    } else {
        try bindNull(stmt, 4);
    }

    try bindText(stmt, 5, task.action);
    try bindText(stmt, 6, task.expected_result);
    try bindText(stmt, 7, task.created_at);

    const step_rc = c.sqlite3_step(stmt);
    if (step_rc != c.SQLITE_DONE) return error.StepFailed;

    return conn.lastInsertRowId();
}

pub fn updateTaskStatus(conn: Connection, id: i64, new_status: TaskStatus) !void {
    const status_str = new_status.toString();
    const sql = "UPDATE tasks SET status = ? WHERE id = ?";
    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), sql.ptr, @intCast(sql.len), &stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    try bindText(stmt, 1, status_str);
    try bindInt64(stmt, 2, id);

    const step_rc = c.sqlite3_step(stmt);
    if (step_rc != c.SQLITE_DONE) return error.StepFailed;
}

pub fn updateTaskPriority(conn: Connection, id: i64, priority: i32) !void {
    const sql = "UPDATE tasks SET priority = ? WHERE id = ?";
    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), sql.ptr, @intCast(sql.len), &stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    try bindInt(stmt, 1, priority);
    try bindInt64(stmt, 2, id);

    const step_rc = c.sqlite3_step(stmt);
    if (step_rc != c.SQLITE_DONE) return error.StepFailed;
}

pub fn updateTaskSeverity(conn: Connection, id: i64, severity: i32) !void {
    const sql = "UPDATE tasks SET severity = ? WHERE id = ?";
    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), sql.ptr, @intCast(sql.len), &stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    try bindInt(stmt, 1, severity);
    try bindInt64(stmt, 2, id);

    const step_rc = c.sqlite3_step(stmt);
    if (step_rc != c.SQLITE_DONE) return error.StepFailed;
}

pub fn updateTaskCompletedAt(conn: Connection, id: i64, completed_at: ?[]const u8) !void {
    const sql = "UPDATE tasks SET completed_at = ? WHERE id = ?";
    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), sql.ptr, @intCast(sql.len), &stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    if (completed_at) |ca| {
        try bindText(stmt, 1, ca);
    } else {
        try bindNull(stmt, 1);
    }
    try bindInt64(stmt, 2, id);

    const step_rc = c.sqlite3_step(stmt);
    if (step_rc != c.SQLITE_DONE) return error.StepFailed;
}

pub fn getTaskById(allocator: std.mem.Allocator, conn: Connection, id: i64) !Task {
    const sql = "SELECT id, priority, severity, status, description, specialists, action, expected_result, created_at, completed_at FROM tasks WHERE id = ?";
    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), sql.ptr, @intCast(sql.len), &stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    _ = c.sqlite3_bind_int64(stmt, 1, id);

    if (c.sqlite3_step(stmt) != c.SQLITE_ROW) return error.TaskNotFound;

    return rowToTask(allocator, stmt.?);
}

pub fn getTasksByIds(allocator: std.mem.Allocator, conn: Connection, ids: []const i64) ![]Task {
    if (ids.len == 0) return &[_]Task{};

    var list: std.ArrayListUnmanaged(Task) = .empty;
    errdefer {
        for (list.items) |*t| t.deinit(allocator);
        list.deinit(allocator);
    }

    for (ids) |id| {
        if (getTaskById(allocator, conn, id)) |task| {
            try list.append(allocator, task);
        } else |err| {
            if (err == error.TaskNotFound) continue;
            return err;
        }
    }

    return list.toOwnedSlice(allocator);
}

/// Filter options for listing tasks
pub const TaskFilterOptions = struct {
    status: ?TaskStatus = null,
    priority_min: ?i32 = null,
    severity_min: ?i32 = null,
    limit: ?i32 = null,
};

pub fn listTasks(allocator: std.mem.Allocator, conn: Connection, filters: TaskFilterOptions) ![]Task {
    const sql_base: []const u8 = "SELECT id, priority, severity, status, description, specialists, action, expected_result, created_at, completed_at FROM tasks";
    const order_clause = " ORDER BY priority DESC, created_at ASC";

    // Build WHERE clause dynamically
    var where_parts: std.ArrayListUnmanaged([]const u8) = .empty;
    defer where_parts.deinit(allocator);

    if (filters.status != null) try where_parts.append(allocator, "status = ?");
    if (filters.priority_min != null) try where_parts.append(allocator, "priority >= ?");
    if (filters.severity_min != null) try where_parts.append(allocator, "severity >= ?");

    var full_sql: []const u8 = undefined;
    if (where_parts.items.len > 0) {
        const where_clause = try std.mem.join(allocator, " AND ", where_parts.items);
        defer allocator.free(where_clause);
        if (filters.limit != null) {
            full_sql = try std.fmt.allocPrint(allocator, "{s} WHERE {s}{s} LIMIT {d}", .{ sql_base, where_clause, order_clause, filters.limit.? });
        } else {
            full_sql = try std.fmt.allocPrint(allocator, "{s} WHERE {s}{s}", .{ sql_base, where_clause, order_clause });
        }
    } else {
        if (filters.limit != null) {
            full_sql = try std.fmt.allocPrint(allocator, "{s}{s} LIMIT {d}", .{ sql_base, order_clause, filters.limit.? });
        } else {
            full_sql = try std.mem.concat(allocator, u8, &[_][]const u8{ sql_base, order_clause });
        }
    }
    defer allocator.free(full_sql);

    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), full_sql.ptr, @intCast(full_sql.len), &stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    // Bind parameters
    var bind_idx: c_int = 1;
    if (filters.status) |s| {
        const s_str = s.toString();
        _ = c.sqlite3_bind_text(stmt, bind_idx, s_str.ptr, @intCast(s_str.len), c.SQLITE_STATIC);
        bind_idx += 1;
    }
    if (filters.priority_min) |p| {
        _ = c.sqlite3_bind_int(stmt, bind_idx, p);
        bind_idx += 1;
    }
    if (filters.severity_min) |s| {
        _ = c.sqlite3_bind_int(stmt, bind_idx, s);
        bind_idx += 1;
    }

    var list: std.ArrayListUnmanaged(Task) = .empty;
    errdefer {
        for (list.items) |*t| t.deinit(allocator);
        list.deinit(allocator);
    }

    while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
        try list.append(allocator, try rowToTask(allocator, stmt.?));
    }

    return list.toOwnedSlice(allocator);
}

fn rowToTask(allocator: std.mem.Allocator, stmt: *c.sqlite3_stmt) !Task {
    const id = c.sqlite3_column_int64(stmt, 0);
    const priority = c.sqlite3_column_int(stmt, 1);
    const severity = c.sqlite3_column_int(stmt, 2);
    const status_str = std.mem.span(c.sqlite3_column_text(stmt, 3));
    const description = std.mem.span(c.sqlite3_column_text(stmt, 4));
    const specialists_ptr = c.sqlite3_column_text(stmt, 5);
    const action = std.mem.span(c.sqlite3_column_text(stmt, 6));
    const expected_result = std.mem.span(c.sqlite3_column_text(stmt, 7));
    const created_at = std.mem.span(c.sqlite3_column_text(stmt, 8));
    const completed_at_ptr = c.sqlite3_column_text(stmt, 9);

    return Task{
        .id = id,
        .priority = priority,
        .severity = severity,
        .status = try TaskStatus.fromString(status_str),
        .description = try allocator.dupe(u8, description),
        .specialists = if (specialists_ptr) |p| try allocator.dupe(u8, std.mem.span(p)) else null,
        .action = try allocator.dupe(u8, action),
        .expected_result = try allocator.dupe(u8, expected_result),
        .created_at = try allocator.dupe(u8, created_at),
        .completed_at = if (completed_at_ptr) |p| try allocator.dupe(u8, std.mem.span(p)) else null,
    };
}

pub fn updateTask(allocator: std.mem.Allocator, conn: Connection, id: i64, updates: Task.TaskUpdate) !void {
    var parts: std.ArrayListUnmanaged([]const u8) = .empty;
    defer parts.deinit(allocator);

    if (updates.priority) |_| try parts.append(allocator, "priority = ?");
    if (updates.severity) |_| try parts.append(allocator, "severity = ?");
    if (updates.description) |_| try parts.append(allocator, "description = ?");
    if (updates.specialists) |_| try parts.append(allocator, "specialists = ?");
    if (updates.action) |_| try parts.append(allocator, "action = ?");
    if (updates.expected_result) |_| try parts.append(allocator, "expected_result = ?");

    if (parts.items.len == 0) return;

    const set_clause = try std.mem.join(allocator, ", ", parts.items);
    defer allocator.free(set_clause);

    const sql = try std.fmt.allocPrint(allocator, "UPDATE tasks SET {s} WHERE id = ?", .{set_clause});
    defer allocator.free(sql);

    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), sql.ptr, @intCast(sql.len), &stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    var idx: c_int = 1;
    if (updates.priority) |p| {
        _ = c.sqlite3_bind_int(stmt, idx, p);
        idx += 1;
    }
    if (updates.severity) |s| {
        _ = c.sqlite3_bind_int(stmt, idx, s);
        idx += 1;
    }
    if (updates.description) |d| {
        _ = c.sqlite3_bind_text(stmt, idx, d.ptr, @intCast(d.len), c.SQLITE_STATIC);
        idx += 1;
    }
    if (updates.specialists) |s| {
        _ = c.sqlite3_bind_text(stmt, idx, s.ptr, @intCast(s.len), c.SQLITE_STATIC);
        idx += 1;
    }
    if (updates.action) |a| {
        _ = c.sqlite3_bind_text(stmt, idx, a.ptr, @intCast(a.len), c.SQLITE_STATIC);
        idx += 1;
    }
    if (updates.expected_result) |e| {
        _ = c.sqlite3_bind_text(stmt, idx, e.ptr, @intCast(e.len), c.SQLITE_STATIC);
        idx += 1;
    }

    _ = c.sqlite3_bind_int64(stmt, idx, id);

    if (c.sqlite3_step(stmt) != c.SQLITE_DONE) return error.StepFailed;
}

pub fn deleteTask(conn: Connection, id: i64) !void {
    const sql = "DELETE FROM tasks WHERE id = ?";
    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), sql.ptr, @intCast(sql.len), &stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    _ = c.sqlite3_bind_int64(stmt, 1, id);

    const step_rc = c.sqlite3_step(stmt);
    if (step_rc != c.SQLITE_DONE) return error.StepFailed;
}

// ============== BULK TASK QUERIES ==============

/// Check which task IDs exist in the database
pub fn filterExistingTaskIds(allocator: std.mem.Allocator, conn: Connection, ids: []const i64) ![]i64 {
    if (ids.len == 0) return &[_]i64{};

    // Build IN clause with placeholders
    var placeholders: std.ArrayListUnmanaged(u8) = .empty;
    defer placeholders.deinit(allocator);

    for (ids, 0..) |_, i| {
        if (i > 0) try placeholders.append(allocator, ',');
        try placeholders.appendSlice(allocator, "?");
    }

    const sql = try std.fmt.allocPrint(allocator, "SELECT id FROM tasks WHERE id IN ({s})", .{placeholders.items});
    defer allocator.free(sql);

    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), sql.ptr, @intCast(sql.len), &stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    // Bind all IDs
    for (ids, 0..) |id, i| {
        _ = c.sqlite3_bind_int64(stmt, @intCast(i + 1), id);
    }

    var list: std.ArrayListUnmanaged(i64) = .empty;
    errdefer list.deinit(allocator);

    while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
        try list.append(allocator, c.sqlite3_column_int64(stmt, 0));
    }

    return list.toOwnedSlice(allocator);
}

/// Update status for multiple tasks at once
pub fn updateTaskStatusBulk(allocator: std.mem.Allocator, conn: Connection, ids: []const i64, new_status: TaskStatus) !usize {
    if (ids.len == 0) return 0;

    // Build IN clause with placeholders
    var placeholders: std.ArrayListUnmanaged(u8) = .empty;
    defer placeholders.deinit(allocator);

    for (ids, 0..) |_, i| {
        if (i > 0) try placeholders.append(allocator, ',');
        try placeholders.appendSlice(allocator, "?");
    }

    const status_str = new_status.toString();
    const sql = try std.fmt.allocPrint(allocator, "UPDATE tasks SET status = ? WHERE id IN ({s})", .{ placeholders.items });
    defer allocator.free(sql);

    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), sql.ptr, @intCast(sql.len), &stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    // Bind status first (parameter 1)
    _ = c.sqlite3_bind_text(stmt, 1, status_str.ptr, @intCast(status_str.len), c.SQLITE_STATIC);

    // Bind all IDs starting from parameter 2
    for (ids, 0..) |id, i| {
        _ = c.sqlite3_bind_int64(stmt, @intCast(i + 2), id);
    }

    const step_rc = c.sqlite3_step(stmt);
    if (step_rc != c.SQLITE_DONE) return error.StepFailed;

    return @intCast(c.sqlite3_changes(@ptrCast(conn.db)));
}

/// Update priority for multiple tasks at once
pub fn updateTaskPriorityBulk(allocator: std.mem.Allocator, conn: Connection, ids: []const i64, priority: i32) !usize {
    if (ids.len == 0) return 0;

    var placeholders: std.ArrayListUnmanaged(u8) = .empty;
    defer placeholders.deinit(allocator);

    for (ids, 0..) |_, i| {
        if (i > 0) try placeholders.append(allocator, ',');
        try placeholders.appendSlice(allocator, "?");
    }

    const sql = try std.fmt.allocPrint(allocator, "UPDATE tasks SET priority = ? WHERE id IN ({s})", .{ placeholders.items });
    defer allocator.free(sql);

    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), sql.ptr, @intCast(sql.len), &stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    _ = c.sqlite3_bind_int(stmt, 1, priority);

    for (ids, 0..) |id, i| {
        _ = c.sqlite3_bind_int64(stmt, @intCast(i + 2), id);
    }

    const step_rc = c.sqlite3_step(stmt);
    if (step_rc != c.SQLITE_DONE) return error.StepFailed;

    return @intCast(c.sqlite3_changes(@ptrCast(conn.db)));
}

/// Update severity for multiple tasks at once
pub fn updateTaskSeverityBulk(allocator: std.mem.Allocator, conn: Connection, ids: []const i64, severity: i32) !usize {
    if (ids.len == 0) return 0;

    var placeholders: std.ArrayListUnmanaged(u8) = .empty;
    defer placeholders.deinit(allocator);

    for (ids, 0..) |_, i| {
        if (i > 0) try placeholders.append(allocator, ',');
        try placeholders.appendSlice(allocator, "?");
    }

    const sql = try std.fmt.allocPrint(allocator, "UPDATE tasks SET severity = ? WHERE id IN ({s})", .{ placeholders.items });
    defer allocator.free(sql);

    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), sql.ptr, @intCast(sql.len), &stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    _ = c.sqlite3_bind_int(stmt, 1, severity);

    for (ids, 0..) |id, i| {
        _ = c.sqlite3_bind_int64(stmt, @intCast(i + 2), id);
    }

    const step_rc = c.sqlite3_step(stmt);
    if (step_rc != c.SQLITE_DONE) return error.StepFailed;

    return @intCast(c.sqlite3_changes(@ptrCast(conn.db)));
}

/// Update completed_at for multiple tasks at once
pub fn updateTaskCompletedAtBulk(allocator: std.mem.Allocator, conn: Connection, ids: []const i64, completed_at: ?[]const u8) !usize {
    if (ids.len == 0) return 0;

    var placeholders: std.ArrayListUnmanaged(u8) = .empty;
    defer placeholders.deinit(allocator);

    for (ids, 0..) |_, i| {
        if (i > 0) try placeholders.append(allocator, ',');
        try placeholders.appendSlice(allocator, "?");
    }

    const sql = try std.fmt.allocPrint(allocator, "UPDATE tasks SET completed_at = ? WHERE id IN ({s})", .{ placeholders.items });
    defer allocator.free(sql);

    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), sql.ptr, @intCast(sql.len), &stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    if (completed_at) |ca| {
        _ = c.sqlite3_bind_text(stmt, 1, ca.ptr, @intCast(ca.len), c.SQLITE_STATIC);
    } else {
        _ = c.sqlite3_bind_null(stmt, 1);
    }

    for (ids, 0..) |id, i| {
        _ = c.sqlite3_bind_int64(stmt, @intCast(i + 2), id);
    }

    const step_rc = c.sqlite3_step(stmt);
    if (step_rc != c.SQLITE_DONE) return error.StepFailed;

    return @intCast(c.sqlite3_changes(@ptrCast(conn.db)));
}

/// Delete multiple tasks at once
pub fn deleteTaskBulk(allocator: std.mem.Allocator, conn: Connection, ids: []const i64) !usize {
    if (ids.len == 0) return 0;

    var placeholders: std.ArrayListUnmanaged(u8) = .empty;
    defer placeholders.deinit(allocator);

    for (ids, 0..) |_, i| {
        if (i > 0) try placeholders.append(allocator, ',');
        try placeholders.appendSlice(allocator, "?");
    }

    const sql = try std.fmt.allocPrint(allocator, "DELETE FROM tasks WHERE id IN ({s})", .{ placeholders.items });
    defer allocator.free(sql);

    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), sql.ptr, @intCast(sql.len), &stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    for (ids, 0..) |id, i| {
        _ = c.sqlite3_bind_int64(stmt, @intCast(i + 1), id);
    }

    const step_rc = c.sqlite3_step(stmt);
    if (step_rc != c.SQLITE_DONE) return error.StepFailed;

    return @intCast(c.sqlite3_changes(@ptrCast(conn.db)));
}

// ============== SPRINT QUERIES ==============

pub fn insertSprint(conn: Connection, description: []const u8, created_at: []const u8) !i64 {
    const sql = "INSERT INTO sprints (description, created_at) VALUES (?, ?)";

    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), sql.ptr, @intCast(sql.len), &stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    _ = c.sqlite3_bind_text(stmt, 1, description.ptr, @intCast(description.len), c.SQLITE_STATIC);
    _ = c.sqlite3_bind_text(stmt, 2, created_at.ptr, @intCast(created_at.len), c.SQLITE_STATIC);

    const step_rc = c.sqlite3_step(stmt);
    if (step_rc != c.SQLITE_DONE) return error.StepFailed;

    return conn.lastInsertRowId();
}

pub fn updateSprintStatus(conn: Connection, id: i64, status: SprintStatus) !void {
    const status_str = status.toString();
    const sql = "UPDATE sprints SET status = ? WHERE id = ?";

    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), sql.ptr, @intCast(sql.len), &stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    _ = c.sqlite3_bind_text(stmt, 1, status_str.ptr, @intCast(status_str.len), c.SQLITE_STATIC);
    _ = c.sqlite3_bind_int64(stmt, 2, id);

    const step_rc = c.sqlite3_step(stmt);
    if (step_rc != c.SQLITE_DONE) return error.StepFailed;
}

pub fn updateSprintStartedAt(conn: Connection, id: i64, started_at: ?[]const u8) !void {
    const sql = "UPDATE sprints SET started_at = ? WHERE id = ?";
    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), sql.ptr, @intCast(sql.len), &stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    if (started_at) |sa| {
        _ = c.sqlite3_bind_text(stmt, 1, sa.ptr, @intCast(sa.len), c.SQLITE_STATIC);
    } else {
        _ = c.sqlite3_bind_null(stmt, 1);
    }
    _ = c.sqlite3_bind_int64(stmt, 2, id);

    const step_rc = c.sqlite3_step(stmt);
    if (step_rc != c.SQLITE_DONE) return error.StepFailed;
}

pub fn updateSprintClosedAt(conn: Connection, id: i64, closed_at: ?[]const u8) !void {
    const sql = "UPDATE sprints SET closed_at = ? WHERE id = ?";
    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), sql.ptr, @intCast(sql.len), &stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    if (closed_at) |ca| {
        _ = c.sqlite3_bind_text(stmt, 1, ca.ptr, @intCast(ca.len), c.SQLITE_STATIC);
    } else {
        _ = c.sqlite3_bind_null(stmt, 1);
    }
    _ = c.sqlite3_bind_int64(stmt, 2, id);

    const step_rc = c.sqlite3_step(stmt);
    if (step_rc != c.SQLITE_DONE) return error.StepFailed;
}

pub fn getSprintById(allocator: std.mem.Allocator, conn: Connection, id: i64) !Sprint {
    const sql = "SELECT id, status, description, created_at, started_at, closed_at FROM sprints WHERE id = ?";
    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), sql.ptr, @intCast(sql.len), &stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    _ = c.sqlite3_bind_int64(stmt, 1, id);

    if (c.sqlite3_step(stmt) != c.SQLITE_ROW) return error.SprintNotFound;

    const status_str = std.mem.span(c.sqlite3_column_text(stmt, 1));
    const description = std.mem.span(c.sqlite3_column_text(stmt, 2));
    const created_at = std.mem.span(c.sqlite3_column_text(stmt, 3));
    const started_at_ptr = c.sqlite3_column_text(stmt, 4);
    const closed_at_ptr = c.sqlite3_column_text(stmt, 5);

    var sprint = try Sprint.init(allocator, id, description, created_at);
    sprint.status = try SprintStatus.fromString(status_str);
    if (started_at_ptr) |p| sprint.started_at = try allocator.dupe(u8, std.mem.span(p));
    if (closed_at_ptr) |p| sprint.closed_at = try allocator.dupe(u8, std.mem.span(p));

    // Also fetch task IDs
    const task_ids = try getTaskIdsBySprint(allocator, conn, id);
    defer allocator.free(task_ids);

    // We need to re-allocate sprint.tasks because Sprint.init allocates an empty one
    allocator.free(sprint.tasks);
    sprint.tasks = try allocator.dupe(i64, task_ids);
    sprint.task_count = @intCast(task_ids.len);

    return sprint;
}

fn getTaskIdsBySprint(allocator: std.mem.Allocator, conn: Connection, sprint_id: i64) ![]i64 {
    const sql = "SELECT task_id FROM sprint_tasks WHERE sprint_id = ?";
    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), sql.ptr, @intCast(sql.len), &stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    _ = c.sqlite3_bind_int64(stmt, 1, sprint_id);

    var list: std.ArrayListUnmanaged(i64) = .empty;
    defer list.deinit(allocator);

    while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
        try list.append(allocator, c.sqlite3_column_int64(stmt, 0));
    }

    return list.toOwnedSlice(allocator);
}

pub fn getTasksBySprint(allocator: std.mem.Allocator, conn: Connection, sprint_id: i64) ![]Task {
    const sql =
        \\SELECT t.id, t.priority, t.severity, t.status, t.description, t.specialists, t.action, t.expected_result, t.created_at, t.completed_at
        \\FROM tasks t
        \\JOIN sprint_tasks st ON t.id = st.task_id
        \\WHERE st.sprint_id = ?
        \\ORDER BY t.priority DESC, t.severity DESC
    ;

    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), sql.ptr, @intCast(sql.len), &stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    _ = c.sqlite3_bind_int64(stmt, 1, sprint_id);

    var list: std.ArrayListUnmanaged(Task) = .empty;
    errdefer {
        for (list.items) |*t| t.deinit(allocator);
        list.deinit(allocator);
    }

    while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
        try list.append(allocator, try rowToTask(allocator, stmt.?));
    }

    return list.toOwnedSlice(allocator);
}

/// Get tasks by sprint with optional status filter
pub fn getTasksBySprintFiltered(allocator: std.mem.Allocator, conn: Connection, sprint_id: i64, status_filter: ?TaskStatus) ![]Task {
    const sql_base =
        \\SELECT t.id, t.priority, t.severity, t.status, t.description, t.specialists, t.action, t.expected_result, t.created_at, t.completed_at
        \\FROM tasks t
        \\JOIN sprint_tasks st ON t.id = st.task_id
        \\WHERE st.sprint_id = ?
    ;
    const order_clause = " ORDER BY t.priority DESC, t.severity DESC";

    var full_sql: []const u8 = undefined;
    if (status_filter) |s| {
        _ = s; // capture is used for the condition check
        full_sql = try std.fmt.allocPrint(allocator, "{s} AND t.status = ?{s}", .{ sql_base, order_clause });
    } else {
        full_sql = try std.mem.concat(allocator, u8, &[_][]const u8{ sql_base, order_clause });
    }
    defer allocator.free(full_sql);

    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), full_sql.ptr, @intCast(full_sql.len), &stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    _ = c.sqlite3_bind_int64(stmt, 1, sprint_id);
    if (status_filter) |s| {
        const s_str = s.toString();
        _ = c.sqlite3_bind_text(stmt, 2, s_str.ptr, @intCast(s_str.len), c.SQLITE_STATIC);
    }

    var list: std.ArrayListUnmanaged(Task) = .empty;
    errdefer {
        for (list.items) |*t| t.deinit(allocator);
        list.deinit(allocator);
    }

    while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
        try list.append(allocator, try rowToTask(allocator, stmt.?));
    }

    return list.toOwnedSlice(allocator);
}

pub fn updateSprintDescription(conn: Connection, id: i64, description: []const u8) !void {
    const sql = "UPDATE sprints SET description = ? WHERE id = ?";
    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), sql.ptr, @intCast(sql.len), &stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    _ = c.sqlite3_bind_text(stmt, 1, description.ptr, @intCast(description.len), c.SQLITE_STATIC);
    _ = c.sqlite3_bind_int64(stmt, 2, id);

    const step_rc = c.sqlite3_step(stmt);
    if (step_rc != c.SQLITE_DONE) return error.StepFailed;
}

pub fn listSprints(allocator: std.mem.Allocator, conn: Connection, status_filter: ?SprintStatus) ![]Sprint {
    const sql: []const u8 = "SELECT id, status, description, created_at, started_at, closed_at FROM sprints";
    var where_clause: []const u8 = "";
    if (status_filter != null) {
        where_clause = " WHERE status = ?";
    }
    const order_clause = " ORDER BY created_at DESC";

    const full_sql = try std.mem.concat(allocator, u8, &[_][]const u8{ sql, where_clause, order_clause });
    defer allocator.free(full_sql);

    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), full_sql.ptr, @intCast(full_sql.len), &stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    if (status_filter) |s| {
        const s_str = s.toString();
        _ = c.sqlite3_bind_text(stmt, 1, s_str.ptr, @intCast(s_str.len), c.SQLITE_STATIC);
    }

    var list: std.ArrayListUnmanaged(Sprint) = .empty;
    errdefer {
        for (list.items) |*s| s.deinit(allocator);
        list.deinit(allocator);
    }

    while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
        const id = c.sqlite3_column_int64(stmt, 0);
        const status_str = std.mem.span(c.sqlite3_column_text(stmt, 1));
        const description = std.mem.span(c.sqlite3_column_text(stmt, 2));
        const created_at = std.mem.span(c.sqlite3_column_text(stmt, 3));
        const started_at_ptr = c.sqlite3_column_text(stmt, 4);
        const closed_at_ptr = c.sqlite3_column_text(stmt, 5);

        var sprint = try Sprint.init(allocator, id, description, created_at);
        sprint.status = try SprintStatus.fromString(status_str);
        if (started_at_ptr) |p| sprint.started_at = try allocator.dupe(u8, std.mem.span(p));
        if (closed_at_ptr) |p| sprint.closed_at = try allocator.dupe(u8, std.mem.span(p));

        try list.append(allocator, sprint);
    }

    return list.toOwnedSlice(allocator);
}

pub fn deleteSprint(conn: Connection, id: i64) !void {
    const sql = "DELETE FROM sprints WHERE id = ?";

    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), sql.ptr, @intCast(sql.len), &stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    _ = c.sqlite3_bind_int64(stmt, 1, id);

    const step_rc = c.sqlite3_step(stmt);
    if (step_rc != c.SQLITE_DONE) return error.StepFailed;
}

// ============== SPRINT TASKS QUERIES ==============

pub fn addTaskToSprint(conn: Connection, sprint_id: i64, task_id: i64, added_at: []const u8) !void {
    const sql = "INSERT INTO sprint_tasks (sprint_id, task_id, added_at) VALUES (?, ?, ?)";

    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), sql.ptr, @intCast(sql.len), &stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    _ = c.sqlite3_bind_int64(stmt, 1, sprint_id);
    _ = c.sqlite3_bind_int64(stmt, 2, task_id);
    _ = c.sqlite3_bind_text(stmt, 3, added_at.ptr, @intCast(added_at.len), c.SQLITE_STATIC);

    const step_rc = c.sqlite3_step(stmt);
    if (step_rc != c.SQLITE_DONE) return error.StepFailed;
}

pub fn getSprintIdByTaskId(conn: Connection, task_id: i64) !?i64 {
    const sql = "SELECT sprint_id FROM sprint_tasks WHERE task_id = ?";
    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), sql.ptr, @intCast(sql.len), &stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    _ = c.sqlite3_bind_int64(stmt, 1, task_id);

    if (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
        return c.sqlite3_column_int64(stmt, 0);
    }

    return null;
}

pub fn removeTaskFromSprint(conn: Connection, task_id: i64) !void {
    const sql = "DELETE FROM sprint_tasks WHERE task_id = ?";

    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), sql.ptr, @intCast(sql.len), &stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    _ = c.sqlite3_bind_int64(stmt, 1, task_id);

    const step_rc = c.sqlite3_step(stmt);
    if (step_rc != c.SQLITE_DONE) return error.StepFailed;
}

pub fn moveTaskBetweenSprints(conn: Connection, task_id: i64, new_sprint_id: i64) !void {
    const sql = "UPDATE sprint_tasks SET sprint_id = ? WHERE task_id = ?";

    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), sql.ptr, @intCast(sql.len), &stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    _ = c.sqlite3_bind_int64(stmt, 1, new_sprint_id);
    _ = c.sqlite3_bind_int64(stmt, 2, task_id);

    const step_rc = c.sqlite3_step(stmt);
    if (step_rc != c.SQLITE_DONE) return error.StepFailed;
}

pub fn getSprintStats(allocator: std.mem.Allocator, conn: Connection, sprint_id: i64) !@import("../models/sprint.zig").SprintStats {
    const sql =
        \\SELECT
        \\  s.id,
        \\  s.description,
        \\  s.status,
        \\  s.created_at,
        \\  s.started_at,
        \\  s.closed_at,
        \\  COUNT(t.id),
        \\  SUM(CASE WHEN t.status = 'BACKLOG' THEN 1 ELSE 0 END),
        \\  SUM(CASE WHEN t.status = 'SPRINT' THEN 1 ELSE 0 END),
        \\  SUM(CASE WHEN t.status = 'DOING' THEN 1 ELSE 0 END),
        \\  SUM(CASE WHEN t.status = 'TESTING' THEN 1 ELSE 0 END),
        \\  SUM(CASE WHEN t.status = 'COMPLETED' THEN 1 ELSE 0 END)
        \\FROM sprints s
        \\LEFT JOIN sprint_tasks st ON s.id = st.sprint_id
        \\LEFT JOIN tasks t ON st.task_id = t.id
        \\WHERE s.id = ?
        \\GROUP BY s.id, s.description, s.status, s.created_at, s.started_at, s.closed_at
    ;

    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), sql.ptr, @intCast(sql.len), &stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    _ = c.sqlite3_bind_int64(stmt, 1, sprint_id);

    if (c.sqlite3_step(stmt) != c.SQLITE_ROW) return error.StepFailed;

    const id = c.sqlite3_column_int64(stmt, 0);
    const desc_ptr = c.sqlite3_column_text(stmt, 1);
    const desc_len: usize = @intCast(c.sqlite3_column_bytes(stmt, 1));
    const status_str = c.sqlite3_column_text(stmt, 2);
    const created_ptr = c.sqlite3_column_text(stmt, 3);
    const created_len: usize = @intCast(c.sqlite3_column_bytes(stmt, 3));

    const description = try allocator.dupe(u8, desc_ptr[0..desc_len]);
    errdefer allocator.free(description);

    const status_len: usize = @intCast(c.sqlite3_column_bytes(stmt, 2));
    const status = SprintStatus.fromString(status_str[0..status_len]) catch .PENDING;

    const created_at = try allocator.dupe(u8, created_ptr[0..created_len]);
    errdefer allocator.free(created_at);

    const started_at: ?[]const u8 = if (c.sqlite3_column_type(stmt, 4) == c.SQLITE_NULL) null else blk: {
        const ptr = c.sqlite3_column_text(stmt, 4);
        const len: usize = @intCast(c.sqlite3_column_bytes(stmt, 4));
        break :blk try allocator.dupe(u8, ptr[0..len]);
    };
    errdefer if (started_at) |sa| allocator.free(sa);

    const closed_at: ?[]const u8 = if (c.sqlite3_column_type(stmt, 5) == c.SQLITE_NULL) null else blk: {
        const ptr = c.sqlite3_column_text(stmt, 5);
        const len: usize = @intCast(c.sqlite3_column_bytes(stmt, 5));
        break :blk try allocator.dupe(u8, ptr[0..len]);
    };
    errdefer if (closed_at) |ca| allocator.free(ca);

    const total = c.sqlite3_column_int(stmt, 6);
    const backlog = c.sqlite3_column_int(stmt, 7);
    const sprint = c.sqlite3_column_int(stmt, 8);
    const doing = c.sqlite3_column_int(stmt, 9);
    const testing = c.sqlite3_column_int(stmt, 10);
    const completed = c.sqlite3_column_int(stmt, 11);

    const completion_percentage: i32 = if (total > 0) @intCast(@divTrunc(completed * 100, total)) else 0;

    return .{
        .id = id,
        .description = description,
        .status = status,
        .created_at = created_at,
        .started_at = started_at,
        .closed_at = closed_at,
        .total_tasks = total,
        .by_status = .{
            .backlog = backlog,
            .sprint = sprint,
            .doing = doing,
            .testing = testing,
            .completed = completed,
        },
        .completion_percentage = completion_percentage,
    };
}

// ============== AUDIT QUERIES ==============

pub fn logOperation(conn: Connection, operation: []const u8, entity_type: []const u8, entity_id: i64, performed_at: []const u8) !void {
    const sql = "INSERT INTO audit (operation, entity_type, entity_id, performed_at) VALUES (?, ?, ?, ?)";

    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), sql.ptr, @intCast(sql.len), &stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    _ = c.sqlite3_bind_text(stmt, 1, operation.ptr, @intCast(operation.len), c.SQLITE_STATIC);
    _ = c.sqlite3_bind_text(stmt, 2, entity_type.ptr, @intCast(entity_type.len), c.SQLITE_STATIC);
    _ = c.sqlite3_bind_int64(stmt, 3, entity_id);
    _ = c.sqlite3_bind_text(stmt, 4, performed_at.ptr, @intCast(performed_at.len), c.SQLITE_STATIC);

    const step_rc = c.sqlite3_step(stmt);
    if (step_rc != c.SQLITE_DONE) return error.StepFailed;
}

/// Filter options for audit entries
pub const AuditFilterOptions = struct {
    operation: ?[]const u8 = null,
    entity_type: ?[]const u8 = null,
    entity_id: ?i64 = null,
    since: ?[]const u8 = null,
    until: ?[]const u8 = null,
    limit: i32 = 100,
    offset: i32 = 0,
};

/// Result struct for paginated audit list
pub const AuditListResult = struct {
    entries: []AuditEntry,
    total: i64,
};

pub fn listAuditEntries(allocator: std.mem.Allocator, conn: Connection, filters: AuditFilterOptions) !AuditListResult {
    // First, count total matching entries
    const count_sql_base = "SELECT COUNT(*) FROM audit";
    var count_where_parts: std.ArrayListUnmanaged([]const u8) = .empty;
    defer count_where_parts.deinit(allocator);

    if (filters.operation != null) try count_where_parts.append(allocator, "operation = ?");
    if (filters.entity_type != null) try count_where_parts.append(allocator, "LOWER(entity_type) = LOWER(?)");
    if (filters.entity_id != null) try count_where_parts.append(allocator, "entity_id = ?");
    if (filters.since != null) try count_where_parts.append(allocator, "performed_at >= ?");
    if (filters.until != null) try count_where_parts.append(allocator, "performed_at <= ?");

    const count_sql = if (count_where_parts.items.len > 0)
        try std.fmt.allocPrint(allocator, "{s} WHERE {s}", .{ count_sql_base, try std.mem.join(allocator, " AND ", count_where_parts.items) })
    else
        try allocator.dupe(u8, count_sql_base);
    defer allocator.free(count_sql);

    var count_stmt: ?*c.sqlite3_stmt = null;
    var rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), count_sql.ptr, @intCast(count_sql.len), &count_stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(count_stmt);

    // Bind filter parameters for count
    var bind_idx: c_int = 1;
    if (filters.operation) |op| {
        _ = c.sqlite3_bind_text(count_stmt, bind_idx, op.ptr, @intCast(op.len), c.SQLITE_STATIC);
        bind_idx += 1;
    }
    if (filters.entity_type) |et| {
        _ = c.sqlite3_bind_text(count_stmt, bind_idx, et.ptr, @intCast(et.len), c.SQLITE_STATIC);
        bind_idx += 1;
    }
    if (filters.entity_id) |eid| {
        _ = c.sqlite3_bind_int64(count_stmt, bind_idx, eid);
        bind_idx += 1;
    }
    if (filters.since) |s| {
        _ = c.sqlite3_bind_text(count_stmt, bind_idx, s.ptr, @intCast(s.len), c.SQLITE_STATIC);
        bind_idx += 1;
    }
    if (filters.until) |u| {
        _ = c.sqlite3_bind_text(count_stmt, bind_idx, u.ptr, @intCast(u.len), c.SQLITE_STATIC);
        bind_idx += 1;
    }

    if (c.sqlite3_step(count_stmt) != c.SQLITE_ROW) return error.StepFailed;
    const total = c.sqlite3_column_int64(count_stmt, 0);

    // Now fetch the actual entries
    const select_sql_base = "SELECT id, operation, entity_type, entity_id, performed_at FROM audit";
    var select_where_parts: std.ArrayListUnmanaged([]const u8) = .empty;
    defer select_where_parts.deinit(allocator);

    if (filters.operation != null) try select_where_parts.append(allocator, "operation = ?");
    if (filters.entity_type != null) try select_where_parts.append(allocator, "LOWER(entity_type) = LOWER(?)");
    if (filters.entity_id != null) try select_where_parts.append(allocator, "entity_id = ?");
    if (filters.since != null) try select_where_parts.append(allocator, "performed_at >= ?");
    if (filters.until != null) try select_where_parts.append(allocator, "performed_at <= ?");

    // Build select SQL with WHERE clause
    var select_sql: []const u8 = undefined;
    if (select_where_parts.items.len > 0) {
        const where_clause = try std.mem.join(allocator, " AND ", select_where_parts.items);
        defer allocator.free(where_clause);
        select_sql = try std.fmt.allocPrint(allocator, "{s} WHERE {s} ORDER BY performed_at DESC LIMIT {d} OFFSET {d}", .{ select_sql_base, where_clause, filters.limit, filters.offset });
    } else {
        select_sql = try std.fmt.allocPrint(allocator, "{s} ORDER BY performed_at DESC LIMIT {d} OFFSET {d}", .{ select_sql_base, filters.limit, filters.offset });
    }
    defer allocator.free(select_sql);

    var stmt: ?*c.sqlite3_stmt = null;
    rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), select_sql.ptr, @intCast(select_sql.len), &stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    // Bind filter parameters for select
    bind_idx = 1;
    if (filters.operation) |op| {
        _ = c.sqlite3_bind_text(stmt, bind_idx, op.ptr, @intCast(op.len), c.SQLITE_STATIC);
        bind_idx += 1;
    }
    if (filters.entity_type) |et| {
        _ = c.sqlite3_bind_text(stmt, bind_idx, et.ptr, @intCast(et.len), c.SQLITE_STATIC);
        bind_idx += 1;
    }
    if (filters.entity_id) |eid| {
        _ = c.sqlite3_bind_int64(stmt, bind_idx, eid);
        bind_idx += 1;
    }
    if (filters.since) |s| {
        _ = c.sqlite3_bind_text(stmt, bind_idx, s.ptr, @intCast(s.len), c.SQLITE_STATIC);
        bind_idx += 1;
    }
    if (filters.until) |u| {
        _ = c.sqlite3_bind_text(stmt, bind_idx, u.ptr, @intCast(u.len), c.SQLITE_STATIC);
        bind_idx += 1;
    }

    var list: std.ArrayListUnmanaged(AuditEntry) = .empty;
    errdefer {
        for (list.items) |*e| e.deinit(allocator);
        list.deinit(allocator);
    }

    while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
        const id = c.sqlite3_column_int64(stmt, 0);
        const operation = std.mem.span(c.sqlite3_column_text(stmt, 1));
        const entity_type = std.mem.span(c.sqlite3_column_text(stmt, 2));
        const entity_id = c.sqlite3_column_int64(stmt, 3);
        const performed_at = std.mem.span(c.sqlite3_column_text(stmt, 4));

        try list.append(allocator, try AuditEntry.init(
            allocator,
            id,
            operation,
            entity_type,
            entity_id,
            performed_at,
        ));
    }

    return AuditListResult{
        .entries = try list.toOwnedSlice(allocator),
        .total = total,
    };
}

pub fn getEntityHistory(allocator: std.mem.Allocator, conn: Connection, entity_type: []const u8, entity_id: i64) ![]AuditEntry {
    const sql =
        \\SELECT id, operation, entity_type, entity_id, performed_at
        \\FROM audit
        \\WHERE LOWER(entity_type) = LOWER(?) AND entity_id = ?
        \\ORDER BY performed_at DESC
    ;

    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), sql.ptr, @intCast(sql.len), &stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    _ = c.sqlite3_bind_text(stmt, 1, entity_type.ptr, @intCast(entity_type.len), c.SQLITE_STATIC);
    _ = c.sqlite3_bind_int64(stmt, 2, entity_id);

    var list: std.ArrayListUnmanaged(AuditEntry) = .empty;
    errdefer {
        for (list.items) |*e| e.deinit(allocator);
        list.deinit(allocator);
    }

    while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
        const id = c.sqlite3_column_int64(stmt, 0);
        const operation = std.mem.span(c.sqlite3_column_text(stmt, 1));
        const et = std.mem.span(c.sqlite3_column_text(stmt, 2));
        const eid = c.sqlite3_column_int64(stmt, 3);
        const performed_at = std.mem.span(c.sqlite3_column_text(stmt, 4));

        try list.append(allocator, try AuditEntry.init(
            allocator,
            id,
            operation,
            et,
            eid,
            performed_at,
        ));
    }

    return list.toOwnedSlice(allocator);
}

pub fn getAuditStats(allocator: std.mem.Allocator, conn: Connection, since: ?[]const u8, until: ?[]const u8) !AuditStats {
    var stats = AuditStats.init(allocator);
    errdefer stats.deinit(allocator);

    // Build WHERE clause for time range
    var where_parts: std.ArrayListUnmanaged([]const u8) = .empty;
    defer where_parts.deinit(allocator);

    if (since != null) try where_parts.append(allocator, "performed_at >= ?");
    if (until != null) try where_parts.append(allocator, "performed_at <= ?");

    const where_clause = if (where_parts.items.len > 0)
        try std.fmt.allocPrint(allocator, "WHERE {s}", .{try std.mem.join(allocator, " AND ", where_parts.items)})
    else
        try allocator.dupe(u8, "");
    defer allocator.free(where_clause);

    // Get total count
    const total_sql = if (where_parts.items.len > 0)
        try std.fmt.allocPrint(allocator, "SELECT COUNT(*) FROM audit {s}", .{where_clause})
    else
        try allocator.dupe(u8, "SELECT COUNT(*) FROM audit");
    defer allocator.free(total_sql);

    var total_stmt: ?*c.sqlite3_stmt = null;
    var rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), total_sql.ptr, @intCast(total_sql.len), &total_stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(total_stmt);

    var bind_idx: c_int = 1;
    if (since) |s| {
        _ = c.sqlite3_bind_text(total_stmt, bind_idx, s.ptr, @intCast(s.len), c.SQLITE_STATIC);
        bind_idx += 1;
    }
    if (until) |u| {
        _ = c.sqlite3_bind_text(total_stmt, bind_idx, u.ptr, @intCast(u.len), c.SQLITE_STATIC);
        bind_idx += 1;
    }

    if (c.sqlite3_step(total_stmt) == c.SQLITE_ROW) {
        stats.total_entries = c.sqlite3_column_int64(total_stmt, 0);
    }

    // Get counts by operation
    const op_sql = if (where_parts.items.len > 0)
        try std.fmt.allocPrint(allocator, "SELECT operation, COUNT(*) FROM audit {s} GROUP BY operation", .{where_clause})
    else
        try allocator.dupe(u8, "SELECT operation, COUNT(*) FROM audit GROUP BY operation");
    defer allocator.free(op_sql);

    var op_stmt: ?*c.sqlite3_stmt = null;
    rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), op_sql.ptr, @intCast(op_sql.len), &op_stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(op_stmt);

    bind_idx = 1;
    if (since) |s| {
        _ = c.sqlite3_bind_text(op_stmt, bind_idx, s.ptr, @intCast(s.len), c.SQLITE_STATIC);
        bind_idx += 1;
    }
    if (until) |u| {
        _ = c.sqlite3_bind_text(op_stmt, bind_idx, u.ptr, @intCast(u.len), c.SQLITE_STATIC);
        bind_idx += 1;
    }

    while (c.sqlite3_step(op_stmt) == c.SQLITE_ROW) {
        const operation = std.mem.span(c.sqlite3_column_text(op_stmt, 0));
        const count = c.sqlite3_column_int64(op_stmt, 1);
        try stats.by_operation.put(try allocator.dupe(u8, operation), count);
    }

    // Get counts by entity_type
    const et_sql = if (where_parts.items.len > 0)
        try std.fmt.allocPrint(allocator, "SELECT entity_type, COUNT(*) FROM audit {s} GROUP BY entity_type", .{where_clause})
    else
        try allocator.dupe(u8, "SELECT entity_type, COUNT(*) FROM audit GROUP BY entity_type");
    defer allocator.free(et_sql);

    var et_stmt: ?*c.sqlite3_stmt = null;
    rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), et_sql.ptr, @intCast(et_sql.len), &et_stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(et_stmt);

    bind_idx = 1;
    if (since) |s| {
        _ = c.sqlite3_bind_text(et_stmt, bind_idx, s.ptr, @intCast(s.len), c.SQLITE_STATIC);
        bind_idx += 1;
    }
    if (until) |u| {
        _ = c.sqlite3_bind_text(et_stmt, bind_idx, u.ptr, @intCast(u.len), c.SQLITE_STATIC);
        bind_idx += 1;
    }

    while (c.sqlite3_step(et_stmt) == c.SQLITE_ROW) {
        const entity_type = std.mem.span(c.sqlite3_column_text(et_stmt, 0));
        const count = c.sqlite3_column_int64(et_stmt, 1);
        try stats.by_entity_type.put(try allocator.dupe(u8, entity_type), count);
    }

    // Get first and last entry dates
    const range_sql = if (where_parts.items.len > 0)
        try std.fmt.allocPrint(allocator, "SELECT MIN(performed_at), MAX(performed_at) FROM audit {s}", .{where_clause})
    else
        try allocator.dupe(u8, "SELECT MIN(performed_at), MAX(performed_at) FROM audit");
    defer allocator.free(range_sql);

    var range_stmt: ?*c.sqlite3_stmt = null;
    rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), range_sql.ptr, @intCast(range_sql.len), &range_stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(range_stmt);

    bind_idx = 1;
    if (since) |s| {
        _ = c.sqlite3_bind_text(range_stmt, bind_idx, s.ptr, @intCast(s.len), c.SQLITE_STATIC);
        bind_idx += 1;
    }
    if (until) |u| {
        _ = c.sqlite3_bind_text(range_stmt, bind_idx, u.ptr, @intCast(u.len), c.SQLITE_STATIC);
        bind_idx += 1;
    }

    if (c.sqlite3_step(range_stmt) == c.SQLITE_ROW) {
        const first_ptr = c.sqlite3_column_text(range_stmt, 0);
        const last_ptr = c.sqlite3_column_text(range_stmt, 1);
        if (first_ptr) |p| stats.first_entry = try allocator.dupe(u8, std.mem.span(p));
        if (last_ptr) |p| stats.last_entry = try allocator.dupe(u8, std.mem.span(p));
    }

    return stats;
}
