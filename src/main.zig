const std = @import("std");
const cli = @import("cli.zig");

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

// Commands
const roadmap_cmd = @import("commands/roadmap.zig");
const task_cmd = @import("commands/task.zig");
const sprint_cmd = @import("commands/sprint.zig");

// Aliases for clarity
const roadmap_model = @import("models/roadmap.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    cli.run(allocator, args) catch |err| {
        const err_name = @errorName(err);
        const err_msg = "An unexpected error occurred during execution";

        const err_json = json.errorResponse(allocator, err_name, err_msg) catch "{\"success\":false,\"error\":{\"code\":\"FATAL\",\"message\":\"Critical system failure\"}}";
        defer if (!std.mem.eql(u8, err_json, "{\"success\":false,\"error\":{\"code\":\"FATAL\",\"message\":\"Critical system failure\"}}")) allocator.free(err_json);

        const stderr = std.fs.File.stderr().deprecatedWriter();
        stderr.print("{s}\n", .{err_json}) catch {};
        std.process.exit(1);
    };
}

// ============== TESTS ==============

test "all modules compile" {
    _ = time;
    _ = path;
    _ = json;
    _ = task;
    _ = sprint;
    _ = roadmap_model;
    _ = connection;
    _ = schema;
    _ = queries;
    _ = roadmap_cmd;
    _ = task_cmd;
    _ = sprint_cmd;
    _ = cli;
}
