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

const AppMode = enum {
    Editor,
    Game,
};

const Entity = struct {
    position: Vector3,
    size: Vector3,
};

const State = struct {
    now: f32 = 0,
    delta: f32 = 0,
    mode: AppMode,
    main_camera: Camera3d,
    camera_mode: rl.CameraMode,
    mouse_delta: Vector2,

    entities: [4]Entity = undefined,

    touch_id: usize = 1000,
    touch_cube: bool = false,

    ray: rl.Ray,

    dir: Vector2,
    gamepad: i32 = -1,

    gizmo: gizmo.Gizmo,

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

    if (state.touch_cube and state.touch_id < state.entities.len) {
        state.gizmo.position = state.entities[state.touch_id].position;
        state.gizmo.update(state.main_camera);
        state.entities[state.touch_id].position = state.gizmo.position;
    } else {
        state.gizmo.reset();
    }

    for (state.entities, 0..) |_, i| {
        const cubePosition = state.entities[i].position;
        const cubeSize = state.entities[i].size;

        if (rl.isMouseButtonPressed(rl.MouseButton.mouse_button_left)) {
            const ray = state.getRayFromCamera();

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

            const collision = rl.getRayCollisionBox(ray, boundingBox);

            if (collision.hit) {
                state.touch_cube = collision.hit;
                state.touch_id = i;
                state.ray = ray;

                break;
            }
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

fn loadRenderTextureDepthTex(width: i32, height: i32) rl.RenderTexture2D
{
    var target: rl.RenderTexture2D = rl.RenderTexture2D.init(width, height);

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

            for (state.entities, 0..) |e, i| {
                rl.drawCube(e.position, e.size.x, e.size.y, e.size.z, rl.Color.gray);
                if (state.touch_id == i) {
                    rl.drawCubeWires(e.position, e.size.x + 0.2, e.size.y + 0.2, e.size.z + 0.2, Color.dark_green);
                }
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

        const pos = state.entities[state.touch_id].position;
        rl.drawText(rl.textFormat("Pos: { %.2f, %.2f, %.2f } \n", .{ pos.x, pos.y, pos.z }), 10, 180, 30, Color.green);
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
        .entities = [4]Entity{
            Entity{ .position = Vector3{ .x = 0, .y = 0, .z = 0 }, .size = Vector3{ .x = 1, .y = 1, .z = 1 } },
            Entity{ .position = Vector3{ .x = 2, .y = 1, .z = 2 }, .size = Vector3{ .x = 2, .y = 2, .z = 2 } },
            Entity{ .position = Vector3{ .x = 5, .y = 2, .z = 5 }, .size = Vector3{ .x = 3, .y = 3, .z = 3 } },
            Entity{ .position = Vector3{ .x = 9, .y = 3, .z = 9 }, .size = Vector3{ .x = 4, .y = 4, .z = 4 } },
        },
        .ray = undefined,
        .dir = Vector2.init(0.0, 0.0),
        .mouse_delta = Vector2.zero(),
        .gizmo = gizmo.Gizmo.init(),
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
