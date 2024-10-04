export var AmdPowerXpressRequestHighPerformance: u32 = 0x1;
export var NvOptimusEnablement: u32 = 0x1;

const std = @import("std");
const rl = @import("raylib");
const rgui = @import("raygui");
const gl = rl.gl;
const gizmo = @import("gizmo.zig");

const Vector3 = rl.Vector3;
const Vector2 = rl.Vector2;
const Camera3d = rl.Camera3D;
const Camera2d = rl.Camera2D;
const Color = rl.Color;
const KeyboardKey = rl.KeyboardKey;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

var ObjectsIdCounter: u32 = 0;
pub fn genId() u32 {
    const id = ObjectsIdCounter + 1;
    ObjectsIdCounter += 1;
    return id;
}

const AppMode = enum {
    Editor,
    Game,
};

const PointLight = struct {
    // radius info
};

const DirLight = struct {
    // will be empte, as scene object will have direction component,
    dir: Vector3,
};

const Ligth = union(enum) {
    Point: PointLight,
    Dir: DirLight,
};

const ModelData = struct {
    model: rl.Model,
    bbox: rl.BoundingBox,
//    animations: rl.ModelAnimation,

    pub fn useShader(self: @This(), shader: rl.Shader) void {
        const materials: usize = @intCast(self.model.materialCount);
        for(0..materials) |i| {
            self.model.materials[i].shader = shader;
        }
    }
};

const ObjectData = union(enum) {
    Model: ModelData,
};

const ModelsTable = std.AutoHashMap([*:0]const u8, rl.Model);
var loaded_models =  ModelsTable.init(allocator);

pub fn loadModel(file_name: [*:0]const u8) rl.Model {
    if (!loaded_models.contains(file_name)) {
        const model = rl.loadModel(file_name);
        loaded_models.put(file_name, model) catch unreachable;
    }

    const entry = loaded_models.get(file_name);
    return entry.?;
}

pub fn unloadModels() void {
    var it = loaded_models.iterator();
    while (it.next()) |entry| {
        entry.value_ptr.*.unload();
    }

    loaded_models.deinit();
}

fn drawModel(model: rl.Model, transform: rl.Matrix, c: Color) void {
    const model_transform = model.transform.multiply(transform);

    for(0..@intCast(model.meshCount)) |i| {

        const loc: usize = @intCast(@intFromEnum(rl.MATERIAL_MAP_DIFFUSE));
        const color = model.materials[@intCast(model.meshMaterial[i])].maps[loc].color;

        model.materials[@intCast(model.meshMaterial[i])].maps[loc].color = c;
        rl.drawMesh(model.meshes[i], model.materials[@intCast(model.meshMaterial[i])], model_transform);
        model.materials[@intCast(model.meshMaterial[i])].maps[loc].color = color;
    }
}

pub fn generateTransformMatrix(position: rl.Vector3, scale: rl.Vector3, rotations: rl.Vector3) rl.Matrix {
    const translation_matrix = rl.Matrix.translate(position.x, position.y, position.z);

    const scale_matrix = rl.Matrix.scale(scale.x, scale.y, scale.z);

    const quaternionX = rl.Quaternion.fromAxisAngle(rl.Vector3{ .x = 1, .y = 0, .z = 0 }, rotations.x);
    const quaternionY = rl.Quaternion.fromAxisAngle(rl.Vector3{ .x = 0, .y = 1, .z = 0 }, rotations.y);
    const quaternionZ = rl.Quaternion.fromAxisAngle(rl.Vector3{ .x = 0, .y = 0, .z = 1 }, rotations.z);

    const combined_quaternion = rl.math.quaternionMultiply(quaternionX, rl.math.quaternionMultiply(quaternionY, quaternionZ));
    const rotation_matrix = rl.Quaternion.toMatrix(combined_quaternion);

    return scale_matrix.multiply(rotation_matrix).multiply(translation_matrix);
}

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

