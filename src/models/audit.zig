const std = @import("std");

/// Audit entry model
/// Represents a single audit log entry
pub const AuditEntry = struct {
    id: i64,
    operation: []const u8,
    entity_type: []const u8,
    entity_id: i64,
    performed_at: []const u8,

    /// Creates a new audit entry
    pub fn init(
        allocator: std.mem.Allocator,
        id: i64,
        operation: []const u8,
        entity_type: []const u8,
        entity_id: i64,
        performed_at: []const u8,
    ) !AuditEntry {
        return AuditEntry{
            .id = id,
            .operation = try allocator.dupe(u8, operation),
            .entity_type = try allocator.dupe(u8, entity_type),
            .entity_id = entity_id,
            .performed_at = try allocator.dupe(u8, performed_at),
        };
    }

    /// Frees memory allocated for the audit entry
    pub fn deinit(self: *AuditEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.operation);
        allocator.free(self.entity_type);
        allocator.free(self.performed_at);
    }

    /// Formats the audit entry as a JSON string
    pub fn toJson(self: AuditEntry, allocator: std.mem.Allocator) ![]const u8 {
        const json = @import("../utils/json.zig");

        const op_escaped = try json.escapeString(allocator, self.operation);
        defer allocator.free(op_escaped);

        const entity_type_escaped = try json.escapeString(allocator, self.entity_type);
        defer allocator.free(entity_type_escaped);

        const performed_at_escaped = try json.escapeString(allocator, self.performed_at);
        defer allocator.free(performed_at_escaped);

        return std.fmt.allocPrint(allocator,
            \\{{"id":{d},"operation":{s},"entity_type":{s},"entity_id":{d},"performed_at":{s}}}
        , .{ self.id, op_escaped, entity_type_escaped, self.entity_id, performed_at_escaped });
    }
};

/// Operation type enum for audit entries
pub const OperationType = enum {
    /// Task operations
    TASK_CREATE,
    TASK_UPDATE,
    TASK_DELETE,
    TASK_STATUS_CHANGE,
    TASK_PRIORITY_CHANGE,
    TASK_SEVERITY_CHANGE,
    /// Sprint operations
    SPRINT_CREATE,
    SPRINT_UPDATE,
    SPRINT_DELETE,
    SPRINT_START,
    SPRINT_CLOSE,
    SPRINT_REOPEN,
    /// Sprint-task operations
    SPRINT_ADD_TASK,
    SPRINT_REMOVE_TASK,
    SPRINT_MOVE_TASK,
    /// Sprint query operations
    SPRINT_GET,
    SPRINT_STATS,
    SPRINT_LIST_TASKS,

    /// Converts operation type to string
    pub fn toString(self: OperationType) []const u8 {
        return switch (self) {
            .TASK_CREATE => "TASK_CREATE",
            .TASK_UPDATE => "TASK_UPDATE",
            .TASK_DELETE => "TASK_DELETE",
            .TASK_STATUS_CHANGE => "TASK_STATUS_CHANGE",
            .TASK_PRIORITY_CHANGE => "TASK_PRIORITY_CHANGE",
            .TASK_SEVERITY_CHANGE => "TASK_SEVERITY_CHANGE",
            .SPRINT_CREATE => "SPRINT_CREATE",
            .SPRINT_UPDATE => "SPRINT_UPDATE",
            .SPRINT_DELETE => "SPRINT_DELETE",
            .SPRINT_START => "SPRINT_START",
            .SPRINT_CLOSE => "SPRINT_CLOSE",
            .SPRINT_REOPEN => "SPRINT_REOPEN",
            .SPRINT_ADD_TASK => "SPRINT_ADD_TASK",
            .SPRINT_REMOVE_TASK => "SPRINT_REMOVE_TASK",
            .SPRINT_MOVE_TASK => "SPRINT_MOVE_TASK",
            .SPRINT_GET => "SPRINT_GET",
            .SPRINT_STATS => "SPRINT_STATS",
            .SPRINT_LIST_TASKS => "SPRINT_LIST_TASKS",
        };
    }

    /// Parses a string into OperationType
    pub fn fromString(str: []const u8) !OperationType {
        if (std.mem.eql(u8, str, "TASK_CREATE")) return .TASK_CREATE;
        if (std.mem.eql(u8, str, "TASK_UPDATE")) return .TASK_UPDATE;
        if (std.mem.eql(u8, str, "TASK_DELETE")) return .TASK_DELETE;
        if (std.mem.eql(u8, str, "TASK_STATUS_CHANGE")) return .TASK_STATUS_CHANGE;
        if (std.mem.eql(u8, str, "TASK_PRIORITY_CHANGE")) return .TASK_PRIORITY_CHANGE;
        if (std.mem.eql(u8, str, "TASK_SEVERITY_CHANGE")) return .TASK_SEVERITY_CHANGE;
        if (std.mem.eql(u8, str, "SPRINT_CREATE")) return .SPRINT_CREATE;
        if (std.mem.eql(u8, str, "SPRINT_UPDATE")) return .SPRINT_UPDATE;
        if (std.mem.eql(u8, str, "SPRINT_DELETE")) return .SPRINT_DELETE;
        if (std.mem.eql(u8, str, "SPRINT_START")) return .SPRINT_START;
        if (std.mem.eql(u8, str, "SPRINT_CLOSE")) return .SPRINT_CLOSE;
        if (std.mem.eql(u8, str, "SPRINT_REOPEN")) return .SPRINT_REOPEN;
        if (std.mem.eql(u8, str, "SPRINT_ADD_TASK")) return .SPRINT_ADD_TASK;
        if (std.mem.eql(u8, str, "SPRINT_REMOVE_TASK")) return .SPRINT_REMOVE_TASK;
        if (std.mem.eql(u8, str, "SPRINT_MOVE_TASK")) return .SPRINT_MOVE_TASK;
        if (std.mem.eql(u8, str, "SPRINT_GET")) return .SPRINT_GET;
        if (std.mem.eql(u8, str, "SPRINT_STATS")) return .SPRINT_STATS;
        if (std.mem.eql(u8, str, "SPRINT_LIST_TASKS")) return .SPRINT_LIST_TASKS;
        return error.InvalidOperationType;
    }
};

