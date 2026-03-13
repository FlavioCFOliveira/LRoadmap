const std = @import("std");

/// Name of the directory where roadmaps are stored
pub const ROADMAPS_DIR_NAME = ".roadmaps";

/// Extension for roadmap database files
pub const ROADMAP_EXTENSION = ".db";

/// Maximum length for roadmap names
pub const MAX_ROADMAP_NAME_LEN = 50;

/// Returns the path to the user's home directory.
/// Caller owns the returned memory.
pub fn getHomeDir(allocator: std.mem.Allocator) ![]const u8 {
    // Try environment variables in order of preference
    const env_vars = [_][]const u8{ "HOME", "USERPROFILE", "HOMEDRIVE", "HOMEPATH" };

    for (env_vars) |var_name| {
        if (std.process.getEnvVarOwned(allocator, var_name)) |value| {
            return value;
        } else |_| {
            continue;
        }
    }

    return error.HomeDirNotFound;
}

/// Returns the path to the .roadmaps directory (~/.roadmaps).
/// Caller owns the returned memory.
pub fn getRoadmapsDir(allocator: std.mem.Allocator) ![]const u8 {
    const home = try getHomeDir(allocator);
    defer allocator.free(home);

    return std.fs.path.join(allocator, &[_][]const u8{ home, ROADMAPS_DIR_NAME });
}

/// Returns the full path for a roadmap database file.
/// Caller owns the returned memory.
pub fn getRoadmapPath(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    const roadmaps_dir = try getRoadmapsDir(allocator);
    defer allocator.free(roadmaps_dir);

    const filename = try std.fmt.allocPrint(allocator, "{s}{s}", .{ name, ROADMAP_EXTENSION });
    defer allocator.free(filename);

    return std.fs.path.join(allocator, &[_][]const u8{ roadmaps_dir, filename });
}

/// Ensures the .roadmaps directory exists, creating it if necessary.
pub fn ensureRoadmapsDirExists() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const roadmaps_dir = try getRoadmapsDir(allocator);

    std.fs.cwd().makeDir(roadmaps_dir) catch |err| {
        switch (err) {
            error.PathAlreadyExists => {}, // Directory already exists, ok
            else => return err,
        }
    };
}

/// Ensures a directory exists, creating it if necessary.
pub fn ensureDirExists(path: []const u8) !void {
    std.fs.cwd().makeDir(path) catch |err| {
        switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        }
    };
}

/// Validates a roadmap name.
/// Rules: alphanumeric, hyphens, underscores only; max 50 characters.
pub fn isValidRoadmapName(name: []const u8) bool {
    if (name.len == 0 or name.len > MAX_ROADMAP_NAME_LEN) return false;

    for (name) |c| {
        const valid = std.ascii.isAlphanumeric(c) or c == '-' or c == '_';
        if (!valid) return false;
    }

    return true;
}

/// Checks if a file exists at the given path.
pub fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

/// Returns the roadmap name from a file path (without extension).
/// Caller owns the returned memory.
pub fn getRoadmapNameFromPath(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const basename = std.fs.path.basename(path);

    // Remove .db extension
    if (std.mem.endsWith(u8, basename, ROADMAP_EXTENSION)) {
        const name_len = basename.len - ROADMAP_EXTENSION.len;
        return try allocator.dupe(u8, basename[0..name_len]);
    }

    return try allocator.dupe(u8, basename);
}

/// Lists all roadmap files in the .roadmaps directory.
/// Returns an array of roadmap names (without .db extension).
/// Caller owns the returned memory and must free each name and the array.
pub fn listRoadmaps(allocator: std.mem.Allocator) ![][]const u8 {
    const roadmaps_dir = try getRoadmapsDir(allocator);
    defer allocator.free(roadmaps_dir);

    var dir = std.fs.cwd().openDir(roadmaps_dir, .{ .iterate = true }) catch |err| {
        // If directory doesn't exist, return empty list
        if (err == error.FileNotFound) return &[_][]const u8{};
        return err;
    };
    defer dir.close();

    var names: std.ArrayListUnmanaged([]const u8) = .empty;
    defer {
        for (names.items) |name| {
            allocator.free(name);
        }
        names.deinit(allocator);
    }

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ROADMAP_EXTENSION)) {
            const name = try allocator.dupe(u8, entry.name);
            // Remove .db extension
            const clean_name = name[0 .. name.len - ROADMAP_EXTENSION.len];
            const name_copy = try allocator.dupe(u8, clean_name);
            allocator.free(name);
            try names.append(allocator, name_copy);
        }
    }

    // Transfer ownership
    const result = try names.toOwnedSlice(allocator);
    return result;
}

// ============== TESTS ==============

test "getHomeDir returns valid path" {
    const allocator = std.testing.allocator;
    const home = try getHomeDir(allocator);
    defer allocator.free(home);

    try std.testing.expect(home.len > 0);
}

test "getRoadmapsDir returns valid path" {
    const allocator = std.testing.allocator;
    const dir = try getRoadmapsDir(allocator);
    defer allocator.free(dir);

    try std.testing.expect(std.mem.endsWith(u8, dir, ".roadmaps"));
}

test "getRoadmapPath returns correct path" {
    const allocator = std.testing.allocator;
    const path = try getRoadmapPath(allocator, "myproject");
    defer allocator.free(path);

    try std.testing.expect(std.mem.endsWith(u8, path, ".roadmaps/myproject.db"));
}

test "isValidRoadmapName validates correctly" {
    // Valid names
    try std.testing.expect(isValidRoadmapName("project1"));
    try std.testing.expect(isValidRoadmapName("my-project"));
    try std.testing.expect(isValidRoadmapName("my_project"));
    try std.testing.expect(isValidRoadmapName("Project123"));

    // Invalid names
    try std.testing.expect(!isValidRoadmapName("")); // Empty
    try std.testing.expect(!isValidRoadmapName("project with spaces")); // Spaces
    try std.testing.expect(!isValidRoadmapName("project@#$")); // Special chars
    try std.testing.expect(!isValidRoadmapName("/path/to/project")); // Path separators
}

test "getRoadmapNameFromPath extracts name" {
    const allocator = std.testing.allocator;
    const name = try getRoadmapNameFromPath(allocator, "/home/user/.roadmaps/myproject.db");
    defer allocator.free(name);

    try std.testing.expectEqualStrings("myproject", name);
}
