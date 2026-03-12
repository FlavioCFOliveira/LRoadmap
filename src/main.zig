const std = @import("std");

// Utils
const time = @import("utils/time.zig");
const path = @import("utils/path.zig");
const json = @import("utils/json.zig");

// Models
const task = @import("models/task.zig");
const sprint = @import("models/sprint.zig");
const roadmap = @import("models/roadmap.zig");

pub fn main() !void {
    // Test time utility
    const allocator = std.heap.page_allocator;
    const now = time.nowUtc(allocator) catch "error";
    defer if (!std.mem.eql(u8, now, "error")) allocator.free(now);

    // Print basic info using posix write
    const msg = "LRoadmap CLI - Version 1.0.0-draft\nRun with: rmp --help\n\n";
    _ = std.posix.write(1, msg) catch {};

    const msg2 = "Utils loaded:\n";
    _ = std.posix.write(1, msg2) catch {};

    const msg3 = "  - time.zig: Current UTC: ";
    _ = std.posix.write(1, msg3) catch {};
    _ = std.posix.write(1, now) catch {};

    const msg4 = "\n  - path.zig: Roadmaps dir: ~/.roadmaps/\n";
    _ = std.posix.write(1, msg4) catch {};

    const msg5 = "  - json.zig: JSON response formatting ready\n";
    _ = std.posix.write(1, msg5) catch {};

    const msg6 = "\nModels loaded:\n";
    _ = std.posix.write(1, msg6) catch {};

    const msg7 = "  - task.zig: Task and TaskStatus\n";
    _ = std.posix.write(1, msg7) catch {};

    const msg8 = "  - sprint.zig: Sprint and SprintStatus\n";
    _ = std.posix.write(1, msg8) catch {};

    const msg9 = "  - roadmap.zig: Roadmap\n";
    _ = std.posix.write(1, msg9) catch {};
}

// ============== TESTS ==============

test "all modules compile" {
    _ = time;
    _ = path;
    _ = json;
    _ = task;
    _ = sprint;
    _ = roadmap;
}
