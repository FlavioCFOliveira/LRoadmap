const std = @import("std");
const path = @import("../utils/path.zig");
const json = @import("../utils/json.zig");
const time = @import("../utils/time.zig");
const connection = @import("../db/connection.zig");
const queries = @import("../db/queries.zig");
const AuditEntry = @import("../models/audit.zig").AuditEntry;
const AuditStats = @import("../models/audit.zig").AuditStats;
const roadmap = @import("roadmap.zig");
const json_utils = @import("../utils/json.zig");

/// Filter options for audit list command
pub const AuditListOptions = struct {
    operation: ?[]const u8 = null,
    entity_type: ?[]const u8 = null,
    entity_id: ?i64 = null,
    since: ?[]const u8 = null,
    until: ?[]const u8 = null,
    limit: i32 = 100,
    offset: i32 = 0,
};

/// List audit entries with optional filters
pub fn listAuditEntries(allocator: std.mem.Allocator, options: AuditListOptions) ![]const u8 {
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

    const filters = queries.AuditFilterOptions{
        .operation = options.operation,
        .entity_type = options.entity_type,
        .entity_id = options.entity_id,
        .since = options.since,
        .until = options.until,
        .limit = options.limit,
        .offset = options.offset,
    };

    const result = queries.listAuditEntries(allocator, conn, filters) catch {
        return json.errorResponse(allocator, "DB_ERROR", "Failed to list audit entries");
    };
    defer {
        for (result.entries) |*e| e.deinit(allocator);
        allocator.free(result.entries);
    }

    // Build entries JSON array
    var entry_json_parts: std.ArrayListUnmanaged([]const u8) = .empty;
    defer {
        for (entry_json_parts.items) |p| allocator.free(p);
        entry_json_parts.deinit(allocator);
    }

    for (result.entries) |entry| {
        const entry_json = entry.toJson(allocator) catch {
            return json.errorResponse(allocator, "SYSTEM_ERROR", "Failed to serialize audit entry");
        };
        entry_json_parts.append(allocator, entry_json) catch {
            allocator.free(entry_json);
            return json.errorResponse(allocator, "SYSTEM_ERROR", "Failed to append entry");
        };
    }
    const entries_array = std.mem.join(allocator, ",", entry_json_parts.items) catch {
        return json.errorResponse(allocator, "SYSTEM_ERROR", "Failed to join entries");
    };
    defer allocator.free(entries_array);

    // Build filters JSON
    const roadmap_escaped = json_utils.escapeString(allocator, current) catch {
        return json.errorResponse(allocator, "SYSTEM_ERROR", "Failed to escape roadmap name");
    };
    defer allocator.free(roadmap_escaped);

    const op_val = if (options.operation) |op| blk: {
        const escaped = json_utils.escapeString(allocator, op) catch break :blk try allocator.dupe(u8, "null");
        break :blk escaped;
    } else try allocator.dupe(u8, "null");
    defer allocator.free(op_val);

    const et_val = if (options.entity_type) |et| blk: {
        const escaped = json_utils.escapeString(allocator, et) catch break :blk try allocator.dupe(u8, "null");
        break :blk escaped;
    } else try allocator.dupe(u8, "null");
    defer allocator.free(et_val);

    const eid_val = if (options.entity_id) |eid|
        std.fmt.allocPrint(allocator, "{d}", .{eid}) catch try allocator.dupe(u8, "null")
    else
        try allocator.dupe(u8, "null");
    defer allocator.free(eid_val);

    const since_val = if (options.since) |s| blk: {
        const escaped = json_utils.escapeString(allocator, s) catch break :blk try allocator.dupe(u8, "null");
        break :blk escaped;
    } else try allocator.dupe(u8, "null");
    defer allocator.free(since_val);

    const until_val = if (options.until) |u| blk: {
        const escaped = json_utils.escapeString(allocator, u) catch break :blk try allocator.dupe(u8, "null");
        break :blk escaped;
    } else try allocator.dupe(u8, "null");
    defer allocator.free(until_val);

    const data_json = std.fmt.allocPrint(allocator,
        \\{{"roadmap":{s},"count":{d},"total":{d},"filters":{{"operation":{s},"entity_type":{s},"entity_id":{s},"since":{s},"until":{s},"limit":{d},"offset":{d}}},"entries":[{s}]}}
    , .{
        roadmap_escaped,
        result.entries.len,
        result.total,
        op_val,
        et_val,
        eid_val,
        since_val,
        until_val,
        options.limit,
        options.offset,
        entries_array,
    }) catch {
        return json.errorResponse(allocator, "SYSTEM_ERROR", "Failed to build response");
    };
    defer allocator.free(data_json);

    return json.success(allocator, data_json);
}