const SceneObject = struct {
    id: u32,

    color: Color,
    data: ObjectData,

    position: Vector3,
    scale: Vector3,
    rotations: Vector3,

    pub fn init(p: Vector3, data: ObjectData, color: Color) @This() {
        return .{
            .id = genId(),
            .position = p,
            .scale = Vector3.init(1.0, 1.0, 1.0),
            .color = color,
            .data = data,
            .rotations = Vector3.zero(),
        };
    }

    fn render(self: SceneObject) void {
        switch (self.data) {
            .Model => {
                const modelData = self.data.Model;
                const mat = generateTransformMatrix(self.position, self.scale, self.rotations);
                drawModel(modelData.model, mat, self.color);
            }
        }
    }

    fn renderColored(self: SceneObject, color: Color) void {
        switch (self.data) {
            .Model => {
                const data = self.data.Model;
                data.useShader(state.colored_shader);

                const mat = generateTransformMatrix(self.position, self.scale, self.rotations);
                drawModel(data.model, mat, color);
            }
        }
    }

    fn renderBounds(self: SceneObject) void {
        switch (self.data) {
            .Model => {
                const data = self.data.Model;
                const bbox = data.bbox;

                const mat = generateTransformMatrix(self.position, self.scale, self.rotations);

                var vertices: [8]rl.Vector3 = [_]rl.Vector3{
                    bbox.min,
                    rl.Vector3 { .x = bbox.max.x, .y = bbox.min.y, .z = bbox.min.z },
                    rl.Vector3 { .x = bbox.max.x, .y = bbox.min.y, .z = bbox.max.z },
                    rl.Vector3 { .x = bbox.min.x, .y = bbox.min.y, .z = bbox.max.z },
                    rl.Vector3 { .x = bbox.min.x, .y = bbox.max.y, .z = bbox.min.z },
                    rl.Vector3 { .x = bbox.max.x, .y = bbox.max.y, .z = bbox.min.z },
                    bbox.max,
                    rl.Vector3{ .x = bbox.min.x, .y = bbox.max.y, .z = bbox.max.z },
                };

                for (0..vertices.len) |i| {
                    vertices[i] = rl.Vector3.transform(vertices[i], mat);
                }

                drawOBB(vertices, Color.dark_green);
            }
        }
    }
};

const textFormat = rl.textFormat;

fn infoLog(text: [*:0]const u8, args: anytype) void {
    rl.traceLog(rl.TraceLogLevel.log_info, rl.textFormat(text, args));
}

fn errorLog(text: [*:0]const u8, args: anytype) void {
    rl.traceLog(rl.TraceLogLevel.log_error, rl.textFormat(text, args));
}

fn createModel(p: Vector3, file_name: [*:0]const u8) SceneObject {
    const model = loadModel(file_name);
    const bbox = rl.getModelBoundingBox(model);

    for(0..@intCast(model.materialCount)) |i| {
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
            map_normal.texture = state.default_normal_map;
        }
    }

    return SceneObject.init(
        p,
        ObjectData {
            .Model = ModelData {
                .model = model,
                .bbox = bbox,
            }
        },
        Color.white
    );
}

fn createCube(p: Vector3, size: Vector3, c: Color) SceneObject {
    // todo: not unloaded!
    const cube_model = rl.loadModel("res/models/bin/cube.glb");

    cube_model.materials[0].maps[@intFromEnum(rl.MaterialMapIndex.material_map_albedo)].texture = state.default_diffuse_map;
    cube_model.materials[0].maps[@intFromEnum(rl.MaterialMapIndex.material_map_albedo)].color = c;

    cube_model.materials[0].maps[@intFromEnum(rl.MaterialMapIndex.material_map_normal)].texture = state.default_normal_map;

    cube_model.materials[0].maps[@intFromEnum(rl.MaterialMapIndex.material_map_metalness)].texture = state.default_specular_map;

    var obj = SceneObject.init(
        p,
        ObjectData {
            .Model = ModelData {
                .model = cube_model,
                .bbox = rl.getModelBoundingBox(cube_model)
            }
        },
        c);

    obj.scale = size.scale(0.5);
    return obj;
}

