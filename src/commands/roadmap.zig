const std = @import("std");
const path = @import("../utils/path.zig");
const json = @import("../utils/json.zig");
const time = @import("../utils/time.zig");
const connection = @import("../db/connection.zig");
const schema = @import("../db/schema.zig");
const queries = @import("../db/queries.zig");

/// Lists all roadmaps in the ~/.roadmaps directory
pub fn listRoadmaps(allocator: std.mem.Allocator) ![]const u8 {
    const roadmaps_dir = path.getRoadmapsDir(allocator) catch {
        return json.errorResponse(allocator, "SYSTEM_ERROR", "Failed to get roadmaps directory");
    };
    defer allocator.free(roadmaps_dir);

    // Check if directory exists
    var dir = std.fs.cwd().openDir(roadmaps_dir, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) {
            // Directory doesn't exist, return empty array
            return json.success(allocator, "[]");
        }
        return json.errorResponse(allocator, "SYSTEM_ERROR", "Failed to open roadmaps directory");
    };
    defer dir.close();

    // Collect roadmap info
    var roadmaps: std.array_list.Aligned(RoadmapInfo, null) = .empty;
    defer {
        for (roadmaps.items) |r| {
            allocator.free(r.name);
            allocator.free(r.path);
            allocator.free(r.created_at);
        }
        roadmaps.deinit(allocator);
    }

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".db")) {
            // Extract name without extension
            const name = entry.name[0 .. entry.name.len - 3]; // Remove .db

            // Get full path
            const full_path = try std.fs.path.join(allocator, &[_][]const u8{ roadmaps_dir, entry.name });
            defer allocator.free(full_path);

            // Get file stats
            const stat = dir.statFile(entry.name) catch continue;

            // Try to get creation time from database
            var created_at: []const u8 = try allocator.dupe(u8, "unknown");

            // Open connection to get metadata
            var maybe_conn = connection.Connection.open(allocator, full_path) catch null;
            if (maybe_conn) |*conn| {
                if (schema.getSchemaVersion(conn.*, allocator)) |version| {
                    allocator.free(version);
                } else |_| {}
                // For now, use current time as placeholder
                if (time.nowUtc(allocator)) |now| {
                    allocator.free(created_at);
                    created_at = now;
                } else |_| {}
                conn.close(allocator);
            }

            const info = RoadmapInfo{
                .name = try allocator.dupe(u8, name),
                .path = try std.fmt.allocPrint(allocator, "~/.roadmaps/{s}", .{entry.name}),
                .size = @intCast(stat.size),
                .created_at = created_at,
            };
            try roadmaps.append(allocator, info);
        }
    }

    // Build JSON response
    return buildRoadmapListJson(allocator, roadmaps.items);
}

/// Creates a new roadmap
pub fn createRoadmap(allocator: std.mem.Allocator, name: []const u8, force: bool) ![]const u8 {
    // Validate name
    if (!isValidRoadmapName(name)) {
        return json.errorResponse(allocator, "INVALID_INPUT", "Invalid roadmap name. Use only alphanumeric, hyphens, and underscores (max 50 chars)");
    }

    // Get path
    const roadmap_path = path.getRoadmapPath(allocator, name) catch {
        return json.errorResponse(allocator, "SYSTEM_ERROR", "Failed to get roadmap path");
    };
    defer allocator.free(roadmap_path);

    // Check if exists
    if (path.fileExists(roadmap_path)) {
        if (!force) {
            const details = try std.fmt.allocPrint(allocator, "{{\"roadmap_name\":\"{s}\",\"existing_path\":\"{s}\"}}", .{ name, roadmap_path });
            defer allocator.free(details);
            const msg = try std.fmt.allocPrint(allocator, "Roadmap '{s}' already exists at {s}", .{ name, roadmap_path });
            defer allocator.free(msg);
            return json.errorResponseWithDetails(allocator, "ROADMAP_EXISTS", msg, details);
        }
        // Remove existing file
        std.fs.cwd().deleteFile(roadmap_path) catch {
            return json.errorResponse(allocator, "SYSTEM_ERROR", "Failed to remove existing roadmap");
        };
    }

    // Ensure directory exists
    path.ensureRoadmapsDirExists() catch {
        return json.errorResponse(allocator, "SYSTEM_ERROR", "Failed to create roadmaps directory");
    };

    // Create database
    var conn = connection.Connection.open(allocator, roadmap_path) catch {
        return json.errorResponse(allocator, "DB_ERROR", "Failed to create roadmap database");
    };
    defer conn.close(allocator);

    // Create schema
    schema.createSchema(conn) catch {
        return json.errorResponse(allocator, "DB_ERROR", "Failed to create database schema");
    };

    // Get current time
    const now = time.nowUtc(allocator) catch {
        return json.errorResponse(allocator, "SYSTEM_ERROR", "Failed to get current time");
    };
    defer allocator.free(now);

    // Log operation to audit table
    try queries.logOperation(conn, "ROADMAP_CREATE", "ROADMAP", 0, now);

    // Build response - simplified to return only the name
    const response = try std.fmt.allocPrint(allocator, "{{\"name\":\"{s}\"}}", .{name});
    defer allocator.free(response);

    return json.success(allocator, response);
}

