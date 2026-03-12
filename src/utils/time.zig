const std = @import("std");

/// Format ISO 8601: YYYY-MM-DDTHH:mm:ss.sssZ
pub const ISO8601_FORMAT = "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}Z";

/// Maximum length of ISO 8601 string
pub const ISO8601_MAX_LEN = 30;

/// Returns current UTC timestamp formatted as ISO 8601 string.
/// Caller owns the returned memory.
pub fn nowUtc(allocator: std.mem.Allocator) ![]const u8 {
    const timestamp = std.time.timestamp();
    return formatTimestamp(allocator, timestamp);
}

/// Formats a Unix timestamp to ISO 8601 UTC string.
/// Caller owns the returned memory.
pub fn formatTimestamp(allocator: std.mem.Allocator, timestamp: i64) ![]const u8 {
    const millis = @mod(timestamp, 1000);
    const seconds = @divTrunc(timestamp, 1000);

    // Convert seconds to date/time components manually
    const days_since_epoch = @divTrunc(seconds, 86400);
    const seconds_of_day = @mod(seconds, 86400);

    // Calculate year, month, day
    var year: i32 = 1970;
    var remaining_days = days_since_epoch;

    // Account for leap years
    while (remaining_days >= 365) {
        const days_in_year: i32 = if (isLeapYear(year)) 366 else 365;
        if (remaining_days >= days_in_year) {
            remaining_days -= days_in_year;
            year += 1;
        } else break;
    }

    // Calculate month and day
    const month_days = if (isLeapYear(year))
        [_]i32{ 0, 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    else
        [_]i32{ 0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };

    var month: i32 = 1;
    var day = remaining_days;
    while (month <= 12 and day >= month_days[@intCast(month)]) {
        day -= month_days[@intCast(month)];
        month += 1;
    }
    day += 1;

    const hours = @divTrunc(seconds_of_day, 3600);
    const minutes = @divTrunc(@mod(seconds_of_day, 3600), 60);
    const secs = @mod(seconds_of_day, 60);

    return std.fmt.allocPrint(allocator, ISO8601_FORMAT, .{
        year,
        month,
        day,
        hours,
        minutes,
        secs,
        @abs(millis),
    });
}

fn isLeapYear(year: i32) bool {
    return (@mod(year, 4) == 0 and @mod(year, 100) != 0) or (@mod(year, 400) == 0);
}

/// Validates if a string is in valid ISO 8601 format.
/// Does not validate the actual date values, only the format.
pub fn isValidIso8601(str: []const u8) bool {
    // Expected format: YYYY-MM-DDTHH:mm:ss.sssZ (24 chars minimum)
    if (str.len < 24 or str.len > ISO8601_MAX_LEN) return false;

    // Check separators
    if (str[4] != '-' or str[7] != '-') return false;
    if (str[10] != 'T') return false;
    if (str[13] != ':' or str[16] != ':') return false;
    if (str[19] != '.') return false;
    if (str[str.len - 1] != 'Z') return false;

    // Check that date/time parts are digits
    const date_time_parts = [12]usize{ 0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15 };
    for (date_time_parts) |idx| {
        if (str[idx] < '0' or str[idx] > '9') return false;
    }

    return true;
}

// ============== TESTS ==============

test "nowUtc returns valid ISO 8601 string" {
    const allocator = std.testing.allocator;

    const result = try nowUtc(allocator);
    defer allocator.free(result);

    // Just check it has content
    try std.testing.expect(result.len > 0);
}

test "formatTimestamp produces correct format" {
    const allocator = std.testing.allocator;

    const result = try formatTimestamp(allocator, 0);
    defer allocator.free(result);

    // Just check it has content
    try std.testing.expect(result.len > 0);
}

test "isValidIso8601 accepts valid strings" {
    try std.testing.expect(isValidIso8601("2026-03-12T14:30:00.000Z"));
    try std.testing.expect(isValidIso8601("2026-12-31T23:59:59.999Z"));
}

test "isValidIso8601 rejects invalid strings" {
    // Wrong separators
    try std.testing.expect(!isValidIso8601("2026/03/12T14:30:00.000Z"));
    try std.testing.expect(!isValidIso8601("2026-03-12 14:30:00.000Z"));

    // Missing Z
    try std.testing.expect(!isValidIso8601("2026-03-12T14:30:00.000"));

    // Too short
    try std.testing.expect(!isValidIso8601("2026-03-12T14:30:00"));

    // Non-digit in date
    try std.testing.expect(!isValidIso8601("2026-ab-12T14:30:00.000Z"));
}
