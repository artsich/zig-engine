const rl = @import("raylib");
const std = @import("std");
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

pub var instanced_shader: rl.Shader = undefined;

pub fn init_default_resources() void {
    colored_shader = rl.loadShader("res/shaders/colored.vs.glsl", "res/shaders/colored.fs.glsl");
    default_normal_map = rl.loadTextureFromImage(rl.genImageColor(1, 1, rl.Color.fromNormalized(rl.Vector4.init(0.5, 0.5, 1, 1))));
    default_diffuse_map = rl.loadTextureFromImage(rl.genImageColor(1, 1, rl.Color.white));
    default_specular_map = rl.loadTextureFromImage(rl.genImageColor(1, 1, rl.Color.black));

    sphere_mesh = rl.genMeshSphere(1, 32, 32);
    default_material = rl.loadMaterialDefault();

    instanced_shader = rl.loadShader("res/shaders/instanced_shader.vs.glsl", "res/shaders/instanced_shader.fs.glsl");
    instanced_shader.locs[@intFromEnum(rl.ShaderLocationIndex.shader_loc_matrix_model)] = rl.getShaderLocationAttrib(instanced_shader, "instanceTransform");
}

const Text = []const u8;

fn load_file(path: []const u8, allocator: std.mem.Allocator) Text {
    const content = std.fs.cwd()
        .readFileAlloc(allocator, path, std.math.maxInt(usize)) catch unreachable;
    return content;
}

fn unload_file(text: *Text, allocator: std.mem.Allocator) void {
    allocator.free(text.*);
}

pub fn Resource(comptime T: type, load_fn: fn ([]const u8, Allocator) T, unload_fn: fn (*T, Allocator) void) type {
    return struct {
        path: []const u8,
        timestamp: i128 = 0,
        allocator: Allocator,
        loaded: bool = false,
        data: T,

        pub fn init(
            path: []const u8,
            allocator: Allocator,
        ) @This() {
            return .{
                .path = path,
                .timestamp = @This().get_file_timestamp(path),
                .data = undefined,
                .allocator = allocator,
            };
        }

        pub fn load(self: *@This()) void {
            if (self.loaded) {
                self.unload();
            }
            self.data = load_fn(self.path, self.allocator);
            self.loaded = true;
            self.timestamp = get_file_timestamp(self.path);
        }

        pub fn unload(self: *@This()) void {
            std.debug.assert(self.loaded);
            unload_fn(&self.data, self.allocator);
            self.loaded = false;
        }

        pub fn isChanged(self: *const @This()) bool {
            const new_timestamp = get_file_timestamp(self.path);
            return self.timestamp != new_timestamp;
        }

        pub fn getData(self: *const @This()) *const T {
            std.debug.assert(self.loaded);
            return &self.data;
        }

        // todo: so, not effective to open file each time,
        // consider any file watcher...
        fn get_file_timestamp(file_path: []const u8) i128 {
            const cwd = std.fs.cwd();
            const file = cwd.openFile(file_path, .{}) catch unreachable;
            defer file.close();
            const stat = file.stat() catch unreachable;
            return stat.mtime;
        }
    };
}

pub const ResourceText = Resource(Text, load_file, unload_file);
