const rl = @import("raylib");
const std = @import("std");
const log = @import("log.zig");
const json = std.json;

const Allocator = std.mem.Allocator;

pub const Models = struct {
    const ModelsTable = std.AutoHashMap([*:0]const u8, rl.Model);

    loaded_models: ModelsTable,

    pub fn init(allocator: Allocator) @This() {
        return .{ .loaded_models = ModelsTable.init(allocator) };
    }

    pub fn loadModel(self: *@This(), file_name: [*:0]const u8) rl.Model {
        if (!self.loaded_models.contains(file_name)) {
            const model = rl.loadModel(file_name);
            self.loaded_models.put(file_name, model) catch unreachable;
        }

        return self.loaded_models.get(file_name).?;
    }

    pub fn unloadModels(self: *@This()) void {
        var it = self.loaded_models.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.unload();
        }
        self.loaded_models.deinit();
    }
};

pub var colored_shader: rl.Shader = undefined;
pub var default_normal_map: rl.Texture2D = undefined;
pub var default_diffuse_map: rl.Texture2D = undefined;
pub var default_specular_map: rl.Texture2D = undefined;

pub var sphere_mesh: rl.Mesh = undefined;

pub var default_material: rl.Material = undefined;
pub var default_shader: rl.Shader = undefined;

pub var instanced_shader: rl.Shader = undefined;

pub fn init_default_resources() void {
    colored_shader = rl.loadShader("res/shaders/colored.vs.glsl", "res/shaders/colored.fs.glsl");
    default_normal_map = rl.loadTextureFromImage(rl.genImageColor(1, 1, rl.Color.fromNormalized(rl.Vector4.init(0.5, 0.5, 1, 1))));
    default_diffuse_map = rl.loadTextureFromImage(rl.genImageColor(1, 1, rl.Color.white));
    default_specular_map = rl.loadTextureFromImage(rl.genImageColor(1, 1, rl.Color.black));

    sphere_mesh = rl.genMeshSphere(1, 32, 32);
    default_material = rl.loadMaterialDefault();
    default_shader = default_material.shader;

    instanced_shader = rl.loadShader("res/shaders/instanced_shader.vs.glsl", "res/shaders/instanced_shader.fs.glsl");
    instanced_shader.locs[@intFromEnum(rl.ShaderLocationIndex.shader_loc_matrix_model)] = rl.getShaderLocationAttrib(instanced_shader, "instanceTransform");
}

const Text = []const u8;
const SubFilePaths = []const []const u8;

fn load_text(res: *ResourceText, alloc: std.mem.Allocator) void {
    res.data = res.file.content(alloc);
}

fn unload_text(res: *ResourceText, allocator: std.mem.Allocator) void {
    allocator.free(res.*.data);
}

const File = struct {
    path: []const u8,
    timestamp: i128,

    pub fn init(path: []const u8) @This() {
        return .{ .path = path, .timestamp = get_file_timestamp(path) };
    }

    pub fn isChanged(self: @This()) bool {
        return self.timestamp != get_file_timestamp(self.path);
    }

    pub fn content(self: *@This(), alloc: Allocator) []const u8 {
        self.timestamp = get_file_timestamp(self.path);
        return std.fs.cwd().readFileAlloc(alloc, self.path, std.math.maxInt(usize)) catch unreachable;
    }

    pub fn exists(self: @This()) std.fs.Dir.AccessError!bool {
        std.fs.cwd().access(self.path, .{ .mode = .read_write }) catch |err| {
            return err;
        };

        return true;
    }

    pub fn cContent(
        self: *@This(),
        allocator: Allocator,
    ) []const u8 {
        const data = self.content(allocator);
        defer allocator.free(data);

        var buffer = allocator.alloc(u8, data.len + 1) catch unreachable;
        std.mem.copyForwards(u8, buffer[0..data.len], data);
        buffer[data.len] = 0;
        return buffer;
    }

    fn get_file_timestamp(file_path: []const u8) i128 {
        const cwd = std.fs.cwd();
        const file = cwd.openFile(file_path, .{}) catch unreachable;
        defer file.close();
        const stat = file.stat() catch unreachable;
        return stat.mtime;
    }
};

