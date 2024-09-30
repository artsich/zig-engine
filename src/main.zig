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

const CubeData = struct {
    size: Vector3,
};

const PlaneData = struct {
    size: Vector2,
};

const ModelData = struct {
    model: *const rl.Model,
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
    Cube: CubeData,
    Plane: PlaneData,
    Model: ModelData,
};

const ModelsTable = std.AutoHashMap([*:0]const u8, rl.Model);
var loaded_models =  ModelsTable.init(allocator);

pub fn loadModel(file_name: [*:0]const u8) *const rl.Model {
    if (!loaded_models.contains(file_name)) {
        const model = rl.loadModel(file_name);
        loaded_models.put(file_name, model) catch unreachable;
    }

    const entry = loaded_models.getEntry(file_name);
    return entry.?.value_ptr;
}

pub fn unloadModels() void {
    var it = loaded_models.iterator();
    while (it.next()) |entry| {
        entry.value_ptr.*.unload();
    }

    loaded_models.deinit();
}

const SceneObject = struct {
    id: u32,
    position: Vector3,
    color: Color,
    data: ObjectData,

    pub fn init(p: Vector3, data: ObjectData, color: Color) @This() {
        return .{
            .id = genId(),
            .position = p,
            .color = color,
            .data = data,
        };
    }

    fn render(self: SceneObject) void {
        switch (self.data) {
            .Cube => {
                const cube = self.data.Cube;
                rl.drawCube(self.position, cube.size.x, cube.size.y, cube.size.z, self.color);
            },
            .Plane => {
                const plane = self.data.Plane;
                rl.drawPlane(self.position, plane.size, self.color);
            },
            .Model => {
                const data = self.data.Model;
                rl.drawModel(data.model.*, self.position, 1.0, self.color);
            }
        }
    }

    fn renderColored(self: SceneObject, color: Color) void {
        switch (self.data) {
            .Cube => {
                const cube = self.data.Cube;
                rl.drawCube(self.position, cube.size.x, cube.size.y, cube.size.z, color);
            },
            .Plane => {
                const plane = self.data.Plane;
                rl.drawPlane(self.position, plane.size, color);
            },
            .Model => {
                const data = self.data.Model;
                data.useShader(state.coloredShader);
                rl.drawModel(data.model.*, self.position, 1.0, color);
            }
        }
    }

    fn renderWired(self: SceneObject) void {
        switch (self.data) {
            .Cube => {
                const cube = self.data.Cube;
                rl.drawCubeWires(self.position, cube.size.x + 0.2, cube.size.y + 0.2, cube.size.z + 0.2, Color.dark_green);
            },
            .Plane => {
                const plane = self.data.Plane;
                rl.drawCubeWires(self.position, plane.size.x + 0.2, 0.2, plane.size.y + 0.2, Color.dark_green);
            },
            .Model => {
                const data = self.data.Model;
                // todo: must transorm to world space, after i introduce Translation matrix!
                const bbox = data.bbox;
                const transformed_bbox = rl.BoundingBox{
                    .min = rl.Vector3.add(bbox.min, self.position),
                    .max = rl.Vector3.add(bbox.max, self.position),
                };
                rl.drawBoundingBox(transformed_bbox, Color.dark_green);
            }
        }
    }
};

const textFormat = rl.textFormat;

fn infoLog(text: [*:0]const u8, args: anytype) void {
    rl.traceLog(rl.TraceLogLevel.log_info, rl.textFormat(text, args));
}

fn createModel(p: Vector3, file_name: [*:0]const u8) SceneObject {
    const model = loadModel(file_name);
    const bbox = rl.getModelBoundingBox(model.*);

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
    return SceneObject.init(
        p,
        ObjectData {
            .Cube = CubeData {
                .size = size,
            }
        },
        c);
}

fn createPlane(p: Vector3, size: Vector2, c: Color) SceneObject {
    return SceneObject.init(
        p,
        ObjectData {
            .Plane = PlaneData {
                .size = size
            },
        },
        c);
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
            .positions =positionsTex,
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
    gbufferShader: rl.Shader,
    gbufferTextureType: GBufferTexture = GBufferTexture.Position,

    coloredShader: rl.Shader,

    pub fn getRayFromCamera(self: *State) rl.Ray {
        const screenWidth: f32 = @floatFromInt(rl.getScreenWidth());
        const screenHeight: f32 = @floatFromInt(rl.getScreenHeight());
        return rl.getScreenToWorldRay(.{ .x = screenWidth / 2.0, .y = screenHeight / 2.0 }, self.main_camera);
    }
};