/// Get audit history for a specific entity
pub fn getEntityHistory(allocator: std.mem.Allocator, entity_type: []const u8, entity_id: i64) ![]const u8 {
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

    const entries = queries.getEntityHistory(allocator, conn, entity_type, entity_id) catch {
        return json.errorResponse(allocator, "DB_ERROR", "Failed to get entity history");
    };
    defer {
        for (entries) |*e| e.deinit(allocator);
        allocator.free(entries);
    }

    // Build entries JSON array
    var entry_json_parts: std.ArrayListUnmanaged([]const u8) = .empty;
    defer {
        for (entry_json_parts.items) |p| allocator.free(p);
        entry_json_parts.deinit(allocator);
    }

    for (entries) |entry| {
        const entry_json = entry.toJson(allocator) catch {
            return json.errorResponse(allocator, "SYSTEM_ERROR", "Failed to serialize audit entry");
        };
        entry_json_parts.append(allocator, entry_json) catch {
            allocator.free(entry_json);
            return json.errorResponse(allocator, "SYSTEM_ERROR", "Failed to append entry");
        };
    }
    const entries_array = std.mem.join(allocator, ",", entry_json_parts.items) catch {
        return json.errorResponse(allocator, "SYSTEM_ERROR", "Failed to join entries");
    };
    defer allocator.free(entries_array);

    // Build output
    const roadmap_escaped = json_utils.escapeString(allocator, current) catch {
        return json.errorResponse(allocator, "SYSTEM_ERROR", "Failed to escape roadmap name");
    };
    defer allocator.free(roadmap_escaped);

    const entity_type_escaped = json_utils.escapeString(allocator, entity_type) catch {
        return json.errorResponse(allocator, "SYSTEM_ERROR", "Failed to escape entity type");
    };
    defer allocator.free(entity_type_escaped);

    const data_json = std.fmt.allocPrint(allocator,
        \\{{"roadmap":{s},"entity_type":{s},"entity_id":{d},"count":{d},"entries":[{s}]}}
    , .{
        roadmap_escaped,
        entity_type_escaped,
        entity_id,
        entries.len,
        entries_array,
    }) catch {
        return json.errorResponse(allocator, "SYSTEM_ERROR", "Failed to build response");
    };
    defer allocator.free(data_json);

    return json.success(allocator, data_json);
}

