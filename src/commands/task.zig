const std = @import("std");
const path = @import("../utils/path.zig");
const json = @import("../utils/json.zig");
const time = @import("../utils/time.zig");
const connection = @import("../db/connection.zig");
const queries = @import("../db/queries.zig");
const Task = @import("../models/task.zig").Task;
const TaskStatus = @import("../models/task.zig").TaskStatus;
const roadmap = @import("roadmap.zig");

/// Task input for creating a new task
pub const TaskInput = struct {
    priority: i32,
    severity: i32,
    description: []const u8,
    specialists: ?[]const u8,
    action: []const u8,
    expected_result: []const u8,
};

/// Adds a new task to the current roadmap
pub fn addTask(allocator: std.mem.Allocator, input: TaskInput) ![]const u8 {
    // Get current roadmap
    const current = try roadmap.getCurrentRoadmap(allocator) orelse {
        return json.errorResponse(allocator, "NO_ROADMAP", "No roadmap selected. Use 'rmp roadmap use <name>' first");
    };
    defer allocator.free(current);

    // Get full path
    const roadmap_path = path.getRoadmapPath(allocator, current) catch {
        return json.errorResponse(allocator, "SYSTEM_ERROR", "Failed to get roadmap path");
    };
    defer allocator.free(roadmap_path);

    // Validate roadmap exists
    if (!path.fileExists(roadmap_path)) {
        return json.errorResponse(allocator, "ROADMAP_NOT_FOUND", "Selected roadmap no longer exists");
    }

    // Open connection
    var conn = connection.Connection.open(allocator, roadmap_path) catch {
        return json.errorResponse(allocator, "DB_ERROR", "Failed to open roadmap database");
    };
    defer conn.close(allocator);

    // Get current time
    const now = time.nowUtc(allocator) catch {
        return json.errorResponse(allocator, "SYSTEM_ERROR", "Failed to get current time");
    };
    defer allocator.free(now);

    // Create task
    const task = Task{
        .id = 0, // Will be set by database
        .priority = input.priority,
        .severity = input.severity,
        .status = .BACKLOG,
        .description = input.description,
        .specialists = input.specialists,
        .action = input.action,
        .expected_result = input.expected_result,
        .created_at = now,
        .completed_at = null,
    };

    // Insert task
    const task_id = queries.insertTask(conn, task) catch {
        return json.errorResponse(allocator, "DB_ERROR", "Failed to insert task");
    };

    // Log operation
    queries.logOperation(conn, "CREATE", "task", task_id, now) catch {};

    // Build response
    const response = try std.fmt.allocPrint(allocator, "{{\"id\":{d},\"priority\":{d},\"severity\":{d},\"status\":\"BACKLOG\",\"description\":\"{s}\",\"created_at\":\"{s}\"}}", .{
        task_id, input.priority, input.severity, input.description, now,
    });
    defer allocator.free(response);

    return json.success(allocator, response);
}

/// Lists tasks with optional status filter
pub fn listTasks(allocator: std.mem.Allocator, status_filter: ?TaskStatus) ![]const u8 {
    // Get current roadmap
    const current = try roadmap.getCurrentRoadmap(allocator) orelse {
        return json.errorResponse(allocator, "NO_ROADMAP", "No roadmap selected. Use 'rmp roadmap use <name>' first");
    };
    defer allocator.free(current);

    // Get full path
    const roadmap_path = path.getRoadmapPath(allocator, current) catch {
        return json.errorResponse(allocator, "SYSTEM_ERROR", "Failed to get roadmap path");
    };
    defer allocator.free(roadmap_path);

    // Validate roadmap exists
    if (!path.fileExists(roadmap_path)) {
        return json.errorResponse(allocator, "ROADMAP_NOT_FOUND", "Selected roadmap no longer exists");
    }

    // Open connection
    var conn = connection.Connection.open(allocator, roadmap_path) catch {
        return json.errorResponse(allocator, "DB_ERROR", "Failed to open roadmap database");
    };
    defer conn.close(allocator);

    // Query tasks based on filter
    const tasks_json = try fetchTasksJson(allocator, conn, status_filter);
    defer allocator.free(tasks_json);

    return json.success(allocator, tasks_json);
}

