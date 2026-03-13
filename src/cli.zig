const std = @import("std");
const json = @import("utils/json.zig");
const roadmap = @import("commands/roadmap.zig");
const task = @import("commands/task.zig");
const sprint = @import("commands/sprint.zig");
const audit = @import("commands/audit.zig");
const Task = @import("models/task.zig").Task;

/// CLI command structure
const Command = struct {
    name: []const u8,
    subcommand: ?[]const u8,
    args: []const []const u8,
    flags: std.StringHashMap([]const u8),
};

fn printStdout(comptime fmt: []const u8, args: anytype) void {
    const stdout = std.fs.File.stdout().deprecatedWriter();
    stdout.print(fmt, args) catch {};
}

fn printError(allocator: std.mem.Allocator, code: []const u8, message: []const u8) void {
    const err_json = json.errorResponse(allocator, code, message) catch "{\"success\":false,\"error\":{\"code\":\"SYSTEM_ERROR\",\"message\":\"Failed to generate error response\"}}";
    defer if (!std.mem.eql(u8, err_json, "{\"success\":false,\"error\":{\"code\":\"SYSTEM_ERROR\",\"message\":\"Failed to generate error response\"}}")) allocator.free(err_json);
    printStdout("{s}\n", .{err_json});
}

/// Main entry point for CLI
pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 2) {
        printUsage(allocator);
        return;
    }

    // Check for global flags before the command
    var cmd_idx: usize = 1;
    var roadmap_override: ?[]const u8 = null;

    while (cmd_idx < args.len) {
        const arg = args[cmd_idx];
        if (std.mem.eql(u8, arg, "-r") or std.mem.eql(u8, arg, "--roadmap")) {
            cmd_idx += 1;
            if (cmd_idx < args.len) {
                roadmap_override = args[cmd_idx];
                cmd_idx += 1;
            }
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printUsage(allocator);
            return;
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            printStdout("LRoadmap v1.0.0\n", .{});
            return;
        } else {
            // This must be the command
            break;
        }
    }

    if (cmd_idx >= args.len) {
        printUsage(allocator);
        return;
    }

    const cmd = args[cmd_idx];
    const subargs = args[cmd_idx + 1 ..];

    // If we have an override, set it as current for this session
    if (roadmap_override) |r| {
        const res = try roadmap.useRoadmap(allocator, r);
        defer allocator.free(res);
        if (std.mem.indexOf(u8, res, "\"success\":false") != null) {
            printStdout("{s}\n", .{res});
            std.process.exit(1);
        }
    }

    // Route to appropriate command handler
    if (std.mem.eql(u8, cmd, "roadmap") or std.mem.eql(u8, cmd, "road")) {
        try handleRoadmapCommand(allocator, subargs);
    } else if (std.mem.eql(u8, cmd, "task")) {
        try handleTaskCommand(allocator, subargs);
    } else if (std.mem.eql(u8, cmd, "sprint")) {
        try handleSprintCommand(allocator, subargs);
    } else if (std.mem.eql(u8, cmd, "audit")) {
        try handleAuditCommand(allocator, subargs);
    } else {
        printError(allocator, "UNKNOWN_COMMAND", try std.fmt.allocPrint(allocator, "Unknown command: {s}", .{cmd}));
        std.process.exit(1);
    }
}

// ============== ROADMAP COMMANDS ==============

fn handleRoadmapCommand(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len > 0 and (std.mem.eql(u8, args[0], "-h") or std.mem.eql(u8, args[0], "--help"))) {
        printCommandHelp(allocator, "roadmap");
        return;
    }
    if (args.len == 0) {
        // Default: list roadmaps
        const result = try roadmap.listRoadmaps(allocator);
        defer allocator.free(result);
        printStdout("{s}\n", .{result});
        return;
    }

    const subcmd = args[0];
    const subargs = args[1..];

    if (std.mem.eql(u8, subcmd, "list") or std.mem.eql(u8, subcmd, "ls")) {
        const result = try roadmap.listRoadmaps(allocator);
        defer allocator.free(result);
        printStdout("{s}\n", .{result});
    } else if (std.mem.eql(u8, subcmd, "create") or std.mem.eql(u8, subcmd, "new")) {
        if (subargs.len < 1) {
            printError(allocator, "INVALID_INPUT", "Usage: rmp roadmap create <name> [--force]");
            std.process.exit(1);
        }
        const name = subargs[0];
        const force = hasFlag(subargs, "--force");
        const result = try roadmap.createRoadmap(allocator, name, force);
        defer allocator.free(result);
        printStdout("{s}\n", .{result});
    } else if (std.mem.eql(u8, subcmd, "remove") or std.mem.eql(u8, subcmd, "rm") or std.mem.eql(u8, subcmd, "delete")) {
        if (subargs.len < 1) {
            printError(allocator, "INVALID_INPUT", "Usage: rmp roadmap remove <name>");
            std.process.exit(1);
        }
        const name = subargs[0];
        const result = try roadmap.removeRoadmap(allocator, name);
        defer allocator.free(result);
        printStdout("{s}\n", .{result});
    } else if (std.mem.eql(u8, subcmd, "use")) {
        if (subargs.len < 1) {
            printError(allocator, "INVALID_INPUT", "Usage: rmp roadmap use <name>");
            std.process.exit(1);
        }
        const name = subargs[0];
        const result = try roadmap.useRoadmap(allocator, name);
        defer allocator.free(result);
        printStdout("{s}\n", .{result});
    } else {
        printError(allocator, "UNKNOWN_SUBCOMMAND", try std.fmt.allocPrint(allocator, "Unknown roadmap subcommand: {s}", .{subcmd}));
        std.process.exit(1);
    }
}

// ============== TASK COMMANDS ==============

