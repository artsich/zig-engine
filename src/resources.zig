const rl = @import("raylib");

pub const Models = struct {
    const std = @import("std");
    const Allocator = std.mem.Allocator;

    const ModelsTable = std.AutoHashMap([*:0]const u8, rl.Model);

    loaded_models: ModelsTable,

    pub fn init(allocator: Allocator) @This() {
        return .{
            .loaded_models = ModelsTable.init(allocator)
        };
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

pub fn init_default_resources() void {
    colored_shader = rl.loadShader("res/shaders/colored.vs.glsl", "res/shaders/colored.fs.glsl");
    default_normal_map =  rl.loadTextureFromImage(
        rl.genImageColor(
            1, 1,
            rl.Color.fromNormalized(
                rl.Vector4.init(0.5, 0.5, 1, 1))));
    default_diffuse_map = rl.loadTextureFromImage(rl.genImageColor(1, 1, rl.Color.white));
    default_specular_map = rl.loadTextureFromImage(rl.genImageColor(1, 1, rl.Color.black));
}