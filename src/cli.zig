const std = @import("std");
const json = @import("utils/json.zig");
const time = @import("utils/time.zig");
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

fn printStderr(comptime fmt: []const u8, args: anytype) void {
    const stderr = std.fs.File.stderr().deprecatedWriter();
    stderr.print(fmt, args) catch {};
}

const ExitCode = struct {
    pub const SUCCESS = 0;
    pub const FAILURE = 1;
    pub const MISUSE = 2;
    pub const NO_ROADMAP = 3;
    pub const NOT_FOUND = 4;
    pub const EXISTS = 5;
    pub const INVALID_DATA = 6;
    pub const CMD_NOT_FOUND = 127;
    pub const SIGINT = 130;
};

fn getExitCodeForError(error_code: []const u8) u8 {
    if (std.mem.eql(u8, error_code, "INVALID_INPUT")) return ExitCode.MISUSE;
    if (std.mem.eql(u8, error_code, "INVALID_DATE")) return ExitCode.INVALID_DATA;
    if (std.mem.eql(u8, error_code, "INVALID_DATE_RANGE")) return ExitCode.INVALID_DATA;
    if (std.mem.eql(u8, error_code, "INVALID_PRIORITY")) return ExitCode.INVALID_DATA;
    if (std.mem.eql(u8, error_code, "ROADMAP_NOT_FOUND")) return ExitCode.NOT_FOUND;
    if (std.mem.eql(u8, error_code, "ROADMAP_EXISTS")) return ExitCode.EXISTS;
    if (std.mem.eql(u8, error_code, "TASK_NOT_FOUND")) return ExitCode.NOT_FOUND;
    if (std.mem.eql(u8, error_code, "SPRINT_NOT_FOUND")) return ExitCode.NOT_FOUND;
    if (std.mem.eql(u8, error_code, "NO_ROADMAP")) return ExitCode.NO_ROADMAP;
    if (std.mem.eql(u8, error_code, "DB_ERROR")) return ExitCode.FAILURE;
    if (std.mem.eql(u8, error_code, "SYSTEM_ERROR")) return ExitCode.FAILURE;
    if (std.mem.eql(u8, error_code, "UNKNOWN_SUBCOMMAND")) return ExitCode.MISUSE;
    if (std.mem.eql(u8, error_code, "UNKNOWN_COMMAND")) return ExitCode.CMD_NOT_FOUND;
    if (std.mem.eql(u8, error_code, "NO_SPRINT")) return ExitCode.NOT_FOUND;
    return ExitCode.FAILURE;
}

fn printError(allocator: std.mem.Allocator, code: []const u8, message: []const u8) u8 {
    _ = allocator;
    printStderr("Error: {s}\n", .{message});
    return getExitCodeForError(code);
}

/// Prints error and then prints help for the command to stderr
fn printErrorWithHelp(allocator: std.mem.Allocator, code: []const u8, message: []const u8, command: []const u8) u8 {
    const exit_code = printError(allocator, code, message);
    printStderr("\n", .{});
    printCommandHelpStderr(allocator, command);
    return exit_code;
}