fn handleTaskCommand(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len > 0 and (std.mem.eql(u8, args[0], "-h") or std.mem.eql(u8, args[0], "--help"))) {
        printCommandHelp(allocator, "task");
        return;
    }
    if (args.len == 0) {
        // Default: list tasks
        const filters = @import("db/queries.zig").TaskFilterOptions{};
        const result = try task.listTasks(allocator, filters);
        defer allocator.free(result);
        printStdout("{s}\n", .{result});
        return;
    }

    const subcmd = args[0];
    const subargs = args[1..];

    if (subcmd.len == 0) {
        printUsage(allocator);
        return;
    }

    if (std.mem.eql(u8, subcmd, "list") or std.mem.eql(u8, subcmd, "ls")) {
        const status_filter = getStatusFilter(subargs);
        const priority_min = getPriorityMinFilter(subargs);
        const severity_min = getSeverityMinFilter(subargs);
        const limit = getLimitFilter(subargs);

        const filters = @import("db/queries.zig").TaskFilterOptions{
            .status = status_filter,
            .priority_min = priority_min,
            .severity_min = severity_min,
            .limit = limit,
        };

        const result = try task.listTasks(allocator, filters);
        defer allocator.free(result);
        printStdout("{s}\n", .{result});
    } else if (std.mem.eql(u8, subcmd, "get")) {
        if (subargs.len < 1) {
            printError(allocator, "INVALID_INPUT", "Usage: rmp task get <ids>");
            std.process.exit(1);
        }
        if (subargs.len > 1) {
            printError(allocator, "INVALID_INPUT", "Too many arguments for 'task get'. Only 1 comma-separated ID list is allowed.");
            std.process.exit(1);
        }
        const ids = parseIds(allocator, subargs[0]) catch |err| {
            const err_msg = switch (err) {
                error.InvalidCharacter => try std.fmt.allocPrint(allocator, "Invalid character in task IDs: {s}", .{subargs[0]}),
                error.Overflow => try std.fmt.allocPrint(allocator, "Task ID too large: {s}", .{subargs[0]}),
                else => try std.fmt.allocPrint(allocator, "Invalid task IDs: {s} (error: {any})", .{ subargs[0], err }),
            };
            defer allocator.free(err_msg);
            printError(allocator, "INVALID_INPUT", err_msg);
            std.process.exit(1);
        };
        defer allocator.free(ids);

        if (ids.len == 0) {
            printError(allocator, "INVALID_INPUT", "No task IDs provided");
            std.process.exit(1);
        }

        var results_list: std.ArrayListUnmanaged([]const u8) = .empty;
        defer {
            for (results_list.items) |r| allocator.free(r);
            results_list.deinit(allocator);
        }

        for (ids) |id| {
            const res = task.getTask(allocator, id) catch |err| {
                const err_json = try json.errorResponse(allocator, "TASK_NOT_FOUND", try std.fmt.allocPrint(allocator, "Task {d} not found (error: {any})", .{ id, err }));
                try results_list.append(allocator, err_json);
                continue;
            };
            try results_list.append(allocator, res);
        }

        const final_json = try buildBulkResponse(allocator, results_list.items);
        defer allocator.free(final_json);
        printStdout("{s}\n", .{final_json});
    } else if (std.mem.eql(u8, subcmd, "add") or std.mem.eql(u8, subcmd, "new")) {
        try handleTaskAdd(allocator, subargs);
    } else if (std.mem.eql(u8, subcmd, "status") or std.mem.eql(u8, subcmd, "stat")) {
        if (subargs.len < 2) {
            printError(allocator, "INVALID_INPUT", "Usage: rmp task status <ids> <status>");
            std.process.exit(1);
        }
        if (subargs.len > 2) {
            printError(allocator, "INVALID_INPUT", "Too many arguments for 'task status'. Usage: rmp task status <ids> <status>");
            std.process.exit(1);
        }
        const ids = parseIds(allocator, subargs[0]) catch |err| {
            printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid task IDs: {s} (error: {any})", .{ subargs[0], err }));
            std.process.exit(1);
        };
        defer allocator.free(ids);

        const status = @import("models/task.zig").TaskStatus.fromString(subargs[1]) catch {
            printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid status: {s}", .{subargs[1]}));
            std.process.exit(1);
        };

        var results_list: std.ArrayListUnmanaged([]const u8) = .empty;
        defer {
            for (results_list.items) |r| allocator.free(r);
            results_list.deinit(allocator);
        }

        for (ids) |id| {
            const res = task.changeTaskStatus(allocator, id, status) catch |err| {
                const err_json = try json.errorResponse(allocator, "UPDATE_FAILED", try std.fmt.allocPrint(allocator, "Failed to update task {d} (error: {any})", .{ id, err }));
                try results_list.append(allocator, err_json);
                continue;
            };
            try results_list.append(allocator, res);
        }

        const final_json = try buildBulkResponse(allocator, results_list.items);
        defer allocator.free(final_json);
        printStdout("{s}\n", .{final_json});
    } else if (std.mem.eql(u8, subcmd, "prio") or std.mem.eql(u8, subcmd, "priority")) {
        if (subargs.len < 2) {
            printError(allocator, "INVALID_INPUT", "Usage: rmp task prio <ids> <priority>");
            std.process.exit(1);
        }
        if (subargs.len > 2) {
            printError(allocator, "INVALID_INPUT", "Too many arguments for 'task prio'. Usage: rmp task prio <ids> <priority>");
            std.process.exit(1);
        }
        const ids = parseIds(allocator, subargs[0]) catch |err| {
            printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid task IDs: {s} (error: {any})", .{ subargs[0], err }));
            std.process.exit(1);
        };
        defer allocator.free(ids);

        const priority = std.fmt.parseInt(i32, subargs[1], 10) catch {
            printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid priority: {s}", .{subargs[1]}));
            std.process.exit(1);
        };

        if (priority < 0 or priority > 9) {
            printError(allocator, "INVALID_PRIORITY", "Priority must be between 0 and 9");
            std.process.exit(1);
        }

        var results_list: std.ArrayListUnmanaged([]const u8) = .empty;
        defer {
            for (results_list.items) |r| allocator.free(r);
            results_list.deinit(allocator);
        }

        for (ids) |id| {
            const res = task.setPriority(allocator, id, priority) catch |err| {
                const err_json = try json.errorResponse(allocator, "UPDATE_FAILED", try std.fmt.allocPrint(allocator, "Failed to set priority for task {d} (error: {any})", .{ id, err }));
                try results_list.append(allocator, err_json);
                continue;
            };
            try results_list.append(allocator, res);
        }

        const final_json = try buildBulkResponse(allocator, results_list.items);
        defer allocator.free(final_json);
        printStdout("{s}\n", .{final_json});
    } else if (std.mem.eql(u8, subcmd, "sev") or std.mem.eql(u8, subcmd, "severity")) {
        if (subargs.len < 2) {
            printError(allocator, "INVALID_INPUT", "Usage: rmp task sev <ids> <severity>");
            std.process.exit(1);
        }
        if (subargs.len > 2) {
            printError(allocator, "INVALID_INPUT", "Too many arguments for 'task sev'. Usage: rmp task sev <ids> <severity>");
            std.process.exit(1);
        }
        const ids = parseIds(allocator, subargs[0]) catch |err| {
            printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid task IDs: {s} (error: {any})", .{ subargs[0], err }));
            std.process.exit(1);
        };
        defer allocator.free(ids);

        const severity = std.fmt.parseInt(i32, subargs[1], 10) catch {
            printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid severity: {s}", .{subargs[1]}));
            std.process.exit(1);
        };

        if (severity < 0 or severity > 9) {
            printError(allocator, "INVALID_INPUT", "Severity must be between 0 and 9");
            std.process.exit(1);
        }

        var results_list: std.ArrayListUnmanaged([]const u8) = .empty;
        defer {
            for (results_list.items) |r| allocator.free(r);
            results_list.deinit(allocator);
        }

        for (ids) |id| {
            const res = task.setSeverity(allocator, id, severity) catch |err| {
                const err_json = try json.errorResponse(allocator, "UPDATE_FAILED", try std.fmt.allocPrint(allocator, "Failed to set severity for task {d} (error: {any})", .{ id, err }));
                try results_list.append(allocator, err_json);
                continue;
            };
            try results_list.append(allocator, res);
        }

        const final_json = try buildBulkResponse(allocator, results_list.items);
        defer allocator.free(final_json);
        printStdout("{s}\n", .{final_json});
    } else if (std.mem.eql(u8, subcmd, "edit")) {
        try handleTaskEdit(allocator, subargs);
    } else if (std.mem.eql(u8, subcmd, "delete") or std.mem.eql(u8, subcmd, "rm")) {
        if (subargs.len < 1) {
            printError(allocator, "INVALID_INPUT", "Usage: rmp task delete <ids>");
            std.process.exit(1);
        }
        const ids = parseIds(allocator, subargs[0]) catch |err| {
            printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid task IDs: {s} (error: {any})", .{ subargs[0], err }));
            std.process.exit(1);
        };
        defer allocator.free(ids);

        var results_list: std.ArrayListUnmanaged([]const u8) = .empty;
        defer {
            for (results_list.items) |r| allocator.free(r);
            results_list.deinit(allocator);
        }

        for (ids) |id| {
            const res = task.deleteTask(allocator, id) catch |err| {
                const err_json = try json.errorResponse(allocator, "DELETE_FAILED", try std.fmt.allocPrint(allocator, "Failed to delete task {d} (error: {any})", .{ id, err }));
                try results_list.append(allocator, err_json);
                continue;
            };
            try results_list.append(allocator, res);
        }

        const final_json = try buildBulkResponse(allocator, results_list.items);
        defer allocator.free(final_json);
        printStdout("{s}\n", .{final_json});
    } else {
        printStdout("Unknown task subcommand: {s}\n", .{subcmd});
        printStdout("Available: list, get, add, status, prio, sev, edit, delete\n", .{});
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
                priority = std.fmt.parseInt(i32, args[i], 10) catch {
                    printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid priority value: {s}. Must be 0-9.", .{args[i]}));
                    std.process.exit(1);
                };
                if (priority < 0 or priority > 9) {
                    printError(allocator, "INVALID_PRIORITY", "Priority must be between 0 and 9");
                    std.process.exit(1);
                }
            } else {
                printError(allocator, "INVALID_INPUT", "Missing value for priority flag");
                std.process.exit(1);
            }
        } else if (std.mem.eql(u8, arg, "-s") or std.mem.eql(u8, arg, "--severity")) {
            i += 1;
            if (i < args.len) {
                severity = std.fmt.parseInt(i32, args[i], 10) catch {
                    printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid severity value: {s}. Must be 0-9.", .{args[i]}));
                    std.process.exit(1);
                };
                if (severity < 0 or severity > 9) {
                    printError(allocator, "INVALID_INPUT", "Severity must be between 0 and 9");
                    std.process.exit(1);
                }
            } else {
                printError(allocator, "INVALID_INPUT", "Missing value for severity flag");
                std.process.exit(1);
            }
        } else if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--description")) {
            i += 1;
            if (i < args.len) {
                description = args[i];
            } else {
                printError(allocator, "INVALID_INPUT", "Missing value for description flag");
                std.process.exit(1);
            }
        } else if (std.mem.eql(u8, arg, "-sp") or std.mem.eql(u8, arg, "--specialists")) {
            i += 1;
            if (i < args.len) {
                specialists = args[i];
            } else {
                printError(allocator, "INVALID_INPUT", "Missing value for specialists flag");
                std.process.exit(1);
            }
        } else if (std.mem.eql(u8, arg, "-a") or std.mem.eql(u8, arg, "--action")) {
            i += 1;
            if (i < args.len) {
                action = args[i];
            } else {
                printError(allocator, "INVALID_INPUT", "Missing value for action flag");
                std.process.exit(1);
            }
        } else if (std.mem.eql(u8, arg, "-e") or std.mem.eql(u8, arg, "--expected")) {
            i += 1;
            if (i < args.len) {
                expected_result = args[i];
            } else {
                printError(allocator, "INVALID_INPUT", "Missing value for expected flag");
                std.process.exit(1);
            }
        }
    }

    if (description == null or action == null or expected_result == null) {
        const err_json = try json.errorResponse(allocator, "INVALID_INPUT", "Missing required fields. Usage: rmp task add -d <description> -a <action> -e <expected_result> [-p priority] [-s severity] [-sp specialists]");
        defer allocator.free(err_json);
        printStdout("{s}\n", .{err_json});
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
    printStdout("{s}\n", .{result});
}

