const std = @import("std");

// Utils
const time = @import("utils/time.zig");
const path = @import("utils/path.zig");
const json = @import("utils/json.zig");

// Models
const task = @import("models/task.zig");
const sprint = @import("models/sprint.zig");
const roadmap = @import("models/roadmap.zig");

// Database
const connection = @import("db/connection.zig");
const schema = @import("db/schema.zig");
const queries = @import("db/queries.zig");

pub fn main() !void {
    // Test time utility
    const allocator = std.heap.page_allocator;
    const now = time.nowUtc(allocator) catch "error";
    defer if (!std.mem.eql(u8, now, "error")) allocator.free(now);

    // Print basic info
    const msg = "LRoadmap CLI - Version 1.0.0-draft\nRun with: rmp --help\n\n";
    _ = std.posix.write(1, msg) catch {};

    const msg2 = "Utils loaded: time, path, json\n";
    _ = std.posix.write(1, msg2) catch {};

    const msg3 = "Models loaded: task, sprint, roadmap\n";
    _ = std.posix.write(1, msg3) catch {};

    const msg4 = "Database loaded: connection, schema, queries\n";
    _ = std.posix.write(1, msg4) catch {};
}

// ============== TESTS ==============

test "all modules compile" {
    _ = time;
    _ = path;
    _ = json;
    _ = task;
    _ = sprint;
    _ = roadmap;
    _ = connection;
    _ = schema;
    _ = queries;
}
