const std = @import("std");
const rl = @import("raylib");
const rgui = @import("raygui");
const gl = rl.gl;

const Vector3 = rl.Vector3;
const Vector2 = rl.Vector2;
const Camera3d = rl.Camera3D;
const Camera2d = rl.Camera2D;
const Color = rl.Color;
const KeyboardKey = rl.KeyboardKey;

const AppMode = enum {
    Editor,
    Game,
};

pub const AxisType = enum {
    X,
    Y,
    Z,
};

pub const Axis = struct {
    position: Vector3,
    length: f32,
    width: f32,
    color: Color,
    axis_type: AxisType,

    len_scale_factor: f32 = 0,
    width_scale_factor: f32 = 0,

    pub fn init(color: Color, axis_type: AxisType) Axis {
        return .{
            .position = Vector3{ .x = 0, .y = 0, .z = 0 },
            .length = 2.0,
            .width = 0.1,
            .color = color,
            .axis_type = axis_type,
        };
    }

    pub fn update(self: *Axis, origin: Vector3) void {
        self.position = origin;
        const distance_to_camera = rl.Vector3.distance(self.position, state.main_camera.position);

        const base_size = 1.2;
        const base_length = 1.0;

        self.len_scale_factor = base_length * distance_to_camera / 10.0;
        self.width_scale_factor = base_size * distance_to_camera / 10.0;
    }

    pub fn render(self: Axis) void {
        const scaled_length = self.length * self.len_scale_factor;
        const scaled_width = self.width * self.width_scale_factor;

        switch (self.axis_type) {
            AxisType.X => {
                const adjusted_position = Vector3{
                    .x = self.position.x + (scaled_length / 2.0),
                    .y = self.position.y,
                    .z = self.position.z,
                };
                rl.drawCube(adjusted_position, scaled_length, scaled_width, scaled_width, self.color);
            },
            AxisType.Y => {
                const adjusted_position = Vector3{
                    .x = self.position.x,
                    .y = self.position.y + (scaled_length / 2.0),
                    .z = self.position.z,
                };
                rl.drawCube(adjusted_position, scaled_width, scaled_length, scaled_width, self.color);
            },
            AxisType.Z => {
                const adjusted_position = Vector3{
                    .x = self.position.x,
                    .y = self.position.y,
                    .z = self.position.z + (scaled_length / 2.0),
                };
                rl.drawCube(adjusted_position, scaled_width, scaled_width, scaled_length, self.color);
            },
        }
    }

    pub fn checkRayIntersection(self: Axis, ray: rl.Ray) bool {
        const scaled_length = self.length * self.len_scale_factor;
        const scaled_width = self.width * self.width_scale_factor;

        const bounding_box = rl.BoundingBox{
            .min = switch (self.axis_type) {
                AxisType.X => Vector3{
                    .x = self.position.x,
                    .y = self.position.y - (scaled_width / 2.0),
                    .z = self.position.z - (scaled_width / 2.0),
                },
                AxisType.Y => Vector3{
                    .x = self.position.x - (scaled_width / 2.0),
                    .y = self.position.y,
                    .z = self.position.z - (scaled_width / 2.0),
                },
                AxisType.Z => Vector3{
                    .x = self.position.x - (scaled_width / 2.0),
                    .y = self.position.y - (scaled_width / 2.0),
                    .z = self.position.z,
                },
            },
            .max = switch (self.axis_type) {
                AxisType.X => Vector3{
                    .x = self.position.x + scaled_length,
                    .y = self.position.y + (scaled_width / 2.0),
                    .z = self.position.z + (scaled_width / 2.0),
                },
                AxisType.Y => Vector3{
                    .x = self.position.x + (scaled_width / 2.0),
                    .y = self.position.y + scaled_length,
                    .z = self.position.z + (scaled_width / 2.0),
                },
                AxisType.Z => Vector3{
                    .x = self.position.x + (scaled_width / 2.0),
                    .y = self.position.y + (scaled_width / 2.0),
                    .z = self.position.z + scaled_length,
                },
            },
        };

        const info = rl.getRayCollisionBox(ray, bounding_box);
        return info.hit;
    }
};