fn handleTaskEdit(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        printError(allocator, "INVALID_INPUT", "Usage: rmp task edit <id> [options...]");
        std.process.exit(1);
    }

    const id = std.fmt.parseInt(i64, args[0], 10) catch {
        printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid task ID: {s}", .{args[0]}));
        std.process.exit(1);
    };

    var updates = Task.TaskUpdate{
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
                updates.priority = std.fmt.parseInt(i32, args[i], 10) catch {
                    printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid priority value: {s}. Must be 0-9.", .{args[i]}));
                    std.process.exit(1);
                };
            } else {
                printError(allocator, "INVALID_INPUT", "Missing value for priority flag");
                std.process.exit(1);
            }
        } else if (std.mem.eql(u8, arg, "-s") or std.mem.eql(u8, arg, "--severity")) {
            i += 1;
            if (i < args.len) {
                updates.severity = std.fmt.parseInt(i32, args[i], 10) catch {
                    printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid severity value: {s}. Must be 0-9.", .{args[i]}));
                    std.process.exit(1);
                };
            } else {
                printError(allocator, "INVALID_INPUT", "Missing value for severity flag");
                std.process.exit(1);
            }
        } else if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--description")) {
            i += 1;
            if (i < args.len) {
                updates.description = args[i];
            } else {
                printError(allocator, "INVALID_INPUT", "Missing value for description flag");
                std.process.exit(1);
            }
        } else if (std.mem.eql(u8, arg, "-sp") or std.mem.eql(u8, arg, "--specialists")) {
            i += 1;
            if (i < args.len) {
                updates.specialists = args[i];
            } else {
                printError(allocator, "INVALID_INPUT", "Missing value for specialists flag");
                std.process.exit(1);
            }
        } else if (std.mem.eql(u8, arg, "-a") or std.mem.eql(u8, arg, "--action")) {
            i += 1;
            if (i < args.len) {
                updates.action = args[i];
            } else {
                printError(allocator, "INVALID_INPUT", "Missing value for action flag");
                std.process.exit(1);
            }
        } else if (std.mem.eql(u8, arg, "-e") or std.mem.eql(u8, arg, "--expected")) {
            i += 1;
            if (i < args.len) {
                updates.expected_result = args[i];
            } else {
                printError(allocator, "INVALID_INPUT", "Missing value for expected flag");
                std.process.exit(1);
            }
        }
    }

    if (updates.priority) |p| {
        if (p < 0 or p > 9) {
            printError(allocator, "INVALID_PRIORITY", "Priority must be between 0 and 9");
            std.process.exit(1);
        }
    }

    if (updates.severity) |s| {
        if (s < 0 or s > 9) {
            printError(allocator, "INVALID_INPUT", "Severity must be between 0 and 9");
            std.process.exit(1);
        }
    }

    const result = try task.editTask(allocator, id, updates);
    defer allocator.free(result);
    printStdout("{s}\n", .{result});
}

