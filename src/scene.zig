const rl = @import("raylib");
const math = @import("math.zig");
const id = @import("id.zig");
const resources = @import("resources.zig");

var SceneObjectsIds = id.Generator.init();

fn drawOBB(vertices: [8]rl.Vector3, color: rl.Color) void {
    rl.drawLine3D(vertices[0], vertices[1], color);
    rl.drawLine3D(vertices[1], vertices[2], color);
    rl.drawLine3D(vertices[2], vertices[3], color);
    rl.drawLine3D(vertices[3], vertices[0], color);

    rl.drawLine3D(vertices[4], vertices[5], color);
    rl.drawLine3D(vertices[5], vertices[6], color);
    rl.drawLine3D(vertices[6], vertices[7], color);
    rl.drawLine3D(vertices[7], vertices[4], color);

    rl.drawLine3D(vertices[0], vertices[4], color);
    rl.drawLine3D(vertices[1], vertices[5], color);
    rl.drawLine3D(vertices[2], vertices[6], color);
    rl.drawLine3D(vertices[3], vertices[7], color);
}

fn drawModel(model: rl.Model, transform: rl.Matrix, c: rl.Color) void {
    const model_transform = model.transform.multiply(transform);

    for (0..@intCast(model.meshCount)) |i| {
        const loc: usize = @intCast(@intFromEnum(rl.MATERIAL_MAP_DIFFUSE));
        const color = model.materials[@intCast(model.meshMaterial[i])].maps[loc].color;

        model.materials[@intCast(model.meshMaterial[i])].maps[loc].color = c;
        rl.drawMesh(model.meshes[i], model.materials[@intCast(model.meshMaterial[i])], model_transform);
        model.materials[@intCast(model.meshMaterial[i])].maps[loc].color = color;
    }
}

pub const ObjectData = union(enum) {
    Model: ModelData,
    Light: Light,
};

pub const ModelData = struct {
    model: rl.Model,
    bbox: rl.BoundingBox,

    pub fn useShader(self: @This(), shader: rl.Shader) void {
        const materials: usize = @intCast(self.model.materialCount);
        for (0..materials) |i| {
            self.model.materials[i].shader = shader;
        }
    }
};

pub const PointLight = struct {
    radius: f32,
};

pub const Light = union(enum) {
    Point: PointLight,
};

pub const SceneObject = struct {
    id: u32,

    color: rl.Color,
    data: ObjectData,

    position: rl.Vector3,
    scale: rl.Vector3,
    rotations: rl.Vector3,

    pub fn init(p: rl.Vector3, data: ObjectData, color: rl.Color) @This() {
        return .{
            .id = SceneObjectsIds.next(),
            .position = p,
            .scale = rl.Vector3.init(1.0, 1.0, 1.0),
            .color = color,
            .data = data,
            .rotations = rl.Vector3.zero(),
        };
    }

    pub fn render(self: SceneObject) void {
        switch (self.data) {
            .Model => {
                const modelData = self.data.Model;
                const mat = math.getTransformMatrix(self.position, self.scale, self.rotations);
                drawModel(modelData.model, mat, self.color);
            },
            .Light => {
                switch (self.data.Light) {
                    .Point => {
                        rl.drawCube(self.position, 1.0, 1.0, 1.0, self.color);
                    },
                }
            },
        }
    }

    pub fn renderForPicking(self: SceneObject) void {
        const color = rl.Color.fromInt(self.id);
        switch (self.data) {
            .Model => {
                const data = self.data.Model;
                data.useShader(resources.colored_shader);
                const mat = math.getTransformMatrix(self.position, self.scale, self.rotations);

                drawModel(data.model, mat, color);
            },
            .Light => {
                switch (self.data.Light) {
                    .Point => {
                        rl.drawCube(self.position, 1.0, 1.0, 1.0, color);
                    },
                }
            },
        }
    }

    pub fn renderBounds(self: SceneObject) void {
        switch (self.data) {
            .Model => {
                const data = self.data.Model;
                const bbox = data.bbox;

                const mat = math.getTransformMatrix(self.position, self.scale, self.rotations);

                var vertices: [8]rl.Vector3 = [_]rl.Vector3{
                    bbox.min,
                    rl.Vector3{ .x = bbox.max.x, .y = bbox.min.y, .z = bbox.min.z },
                    rl.Vector3{ .x = bbox.max.x, .y = bbox.min.y, .z = bbox.max.z },
                    rl.Vector3{ .x = bbox.min.x, .y = bbox.min.y, .z = bbox.max.z },
                    rl.Vector3{ .x = bbox.min.x, .y = bbox.max.y, .z = bbox.min.z },
                    rl.Vector3{ .x = bbox.max.x, .y = bbox.max.y, .z = bbox.min.z },
                    bbox.max,
                    rl.Vector3{ .x = bbox.min.x, .y = bbox.max.y, .z = bbox.max.z },
                };

                for (0..vertices.len) |i| {
                    vertices[i] = rl.Vector3.transform(vertices[i], mat);
                }

                drawOBB(vertices, rl.Color.dark_green);
            },
            .Light => {
                const data = self.data.Light.Point;
                var c = self.color;
                c.a = @round(0.11 * 255);
                rl.drawSphereWires(self.position, data.radius, 12, 12, c);
            },
        }
    }
};