pub fn Resource(comptime T: type) type {
    return struct {
        const LoadFnType = *const fn (*@This(), Allocator) void;
        const UnloadFnType = *const fn (*@This(), Allocator) void;

        file: File,

        allocator: Allocator,
        loaded: bool = false,
        data: T,

        load_fn: LoadFnType,
        unload_fn: UnloadFnType,

        pub fn init(path: []const u8, allocator: Allocator, load_fn: LoadFnType, unload_fn: UnloadFnType) @This() {
            return .{
                .file = File.init(path),
                .data = undefined,
                .allocator = allocator,
                .load_fn = load_fn,
                .unload_fn = unload_fn,
            };
        }

        pub fn load(self: *@This()) void {
            self.load_fn(self, self.allocator);
            self.loaded = true;
        }

        pub fn unload(self: *@This()) void {
            std.debug.assert(self.loaded);
            self.unload_fn(self, self.allocator);
            self.loaded = false;
        }

        pub fn isChanged(self: *const @This()) bool {
            if (self.file.isChanged()) {
                return true;
            }

            return false;
        }

        pub fn getData(self: *const @This()) *const T {
            std.debug.assert(self.loaded);
            return &self.data;
        }
    };
}

pub const ResourceText = Resource(Text);

pub fn createText(path: []const u8, alloc: Allocator) ResourceText {
    return ResourceText.init(path, alloc, &load_text, &unload_text);
}

pub const ResourceShader = Resource(rl.Shader);

pub fn createShader(path: []const u8, alloc: Allocator) ResourceShader {
    return ResourceShader.init(path, alloc, &load_shader, &unload_shader);
}

fn toNullTerminated(allocator: Allocator, data: []const u8) []const u8 {
    var buffer = allocator.alloc(u8, data.len + 1) catch unreachable;
    std.mem.copyForwards(u8, buffer[0..data.len], data);
    buffer[data.len] = 0;
    return buffer;
}

fn loadShader(vertex: *File, fragment: *File, allocator: Allocator) rl.Shader {
    vertex.exists() catch |err| {
        log.err("%s", .{@errorName(err).ptr});
        return default_shader;
    };

    fragment.exists() catch |err| {
        log.err("%s", .{@errorName(err).ptr});
        return default_shader;
    };

    const vertexContent = vertex.cContent(allocator);
    defer allocator.free(vertex);

    const fragmentContent = vertex.cContent(allocator);
    defer allocator.free(fragment);

    return rl.loadShaderFromMemory(@ptrCast(vertexContent.ptr), @ptrCast(fragmentContent.ptr));
}

fn load_shader(res: *ResourceShader, allocator: Allocator) void {
    const ShaderMeta = struct {
        vertex: []const u8,
        fragment: []const u8,
    };

    const jsonContent = res.file.content(allocator);
    defer allocator.free(jsonContent);

    const parsed = json.parseFromSlice(ShaderMeta, allocator, jsonContent, .{ .allocate = .alloc_always }) catch unreachable;
    defer parsed.deinit();

    const meta = parsed.value;

    var vertexFile = File.init(meta.vertex);
    var fragmentFile = File.init(meta.fragment);

    const program = loadShader(&vertexFile, &fragmentFile);

    if (program.id == default_shader.id) {
        if (res.data.id == 0) {
            res.data = default_shader;
            log.err("Loading of %s is failed. Set default shader...", .{res.file.path.ptr});
        } else {
            log.err("Shader reload failed, see errors above...", .{});
        }
    } else if (res.data.id != program.id) {
        if (res.loaded) {
            res.unload();
        }
        res.data = program;
    }
}

fn unload_shader(res: *ResourceShader, _: std.mem.Allocator) void {
    rl.unloadShader(res.data);
}