/// Prints error and then prints help for the subcommand to stderr
fn printErrorWithSubcommandHelp(code: []const u8, message: []const u8, command: []const u8, subcommand: []const u8) u8 {
    const exit_code = printError(std.heap.page_allocator, code, message);
    printStderr("\n", .{});
    printSubcommandHelp(command, subcommand);
    return exit_code;
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
        if (std.mem.indexOf(u8, res, "\"code\":") != null) {
            printStdout("{s}\n", .{res});
            std.process.exit(ExitCode.FAILURE);
        }
    }

    // Route to appropriate command handler
    if (std.mem.eql(u8, cmd, "roadmap") or std.mem.eql(u8, cmd, "road")) {
        try handleRoadmapCommand(allocator, subargs);
    } else if (std.mem.eql(u8, cmd, "task")) {
        try handleTaskCommand(allocator, subargs);
    } else if (std.mem.eql(u8, cmd, "sprint")) {
        try handleSprintCommand(allocator, subargs);
    } else if (std.mem.eql(u8, cmd, "audit") or std.mem.eql(u8, cmd, "aud")) {
        try handleAuditCommand(allocator, subargs);
    } else {
        const exit_code = printError(allocator, "UNKNOWN_COMMAND", try std.fmt.allocPrint(allocator, "Unknown command: {s}", .{cmd}));
        std.process.exit(exit_code);
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
        if (subargs.len > 0 and (std.mem.eql(u8, subargs[0], "-h") or std.mem.eql(u8, subargs[0], "--help"))) {
            printSubcommandHelp("roadmap", "list");
            return;
        }
        const result = try roadmap.listRoadmaps(allocator);
        defer allocator.free(result);
        if (std.mem.indexOf(u8, result, "\"code\":") != null) {
            printStdout("{s}\n", .{result});
            std.process.exit(ExitCode.FAILURE);
        }
        printStdout("{s}\n", .{result});
    } else if (std.mem.eql(u8, subcmd, "create") or std.mem.eql(u8, subcmd, "new")) {
        if (subargs.len > 0 and (std.mem.eql(u8, subargs[0], "-h") or std.mem.eql(u8, subargs[0], "--help"))) {
            printSubcommandHelp("roadmap", "create");
            return;
        }
        if (subargs.len < 1 or (subargs.len == 1 and std.mem.startsWith(u8, subargs[0], "-"))) {
            const exit_code = printErrorWithSubcommandHelp("INVALID_INPUT", "Missing required parameter: roadmap name", "roadmap", "create");
            std.process.exit(exit_code);
        }
        const name = subargs[0];
        const force = hasFlag(subargs, "--force");
        const result = try roadmap.createRoadmap(allocator, name, force);
        defer allocator.free(result);
        if (std.mem.indexOf(u8, result, "\"code\":") != null) {
            printStdout("{s}\n", .{result});
            std.process.exit(ExitCode.EXISTS);
        }
        printStdout("{s}\n", .{result});
    } else if (std.mem.eql(u8, subcmd, "remove") or std.mem.eql(u8, subcmd, "rm") or std.mem.eql(u8, subcmd, "delete")) {
        if (subargs.len > 0 and (std.mem.eql(u8, subargs[0], "-h") or std.mem.eql(u8, subargs[0], "--help"))) {
            printSubcommandHelp("roadmap", "remove");
            return;
        }
        if (subargs.len < 1) {
            const exit_code = printErrorWithSubcommandHelp("INVALID_INPUT", "Missing required parameter: roadmap name", "roadmap", "remove");
            std.process.exit(exit_code);
        }
        const name = subargs[0];
        const result = try roadmap.removeRoadmap(allocator, name);
        defer allocator.free(result);
        if (std.mem.indexOf(u8, result, "\"code\":") != null) {
            printStdout("{s}\n", .{result});
            std.process.exit(ExitCode.NOT_FOUND);
        }
        printStdout("{s}\n", .{result});
    } else if (std.mem.eql(u8, subcmd, "use")) {
        if (subargs.len > 0 and (std.mem.eql(u8, subargs[0], "-h") or std.mem.eql(u8, subargs[0], "--help"))) {
            printSubcommandHelp("roadmap", "use");
            return;
        }
        if (subargs.len < 1) {
            const exit_code = printErrorWithSubcommandHelp("INVALID_INPUT", "Missing required parameter: roadmap name", "roadmap", "use");
            std.process.exit(exit_code);
        }
        const name = subargs[0];
        const result = try roadmap.useRoadmap(allocator, name);
        defer allocator.free(result);
        if (std.mem.indexOf(u8, result, "\"code\":") != null) {
            printStdout("{s}\n", .{result});
            std.process.exit(ExitCode.NOT_FOUND);
        }
        printStdout("{s}\n", .{result});
    } else {
        const err_msg = try std.fmt.allocPrint(allocator, "Unknown roadmap subcommand: {s}", .{subcmd});
        defer allocator.free(err_msg);
        const exit_code = printErrorWithHelp(allocator, "UNKNOWN_SUBCOMMAND", err_msg, "roadmap");
        std.process.exit(exit_code);
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
        if (subargs.len > 0 and (std.mem.eql(u8, subargs[0], "-h") or std.mem.eql(u8, subargs[0], "--help"))) {
            printSubcommandHelp("task", "list");
            return;
        }
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
        if (std.mem.indexOf(u8, result, "\"code\":") != null) {
            printStdout("{s}\n", .{result});
            std.process.exit(ExitCode.FAILURE);
        }
        printStdout("{s}\n", .{result});
    } else if (std.mem.eql(u8, subcmd, "get")) {
        if (subargs.len > 0 and (std.mem.eql(u8, subargs[0], "-h") or std.mem.eql(u8, subargs[0], "--help"))) {
            printSubcommandHelp("task", "get");
            return;
        }
        if (subargs.len < 1) {
            const exit_code = printErrorWithHelp(allocator, "INVALID_INPUT", "Missing required parameter: task IDs", "task");
            std.process.exit(exit_code);
        }
        if (subargs.len > 1) {
            const exit_code = printError(allocator, "INVALID_INPUT", "Too many arguments for 'task get'. Only 1 comma-separated ID list is allowed.");
            std.process.exit(exit_code);
        }
        const ids = parseIds(allocator, subargs[0]) catch |err| {
            const err_msg = switch (err) {
                error.InvalidCharacter => try std.fmt.allocPrint(allocator, "Invalid character in task IDs: {s}", .{subargs[0]}),
                error.Overflow => try std.fmt.allocPrint(allocator, "Task ID too large: {s}", .{subargs[0]}),
                else => try std.fmt.allocPrint(allocator, "Invalid task IDs: {s} (error: {any})", .{ subargs[0], err }),
            };
            defer allocator.free(err_msg);
            const exit_code = printError(allocator, "INVALID_INPUT", err_msg);
            std.process.exit(exit_code);
        };
        defer allocator.free(ids);

        if (ids.len == 0) {
            const exit_code = printError(allocator, "INVALID_INPUT", "No task IDs provided");
            std.process.exit(exit_code);
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
        // Check if any result is an error
        var has_error = false;
        for (results_list.items) |res| {
            if (std.mem.indexOf(u8, res, "\"code\":") != null) {
                has_error = true;
                break;
            }
        }
        printStdout("{s}\n", .{final_json});
        if (has_error) {
            std.process.exit(ExitCode.NOT_FOUND);
        }
    } else if (std.mem.eql(u8, subcmd, "create") or std.mem.eql(u8, subcmd, "add") or std.mem.eql(u8, subcmd, "new")) {
        if (subargs.len > 0 and (std.mem.eql(u8, subargs[0], "-h") or std.mem.eql(u8, subargs[0], "--help"))) {
            printSubcommandHelp("task", "create");
            return;
        }
        try handleTaskAdd(allocator, subargs);
    } else if (std.mem.eql(u8, subcmd, "status") or std.mem.eql(u8, subcmd, "stat")) {
        if (subargs.len > 0 and (std.mem.eql(u8, subargs[0], "-h") or std.mem.eql(u8, subargs[0], "--help"))) {
            printSubcommandHelp("task", "set-status");
            return;
        }
        if (subargs.len < 2) {
            const exit_code = printErrorWithHelp(allocator, "INVALID_INPUT", "Missing required parameters: task IDs and/or status", "task");
            std.process.exit(exit_code);
        }
        if (subargs.len > 2) {
            const exit_code = printError(allocator, "INVALID_INPUT", "Too many arguments for 'task status'. Usage: rmp task status <ids> <status>");
            std.process.exit(exit_code);
        }
        const ids = parseIds(allocator, subargs[0]) catch |err| {
            const exit_code = printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid task IDs: {s} (error: {any})", .{ subargs[0], err }));
            std.process.exit(exit_code);
        };
        defer allocator.free(ids);

        const status = @import("models/task.zig").TaskStatus.fromString(subargs[1]) catch {
            const exit_code = printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid status: {s}", .{subargs[1]}));
            std.process.exit(exit_code);
        };

        _ = task.changeTaskStatus(allocator, ids, status) catch |err| {
            const err_json = json.errorResponse(allocator, "UPDATE_FAILED", try std.fmt.allocPrint(allocator, "Failed to update tasks (error: {any})", .{err})) catch |e| {
                printStderr("Critical error: {any}\n", .{e});
                std.process.exit(ExitCode.FAILURE);
            };
            defer allocator.free(err_json);
            printStderr("{s}\n", .{err_json});
            std.process.exit(ExitCode.NOT_FOUND);
        };
        // Success: no output
    } else if (std.mem.eql(u8, subcmd, "prio") or std.mem.eql(u8, subcmd, "priority")) {
        if (subargs.len > 0 and (std.mem.eql(u8, subargs[0], "-h") or std.mem.eql(u8, subargs[0], "--help"))) {
            printSubcommandHelp("task", "set-priority");
            return;
        }
        if (subargs.len < 2) {
            const exit_code = printErrorWithHelp(allocator, "INVALID_INPUT", "Missing required parameters: task IDs and/or priority value", "task");
            std.process.exit(exit_code);
        }
        if (subargs.len > 2) {
            const exit_code = printError(allocator, "INVALID_INPUT", "Too many arguments for 'task prio'. Usage: rmp task prio <ids> <priority>");
            std.process.exit(exit_code);
        }
        const ids = parseIds(allocator, subargs[0]) catch |err| {
            const exit_code = printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid task IDs: {s} (error: {any})", .{ subargs[0], err }));
            std.process.exit(exit_code);
        };
        defer allocator.free(ids);

        const priority = std.fmt.parseInt(i32, subargs[1], 10) catch {
            const exit_code = printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid priority: {s}", .{subargs[1]}));
            std.process.exit(exit_code);
        };

        if (priority < 0 or priority > 9) {
            const err_json = json.errorResponse(allocator, "INVALID_PRIORITY", "Priority must be between 0 and 9") catch {
                printStderr("Priority must be between 0 and 9\n", .{});
                std.process.exit(ExitCode.INVALID_DATA);
            };
            defer allocator.free(err_json);
            printStderr("{s}\n", .{err_json});
            std.process.exit(ExitCode.INVALID_DATA);
        }

        _ = task.setPriority(allocator, ids, priority) catch |err| {
            const err_json = json.errorResponse(allocator, "UPDATE_FAILED", try std.fmt.allocPrint(allocator, "Failed to set priority for tasks (error: {any})", .{err})) catch |e| {
                printStderr("Critical error: {any}\n", .{e});
                std.process.exit(ExitCode.FAILURE);
            };
            defer allocator.free(err_json);
            printStderr("{s}\n", .{err_json});
            std.process.exit(ExitCode.NOT_FOUND);
        };
        // Success: no output
    } else if (std.mem.eql(u8, subcmd, "sev") or std.mem.eql(u8, subcmd, "severity")) {
        if (subargs.len > 0 and (std.mem.eql(u8, subargs[0], "-h") or std.mem.eql(u8, subargs[0], "--help"))) {
            printSubcommandHelp("task", "set-severity");
            return;
        }
        if (subargs.len < 2) {
            const exit_code = printErrorWithHelp(allocator, "INVALID_INPUT", "Missing required parameters: task IDs and/or severity value", "task");
            std.process.exit(exit_code);
        }
        if (subargs.len > 2) {
            const exit_code = printError(allocator, "INVALID_INPUT", "Too many arguments for 'task sev'. Usage: rmp task sev <ids> <severity>");
            std.process.exit(exit_code);
        }
        const ids = parseIds(allocator, subargs[0]) catch |err| {
            const exit_code = printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid task IDs: {s} (error: {any})", .{ subargs[0], err }));
            std.process.exit(exit_code);
        };
        defer allocator.free(ids);

        const severity = std.fmt.parseInt(i32, subargs[1], 10) catch {
            const exit_code = printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid severity: {s}", .{subargs[1]}));
            std.process.exit(exit_code);
        };

        if (severity < 0 or severity > 9) {
            const err_json = json.errorResponse(allocator, "INVALID_SEVERITY", "Severity must be between 0 and 9") catch {
                printStderr("Severity must be between 0 and 9\n", .{});
                std.process.exit(ExitCode.INVALID_DATA);
            };
            defer allocator.free(err_json);
            printStderr("{s}\n", .{err_json});
            std.process.exit(ExitCode.INVALID_DATA);
        }

        _ = task.setSeverity(allocator, ids, severity) catch |err| {
            const err_json = json.errorResponse(allocator, "UPDATE_FAILED", try std.fmt.allocPrint(allocator, "Failed to set severity for tasks (error: {any})", .{err})) catch |e| {
                printStderr("Critical error: {any}\n", .{e});
                std.process.exit(ExitCode.FAILURE);
            };
            defer allocator.free(err_json);
            printStderr("{s}\n", .{err_json});
            std.process.exit(ExitCode.NOT_FOUND);
        };
        // Success: no output
    } else if (std.mem.eql(u8, subcmd, "edit")) {
        if (subargs.len > 0 and (std.mem.eql(u8, subargs[0], "-h") or std.mem.eql(u8, subargs[0], "--help"))) {
            printSubcommandHelp("task", "edit");
            return;
        }
        try handleTaskEdit(allocator, subargs);
    } else if (std.mem.eql(u8, subcmd, "delete") or std.mem.eql(u8, subcmd, "rm")) {
        if (subargs.len > 0 and (std.mem.eql(u8, subargs[0], "-h") or std.mem.eql(u8, subargs[0], "--help"))) {
            printSubcommandHelp("task", "remove");
            return;
        }
        if (subargs.len < 1) {
            const exit_code = printErrorWithHelp(allocator, "INVALID_INPUT", "Missing required parameter: task IDs", "task");
            std.process.exit(exit_code);
        }
        const ids = parseIds(allocator, subargs[0]) catch |err| {
            const exit_code = printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid task IDs: {s} (error: {any})", .{ subargs[0], err }));
            std.process.exit(exit_code);
        };
        defer allocator.free(ids);

        _ = task.deleteTask(allocator, ids) catch |err| {
            const err_json = json.errorResponse(allocator, "DELETE_FAILED", try std.fmt.allocPrint(allocator, "Failed to delete tasks (error: {any})", .{err})) catch |e| {
                printStderr("Critical error: {any}\n", .{e});
                std.process.exit(ExitCode.FAILURE);
            };
            defer allocator.free(err_json);
            printStderr("{s}\n", .{err_json});
            std.process.exit(ExitCode.NOT_FOUND);
        };
        // Success: no output
    } else {
        printStdout("Unknown task subcommand: {s}\n", .{subcmd});
        printStdout("Available: list, get, add, status, prio, sev, edit, delete\n", .{});
        const exit_code = printError(allocator, "UNKNOWN_SUBCOMMAND", try std.fmt.allocPrint(allocator, "Unknown task subcommand: {s}", .{subcmd}));
        std.process.exit(exit_code);
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
                    const exit_code = printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid priority value: {s}. Must be 0-9.", .{args[i]}));
                    std.process.exit(exit_code);
                };
                if (priority < 0 or priority > 9) {
                    const err_json = json.errorResponse(allocator, "INVALID_PRIORITY", "Priority must be between 0 and 9") catch {
                        printStderr("Priority must be between 0 and 9\n", .{});
                        std.process.exit(ExitCode.INVALID_DATA);
                    };
                    defer allocator.free(err_json);
                    printStderr("{s}\n", .{err_json});
                    std.process.exit(ExitCode.INVALID_DATA);
                }
            } else {
                const exit_code = printError(allocator, "INVALID_INPUT", "Missing value for priority flag");
                std.process.exit(exit_code);
            }
        } else if (std.mem.eql(u8, arg, "-s") or std.mem.eql(u8, arg, "--severity")) {
            i += 1;
            if (i < args.len) {
                severity = std.fmt.parseInt(i32, args[i], 10) catch {
                    const exit_code = printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid severity value: {s}. Must be 0-9.", .{args[i]}));
                    std.process.exit(exit_code);
                };
                if (severity < 0 or severity > 9) {
                    const err_json = json.errorResponse(allocator, "INVALID_SEVERITY", "Severity must be between 0 and 9") catch {
                        printStderr("Severity must be between 0 and 9\n", .{});
                        std.process.exit(ExitCode.INVALID_DATA);
                    };
                    defer allocator.free(err_json);
                    printStderr("{s}\n", .{err_json});
                    std.process.exit(ExitCode.INVALID_DATA);
                }
            } else {
                const exit_code = printError(allocator, "INVALID_INPUT", "Missing value for severity flag");
                std.process.exit(exit_code);
            }
        } else if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--description")) {
            i += 1;
            if (i < args.len) {
                description = args[i];
            } else {
                const exit_code = printError(allocator, "INVALID_INPUT", "Missing value for description flag");
                std.process.exit(exit_code);
            }
        } else if (std.mem.eql(u8, arg, "-sp") or std.mem.eql(u8, arg, "--specialists")) {
            i += 1;
            if (i < args.len) {
                specialists = args[i];
            } else {
                const exit_code = printError(allocator, "INVALID_INPUT", "Missing value for specialists flag");
                std.process.exit(exit_code);
            }
        } else if (std.mem.eql(u8, arg, "-a") or std.mem.eql(u8, arg, "--action")) {
            i += 1;
            if (i < args.len) {
                action = args[i];
            } else {
                const exit_code = printError(allocator, "INVALID_INPUT", "Missing value for action flag");
                std.process.exit(exit_code);
            }
        } else if (std.mem.eql(u8, arg, "-e") or std.mem.eql(u8, arg, "--expected-result")) {
            i += 1;
            if (i < args.len) {
                expected_result = args[i];
            } else {
                const exit_code = printError(allocator, "INVALID_INPUT", "Missing value for expected-result flag");
                std.process.exit(exit_code);
            }
        }
    }

    if (description == null or action == null or expected_result == null) {
        const exit_code = printErrorWithSubcommandHelp("INVALID_INPUT", "Missing required options: --description, --action, --expected-result", "task", "create");
        std.process.exit(exit_code);
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
    if (std.mem.indexOf(u8, result, "\"code\":") != null) {
        printStdout("{s}\n", .{result});
        std.process.exit(ExitCode.FAILURE);
    }
    printStdout("{s}\n", .{result});
}