const Gizmo = struct {
    position: Vector3,
    selected_plane: i32 = -1,
    axis: [3]Axis = undefined,
    dragging: bool = false,

    pub fn init() Gizmo {
        return Gizmo{
            .position = Vector3 { .x = 0, .y = 0, .z = 0 },
            .selected_plane = undefined,
            .axis = [_]Axis{
                Axis.init(Color.red, AxisType.X),
                Axis.init(Color.green, AxisType.Y),
                Axis.init(Color.blue, AxisType.Z),
            },
        };
    }

    pub fn reset(self: *Gizmo) void {
        self.position = Vector3.zero();
        self.dragging = false;
        self.selected_plane = -1;
    }

    pub fn update(self: *Gizmo) void {
        Axis.update(&self.axis[0], self.position);
        Axis.update(&self.axis[1], self.position);
        Axis.update(&self.axis[2], self.position);

        self.selectPlane();
        self.updatePosition(state.mouse_delta);
    }

    pub fn selectPlane(self: *Gizmo) void {
        if (rl.isMouseButtonPressed(rl.MouseButton.mouse_button_left)) {
            const ray = state.getRayFromCamera();
            self.selected_plane = -1;

            if (self.axis[0].checkRayIntersection(ray)) {
                self.selected_plane = 0;
            } else if (self.axis[1].checkRayIntersection(ray)) {
                self.selected_plane = 1;
            } else if (self.axis[2].checkRayIntersection(ray)) {
                self.selected_plane = 2;
            }

            self.dragging = self.selected_plane != -1;
        }

        if (rl.isMouseButtonReleased(rl.MouseButton.mouse_button_left)) {
            self.dragging = false;
            self.selected_plane = -1;
        }
    }

    pub fn updatePosition(self: *Gizmo, mouse_delta: Vector2) void {
        if (self.dragging) {
            const speed = 4.0;

            const axis_x = Vector3{ .x = 1, .y = 0, .z = 0 };
            const axis_y = Vector3{ .x = 0, .y = 1, .z = 0 };
            const axis_z = Vector3{ .x = 0, .y = 0, .z = 1 };

            const selected_axis_vector: Vector3 = switch (self.selected_plane) {
                0 => axis_x,
                1 => axis_y,
                2 => axis_z,
                else => unreachable,
            };

            // Проекция позиции объекта и конца оси на экран
            const axis_start_3d = self.position;
            const axis_end_3d = self.position.add(selected_axis_vector);

            const axis_start_2d = rl.getWorldToScreen(axis_start_3d, state.main_camera);
            const axis_end_2d = rl.getWorldToScreen(axis_end_3d, state.main_camera);

            // Вектор оси в пространстве экрана
            const axis_screen_vector = axis_end_2d.subtract(axis_start_2d).normalize();

            // Проецируем движение мыши на вектор оси на экране
            const mouse_movement_along_axis = mouse_delta.dotProduct(axis_screen_vector);

            const delta_position = selected_axis_vector.scale(mouse_movement_along_axis * speed * state.delta);
            self.position = self.position.add(delta_position);
        }
    }

    pub fn render(self: *Gizmo) void {
        Axis.render(self.axis[0]);
        Axis.render(self.axis[1]);
        Axis.render(self.axis[2]);
    }
};

const State = struct {
    now: f32 = 0,
    delta: f32 = 0,
    mode: AppMode,
    main_camera: Camera3d,
    camera_mode: rl.CameraMode,
    mouse_delta: Vector2,

    cube_position: Vector3,
    cube_size: Vector3,
    touch_cube: bool = false,
    ray: rl.Ray,

    dir: Vector2,
    gamepad: i32 = -1,

    gizmo: Gizmo,

    render_target: rl.RenderTexture2D,

    pub fn getRayFromCamera(self: *State) rl.Ray {
        const screenWidth: f32 = @floatFromInt(rl.getScreenWidth());
        const screenHeight: f32 = @floatFromInt(rl.getScreenHeight());
        return rl.getScreenToWorldRay(.{ .x = screenWidth / 2.0, .y = screenHeight / 2.0 }, self.main_camera);
    }
};

var state: State = undefined;

fn switchAppState() void {
    state.mode = switch (state.mode) {
        AppMode.Editor => AppMode.Game,
        AppMode.Game => AppMode.Editor,
    };
}

