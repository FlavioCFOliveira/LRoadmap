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

    const task = Task{
        .id = 0,
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

    const task_id = try queries.insertTask(conn, task);
    try queries.logOperation(conn, "TASK_CREATE", "task", task_id, now);

    const created_task = try queries.getTaskById(allocator, conn, task_id);
    defer {
        var t = created_task;
        t.deinit(allocator);
    }

    const task_json = try created_task.toJson(allocator);
    defer allocator.free(task_json);

    return json.success(allocator, task_json);
}

/// Lists tasks with optional status filter
pub fn listTasks(allocator: std.mem.Allocator, status_filter: ?TaskStatus) ![]const u8 {
    const current = try roadmap.getCurrentRoadmap(allocator) orelse {
        return json.errorResponse(allocator, "NO_ROADMAP", "No roadmap selected. Use 'rmp roadmap use <name>' first");
    };
    defer allocator.free(current);

    const roadmap_path = try path.getRoadmapPath(allocator, current);
    defer allocator.free(roadmap_path);

    var conn = try connection.Connection.open(allocator, roadmap_path);
    defer conn.close(allocator);

    const tasks = try queries.listTasks(allocator, conn, status_filter);
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

    const result = try std.fmt.allocPrint(allocator, "{{\"roadmap\":\"{s}\",\"count\":{d},\"tasks\":[{s}]}}", .{ current, tasks.len, tasks_str });
    defer allocator.free(result);

    return json.success(allocator, result);
}

/// Gets a single task by ID
pub fn getTask(allocator: std.mem.Allocator, task_id: i64) ![]const u8 {
    const current = try roadmap.getCurrentRoadmap(allocator) orelse {
        return json.errorResponse(allocator, "NO_ROADMAP", "No roadmap selected. Use 'rmp roadmap use <name>' first");
    };
    defer allocator.free(current);

    const roadmap_path = try path.getRoadmapPath(allocator, current);
    defer allocator.free(roadmap_path);

    var conn = try connection.Connection.open(allocator, roadmap_path);
    defer conn.close(allocator);

    var task_obj = queries.getTaskById(allocator, conn, task_id) catch |err| {
        if (err == error.TaskNotFound) {
            const details = try std.fmt.allocPrint(allocator, "{{\"roadmap\":\"{s}\",\"missing_ids\":[{d}]}}", .{ current, task_id });
            defer allocator.free(details);
            const msg = try std.fmt.allocPrint(allocator, "Task with ID {d} not found in roadmap '{s}'", .{ task_id, current });
            defer allocator.free(msg);
            return json.errorResponseWithDetails(allocator, "TASK_NOT_FOUND", msg, details);
        }
        return err;
    };
    defer task_obj.deinit(allocator);

    const task_json = try task_obj.toJson(allocator);
    defer allocator.free(task_json);

    return json.success(allocator, task_json);
}

/// Changes the status of a task
pub fn changeTaskStatus(allocator: std.mem.Allocator, task_id: i64, new_status: TaskStatus) ![]const u8 {
    const current = try roadmap.getCurrentRoadmap(allocator) orelse {
        return json.errorResponse(allocator, "NO_ROADMAP", "No roadmap selected. Use 'rmp roadmap use <name>' first");
    };
    defer allocator.free(current);

    const roadmap_path = try path.getRoadmapPath(allocator, current);
    defer allocator.free(roadmap_path);

    var conn = try connection.Connection.open(allocator, roadmap_path);
    defer conn.close(allocator);

    var task_obj = queries.getTaskById(allocator, conn, task_id) catch |err| {
        if (err == error.TaskNotFound) {
            const details = try std.fmt.allocPrint(allocator, "{{\"roadmap\":\"{s}\",\"missing_ids\":[{d}]}}", .{ current, task_id });
            defer allocator.free(details);
            const msg = try std.fmt.allocPrint(allocator, "Task with ID {d} not found in roadmap '{s}'", .{ task_id, current });
            defer allocator.free(msg);
            return json.errorResponseWithDetails(allocator, "TASK_NOT_FOUND", msg, details);
        }
        return err;
    };
    defer task_obj.deinit(allocator);

    if (!task_obj.status.isValidTransition(new_status)) {
        return json.errorResponse(allocator, "INVALID_STATUS", "Invalid status transition");
    }

    try queries.updateTaskStatus(conn, task_id, new_status);

    const now = try time.nowUtc(allocator);
    defer allocator.free(now);

    if (new_status == .COMPLETED) {
        try queries.updateTaskCompletedAt(conn, task_id, now);
    } else if (task_obj.status == .COMPLETED) {
        try queries.updateTaskCompletedAt(conn, task_id, null);
    }

    try queries.logOperation(conn, "TASK_STATUS_CHANGE", "task", task_id, now);

    const response = try std.fmt.allocPrint(allocator, "{{\"id\":{d},\"previous_status\":\"{s}\",\"new_status\":\"{s}\",\"changed_at\":\"{s}\"}}", .{
        task_id, task_obj.status.toString(), new_status.toString(), now,
    });
    defer allocator.free(response);

    return json.success(allocator, response);
}

