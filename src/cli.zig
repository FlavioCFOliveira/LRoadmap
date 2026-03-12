const std = @import("std");
const json = @import("utils/json.zig");
const roadmap = @import("commands/roadmap.zig");
const task = @import("commands/task.zig");
const sprint = @import("commands/sprint.zig");

/// CLI command structure
const Command = struct {
    name: []const u8,
    subcommand: ?[]const u8,
    args: []const []const u8,
    flags: std.StringHashMap([]const u8),
};

/// Main entry point for CLI
pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 2) {
        printUsage();
        return;
    }

    const cmd = args[1];
    const subargs = args[2..];

    if (std.mem.eql(u8, cmd, "--help") or std.mem.eql(u8, cmd, "-h")) {
        printUsage();
        return;
    }

    if (std.mem.eql(u8, cmd, "--version") or std.mem.eql(u8, cmd, "-v")) {
        std.debug.print("LRoadmap v1.0.0\n", .{});
        return;
    }

    // Route to appropriate command handler
    if (std.mem.eql(u8, cmd, "roadmap")) {
        try handleRoadmapCommand(allocator, subargs);
    } else if (std.mem.eql(u8, cmd, "task")) {
        try handleTaskCommand(allocator, subargs);
    } else if (std.mem.eql(u8, cmd, "sprint")) {
        try handleSprintCommand(allocator, subargs);
    } else {
        std.debug.print("Unknown command: {s}\n", .{cmd});
        printUsage();
        std.process.exit(1);
    }
}

// ============== ROADMAP COMMANDS ==============

fn handleRoadmapCommand(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        // Default: list roadmaps
        const result = try roadmap.listRoadmaps(allocator);
        defer allocator.free(result);
        std.debug.print("{s}\n", .{result});
        return;
    }

    const subcmd = args[0];
    const subargs = args[1..];

    if (std.mem.eql(u8, subcmd, "list")) {
        const result = try roadmap.listRoadmaps(allocator);
        defer allocator.free(result);
        std.debug.print("{s}\n", .{result});
    } else if (std.mem.eql(u8, subcmd, "create")) {
        if (subargs.len < 1) {
            std.debug.print("Usage: rmp roadmap create <name> [--force]\n", .{});
            std.process.exit(1);
        }
        const name = subargs[0];
        const force = hasFlag(subargs, "--force");
        const result = try roadmap.createRoadmap(allocator, name, force);
        defer allocator.free(result);
        std.debug.print("{s}\n", .{result});
    } else if (std.mem.eql(u8, subcmd, "remove")) {
        if (subargs.len < 1) {
            std.debug.print("Usage: rmp roadmap remove <name>\n", .{});
            std.process.exit(1);
        }
        const name = subargs[0];
        const result = try roadmap.removeRoadmap(allocator, name);
        defer allocator.free(result);
        std.debug.print("{s}\n", .{result});
    } else if (std.mem.eql(u8, subcmd, "use")) {
        if (subargs.len < 1) {
            std.debug.print("Usage: rmp roadmap use <name>\n", .{});
            std.process.exit(1);
        }
        const name = subargs[0];
        const result = try roadmap.useRoadmap(allocator, name);
        defer allocator.free(result);
        std.debug.print("{s}\n", .{result});
    } else {
        std.debug.print("Unknown roadmap subcommand: {s}\n", .{subcmd});
        std.debug.print("Available: list, create, remove, use\n", .{});
        std.process.exit(1);
    }
}

// ============== TASK COMMANDS ==============

