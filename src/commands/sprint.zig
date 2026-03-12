const std = @import("std");
const path = @import("../utils/path.zig");
const json = @import("../utils/json.zig");
const time = @import("../utils/time.zig");
const connection = @import("../db/connection.zig");
const queries = @import("../db/queries.zig");
const Sprint = @import("../models/sprint.zig").Sprint;
const SprintStatus = @import("../models/sprint.zig").SprintStatus;
const roadmap = @import("roadmap.zig");

/// Adds a new sprint to the current roadmap
pub fn addSprint(allocator: std.mem.Allocator, description: []const u8) ![]const u8 {
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

    // Insert sprint
    const sprint_id = queries.insertSprint(conn, description, now) catch {
        return json.errorResponse(allocator, "DB_ERROR", "Failed to insert sprint");
    };

    // Log operation
    queries.logOperation(conn, "CREATE", "sprint", sprint_id, now) catch {};

    // Build response
    const response = try std.fmt.allocPrint(allocator, "{{\"id\":{d},\"description\":\"{s}\",\"status\":\"PENDING\",\"created_at\":\"{s}\"}}", .{
        sprint_id, description, now,
    });
    defer allocator.free(response);

    return json.success(allocator, response);
}

/// Opens a sprint (changes status from PENDING to OPEN)
pub fn openSprint(allocator: std.mem.Allocator, sprint_id: i64) ![]const u8 {
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

    // Verify sprint exists and get current status
    const current_status = getSprintStatus(conn, sprint_id) catch {
        return json.errorResponse(allocator, "SPRINT_NOT_FOUND", "Sprint not found");
    };

    // Validate transition (must be PENDING to OPEN)
    if (current_status != .PENDING) {
        return json.errorResponse(allocator, "INVALID_STATUS", "Sprint must be in PENDING status to open");
    }

    // Get current time
    const now = time.nowUtc(allocator) catch {
        return json.errorResponse(allocator, "SYSTEM_ERROR", "Failed to get current time");
    };
    defer allocator.free(now);

    // Update sprint status
    queries.updateSprintStatus(conn, sprint_id, .OPEN) catch {
        return json.errorResponse(allocator, "DB_ERROR", "Failed to update sprint status");
    };

    // Log operation
    queries.logOperation(conn, "OPEN", "sprint", sprint_id, now) catch {};

    // Build response
    const response = try std.fmt.allocPrint(allocator, "{{\"id\":{d},\"previous_status\":\"PENDING\",\"new_status\":\"OPEN\",\"opened_at\":\"{s}\"}}", .{
        sprint_id, now,
    });
    defer allocator.free(response);

    return json.success(allocator, response);
}

/// Closes a sprint (changes status from OPEN to CLOSED)
pub fn closeSprint(allocator: std.mem.Allocator, sprint_id: i64) ![]const u8 {
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

    // Verify sprint exists and get current status
    const current_status = getSprintStatus(conn, sprint_id) catch {
        return json.errorResponse(allocator, "SPRINT_NOT_FOUND", "Sprint not found");
    };

    // Validate transition (must be OPEN to CLOSED)
    if (current_status != .OPEN) {
        return json.errorResponse(allocator, "INVALID_STATUS", "Sprint must be in OPEN status to close");
    }

    // Get current time
    const now = time.nowUtc(allocator) catch {
        return json.errorResponse(allocator, "SYSTEM_ERROR", "Failed to get current time");
    };
    defer allocator.free(now);

    // Update sprint status
    queries.updateSprintStatus(conn, sprint_id, .CLOSED) catch {
        return json.errorResponse(allocator, "DB_ERROR", "Failed to update sprint status");
    };

    // Log operation
    queries.logOperation(conn, "CLOSE", "sprint", sprint_id, now) catch {};

    // Build response
    const response = try std.fmt.allocPrint(allocator, "{{\"id\":{d},\"previous_status\":\"OPEN\",\"new_status\":\"CLOSED\",\"closed_at\":\"{s}\"}}", .{
        sprint_id, now,
    });
    defer allocator.free(response);

    return json.success(allocator, response);
}

/// Lists all sprints
pub fn listSprints(allocator: std.mem.Allocator, status_filter: ?SprintStatus) ![]const u8 {
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

    // Fetch sprints
    const sprints_json = try fetchSprintsJson(allocator, conn, status_filter);
    defer allocator.free(sprints_json);

    return json.success(allocator, sprints_json);
}

