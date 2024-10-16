const rl = @import("raylib");
const std = @import("std");

const log = @import("../log.zig");
const json = std.json;
const dlog = std.debug.print;
const io = @import("../io.zig");
const fw = @import("file-watcher.zig");

const Allocator = std.mem.Allocator;

const r = @import("resource.zig");
const Res = r.Res;

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

var shader_loadert_impl: r.ShaderLoader = undefined;
var shader_loader = r.Loader(rl.Shader).init(&shader_loadert_impl);

var text_loadert_impl: r.TextLoader = undefined;
var text_loader = r.Loader(r.Text).init(&text_loadert_impl);

fn init_default_resources() void {
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

var res_map: std.StringHashMap(*anyopaque) = undefined;

pub fn init(allocator: Allocator) void {
    init_default_resources();
    fw.init(allocator);

    shader_loadert_impl = r.ShaderLoader.init(allocator);
    text_loadert_impl = r.TextLoader.init(allocator);
    res_map = std.StringHashMap(*anyopaque).init(allocator);
}

pub fn deinit(_: Allocator) void {
    // todo: deinit all resources... in res_map
    res_map.deinit();
    fw.deinit();
}

// run it once per secend
pub fn tryHotReload() void {
    fw.update();

    const modified = fw.getModified();
    if (modified.len > 0) {
        for (modified) |mf| {
            const result = res_map.get(mf.path);
            if (result) |any| {
                const res: *Res(anyopaque) = @ptrCast(@alignCast(any));

                fw.deatach(anyopaque, res);
                res.reload();
                fw.attach(anyopaque, res);

                log.info("[RES] %s - modified...", .{mf.path.ptr});
            }
        }
        fw.markUpdated();
    }
}

pub fn update() void {
    tryHotReload();
}

fn getLoader(comptime T: type) *r.Loader(T) {
    if (@typeName(T).ptr == @typeName(rl.Shader).ptr) {
        return &shader_loader;
    }
    if (@typeName(T).ptr == @typeName(r.Text).ptr) {
        return &text_loader;
    }
    @compileError("Unsupported resource type");
}

/// For now user must manualy handle allocated resource...
pub fn load(comptime T: type, path: []const u8, alloc: Allocator) *Res(T) {
    const loader = getLoader(T);

    const res = alloc.create(Res(T)) catch unreachable;
    res.* = Res(T).init(path, loader);
    res_map.put(path, res) catch unreachable;

    res.*.reload();
    fw.attach(T, res);

    log.info("[RES] `%s` loaded ", .{path.ptr});
    return res;
}

fn get(comptime T: anytype, path: []const u8) *const Res(T) {
    const entry = res_map.get(path);
    if (entry) |cached_res| {
        return @ptrCast(@alignCast(cached_res));
    } else unreachable;
}

pub fn unload(comptime T: anytype, res: *Res(T), alloc: Allocator) void {
    const removed = res_map.remove(res.file.path);
    std.debug.assert(removed);

    fw.deatach(T, res);
    res.unload();
    alloc.destroy(res);
}