fn handleTaskCommand(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        // Default: list tasks
        const result = try task.listTasks(allocator, null);
        defer allocator.free(result);
        std.debug.print("{s}\n", .{result});
        return;
    }

    const subcmd = args[0];
    const subargs = args[1..];

    if (std.mem.eql(u8, subcmd, "list")) {
        const status_filter = getStatusFilter(subargs);
        const result = try task.listTasks(allocator, status_filter);
        defer allocator.free(result);
        std.debug.print("{s}\n", .{result});
    } else if (std.mem.eql(u8, subcmd, "add")) {
        try handleTaskAdd(allocator, subargs);
    } else if (std.mem.eql(u8, subcmd, "status")) {
        if (subargs.len < 2) {
            std.debug.print("Usage: rmp task status <id> <status>\n", .{});
            std.process.exit(1);
        }
        const id = std.fmt.parseInt(i64, subargs[0], 10) catch {
            std.debug.print("Invalid task ID: {s}\n", .{subargs[0]});
            std.process.exit(1);
        };
        const status = @import("models/task.zig").TaskStatus.fromString(subargs[1]) catch {
            std.debug.print("Invalid status: {s}\n", .{subargs[1]});
            std.process.exit(1);
        };
        const result = try task.changeTaskStatus(allocator, id, status);
        defer allocator.free(result);
        std.debug.print("{s}\n", .{result});
    } else if (std.mem.eql(u8, subcmd, "edit")) {
        try handleTaskEdit(allocator, subargs);
    } else if (std.mem.eql(u8, subcmd, "delete")) {
        if (subargs.len < 1) {
            std.debug.print("Usage: rmp task delete <id>\n", .{});
            std.process.exit(1);
        }
        const id = std.fmt.parseInt(i64, subargs[0], 10) catch {
            std.debug.print("Invalid task ID: {s}\n", .{subargs[0]});
            std.process.exit(1);
        };
        const result = try task.deleteTask(allocator, id);
        defer allocator.free(result);
        std.debug.print("{s}\n", .{result});
    } else {
        std.debug.print("Unknown task subcommand: {s}\n", .{subcmd});
        std.debug.print("Available: list, add, status, edit, delete\n", .{});
        std.process.exit(1);
    }
}

fn handleTaskAdd(allocator: std.mem.Allocator, args: []const []const u8) !void {
    // Parse task add arguments
    var priority: i32 = 0;
    var severity: i32 = 0;
    var description: ?[]const u8 = null;
    var specialists: ?[]const u8 = null;
    var action: ?[]const u8 = null;
    var expected_result: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-p") or std.mem.eql(u8, arg, "--priority")) {
            i += 1;
            if (i < args.len) {
                priority = std.fmt.parseInt(i32, args[i], 10) catch 0;
            }
        } else if (std.mem.eql(u8, arg, "-s") or std.mem.eql(u8, arg, "--severity")) {
            i += 1;
            if (i < args.len) {
                severity = std.fmt.parseInt(i32, args[i], 10) catch 0;
            }
        } else if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--description")) {
            i += 1;
            if (i < args.len) description = args[i];
        } else if (std.mem.eql(u8, arg, "-sp") or std.mem.eql(u8, arg, "--specialists")) {
            i += 1;
            if (i < args.len) specialists = args[i];
        } else if (std.mem.eql(u8, arg, "-a") or std.mem.eql(u8, arg, "--action")) {
            i += 1;
            if (i < args.len) action = args[i];
        } else if (std.mem.eql(u8, arg, "-e") or std.mem.eql(u8, arg, "--expected")) {
            i += 1;
            if (i < args.len) expected_result = args[i];
        }
    }

    if (description == null or action == null or expected_result == null) {
        std.debug.print("Usage: rmp task add -d <description> -a <action> -e <expected_result> [-p priority] [-s severity] [-sp specialists]\n", .{});
        std.process.exit(1);
    }

    const input = task.TaskInput{
        .priority = priority,
        .severity = severity,
        .description = description.?,
        .specialists = specialists,
        .action = action.?,
        .expected_result = expected_result.?,
    };

    const result = try task.addTask(allocator, input);
    defer allocator.free(result);
    std.debug.print("{s}\n", .{result});
}

