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
    queries.logOperation(conn, "SPRINT_CREATE", "sprint", sprint_id, now) catch {};

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
    var sprint_obj = queries.getSprintById(allocator, conn, sprint_id) catch |err| {
        if (err == error.SprintNotFound) {
            const details = try std.fmt.allocPrint(allocator, "{{\"roadmap\":\"{s}\",\"sprint_id\":{d}}}", .{ current, sprint_id });
            defer allocator.free(details);
            const msg = try std.fmt.allocPrint(allocator, "Sprint with ID {d} not found in roadmap '{s}'", .{ sprint_id, current });
            defer allocator.free(msg);
            return json.errorResponseWithDetails(allocator, "SPRINT_NOT_FOUND", msg, details);
        }
        return err;
    };
    defer sprint_obj.deinit(allocator);

    // Validate transition (must be PENDING to OPEN)
    if (sprint_obj.status != .PENDING) {
        return json.errorResponse(allocator, "INVALID_STATUS", "Sprint must be in PENDING status to open");
    }

    // Get current time
    const now = time.nowUtc(allocator) catch {
        return json.errorResponse(allocator, "SYSTEM_ERROR", "Failed to get current time");
    };
    defer allocator.free(now);

    // Update sprint status and started_at
    queries.updateSprintStatus(conn, sprint_id, .OPEN) catch {
        return json.errorResponse(allocator, "DB_ERROR", "Failed to update sprint status");
    };
    queries.updateSprintStartedAt(conn, sprint_id, now) catch {};

    // Log operation
    queries.logOperation(conn, "SPRINT_START", "sprint", sprint_id, now) catch {};

    // Build response
    const response = try std.fmt.allocPrint(allocator, "{{\"id\":{d},\"previous_status\":\"PENDING\",\"new_status\":\"OPEN\",\"started_at\":\"{s}\"}}", .{
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
    var sprint_obj = queries.getSprintById(allocator, conn, sprint_id) catch |err| {
        if (err == error.SprintNotFound) {
            const details = try std.fmt.allocPrint(allocator, "{{\"roadmap\":\"{s}\",\"sprint_id\":{d}}}", .{ current, sprint_id });
            defer allocator.free(details);
            const msg = try std.fmt.allocPrint(allocator, "Sprint with ID {d} not found in roadmap '{s}'", .{ sprint_id, current });
            defer allocator.free(msg);
            return json.errorResponseWithDetails(allocator, "SPRINT_NOT_FOUND", msg, details);
        }
        return err;
    };
    defer sprint_obj.deinit(allocator);

    // Validate transition (must be OPEN to CLOSED)
    if (sprint_obj.status != .OPEN) {
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
    queries.logOperation(conn, "SPRINT_CLOSE", "sprint", sprint_id, now) catch {};

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
    var conn = try connection.Connection.open(allocator, roadmap_path);
    defer conn.close(allocator);

    // Fetch sprints
    const sprints = try queries.listSprints(allocator, conn, status_filter);
    defer {
        for (sprints) |*s| s.deinit(allocator);
        allocator.free(sprints);
    }

    var json_sprints: std.ArrayListUnmanaged([]const u8) = .empty;
    defer {
        for (json_sprints.items) |js| allocator.free(js);
        json_sprints.deinit(allocator);
    }

    for (sprints) |s| {
        try json_sprints.append(allocator, try s.toJson(allocator));
    }

    const sprints_str = try std.mem.join(allocator, ",", json_sprints.items);
    defer allocator.free(sprints_str);

    const result = try std.fmt.allocPrint(allocator, "{{\"count\":{d},\"sprints\":[{s}]}}", .{ sprints.len, sprints_str });
    defer allocator.free(result);

    return json.success(allocator, result);
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

    // Update task status to SPRINT as per spec
    try queries.updateTaskStatus(conn, task_id, .SPRINT);

    // Log operation
    queries.logOperation(conn, "SPRINT_ADD_TASK", "sprint", sprint_id, now) catch {};

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
    const roadmap_path = try path.getRoadmapPath(allocator, current);
    defer allocator.free(roadmap_path);

    // Open connection
    var conn = try connection.Connection.open(allocator, roadmap_path);
    defer conn.close(allocator);

    // Get current time
    const now = try time.nowUtc(allocator);
    defer allocator.free(now);

    // Get sprint ID before removing task for audit
    const maybe_sprint_id = try queries.getSprintIdByTaskId(conn, task_id);

    // Remove task from sprint
    try queries.removeTaskFromSprint(conn, task_id);

    // Return task to BACKLOG state as per spec
    try queries.updateTaskStatus(conn, task_id, .BACKLOG);

    // Log operation
    if (maybe_sprint_id) |sprint_id| {
        try queries.logOperation(conn, "SPRINT_REMOVE_TASK", "sprint", sprint_id, now);
    }

    // Build response
    const response = try std.fmt.allocPrint(allocator, "{{\"task_id\":{d},\"removed_at\":\"{s}\"}}", .{ task_id, now });
    defer allocator.free(response);

    return json.success(allocator, response);
}

/// Gets a sprint by ID
pub fn getSprint(allocator: std.mem.Allocator, sprint_id: i64) ![]const u8 {
    const current = try roadmap.getCurrentRoadmap(allocator) orelse {
        return json.errorResponse(allocator, "NO_ROADMAP", "No roadmap selected. Use 'rmp roadmap use <name>' first");
    };
    defer allocator.free(current);

    const roadmap_path = try path.getRoadmapPath(allocator, current);
    defer allocator.free(roadmap_path);

    var conn = try connection.Connection.open(allocator, roadmap_path);
    defer conn.close(allocator);

    var sprint_obj = queries.getSprintById(allocator, conn, sprint_id) catch |err| {
        if (err == error.SprintNotFound) {
            return json.errorResponse(allocator, "SPRINT_NOT_FOUND", try std.fmt.allocPrint(allocator, "Sprint {d} not found", .{sprint_id}));
        }
        return err;
    };
    defer sprint_obj.deinit(allocator);

    const sprint_json = try sprint_obj.toJson(allocator);
    defer allocator.free(sprint_json);

    return json.success(allocator, sprint_json);
}

/// Lists tasks in a sprint with optional status filter
pub fn listSprintTasks(allocator: std.mem.Allocator, sprint_id: i64, status_filter: ?@import("../models/task.zig").TaskStatus) ![]const u8 {
    const current = try roadmap.getCurrentRoadmap(allocator) orelse {
        return json.errorResponse(allocator, "NO_ROADMAP", "No roadmap selected. Use 'rmp roadmap use <name>' first");
    };
    defer allocator.free(current);

    const roadmap_path = try path.getRoadmapPath(allocator, current);
    defer allocator.free(roadmap_path);

    var conn = try connection.Connection.open(allocator, roadmap_path);
    defer conn.close(allocator);

    const tasks = try queries.getTasksBySprintFiltered(allocator, conn, sprint_id, status_filter);
    defer {
        for (tasks) |*t| t.deinit(allocator);
        allocator.free(tasks);
    }

    var json_tasks: std.ArrayListUnmanaged([]const u8) = .empty;
    defer {
        for (json_tasks.items) |jt| allocator.free(jt);
        json_tasks.deinit(allocator);
    }

    for (tasks) |t| {
        try json_tasks.append(allocator, try t.toJson(allocator));
    }

    const tasks_str = try std.mem.join(allocator, ",", json_tasks.items);
    defer allocator.free(tasks_str);

    const result = if (status_filter) |s|
        try std.fmt.allocPrint(allocator, "{{\"sprint_id\":{d},\"count\":{d},\"status_filter\":\"{s}\",\"tasks\":[{s}]}}", .{ sprint_id, tasks.len, s.toString(), tasks_str })
    else
        try std.fmt.allocPrint(allocator, "{{\"sprint_id\":{d},\"count\":{d},\"tasks\":[{s}]}}", .{ sprint_id, tasks.len, tasks_str });
    defer allocator.free(result);

    return json.success(allocator, result);
}

/// Updates a sprint description
pub fn updateSprint(allocator: std.mem.Allocator, sprint_id: i64, description: []const u8) ![]const u8 {
    const current = try roadmap.getCurrentRoadmap(allocator) orelse {
        return json.errorResponse(allocator, "NO_ROADMAP", "No roadmap selected. Use 'rmp roadmap use <name>' first");
    };
    defer allocator.free(current);

    const roadmap_path = try path.getRoadmapPath(allocator, current);
    defer allocator.free(roadmap_path);

    var conn = try connection.Connection.open(allocator, roadmap_path);
    defer conn.close(allocator);

    try queries.updateSprintDescription(conn, sprint_id, description);

    const now = try time.nowUtc(allocator);
    defer allocator.free(now);

    try queries.logOperation(conn, "SPRINT_UPDATE", "sprint", sprint_id, now);

    const response = try std.fmt.allocPrint(allocator, "{{\"id\":{d},\"description\":\"{s}\",\"updated_at\":\"{s}\"}}", .{ sprint_id, description, now });
    defer allocator.free(response);

    return json.success(allocator, response);
}

/// Reopens a sprint (CLOSED -> OPEN)
pub fn reopenSprint(allocator: std.mem.Allocator, sprint_id: i64) ![]const u8 {
    const current = try roadmap.getCurrentRoadmap(allocator) orelse {
        return json.errorResponse(allocator, "NO_ROADMAP", "No roadmap selected. Use 'rmp roadmap use <name>' first");
    };
    defer allocator.free(current);

    const roadmap_path = try path.getRoadmapPath(allocator, current);
    defer allocator.free(roadmap_path);

    var conn = try connection.Connection.open(allocator, roadmap_path);
    defer conn.close(allocator);

    const sprint_obj = try queries.getSprintById(allocator, conn, sprint_id);
    defer {
        var s = sprint_obj;
        s.deinit(allocator);
    }

    if (sprint_obj.status != .CLOSED) {
        return json.errorResponse(allocator, "INVALID_STATUS", "Only CLOSED sprints can be reopened");
    }

    try queries.updateSprintStatus(conn, sprint_id, .OPEN);
    try queries.updateSprintClosedAt(conn, sprint_id, null);

    const now = try time.nowUtc(allocator);
    defer allocator.free(now);

    try queries.logOperation(conn, "SPRINT_REOPEN", "sprint", sprint_id, now);

    const response = try std.fmt.allocPrint(allocator, "{{\"id\":{d},\"previous_status\":\"CLOSED\",\"new_status\":\"OPEN\",\"reopened_at\":\"{s}\"}}", .{ sprint_id, now });
    defer allocator.free(response);

    return json.success(allocator, response);
}

/// Gets sprint statistics
pub fn getSprintStats(allocator: std.mem.Allocator, sprint_id: i64) ![]const u8 {
    const current = try roadmap.getCurrentRoadmap(allocator) orelse {
        return json.errorResponse(allocator, "NO_ROADMAP", "No roadmap selected. Use 'rmp roadmap use <name>' first");
    };
    defer allocator.free(current);

    const roadmap_path = try path.getRoadmapPath(allocator, current);
    defer allocator.free(roadmap_path);

    var conn = try connection.Connection.open(allocator, roadmap_path);
    defer conn.close(allocator);

    const stats = try queries.getSprintStats(conn, sprint_id);

    // Convert stats to JSON manually since SprintStats doesn't have toJson
    const response = try std.fmt.allocPrint(allocator,
        \\{{"id":{d},"total_tasks":{d},"completion_percentage":{d},"by_status":{{"BACKLOG":{d},"SPRINT":{d},"DOING":{d},"TESTING":{d},"COMPLETED":{d}}}}}
    , .{
        sprint_id,
        stats.total_tasks,
        stats.completion_percentage,
        stats.by_status.backlog,
        stats.by_status.sprint,
        stats.by_status.doing,
        stats.by_status.testing,
        stats.by_status.completed,
    });
    defer allocator.free(response);

    return json.success(allocator, response);
}

/// Deletes a sprint
pub fn deleteSprint(allocator: std.mem.Allocator, sprint_id: i64) ![]const u8 {
    const current = try roadmap.getCurrentRoadmap(allocator) orelse {
        return json.errorResponse(allocator, "NO_ROADMAP", "No roadmap selected. Use 'rmp roadmap use <name>' first");
    };
    defer allocator.free(current);

    const roadmap_path = try path.getRoadmapPath(allocator, current);
    defer allocator.free(roadmap_path);

    var conn = try connection.Connection.open(allocator, roadmap_path);
    defer conn.close(allocator);

    const now = try time.nowUtc(allocator);
    defer allocator.free(now);

    try queries.logOperation(conn, "SPRINT_DELETE", "sprint", sprint_id, now);
    try queries.deleteSprint(conn, sprint_id);

    const response = try std.fmt.allocPrint(allocator, "{{\"id\":{d},\"deleted_at\":\"{s}\"}}", .{ sprint_id, now });
    defer allocator.free(response);

    return json.success(allocator, response);
}

/// Moves a task between sprints
pub fn moveTaskBetweenSprints(allocator: std.mem.Allocator, task_id: i64, new_sprint_id: i64) ![]const u8 {
    const current = try roadmap.getCurrentRoadmap(allocator) orelse {
        return json.errorResponse(allocator, "NO_ROADMAP", "No roadmap selected. Use 'rmp roadmap use <name>' first");
    };
    defer allocator.free(current);

    const roadmap_path = try path.getRoadmapPath(allocator, current);
    defer allocator.free(roadmap_path);

    var conn = try connection.Connection.open(allocator, roadmap_path);
    defer conn.close(allocator);

    try queries.moveTaskBetweenSprints(conn, task_id, new_sprint_id);

    const now = try time.nowUtc(allocator);
    defer allocator.free(now);

    try queries.logOperation(conn, "SPRINT_MOVE_TASK", "sprint", new_sprint_id, now);

    const response = try std.fmt.allocPrint(allocator, "{{\"task_id\":{d},\"new_sprint_id\":{d},\"moved_at\":\"{s}\"}}", .{ task_id, new_sprint_id, now });
    defer allocator.free(response);

    return json.success(allocator, response);
}


fn fetchSprintsJson(allocator: std.mem.Allocator, conn: connection.Connection, status_filter: ?SprintStatus) ![]const u8 {
    const sprints = try queries.listSprints(allocator, conn, status_filter);
    defer {
        for (sprints) |*s| s.deinit(allocator);
        allocator.free(sprints);
    }

    var json_sprints: std.ArrayListUnmanaged([]const u8) = .empty;
    defer {
        for (json_sprints.items) |js| allocator.free(js);
        json_sprints.deinit(allocator);
    }

    for (sprints) |s| {
        try json_sprints.append(allocator, try s.toJson(allocator));
    }

    const sprints_str = try std.mem.join(allocator, ",", json_sprints.items);
    defer allocator.free(sprints_str);

    return std.fmt.allocPrint(allocator, "{{\"count\":{d},\"sprints\":[{s}]}}", .{ sprints.len, sprints_str });
}