var state: State = undefined;

const window_width = 2560;
const window_height = (9*window_width)/16;

fn switchAppState() void {
    state.mode = switch (state.mode) {
        AppMode.Editor => AppMode.Game,
        AppMode.Game => AppMode.Editor,
    };
}

fn getSceneObjectById(id: u32) *SceneObject {
    for (state.objects.items) |*obj| {
        if (obj.id == id) {
            return obj;
        }
    }

    unreachable;
}

fn updateEditor() void {
    if (!state.gizmo.dragging) {
        state.main_camera.update(rl.CameraMode.camera_free);
    }

    if (state.touched) {
        const obj = getSceneObjectById(state.touch_id);
        state.gizmo.position = obj.*.position;
        state.gizmo.update(state.main_camera);
        obj.*.position = state.gizmo.position;
    } else {
        state.gizmo.reset();
    }

    if (!state.gizmo.dragging and rl.isMouseButtonPressed(rl.MouseButton.mouse_button_left)) {
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
        } else {
            state.touched = false;
            state.touch_id = 0;
        }
    }

    if (rl.isKeyDown(rl.KeyboardKey.key_right_control)) {
        if (rl.isKeyPressed(rl.KeyboardKey.key_b)) {
            state.gbufferTextureType = @enumFromInt((@intFromEnum(state.gbufferTextureType) + 1) % getEnumCount(GBufferTexture));
            const name = state.gbufferTextureType.getName();
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
    // state.cube_position = Vector3.add(state.cube_position, Vector3.init(velocity.x, 0.0, velocity.y));
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
        state.gbuffer.clear();

        gl.rlDisableColorBlend();
        defer gl.rlEnableColorBlend();

        rl.beginShaderMode(state.gbufferShader);
        defer rl.endShaderMode();

        rl.beginMode3D(state.main_camera);
        {
            defer rl.endMode3D();

            for (state.objects.items) |obj| {
                switch (obj.data) {
                    .Model => {
                        obj.data.Model.useShader(state.gbufferShader);
                    },
                    else => {}
                }
                obj.render();
            }
        }
    }

    state.gbuffer.copyDepthTo(0);

    rl.drawTextureRec(
        rl.Texture2D {
            .id = switch(state.gbufferTextureType) {
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
        touched_obj.renderWired();
        state.gizmo.render();
        const pos = touched_obj.position;
        const id = touched_obj.id;
        rl.drawText(rl.textFormat("ID: %d", .{ id }), 10, 150, 30, Color.green);
        rl.drawText(rl.textFormat("Pos: { %.2f, %.2f, %.2f }", .{ pos.x, pos.y, pos.z }), 10, 180, 30, Color.green);

        rl.endMode3D();
        gl.rlEnableDepthTest();
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
    rl.drawText(rl.textFormat("%dx%d", .{ screenWidth, screenHeight }), 10, 90, 30, rl.Color.black);

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
    //rl.toggleFullscreen();
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
        .gbufferShader = rl.loadShader("res/shaders/gbuffer.vs.glsl", "res/shaders/gbuffer.fs.glsl"),
        .coloredShader = rl.loadShader("res/shaders/colored.vs.glsl", "res/shaders/colored.fs.glsl"),
    };

    try state.objects.append(createPlane(Vector3.zero(), Vector2.init(10.0, 10.0), Color.dark_gray));
    try state.objects.append(createCube(Vector3.init(2, 1, 2), Vector3.init(2, 2, 2), Color.dark_purple));
    try state.objects.append(createCube(Vector3.init(5, 2, 5), Vector3.init(3, 3, 3), Color.sky_blue ));
    try state.objects.append(createCube(Vector3.init(9, 3, 9), Vector3.init(4, 4, 4), Color.magenta));
    try state.objects.append(createModel(Vector3.zero(), "res/models/Suzanne.gltf"));
    try state.objects.append(createModel(Vector3.init(2.0, 1.0, 0.0),"res/models/backpack/backpack.obj"));
    try state.objects.append(createModel(Vector3.init(-2.0, 1.0, 0.0),"res/models/cyborg/cyborg.obj"));
    try state.objects.append(createModel(Vector3.init(0.0, 3.0, 0.0),"res/models/nanosuit/nanosuit.obj"));

    defer {
        _ = gpa.deinit();
    }
    defer unloadRenderTextureDepthTex(state.render_target);
    defer unloadRenderTextureDepthTex(state.picking_texture);
    defer state.objects.deinit();
    defer unloadModels();

    while (!rl.windowShouldClose()) {
        try update();
        try render();
    }
}
