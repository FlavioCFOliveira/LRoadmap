const std = @import("std");
const c = @cImport({
    @cInclude("sqlite3.h");
});
const Connection = @import("connection.zig").Connection;
const Task = @import("../models/task.zig").Task;
const TaskStatus = @import("../models/task.zig").TaskStatus;
const Sprint = @import("../models/sprint.zig").Sprint;
const SprintStatus = @import("../models/sprint.zig").SprintStatus;

// ============== TASK QUERIES ==============

pub fn insertTask(conn: Connection, task: Task) !i64 {
    const sql = "INSERT INTO tasks (priority, severity, description, specialists, action, expected_result, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)";

    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(@ptrCast(conn.db), sql.ptr, @intCast(sql.len), &stmt, null);
    if (rc != c.SQLITE_OK) return error.PrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    _ = c.sqlite3_bind_int(stmt, 1, task.priority);
    _ = c.sqlite3_bind_int(stmt, 2, task.severity);
    _ = c.sqlite3_bind_text(stmt, 3, task.description.ptr, @intCast(task.description.len), c.SQLITE_STATIC);

    if (task.specialists) |s| {
        _ = c.sqlite3_bind_text(stmt, 4, s.ptr, @intCast(s.len), c.SQLITE_STATIC);
    } else {
        _ = c.sqlite3_bind_null(stmt, 4);
    }

    _ = c.sqlite3_bind_text(stmt, 5, task.action.ptr, @intCast(task.action.len), c.SQLITE_STATIC);
    _ = c.sqlite3_bind_text(stmt, 6, task.expected_result.ptr, @intCast(task.expected_result.len), c.SQLITE_STATIC);
    _ = c.sqlite3_bind_text(stmt, 7, task.created_at.ptr, @intCast(task.created_at.len), c.SQLITE_STATIC);

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

    _ = c.sqlite3_bind_text(stmt, 1, status_str.ptr, @intCast(status_str.len), c.SQLITE_STATIC);
    _ = c.sqlite3_bind_int64(stmt, 2, id);

    const step_rc = c.sqlite3_step(stmt);
    if (step_rc != c.SQLITE_DONE) return error.StepFailed;
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
