const std = @import("std");

/// Sprint status enum
pub const SprintStatus = enum {
    PENDING,
    OPEN,
    CLOSED,

    pub fn toString(self: SprintStatus) []const u8 {
        return switch (self) {
            .PENDING => "PENDING",
            .OPEN => "OPEN",
            .CLOSED => "CLOSED",
        };
    }

    pub fn fromString(str: []const u8) !SprintStatus {
        if (std.mem.eql(u8, str, "PENDING")) return .PENDING;
        if (std.mem.eql(u8, str, "OPEN")) return .OPEN;
        if (std.mem.eql(u8, str, "CLOSED")) return .CLOSED;
        return error.InvalidStatus;
    }

    pub fn isValidTransition(self: SprintStatus, new_status: SprintStatus) bool {
        return switch (self) {
            .PENDING => new_status == .PENDING or new_status == .OPEN,
            .OPEN => new_status == .OPEN or new_status == .CLOSED,
            .CLOSED => new_status == .CLOSED or new_status == .OPEN,
        };
    }
};

/// Sprint model
pub const Sprint = struct {
    id: i64,
    status: SprintStatus,
    description: []const u8,
    tasks: []i64,
    task_count: i32,
    created_at: []const u8,
    started_at: ?[]const u8,
    closed_at: ?[]const u8,

    pub fn init(
        allocator: std.mem.Allocator,
        id: i64,
        description: []const u8,
        created_at: []const u8,
    ) !Sprint {
        return Sprint{
            .id = id,
            .status = .PENDING,
            .description = try allocator.dupe(u8, description),
            .tasks = try allocator.alloc(i64, 0),
            .task_count = 0,
            .created_at = try allocator.dupe(u8, created_at),
            .started_at = null,
            .closed_at = null,
        };
    }

    pub fn deinit(self: *Sprint, allocator: std.mem.Allocator) void {
        allocator.free(self.description);
        allocator.free(self.tasks);
        allocator.free(self.created_at);
        if (self.started_at) |s| allocator.free(s);
        if (self.closed_at) |c| allocator.free(c);
    }

    pub fn setStatus(self: *Sprint, new_status: SprintStatus) !void {
        if (!self.status.isValidTransition(new_status)) {
            return error.InvalidStatusTransition;
        }
        self.status = new_status;
    }

    pub fn addTask(self: *Sprint, allocator: std.mem.Allocator, task_id: i64) !void {
        for (self.tasks) |existing_id| {
            if (existing_id == task_id) return error.TaskAlreadyInSprint;
        }
        const new_tasks = try allocator.realloc(self.tasks, self.tasks.len + 1);
        self.tasks = new_tasks;
        self.tasks[self.tasks.len - 1] = task_id;
        self.task_count += 1;
    }

    pub fn removeTask(self: *Sprint, allocator: std.mem.Allocator, task_id: i64) !void {
        const index = for (self.tasks, 0..) |id, i| {
            if (id == task_id) break i;
        } else return error.TaskNotFound;

        if (index < self.tasks.len - 1) {
            std.mem.copyForwards(i64, self.tasks[index..], self.tasks[index + 1 ..]);
        }
        const new_tasks = try allocator.realloc(self.tasks, self.tasks.len - 1);
        self.tasks = new_tasks;
        self.task_count -= 1;
    }

    pub fn hasTask(self: Sprint, task_id: i64) bool {
        for (self.tasks) |id| {
            if (id == task_id) return true;
        }
        return false;
    }
};

/// Sprint statistics
pub const SprintStats = struct {
    total_tasks: i32,
    by_status: struct {
        backlog: i32,
        sprint: i32,
        doing: i32,
        testing: i32,
        completed: i32,
    },
    completion_percentage: i32,
};

// ============== TESTS ==============

test "SprintStatus toString" {
    try std.testing.expectEqualStrings("PENDING", SprintStatus.PENDING.toString());
}

test "SprintStatus fromString" {
    try std.testing.expectEqual(SprintStatus.OPEN, try SprintStatus.fromString("OPEN"));
}

test "Sprint init and deinit" {
    const allocator = std.testing.allocator;
    var sprint = try Sprint.init(allocator, 1, "Sprint 1", "2026-03-12T14:30:00.000Z");
    defer sprint.deinit(allocator);
    try std.testing.expectEqual(@as(i64, 1), sprint.id);
}

test "Sprint addTask" {
    const allocator = std.testing.allocator;
    var sprint = try Sprint.init(allocator, 1, "Sprint 1", "2026-03-12T14:30:00.000Z");
    defer sprint.deinit(allocator);
    try sprint.addTask(allocator, 1);
    try sprint.addTask(allocator, 2);
    try std.testing.expectEqual(@as(i32, 2), sprint.task_count);
    try std.testing.expect(sprint.hasTask(1));
}

test "Sprint removeTask" {
    const allocator = std.testing.allocator;
    var sprint = try Sprint.init(allocator, 1, "Sprint 1", "2026-03-12T14:30:00.000Z");
    defer sprint.deinit(allocator);
    try sprint.addTask(allocator, 1);
    try sprint.addTask(allocator, 2);
    try sprint.removeTask(allocator, 2);
    try std.testing.expectEqual(@as(i32, 1), sprint.task_count);
    try std.testing.expect(!sprint.hasTask(2));
}