// ============== SPRINT COMMANDS ==============

fn handleSprintCommand(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len > 0 and (std.mem.eql(u8, args[0], "-h") or std.mem.eql(u8, args[0], "--help"))) {
        printCommandHelp(allocator, "sprint");
        return;
    }
    if (args.len == 0) {
        // Default: list sprints
        const result = try sprint.listSprints(allocator, null);
        defer allocator.free(result);
        printStdout("{s}\n", .{result});
        return;
    }

    const subcmd = args[0];
    const subargs = args[1..];

    if (std.mem.eql(u8, subcmd, "list") or std.mem.eql(u8, subcmd, "ls")) {
        const status_filter = getSprintStatusFilter(subargs);
        const result = try sprint.listSprints(allocator, status_filter);
        defer allocator.free(result);
        printStdout("{s}\n", .{result});
    } else if (std.mem.eql(u8, subcmd, "get")) {
        if (subargs.len < 1) {
            printError(allocator, "INVALID_INPUT", "Usage: rmp sprint get <id>");
            std.process.exit(1);
        }
        const id = std.fmt.parseInt(i64, subargs[0], 10) catch {
            printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid sprint ID: {s}", .{subargs[0]}));
            std.process.exit(1);
        };
        const result = try sprint.getSprint(allocator, id);
        defer allocator.free(result);
        printStdout("{s}\n", .{result});
    } else if (std.mem.eql(u8, subcmd, "tasks")) {
        if (subargs.len < 1) {
            printError(allocator, "INVALID_INPUT", "Usage: rmp sprint tasks <id>");
            std.process.exit(1);
        }
        const id = std.fmt.parseInt(i64, subargs[0], 10) catch {
            printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid sprint ID: {s}", .{subargs[0]}));
            std.process.exit(1);
        };
        const status_filter = getStatusFilter(subargs);
        const result = try sprint.listSprintTasks(allocator, id, status_filter);
        defer allocator.free(result);
        printStdout("{s}\n", .{result});
    } else if (std.mem.eql(u8, subcmd, "add") or std.mem.eql(u8, subcmd, "new")) {
        if (subargs.len < 1) {
            printError(allocator, "INVALID_INPUT", "Usage: rmp sprint add <description>");
            std.process.exit(1);
        }
        const description = try std.mem.join(allocator, " ", subargs);
        defer allocator.free(description);
        const result = try sprint.addSprint(allocator, description);
        defer allocator.free(result);
        printStdout("{s}\n", .{result});
    } else if (std.mem.eql(u8, subcmd, "open") or std.mem.eql(u8, subcmd, "start")) {
        if (subargs.len < 1) {
            printError(allocator, "INVALID_INPUT", "Usage: rmp sprint open <id>");
            std.process.exit(1);
        }
        const id = std.fmt.parseInt(i64, subargs[0], 10) catch {
            printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid sprint ID: {s}", .{subargs[0]}));
            std.process.exit(1);
        };
        const result = try sprint.openSprint(allocator, id);
        defer allocator.free(result);
        printStdout("{s}\n", .{result});
    } else if (std.mem.eql(u8, subcmd, "close")) {
        if (subargs.len < 1) {
            printError(allocator, "INVALID_INPUT", "Usage: rmp sprint close <id>");
            std.process.exit(1);
        }
        const id = std.fmt.parseInt(i64, subargs[0], 10) catch {
            printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid sprint ID: {s}", .{subargs[0]}));
            std.process.exit(1);
        };
        const result = try sprint.closeSprint(allocator, id);
        defer allocator.free(result);
        printStdout("{s}\n", .{result});
    } else if (std.mem.eql(u8, subcmd, "reopen")) {
        if (subargs.len < 1) {
            printError(allocator, "INVALID_INPUT", "Usage: rmp sprint reopen <id>");
            std.process.exit(1);
        }
        const id = std.fmt.parseInt(i64, subargs[0], 10) catch {
            printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid sprint ID: {s}", .{subargs[0]}));
            std.process.exit(1);
        };
        const result = try sprint.reopenSprint(allocator, id);
        defer allocator.free(result);
        printStdout("{s}\n", .{result});
    } else if (std.mem.eql(u8, subcmd, "stats")) {
        if (subargs.len < 1) {
            printError(allocator, "INVALID_INPUT", "Usage: rmp sprint stats <id>");
            std.process.exit(1);
        }
        const id = std.fmt.parseInt(i64, subargs[0], 10) catch {
            printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid sprint ID: {s}", .{subargs[0]}));
            std.process.exit(1);
        };
        const result = try sprint.getSprintStats(allocator, id);
        defer allocator.free(result);
        printStdout("{s}\n", .{result});
    } else if (std.mem.eql(u8, subcmd, "update") or std.mem.eql(u8, subcmd, "upd")) {
        if (subargs.len < 2) {
            printError(allocator, "INVALID_INPUT", "Usage: rmp sprint update <id> <description>");
            std.process.exit(1);
        }
        const id = std.fmt.parseInt(i64, subargs[0], 10) catch {
            printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid sprint ID: {s}", .{subargs[0]}));
            std.process.exit(1);
        };
        const description = try std.mem.join(allocator, " ", subargs[1..]);
        defer allocator.free(description);
        const result = try sprint.updateSprint(allocator, id, description);
        defer allocator.free(result);
        printStdout("{s}\n", .{result});
    } else if (std.mem.eql(u8, subcmd, "add-task") or std.mem.eql(u8, subcmd, "add-tasks") or std.mem.eql(u8, subcmd, "add")) {
        if (subargs.len < 2) {
            printError(allocator, "INVALID_INPUT", "Usage: rmp sprint add-task <sprint_id> <task_ids>");
            std.process.exit(1);
        }
        const sprint_id = std.fmt.parseInt(i64, subargs[0], 10) catch {
            printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid sprint ID: {s}", .{subargs[0]}));
            std.process.exit(1);
        };
        const task_ids = parseIds(allocator, subargs[1]) catch |err| {
            printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid task IDs: {s} (error: {any})", .{ subargs[1], err }));
            std.process.exit(1);
        };
        defer allocator.free(task_ids);

        var results_list: std.ArrayListUnmanaged([]const u8) = .empty;
        defer {
            for (results_list.items) |r| allocator.free(r);
            results_list.deinit(allocator);
        }

        for (task_ids) |task_id| {
            const res = sprint.addTaskToSprint(allocator, sprint_id, task_id) catch |err| {
                const err_json = try json.errorResponse(allocator, "ADD_TASK_FAILED", try std.fmt.allocPrint(allocator, "Failed to add task {d} to sprint {d} (error: {any})", .{ task_id, sprint_id, err }));
                try results_list.append(allocator, err_json);
                continue;
            };
            try results_list.append(allocator, res);
        }

        const final_json = try buildBulkResponse(allocator, results_list.items);
        defer allocator.free(final_json);
        printStdout("{s}\n", .{final_json});
    } else if (std.mem.eql(u8, subcmd, "remove-task") or std.mem.eql(u8, subcmd, "remove-tasks") or std.mem.eql(u8, subcmd, "rm-tasks")) {
        if (subargs.len < 1) {
            printError(allocator, "INVALID_INPUT", "Usage: rmp sprint remove-tasks <sprint_id> <task_ids>");
            std.process.exit(1);
        }

        // Spec says: rmp sprint rm-tasks <sprint_id> <task_ids>
        // But removeTaskFromSprint only needs task_id.
        // We'll skip the first arg if 2 are provided to match the spec.
        const ids_arg = if (subargs.len >= 2) subargs[1] else subargs[0];

        const task_ids = parseIds(allocator, ids_arg) catch |err| {
            printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid task IDs: {s} (error: {any})", .{ ids_arg, err }));
            std.process.exit(1);
        };
        defer allocator.free(task_ids);

        var results_list: std.ArrayListUnmanaged([]const u8) = .empty;
        defer {
            for (results_list.items) |r| allocator.free(r);
            results_list.deinit(allocator);
        }

        for (task_ids) |task_id| {
            const res = sprint.removeTaskFromSprint(allocator, task_id) catch |err| {
                const err_json = try json.errorResponse(allocator, "REMOVE_TASK_FAILED", try std.fmt.allocPrint(allocator, "Failed to remove task {d} from sprint (error: {any})", .{ task_id, err }));
                try results_list.append(allocator, err_json);
                continue;
            };
            try results_list.append(allocator, res);
        }

        const final_json = try buildBulkResponse(allocator, results_list.items);
        defer allocator.free(final_json);
        printStdout("{s}\n", .{final_json});
    } else if (std.mem.eql(u8, subcmd, "move-tasks") or std.mem.eql(u8, subcmd, "mv-tasks")) {
        if (subargs.len < 3) {
            printError(allocator, "INVALID_INPUT", "Usage: rmp sprint move-tasks <from_sprint_id> <to_sprint_id> <task_ids>");
            std.process.exit(1);
        }

        // Spec: mv-tasks <from-sprint> <to-sprint> <task-ids...>
        const new_sprint_id = std.fmt.parseInt(i64, subargs[1], 10) catch {
            printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid to_sprint_id: {s}", .{subargs[1]}));
            std.process.exit(1);
        };

        const task_ids = parseIds(allocator, subargs[2]) catch |err| {
            printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid task IDs: {s} (error: {any})", .{ subargs[2], err }));
            std.process.exit(1);
        };
        defer allocator.free(task_ids);

        var results_list: std.ArrayListUnmanaged([]const u8) = .empty;
        defer {
            for (results_list.items) |r| allocator.free(r);
            results_list.deinit(allocator);
        }

        for (task_ids) |task_id| {
            const res = sprint.moveTaskBetweenSprints(allocator, task_id, new_sprint_id) catch |err| {
                const err_json = try json.errorResponse(allocator, "MOVE_TASK_FAILED", try std.fmt.allocPrint(allocator, "Failed to move task {d} to sprint {d} (error: {any})", .{ task_id, new_sprint_id, err }));
                try results_list.append(allocator, err_json);
                continue;
            };
            try results_list.append(allocator, res);
        }

        const final_json = try buildBulkResponse(allocator, results_list.items);
        defer allocator.free(final_json);
        printStdout("{s}\n", .{final_json});
    } else if (std.mem.eql(u8, subcmd, "remove") or std.mem.eql(u8, subcmd, "rm")) {
        if (subargs.len < 1) {
            printError(allocator, "INVALID_INPUT", "Usage: rmp sprint remove <ids>");
            std.process.exit(1);
        }
        const ids = parseIds(allocator, subargs[0]) catch |err| {
            printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid sprint IDs: {s} (error: {any})", .{ subargs[0], err }));
            std.process.exit(1);
        };
        defer allocator.free(ids);

        var results_list: std.ArrayListUnmanaged([]const u8) = .empty;
        defer {
            for (results_list.items) |r| allocator.free(r);
            results_list.deinit(allocator);
        }

        for (ids) |id| {
            const res = sprint.deleteSprint(allocator, id) catch |err| {
                const err_json = try json.errorResponse(allocator, "DELETE_FAILED", try std.fmt.allocPrint(allocator, "Failed to delete sprint {d} (error: {any})", .{ id, err }));
                try results_list.append(allocator, err_json);
                continue;
            };
            try results_list.append(allocator, res);
        }

        const final_json = try buildBulkResponse(allocator, results_list.items);
        defer allocator.free(final_json);
        printStdout("{s}\n", .{final_json});
    } else {
        printError(allocator, "UNKNOWN_SUBCOMMAND", try std.fmt.allocPrint(allocator, "Unknown sprint subcommand: {s}", .{subcmd}));
        std.process.exit(1);
    }
}