fn handleTaskEdit(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        const exit_code = printErrorWithHelp(allocator, "INVALID_INPUT", "Missing required parameter: task ID", "task");
        std.process.exit(exit_code);
    }

    const id = std.fmt.parseInt(i64, args[0], 10) catch {
        const exit_code = printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid task ID: {s}", .{args[0]}));
        std.process.exit(exit_code);
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
                    const exit_code = printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid priority value: {s}. Must be 0-9.", .{args[i]}));
                    std.process.exit(exit_code);
                };
            } else {
                const exit_code = printError(allocator, "INVALID_INPUT", "Missing value for priority flag");
                std.process.exit(exit_code);
            }
        } else if (std.mem.eql(u8, arg, "-s") or std.mem.eql(u8, arg, "--severity")) {
            i += 1;
            if (i < args.len) {
                updates.severity = std.fmt.parseInt(i32, args[i], 10) catch {
                    const exit_code = printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid severity value: {s}. Must be 0-9.", .{args[i]}));
                    std.process.exit(exit_code);
                };
            } else {
                const exit_code = printError(allocator, "INVALID_INPUT", "Missing value for severity flag");
                std.process.exit(exit_code);
            }
        } else if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--description")) {
            i += 1;
            if (i < args.len) {
                updates.description = args[i];
            } else {
                const exit_code = printError(allocator, "INVALID_INPUT", "Missing value for description flag");
                std.process.exit(exit_code);
            }
        } else if (std.mem.eql(u8, arg, "-sp") or std.mem.eql(u8, arg, "--specialists")) {
            i += 1;
            if (i < args.len) {
                updates.specialists = args[i];
            } else {
                const exit_code = printError(allocator, "INVALID_INPUT", "Missing value for specialists flag");
                std.process.exit(exit_code);
            }
        } else if (std.mem.eql(u8, arg, "-a") or std.mem.eql(u8, arg, "--action")) {
            i += 1;
            if (i < args.len) {
                updates.action = args[i];
            } else {
                const exit_code = printError(allocator, "INVALID_INPUT", "Missing value for action flag");
                std.process.exit(exit_code);
            }
        } else if (std.mem.eql(u8, arg, "-e") or std.mem.eql(u8, arg, "--expected-result")) {
            i += 1;
            if (i < args.len) {
                updates.expected_result = args[i];
            } else {
                const exit_code = printError(allocator, "INVALID_INPUT", "Missing value for expected-result flag");
                std.process.exit(exit_code);
            }
        }
    }

    if (updates.priority) |p| {
        if (p < 0 or p > 9) {
            const exit_code = printError(allocator, "INVALID_PRIORITY", "Priority must be between 0 and 9");
            std.process.exit(exit_code);
        }
    }

    if (updates.severity) |s| {
        if (s < 0 or s > 9) {
            const exit_code = printError(allocator, "INVALID_INPUT", "Severity must be between 0 and 9");
            std.process.exit(exit_code);
        }
    }

    const result = try task.editTask(allocator, id, updates);
    defer allocator.free(result);
    if (std.mem.indexOf(u8, result, "\"code\":") != null) {
        printStdout("{s}\n", .{result});
        std.process.exit(ExitCode.NOT_FOUND);
    }
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
        if (std.mem.indexOf(u8, result, "\"code\":") != null) {
            printStdout("{s}\n", .{result});
            std.process.exit(ExitCode.FAILURE);
        }
        printStdout("{s}\n", .{result});
        return;
    }

    const subcmd = args[0];
    const subargs = args[1..];

    if (std.mem.eql(u8, subcmd, "list") or std.mem.eql(u8, subcmd, "ls")) {
        if (subargs.len > 0 and (std.mem.eql(u8, subargs[0], "-h") or std.mem.eql(u8, subargs[0], "--help"))) {
            printSubcommandHelp("sprint", "list");
            return;
        }
        const status_filter = getSprintStatusFilter(subargs);
        const result = try sprint.listSprints(allocator, status_filter);
        defer allocator.free(result);
        if (std.mem.indexOf(u8, result, "\"code\":") != null) {
            printStdout("{s}\n", .{result});
            std.process.exit(ExitCode.FAILURE);
        }
        printStdout("{s}\n", .{result});
    } else if (std.mem.eql(u8, subcmd, "get")) {
        if (subargs.len > 0 and (std.mem.eql(u8, subargs[0], "-h") or std.mem.eql(u8, subargs[0], "--help"))) {
            printSubcommandHelp("sprint", "get");
            return;
        }
        if (subargs.len < 1) {
            const exit_code = printErrorWithHelp(allocator, "INVALID_INPUT", "Missing required parameter: sprint ID", "sprint");
            std.process.exit(exit_code);
        }
        const id = std.fmt.parseInt(i64, subargs[0], 10) catch {
            const exit_code = printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid sprint ID: {s}", .{subargs[0]}));
            std.process.exit(exit_code);
        };
        const result = try sprint.getSprint(allocator, id);
        defer allocator.free(result);
        if (std.mem.indexOf(u8, result, "\"code\":") != null) {
            printStdout("{s}\n", .{result});
            std.process.exit(ExitCode.NOT_FOUND);
        }
        printStdout("{s}\n", .{result});
    } else if (std.mem.eql(u8, subcmd, "tasks")) {
        if (subargs.len > 0 and (std.mem.eql(u8, subargs[0], "-h") or std.mem.eql(u8, subargs[0], "--help"))) {
            printSubcommandHelp("sprint", "tasks");
            return;
        }
        if (subargs.len < 1) {
            const exit_code = printErrorWithHelp(allocator, "INVALID_INPUT", "Missing required parameter: sprint ID", "sprint");
            std.process.exit(exit_code);
        }
        const id = std.fmt.parseInt(i64, subargs[0], 10) catch {
            const exit_code = printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid sprint ID: {s}", .{subargs[0]}));
            std.process.exit(exit_code);
        };
        const status_filter = getStatusFilter(subargs);
        const result = try sprint.listSprintTasks(allocator, id, status_filter);
        defer allocator.free(result);
        if (std.mem.indexOf(u8, result, "\"code\":") != null) {
            printStdout("{s}\n", .{result});
            std.process.exit(ExitCode.NOT_FOUND);
        }
        printStdout("{s}\n", .{result});
    } else if (std.mem.eql(u8, subcmd, "create") or std.mem.eql(u8, subcmd, "add") or std.mem.eql(u8, subcmd, "new")) {
        if (subargs.len > 0 and (std.mem.eql(u8, subargs[0], "-h") or std.mem.eql(u8, subargs[0], "--help"))) {
            printSubcommandHelp("sprint", "create");
            return;
        }
        if (subargs.len < 1) {
            const exit_code = printErrorWithHelp(allocator, "INVALID_INPUT", "Missing required parameter: sprint description", "sprint");
            std.process.exit(exit_code);
        }
        const description = try std.mem.join(allocator, " ", subargs);
        defer allocator.free(description);
        const result = try sprint.addSprint(allocator, description);
        defer allocator.free(result);
        if (std.mem.indexOf(u8, result, "\"code\":") != null) {
            printStdout("{s}\n", .{result});
            std.process.exit(ExitCode.FAILURE);
        }
        printStdout("{s}\n", .{result});
    } else if (std.mem.eql(u8, subcmd, "open") or std.mem.eql(u8, subcmd, "start")) {
        if (subargs.len > 0 and (std.mem.eql(u8, subargs[0], "-h") or std.mem.eql(u8, subargs[0], "--help"))) {
            printSubcommandHelp("sprint", "start");
            return;
        }
        if (subargs.len < 1) {
            const exit_code = printErrorWithHelp(allocator, "INVALID_INPUT", "Missing required parameter: sprint ID", "sprint");
            std.process.exit(exit_code);
        }
        const id = std.fmt.parseInt(i64, subargs[0], 10) catch {
            const exit_code = printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid sprint ID: {s}", .{subargs[0]}));
            std.process.exit(exit_code);
        };
        _ = sprint.openSprint(allocator, id) catch |err| {
            const exit_code = printError(allocator, "SPRINT_NOT_FOUND", try std.fmt.allocPrint(allocator, "Sprint not found: {d} (error: {any})", .{ id, err }));
            std.process.exit(exit_code);
        };
        // Success: no output
    } else if (std.mem.eql(u8, subcmd, "close")) {
        if (subargs.len > 0 and (std.mem.eql(u8, subargs[0], "-h") or std.mem.eql(u8, subargs[0], "--help"))) {
            printSubcommandHelp("sprint", "close");
            return;
        }
        if (subargs.len < 1) {
            const exit_code = printErrorWithHelp(allocator, "INVALID_INPUT", "Missing required parameter: sprint ID", "sprint");
            std.process.exit(exit_code);
        }
        const id = std.fmt.parseInt(i64, subargs[0], 10) catch {
            const exit_code = printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid sprint ID: {s}", .{subargs[0]}));
            std.process.exit(exit_code);
        };
        _ = sprint.closeSprint(allocator, id) catch |err| {
            const exit_code = printError(allocator, "SPRINT_NOT_FOUND", try std.fmt.allocPrint(allocator, "Sprint not found: {d} (error: {any})", .{ id, err }));
            std.process.exit(exit_code);
        };
        // Success: no output
    } else if (std.mem.eql(u8, subcmd, "reopen")) {
        if (subargs.len > 0 and (std.mem.eql(u8, subargs[0], "-h") or std.mem.eql(u8, subargs[0], "--help"))) {
            printSubcommandHelp("sprint", "reopen");
            return;
        }
        if (subargs.len < 1) {
            const exit_code = printErrorWithHelp(allocator, "INVALID_INPUT", "Missing required parameter: sprint ID", "sprint");
            std.process.exit(exit_code);
        }
        const id = std.fmt.parseInt(i64, subargs[0], 10) catch {
            const exit_code = printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid sprint ID: {s}", .{subargs[0]}));
            std.process.exit(exit_code);
        };
        _ = sprint.reopenSprint(allocator, id) catch |err| {
            const exit_code = printError(allocator, "SPRINT_NOT_FOUND", try std.fmt.allocPrint(allocator, "Sprint not found: {d} (error: {any})", .{ id, err }));
            std.process.exit(exit_code);
        };
        // Success: no output
    } else if (std.mem.eql(u8, subcmd, "stats")) {
        if (subargs.len > 0 and (std.mem.eql(u8, subargs[0], "-h") or std.mem.eql(u8, subargs[0], "--help"))) {
            printSubcommandHelp("sprint", "stats");
            return;
        }
        if (subargs.len < 1) {
            const exit_code = printErrorWithHelp(allocator, "INVALID_INPUT", "Missing required parameter: sprint ID", "sprint");
            std.process.exit(exit_code);
        }
        const id = std.fmt.parseInt(i64, subargs[0], 10) catch {
            const exit_code = printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid sprint ID: {s}", .{subargs[0]}));
            std.process.exit(exit_code);
        };
        const result = try sprint.getSprintStats(allocator, id);
        defer allocator.free(result);
        if (std.mem.indexOf(u8, result, "\"code\":") != null) {
            printStdout("{s}\n", .{result});
            std.process.exit(ExitCode.NOT_FOUND);
        }
        printStdout("{s}\n", .{result});
    } else if (std.mem.eql(u8, subcmd, "update") or std.mem.eql(u8, subcmd, "upd")) {
        if (subargs.len > 0 and (std.mem.eql(u8, subargs[0], "-h") or std.mem.eql(u8, subargs[0], "--help"))) {
            printSubcommandHelp("sprint", "update");
            return;
        }
        if (subargs.len < 2) {
            const exit_code = printErrorWithHelp(allocator, "INVALID_INPUT", "Missing required parameters: sprint ID and/or description", "sprint");
            std.process.exit(exit_code);
        }
        const id = std.fmt.parseInt(i64, subargs[0], 10) catch {
            const exit_code = printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid sprint ID: {s}", .{subargs[0]}));
            std.process.exit(exit_code);
        };
        const description = try std.mem.join(allocator, " ", subargs[1..]);
        defer allocator.free(description);
        _ = sprint.updateSprint(allocator, id, description) catch |err| {
            const exit_code = printError(allocator, "UPDATE_FAILED", try std.fmt.allocPrint(allocator, "Failed to update sprint: {d} (error: {any})", .{ id, err }));
            std.process.exit(exit_code);
        };
        // Success: no output
    } else if (std.mem.eql(u8, subcmd, "add-tasks") or std.mem.eql(u8, subcmd, "add-task")) {
        if (subargs.len > 0 and (std.mem.eql(u8, subargs[0], "-h") or std.mem.eql(u8, subargs[0], "--help"))) {
            printSubcommandHelp("sprint", "add-tasks");
            return;
        }
        if (subargs.len < 2) {
            const exit_code = printErrorWithHelp(allocator, "INVALID_INPUT", "Missing required parameters: sprint ID and/or task IDs", "sprint");
            std.process.exit(exit_code);
        }
        const sprint_id = std.fmt.parseInt(i64, subargs[0], 10) catch {
            const exit_code = printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid sprint ID: {s}", .{subargs[0]}));
            std.process.exit(exit_code);
        };
        const task_ids = parseIds(allocator, subargs[1]) catch |err| {
            const exit_code = printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid task IDs: {s} (error: {any})", .{ subargs[1], err }));
            std.process.exit(exit_code);
        };
        defer allocator.free(task_ids);

        var results_list: std.ArrayListUnmanaged([]const u8) = .empty;
        defer {
            for (results_list.items) |r| allocator.free(r);
            results_list.deinit(allocator);
        }

        var has_error = false;
        for (task_ids) |task_id| {
            _ = sprint.addTaskToSprint(allocator, sprint_id, task_id) catch |err| {
                printStderr("Failed to add task {d} to sprint {d} (error: {any})\n", .{ task_id, sprint_id, err });
                has_error = true;
                continue;
            };
        }
        // Success: no output on stdout
        if (has_error) {
            std.process.exit(ExitCode.NOT_FOUND);
        }
    } else if (std.mem.eql(u8, subcmd, "remove-task") or std.mem.eql(u8, subcmd, "remove-tasks") or std.mem.eql(u8, subcmd, "rm-tasks")) {
        if (subargs.len > 0 and (std.mem.eql(u8, subargs[0], "-h") or std.mem.eql(u8, subargs[0], "--help"))) {
            printSubcommandHelp("sprint", "remove-tasks");
            return;
        }
        if (subargs.len < 1) {
            const exit_code = printErrorWithHelp(allocator, "INVALID_INPUT", "Missing required parameters: sprint ID and/or task IDs", "sprint");
            std.process.exit(exit_code);
        }

        // Spec says: rmp sprint rm-tasks <sprint_id> <task_ids>
        // But removeTaskFromSprint only needs task_id.
        // We'll skip the first arg if 2 are provided to match the spec.
        const ids_arg = if (subargs.len >= 2) subargs[1] else subargs[0];

        const task_ids = parseIds(allocator, ids_arg) catch |err| {
            const exit_code = printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid task IDs: {s} (error: {any})", .{ ids_arg, err }));
            std.process.exit(exit_code);
        };
        defer allocator.free(task_ids);

        var results_list: std.ArrayListUnmanaged([]const u8) = .empty;
        defer {
            for (results_list.items) |r| allocator.free(r);
            results_list.deinit(allocator);
        }

        var has_error_rm = false;
        for (task_ids) |task_id| {
            _ = sprint.removeTaskFromSprint(allocator, task_id) catch |err| {
                printStderr("Failed to remove task {d} from sprint (error: {any})\n", .{ task_id, err });
                has_error_rm = true;
                continue;
            };
        }
        // Success: no output on stdout
        if (has_error_rm) {
            std.process.exit(ExitCode.NOT_FOUND);
        }
    } else if (std.mem.eql(u8, subcmd, "move-tasks") or std.mem.eql(u8, subcmd, "mv-tasks")) {
        if (subargs.len > 0 and (std.mem.eql(u8, subargs[0], "-h") or std.mem.eql(u8, subargs[0], "--help"))) {
            printSubcommandHelp("sprint", "move-tasks");
            return;
        }
        if (subargs.len < 3) {
            const exit_code = printErrorWithHelp(allocator, "INVALID_INPUT", "Missing required parameters: from sprint ID, to sprint ID, and/or task IDs", "sprint");
            std.process.exit(exit_code);
        }

        // Spec: mv-tasks <from-sprint> <to-sprint> <task-ids...>
        const new_sprint_id = std.fmt.parseInt(i64, subargs[1], 10) catch {
            const exit_code = printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid to_sprint_id: {s}", .{subargs[1]}));
            std.process.exit(exit_code);
        };

        const task_ids = parseIds(allocator, subargs[2]) catch |err| {
            const exit_code = printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid task IDs: {s} (error: {any})", .{ subargs[2], err }));
            std.process.exit(exit_code);
        };
        defer allocator.free(task_ids);

        var results_list: std.ArrayListUnmanaged([]const u8) = .empty;
        defer {
            for (results_list.items) |r| allocator.free(r);
            results_list.deinit(allocator);
        }

        var has_error_mv = false;
        for (task_ids) |task_id| {
            _ = sprint.moveTaskBetweenSprints(allocator, task_id, new_sprint_id) catch |err| {
                printStderr("Failed to move task {d} to sprint {d} (error: {any})\n", .{ task_id, new_sprint_id, err });
                has_error_mv = true;
                continue;
            };
        }
        // Success: no output on stdout
        if (has_error_mv) {
            std.process.exit(ExitCode.NOT_FOUND);
        }
    } else if (std.mem.eql(u8, subcmd, "remove") or std.mem.eql(u8, subcmd, "rm")) {
        if (subargs.len > 0 and (std.mem.eql(u8, subargs[0], "-h") or std.mem.eql(u8, subargs[0], "--help"))) {
            printSubcommandHelp("sprint", "remove");
            return;
        }
        if (subargs.len < 1) {
            const exit_code = printErrorWithHelp(allocator, "INVALID_INPUT", "Missing required parameter: sprint ID(s)", "sprint");
            std.process.exit(exit_code);
        }
        const ids = parseIds(allocator, subargs[0]) catch |err| {
            const exit_code = printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid sprint IDs: {s} (error: {any})", .{ subargs[0], err }));
            std.process.exit(exit_code);
        };
        defer allocator.free(ids);

        var results_list: std.ArrayListUnmanaged([]const u8) = .empty;
        defer {
            for (results_list.items) |r| allocator.free(r);
            results_list.deinit(allocator);
        }

        var has_error_sprint_rm = false;
        for (ids) |id| {
            _ = sprint.deleteSprint(allocator, id) catch |err| {
                printStderr("Failed to delete sprint {d} (error: {any})\n", .{ id, err });
                has_error_sprint_rm = true;
                continue;
            };
        }
        // Success: no output on stdout
        if (has_error_sprint_rm) {
            std.process.exit(ExitCode.NOT_FOUND);
        }
    } else {
        const exit_code = printError(allocator, "UNKNOWN_SUBCOMMAND", try std.fmt.allocPrint(allocator, "Unknown sprint subcommand: {s}", .{subcmd}));
        std.process.exit(exit_code);
    }
}