fn createPlane(p: Vector3, size: Vector2, c: Color) SceneObject {
    // todo: this model is not unloaded!!!
    const plane_model = rl.loadModel("res/models/bin/plane.glb");

    plane_model.materials[0].maps[@intFromEnum(rl.MaterialMapIndex.material_map_albedo)].texture = rl.loadTextureFromImage(
        rl.genImageColor(1, 1, c));

    var normal_map = rl.loadTexture("res/brick-normal.png");
    plane_model.materials[0].maps[@intFromEnum(rl.MaterialMapIndex.material_map_normal)].texture = normal_map;

    rl.genTextureMipmaps(&normal_map);
    rl.setTextureFilter(normal_map, rl.TextureFilter.texture_filter_bilinear);

    var obj = SceneObject.init(
        p,
        ObjectData {
            .Model = ModelData {
                .model = plane_model,
                .bbox = rl.getModelBoundingBox(plane_model)
            },
        },
        c);

    obj.scale = Vector3.init(size.x, 0.001, size.y).scale(0.5);
    return obj;
}

const GL_READ_FRAMEBUFFER = 0x8CA8;
const GL_DRAW_FRAMEBUFFER = 0x8CA9;
const GL_DEPTH_BUFFER_BIT = 0x00000100;

const GBuffer = struct {
    framebuffer: u32,
    albedoSpec: u32,
    normals: u32,
    positions: u32,
    depth: u32,

    pub fn init(width: i32, height: i32) @This() {
        const framebuffer = gl.rlLoadFramebuffer();
        if (framebuffer == 0)
        {
            rl.traceLog(rl.TraceLogLevel.log_error ,"Failed to create gbuffer.");
            unreachable;
        }

        gl.rlEnableFramebuffer(framebuffer);
        defer gl.rlDisableFramebuffer();

        const positionsTex = gl.rlLoadTexture(null, width, height, @intFromEnum(gl.rlPixelFormat.rl_pixelformat_uncompressed_r32g32b32), 1);
        const normalTex = gl.rlLoadTexture(null, width, height, @intFromEnum(gl.rlPixelFormat.rl_pixelformat_uncompressed_r32g32b32), 1);
        const albedoSpecTex = gl.rlLoadTexture(null, width, height, @intFromEnum(gl.rlPixelFormat.rl_pixelformat_uncompressed_r8g8b8a8), 1);

        gl.rlActiveDrawBuffers(3);

        gl.rlFramebufferAttach(framebuffer, positionsTex, @intFromEnum(gl.rlFramebufferAttachType.rl_attachment_color_channel0), @intFromEnum(gl.rlFramebufferAttachTextureType.rl_attachment_texture2d), 0);
        gl.rlFramebufferAttach(framebuffer, normalTex, @intFromEnum(gl.rlFramebufferAttachType.rl_attachment_color_channel1), @intFromEnum(gl.rlFramebufferAttachTextureType.rl_attachment_texture2d), 0);
        gl.rlFramebufferAttach(framebuffer, albedoSpecTex, @intFromEnum(gl.rlFramebufferAttachType.rl_attachment_color_channel2), @intFromEnum(gl.rlFramebufferAttachTextureType.rl_attachment_texture2d), 0);

        const depthTex = gl.rlLoadTextureDepth(width, height, true);
        gl.rlFramebufferAttach(framebuffer, depthTex, @intFromEnum(gl.rlFramebufferAttachType.rl_attachment_depth), @intFromEnum(gl.rlFramebufferAttachTextureType.rl_attachment_renderbuffer), 0);

        if (gl.rlFramebufferComplete(framebuffer)) {
            rl.traceLog(rl.TraceLogLevel.log_info, rl.textFormat("FBO: [ID %i] Framebuffer object created successfully", .{ framebuffer }));
        }
        else unreachable;

        gl.rlDisableFramebuffer();

        return GBuffer {
            .framebuffer = framebuffer,
            .albedoSpec = albedoSpecTex,
            .normals = normalTex,
            .positions = positionsTex,
            .depth = depthTex,
        };
    }

    pub fn copyDepthTo(self: @This(), target: u32) void {
        gl.rlBindFramebuffer(GL_READ_FRAMEBUFFER, self.framebuffer);
        gl.rlBindFramebuffer(GL_DRAW_FRAMEBUFFER, target);
        gl.rlBlitFramebuffer(0, 0, window_width, window_height, 0, 0, window_width, window_height, GL_DEPTH_BUFFER_BIT);
        gl.rlDisableFramebuffer();
    }

    pub fn begin(self: @This()) void {
        gl.rlEnableFramebuffer(self.framebuffer);
    }

    pub fn clear(_: @This()) void {
        gl.rlClearScreenBuffers();
    }

    pub fn end(_: @This()) void {
        gl.rlDisableFramebuffer();
    }
};