/// Adds a task to a sprint
pub fn addTaskToSprint(allocator: std.mem.Allocator, sprint_id: i64, task_id: i64) ![]const u8 {
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

    // Add task to sprint
    queries.addTaskToSprint(conn, sprint_id, task_id, now) catch {
        return json.errorResponse(allocator, "DB_ERROR", "Failed to add task to sprint");
    };

    // Log operation
    queries.logOperation(conn, "ADD_TASK", "sprint", sprint_id, now) catch {};

    // Build response
    const response = try std.fmt.allocPrint(allocator, "{{\"sprint_id\":{d},\"task_id\":{d},\"added_at\":\"{s}\"}}", .{
        sprint_id, task_id, now,
    });
    defer allocator.free(response);

    return json.success(allocator, response);
}

/// Removes a task from a sprint
pub fn removeTaskFromSprint(allocator: std.mem.Allocator, task_id: i64) ![]const u8 {
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

    // Remove task from sprint
    queries.removeTaskFromSprint(conn, task_id) catch {
        return json.errorResponse(allocator, "DB_ERROR", "Failed to remove task from sprint");
    };

    // Log operation
    queries.logOperation(conn, "REMOVE_TASK", "task", task_id, now) catch {};

    // Build response
    const response = try std.fmt.allocPrint(allocator, "{{\"task_id\":{d},\"removed_at\":\"{s}\"}}", .{ task_id, now });
    defer allocator.free(response);

    return json.success(allocator, response);
}

// ============== HELPER FUNCTIONS ==============

fn getSprintStatus(conn: connection.Connection, sprint_id: i64) !SprintStatus {
    const c = @cImport({
        @cInclude("sqlite3.h");
    });

    const sql = "SELECT status FROM sprints WHERE id = ?";
    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), sql.ptr, @intCast(sql.len), &stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    _ = c.sqlite3_bind_int64(stmt, 1, sprint_id);

    const step_rc = c.sqlite3_step(stmt);
    if (step_rc != c.SQLITE_ROW) return error.SprintNotFound;

    const status_text = std.mem.span(c.sqlite3_column_text(stmt, 0));
    return SprintStatus.fromString(status_text);
}

fn fetchSprintsJson(allocator: std.mem.Allocator, conn: connection.Connection, status_filter: ?SprintStatus) ![]const u8 {
    const c = @cImport({
        @cInclude("sqlite3.h");
    });

    var sql: []const u8 = undefined;
    if (status_filter) |_| {
        sql = "SELECT id, status, description, created_at, started_at, closed_at FROM sprints WHERE status = ? ORDER BY created_at DESC";
    } else {
        sql = "SELECT id, status, description, created_at, started_at, closed_at FROM sprints ORDER BY created_at DESC";
    }

    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), sql.ptr, @intCast(sql.len), &stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    if (status_filter) |s| {
        const status_str = s.toString();
        _ = c.sqlite3_bind_text(stmt, 1, status_str.ptr, @intCast(status_str.len), c.SQLITE_STATIC);
    }

    var sprints: std.array_list.Aligned([]const u8, null) = .empty;
    defer {
        for (sprints.items) |s| {
            allocator.free(s);
        }
        sprints.deinit(allocator);
    }

    while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
        const id = c.sqlite3_column_int64(stmt, 0);
        const status = std.mem.span(c.sqlite3_column_text(stmt, 1));
        const description = std.mem.span(c.sqlite3_column_text(stmt, 2));
        const created_at = std.mem.span(c.sqlite3_column_text(stmt, 3));

        const started_at_ptr = c.sqlite3_column_text(stmt, 4);
        const closed_at_ptr = c.sqlite3_column_text(stmt, 5);

        const started_at: ?[]const u8 = if (started_at_ptr) |p| std.mem.span(p) else null;
        const closed_at: ?[]const u8 = if (closed_at_ptr) |p| std.mem.span(p) else null;

        const sprint_json = if (started_at) |s| (
            if (closed_at) |cl|
                try std.fmt.allocPrint(allocator, "{{\"id\":{d},\"status\":\"{s}\",\"description\":\"{s}\",\"created_at\":\"{s}\",\"started_at\":\"{s}\",\"closed_at\":\"{s}\"}}", .{
                    id, status, description, created_at, s, cl,
                })
            else
                try std.fmt.allocPrint(allocator, "{{\"id\":{d},\"status\":\"{s}\",\"description\":\"{s}\",\"created_at\":\"{s}\",\"started_at\":\"{s}\"}}", .{
                    id, status, description, created_at, s,
                })
        ) else (
            try std.fmt.allocPrint(allocator, "{{\"id\":{d},\"status\":\"{s}\",\"description\":\"{s}\",\"created_at\":\"{s}\"}}", .{
                id, status, description, created_at,
            })
        );

        try sprints.append(allocator, sprint_json);
    }

    const sprints_str = try std.mem.join(allocator, ",", sprints.items);
    defer allocator.free(sprints_str);

    return std.fmt.allocPrint(allocator, "{{\"count\":{d},\"sprints\":[{s}]}}", .{ sprints.items.len, sprints_str });
}