/// Changes the status of a task
pub fn changeTaskStatus(allocator: std.mem.Allocator, task_id: i64, new_status: TaskStatus) ![]const u8 {
    // Get current roadmap
    const current = try roadmap.getCurrentRoadmap(allocator) orelse {
        return json.errorResponse(allocator, "NO_ROADMAP", "No roadmap selected. Use 'rmp roadmap use <name>' first");
    };
    defer allocator.free(current);

    // Get full path
    const roadmap_path = path.getRoadmapPath(allocator, current) catch {
        return json.errorResponse(allocator, "SYSTEM_ERROR", "Failed to get roadmap path");
    };
    defer allocator.free(roadmap_path);

    // Validate roadmap exists
    if (!path.fileExists(roadmap_path)) {
        return json.errorResponse(allocator, "ROADMAP_NOT_FOUND", "Selected roadmap no longer exists");
    }

    // Open connection
    var conn = connection.Connection.open(allocator, roadmap_path) catch {
        return json.errorResponse(allocator, "DB_ERROR", "Failed to open roadmap database");
    };
    defer conn.close(allocator);

    // Get current status
    const current_status = getTaskStatus(conn, task_id) catch {
        return json.errorResponse(allocator, "TASK_NOT_FOUND", "Task not found");
    };

    // Validate transition
    if (!current_status.isValidTransition(new_status)) {
        return json.errorResponse(allocator, "INVALID_TRANSITION", "Invalid status transition");
    }

    // Update status
    queries.updateTaskStatus(conn, task_id, new_status) catch {
        return json.errorResponse(allocator, "DB_ERROR", "Failed to update task status");
    };

    // Get current time
    const now = time.nowUtc(allocator) catch {
        return json.errorResponse(allocator, "SYSTEM_ERROR", "Failed to get current time");
    };
    defer allocator.free(now);

    // Log operation
    queries.logOperation(conn, "STATUS_CHANGE", "task", task_id, now) catch {};

    // Build response
    const response = try std.fmt.allocPrint(allocator, "{{\"id\":{d},\"previous_status\":\"{s}\",\"new_status\":\"{s}\",\"changed_at\":\"{s}\"}}", .{
        task_id, current_status.toString(), new_status.toString(), now,
    });
    defer allocator.free(response);

    return json.success(allocator, response);
}

/// Edits a task
pub fn editTask(allocator: std.mem.Allocator, task_id: i64, updates: TaskUpdate) ![]const u8 {
    // Get current roadmap
    const current = try roadmap.getCurrentRoadmap(allocator) orelse {
        return json.errorResponse(allocator, "NO_ROADMAP", "No roadmap selected. Use 'rmp roadmap use <name>' first");
    };
    defer allocator.free(current);

    // Get full path
    const roadmap_path = path.getRoadmapPath(allocator, current) catch {
        return json.errorResponse(allocator, "SYSTEM_ERROR", "Failed to get roadmap path");
    };
    defer allocator.free(roadmap_path);

    // Validate roadmap exists
    if (!path.fileExists(roadmap_path)) {
        return json.errorResponse(allocator, "ROADMAP_NOT_FOUND", "Selected roadmap no longer exists");
    }

    // Open connection
    var conn = connection.Connection.open(allocator, roadmap_path) catch {
        return json.errorResponse(allocator, "DB_ERROR", "Failed to open roadmap database");
    };
    defer conn.close(allocator);

    // Verify task exists
    _ = getTaskStatus(conn, task_id) catch {
        return json.errorResponse(allocator, "TASK_NOT_FOUND", "Task not found");
    };

    // Build update SQL dynamically
    try executeTaskUpdate(allocator, conn, task_id, updates);

    // Get current time
    const now = time.nowUtc(allocator) catch {
        return json.errorResponse(allocator, "SYSTEM_ERROR", "Failed to get current time");
    };
    defer allocator.free(now);

    // Log operation
    queries.logOperation(conn, "EDIT", "task", task_id, now) catch {};

    // Build response
    const response = try std.fmt.allocPrint(allocator, "{{\"id\":{d},\"message\":\"Task updated successfully\",\"updated_at\":\"{s}\"}}", .{ task_id, now });
    defer allocator.free(response);

    return json.success(allocator, response);
}

