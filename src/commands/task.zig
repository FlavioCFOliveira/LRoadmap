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

/// Lists tasks with optional filters
pub fn listTasks(allocator: std.mem.Allocator, filters: queries.TaskFilterOptions) ![]const u8 {
    const current = try roadmap.getCurrentRoadmap(allocator) orelse {
        return json.errorResponse(allocator, "NO_ROADMAP", "No roadmap selected. Use 'rmp roadmap use <name>' first");
    };
    defer allocator.free(current);

    const roadmap_path = try path.getRoadmapPath(allocator, current);
    defer allocator.free(roadmap_path);

    var conn = try connection.Connection.open(allocator, roadmap_path);
    defer conn.close(allocator);

    const tasks = try queries.listTasks(allocator, conn, filters);
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

    // Build filters info for response
    var filter_parts: std.ArrayListUnmanaged([]const u8) = .empty;
    defer {
        for (filter_parts.items) |p| allocator.free(p);
        filter_parts.deinit(allocator);
    }

    if (filters.status) |s| {
        try filter_parts.append(allocator, try std.fmt.allocPrint(allocator, "\"status\":\"{s}\"", .{s.toString()}));
    }
    if (filters.priority_min) |p| {
        try filter_parts.append(allocator, try std.fmt.allocPrint(allocator, "\"priority_min\":{d}", .{p}));
    }
    if (filters.severity_min) |s| {
        try filter_parts.append(allocator, try std.fmt.allocPrint(allocator, "\"severity_min\":{d}", .{s}));
    }
    if (filters.limit) |l| {
        try filter_parts.append(allocator, try std.fmt.allocPrint(allocator, "\"limit\":{d}", .{l}));
    }

    const filters_str = if (filter_parts.items.len > 0)
        try std.mem.join(allocator, ",", filter_parts.items)
    else
        try allocator.dupe(u8, "");
    defer allocator.free(filters_str);

    const result = if (filters_str.len > 0)
        try std.fmt.allocPrint(allocator, "{{\"roadmap\":\"{s}\",\"count\":{d},\"filters\":{{{s}}},\"tasks\":[{s}]}}", .{ current, tasks.len, filters_str, tasks_str })
    else
        try std.fmt.allocPrint(allocator, "{{\"roadmap\":\"{s}\",\"count\":{d},\"tasks\":[{s}]}}", .{ current, tasks.len, tasks_str });
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

/// Changes the status of multiple tasks
pub fn changeTaskStatus(allocator: std.mem.Allocator, ids: []const i64, new_status: TaskStatus) ![]const u8 {
    const current = try roadmap.getCurrentRoadmap(allocator) orelse {
        return json.errorResponse(allocator, "NO_ROADMAP", "No roadmap selected. Use 'rmp roadmap use <name>' first");
    };
    defer allocator.free(current);

    const roadmap_path = try path.getRoadmapPath(allocator, current);
    defer allocator.free(roadmap_path);

    var conn = try connection.Connection.open(allocator, roadmap_path);
    defer conn.close(allocator);

    // Verify all tasks exist and check valid transitions
    const now = try time.nowUtc(allocator);
    defer allocator.free(now);

    const existing_ids = try queries.filterExistingTaskIds(allocator, conn, ids);
    defer allocator.free(existing_ids);

    if (existing_ids.len == 0) {
        const details = try std.fmt.allocPrint(allocator, "{{\"roadmap\":\"{s}\",\"missing_ids\":{any}}}", .{ current, ids });
        defer allocator.free(details);
        return json.errorResponseWithDetails(allocator, "TASKS_NOT_FOUND", "No tasks found with the provided IDs", details);
    }

    // Check for missing IDs
    if (existing_ids.len < ids.len) {
        var missing: std.ArrayListUnmanaged(i64) = .empty;
        defer missing.deinit(allocator);

        for (ids) |id| {
            var found = false;
            for (existing_ids) |existing| {
                if (id == existing) {
                    found = true;
                    break;
                }
            }
            if (!found) try missing.append(allocator, id);
        }

        const details = try std.fmt.allocPrint(allocator, "{{\"roadmap\":\"{s}\",\"missing_ids\":{any},\"found\":{d},\"requested\":{d}}}", .{ current, missing.items, existing_ids.len, ids.len });
        defer allocator.free(details);
        const msg = try std.fmt.allocPrint(allocator, "Only {d} of {d} tasks found in roadmap '{s}'", .{ existing_ids.len, ids.len, current });
        defer allocator.free(msg);
        return json.errorResponseWithDetails(allocator, "SOME_TASKS_NOT_FOUND", msg, details);
    }

    // Update status for all tasks
    const updated_count = try queries.updateTaskStatusBulk(allocator, conn, ids, new_status);

    // Update completed_at based on status
    if (new_status == .COMPLETED) {
        _ = try queries.updateTaskCompletedAtBulk(allocator, conn, ids, now);
    } else {
        // If moving away from COMPLETED, clear completed_at
        _ = try queries.updateTaskCompletedAtBulk(allocator, conn, ids, null);
    }

    // Log operation for each task
    for (ids) |id| {
        try queries.logOperation(conn, "TASK_STATUS_CHANGE", "task", id, now);
    }

    // Build response
    var ids_json: std.ArrayListUnmanaged(u8) = .empty;
    defer ids_json.deinit(allocator);

    for (ids, 0..) |id, i| {
        if (i > 0) try ids_json.append(allocator, ',');
        const id_str = try std.fmt.allocPrint(allocator, "{d}", .{id});
        defer allocator.free(id_str);
        try ids_json.appendSlice(allocator, id_str);
    }

    const response = try std.fmt.allocPrint(allocator, "{{\"updated\":[{s}],\"count\":{d},\"new_status\":\"{s}\",\"changed_at\":\"{s}\"}}", .{
        ids_json.items, updated_count, new_status.toString(), now,
    });
    defer allocator.free(response);

    return json.success(allocator, response);
}

/// Sets the priority of multiple tasks
pub fn setPriority(allocator: std.mem.Allocator, ids: []const i64, priority: i32) ![]const u8 {
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

    // Verify all tasks exist
    const existing_ids = try queries.filterExistingTaskIds(allocator, conn, ids);
    defer allocator.free(existing_ids);

    if (existing_ids.len == 0) {
        const details = try std.fmt.allocPrint(allocator, "{{\"roadmap\":\"{s}\",\"missing_ids\":{any}}}", .{ current, ids });
        defer allocator.free(details);
        return json.errorResponseWithDetails(allocator, "TASKS_NOT_FOUND", "No tasks found with the provided IDs", details);
    }

    if (existing_ids.len < ids.len) {
        var missing: std.ArrayListUnmanaged(i64) = .empty;
        defer missing.deinit(allocator);

        for (ids) |id| {
            var found = false;
            for (existing_ids) |existing| {
                if (id == existing) {
                    found = true;
                    break;
                }
            }
            if (!found) try missing.append(allocator, id);
        }

        const details = try std.fmt.allocPrint(allocator, "{{\"roadmap\":\"{s}\",\"missing_ids\":{any}}}", .{ current, missing.items });
        defer allocator.free(details);
        const msg = try std.fmt.allocPrint(allocator, "Only {d} of {d} tasks found", .{ existing_ids.len, ids.len });
        defer allocator.free(msg);
        return json.errorResponseWithDetails(allocator, "SOME_TASKS_NOT_FOUND", msg, details);
    }

    // Update priority for all tasks
    const updated_count = try queries.updateTaskPriorityBulk(allocator, conn, ids, priority);

    // Log operation for each task
    for (ids) |id| {
        try queries.logOperation(conn, "TASK_PRIORITY_CHANGE", "task", id, now);
    }

    // Build response
    var ids_json: std.ArrayListUnmanaged(u8) = .empty;
    defer ids_json.deinit(allocator);

    for (ids, 0..) |id, i| {
        if (i > 0) try ids_json.append(allocator, ',');
        const id_str = try std.fmt.allocPrint(allocator, "{d}", .{id});
        defer allocator.free(id_str);
        try ids_json.appendSlice(allocator, id_str);
    }

    const response = try std.fmt.allocPrint(allocator, "{{\"updated\":[{s}],\"count\":{d},\"new_priority\":{d},\"changed_at\":\"{s}\"}}", .{
        ids_json.items, updated_count, priority, now,
    });
    defer allocator.free(response);

    return json.success(allocator, response);
}

/// Sets the severity of multiple tasks
pub fn setSeverity(allocator: std.mem.Allocator, ids: []const i64, severity: i32) ![]const u8 {
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

    // Verify all tasks exist
    const existing_ids = try queries.filterExistingTaskIds(allocator, conn, ids);
    defer allocator.free(existing_ids);

    if (existing_ids.len == 0) {
        const details = try std.fmt.allocPrint(allocator, "{{\"roadmap\":\"{s}\",\"missing_ids\":{any}}}", .{ current, ids });
        defer allocator.free(details);
        return json.errorResponseWithDetails(allocator, "TASKS_NOT_FOUND", "No tasks found with the provided IDs", details);
    }

    if (existing_ids.len < ids.len) {
        var missing: std.ArrayListUnmanaged(i64) = .empty;
        defer missing.deinit(allocator);

        for (ids) |id| {
            var found = false;
            for (existing_ids) |existing| {
                if (id == existing) {
                    found = true;
                    break;
                }
            }
            if (!found) try missing.append(allocator, id);
        }

        const details = try std.fmt.allocPrint(allocator, "{{\"roadmap\":\"{s}\",\"missing_ids\":{any}}}", .{ current, missing.items });
        defer allocator.free(details);
        const msg = try std.fmt.allocPrint(allocator, "Only {d} of {d} tasks found", .{ existing_ids.len, ids.len });
        defer allocator.free(msg);
        return json.errorResponseWithDetails(allocator, "SOME_TASKS_NOT_FOUND", msg, details);
    }

    // Update severity for all tasks
    const updated_count = try queries.updateTaskSeverityBulk(allocator, conn, ids, severity);

    // Log operation for each task
    for (ids) |id| {
        try queries.logOperation(conn, "TASK_SEVERITY_CHANGE", "task", id, now);
    }

    // Build response
    var ids_json: std.ArrayListUnmanaged(u8) = .empty;
    defer ids_json.deinit(allocator);

    for (ids, 0..) |id, i| {
        if (i > 0) try ids_json.append(allocator, ',');
        const id_str = try std.fmt.allocPrint(allocator, "{d}", .{id});
        defer allocator.free(id_str);
        try ids_json.appendSlice(allocator, id_str);
    }

    const response = try std.fmt.allocPrint(allocator, "{{\"updated\":[{s}],\"count\":{d},\"new_severity\":{d},\"changed_at\":\"{s}\"}}", .{
        ids_json.items, updated_count, severity, now,
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

/// Deletes multiple tasks
pub fn deleteTask(allocator: std.mem.Allocator, ids: []const i64) ![]const u8 {
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

    // Verify all tasks exist
    const existing_ids = try queries.filterExistingTaskIds(allocator, conn, ids);
    defer allocator.free(existing_ids);

    if (existing_ids.len == 0) {
        const details = try std.fmt.allocPrint(allocator, "{{\"roadmap\":\"{s}\",\"missing_ids\":{any}}}", .{ current, ids });
        defer allocator.free(details);
        return json.errorResponseWithDetails(allocator, "TASKS_NOT_FOUND", "No tasks found with the provided IDs", details);
    }

    if (existing_ids.len < ids.len) {
        var missing: std.ArrayListUnmanaged(i64) = .empty;
        defer missing.deinit(allocator);

        for (ids) |id| {
            var found = false;
            for (existing_ids) |existing| {
                if (id == existing) {
                    found = true;
                    break;
                }
            }
            if (!found) try missing.append(allocator, id);
        }

        const details = try std.fmt.allocPrint(allocator, "{{\"roadmap\":\"{s}\",\"missing_ids\":{any}}}", .{ current, missing.items });
        defer allocator.free(details);
        const msg = try std.fmt.allocPrint(allocator, "Only {d} of {d} tasks found", .{ existing_ids.len, ids.len });
        defer allocator.free(msg);
        return json.errorResponseWithDetails(allocator, "SOME_TASKS_NOT_FOUND", msg, details);
    }

    // Log operation for each task before deletion
    for (ids) |id| {
        try queries.logOperation(conn, "TASK_DELETE", "task", id, now);
    }

    // Delete all tasks
    const deleted_count = try queries.deleteTaskBulk(allocator, conn, ids);

    // Build response
    var ids_json: std.ArrayListUnmanaged(u8) = .empty;
    defer ids_json.deinit(allocator);

    for (ids, 0..) |id, i| {
        if (i > 0) try ids_json.append(allocator, ',');
        const id_str = try std.fmt.allocPrint(allocator, "{d}", .{id});
        defer allocator.free(id_str);
        try ids_json.appendSlice(allocator, id_str);
    }

    const response = try std.fmt.allocPrint(allocator, "{{\"deleted\":[{s}],\"count\":{d},\"deleted_at\":\"{s}\"}}", .{
        ids_json.items, deleted_count, now,
    });
    defer allocator.free(response);

    return json.success(allocator, response);
}