// ============== AUDIT COMMANDS ==============

fn handleAuditCommand(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len > 0 and (std.mem.eql(u8, args[0], "-h") or std.mem.eql(u8, args[0], "--help"))) {
        printCommandHelp(allocator, "audit");
        return;
    }

    if (args.len == 0) {
        printError(allocator, "INVALID_INPUT", "Usage: rmp audit <subcommand> [options]\nSubcommands: list, history, stats");
        std.process.exit(1);
    }

    const subcmd = args[0];
    const subargs = args[1..];

    if (std.mem.eql(u8, subcmd, "list") or std.mem.eql(u8, subcmd, "ls")) {
        // Parse flags for list command
        var options = audit.AuditListOptions{};

        var i: usize = 0;
        while (i < subargs.len) : (i += 1) {
            const arg = subargs[i];
            if (std.mem.eql(u8, arg, "-r") or std.mem.eql(u8, arg, "--roadmap")) {
                // Already handled by global flag
                i += 1;
            } else if (std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--operation")) {
                i += 1;
                if (i < subargs.len) options.operation = subargs[i];
            } else if (std.mem.eql(u8, arg, "-e") or std.mem.eql(u8, arg, "--entity-type")) {
                i += 1;
                if (i < subargs.len) options.entity_type = subargs[i];
            } else if (std.mem.eql(u8, arg, "--entity-id")) {
                i += 1;
                if (i < subargs.len) {
                    options.entity_id = std.fmt.parseInt(i64, subargs[i], 10) catch {
                        printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid entity ID: {s}", .{subargs[i]}));
                        std.process.exit(1);
                    };
                }
            } else if (std.mem.eql(u8, arg, "--since")) {
                i += 1;
                if (i < subargs.len) options.since = subargs[i];
            } else if (std.mem.eql(u8, arg, "--until")) {
                i += 1;
                if (i < subargs.len) options.until = subargs[i];
            } else if (std.mem.eql(u8, arg, "-l") or std.mem.eql(u8, arg, "--limit")) {
                i += 1;
                if (i < subargs.len) {
                    options.limit = std.fmt.parseInt(i32, subargs[i], 10) catch {
                        printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid limit: {s}", .{subargs[i]}));
                        std.process.exit(1);
                    };
                    if (options.limit < 1 or options.limit > 1000) {
                        printError(allocator, "INVALID_INPUT", "Limit must be between 1 and 1000");
                        std.process.exit(1);
                    }
                }
            } else if (std.mem.eql(u8, arg, "--offset")) {
                i += 1;
                if (i < subargs.len) {
                    options.offset = std.fmt.parseInt(i32, subargs[i], 10) catch {
                        printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid offset: {s}", .{subargs[i]}));
                        std.process.exit(1);
                    };
                    if (options.offset < 0) {
                        printError(allocator, "INVALID_INPUT", "Offset must be non-negative");
                        std.process.exit(1);
                    }
                }
            }
        }

        const result = audit.listAuditEntries(allocator, options) catch |err| {
            printError(allocator, "AUDIT_ERROR", try std.fmt.allocPrint(allocator, "Failed to list audit entries: {any}", .{err}));
            std.process.exit(1);
        };
        defer allocator.free(result);
        printStdout("{s}\n", .{result});
    } else if (std.mem.eql(u8, subcmd, "history") or std.mem.eql(u8, subcmd, "hist")) {
        // Parse flags for history command
        var entity_type: ?[]const u8 = null;
        var entity_id: ?i64 = null;

        var i: usize = 0;
        while (i < subargs.len) : (i += 1) {
            const arg = subargs[i];
            if (std.mem.eql(u8, arg, "-r") or std.mem.eql(u8, arg, "--roadmap")) {
                // Already handled by global flag
                i += 1;
            } else if (std.mem.eql(u8, arg, "-e") or std.mem.eql(u8, arg, "--entity-type")) {
                i += 1;
                if (i < subargs.len) entity_type = subargs[i];
            }
        }

        // Entity ID should be the last positional argument
        if (subargs.len > 0) {
            // Find the last non-flag argument as entity_id
            var last_arg: ?[]const u8 = null;
            var idx: usize = subargs.len;
            while (idx > 0) : (idx -= 1) {
                const a = subargs[idx - 1];
                if (!std.mem.startsWith(u8, a, "-") and
                    !std.mem.eql(u8, a, "TASK") and
                    !std.mem.eql(u8, a, "SPRINT")) {
                    last_arg = a;
                    break;
                }
            }
            if (last_arg) |id_str| {
                entity_id = std.fmt.parseInt(i64, id_str, 10) catch {
                    printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid entity ID: {s}", .{id_str}));
                    std.process.exit(1);
                };
            }
        }

        if (entity_type == null) {
            printError(allocator, "INVALID_INPUT", "Entity type is required. Use -e or --entity-type (TASK or SPRINT)");
            std.process.exit(1);
        }

        if (entity_id == null) {
            printError(allocator, "INVALID_INPUT", "Entity ID is required");
            std.process.exit(1);
        }

        const result = audit.getEntityHistory(allocator, entity_type.?, entity_id.?) catch |err| {
            printError(allocator, "AUDIT_ERROR", try std.fmt.allocPrint(allocator, "Failed to get entity history: {any}", .{err}));
            std.process.exit(1);
        };
        defer allocator.free(result);
        printStdout("{s}\n", .{result});
    } else if (std.mem.eql(u8, subcmd, "stats")) {
        // Parse flags for stats command
        var since_filter: ?[]const u8 = null;
        var until_filter: ?[]const u8 = null;

        var i: usize = 0;
        while (i < subargs.len) : (i += 1) {
            const arg = subargs[i];
            if (std.mem.eql(u8, arg, "-r") or std.mem.eql(u8, arg, "--roadmap")) {
                // Already handled by global flag
                i += 1;
            } else if (std.mem.eql(u8, arg, "--since")) {
                i += 1;
                if (i < subargs.len) since_filter = subargs[i];
            } else if (std.mem.eql(u8, arg, "--until")) {
                i += 1;
                if (i < subargs.len) until_filter = subargs[i];
            }
        }

        const result = audit.getAuditStats(allocator, since_filter, until_filter) catch |err| {
            printError(allocator, "AUDIT_ERROR", try std.fmt.allocPrint(allocator, "Failed to get audit stats: {any}", .{err}));
            std.process.exit(1);
        };
        defer allocator.free(result);
        printStdout("{s}\n", .{result});
    } else {
        printError(allocator, "UNKNOWN_SUBCOMMAND", try std.fmt.allocPrint(allocator, "Unknown audit subcommand: {s}", .{subcmd}));
        std.process.exit(1);
    }
}

