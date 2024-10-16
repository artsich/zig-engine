const io = @import("../io.zig");
const std = @import("std");
const Res = @import("resource.zig").Res;

var monitored_files: std.ArrayList(io.File) = undefined;
var last_modify_times: std.ArrayList(i128) = undefined;
var requires_update: std.ArrayList(io.File) = undefined;
var update_map: std.StringHashMap([]const u8) = undefined;

pub fn init(allocator: std.mem.Allocator) void {
    monitored_files = std.ArrayList(io.File).init(allocator);
    last_modify_times = std.ArrayList(i128).init(allocator);
    requires_update = std.ArrayList(io.File).init(allocator);
    update_map = std.StringHashMap([]const u8).init(allocator);
}

pub fn deinit() void {
    monitored_files.deinit();
    last_modify_times.deinit();
    requires_update.deinit();
    update_map.deinit();
}

fn addFile(source_file: io.File, update_target: io.File) void {
    monitored_files.append(source_file) catch unreachable;
    last_modify_times.append(source_file.get_file_timestamp()) catch unreachable;
    update_map.put(source_file.path, update_target.path) catch unreachable;
}

fn removeFile(file: io.File) void {
    var index: isize = -1;
    for (monitored_files.items, 0..) |mf, i| {
        if (std.mem.eql(u8, file.path, mf.path)) {
            index = @intCast(i);
            break;
        }
    }

    if (index > 0) {
        const indexu: usize = @intCast(index);
        _ = monitored_files.swapRemove(indexu);
        _ = last_modify_times.swapRemove(indexu);
        _ = update_map.remove(file.path);
    }
}

pub fn deatach(comptime T: anytype, res: *const Res(T)) void {
    removeFile(res.file);
    for (res.sub_files) |sub| {
        removeFile(sub);
    }
}

pub fn attach(comptime T: anytype, res: *const Res(T)) void {
    addFile(res.file, res.file);

    for (res.sub_files) |sub| {
        addFile(sub, res.file);
    }
}

pub fn markUpdated() void {
    requires_update.resize(0) catch unreachable;
}

pub fn getModified() []const io.File {
    return requires_update.items;
}

pub fn update() void {
    for (0..monitored_files.items.len) |i| {
        const last_modification_time = last_modify_times.items[i];
        const file = monitored_files.items[i];

        const file_mod_time = file.get_file_timestamp();
        if (last_modification_time < file_mod_time) {
            last_modify_times.items[i] = file_mod_time;

            const file_to_update = update_map.get(file.path);
            if (file_to_update) |fu| {
                requires_update.append(io.File.init(fu)) catch unreachable;
            }
        }
    }
}
