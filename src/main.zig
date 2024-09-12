const std = @import("std");
const rl = @import("raylib");
const rgui = @import("raygui");

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


const Plane = enum {
    X,
    Y,
    Z,
};

const Gizmo = struct {
    position: Vector3,
    selected_plane: ?Plane = undefined,

    pub fn init() Gizmo {
        return Gizmo{
            .position = Vector3 { .x = 0, .y = 0, .z = 0 },
            .selected_plane = null,
        };
    }

    pub fn update(self: *Gizmo) void {
        self.selectPlane();
        self.updatePosition(state.mouse_delta);
    }

    fn intersectPlaneXY(self: *Gizmo, ray: rl.Ray) bool {
        const size = Vector2.init(1, 1);
        // Определяем четыре угловых точки квадрата на плоскости XY, с центром в gizmo.position
        const p1 = rl.Vector3 { .x = self.position.x - size.x / 2, .y = self.position.y - size.y / 2, .z = self.position.z };
        const p2 = rl.Vector3 { .x = self.position.x + size.x / 2, .y = self.position.y - size.y / 2, .z = self.position.z };
        const p3 = rl.Vector3 { .x = self.position.x + size.x / 2, .y = self.position.y + size.y / 2, .z = self.position.z };
        const p4 = rl.Vector3 { .x = self.position.x - size.x / 2, .y = self.position.y + size.y / 2, .z = self.position.z };

        const collision = rl.getRayCollisionQuad(ray, p1, p2, p3, p4);
        return collision.hit;
    }

    pub fn selectPlane(self: *Gizmo) void {
        if (rl.isMouseButtonDown(rl.MouseButton.mouse_button_left)) {
            const ray = state.getRayFromCamera();
            if (self.intersectPlaneXY(ray)) {
                self.selected_plane = .Z;
                std.debug.print("Intersected with xy\n", .{});
            }
            // else if (intersectsPlaneXZ(mousePosition, self.position)) {
            //     self.selectedPlane = .Y;
            // } else if (intersectsPlaneYZ(mousePosition, self.position)) {
            //     self.selectedPlane = .X;
            // }
        }
        else {
            self.selected_plane = undefined;
        }
    }

    pub fn updatePosition(self: *Gizmo, mouseDelta: Vector2) void {
        const speed = 2.0;
        if (self.selected_plane) |sp| {
            switch (sp) {
                .X => self.position.y += mouseDelta.y * state.delta * speed,
                .Y => self.position.z += mouseDelta.y * state.delta * speed,
                .Z => self.position.x += mouseDelta.x * state.delta * speed,
            }
        }
    }

    pub fn render(self: *Gizmo) void {
        rl.drawCube(self.position, 1, 1, 3, Color.green);
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
    state.main_camera.update(rl.CameraMode.camera_free);

    var collision: rl.RayCollision = .{
        .hit = false,
        .distance = 0.0,
        .normal = Vector3.zero(),
        .point = Vector3.zero(),
    };

    state.gizmo.position = state.cube_position;
    state.gizmo.update();

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

    state.mouse_delta = rl.getMouseDelta().normalize();

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

    if (state.mode == AppMode.Editor) {
        updateEditor();
    } else if (state.mode == AppMode.Game) {
        updateGame();
    }
}

fn drawCursor() void {
    const screenWidth = rl.getScreenWidth();
    const screenHeight = rl.getScreenHeight();
    rl.drawRectangle(@divExact(screenWidth, 2), @divExact(screenHeight, 2), 10, 10, Color.green);
}

fn render() !void {
    rl.beginMode3D(state.main_camera);
    rl.drawCube(state.cube_position, 2.0, 2.0, 2.0, rl.Color.red);

    if (state.touch_cube) {
        rl.drawCubeWires(state.cube_position, state.cube_size.x + 0.2, state.cube_size.y + 0.2, state.cube_size.z + 0.2, Color.dark_green);
    }
    rl.drawRay(state.ray, Color.dark_purple);

    rl.drawGrid(100.0, 1.0);


    rl.endMode3D();
    state.gizmo.render();

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
    const screenWidth = 1920;
    const screenHeight = 1080;

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
    };

    rl.setTargetFPS(120);
    rl.disableCursor();

    while (!rl.windowShouldClose()) {
        try update();

        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(rl.Color.white);
        try render();
    }
}