fn getEnumCount(comptime T: type) usize {
    return @typeInfo(T).Enum.fields.len;
}

const GBufferTexture = enum(u32) {
    Shading = 0,
    Position = 1,
    Normals = 2,
    Albedo = 3,

    pub fn getName(self: GBufferTexture) [*:0]const u8 {
        return switch (self) {
            .Position => "Position",
            .Normals => "Normals",
            .Albedo => "Albedo",
            .Shading => "Shading",
        };
    }
};

const State = struct {
    now: f32 = 0,
    delta: f32 = 0,
    mode: AppMode,
    main_camera: Camera3d,
    camera_mode: rl.CameraMode,
    mouse_delta: Vector2,

    objects: std.ArrayList(SceneObject),
    touch_id: u32 = 0,
    touched: bool = false,

    dir: Vector2,
    gamepad: i32 = -1,

    gizmo: gizmo.Gizmo,

    render_target: rl.RenderTexture2D,
    picking_texture: rl.RenderTexture2D,

    gbuffer: GBuffer,
    gbuffer_shader: rl.Shader,
    gbuffer_texture_type: GBufferTexture = GBufferTexture.Shading,

    default_normal_map: rl.Texture2D,
    default_diffuse_map: rl.Texture2D,
    default_specular_map: rl.Texture2D,

    deferred_shading_shader: rl.Shader,
    colored_shader: rl.Shader,

    pub fn getRayFromCamera(self: *State) rl.Ray {
        const screenWidth: f32 = @floatFromInt(rl.getScreenWidth());
        const screenHeight: f32 = @floatFromInt(rl.getScreenHeight());
        return rl.getScreenToWorldRay(.{ .x = screenWidth / 2.0, .y = screenHeight / 2.0 }, self.main_camera);
    }
};

var state: State = undefined;

const window_width = 1920;
const window_height = (9*window_width)/16;

fn switchAppState() void {
    state.mode = switch (state.mode) {
        AppMode.Editor => AppMode.Game,
        AppMode.Game => AppMode.Editor,
    };
}

// todo: Optimize search
fn getSceneObjectById(id: u32) *SceneObject {
    for (state.objects.items) |*obj| {
        if (obj.id == id) {
            return obj;
        }
    }

    unreachable;
}

fn updateEditor() void {
    const editor_gizmo = &state.gizmo;

    if (!editor_gizmo.dragging and !editor_gizmo.rotating) {
        state.main_camera.update(rl.CameraMode.camera_free);
    }

    if (state.touched) {
        editor_gizmo.update(state.main_camera);
        const obj = getSceneObjectById(state.touch_id);
        obj.*.position = editor_gizmo.position;
        obj.*.rotations = editor_gizmo.rotations;
    }

    // todo: Gizmo redesign ideas
    // 1) undo\redo available. (so, command pattern)
    // 2) i think need to capture scene object inside gizmo when touch object.
    //      when user touch object it should be attached to the gizmo and deattached when untouch.
    //      No it is better to call only one method Update(sceneObject) each frame.
    //      Will be more stateless.
    if (!editor_gizmo.dragging and rl.isMouseButtonPressed(rl.MouseButton.mouse_button_left)) {
        const screen_width: f32 = @floatFromInt(rl.getScreenWidth());
        const screen_height: f32 = @floatFromInt(rl.getScreenHeight());
        const mouse_pos = Vector2.init(screen_width / 2.0, screen_height / 2.0);

        const image = rl.loadImageFromTexture(state.picking_texture.texture);
        defer rl.unloadImage(image);

        const picked_color = rl.getImageColor(image, @intFromFloat(mouse_pos.x), @intFromFloat(mouse_pos.y));
        const object_id = picked_color.toInt();

        rl.traceLog(rl.TraceLogLevel.log_info, rl.textFormat("Id picked: %d \n", .{ object_id }));

        if (object_id > 0) {
            state.touched = true;
            state.touch_id = @intCast(object_id);

            const obj = getSceneObjectById(state.touch_id);
            editor_gizmo.position = obj.*.position;
            editor_gizmo.rotations = obj.*.rotations;
        } else {
            state.touched = false;
            state.touch_id = 0;
        }
    }

    if (rl.isKeyDown(rl.KeyboardKey.key_right_control)) {
        if (rl.isKeyPressed(rl.KeyboardKey.key_b)) {
            state.gbuffer_texture_type = @enumFromInt((@intFromEnum(state.gbuffer_texture_type) + 1) % getEnumCount(GBufferTexture));
            const name = state.gbuffer_texture_type.getName();
            infoLog("Display gbuffer - %s", .{ name });
        }
    }
}