/// Task update structure
pub const TaskUpdate = struct {
    priority: ?i32,
    severity: ?i32,
    description: ?[]const u8,
    specialists: ?[]const u8,
    action: ?[]const u8,
    expected_result: ?[]const u8,
};

/// Deletes a task
pub fn deleteTask(allocator: std.mem.Allocator, task_id: i64) ![]const u8 {
    // Get current roadmap
    const current = try roadmap.getCurrentRoadmap(allocator) orelse {
        return json.errorResponse(allocator, "NO_ROADMAP", "No roadmap selected. Use 'rmp roadmap use <name>' first");
    };
    defer allocator.free(current);

    // Get full path
    const roadmap_path = path.getRoadmapPath(allocator, current) catch {
        return json.errorResponse(allocator, "SYSTEM_ERROR", "Failed to get roadmap path");
    };
    defer allocator.free(roadmap_path);

    // Validate roadmap exists
    if (!path.fileExists(roadmap_path)) {
        return json.errorResponse(allocator, "ROADMAP_NOT_FOUND", "Selected roadmap no longer exists");
    }

    // Open connection
    var conn = connection.Connection.open(allocator, roadmap_path) catch {
        return json.errorResponse(allocator, "DB_ERROR", "Failed to open roadmap database");
    };
    defer conn.close(allocator);

    // Get current time before deletion
    const now = time.nowUtc(allocator) catch {
        return json.errorResponse(allocator, "SYSTEM_ERROR", "Failed to get current time");
    };
    defer allocator.free(now);

    // Log operation before deletion
    queries.logOperation(conn, "DELETE", "task", task_id, now) catch {};

    // Delete task
    queries.deleteTask(conn, task_id) catch {
        return json.errorResponse(allocator, "DB_ERROR", "Failed to delete task");
    };

    // Build response
    const response = try std.fmt.allocPrint(allocator, "{{\"id\":{d},\"deleted_at\":\"{s}\"}}", .{ task_id, now });
    defer allocator.free(response);

    return json.success(allocator, response);
}

// ============== HELPER FUNCTIONS ==============

fn getTaskStatus(conn: connection.Connection, task_id: i64) !TaskStatus {
    const c = @cImport({
        @cInclude("sqlite3.h");
    });

    const sql = "SELECT status FROM tasks WHERE id = ?";
    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), sql.ptr, @intCast(sql.len), &stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    _ = c.sqlite3_bind_int64(stmt, 1, task_id);

    const step_rc = c.sqlite3_step(stmt);
    if (step_rc != c.SQLITE_ROW) return error.TaskNotFound;

    const status_text = std.mem.span(c.sqlite3_column_text(stmt, 0));
    return TaskStatus.fromString(status_text);
}