/// Entity type enum
pub const EntityType = enum {
    TASK,
    SPRINT,

    /// Converts entity type to string
    pub fn toString(self: EntityType) []const u8 {
        return switch (self) {
            .TASK => "TASK",
            .SPRINT => "SPRINT",
        };
    }

    /// Parses a string into EntityType
    pub fn fromString(str: []const u8) !EntityType {
        if (std.mem.eql(u8, str, "TASK")) return .TASK;
        if (std.mem.eql(u8, str, "SPRINT")) return .SPRINT;
        return error.InvalidEntityType;
    }
};

/// Audit statistics model
pub const AuditStats = struct {
    total_entries: i64,
    by_operation: std.StringHashMap(i64),
    by_entity_type: std.StringHashMap(i64),
    first_entry: ?[]const u8,
    last_entry: ?[]const u8,

    /// Creates empty audit stats
    pub fn init(allocator: std.mem.Allocator) AuditStats {
        return AuditStats{
            .total_entries = 0,
            .by_operation = std.StringHashMap(i64).init(allocator),
            .by_entity_type = std.StringHashMap(i64).init(allocator),
            .first_entry = null,
            .last_entry = null,
        };
    }

    /// Frees memory allocated for audit stats
    pub fn deinit(self: *AuditStats, allocator: std.mem.Allocator) void {
        var op_iter = self.by_operation.keyIterator();
        while (op_iter.next()) |key| {
            allocator.free(key.*);
        }
        self.by_operation.deinit();

        var et_iter = self.by_entity_type.keyIterator();
        while (et_iter.next()) |key| {
            allocator.free(key.*);
        }
        self.by_entity_type.deinit();

        if (self.first_entry) |fe| allocator.free(fe);
        if (self.last_entry) |le| allocator.free(le);
    }

    /// Formats the audit stats as a JSON string
    pub fn toJson(self: AuditStats, allocator: std.mem.Allocator) ![]const u8 {
        const json = @import("../utils/json.zig");

        // Build by_operation JSON
        var op_parts: std.ArrayListUnmanaged([]const u8) = .empty;
        defer {
            for (op_parts.items) |p| allocator.free(p);
            op_parts.deinit(allocator);
        }

        var op_iter = self.by_operation.iterator();
        while (op_iter.next()) |entry| {
            const op_escaped = try json.escapeString(allocator, entry.key_ptr.*);
            defer allocator.free(op_escaped);
            const part = try std.fmt.allocPrint(allocator, "{s}:{d}", .{ op_escaped, entry.value_ptr.* });
            try op_parts.append(allocator, part);
        }
        const by_op_json = try std.mem.join(allocator, ",", op_parts.items);
        defer allocator.free(by_op_json);

        // Build by_entity_type JSON
        var et_parts: std.ArrayListUnmanaged([]const u8) = .empty;
        defer {
            for (et_parts.items) |p| allocator.free(p);
            et_parts.deinit(allocator);
        }

        var et_iter = self.by_entity_type.iterator();
        while (et_iter.next()) |entry| {
            const et_escaped = try json.escapeString(allocator, entry.key_ptr.*);
            defer allocator.free(et_escaped);
            const part = try std.fmt.allocPrint(allocator, "{s}:{d}", .{ et_escaped, entry.value_ptr.* });
            try et_parts.append(allocator, part);
        }
        const by_et_json = try std.mem.join(allocator, ",", et_parts.items);
        defer allocator.free(by_et_json);

        const first_val = if (self.first_entry) |fe| blk: {
            const escaped = try json.escapeString(allocator, fe);
            break :blk escaped;
        } else try allocator.dupe(u8, "null");
        defer allocator.free(first_val);

        const last_val = if (self.last_entry) |le| blk: {
            const escaped = try json.escapeString(allocator, le);
            break :blk escaped;
        } else try allocator.dupe(u8, "null");
        defer allocator.free(last_val);

        return std.fmt.allocPrint(allocator,
            \\{{"total_entries":{d},"by_operation":{{{s}}},"by_entity_type":{{{s}}},"first_entry":{s},"last_entry":{s}}}
        , .{ self.total_entries, by_op_json, by_et_json, first_val, last_val });
    }
};