fn updateGame() void {
    state.gamepad = 0;
    state.main_camera.update(rl.CameraMode.camera_third_person);

    if (!rl.isGamepadAvailable(state.gamepad)) {
        state.gamepad = -1;
    }

    if (state.gamepad >= 0) {
        state.dir.x = rl.getGamepadAxisMovement(state.gamepad, @intFromEnum(rl.GamepadAxis.gamepad_axis_left_x));
        state.dir.y = rl.getGamepadAxisMovement(state.gamepad, @intFromEnum(rl.GamepadAxis.gamepad_axis_left_y));
    } else {
        state.dir = Vector2.init(0.0, 0.0);
    }

    // const acceleration: f32 = 10.0;
    // const velocity = Vector2.scale(state.dir, acceleration * state.delta);
    //
    // const pos = state.objects.items[0].position;
    // state.objects.items[0].position = Vector3.add(pos, Vector3.init(velocity.x, 0.0, velocity.y));
}

fn update() !void {
    state.delta = rl.getFrameTime();
    state.now += state.delta;

    if (rl.isKeyPressed(KeyboardKey.key_f1)) {
        switchAppState();
    }

    if (rl.isKeyPressed(KeyboardKey.key_f10)) {
        rl.toggleBorderlessWindowed();
    }

    state.mouse_delta = rl.getMouseDelta().normalize();

    if (state.mode == AppMode.Editor) {
        updateEditor();
    } else if (state.mode == AppMode.Game) {
        updateGame();
    }
}

fn drawCursor() void {
    const screenWidth = rl.getScreenWidth();
    const screenHeight = rl.getScreenHeight();
    const x = @divTrunc(screenWidth, 2);
    const y = @divTrunc(screenHeight, 2);
    rl.drawRectangle(x, y, 10, 10, Color.dark_green);
}

fn loadPickingTexture(w: i32, h: i32) rl.RenderTexture2D {
    var target = rl.RenderTexture2D.init(w, h);
    if (target.id > 0) {
        gl.rlEnableFramebuffer(target.id);

        target.texture = rl.loadTextureFromImage(rl.genImageColor(w, h, Color.blank));
        rl.setTextureFilter(target.texture, rl.TextureFilter.texture_filter_point);
        rl.setTextureWrap(target.texture, rl.TextureWrap.texture_wrap_clamp);

        gl.rlFramebufferAttach(target.id, target.texture.id, @intFromEnum(gl.rlFramebufferAttachType.rl_attachment_color_channel0), @intFromEnum(gl.rlFramebufferAttachTextureType.rl_attachment_texture2d), 0);
        if (gl.rlFramebufferComplete(target.id)) {
            rl.traceLog(rl.TraceLogLevel.log_info, rl.textFormat("FBO: [ID %i] Framebuffer object created successfully", .{ target.id }));
        }
        else {
            unreachable;
        }
        gl.rlDisableFramebuffer();
    } else  {
        rl.traceLog(rl.TraceLogLevel.log_warning, "FBO: Framebuffer object can not be created");
        unreachable;
    }

    return target;
}