fn fetchTasksJson(allocator: std.mem.Allocator, conn: connection.Connection, status_filter: ?TaskStatus) ![]const u8 {
    const c = @cImport({
        @cInclude("sqlite3.h");
    });

    var sql: []const u8 = undefined;
    if (status_filter) |_| {
        sql = "SELECT id, priority, severity, status, description, specialists, action, expected_result, created_at FROM tasks WHERE status = ? ORDER BY priority DESC, severity DESC";
    } else {
        sql = "SELECT id, priority, severity, status, description, specialists, action, expected_result, created_at FROM tasks ORDER BY priority DESC, severity DESC";
    }

    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), sql.ptr, @intCast(sql.len), &stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    if (status_filter) |s| {
        const status_str = s.toString();
        _ = c.sqlite3_bind_text(stmt, 1, status_str.ptr, @intCast(status_str.len), c.SQLITE_STATIC);
    }

    var tasks: std.array_list.Aligned([]const u8, null) = .empty;
    defer {
        for (tasks.items) |t| {
            allocator.free(t);
        }
        tasks.deinit(allocator);
    }

    while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
        const id = c.sqlite3_column_int64(stmt, 0);
        const priority = c.sqlite3_column_int(stmt, 1);
        const severity = c.sqlite3_column_int(stmt, 2);
        const status = std.mem.span(c.sqlite3_column_text(stmt, 3));
        const description = std.mem.span(c.sqlite3_column_text(stmt, 4));
        const specialists_ptr = c.sqlite3_column_text(stmt, 5);
        const action = std.mem.span(c.sqlite3_column_text(stmt, 6));
        const expected_result = std.mem.span(c.sqlite3_column_text(stmt, 7));
        const created_at = std.mem.span(c.sqlite3_column_text(stmt, 8));

        const specialists: ?[]const u8 = if (specialists_ptr) |p| std.mem.span(p) else null;

        const task_json = if (specialists) |s|
            try std.fmt.allocPrint(allocator, "{{\"id\":{d},\"priority\":{d},\"severity\":{d},\"status\":\"{s}\",\"description\":\"{s}\",\"specialists\":\"{s}\",\"action\":\"{s}\",\"expected_result\":\"{s}\",\"created_at\":\"{s}\"}}", .{
                id, priority, severity, status, description, s, action, expected_result, created_at,
            })
        else
            try std.fmt.allocPrint(allocator, "{{\"id\":{d},\"priority\":{d},\"severity\":{d},\"status\":\"{s}\",\"description\":\"{s}\",\"action\":\"{s}\",\"expected_result\":\"{s}\",\"created_at\":\"{s}\"}}", .{
                id, priority, severity, status, description, action, expected_result, created_at,
            });

        try tasks.append(allocator, task_json);
    }

    const tasks_str = try std.mem.join(allocator, ",", tasks.items);
    defer allocator.free(tasks_str);

    return std.fmt.allocPrint(allocator, "{{\"count\":{d},\"tasks\":[{s}]}}", .{ tasks.items.len, tasks_str });
}

fn executeTaskUpdate(allocator: std.mem.Allocator, conn: connection.Connection, task_id: i64, updates: TaskUpdate) !void {
    const c = @cImport({
        @cInclude("sqlite3.h");
    });

    // Build update parts
    var parts: std.array_list.Aligned([]const u8, null) = .empty;
    defer parts.deinit(allocator);

    if (updates.priority) |_| {
        try parts.append(allocator, "priority = ?");
    }
    if (updates.severity) |_| {
        try parts.append(allocator, "severity = ?");
    }
    if (updates.description) |_| {
        try parts.append(allocator, "description = ?");
    }
    if (updates.specialists) |_| {
        try parts.append(allocator, "specialists = ?");
    }
    if (updates.action) |_| {
        try parts.append(allocator, "action = ?");
    }
    if (updates.expected_result) |_| {
        try parts.append(allocator, "expected_result = ?");
    }

    if (parts.items.len == 0) return; // Nothing to update

    const set_clause = try std.mem.join(allocator, ", ", parts.items);
    defer allocator.free(set_clause);

    const sql = try std.fmt.allocPrint(allocator, "UPDATE tasks SET {s} WHERE id = ?", .{set_clause});
    defer allocator.free(sql);

    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), sql.ptr, @intCast(sql.len), &stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    // Bind parameters
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

    _ = c.sqlite3_bind_int64(stmt, idx, task_id);

    const step_rc = c.sqlite3_step(stmt);
    if (step_rc != c.SQLITE_DONE) return error.StepFailed;
}

// ============== TESTS ==============

test "TaskInput struct" {
    const input = TaskInput{
        .priority = 5,
        .severity = 3,
        .description = "Test task",
        .specialists = null,
        .action = "Do something",
        .expected_result = "Success",
    };
    try std.testing.expectEqual(@as(i32, 5), input.priority);
    try std.testing.expectEqual(@as(i32, 3), input.severity);
}

test "TaskUpdate struct" {
    const update = TaskUpdate{
        .priority = 7,
        .severity = null,
        .description = null,
        .specialists = null,
        .action = null,
        .expected_result = null,
    };
    try std.testing.expectEqual(@as(i32, 7), update.priority.?);
    try std.testing.expectEqual(@as(?i32, null), update.severity);
}
