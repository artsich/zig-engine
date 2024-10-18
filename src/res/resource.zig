const io = @import("../io.zig");
const rl = @import("raylib");
const std = @import("std");
const log = @import("../log.zig");

const Allocator = std.mem.Allocator;

pub fn Loader(comptime T: type) type {
    return struct {
        const VTab = struct {
            load: *const fn (*anyopaque, *Res(T)) void,
            unload: *const fn (*anyopaque, *Res(T)) void,
        };

        ptr: *anyopaque,
        vtab: *const VTab,

        pub fn load(self: *@This(), res: *Res(T)) void {
            self.vtab.load(self.ptr, res);
        }

        pub fn unload(self: *@This(), res: *Res(T)) void {
            self.vtab.unload(self.ptr, res);
        }

        pub fn init(obj: anytype) @This() {
            const Ptr = @TypeOf(obj);
            const PtrInfo = @typeInfo(Ptr);
            std.debug.assert(PtrInfo == .Pointer);
            std.debug.assert(PtrInfo.Pointer.size == .One);
            std.debug.assert(@typeInfo(PtrInfo.Pointer.child) == .Struct);

            const impl = struct {
                fn load(ptr: *anyopaque, res: *Res(T)) void {
                    const self: Ptr = @ptrCast(@alignCast(ptr));
                    self.load(res);
                }

                fn unload(ptr: *anyopaque, res: *Res(T)) void {
                    const self: Ptr = @ptrCast(@alignCast(ptr));
                    self.unload(res);
                }
            };

            return .{ .ptr = obj, .vtab = &.{
                .load = impl.load,
                .unload = impl.unload,
            } };
        }
    };
}

const ResState = enum(u8) {
    Empty,
    Default, // todo: when default state, don't upload it
    Loaded,
};

pub fn Res(comptime T: type) type {
    return struct {
        const Self = @This();

        file: io.File,
        loader: *Loader(T),
        sub_files: []const io.File,
        state: ResState,
        data: *T,

        pub fn init(path: []const u8, loader: *Loader(T)) Self {
            return .{
                .file = io.File.init(path),
                .loader = loader,
                .data = undefined,
                .sub_files = &.{},
                .state = ResState.Empty,
            };
        }

        pub fn reload(self: *Self) void {
            self.loader.load(self);
            self.state = ResState.Loaded;
        }

        pub fn unload(self: *Self) void {
            std.debug.assert(self.state == ResState.Loaded);
            self.loader.unload(self);
            self.state = ResState.Empty;
        }
    };
}

// todo: return default texture if first loading failed...
pub const ShaderLoader = struct {
    const ShaderDescription = struct {
        vertex: []const u8,
        fragment: []const u8,
    };

    allocator: Allocator,

    pub fn init(allocator: Allocator) @This() {
        return .{
            .allocator = allocator,
        };
    }

    fn loadShaderDesc(file: io.File, allocator: Allocator) !std.json.Parsed(ShaderDescription) {
        const jsonContent = file.content(allocator);
        defer allocator.free(jsonContent);

        const parsed = std.json.parseFromSlice(ShaderDescription, allocator, jsonContent, .{ .allocate = .alloc_always });
        return parsed;
    }

    pub fn loadShader(vs: [:0]const u8, fs: [:0]const u8) error{CompilatinFailed}!rl.Shader {
        const shader = rl.loadShader(@ptrCast(vs.ptr), @ptrCast(fs.ptr));

        if (shader.id == 0) {
            return error.CompilatinFailed;
        }

        return shader;
    }

    pub fn load(self: *@This(), res: *Res(rl.Shader)) void {
        const shader_desc = loadShaderDesc(res.file, self.allocator) catch |err| {
            std.debug.print("WARN: RES: SHADER: Description file loading error - {s}\n", .{@errorName(err)});
            if (res.state == ResState.Empty) {
                // set default shader...
                unreachable;
            }
            return;
        };

        defer shader_desc.deinit();

        const vertex_path: [:0]u8 = self.allocator.dupeZ(u8, shader_desc.value.vertex) catch unreachable;
        const fragment_path: [:0]u8 = self.allocator.dupeZ(u8, shader_desc.value.fragment) catch unreachable;
        const loaded_shader = loadShader(vertex_path, fragment_path) catch {
            if (res.state == ResState.Empty) {
                unreachable; // set default shader...
            }

            self.allocator.free(vertex_path);
            self.allocator.free(fragment_path);
            return;
        };

        const shader = self.allocator.create(rl.Shader) catch unreachable;
        shader.* = loaded_shader;

        if (res.state == ResState.Loaded) {
            res.unload();
        }

        res.data = shader;

        const deps = self.allocator.alloc(io.File, 2) catch unreachable;
        deps[0] = io.File.init(vertex_path);
        deps[1] = io.File.init(fragment_path);
        res.sub_files = deps;
    }

    pub fn unload(self: *@This(), res: *Res(rl.Shader)) void {
        rl.unloadShader(res.data.*);
        if (res.sub_files.len > 0) {
            // allocator does not see null terminated value if not cast
            self.allocator.free(@as([:0]const u8, @ptrCast(res.sub_files[0].path)));
            self.allocator.free(@as([:0]const u8, @ptrCast(res.sub_files[1].path)));
            self.allocator.free(res.sub_files);
        }
        self.allocator.destroy(res.data);
    }
};

pub const Text = struct {
    str: []const u8,
};

pub const TextLoader = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) @This() {
        return .{
            .allocator = allocator,
        };
    }

    pub fn load(self: *@This(), res: *Res(Text)) void {
        if (res.state == ResState.Loaded) {
            res.unload();
        }

        const text = self.allocator.create(Text) catch unreachable;
        text.* = .{ .str = res.file.cContent(self.allocator) catch unreachable };
        res.data = text;
    }

    pub fn unload(self: *@This(), res: *Res(Text)) void {
        self.allocator.free(@as([:0]const u8, @ptrCast(res.data.str)));
        self.allocator.destroy(res.data);
    }
};