// ============== UTILITY FUNCTIONS ==============

fn buildBulkResponse(allocator: std.mem.Allocator, results: []const []const u8) ![]const u8 {
    if (results.len == 0) return json.success(allocator, "[]");
    if (results.len == 1) return try allocator.dupe(u8, results[0]);

    var combined: std.ArrayListUnmanaged(u8) = .empty;
    defer combined.deinit(allocator);

    try combined.appendSlice(allocator, "{\"success\":true,\"results\":[");
    for (results, 0..) |res, i| {
        if (i > 0) try combined.append(allocator, ',');
        try combined.appendSlice(allocator, res);
    }
    try combined.appendSlice(allocator, "]}");

    return combined.toOwnedSlice(allocator);
}

fn parseIds(allocator: std.mem.Allocator, input: []const u8) ![]i64 {
    var list: std.ArrayListUnmanaged(i64) = .empty;
    errdefer list.deinit(allocator);

    var it = std.mem.splitScalar(u8, input, ',');
    while (it.next()) |part| {
        const trimmed = std.mem.trim(u8, part, " ");
        if (trimmed.len == 0) continue;
        const id = try std.fmt.parseInt(i64, trimmed, 10);
        try list.append(allocator, id);
    }
    return list.toOwnedSlice(allocator);
}

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

