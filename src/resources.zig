pub const Models = struct {
    const std = @import("std");
    const rl = @import("raylib");
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
