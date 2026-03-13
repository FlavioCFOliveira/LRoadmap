const std = @import("std");

/// Task status enum
/// Represents the lifecycle of a task from creation to completion
pub const TaskStatus = enum {
    /// Task created, awaits planning
    BACKLOG,
    /// Planned, associated to sprint
    SPRINT,
    /// In development
    DOING,
    /// In testing, may have changes
    TESTING,
    /// Developed and tested, closed
    COMPLETED,

    /// Converts status to string representation
    pub fn toString(self: TaskStatus) []const u8 {
        return switch (self) {
            .BACKLOG => "BACKLOG",
            .SPRINT => "SPRINT",
            .DOING => "DOING",
            .TESTING => "TESTING",
            .COMPLETED => "COMPLETED",
        };
    }

    /// Parses a string into TaskStatus
    pub fn fromString(str: []const u8) !TaskStatus {
        if (std.mem.eql(u8, str, "BACKLOG")) return .BACKLOG;
        if (std.mem.eql(u8, str, "SPRINT")) return .SPRINT;
        if (std.mem.eql(u8, str, "DOING")) return .DOING;
        if (std.mem.eql(u8, str, "TESTING")) return .TESTING;
        if (std.mem.eql(u8, str, "COMPLETED")) return .COMPLETED;
        return error.InvalidStatus;
    }

    /// Checks if the transition to a new status is valid
    pub fn isValidTransition(self: TaskStatus, new_status: TaskStatus) bool {
        return switch (self) {
            .BACKLOG => new_status == .BACKLOG or new_status == .SPRINT,
            .SPRINT => new_status == .SPRINT or new_status == .DOING or new_status == .BACKLOG,
            .DOING => new_status == .DOING or new_status == .TESTING or new_status == .SPRINT,
            .TESTING => new_status == .TESTING or new_status == .COMPLETED or new_status == .DOING,
            .COMPLETED => false,
        };
    }
};

/// Task model
pub const Task = struct {
    id: i64,
    priority: i32,
    severity: i32,
    status: TaskStatus,
    description: []const u8,
    specialists: ?[]const u8,
    action: []const u8,
    expected_result: []const u8,
    created_at: []const u8,
    completed_at: ?[]const u8,

    /// Creates a new task with default values
    pub fn init(
        allocator: std.mem.Allocator,
        id: i64,
        description: []const u8,
        action: []const u8,
        expected_result: []const u8,
        created_at: []const u8,
    ) !Task {
        return Task{
            .id = id,
            .priority = 0,
            .severity = 0,
            .status = .BACKLOG,
            .description = try allocator.dupe(u8, description),
            .specialists = null,
            .action = try allocator.dupe(u8, action),
            .expected_result = try allocator.dupe(u8, expected_result),
            .created_at = try allocator.dupe(u8, created_at),
            .completed_at = null,
        };
    }

    /// Frees memory allocated for the task
    pub fn deinit(self: *Task, allocator: std.mem.Allocator) void {
        allocator.free(self.description);
        if (self.specialists) |s| {
            allocator.free(s);
        }
        allocator.free(self.action);
        allocator.free(self.expected_result);
        allocator.free(self.created_at);
        if (self.completed_at) |c| {
            allocator.free(c);
        }
    }

    /// Sets the task status with validation
    pub fn setStatus(self: *Task, new_status: TaskStatus) !void {
        if (!self.status.isValidTransition(new_status)) {
            return error.InvalidStatusTransition;
        }
        self.status = new_status;
    }

    /// Sets the priority (0-9)
    pub fn setPriority(self: *Task, priority: i32) !void {
        if (priority < 0 or priority > 9) {
            return error.InvalidPriority;
        }
        self.priority = priority;
    }

    /// Sets the severity (0-9)
    pub fn setSeverity(self: *Task, severity: i32) !void {
        if (severity < 0 or severity > 9) {
            return error.InvalidSeverity;
        }
        self.severity = severity;
    }

    /// Sets the specialists list
    pub fn setSpecialists(self: *Task, allocator: std.mem.Allocator, specialists: []const u8) !void {
        if (self.specialists) |s| {
            allocator.free(s);
        }
        self.specialists = try allocator.dupe(u8, specialists);
    }

    /// Task update structure
    pub const TaskUpdate = struct {
        priority: ?i32 = null,
        severity: ?i32 = null,
        description: ?[]const u8 = null,
        specialists: ?[]const u8 = null,
        action: ?[]const u8 = null,
        expected_result: ?[]const u8 = null,
    };

    /// Formats the task as a JSON string
    pub fn toJson(self: Task, allocator: std.mem.Allocator) ![]const u8 {
        const json = @import("../utils/json.zig");
        const desc_escaped = try json.escapeString(allocator, self.description);
        defer allocator.free(desc_escaped);

        const action_escaped = try json.escapeString(allocator, self.action);
        defer allocator.free(action_escaped);

        const exp_escaped = try json.escapeString(allocator, self.expected_result);
        defer allocator.free(exp_escaped);

        const created_escaped = try json.escapeString(allocator, self.created_at);
        defer allocator.free(created_escaped);

        const completed_val = if (self.completed_at) |ca| try json.escapeString(allocator, ca) else try allocator.dupe(u8, "null");
        defer allocator.free(completed_val);

        if (self.specialists) |s| {
            const spec_escaped = try json.escapeString(allocator, s);
            defer allocator.free(spec_escaped);

            return std.fmt.allocPrint(allocator,
                \\{{"id":{d},"priority":{d},"severity":{d},"status":"{s}","description":{s},"specialists":{s},"action":{s},"expected_result":{s},"created_at":{s},"completed_at":{s}}}
            , .{ self.id, self.priority, self.severity, self.status.toString(), desc_escaped, spec_escaped, action_escaped, exp_escaped, created_escaped, completed_val });
        } else {
            return std.fmt.allocPrint(allocator,
                \\{{"id":{d},"priority":{d},"severity":{d},"status":"{s}","description":{s},"specialists":null,"action":{s},"expected_result":{s},"created_at":{s},"completed_at":{s}}}
            , .{ self.id, self.priority, self.severity, self.status.toString(), desc_escaped, action_escaped, exp_escaped, created_escaped, completed_val });
        }
    }
};