/// Get priority_min filter from args (-p or --priority)
fn getPriorityMinFilter(args: []const []const u8) ?i32 {
    for (args, 0..) |arg, i| {
        if ((std.mem.eql(u8, arg, "--priority") or std.mem.eql(u8, arg, "-p")) and i + 1 < args.len) {
            return std.fmt.parseInt(i32, args[i + 1], 10) catch null;
        }
    }
    return null;
}

/// Get severity_min filter from args (--severity)
fn getSeverityMinFilter(args: []const []const u8) ?i32 {
    for (args, 0..) |arg, i| {
        if (std.mem.eql(u8, arg, "--severity") and i + 1 < args.len) {
            return std.fmt.parseInt(i32, args[i + 1], 10) catch null;
        }
    }
    return null;
}

/// Get limit filter from args (-l or --limit)
fn getLimitFilter(args: []const []const u8) ?i32 {
    for (args, 0..) |arg, i| {
        if ((std.mem.eql(u8, arg, "--limit") or std.mem.eql(u8, arg, "-l")) and i + 1 < args.len) {
            return std.fmt.parseInt(i32, args[i + 1], 10) catch null;
        }
    }
    return null;
}

// ============== TESTS ==============

test "parseIds validates correctly" {
    const allocator = std.testing.allocator;

    // Valid inputs
    {
        const ids = try parseIds(allocator, "1,2,3");
        defer allocator.free(ids);
        try std.testing.expectEqual(@as(usize, 3), ids.len);
        try std.testing.expectEqual(@as(i64, 1), ids[0]);
        try std.testing.expectEqual(@as(i64, 2), ids[1]);
        try std.testing.expectEqual(@as(i64, 3), ids[2]);
    }

    {
        const ids = try parseIds(allocator, " 10 , 20 ");
        defer allocator.free(ids);
        try std.testing.expectEqual(@as(usize, 2), ids.len);
        try std.testing.expectEqual(@as(i64, 10), ids[0]);
        try std.testing.expectEqual(@as(i64, 20), ids[1]);
    }

    {
        const ids = try parseIds(allocator, "5");
        defer allocator.free(ids);
        try std.testing.expectEqual(@as(usize, 1), ids.len);
        try std.testing.expectEqual(@as(i64, 5), ids[0]);
    }

    // Empty parts
    {
        const ids = try parseIds(allocator, "1,,2");
        defer allocator.free(ids);
        try std.testing.expectEqual(@as(usize, 2), ids.len);
        try std.testing.expectEqual(@as(i64, 1), ids[0]);
        try std.testing.expectEqual(@as(i64, 2), ids[1]);
    }

    // Invalid inputs
    try std.testing.expectError(error.InvalidCharacter, parseIds(allocator, "1,a,3"));
    try std.testing.expectError(error.InvalidCharacter, parseIds(allocator, "abc"));
}