fn loadRenderTextureDepthTex(width: i32, height: i32) rl.RenderTexture2D {
    var target: rl.RenderTexture2D = rl.RenderTexture2D.init(width, height);

    if (target.id > 0) {
        gl.rlEnableFramebuffer(target.id);

        target.texture.id = gl.rlLoadTexture(null, width, height,  @intFromEnum(gl.rlPixelFormat.rl_pixelformat_uncompressed_r8g8b8a8), 1);
        target.depth.id = gl.rlLoadTextureDepth(width, height, false);

        gl.rlFramebufferAttach(target.id, target.texture.id, @intFromEnum(gl.rlFramebufferAttachType.rl_attachment_color_channel0), @intFromEnum(gl.rlFramebufferAttachTextureType.rl_attachment_texture2d), 0);
        gl.rlFramebufferAttach(target.id, target.depth.id, @intFromEnum(gl.rlFramebufferAttachType.rl_attachment_depth), @intFromEnum(gl.rlFramebufferAttachType.rl_attachment_color_channel0), 0);

        if (gl.rlFramebufferComplete(target.id)) {
            rl.traceLog(rl.TraceLogLevel.log_info, rl.textFormat("FBO: [ID %i] Framebuffer object created successfully", .{ target.id }));
        }
        else {
            unreachable;
        }

        gl.rlDisableFramebuffer();
    } else  {
        rl.traceLog(rl.TraceLogLevel.log_warning, "FBO: Framebuffer object can not be created");
    }

    return target;
}

fn unloadRenderTextureDepthTex(target: rl.RenderTexture2D) void {
    if (target.id > 0) {
        target.texture.unload();
        target.depth.unload();
        target.unload();
    }
}

fn renderPickingTexture() void {
    state.picking_texture.begin();
    {
        defer state.picking_texture.end();
        rl.clearBackground(Color.white);

        gl.rlDisableColorBlend();
        defer gl.rlEnableColorBlend();

        rl.beginMode3D(state.main_camera);
        {
            for(state.objects.items) |obj| {
                obj.renderColored(Color.fromInt(@truncate(obj.id)));
            }
        }
        rl.endMode3D();
    }
}

fn renderDeferred() void {
    state.gbuffer.begin();
    {
        defer state.gbuffer.end();
        gl.rlClearColor(0, 0, 0, 0);
        state.gbuffer.clear();

        gl.rlDisableColorBlend();
        defer gl.rlEnableColorBlend();

        rl.beginShaderMode(state.gbuffer_shader);
        defer rl.endShaderMode();

        rl.beginMode3D(state.main_camera);
        {
            defer rl.endMode3D();

            for (state.objects.items) |obj| {
                switch (obj.data) {
                    .Model => {
                        obj.data.Model.useShader(state.gbuffer_shader);
                    },
                }
                obj.render();
            }
        }
    }

    if (state.gbuffer_texture_type == GBufferTexture.Shading) {
        const cameraPos: [3]f32 = .{ state.main_camera.position.x, state.main_camera.position.y, state.main_camera.position.z };
        const camPosIndexLoc: usize = @intCast(@intFromEnum(rl.ShaderLocationIndex.shader_loc_vector_view));
        rl.setShaderValue(state.deferred_shading_shader, state.deferred_shading_shader.locs[camPosIndexLoc], &cameraPos, rl.ShaderUniformDataType.shader_uniform_vec3);

        const light = state.objects.items[0].position;
        const lightPos: [3]f32 = .{ light.x, light.y, light.z };
        const lightPosLoc = rl.getShaderLocation(state.deferred_shading_shader, "lightPos");
        rl.setShaderValue(state.deferred_shading_shader, lightPosLoc, &lightPos, rl.ShaderUniformDataType.shader_uniform_vec3);

        gl.rlDisableColorBlend();
        gl.rlEnableShader(state.deferred_shading_shader.id);

        // zero slot is reserved by raylib!
        gl.rlActiveTextureSlot(1);
        gl.rlEnableTexture(state.gbuffer.positions);

        gl.rlActiveTextureSlot(2);
        gl.rlEnableTexture(state.gbuffer.normals);

        gl.rlActiveTextureSlot(3);
        gl.rlEnableTexture(state.gbuffer.albedoSpec);

        gl.rlLoadDrawQuad();

        gl.rlDisableShader();
        gl.rlEnableColorBlend();
    }
    else {
        rl.drawTextureRec(
            rl.Texture2D {
                .id = switch(state.gbuffer_texture_type) {
                    .Albedo => state.gbuffer.albedoSpec,
                    .Normals => state.gbuffer.normals,
                    .Position => state.gbuffer.positions,
                    .Shading => 0, // todo: Temp solution.
                },
                .width = window_width,
                .height = window_height,
                .mipmaps = 1,
                .format = rl.PixelFormat.pixelformat_uncompressed_r32g32b32
            },
            rl.Rectangle.init(0,  0, @floatFromInt(window_width), @floatFromInt(-window_height)),
            Vector2.init(0.0, 0.0),
            Color.white);
    }

    state.gbuffer.copyDepthTo(0);
}