pub fn createModel(p: rl.Vector3, file_name: [*:0]const u8, models: *resources.Models) SceneObject {
    const model = models.*.loadModel(file_name);
    const bbox = rl.getModelBoundingBox(model);

    for (0..@intCast(model.materialCount)) |i| {
        const map_albedo = &model.materials[i].maps[@intFromEnum(rl.MaterialMapIndex.material_map_albedo)];
        if (map_albedo.*.texture.id > 0) {
            rl.genTextureMipmaps(&map_albedo.*.texture);
            rl.setTextureFilter(map_albedo.*.texture, rl.TextureFilter.texture_filter_bilinear);
        }

        // const map_mettal = &model.materials[i].maps[@intFromEnum(rl.MaterialMapIndex.material_map_metalness)];
        // if (map_mettal.*.texture.id > 0) {
        //     rl.genTextureMipmaps(&map_mettal.*.texture);
        //     rl.setTextureFilter(map_mettal.*.texture, rl.TextureFilter.texture_filter_bilinear);
        // }

        const map_normal = &model.materials[i].maps[@intFromEnum(rl.MaterialMapIndex.material_map_normal)];
        if (map_normal.*.texture.id > 0) {
            rl.genTextureMipmaps(&map_normal.*.texture);
            rl.setTextureFilter(map_normal.*.texture, rl.TextureFilter.texture_filter_bilinear);
        } else {
            map_normal.texture = resources.default_normal_map;
        }
    }

    return SceneObject.init(p, ObjectData{ .Model = ModelData{
        .model = model,
        .bbox = bbox,
    } }, rl.Color.white);
}

pub fn createCube(p: rl.Vector3, size: rl.Vector3, c: rl.Color) SceneObject {
    // todo: not unloaded!
    const cube_model = rl.loadModel("res/models/bin/cube.glb");

    cube_model.materials[0].maps[@intFromEnum(rl.MaterialMapIndex.material_map_albedo)].texture = resources.default_diffuse_map;
    cube_model.materials[0].maps[@intFromEnum(rl.MaterialMapIndex.material_map_albedo)].color = c;
    cube_model.materials[0].maps[@intFromEnum(rl.MaterialMapIndex.material_map_normal)].texture = resources.default_normal_map;
    cube_model.materials[0].maps[@intFromEnum(rl.MaterialMapIndex.material_map_metalness)].texture = resources.default_specular_map;

    var obj = SceneObject.init(p, ObjectData{ .Model = ModelData{ .model = cube_model, .bbox = rl.getModelBoundingBox(cube_model) } }, c);

    obj.scale = size.scale(0.5);
    return obj;
}

pub fn createPlane(p: rl.Vector3, size: rl.Vector2, c: rl.Color) SceneObject {
    // todo: this model is not unloaded!!!
    const plane_model = rl.loadModel("res/models/bin/plane.glb");

    plane_model.materials[0].maps[@intFromEnum(rl.MaterialMapIndex.material_map_albedo)].texture = rl.loadTextureFromImage(rl.genImageColor(1, 1, c));

    var normal_map = rl.loadTexture("res/brick-normal.png");
    plane_model.materials[0].maps[@intFromEnum(rl.MaterialMapIndex.material_map_normal)].texture = normal_map;

    rl.genTextureMipmaps(&normal_map);
    rl.setTextureFilter(normal_map, rl.TextureFilter.texture_filter_bilinear);

    var obj = SceneObject.init(p, ObjectData{
        .Model = ModelData{ .model = plane_model, .bbox = rl.getModelBoundingBox(plane_model) },
    }, c);

    obj.scale = rl.Vector3.init(size.x, 0.001, size.y).scale(0.5);
    return obj;
}