// ============== TESTS ==============

test "AuditEntry init and deinit" {
    const allocator = std.testing.allocator;

    var entry = try AuditEntry.init(
        allocator,
        1,
        "TASK_CREATE",
        "TASK",
        42,
        "2026-03-13T10:30:00.000Z",
    );
    defer entry.deinit(allocator);

    try std.testing.expectEqual(@as(i64, 1), entry.id);
    try std.testing.expectEqualStrings("TASK_CREATE", entry.operation);
    try std.testing.expectEqualStrings("TASK", entry.entity_type);
    try std.testing.expectEqual(@as(i64, 42), entry.entity_id);
}

test "AuditEntry toJson" {
    const allocator = std.testing.allocator;

    var entry = try AuditEntry.init(
        allocator,
        1,
        "TASK_CREATE",
        "TASK",
        42,
        "2026-03-13T10:30:00.000Z",
    );
    defer entry.deinit(allocator);

    const json = try entry.toJson(allocator);
    defer allocator.free(json);

    try std.testing.expect(std.mem.containsAtLeast(u8, json, 1, "\"id\":1"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json, 1, "\"operation\":\"TASK_CREATE\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, json, 1, "\"entity_id\":42"));
}

test "OperationType toString and fromString" {
    try std.testing.expectEqualStrings("TASK_CREATE", OperationType.TASK_CREATE.toString());
    try std.testing.expectEqual(OperationType.TASK_CREATE, try OperationType.fromString("TASK_CREATE"));
    try std.testing.expectEqual(OperationType.SPRINT_START, try OperationType.fromString("SPRINT_START"));
}

test "EntityType toString and fromString" {
    try std.testing.expectEqualStrings("TASK", EntityType.TASK.toString());
    try std.testing.expectEqual(EntityType.TASK, try EntityType.fromString("TASK"));
    try std.testing.expectEqual(EntityType.SPRINT, try EntityType.fromString("SPRINT"));
}

test "AuditStats init and deinit" {
    const allocator = std.testing.allocator;

    var stats = AuditStats.init(allocator);
    defer stats.deinit(allocator);

    try std.testing.expectEqual(@as(i64, 0), stats.total_entries);
}