fn render() !void {
    rl.beginDrawing();
    defer rl.endDrawing();
    rl.clearBackground(rl.Color.white);

    renderPickingTexture();
    renderDeferred();

    // render visual tools
    rl.beginMode3D(state.main_camera);
    rl.drawGrid(100.0, 1.0);
    rl.endMode3D();

    if (state.touched) {
        rl.beginMode3D(state.main_camera);
        gl.rlDisableDepthTest();

        const touched_obj = getSceneObjectById(state.touch_id);
        touched_obj.renderBounds();
        state.gizmo.render();
        const pos = touched_obj.position;
        const rot = touched_obj.rotations;
        const id = touched_obj.id;

        rl.endMode3D();

        rl.drawText(rl.textFormat("ID: %d", .{ id }), 10, 150, 30, Color.green);
        rl.drawText(rl.textFormat("Pos: { %.2f, %.2f, %.2f }", .{ pos.x, pos.y, pos.z }), 10, 180, 30, Color.green);
        rl.drawText(rl.textFormat("Angle: { %.3f, %.3f, %.3f }", .{ rot.x, rot.y, rot.z }), 10, 220, 30, Color.green);
    }

    // render glyphs
    rl.beginMode2D(rl.Camera2D {
        .offset = Vector2.zero(),
        .rotation = 0,
        .target = Vector2.zero(),
        .zoom = 1,
    });

    gl.rlDisableDepthTest();
    // render 2d
    rl.drawText(rl.textFormat("Fps: %d, Delta: %.6f", .{ rl.getFPS(), state.delta }), 10, 10, 30, Color.green);

    if (state.gamepad >= 0) {
        rl.drawText(rl.textFormat("GP%d: %s", .{ state.gamepad, rl.getGamepadName(state.gamepad) }), 10, 50, 30, rl.Color.black);
    } else {
        rl.drawText("GP: NOT DETECTED", 10, 50, 30, Color.gray);
    }

    const screenWidth = rl.getScreenWidth();
    const screenHeight = rl.getScreenHeight();
    rl.drawText(rl.textFormat("%dx%d", .{ screenWidth, screenHeight }), 10, 90, 30, rl.Color.green);

    drawCursor();
    rl.endMode2D();
    gl.rlEnableDepthTest();
}