// ============== AUDIT COMMANDS ==============

fn handleAuditCommand(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len > 0 and (std.mem.eql(u8, args[0], "-h") or std.mem.eql(u8, args[0], "--help"))) {
        printCommandHelp(allocator, "audit");
        return;
    }

    if (args.len == 0) {
        const exit_code = printErrorWithHelp(allocator, "INVALID_INPUT", "Missing required parameter: audit subcommand", "audit");
        std.process.exit(exit_code);
    }

    const subcmd = args[0];
    const subargs = args[1..];

    if (std.mem.eql(u8, subcmd, "list") or std.mem.eql(u8, subcmd, "ls")) {
        if (subargs.len > 0 and (std.mem.eql(u8, subargs[0], "-h") or std.mem.eql(u8, subargs[0], "--help"))) {
            printSubcommandHelp("audit", "list");
            return;
        }
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
                        const exit_code = printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid entity ID: {s}", .{subargs[i]}));
                        std.process.exit(exit_code);
                    };
                }
            } else if (std.mem.eql(u8, arg, "--since")) {
                i += 1;
                if (i < subargs.len) {
                    const since_str = subargs[i];
                    if (!time.isValidIso8601(since_str)) {
                        const exit_code = printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid since date format: {s}. Expected ISO 8601 format (YYYY-MM-DDTHH:mm:ss.sssZ)", .{since_str}));
                        std.process.exit(exit_code);
                    }
                    options.since = since_str;
                }
            } else if (std.mem.eql(u8, arg, "--until")) {
                i += 1;
                if (i < subargs.len) {
                    const until_str = subargs[i];
                    if (!time.isValidIso8601(until_str)) {
                        const exit_code = printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid until date format: {s}. Expected ISO 8601 format (YYYY-MM-DDTHH:mm:ss.sssZ)", .{until_str}));
                        std.process.exit(exit_code);
                    }
                    options.until = until_str;
                }
            } else if (std.mem.eql(u8, arg, "-l") or std.mem.eql(u8, arg, "--limit")) {
                i += 1;
                if (i < subargs.len) {
                    options.limit = std.fmt.parseInt(i32, subargs[i], 10) catch {
                        const exit_code = printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid limit: {s}", .{subargs[i]}));
                        std.process.exit(exit_code);
                    };
                    if (options.limit < 1 or options.limit > 1000) {
                        const exit_code = printError(allocator, "INVALID_INPUT", "Limit must be between 1 and 1000");
                        std.process.exit(exit_code);
                    }
                }
            } else if (std.mem.eql(u8, arg, "--offset")) {
                i += 1;
                if (i < subargs.len) {
                    options.offset = std.fmt.parseInt(i32, subargs[i], 10) catch {
                        const exit_code = printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid offset: {s}", .{subargs[i]}));
                        std.process.exit(exit_code);
                    };
                    if (options.offset < 0) {
                        const exit_code = printError(allocator, "INVALID_INPUT", "Offset must be non-negative");
                        std.process.exit(exit_code);
                    }
                }
            }
        }

        const result = audit.listAuditEntries(allocator, options) catch |err| {
            const exit_code = printError(allocator, "AUDIT_ERROR", try std.fmt.allocPrint(allocator, "Failed to list audit entries: {any}", .{err}));
            std.process.exit(exit_code);
        };
        defer allocator.free(result);
        if (std.mem.indexOf(u8, result, "\"code\":") != null) {
            printStdout("{s}\n", .{result});
            std.process.exit(ExitCode.FAILURE);
        }
        printStdout("{s}\n", .{result});
    } else if (std.mem.eql(u8, subcmd, "history") or std.mem.eql(u8, subcmd, "hist")) {
        if (subargs.len > 0 and (std.mem.eql(u8, subargs[0], "-h") or std.mem.eql(u8, subargs[0], "--help"))) {
            printSubcommandHelp("audit", "history");
            return;
        }
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
                    const exit_code = printError(allocator, "INVALID_INPUT", try std.fmt.allocPrint(allocator, "Invalid entity ID: {s}", .{id_str}));
                    std.process.exit(exit_code);
                };
            }
        }

        if (entity_type == null) {
            const exit_code = printError(allocator, "INVALID_INPUT", "Entity type is required. Use -e or --entity-type (TASK or SPRINT)");
            std.process.exit(exit_code);
        }

        if (entity_id == null) {
            const exit_code = printError(allocator, "INVALID_INPUT", "Entity ID is required");
            std.process.exit(exit_code);
        }

        const result = audit.getEntityHistory(allocator, entity_type.?, entity_id.?) catch |err| {
            const exit_code = printError(allocator, "AUDIT_ERROR", try std.fmt.allocPrint(allocator, "Failed to get entity history: {any}", .{err}));
            std.process.exit(exit_code);
        };
        defer allocator.free(result);
        if (std.mem.indexOf(u8, result, "\"code\":") != null) {
            printStdout("{s}\n", .{result});
            std.process.exit(ExitCode.NOT_FOUND);
        }
        printStdout("{s}\n", .{result});
    } else if (std.mem.eql(u8, subcmd, "stats")) {
        if (subargs.len > 0 and (std.mem.eql(u8, subargs[0], "-h") or std.mem.eql(u8, subargs[0], "--help"))) {
            printSubcommandHelp("audit", "stats");
            return;
        }
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
            const exit_code = printError(allocator, "AUDIT_ERROR", try std.fmt.allocPrint(allocator, "Failed to get audit stats: {any}", .{err}));
            std.process.exit(exit_code);
        };
        defer allocator.free(result);
        if (std.mem.indexOf(u8, result, "\"code\":") != null) {
            printStdout("{s}\n", .{result});
            std.process.exit(ExitCode.FAILURE);
        }
        printStdout("{s}\n", .{result});
    } else {
        const exit_code = printError(allocator, "UNKNOWN_SUBCOMMAND", try std.fmt.allocPrint(allocator, "Unknown audit subcommand: {s}", .{subcmd}));
        std.process.exit(exit_code);
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
            \\usage: rmp roadmap [-h | --help] <subcommand> [<args>]
            \\
            \\Manage roadmaps - the top-level containers for tasks and sprints.
            \\Each roadmap is stored as an independent SQLite database in ~/.roadmaps/
            \\
            \\Subcommands:
            \\   list       List all existing roadmaps
            \\              (alias: ls)
            \\
            \\   create     Create a new roadmap
            \\              (alias: new)
            \\
            \\   remove     Remove a roadmap permanently
            \\              (alias: rm, delete)
            \\
            \\   use        Select a roadmap as default for subsequent commands
            \\
            \\See 'rmp roadmap <subcommand> --help' for more information.
        ;
        printStdout("{s}\n", .{roadmap_help});
    } else if (std.mem.eql(u8, command, "task")) {
        const task_help =
            \\usage: rmp task [-h | --help] <subcommand> [<args>]
            \\
            \\Manage tasks within a roadmap. Tasks track work with status,
            \\priority, severity, and detailed descriptions.
            \\
            \\Subcommands:
            \\   list       List tasks in the selected roadmap
            \\              (alias: ls)
            \\
            \\   create     Create a new task
            \\              (alias: new)
            \\
            \\   get        Get detailed information about task(s)
            \\
            \\   set-status Change task status
            \\              (alias: stat)
            \\
            \\   set-priority
            \\              Change task priority (0-9)
            \\              (alias: prio)
            \\
            \\   set-severity
            \\              Change task severity (0-9)
            \\              (alias: sev)
            \\
            \\   remove     Remove task(s) permanently
            \\              (alias: rm)
            \\
            \\See 'rmp task <subcommand> --help' for more information.
        ;
        printStdout("{s}\n", .{task_help});
    } else if (std.mem.eql(u8, command, "sprint")) {
        const sprint_help =
            \\usage: rmp sprint [-h | --help] <subcommand> [<args>]
            \\
            \\Manage sprints within a roadmap. Sprints group tasks into time-boxed
            \\iterations with lifecycle management (PENDING → OPEN → CLOSED).
            \\
            \\Subcommands:
            \\   list       List sprints in the selected roadmap
            \\              (alias: ls)
            \\
            \\   get        Get detailed information about a sprint
            \\
            \\   tasks      List tasks assigned to a sprint
            \\
            \\   create     Create a new sprint
            \\              (alias: new)
            \\
            \\   add-tasks  Add tasks to a sprint
            \\              (alias: add)
            \\
            \\   remove-tasks
            \\              Remove tasks from a sprint
            \\              (alias: rm-tasks)
            \\
            \\   move-tasks Move tasks between sprints
            \\              (alias: mv-tasks)
            \\
            \\   start      Start a sprint (PENDING → OPEN)
            \\
            \\   close      Close a sprint (OPEN → CLOSED)
            \\
            \\   reopen     Reopen a closed sprint (CLOSED → OPEN)
            \\
            \\   update     Update sprint description
            \\              (alias: upd)
            \\
            \\   stats      Show sprint statistics
            \\
            \\   remove     Remove a sprint
            \\              (alias: rm)
            \\
            \\See 'rmp sprint <subcommand> --help' for more information.
        ;
        printStdout("{s}\n", .{sprint_help});
    } else if (std.mem.eql(u8, command, "audit")) {
        const audit_help =
            \\usage: rmp audit [-h | --help] <subcommand> [<args>]
            \\
            \\View audit log and entity history. All changes to tasks and sprints
            \\are automatically logged for traceability.
            \\
            \\Subcommands:
            \\   list       List audit log entries
            \\              (alias: ls)
            \\
            \\   history    View history for a specific entity
            \\              (alias: hist)
            \\
            \\   stats      Show audit statistics
            \\
            \\See 'rmp audit <subcommand> --help' for more information.
        ;
        printStdout("{s}\n", .{audit_help});
    } else {
        printUsage(allocator);
    }
}