test "getStatusFilter extracts status" {
    const TaskStatus = @import("models/task.zig").TaskStatus;

    {
        const args = [_][]const u8{ "ls", "--status", "DOING" };
        const status = getStatusFilter(&args);
        try std.testing.expectEqual(TaskStatus.DOING, status.?);
    }

    {
        const args = [_][]const u8{ "ls", "-s", "COMPLETED" };
        const status = getStatusFilter(&args);
        try std.testing.expectEqual(TaskStatus.COMPLETED, status.?);
    }

    {
        const args = [_][]const u8{ "ls" };
        const status = getStatusFilter(&args);
        try std.testing.expect(status == null);
    }

    {
        const args = [_][]const u8{ "ls", "-s", "INVALID" };
        const status = getStatusFilter(&args);
        try std.testing.expect(status == null);
    }
}

fn printCommandHelp(allocator: std.mem.Allocator, command: []const u8) void {
    if (std.mem.eql(u8, command, "roadmap")) {
        const roadmap_help =
            \\{
            \\  "success": true,
            \\  "data": {
            \\    "command": "roadmap",
            \\    "description": "Roadmap management commands",
            \\    "subcommands": [
            \\      { "name": "list", "alias": "ls", "description": "List all roadmaps" },
            \\      { "name": "create", "alias": "new", "description": "Create a new roadmap", "options": [{"long": "--force", "description": "Overwrite existing"}] },
            \\      { "name": "remove", "alias": "rm", "description": "Delete a roadmap" },
            \\      { "name": "use", "description": "Set default roadmap" }
            \\    ]
            \\  }
            \\}
        ;
        printStdout("{s}\n", .{roadmap_help});
    } else if (std.mem.eql(u8, command, "task")) {
        const task_help =
            \\{
            \\  "success": true,
            \\  "data": {
            \\    "command": "task",
            \\    "description": "Task management commands",
            \\    "subcommands": [
            \\      { "name": "list", "alias": "ls", "description": "List tasks", "options": [{"short": "-s", "long": "--status", "description": "Filter by status"}] },
            \\      { "name": "get", "description": "Get task details", "args": "<ids>" },
            \\      { "name": "add", "alias": "new", "description": "Create task", "options": [
            \\        {"short": "-d", "long": "--description", "required": true},
            \\        {"short": "-a", "long": "--action", "required": true},
            \\        {"short": "-e", "long": "--expected", "required": true},
            \\        {"short": "-p", "long": "--priority", "description": "0-9"},
            \\        {"short": "-s", "long": "--severity", "description": "0-9"}
            \\      ]},
            \\      { "name": "status", "alias": "stat", "description": "Change status", "args": "<ids> <status>" },
            \\      { "name": "prio", "description": "Change priority", "args": "<ids> <0-9>" },
            \\      { "name": "sev", "description": "Change severity", "args": "<ids> <0-9>" },
            \\      { "name": "edit", "description": "Update task fields" },
            \\      { "name": "delete", "alias": "rm", "description": "Remove tasks", "args": "<ids>" }
            \\    ]
            \\  }
            \\}
        ;
        printStdout("{s}\n", .{task_help});
    } else if (std.mem.eql(u8, command, "sprint")) {
        const sprint_help =
            \\{
            \\  "success": true,
            \\  "data": {
            \\    "command": "sprint",
            \\    "description": "Sprint management commands",
            \\    "subcommands": [
            \\      { "name": "list", "alias": "ls", "description": "List sprints" },
            \\      { "name": "add", "alias": "new", "description": "Create sprint", "args": "<description>" },
            \\      { "name": "open", "alias": "start", "description": "Start a sprint", "args": "<id>" },
            \\      { "name": "close", "description": "Close a sprint", "args": "<id>" },
            \\      { "name": "add-task", "description": "Add task to sprint", "args": "<sprint_id> <task_ids>" },
            \\      { "name": "remove-task", "alias": "rm-tasks", "description": "Remove task from sprint", "args": "<task_ids>" },
            \\      { "name": "move-tasks", "alias": "mv-tasks", "description": "Move tasks between sprints", "args": "<from_id> <to_id> <task_ids>" },
            \\      { "name": "stats", "description": "Get sprint statistics", "args": "<id>" }
            \\    ]
            \\  }
            \\}
        ;
        printStdout("{s}\n", .{sprint_help});
    } else {
        printUsage(allocator);
    }
}

fn printUsage(allocator: std.mem.Allocator) void {
    const help_json =
        \\{
        \\  "success": true,
        \\  "data": {
        \\    "name": "rmp",
        \\    "version": "1.0.0",
        \\    "description": "Local Roadmap Manager CLI for agentic workflows",
        \\    "usage": "rmp [command] [subcommand] [arguments] [options]",
        \\    "commands": [
        \\      {
        \\        "name": "roadmap",
        \\        "alias": "road",
        \\        "subcommands": ["list (ls)", "create (new)", "remove (rm)", "use"]
        \\      },
        \\      {
        \\        "name": "task",
        \\        "subcommands": ["list (ls)", "get", "add (new)", "status (stat)", "prio", "sev", "edit", "delete (rm)"]
        \\      },
        \\      {
        \\        "name": "sprint",
        \\        "subcommands": ["list (ls)", "get", "tasks", "add (new)", "open (start)", "close", "reopen", "stats", "update (upd)", "add-task", "remove-task (rm-tasks)", "move-tasks (mv-tasks)", "remove (rm)"]
        \\      }
        \\    ],
        \\    "global_flags": ["-r, --roadmap <name>", "-h, --help", "-v, --version"],
        \\    "notes": "All responses are JSON. All dates are ISO 8601 UTC. Most commands support bulk IDs (e.g. 1,2,3)."
        \\  }
        \\}
    ;
    _ = allocator;
    printStdout("{s}\n", .{help_json});
}