fn updateEditor() void {
    if (!state.gizmo.dragging) {
        state.main_camera.update(rl.CameraMode.camera_free);
    }

    var collision: rl.RayCollision = .{
        .hit = false,
        .distance = 0.0,
        .normal = Vector3.zero(),
        .point = Vector3.zero(),
    };

    if (state.touch_cube) {
        state.gizmo.position = state.cube_position;

        state.gizmo.update();

        state.cube_position = state.gizmo.position;
    } else {
        state.gizmo.reset();
    }

    var ray: rl.Ray = undefined;

    const cubePosition = state.cube_position;
    const cubeSize = state.cube_size;

    if (rl.isMouseButtonPressed(rl.MouseButton.mouse_button_left)) {
        if (!collision.hit) {
            ray = state.getRayFromCamera();

            const boundingBox = rl.BoundingBox{
                .min = rl.Vector3{
                    .x = cubePosition.x - cubeSize.x / 2.0,
                    .y = cubePosition.y - cubeSize.y / 2.0,
                    .z = cubePosition.z - cubeSize.z / 2.0,
                },
                .max = rl.Vector3{
                    .x = cubePosition.x + cubeSize.x / 2.0,
                    .y = cubePosition.y + cubeSize.y / 2.0,
                    .z = cubePosition.z + cubeSize.z / 2.0,
                },
            };

            collision = rl.getRayCollisionBox(ray, boundingBox);
        } else {
            collision.hit = false;
        }

        state.touch_cube = collision.hit;
        state.ray = ray;
    }
}

fn updateGame() void {
    state.gamepad = 0;
    //state.main_camera.update(rl.CameraMode.camera_third_person);

    if (!rl.isGamepadAvailable(state.gamepad)) {
        state.gamepad = -1;
    }

    if (state.gamepad >= 0) {
        state.dir.x = rl.getGamepadAxisMovement(state.gamepad, @intFromEnum(rl.GamepadAxis.gamepad_axis_left_x));
        state.dir.y = rl.getGamepadAxisMovement(state.gamepad, @intFromEnum(rl.GamepadAxis.gamepad_axis_left_y));
    } else {
        state.dir = Vector2.init(0.0, 0.0);
    }

    const acceleration: f32 = 10.0;
    const velocity = Vector2.scale(state.dir, acceleration * state.delta);
    state.cube_position = Vector3.add(state.cube_position, Vector3.init(velocity.x, 0.0, velocity.y));
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

fn loadRenderTextureDepthTex(width: i32, height: i32) rl.RenderTexture2D
{
    var target: rl.RenderTexture2D = rl.RenderTexture2D.init(width, height);
    //target.id = gl.rlLoadFramebuffer();

    if (target.id > 0)
    {
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
    }
    else  {
        rl.traceLog(rl.TraceLogLevel.log_warning, "FBO: Framebuffer object can not be created");
    }

    return target;
}

// Unload render texture from GPU memory (VRAM)
fn unloadRenderTextureDepthTex(target: rl.RenderTexture2D) void {
    if (target.id > 0) {
        target.texture.unload();
        target.depth.unload();
        target.unload();
    }
}

fn render() !void {

    state.render_target.begin();
    {
        defer state.render_target.end();
        rl.clearBackground(Color.white);

        rl.beginMode3D(state.main_camera);
        {
            defer rl.endMode3D();

            rl.drawCube(state.cube_position, state.cube_size.x, state.cube_size.y, state.cube_size.z, rl.Color.gray);
            if (state.touch_cube) {
                rl.drawCubeWires(state.cube_position, state.cube_size.x + 0.2, state.cube_size.y + 0.2, state.cube_size.z + 0.2, Color.dark_green);
            }
            rl.drawRay(state.ray, Color.dark_purple);
            rl.drawGrid(100.0, 1.0);
        }
    }

    rl.beginDrawing();
    defer rl.endDrawing();
    rl.clearBackground(rl.Color.white);

    rl.drawTextureRec(
        state.render_target.texture,
        rl.Rectangle.init(0,  0, 1280, -720),
        Vector2.init(0.0, 0.0),
        Color.white);

    if (state.touch_cube) {
        rl.beginMode3D(state.main_camera);
        state.gizmo.render();
        rl.endMode3D();

        rl.drawText(rl.textFormat("Pos: { %.2f, %.2f, %.2f } \n", .{ state.cube_position.x, state.cube_position.y, state.cube_position.z }), 10, 180, 30, Color.green);
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
    const screenWidth = 1280;
    const screenHeight = 720;

    rl.initWindow(screenWidth, screenHeight, "Game 1");
    rl.setWindowState(.{
        .window_resizable = true,
        .vsync_hint = true,
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
        .cube_position = Vector3.init(0.0, 1.0, 0.0),
        .cube_size = Vector3.init(2.0, 2.0, 2.0),
        .ray = undefined,
        .dir = Vector2.init(0.0, 0.0),
        .mouse_delta = Vector2.zero(),
        .gizmo = Gizmo.init(),
        .render_target = loadRenderTextureDepthTex(screenWidth, screenHeight),
    };
    defer unloadRenderTextureDepthTex(state.render_target);

    rl.setTargetFPS(120);
    rl.disableCursor();

    while (!rl.windowShouldClose()) {
        try update();
        try render();
    }
}