fn handleTaskEdit(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.debug.print("Usage: rmp task edit <id> [options...]\n", .{});
        std.process.exit(1);
    }

    const id = std.fmt.parseInt(i64, args[0], 10) catch {
        std.debug.print("Invalid task ID: {s}\n", .{args[0]});
        std.process.exit(1);
    };

    var updates = task.TaskUpdate{
        .priority = null,
        .severity = null,
        .description = null,
        .specialists = null,
        .action = null,
        .expected_result = null,
    };

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-p") or std.mem.eql(u8, arg, "--priority")) {
            i += 1;
            if (i < args.len) {
                updates.priority = std.fmt.parseInt(i32, args[i], 10) catch null;
            }
        } else if (std.mem.eql(u8, arg, "-s") or std.mem.eql(u8, arg, "--severity")) {
            i += 1;
            if (i < args.len) {
                updates.severity = std.fmt.parseInt(i32, args[i], 10) catch null;
            }
        } else if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--description")) {
            i += 1;
            if (i < args.len) updates.description = args[i];
        } else if (std.mem.eql(u8, arg, "-sp") or std.mem.eql(u8, arg, "--specialists")) {
            i += 1;
            if (i < args.len) updates.specialists = args[i];
        } else if (std.mem.eql(u8, arg, "-a") or std.mem.eql(u8, arg, "--action")) {
            i += 1;
            if (i < args.len) updates.action = args[i];
        } else if (std.mem.eql(u8, arg, "-e") or std.mem.eql(u8, arg, "--expected")) {
            i += 1;
            if (i < args.len) updates.expected_result = args[i];
        }
    }

    const result = try task.editTask(allocator, id, updates);
    defer allocator.free(result);
    std.debug.print("{s}\n", .{result});
}

// ============== SPRINT COMMANDS ==============

fn handleSprintCommand(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        // Default: list sprints
        const result = try sprint.listSprints(allocator, null);
        defer allocator.free(result);
        std.debug.print("{s}\n", .{result});
        return;
    }

    const subcmd = args[0];
    const subargs = args[1..];

    if (std.mem.eql(u8, subcmd, "list")) {
        const status_filter = getSprintStatusFilter(subargs);
        const result = try sprint.listSprints(allocator, status_filter);
        defer allocator.free(result);
        std.debug.print("{s}\n", .{result});
    } else if (std.mem.eql(u8, subcmd, "add")) {
        if (subargs.len < 1) {
            std.debug.print("Usage: rmp sprint add <description>\n", .{});
            std.process.exit(1);
        }
        const description = try std.mem.join(allocator, " ", subargs);
        defer allocator.free(description);
        const result = try sprint.addSprint(allocator, description);
        defer allocator.free(result);
        std.debug.print("{s}\n", .{result});
    } else if (std.mem.eql(u8, subcmd, "open")) {
        if (subargs.len < 1) {
            std.debug.print("Usage: rmp sprint open <id>\n", .{});
            std.process.exit(1);
        }
        const id = std.fmt.parseInt(i64, subargs[0], 10) catch {
            std.debug.print("Invalid sprint ID: {s}\n", .{subargs[0]});
            std.process.exit(1);
        };
        const result = try sprint.openSprint(allocator, id);
        defer allocator.free(result);
        std.debug.print("{s}\n", .{result});
    } else if (std.mem.eql(u8, subcmd, "close")) {
        if (subargs.len < 1) {
            std.debug.print("Usage: rmp sprint close <id>\n", .{});
            std.process.exit(1);
        }
        const id = std.fmt.parseInt(i64, subargs[0], 10) catch {
            std.debug.print("Invalid sprint ID: {s}\n", .{subargs[0]});
            std.process.exit(1);
        };
        const result = try sprint.closeSprint(allocator, id);
        defer allocator.free(result);
        std.debug.print("{s}\n", .{result});
    } else if (std.mem.eql(u8, subcmd, "add-task")) {
        if (subargs.len < 2) {
            std.debug.print("Usage: rmp sprint add-task <sprint_id> <task_id>\n", .{});
            std.process.exit(1);
        }
        const sprint_id = std.fmt.parseInt(i64, subargs[0], 10) catch {
            std.debug.print("Invalid sprint ID: {s}\n", .{subargs[0]});
            std.process.exit(1);
        };
        const task_id = std.fmt.parseInt(i64, subargs[1], 10) catch {
            std.debug.print("Invalid task ID: {s}\n", .{subargs[1]});
            std.process.exit(1);
        };
        const result = try sprint.addTaskToSprint(allocator, sprint_id, task_id);
        defer allocator.free(result);
        std.debug.print("{s}\n", .{result});
    } else if (std.mem.eql(u8, subcmd, "remove-task")) {
        if (subargs.len < 1) {
            std.debug.print("Usage: rmp sprint remove-task <task_id>\n", .{});
            std.process.exit(1);
        }
        const task_id = std.fmt.parseInt(i64, subargs[0], 10) catch {
            std.debug.print("Invalid task ID: {s}\n", .{subargs[0]});
            std.process.exit(1);
        };
        const result = try sprint.removeTaskFromSprint(allocator, task_id);
        defer allocator.free(result);
        std.debug.print("{s}\n", .{result});
    } else {
        std.debug.print("Unknown sprint subcommand: {s}\n", .{subcmd});
        std.debug.print("Available: list, add, open, close, add-task, remove-task\n", .{});
        std.process.exit(1);
    }
}

