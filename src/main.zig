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

const allocator = std.heap.page_allocator;

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

const Entity = struct {
    id: u32,
    position: Vector3,
    size: Vector3,
    color: Color,
};

const CubeData = struct {
    size: Vector3,
};

const PlaneData = struct {
    size: Vector2,
};

const ObjectData = union(enum) {
    Cube: CubeData,
    Plane: PlaneData,
};

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
                rl.drawPlane(self.position, plane.size, self.color);
            }
        }
    }
};

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
    rl.drawRectangle(x, y, 10, 10, Color.green);
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
        target.texture.width = width;
        target.texture.height = height;
        target.texture.format = rl.PixelFormat.pixelformat_uncompressed_r8g8b8a8;
        target.texture.mipmaps = 1;

        target.depth.id = gl.rlLoadTextureDepth(width, height, false);
        target.depth.width = width;
        target.depth.height = height;
        target.depth.format = rl.PixelFormat.pixelformat_compressed_etc2_rgb;
        target.depth.mipmaps = 1;

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

fn render() !void {
    // render objects for picking
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

    // simple 3d
    state.render_target.begin();
    {
        defer state.render_target.end();
        rl.clearBackground(Color.white);

        rl.beginMode3D(state.main_camera);
        {
            defer rl.endMode3D();

            for (state.objects.items) |obj| {
                obj.render();
                if (state.touch_id == obj.id) {
                    obj.renderWired();
                }
            }

            rl.drawGrid(100.0, 1.0);
        }
    }

    rl.beginDrawing();
    defer rl.endDrawing();
    rl.clearBackground(rl.Color.white);

    rl.drawTextureRec(
        state.render_target.texture,
        rl.Rectangle.init(0,  0, @floatFromInt(rl.getScreenWidth()), @floatFromInt(-rl.getScreenHeight())),
        Vector2.init(0.0, 0.0),
        Color.white);

    if (state.touched) {
        rl.beginMode3D(state.main_camera);
        state.gizmo.render();
        rl.endMode3D();

        const touched_obj = getSceneObjectById(state.touch_id);
        const pos = touched_obj.position;
        const id = touched_obj.id;
        rl.drawText(rl.textFormat("ID: %d", .{ id }), 10, 150, 30, Color.green);
        rl.drawText(rl.textFormat("Pos: { %.2f, %.2f, %.2f }", .{ pos.x, pos.y, pos.z }), 10, 180, 30, Color.green);
    }

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
}

pub fn main() anyerror!void {

    rl.initWindow(window_width, window_height, "Game 1");
    rl.setWindowState(.{
        .window_resizable = true,
        //.vsync_hint = true,
        //        .msaa_4x_hint = true,
        .window_highdpi = true,
    });
    //rl.toggleFullscreen();

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
    };

    try state.objects.append(createPlane(Vector3.zero(), Vector2.init(10.0, 10.0), Color.dark_gray));
    try state.objects.append(createCube(Vector3.init(2, 1, 2), Vector3.init(2, 2, 2), Color.dark_purple));
    try state.objects.append(createCube(Vector3.init(5, 2, 5), Vector3.init(3, 3, 3), Color.sky_blue ));
    try state.objects.append(createCube(Vector3.init(9, 3, 9), Vector3.init(4, 4, 4), Color.magenta));
    try state.objects.append(createCube(Vector3.zero(), Vector3.one(), Color.pink));

    defer state.objects.deinit();
    defer unloadRenderTextureDepthTex(state.render_target);
    defer unloadRenderTextureDepthTex(state.picking_texture);

    rl.setTargetFPS(120);
    rl.disableCursor();

    while (!rl.windowShouldClose()) {
        try update();
        try render();
    }
}
