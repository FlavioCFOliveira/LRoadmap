const std = @import("std");

/// Creates a success response.
/// Returns data as is (simply dupes it to maintain ownership consistency if needed,
/// but the goal is to return the direct JSON object/array).
/// Caller owns the returned memory.
pub fn success(allocator: std.mem.Allocator, data: []const u8) ![]const u8 {
    return try allocator.dupe(u8, data);
}

/// Creates an error response.
/// Caller owns the returned memory.
pub fn errorResponse(allocator: std.mem.Allocator, code: []const u8, message: []const u8) ![]const u8 {
    return try std.fmt.allocPrint(allocator, "{{\"code\":\"{s}\",\"message\":\"{s}\"}}", .{ code, message });
}

/// Creates an error response with details.
/// Caller owns the returned memory.
pub fn errorResponseWithDetails(allocator: std.mem.Allocator, code: []const u8, message: []const u8, details: []const u8) ![]const u8 {
    return try std.fmt.allocPrint(allocator, "{{\"code\":\"{s}\",\"message\":\"{s}\",\"details\":{s}}}", .{ code, message, details });
}

/// Common error codes
pub const ErrorCodes = struct {
    pub const INVALID_INPUT = "INVALID_INPUT";
    pub const ROADMAP_NOT_FOUND = "ROADMAP_NOT_FOUND";
    pub const ROADMAP_EXISTS = "ROADMAP_EXISTS";
    pub const INVALID_SQLITE_FILE = "INVALID_SQLITE_FILE";
    pub const TASK_NOT_FOUND = "TASK_NOT_FOUND";
    pub const SPRINT_NOT_FOUND = "SPRINT_NOT_FOUND";
    pub const INVALID_STATUS = "INVALID_STATUS";
    pub const INVALID_PRIORITY = "INVALID_PRIORITY";
    pub const DB_ERROR = "DB_ERROR";
    pub const SYSTEM_ERROR = "SYSTEM_ERROR";
};

/// Escapes a string for JSON output.
/// Caller owns the returned memory.
pub fn escapeString(allocator: std.mem.Allocator, str: []const u8) ![]const u8 {
    var escaped_len: usize = 2; // Opening and closing quotes
    for (str) |c| {
        switch (c) {
            '"', '\\', '\n', '\r', '\t' => escaped_len += 2,
            else => escaped_len += 1,
        }
    }

    var result = try allocator.alloc(u8, escaped_len);
    result[0] = '"';
    var i: usize = 1;

    for (str) |c| {
        switch (c) {
            '"' => {
                result[i] = '\\';
                result[i + 1] = '"';
                i += 2;
            },
            '\\' => {
                result[i] = '\\';
                result[i + 1] = '\\';
                i += 2;
            },
            '\n' => {
                result[i] = '\\';
                result[i + 1] = 'n';
                i += 2;
            },
            '\r' => {
                result[i] = '\\';
                result[i + 1] = 'r';
                i += 2;
            },
            '\t' => {
                result[i] = '\\';
                result[i + 1] = 't';
                i += 2;
            },
            else => {
                result[i] = c;
                i += 1;
            },
        }
    }
    result[i] = '"';

    return result;
}

/// Formats a JSON number value.
pub fn formatNumber(value: i64) []const u8 {
    var buf: [32]u8 = undefined;
    return std.fmt.bufPrint(&buf, "{d}", .{value}) catch unreachable;
}

// ============== TESTS ==============

test "success response returns data as is" {
    const allocator = std.testing.allocator;

    const data = "{\"name\":\"project1\"}";
    const result = try success(allocator, data);
    defer allocator.free(result);

    try std.testing.expectEqualStrings(data, result);
}

test "escapeString escapes special characters" {
    const allocator = std.testing.allocator;

    const result = try escapeString(allocator, "hello \"world\"");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("\"hello \\\"world\\\"\"", result);
}
