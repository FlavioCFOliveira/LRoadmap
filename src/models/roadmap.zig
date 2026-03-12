const std = @import("std");

/// Roadmap model
pub const Roadmap = struct {
    name: []const u8,
    path: []const u8,
    size: i64,
    created_at: []const u8,

    pub fn init(
        allocator: std.mem.Allocator,
        name: []const u8,
        path: []const u8,
        size: i64,
        created_at: []const u8,
    ) !Roadmap {
        return Roadmap{
            .name = try allocator.dupe(u8, name),
            .path = try allocator.dupe(u8, path),
            .size = size,
            .created_at = try allocator.dupe(u8, created_at),
        };
    }

    pub fn deinit(self: *Roadmap, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.path);
        allocator.free(self.created_at);
    }

    /// Validates a roadmap name
    pub fn isValidName(name: []const u8) bool {
        if (name.len == 0 or name.len > 50) return false;
        for (name) |c| {
            const valid = std.ascii.isAlphanumeric(c) or c == '-' or c == '_';
            if (!valid) return false;
        }
        return true;
    }
};

/// Roadmap list response
pub const RoadmapList = struct {
    count: i32,
    roadmaps: []Roadmap,

    pub fn init(count: i32, roadmaps: []Roadmap) RoadmapList {
        return RoadmapList{
            .count = count,
            .roadmaps = roadmaps,
        };
    }
};

// ============== TESTS ==============

test "Roadmap isValidName" {
    try std.testing.expect(Roadmap.isValidName("project1"));
    try std.testing.expect(!Roadmap.isValidName(""));
    try std.testing.expect(!Roadmap.isValidName("project with spaces"));
}

test "Roadmap init and deinit" {
    const allocator = std.testing.allocator;
    var roadmap = try Roadmap.init(
        allocator,
        "myproject",
        "/home/user/.roadmaps/myproject.db",
        24576,
        "2026-03-12T14:30:00.000Z",
    );
    defer roadmap.deinit(allocator);
    try std.testing.expectEqualStrings("myproject", roadmap.name);
}