/// Get audit statistics
pub fn getAuditStats(allocator: std.mem.Allocator, since: ?[]const u8, until: ?[]const u8) ![]const u8 {
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

    var stats = queries.getAuditStats(allocator, conn, since, until) catch {
        return json.errorResponse(allocator, "DB_ERROR", "Failed to get audit stats");
    };
    defer stats.deinit(allocator);

    // Build by_operation JSON
    var op_parts: std.ArrayListUnmanaged([]const u8) = .empty;
    defer {
        for (op_parts.items) |p| allocator.free(p);
        op_parts.deinit(allocator);
    }

    var op_iter = stats.by_operation.iterator();
    while (op_iter.next()) |entry| {
        const op_escaped = json_utils.escapeString(allocator, entry.key_ptr.*) catch continue;
        defer allocator.free(op_escaped);
        const part = std.fmt.allocPrint(allocator, "{s}:{d}", .{ op_escaped, entry.value_ptr.* }) catch continue;
        op_parts.append(allocator, part) catch {
            allocator.free(part);
            continue;
        };
    }
    const by_op_json = std.mem.join(allocator, ",", op_parts.items) catch "";
    defer allocator.free(by_op_json);

    // Build by_entity_type JSON
    var et_parts: std.ArrayListUnmanaged([]const u8) = .empty;
    defer {
        for (et_parts.items) |p| allocator.free(p);
        et_parts.deinit(allocator);
    }

    var et_iter = stats.by_entity_type.iterator();
    while (et_iter.next()) |entry| {
        const et_escaped = json_utils.escapeString(allocator, entry.key_ptr.*) catch continue;
        defer allocator.free(et_escaped);
        const part = std.fmt.allocPrint(allocator, "{s}:{d}", .{ et_escaped, entry.value_ptr.* }) catch continue;
        et_parts.append(allocator, part) catch {
            allocator.free(part);
            continue;
        };
    }
    const by_et_json = std.mem.join(allocator, ",", et_parts.items) catch "";
    defer allocator.free(by_et_json);

    // Build period and dates
    const roadmap_escaped = json_utils.escapeString(allocator, current) catch {
        return json.errorResponse(allocator, "SYSTEM_ERROR", "Failed to escape roadmap name");
    };
    defer allocator.free(roadmap_escaped);

    const since_val = if (since) |s| blk: {
        const escaped = json_utils.escapeString(allocator, s) catch break :blk try allocator.dupe(u8, "null");
        break :blk escaped;
    } else try allocator.dupe(u8, "null");
    defer allocator.free(since_val);

    const until_val = if (until) |u| blk: {
        const escaped = json_utils.escapeString(allocator, u) catch break :blk try allocator.dupe(u8, "null");
        break :blk escaped;
    } else try allocator.dupe(u8, "null");
    defer allocator.free(until_val);

    const first_val = if (stats.first_entry) |fe| blk: {
        const escaped = json_utils.escapeString(allocator, fe) catch break :blk try allocator.dupe(u8, "null");
        break :blk escaped;
    } else try allocator.dupe(u8, "null");
    defer allocator.free(first_val);

    const last_val = if (stats.last_entry) |le| blk: {
        const escaped = json_utils.escapeString(allocator, le) catch break :blk try allocator.dupe(u8, "null");
        break :blk escaped;
    } else try allocator.dupe(u8, "null");
    defer allocator.free(last_val);

    // Build JSON response piece by piece to avoid format string complexity
    var json_parts: std.ArrayListUnmanaged([]const u8) = .empty;
    defer {
        for (json_parts.items) |p| allocator.free(p);
        json_parts.deinit(allocator);
    }

    // Start building
    try json_parts.append(allocator, try allocator.dupe(u8, "{\"roadmap\":"));
    try json_parts.append(allocator, try allocator.dupe(u8, roadmap_escaped));
    try json_parts.append(allocator, try allocator.dupe(u8, ",\"period\":{\"since\":"));
    try json_parts.append(allocator, try allocator.dupe(u8, since_val));
    try json_parts.append(allocator, try allocator.dupe(u8, ",\"until\":"));
    try json_parts.append(allocator, try allocator.dupe(u8, until_val));
    try json_parts.append(allocator, try std.fmt.allocPrint(allocator, "}},\"total_entries\":{d}", .{stats.total_entries}));
    try json_parts.append(allocator, try allocator.dupe(u8, ",\"by_operation\":{"));
    if (by_op_json.len > 0) {
        try json_parts.append(allocator, try allocator.dupe(u8, by_op_json));
    }
    try json_parts.append(allocator, try allocator.dupe(u8, "},\"by_entity_type\":{"));
    if (by_et_json.len > 0) {
        try json_parts.append(allocator, try allocator.dupe(u8, by_et_json));
    }
    try json_parts.append(allocator, try allocator.dupe(u8, "},\"first_entry\":"));
    try json_parts.append(allocator, try allocator.dupe(u8, first_val));
    try json_parts.append(allocator, try allocator.dupe(u8, ",\"last_entry\":"));
    try json_parts.append(allocator, try allocator.dupe(u8, last_val));
    try json_parts.append(allocator, try allocator.dupe(u8, "}"));

    const data_json = try std.mem.join(allocator, "", json_parts.items);
    defer allocator.free(data_json);

    return json.success(allocator, data_json);
}

// ============== TESTS ==============

test "audit module compiles" {
    // Just verify the module compiles
    _ = listAuditEntries;
    _ = getEntityHistory;
    _ = getAuditStats;
}
