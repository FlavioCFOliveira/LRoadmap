const std = @import("std");

pub const AppError = error{
    InvalidInput,
    RoadmapNotFound,
    RoadmapExists,
    InvalidSqliteFile,
    TaskNotFound,
    SprintNotFound,
    InvalidStatus,
    InvalidPriority,
    DbError,
    SystemError,
    UnknownCommand,
    UnknownSubcommand,
};

pub fn getErrorCode(err: AppError) []const u8 {
    return switch (err) {
        error.InvalidInput => "INVALID_INPUT",
        error.RoadmapNotFound => "ROADMAP_NOT_FOUND",
        error.RoadmapExists => "ROADMAP_EXISTS",
        error.InvalidSqliteFile => "INVALID_SQLITE_FILE",
        error.TaskNotFound => "TASK_NOT_FOUND",
        error.SprintNotFound => "SPRINT_NOT_FOUND",
        error.InvalidStatus => "INVALID_STATUS",
        error.InvalidPriority => "INVALID_PRIORITY",
        error.DbError => "DB_ERROR",
        error.SystemError => "SYSTEM_ERROR",
        error.UnknownCommand => "UNKNOWN_COMMAND",
        error.UnknownSubcommand => "UNKNOWN_SUBCOMMAND",
    };
}