fn printCommandHelpStderr(allocator: std.mem.Allocator, command: []const u8) void {
    if (std.mem.eql(u8, command, "roadmap")) {
        const roadmap_help =
            \\usage: rmp roadmap [-h | --help] <subcommand> [<args>]
            \\
            \\Manage roadmaps - the top-level containers for tasks and sprints.
            \\Each roadmap is stored as an independent SQLite database in ~/.roadmaps/
            \\
            \\Subcommands:
            \\   list       List all existing roadmaps
            \\              (alias: ls)
            \\
            \\   create     Create a new roadmap
            \\              (alias: new)
            \\
            \\   remove     Remove a roadmap permanently
            \\              (alias: rm, delete)
            \\
            \\   use        Select a roadmap as default for subsequent commands
            \\
            \\See 'rmp roadmap <subcommand> --help' for more information.
        ;
        printStderr("{s}\n", .{roadmap_help});
    } else if (std.mem.eql(u8, command, "task")) {
        const task_help =
            \\usage: rmp task [-h | --help] <subcommand> [<args>]
            \\
            \\Manage tasks within a roadmap. Tasks track work with status,
            \\priority, severity, and detailed descriptions.
            \\
            \\Subcommands:
            \\   list       List tasks in the selected roadmap
            \\              (alias: ls)
            \\
            \\   create     Create a new task
            \\              (alias: new)
            \\
            \\   get        Get detailed information about task(s)
            \\
            \\   set-status Change task status
            \\              (alias: stat)
            \\
            \\   set-priority
            \\              Change task priority (0-9)
            \\              (alias: prio)
            \\
            \\   set-severity
            \\              Change task severity (0-9)
            \\              (alias: sev)
            \\
            \\   remove     Remove task(s) permanently
            \\              (alias: rm)
            \\
            \\See 'rmp task <subcommand> --help' for more information.
        ;
        printStderr("{s}\n", .{task_help});
    } else if (std.mem.eql(u8, command, "sprint")) {
        const sprint_help =
            \\usage: rmp sprint [-h | --help] <subcommand> [<args>]
            \\
            \\Manage sprints within a roadmap. Sprints group tasks into time-boxed
            \\iterations with lifecycle management (PENDING → OPEN → CLOSED).
            \\
            \\Subcommands:
            \\   list       List sprints in the selected roadmap
            \\              (alias: ls)
            \\
            \\   get        Get detailed information about a sprint
            \\
            \\   tasks      List tasks assigned to a sprint
            \\
            \\   create     Create a new sprint
            \\              (alias: new)
            \\
            \\   add-tasks  Add tasks to a sprint
            \\              (alias: add)
            \\
            \\   remove-tasks
            \\              Remove tasks from a sprint
            \\              (alias: rm-tasks)
            \\
            \\   move-tasks Move tasks between sprints
            \\              (alias: mv-tasks)
            \\
            \\   start      Start a sprint (PENDING → OPEN)
            \\
            \\   close      Close a sprint (OPEN → CLOSED)
            \\
            \\   reopen     Reopen a closed sprint (CLOSED → OPEN)
            \\
            \\   update     Update sprint description
            \\              (alias: upd)
            \\
            \\   stats      Show sprint statistics
            \\
            \\   remove     Remove a sprint
            \\              (alias: rm)
            \\
            \\See 'rmp sprint <subcommand> --help' for more information.
        ;
        printStderr("{s}\n", .{sprint_help});
    } else if (std.mem.eql(u8, command, "audit")) {
        const audit_help =
            \\usage: rmp audit [-h | --help] <subcommand> [<args>]
            \\
            \\View audit log and entity history. All changes to tasks and sprints
            \\are automatically logged for traceability.
            \\
            \\Subcommands:
            \\   list       List audit log entries
            \\              (alias: ls)
            \\
            \\   history    View history for a specific entity
            \\              (alias: hist)
            \\
            \\   stats      Show audit statistics
            \\
            \\See 'rmp audit <subcommand> --help' for more information.
        ;
        printStderr("{s}\n", .{audit_help});
    } else {
        printUsageStderr(allocator);
    }
}

