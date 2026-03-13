const std = @import("std");

/// Creates a success response JSON string.
/// Returns data wrapped in {"success": true, "data": {...}} format.
/// Caller owns the returned memory.
pub fn success(allocator: std.mem.Allocator, data: []const u8) ![]const u8 {
    // Return data wrapped in success envelope
    return std.fmt.allocPrint(allocator, "{{\"success\":true,\"data\":{s}}}", .{data});
}

/// Creates an error response JSON string.
/// Returns error wrapped in {"success": false, "error": {...}} format.
/// Caller owns the returned memory.
pub fn errorResponse(allocator: std.mem.Allocator, code: []const u8, message: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{{\"success\":false,\"error\":{{\"code\":\"{s}\",\"message\":\"{s}\"}}}}", .{ code, message });
}

/// Creates an error response with details JSON string.
/// Returns error wrapped in {"success": false, "error": {...}} format.
/// Caller owns the returned memory.
pub fn errorResponseWithDetails(allocator: std.mem.Allocator, code: []const u8, message: []const u8, details: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{{\"success\":false,\"error\":{{\"code\":\"{s}\",\"message\":\"{s}\",\"details\":{s}}}}}", .{ code, message, details });
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

test "success response returns data wrapped in success:true" {
    const allocator = std.testing.allocator;

    const data = "{\"name\":\"project1\"}";
    const result = try success(allocator, data);
    defer allocator.free(result);

    // Should return data wrapped in success:true envelope
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "\"success\":true"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "\"data\":{"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "\"name\":\"project1\""));
}

test "error response returns error wrapped in success:false" {
    const allocator = std.testing.allocator;

    const result = try errorResponse(allocator, "ROADMAP_NOT_FOUND", "Roadmap not found");
    defer allocator.free(result);

    // Should contain success:false wrapper
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "\"success\":false"));
    // Should contain error fields inside error object
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "\"error\":{"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "\"code\":\"ROADMAP_NOT_FOUND\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "\"message\":\"Roadmap not found\""));
}

test "error response with details" {
    const allocator = std.testing.allocator;

    const result = try errorResponseWithDetails(allocator, "INVALID_INPUT", "Missing field", "{\"field\":\"name\"}");
    defer allocator.free(result);

    // Should contain success:false wrapper with error object
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "\"success\":false"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "\"error\":{"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "\"code\":\"INVALID_INPUT\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "\"details\":{\"field\":\"name\"}"));
}

test "escapeString escapes special characters" {
    const allocator = std.testing.allocator;

    const result = try escapeString(allocator, "hello \"world\"");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("\"hello \\\"world\\\"\"", result);
}