/// Removes a roadmap
pub fn removeRoadmap(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    // Validate name to prevent path traversal
    if (!isValidRoadmapName(name)) {
        return json.errorResponse(allocator, "INVALID_INPUT", "Invalid roadmap name");
    }

    // Get path
    const roadmap_path = path.getRoadmapPath(allocator, name) catch {
        return json.errorResponse(allocator, "SYSTEM_ERROR", "Failed to get roadmap path");
    };
    defer allocator.free(roadmap_path);

    // Check if exists
    if (!path.fileExists(roadmap_path)) {
        return json.errorResponse(allocator, "ROADMAP_NOT_FOUND", "Roadmap not found");
    }

    // Validate it's a SQLite file
    if (!connection.isValidSQLiteFile(roadmap_path)) {
        return json.errorResponse(allocator, "INVALID_SQLITE_FILE", "File is not a valid SQLite database");
    }

    // Delete file
    std.fs.cwd().deleteFile(roadmap_path) catch {
        return json.errorResponse(allocator, "SYSTEM_ERROR", "Failed to remove roadmap");
    };

    // Get current time
    const now = time.nowUtc(allocator) catch {
        return json.errorResponse(allocator, "SYSTEM_ERROR", "Failed to get current time");
    };
    defer allocator.free(now);

    // Build response
    const response = try std.fmt.allocPrint(allocator, "{{\"name\":\"{s}\",\"removed_at\":\"{s}\"}}", .{ name, now });
    defer allocator.free(response);

    return json.success(allocator, response);
}

/// Sets the default roadmap
pub fn useRoadmap(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    // Validate name to prevent path traversal
    if (!isValidRoadmapName(name)) {
        return json.errorResponse(allocator, "INVALID_INPUT", "Invalid roadmap name");
    }

    // Get path
    const roadmap_path = path.getRoadmapPath(allocator, name) catch {
        return json.errorResponse(allocator, "SYSTEM_ERROR", "Failed to get roadmap path");
    };
    defer allocator.free(roadmap_path);

    // Check if exists
    if (!path.fileExists(roadmap_path)) {
        return json.errorResponse(allocator, "ROADMAP_NOT_FOUND", "Roadmap not found");
    }

    // Validate it's a SQLite file
    if (!connection.isValidSQLiteFile(roadmap_path)) {
        return json.errorResponse(allocator, "INVALID_SQLITE_FILE", "File is not a valid SQLite database");
    }

    // Get roadmaps dir
    const roadmaps_dir = path.getRoadmapsDir(allocator) catch {
        return json.errorResponse(allocator, "SYSTEM_ERROR", "Failed to get roadmaps directory");
    };
    defer allocator.free(roadmaps_dir);

    // Write current roadmap to file
    const current_file = try std.fs.path.join(allocator, &[_][]const u8{ roadmaps_dir, ".current" });
    defer allocator.free(current_file);

    const file = std.fs.cwd().createFile(current_file, .{}) catch {
        return json.errorResponse(allocator, "SYSTEM_ERROR", "Failed to save current roadmap");
    };
    defer file.close();

    file.writeAll(name) catch {
        return json.errorResponse(allocator, "SYSTEM_ERROR", "Failed to write current roadmap");
    };

    // Build response
    const response = try std.fmt.allocPrint(allocator, "{{\"name\":\"{s}\",\"message\":\"Roadmap set as default\"}}", .{name});
    defer allocator.free(response);

    return json.success(allocator, response);
}

/// Gets the current default roadmap
pub fn getCurrentRoadmap(allocator: std.mem.Allocator) !?[]const u8 {
    const roadmaps_dir = path.getRoadmapsDir(allocator) catch return null;
    defer allocator.free(roadmaps_dir);

    const current_file = try std.fs.path.join(allocator, &[_][]const u8{ roadmaps_dir, ".current" });
    defer allocator.free(current_file);

    const file = std.fs.cwd().openFile(current_file, .{}) catch return null;
    defer file.close();

    const content = file.readToEndAlloc(allocator, 1024) catch return null;
    return content;
}

/// Roadmap info structure
const RoadmapInfo = struct {
    name: []const u8,
    path: []const u8,
    size: i64,
    created_at: []const u8,
};

/// Builds JSON for roadmap list
fn buildRoadmapListJson(allocator: std.mem.Allocator, roadmaps: []const RoadmapInfo) ![]const u8 {
    var json_parts: std.array_list.Aligned([]const u8, null) = .empty;
    defer {
        for (json_parts.items) |p| {
            allocator.free(p);
        }
        json_parts.deinit(allocator);
    }

    for (roadmaps) |r| {
        const roadmap_json = try std.fmt.allocPrint(allocator,
            "{{\"name\":\"{s}\",\"path\":\"{s}\",\"size\":{d},\"created_at\":\"{s}\"}}",
            .{ r.name, r.path, r.size, r.created_at });
        try json_parts.append(allocator, roadmap_json);
    }

    const roadmaps_json = try std.mem.join(allocator, ",", json_parts.items);
    defer allocator.free(roadmaps_json);

    // Return array directly without wrapper
    const result = try std.fmt.allocPrint(allocator, "[{s}]", .{roadmaps_json});
    defer allocator.free(result);

    return json.success(allocator, result);
}

/// Validates a roadmap name
fn isValidRoadmapName(name: []const u8) bool {
    if (name.len == 0 or name.len > 50) return false;

    for (name) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '-' and c != '_') {
            return false;
        }
    }

    return true;
}

// ============== TESTS ==============

test "isValidRoadmapName" {
    try std.testing.expect(isValidRoadmapName("project1"));
    try std.testing.expect(isValidRoadmapName("my-project"));
    try std.testing.expect(isValidRoadmapName("my_project"));
    try std.testing.expect(!isValidRoadmapName(""));
    try std.testing.expect(!isValidRoadmapName("project with spaces"));
    try std.testing.expect(!isValidRoadmapName("project@#$"));
}