/// Sets the priority of a task
pub fn setPriority(allocator: std.mem.Allocator, task_id: i64, priority: i32) ![]const u8 {
    const current = try roadmap.getCurrentRoadmap(allocator) orelse {
        return json.errorResponse(allocator, "NO_ROADMAP", "No roadmap selected. Use 'rmp roadmap use <name>' first");
    };
    defer allocator.free(current);

    const roadmap_path = try path.getRoadmapPath(allocator, current);
    defer allocator.free(roadmap_path);

    var conn = try connection.Connection.open(allocator, roadmap_path);
    defer conn.close(allocator);

    // Verify task exists
    var task_obj = try queries.getTaskById(allocator, conn, task_id);
    task_obj.deinit(allocator);

    try queries.updateTaskPriority(conn, task_id, priority);

    const now = try time.nowUtc(allocator);
    defer allocator.free(now);

    try queries.logOperation(conn, "TASK_PRIORITY_CHANGE", "task", task_id, now);

    const response = try std.fmt.allocPrint(allocator, "{{\"id\":{d},\"new_priority\":{d},\"changed_at\":\"{s}\"}}", .{
        task_id, priority, now,
    });
    defer allocator.free(response);

    return json.success(allocator, response);
}

/// Sets the severity of a task
pub fn setSeverity(allocator: std.mem.Allocator, task_id: i64, severity: i32) ![]const u8 {
    const current = try roadmap.getCurrentRoadmap(allocator) orelse {
        return json.errorResponse(allocator, "NO_ROADMAP", "No roadmap selected. Use 'rmp roadmap use <name>' first");
    };
    defer allocator.free(current);

    const roadmap_path = try path.getRoadmapPath(allocator, current);
    defer allocator.free(roadmap_path);

    var conn = try connection.Connection.open(allocator, roadmap_path);
    defer conn.close(allocator);

    // Verify task exists
    var task_obj = try queries.getTaskById(allocator, conn, task_id);
    task_obj.deinit(allocator);

    try queries.updateTaskSeverity(conn, task_id, severity);

    const now = try time.nowUtc(allocator);
    defer allocator.free(now);

    try queries.logOperation(conn, "TASK_SEVERITY_CHANGE", "task", task_id, now);

    const response = try std.fmt.allocPrint(allocator, "{{\"id\":{d},\"new_severity\":{d},\"changed_at\":\"{s}\"}}", .{
        task_id, severity, now,
    });
    defer allocator.free(response);

    return json.success(allocator, response);
}

/// Edits a task
pub fn editTask(allocator: std.mem.Allocator, task_id: i64, updates: Task.TaskUpdate) ![]const u8 {
    const current = try roadmap.getCurrentRoadmap(allocator) orelse {
        return json.errorResponse(allocator, "NO_ROADMAP", "No roadmap selected. Use 'rmp roadmap use <name>' first");
    };
    defer allocator.free(current);

    const roadmap_path = try path.getRoadmapPath(allocator, current);
    defer allocator.free(roadmap_path);

    var conn = try connection.Connection.open(allocator, roadmap_path);
    defer conn.close(allocator);

    // Verify task exists
    var task_obj = try queries.getTaskById(allocator, conn, task_id);
    task_obj.deinit(allocator);

    try queries.updateTask(allocator, conn, task_id, updates);

    const now = try time.nowUtc(allocator);
    defer allocator.free(now);

    try queries.logOperation(conn, "TASK_UPDATE", "task", task_id, now);

    const response = try std.fmt.allocPrint(allocator, "{{\"id\":{d},\"message\":\"Task updated successfully\",\"updated_at\":\"{s}\"}}", .{ task_id, now });
    defer allocator.free(response);

    return json.success(allocator, response);
}

/// Deletes a task
pub fn deleteTask(allocator: std.mem.Allocator, task_id: i64) ![]const u8 {
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

    try queries.logOperation(conn, "TASK_DELETE", "task", task_id, now);
    try queries.deleteTask(conn, task_id);

    const response = try std.fmt.allocPrint(allocator, "{{\"id\":{d},\"deleted_at\":\"{s}\"}}", .{ task_id, now });
    defer allocator.free(response);

    return json.success(allocator, response);
}