// ============== TESTS ==============

test "TaskStatus toString" {
    try std.testing.expectEqualStrings("BACKLOG", TaskStatus.BACKLOG.toString());
}

test "TaskStatus fromString" {
    try std.testing.expectEqual(TaskStatus.BACKLOG, try TaskStatus.fromString("BACKLOG"));
}

test "TaskStatus fromString invalid" {
    try std.testing.expectError(error.InvalidStatus, TaskStatus.fromString("INVALID"));
}

test "TaskStatus isValidTransition" {
    try std.testing.expect(TaskStatus.BACKLOG.isValidTransition(.SPRINT));
    try std.testing.expect(!TaskStatus.BACKLOG.isValidTransition(.DOING));
}

test "Task init and deinit" {
    const allocator = std.testing.allocator;

    var task = try Task.init(
        allocator,
        1,
        "Test description",
        "Test action",
        "Test expected result",
        "2026-03-12T14:30:00.000Z",
    );
    defer task.deinit(allocator);

    try std.testing.expectEqual(@as(i64, 1), task.id);
    try std.testing.expectEqual(TaskStatus.BACKLOG, task.status);
}

test "Task setPriority" {
    const allocator = std.testing.allocator;

    var task = try Task.init(
        allocator,
        1,
        "Test",
        "Action",
        "Result",
        "2026-03-12T14:30:00.000Z",
    );
    defer task.deinit(allocator);

    try task.setPriority(9);
    try std.testing.expectEqual(@as(i32, 9), task.priority);
}

test "Task setPriority invalid" {
    const allocator = std.testing.allocator;

    var task = try Task.init(
        allocator,
        1,
        "Test",
        "Action",
        "Result",
        "2026-03-12T14:30:00.000Z",
    );
    defer task.deinit(allocator);

    try std.testing.expectError(error.InvalidPriority, task.setPriority(10));
}

test "Task toJson" {
    const allocator = std.testing.allocator;

    var task = try Task.init(
        allocator,
        1,
        "Test task",
        "Do something",
        "It works",
        "2026-03-12T14:30:00.000Z",
    );
    defer task.deinit(allocator);

    const json = try task.toJson(allocator);
    defer allocator.free(json);

    try std.testing.expect(std.mem.containsAtLeast(u8, json, 1, "\"id\":1"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json, 1, "\"status\":\"BACKLOG\""));
}