pub fn main() anyerror!void {
    rl.initWindow(window_width, window_height, "Game 1");
    rl.setWindowState(.{
        .window_resizable = true,
        // .vsync_hint = true,
        // .msaa_4x_hint = true,
        // .window_highdpi = true,
    });
    rl.toggleFullscreen();
    rl.setTargetFPS(120);
    rl.disableCursor();

    defer rl.closeWindow();

    state = .{
        .mode = AppMode.Editor,
        .camera_mode = rl.CameraMode.camera_free,
        .main_camera = .{
            .position = Vector3.init(0.0, 10.0, 10.0),
            .target = Vector3.zero(),
            .up = Vector3.init(0.0, 1.0, 0.0),
            .fovy = 45.0,
            .projection = rl.CameraProjection.camera_perspective
        },
        .dir = Vector2.init(0.0, 0.0),
        .mouse_delta = Vector2.zero(),
        .gizmo = gizmo.Gizmo.init(),
        .render_target = loadRenderTextureDepthTex(window_width, window_height),
        .picking_texture = loadPickingTexture(window_width, window_height),
        .objects = std.ArrayList(SceneObject).init(allocator),

        .gbuffer = GBuffer.init(window_width, window_height),
        .gbuffer_shader = rl.loadShader("res/shaders/gbuffer.vs.glsl", "res/shaders/gbuffer.fs.glsl"),
        .colored_shader = rl.loadShader("res/shaders/colored.vs.glsl", "res/shaders/colored.fs.glsl"),
        .deferred_shading_shader = rl.loadShader("res/shaders/deferred_shading.vs.glsl", "res/shaders/deferred_shading.fs.glsl"),

        .default_normal_map = rl.loadTextureFromImage(
            rl.genImageColor(
                1, 1,
                Color.fromNormalized(
                    rl.Vector4.init(0.5, 0.5, 1, 1)))),
        .default_diffuse_map = rl.loadTextureFromImage(rl.genImageColor(1, 1, Color.white)),
        .default_specular_map = rl.loadTextureFromImage(rl.genImageColor(1, 1, Color.black)),
    };

    // shader setup
    state.gbuffer_shader.locs[@intFromEnum(rl.SHADER_LOC_MAP_DIFFUSE)] = rl.getShaderLocation(state.gbuffer_shader, "diffuseTexture");
    state.gbuffer_shader.locs[@intFromEnum(rl.SHADER_LOC_MAP_SPECULAR)] = rl.getShaderLocation(state.gbuffer_shader, "specularTexture");
    state.gbuffer_shader.locs[@intFromEnum(rl.ShaderLocationIndex.shader_loc_map_normal)] = rl.getShaderLocation(state.gbuffer_shader, "normalTexture");

    state.deferred_shading_shader.locs[@intFromEnum(rl.ShaderLocationIndex.shader_loc_vector_view)] = rl.getShaderLocation(state.deferred_shading_shader, "camPos");
    gl.rlEnableShader(state.deferred_shading_shader.id);
        gl.rlSetUniformSampler(
            rl.getShaderLocation(state.deferred_shading_shader, "gPosition"), 1);
        gl.rlSetUniformSampler(
            rl.getShaderLocation(state.deferred_shading_shader, "gNormal"), 2);
        gl.rlSetUniformSampler(
            rl.getShaderLocation(state.deferred_shading_shader, "gAlbedoSpec"), 3);
    gl.rlDisableShader();
    // -----

    infoLog("SHADER: sheders set up.", .{});

    try state.objects.append(createCube(Vector3.init(0, 2, -1), Vector3.init(1, 1, 1), Color.lime));

    try state.objects.append(createPlane(Vector3.init(0.0, 0.1, 0.0), Vector2.init(10.0, 10.0), Color.dark_gray));
    var wall = createPlane(Vector3.init(0, 5, -5), Vector2.init(10.0, 10.0), Color.dark_gray);
    wall.rotations = Vector3.init(3.14/2.0, 0.0, 0.0);
    try state.objects.append(wall);

    var wall2 = createPlane(Vector3.init(10, 5, -5), Vector2.init(10.0, 10.0), Color.dark_gray);
    wall2.rotations = Vector3.init(3.14/2.0, 1.0, 0.0);
    try state.objects.append(wall2);

    try state.objects.append(createCube(Vector3.init(2, 1, 2), Vector3.init(2, 2, 2), Color.dark_purple));
    try state.objects.append(createCube(Vector3.init(9, 3, 9), Vector3.init(4, 4, 4), Color.magenta));
    try state.objects.append(createCube(Vector3.init(5, 2, 5), Vector3.init(3, 3, 3), Color.sky_blue ));

    try state.objects.append(createModel(Vector3.init(0.0, 2.0, 0.0), "res/models/Suzanne.gltf"));
    var nanosuit = createModel(Vector3.init(3.0, -0.5,  3.0),"res/models/bin/nanosuit.glb");
    nanosuit.scale = Vector3.scale(Vector3.one(), 0.25);
    try state.objects.append(nanosuit);
    try state.objects.append(createModel(Vector3.init(-2.0, 1.0, 0.0),"res/models/bin/cyborg.glb")); // todo: model shit, specular is not loaded

    infoLog("MODELS: Models loaded.", .{});

    defer {
        _ = gpa.deinit();
    }
    defer unloadRenderTextureDepthTex(state.render_target);
    defer unloadRenderTextureDepthTex(state.picking_texture);
    defer state.objects.deinit();
    defer unloadModels();
    defer rl.unloadShader(state.colored_shader);
    defer rl.unloadShader(state.gbuffer_shader);
    defer rl.unloadShader(state.deferred_shading_shader);

    while (!rl.windowShouldClose()) {
        try update();
        try render();
    }
}
