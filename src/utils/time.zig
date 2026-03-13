const std = @import("std");

/// Format ISO 8601: YYYY-MM-DDTHH:mm:ss.sssZ
pub const ISO8601_FORMAT = "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.000Z";

/// Maximum length of ISO 8601 string
pub const ISO8601_MAX_LEN = 30;

/// Returns current UTC timestamp formatted as ISO 8601 string.
/// Caller owns the returned memory.
pub fn nowUtc(allocator: std.mem.Allocator) ![]const u8 {
    const timestamp = std.time.timestamp();
    return formatTimestampSeconds(allocator, timestamp);
}

/// Formats a Unix timestamp (in seconds) to ISO 8601 UTC string.
/// Caller owns the returned memory.
pub fn formatTimestampSeconds(allocator: std.mem.Allocator, timestamp: i64) ![]const u8 {
    const seconds = if (timestamp < 0) 0 else @as(u64, @intCast(timestamp));

    const days_since_epoch = seconds / 86400;
    const seconds_of_day = seconds % 86400;

    var year: u16 = 1970;
    var remaining_days = days_since_epoch;

    while (true) {
        const days_in_year: u16 = if (isLeapYear(year)) 366 else 365;
        if (remaining_days >= days_in_year) {
            remaining_days -= days_in_year;
            year += 1;
        } else break;
    }

    const month_days = if (isLeapYear(year))
        [_]u16{ 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    else
        [_]u16{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };

    var month: u8 = 1;
    for (month_days) |md| {
        if (remaining_days >= md) {
            remaining_days -= md;
            month += 1;
        } else break;
    }
    const day: u8 = @intCast(remaining_days + 1);

    const hours = seconds_of_day / 3600;
    const minutes = (seconds_of_day % 3600) / 60;
    const secs = seconds_of_day % 60;

    return std.fmt.allocPrint(allocator, ISO8601_FORMAT, .{
        year,
        month,
        day,
        hours,
        minutes,
        secs,
    });
}

fn isLeapYear(year: u16) bool {
    return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0);
}

/// Validates if a string is in valid ISO 8601 format.
/// Does not validate the actual date values, only the format.
pub fn isValidIso8601(str: []const u8) bool {
    if (str.len < 20) return false;
    if (str[4] != '-' or str[7] != '-') return false;
    if (str[10] != 'T') return false;
    if (str[13] != ':' or str[16] != ':') return false;
    return true;
}

// ============== TESTS ==============

test "nowUtc returns valid ISO 8601 string" {
    const allocator = std.testing.allocator;
    const result = try nowUtc(allocator);
    defer allocator.free(result);
    try std.testing.expect(result.len >= 20);
}

test "formatTimestampSeconds produces correct format" {
    const allocator = std.testing.allocator;
    const result = try formatTimestampSeconds(allocator, 1710254400); // 2024-03-12T14:40:00Z
    defer allocator.free(result);
    try std.testing.expectEqualStrings("2024-03-12T14:40:00.000Z", result);
}
