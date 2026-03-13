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

/// Parsed ISO 8601 date components
pub const Iso8601Components = struct {
    year: u16,
    month: u8,
    day: u8,
    hours: u8,
    minutes: u8,
    seconds: u8,
};

/// Parses an ISO 8601 string into components and validates the date values.
/// Returns error.InvalidIso8601 if the format is invalid or values are out of range.
pub fn parseIso8601(str: []const u8) !Iso8601Components {
    if (!isValidIso8601(str)) return error.InvalidIso8601;

    // Parse year (4 digits)
    const year = std.fmt.parseInt(u16, str[0..4], 10) catch return error.InvalidIso8601;
    if (year < 1970 or year > 2100) return error.InvalidIso8601;

    // Parse month (2 digits)
    const month = std.fmt.parseInt(u8, str[5..7], 10) catch return error.InvalidIso8601;
    if (month < 1 or month > 12) return error.InvalidIso8601;

    // Parse day (2 digits)
    const day = std.fmt.parseInt(u8, str[8..10], 10) catch return error.InvalidIso8601;
    const max_days = if (isLeapYear(year))
        [_]u8{ 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    else
        [_]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    if (day < 1 or day > max_days[month - 1]) return error.InvalidIso8601;

    // Parse hours (2 digits)
    const hours = std.fmt.parseInt(u8, str[11..13], 10) catch return error.InvalidIso8601;
    if (hours > 23) return error.InvalidIso8601;

    // Parse minutes (2 digits)
    const minutes = std.fmt.parseInt(u8, str[14..16], 10) catch return error.InvalidIso8601;
    if (minutes > 59) return error.InvalidIso8601;

    // Parse seconds (2 digits)
    const seconds = std.fmt.parseInt(u8, str[17..19], 10) catch return error.InvalidIso8601;
    if (seconds > 59) return error.InvalidIso8601;

    return Iso8601Components{
        .year = year,
        .month = month,
        .day = day,
        .hours = hours,
        .minutes = minutes,
        .seconds = seconds,
    };
}

/// Validates that "since" date is before or equal to "until" date.
/// Both dates must be valid ISO 8601 strings.
/// Returns true if dates are valid and since <= until.
pub fn isValidDateRange(since: []const u8, until: []const u8) bool {
    const since_components = parseIso8601(since) catch return false;
    const until_components = parseIso8601(until) catch return false;

    // Compare year
    if (since_components.year > until_components.year) return false;
    if (since_components.year < until_components.year) return true;

    // Same year, compare month
    if (since_components.month > until_components.month) return false;
    if (since_components.month < until_components.month) return true;

    // Same month, compare day
    if (since_components.day > until_components.day) return false;
    if (since_components.day < until_components.day) return true;

    // Same day, compare hours
    if (since_components.hours > until_components.hours) return false;
    if (since_components.hours < until_components.hours) return true;

    // Same hour, compare minutes
    if (since_components.minutes > until_components.minutes) return false;
    if (since_components.minutes < until_components.minutes) return true;

    // Same minute, compare seconds
    if (since_components.seconds > until_components.seconds) return false;

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

test "parseIso8601 validates correct dates" {
    const result = try parseIso8601("2024-03-12T14:40:00.000Z");
    try std.testing.expectEqual(@as(u16, 2024), result.year);
    try std.testing.expectEqual(@as(u8, 3), result.month);
    try std.testing.expectEqual(@as(u8, 12), result.day);
    try std.testing.expectEqual(@as(u8, 14), result.hours);
    try std.testing.expectEqual(@as(u8, 40), result.minutes);
    try std.testing.expectEqual(@as(u8, 0), result.seconds);
}

test "parseIso8601 rejects invalid format" {
    try std.testing.expectError(error.InvalidIso8601, parseIso8601("not-a-date"));
    try std.testing.expectError(error.InvalidIso8601, parseIso8601("2024-03-12"));
    try std.testing.expectError(error.InvalidIso8601, parseIso8601("2024/03/12T14:40:00Z"));
}

test "parseIso8601 rejects invalid dates" {
    // Invalid month
    try std.testing.expectError(error.InvalidIso8601, parseIso8601("2024-00-12T14:40:00.000Z"));
    try std.testing.expectError(error.InvalidIso8601, parseIso8601("2024-13-12T14:40:00.000Z"));
    // Invalid day
    try std.testing.expectError(error.InvalidIso8601, parseIso8601("2024-03-00T14:40:00.000Z"));
    try std.testing.expectError(error.InvalidIso8601, parseIso8601("2024-03-32T14:40:00.000Z"));
    // Invalid time
    try std.testing.expectError(error.InvalidIso8601, parseIso8601("2024-03-12T24:00:00.000Z"));
    try std.testing.expectError(error.InvalidIso8601, parseIso8601("2024-03-12T14:60:00.000Z"));
    try std.testing.expectError(error.InvalidIso8601, parseIso8601("2024-03-12T14:40:70.000Z"));
}

test "parseIso8601 handles leap years" {
    // Valid leap year date
    const result = try parseIso8601("2024-02-29T00:00:00.000Z");
    try std.testing.expectEqual(@as(u16, 2024), result.year);
    try std.testing.expectEqual(@as(u8, 2), result.month);
    try std.testing.expectEqual(@as(u8, 29), result.day);

    // Invalid leap year date (2023 is not a leap year)
    try std.testing.expectError(error.InvalidIso8601, parseIso8601("2023-02-29T00:00:00.000Z"));
}

test "isValidDateRange validates date ranges" {
    // Valid ranges
    try std.testing.expect(isValidDateRange("2024-03-01T00:00:00.000Z", "2024-03-12T00:00:00.000Z"));
    try std.testing.expect(isValidDateRange("2024-03-12T00:00:00.000Z", "2024-03-12T00:00:00.000Z")); // Same date

    // Invalid ranges
    try std.testing.expect(!isValidDateRange("2024-03-13T00:00:00.000Z", "2024-03-12T00:00:00.000Z"));
    try std.testing.expect(!isValidDateRange("2024-04-01T00:00:00.000Z", "2024-03-01T00:00:00.000Z"));
    try std.testing.expect(!isValidDateRange("2025-01-01T00:00:00.000Z", "2024-12-31T00:00:00.000Z"));
}