// ============== SUBCOMMAND HELP FUNCTIONS ==============

fn printSubcommandHelp(command: []const u8, subcommand: []const u8) void {
    if (std.mem.eql(u8, command, "roadmap")) {
        if (std.mem.eql(u8, subcommand, "list") or std.mem.eql(u8, subcommand, "ls")) {
            const help =
                \\usage: rmp roadmap list [-h | --help]
                \\
                \\List all existing roadmaps in ~/.roadmaps/
                \\
                \\Output: JSON array of roadmap objects
                \\
                \\Example:
                \\   rmp roadmap list
                \\   rmp road ls
            ;
            printStdout("{s}\n", .{help});
        } else if (std.mem.eql(u8, subcommand, "create") or std.mem.eql(u8, subcommand, "new")) {
            const help =
                \\usage: rmp roadmap create [-h | --help] [--force] <name>
                \\
                \\Create a new roadmap with the given name.
                \\The roadmap will be stored as ~/.roadmaps/<name>.db
                \\
                \\Options:
                \\   --force    Overwrite if roadmap already exists
                \\
                \\Arguments:
                \\   <name>     Name for the new roadmap (alphanumeric, hyphens, underscores)
                \\
                \\Example:
                \\   rmp roadmap create project1
                \\   rmp road new myproject --force
            ;
            printStdout("{s}\n", .{help});
        } else if (std.mem.eql(u8, subcommand, "remove") or std.mem.eql(u8, subcommand, "rm") or std.mem.eql(u8, subcommand, "delete")) {
            const help =
                \\usage: rmp roadmap remove [-h | --help] <name>
                \\
                \\Remove a roadmap permanently. This action cannot be undone.
                \\
                \\Arguments:
                \\   <name>     Name of the roadmap to remove
                \\
                \\Example:
                \\   rmp roadmap remove project1
                \\   rmp road rm oldproject
            ;
            printStdout("{s}\n", .{help});
        } else if (std.mem.eql(u8, subcommand, "use")) {
            const help =
                \\usage: rmp roadmap use [-h | --help] <name>
                \\
                \\Select a roadmap as the default for subsequent commands.
                \\This avoids repeating --roadmap flag in every command.
                \\
                \\Arguments:
                \\   <name>     Name of the roadmap to select
                \\
                \\Example:
                \\   rmp roadmap use project1
                \\   rmp road use myproject
            ;
            printStdout("{s}\n", .{help});
        } else {
            printCommandHelp(std.heap.page_allocator, command);
        }
    } else if (std.mem.eql(u8, command, "task")) {
        if (std.mem.eql(u8, subcommand, "list") or std.mem.eql(u8, subcommand, "ls")) {
            const help =
                \\usage: rmp task list [-h | --help] [-r <name>] [-s <status>] [-p <n>] [--severity <n>] [-l <n>]
                \\
                \\List tasks in the selected roadmap.
                \\
                \\Options:
                \\   -r, --roadmap <name>   Roadmap name (required if no default set)
                \\   -s, --status <status>  Filter by status: BACKLOG, SPRINT, DOING, TESTING, COMPLETED
                \\   -p, --priority <n>     Filter by minimum priority (0-9)
                \\       --severity <n>     Filter by minimum severity (0-9)
                \\   -l, --limit <n>        Limit number of results
                \\
                \\Output: JSON array of task objects
                \\
                \\Examples:
                \\   rmp task list -r project1
                \\   rmp task ls -r project1 -s DOING
                \\   rmp task ls -r project1 -p 5 -l 20
            ;
            printStdout("{s}\n", .{help});
        } else if (std.mem.eql(u8, subcommand, "create") or std.mem.eql(u8, subcommand, "new") or std.mem.eql(u8, subcommand, "add")) {
            const help =
                \\usage: rmp task create [-h | --help] -r <name> -d <desc> -a <action> -e <result> [-p <n>] [--severity <n>] [--specialists <list>]
                \\
                \\Create a new task in the specified roadmap.
                \\
                \\Required Options:
                \\   -r, --roadmap <name>           Roadmap name
                \\   -d, --description <desc>         Task description
                \\   -a, --action <action>            Technical action to perform
                \\   -e, --expected-result <result>   Expected outcome
                \\
                \\Optional Options:
                \\   -p, --priority <n>               Priority 0-9 (default: 0)
                \\       --severity <n>               Severity 0-9 (default: 0)
                \\       --specialists <list>         Comma-separated specialist tags
                \\
                \\Output: JSON object with task ID
                \\
                \\Examples:
                \\   rmp task create -r project1 -d "Fix login bug" -a "Debug auth" -e "Login works"
                \\   rmp task new -r project1 -d "Update docs" -a "Write README" -e "Docs complete" -p 5
            ;
            printStdout("{s}\n", .{help});
        } else if (std.mem.eql(u8, subcommand, "get")) {
            const help =
                \\usage: rmp task get [-h | --help] -r <name> <id>[,<id>,...]
                \\
                \\Get detailed information about one or more tasks.
                \\
                \\Options:
                \\   -r, --roadmap <name>   Roadmap name (required)
                \\
                \\Arguments:
                \\   <id>[,<id>,...]        Comma-separated task IDs (no spaces)
                \\
                \\Output: JSON array of task objects
                \\
                \\Examples:
                \\   rmp task get -r project1 42
                \\   rmp task get -r project1 1,2,3,10
            ;
            printStdout("{s}\n", .{help});
        } else if (std.mem.eql(u8, subcommand, "set-status") or std.mem.eql(u8, subcommand, "status") or std.mem.eql(u8, subcommand, "stat")) {
            const help =
                \\usage: rmp task set-status [-h | --help] -r <name> <id>[,<id>,...] <state>
                \\
                \\Change the status of one or more tasks.
                \\
                \\Options:
                \\   -r, --roadmap <name>   Roadmap name (required)
                \\
                \\Arguments:
                \\   <id>[,<id>,...]        Comma-separated task IDs (no spaces)
                \\   <state>                New status: BACKLOG, SPRINT, DOING, TESTING, COMPLETED
                \\
                \\Status Flow:
                \\   BACKLOG → SPRINT → DOING → TESTING → COMPLETED
                \\
                \\Examples:
                \\   rmp task set-status -r project1 42 DOING
                \\   rmp task stat -r project1 1,2,3 COMPLETED
            ;
            printStdout("{s}\n", .{help});
        } else if (std.mem.eql(u8, subcommand, "set-priority") or std.mem.eql(u8, subcommand, "priority") or std.mem.eql(u8, subcommand, "prio")) {
            const help =
                \\usage: rmp task set-priority [-h | --help] -r <name> <id>[,<id>,...] <priority>
                \\
                \\Change the priority of one or more tasks.
                \\
                \\Options:
                \\   -r, --roadmap <name>   Roadmap name (required)
                \\
                \\Arguments:
                \\   <id>[,<id>,...]        Comma-separated task IDs (no spaces)
                \\   <priority>             Priority value 0-9
                \\
                \\Priority Scale:
                \\   0 = low urgency, 9 = maximum urgency (Product Owner perspective)
                \\
                \\Examples:
                \\   rmp task set-priority -r project1 42 9
                \\   rmp task prio -r project1 1,2,3 5
            ;
            printStdout("{s}\n", .{help});
        } else if (std.mem.eql(u8, subcommand, "set-severity") or std.mem.eql(u8, subcommand, "severity") or std.mem.eql(u8, subcommand, "sev")) {
            const help =
                \\usage: rmp task set-severity [-h | --help] -r <name> <id>[,<id>,...] <severity>
                \\
                \\Change the severity of one or more tasks.
                \\
                \\Options:
                \\   -r, --roadmap <name>   Roadmap name (required)
                \\
                \\Arguments:
                \\   <id>[,<id>,...]        Comma-separated task IDs (no spaces)
                \\   <severity>             Severity value 0-9
                \\
                \\Severity Scale:
                \\   0 = minimal impact, 9 = critical impact (Dev Team perspective)
                \\
                \\Examples:
                \\   rmp task set-severity -r project1 42 5
                \\   rmp task sev -r project1 1,2,3 9
            ;
            printStdout("{s}\n", .{help});
        } else if (std.mem.eql(u8, subcommand, "remove") or std.mem.eql(u8, subcommand, "rm") or std.mem.eql(u8, subcommand, "delete")) {
            const help =
                \\usage: rmp task remove [-h | --help] -r <name> <id>[,<id>,...]
                \\
                \\Remove one or more tasks permanently. This action cannot be undone.
                \\
                \\Options:
                \\   -r, --roadmap <name>   Roadmap name (required)
                \\
                \\Arguments:
                \\   <id>[,<id>,...]        Comma-separated task IDs (no spaces)
                \\
                \\Examples:
                \\   rmp task remove -r project1 42
                \\   rmp task rm -r project1 1,2,3
            ;
            printStdout("{s}\n", .{help});
        } else {
            printCommandHelp(std.heap.page_allocator, command);
        }
    } else if (std.mem.eql(u8, command, "sprint")) {
        if (std.mem.eql(u8, subcommand, "list") or std.mem.eql(u8, subcommand, "ls")) {
            const help =
                \\usage: rmp sprint list [-h | --help] [-r <name>] [-s <status>]
                \\
                \\List sprints in the selected roadmap.
                \\
                \\Options:
                \\   -r, --roadmap <name>   Roadmap name (required if no default set)
                \\   -s, --status <status>  Filter by status: PENDING, OPEN, CLOSED
                \\
                \\Output: JSON array of sprint objects
                \\
                \\Examples:
                \\   rmp sprint list -r project1
                \\   rmp sprint ls -r project1 -s OPEN
            ;
            printStdout("{s}\n", .{help});
        } else if (std.mem.eql(u8, subcommand, "get")) {
            const help =
                \\usage: rmp sprint get [-h | --help] -r <name> <id>
                \\
                \\Get detailed information about a specific sprint.
                \\
                \\Options:
                \\   -r, --roadmap <name>   Roadmap name (required)
                \\
                \\Arguments:
                \\   <id>                   Sprint ID
                \\
                \\Output: JSON sprint object
                \\
                \\Example:
                \\   rmp sprint get -r project1 1
            ;
            printStdout("{s}\n", .{help});
        } else if (std.mem.eql(u8, subcommand, "tasks")) {
            const help =
                \\usage: rmp sprint tasks [-h | --help] -r <name> <sprint-id> [-s <status>]
                \\
                \\List tasks assigned to a specific sprint.
                \\
                \\Options:
                \\   -r, --roadmap <name>   Roadmap name (required)
                \\   -s, --status <status>  Filter by task status
                \\
                \\Arguments:
                \\   <sprint-id>            Sprint ID
                \\
                \\Output: JSON array of task objects
                \\
                \\Examples:
                \\   rmp sprint tasks -r project1 1
                \\   rmp sprint tasks -r project1 1 -s DOING
            ;
            printStdout("{s}\n", .{help});
        } else if (std.mem.eql(u8, subcommand, "create") or std.mem.eql(u8, subcommand, "new") or std.mem.eql(u8, subcommand, "add")) {
            const help =
                \\usage: rmp sprint create [-h | --help] -r <name> -d <description>
                \\
                \\Create a new sprint in the specified roadmap.
                \\
                \\Options:
                \\   -r, --roadmap <name>        Roadmap name (required)
                \\   -d, --description <desc>     Sprint description
                \\
                \\Output: JSON object with sprint ID
                \\
                \\Example:
                \\   rmp sprint create -r project1 -d "Sprint 1 - Initial Setup"
                \\   rmp sprint new -r project1 -d "Sprint 2 - Features"
            ;
            printStdout("{s}\n", .{help});
        } else if (std.mem.eql(u8, subcommand, "add-tasks") or std.mem.eql(u8, subcommand, "add-task")) {
            const help =
                \\usage: rmp sprint add-tasks [-h | --help] -r <name> <sprint-id> <task-ids>
                \\
                \\Add tasks to a sprint. Tasks must be in BACKLOG status.
                \\
                \\Options:
                \\   -r, --roadmap <name>   Roadmap name (required)
                \\
                \\Arguments:
                \\   <sprint-id>            Sprint ID to add tasks to
                \\   <task-ids>             Comma-separated task IDs (no spaces)
                \\
                \\Examples:
                \\   rmp sprint add-tasks -r project1 1 10,11,12
                \\   rmp sprint add -r project1 2 5,6,7,8
            ;
            printStdout("{s}\n", .{help});
        } else if (std.mem.eql(u8, subcommand, "remove-tasks") or std.mem.eql(u8, subcommand, "remove-task") or std.mem.eql(u8, subcommand, "rm-tasks")) {
            const help =
                \\usage: rmp sprint remove-tasks [-h | --help] -r <name> <sprint-id> <task-ids>
                \\
                \\Remove tasks from a sprint. Tasks return to BACKLOG status.
                \\
                \\Options:
                \\   -r, --roadmap <name>   Roadmap name (required)
                \\
                \\Arguments:
                \\   <sprint-id>            Sprint ID to remove tasks from
                \\   <task-ids>             Comma-separated task IDs (no spaces)
                \\
                \\Examples:
                \\   rmp sprint remove-tasks -r project1 1 10,11,12
                \\   rmp sprint rm-tasks -r project1 1 5,6
            ;
            printStdout("{s}\n", .{help});
        } else if (std.mem.eql(u8, subcommand, "move-tasks") or std.mem.eql(u8, subcommand, "mv-tasks")) {
            const help =
                \\usage: rmp sprint move-tasks [-h | --help] -r <name> <from-sprint> <to-sprint> <task-ids>
                \\
                \\Move tasks from one sprint to another.
                \\
                \\Options:
                \\   -r, --roadmap <name>   Roadmap name (required)
                \\
                \\Arguments:
                \\   <from-sprint>          Source sprint ID
                \\   <to-sprint>            Destination sprint ID
                \\   <task-ids>             Comma-separated task IDs (no spaces)
                \\
                \\Examples:
                \\   rmp sprint move-tasks -r project1 1 2 10,11,12
                \\   rmp sprint mv-tasks -r project1 2 3 5,6,7
            ;
            printStdout("{s}\n", .{help});
        } else if (std.mem.eql(u8, subcommand, "start") or std.mem.eql(u8, subcommand, "open")) {
            const help =
                \\usage: rmp sprint start [-h | --help] -r <name> <id>
                \\
                \\Start a sprint, changing its status from PENDING to OPEN.
                \\
                \\Options:
                \\   -r, --roadmap <name>   Roadmap name (required)
                \\
                \\Arguments:
                \\   <id>                   Sprint ID to start
                \\
                \\Example:
                \\   rmp sprint start -r project1 1
            ;
            printStdout("{s}\n", .{help});
        } else if (std.mem.eql(u8, subcommand, "close")) {
            const help =
                \\usage: rmp sprint close [-h | --help] -r <name> <id>
                \\
                \\Close a sprint, changing its status from OPEN to CLOSED.
                \\
                \\Options:
                \\   -r, --roadmap <name>   Roadmap name (required)
                \\
                \\Arguments:
                \\   <id>                   Sprint ID to close
                \\
                \\Example:
                \\   rmp sprint close -r project1 1
            ;
            printStdout("{s}\n", .{help});
        } else if (std.mem.eql(u8, subcommand, "reopen")) {
            const help =
                \\usage: rmp sprint reopen [-h | --help] -r <name> <id>
                \\
                \\Reopen a closed sprint, changing its status from CLOSED to OPEN.
                \\
                \\Options:
                \\   -r, --roadmap <name>   Roadmap name (required)
                \\
                \\Arguments:
                \\   <id>                   Sprint ID to reopen
                \\
                \\Example:
                \\   rmp sprint reopen -r project1 1
            ;
            printStdout("{s}\n", .{help});
        } else if (std.mem.eql(u8, subcommand, "update") or std.mem.eql(u8, subcommand, "upd")) {
            const help =
                \\usage: rmp sprint update [-h | --help] -r <name> <id> -d <description>
                \\
                \\Update a sprint's description.
                \\
                \\Options:
                \\   -r, --roadmap <name>        Roadmap name (required)
                \\   -d, --description <desc>     New description
                \\
                \\Arguments:
                \\   <id>                        Sprint ID
                \\
                \\Example:
                \\   rmp sprint update -r project1 1 -d "Sprint 1 - Setup and Config"
                \\   rmp sprint upd -r project1 1 -d "Updated description"
            ;
            printStdout("{s}\n", .{help});
        } else if (std.mem.eql(u8, subcommand, "stats")) {
            const help =
                \\usage: rmp sprint stats [-h | --help] -r <name> <id>
                \\
                \\Show statistics for a sprint including task counts by status.
                \\
                \\Options:
                \\   -r, --roadmap <name>   Roadmap name (required)
                \\
                \\Arguments:
                \\   <id>                   Sprint ID
                \\
                \\Output: JSON statistics object
                \\
                \\Example:
                \\   rmp sprint stats -r project1 1
            ;
            printStdout("{s}\n", .{help});
        } else if (std.mem.eql(u8, subcommand, "remove") or std.mem.eql(u8, subcommand, "rm")) {
            const help =
                \\usage: rmp sprint remove [-h | --help] -r <name> <id>
                \\
                \\Remove a sprint permanently. Tasks in the sprint are not deleted.
                \\
                \\Options:
                \\   -r, --roadmap <name>   Roadmap name (required)
                \\
                \\Arguments:
                \\   <id>                   Sprint ID to remove
                \\
                \\Example:
                \\   rmp sprint remove -r project1 1
                \\   rmp sprint rm -r project1 2
            ;
            printStdout("{s}\n", .{help});
        } else {
            printCommandHelp(std.heap.page_allocator, command);
        }
    } else if (std.mem.eql(u8, command, "audit")) {
        if (std.mem.eql(u8, subcommand, "list") or std.mem.eql(u8, subcommand, "ls")) {
            const help =
                \\usage: rmp audit list [-h | --help] -r <name> [-o <operation>] [-e <type>] [--entity-id <id>] [--since <date>] [--until <date>] [-l <n>]
                \\
                \\List audit log entries with optional filtering.
                \\
                \\Options:
                \\   -r, --roadmap <name>        Roadmap name (required)
                \\   -o, --operation <type>     Filter by operation type:
                \\                               TASK_CREATE, TASK_UPDATE, TASK_STATUS_CHANGE,
                \\                               TASK_PRIORITY_CHANGE, TASK_SEVERITY_CHANGE,
                \\                               TASK_DELETE, SPRINT_CREATE, SPRINT_UPDATE,
                \\                               SPRINT_START, SPRINT_CLOSE, SPRINT_REOPEN,
                \\                               SPRINT_DELETE, SPRINT_TASK_ADD,
                \\                               SPRINT_TASK_REMOVE, SPRINT_TASK_MOVE
                \\   -e, --entity-type <type>   Filter by entity type: TASK, SPRINT
                \\       --entity-id <id>        Filter by specific entity ID
                \\       --since <date>          Include entries from this date (ISO 8601)
                \\       --until <date>          Include entries until this date (ISO 8601)
                \\   -l, --limit <n>             Limit number of results
                \\
                \\Output: JSON array of audit entries
                \\
                \\Examples:
                \\   rmp audit list -r project1
                \\   rmp audit ls -r project1 -o TASK_STATUS_CHANGE
                \\   rmp audit ls -r project1 -e TASK --since 2026-03-01T00:00:00.000Z
            ;
            printStdout("{s}\n", .{help});
        } else if (std.mem.eql(u8, subcommand, "history") or std.mem.eql(u8, subcommand, "hist")) {
            const help =
                \\usage: rmp audit history [-h | --help] -r <name> -e <type> <id>
                \\
                \\View complete history for a specific entity (task or sprint).
                \\
                \\Options:
                \\   -r, --roadmap <name>        Roadmap name (required)
                \\   -e, --entity-type <type>    Entity type: TASK, SPRINT (required)
                \\
                \\Arguments:
                \\   <id>                        Entity ID
                \\
                \\Output: JSON array of audit entries for the entity
                \\
                \\Examples:
                \\   rmp audit history -r project1 -e TASK 42
                \\   rmp audit hist -r project1 -e SPRINT 1
            ;
            printStdout("{s}\n", .{help});
        } else if (std.mem.eql(u8, subcommand, "stats")) {
            const help =
                \\usage: rmp audit stats [-h | --help] -r <name> [--since <date>] [--until <date>]
                \\
                \\Show audit statistics including operation counts and trends.
                \\
                \\Options:
                \\   -r, --roadmap <name>        Roadmap name (required)
                \\       --since <date>          Include entries from this date (ISO 8601)
                \\       --until <date>          Include entries until this date (ISO 8601)
                \\
                \\Output: JSON statistics object
                \\
                \\Examples:
                \\   rmp audit stats -r project1
                \\   rmp audit stats -r project1 --since 2026-03-01T00:00:00.000Z
            ;
            printStdout("{s}\n", .{help});
        } else {
            printCommandHelp(std.heap.page_allocator, command);
        }
    }
}

