const std = @import("std");
const Allocator = std.mem.Allocator;

pub const File = struct {
    path: []const u8,

    pub fn init(path: []const u8) File {
        return .{
            .path = path,
        };
    }

    pub fn exists(self: @This()) !bool {
        std.fs.cwd().access(self.path, .{ .mode = .read_write }) catch |err| switch (err) {
            error.FileNotFound => return false,
            error.PermissionDenied => return false,
            else => {
                return err;
            },
        };
        return true;
    }

    pub fn content(self: @This(), alloc: Allocator) []const u8 {
        return std.fs.cwd().readFileAlloc(alloc, self.path, std.math.maxInt(usize)) catch unreachable;
    }

    pub fn cContent(
        self: @This(),
        allocator: Allocator,
    ) ![:0]const u8 {
        const data = self.content(allocator);
        defer allocator.free(data);
        return allocator.dupeZ(u8, data);
    }

    pub fn get_file_timestamp(self: @This()) i128 {
        const cwd = std.fs.cwd();
        const file = cwd.openFile(self.path, .{}) catch unreachable;
        defer file.close();
        const stat = file.stat() catch unreachable;
        return stat.mtime;
    }
};