// ============== UTILITY FUNCTIONS ==============

fn hasFlag(args: []const []const u8, flag: []const u8) bool {
    for (args) |arg| {
        if (std.mem.eql(u8, arg, flag)) return true;
    }
    return false;
}

fn getStatusFilter(args: []const []const u8) ?@import("models/task.zig").TaskStatus {
    for (args, 0..) |arg, i| {
        if ((std.mem.eql(u8, arg, "--status") or std.mem.eql(u8, arg, "-s")) and i + 1 < args.len) {
            return @import("models/task.zig").TaskStatus.fromString(args[i + 1]) catch return null;
        }
    }
    return null;
}

fn getSprintStatusFilter(args: []const []const u8) ?@import("models/sprint.zig").SprintStatus {
    for (args, 0..) |arg, i| {
        if ((std.mem.eql(u8, arg, "--status") or std.mem.eql(u8, arg, "-s")) and i + 1 < args.len) {
            return @import("models/sprint.zig").SprintStatus.fromString(args[i + 1]) catch null;
        }
    }
    return null;
}

fn printUsage() void {
    const usage =
        \\LRoadmap CLI v1.0.0 - Technical Roadmap Management Tool
        \\
        \\USAGE:
        \\  rmp <command> [subcommand] [options]
        \\
        \\COMMANDS:
        \\  roadmap              Manage roadmaps
        \\    list              List all roadmaps (default)
        \\    create <name>     Create a new roadmap
        \\    remove <name>       Remove a roadmap
        \\    use <name>         Set default roadmap
        \\
        \\  task                 Manage tasks in current roadmap
        \\    list              List all tasks (default)
        \\    add               Add a new task
        \\      -d, --description <text>   Task description
        \\      -a, --action <text>        Action to perform
        \\      -e, --expected <text>      Expected result
        \\      -p, --priority <0-9>       Priority (default: 0)
        \\      -s, --severity <0-9>       Severity (default: 0)
        \\      -sp, --specialists <text>   Specialists
        \\    status <id> <status>  Change task status
        \\    edit <id> [options]   Edit task
        \\    delete <id>         Delete task
        \\
        \\  sprint               Manage sprints
        \\    list              List all sprints (default)
        \\    add <description>  Create a new sprint
        \\    open <id>          Open a sprint
        \\    close <id>         Close a sprint
        \\    add-task <sprint_id> <task_id>  Add task to sprint
        \\    remove-task <task_id>           Remove task from sprint
        \\
        \\OPTIONS:
        \\  -h, --help          Show this help
        \\  -v, --version       Show version
        \\
    ;
    std.debug.print("{s}", .{usage});
}