fn printUsage(allocator: std.mem.Allocator) void {
    _ = allocator;
    const help_text =
        \\usage: rmp [-h | --help] [-v | --version] <command> [<args>]
        \\
        \\Local Roadmap Manager - CLI for managing technical roadmaps, tasks, and sprints
        \\
        \\These are common LRoadmap commands used in various situations:
        \\
        \\manage roadmaps
        \\   roadmap    Create, list, and manage roadmaps
        \\              (alias: road)
        \\
        \\manage tasks
        \\   task       Create, list, and manage tasks
        \\              Includes status, priority, and severity management
        \\
        \\manage sprints
        \\   sprint     Create, manage, and track sprints
        \\              Includes task assignment and sprint lifecycle
        \\
        \\view audit trail
        \\   audit      View audit log and entity history
        \\              (alias: aud)
        \\
        \\See 'rmp <command> --help' to read about a specific command.
        \\See 'rmp <command> <subcommand> --help' for subcommand details.
    ;
    printStdout("{s}\n", .{help_text});
}

fn printUsageStderr(allocator: std.mem.Allocator) void {
    _ = allocator;
    const help_text =
        \\usage: rmp [-h | --help] [-v | --version] <command> [<args>]
        \\
        \\Local Roadmap Manager - CLI for managing technical roadmaps, tasks, and sprints
        \\
        \\These are common LRoadmap commands used in various situations:
        \\
        \\manage roadmaps
        \\   roadmap    Create, list, and manage roadmaps
        \\              (alias: road)
        \\
        \\manage tasks
        \\   task       Create, list, and manage tasks
        \\              Includes status, priority, and severity management
        \\
        \\manage sprints
        \\   sprint     Create, manage, and track sprints
        \\              Includes task assignment and sprint lifecycle
        \\
        \\view audit trail
        \\   audit      View audit log and entity history
        \\              (alias: aud)
        \\
        \\See 'rmp <command> --help' to read about a specific command.
        \\See 'rmp <command> <subcommand> --help' for subcommand details.
    ;
    printStderr("{s}\n", .{help_text});
}
