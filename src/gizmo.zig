const rl = @import("raylib");

const Vector3 = rl.Vector3;
const Color = rl.Color;

pub const AxisType = enum {
    X,
    Y,
    Z,
};

const Axis = struct {
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

    pub fn update(self: *Axis, origin: Vector3, camera_position: Vector3) void {
        self.position = origin;
        const distance_to_camera = rl.Vector3.distance(self.position,camera_position);

        const base_size = 1.2;
        const base_length = 1.0;

        self.len_scale_factor = base_length * distance_to_camera / 10.0;
        self.width_scale_factor = base_size * distance_to_camera / 10.0;
    }

    pub fn render(self: Axis, selected: bool) void {
        const scaled_length = self.length * self.len_scale_factor;
        const scaled_width = self.width * self.width_scale_factor;

        const color = if (selected) Color.init(176,196,222, 255) else self.color;

        switch (self.axis_type) {
            AxisType.X => {
                const adjusted_position = Vector3{
                    .x = self.position.x + (scaled_length / 2.0),
                    .y = self.position.y,
                    .z = self.position.z,
                };
                rl.drawCube(adjusted_position, scaled_length, scaled_width, scaled_width, color);
            },
            AxisType.Y => {
                const adjusted_position = Vector3{
                    .x = self.position.x,
                    .y = self.position.y + (scaled_length / 2.0),
                    .z = self.position.z,
                };
                rl.drawCube(adjusted_position, scaled_width, scaled_length, scaled_width, color);
            },
            AxisType.Z => {
                const adjusted_position = Vector3{
                    .x = self.position.x,
                    .y = self.position.y,
                    .z = self.position.z + (scaled_length / 2.0),
                };
                rl.drawCube(adjusted_position, scaled_width, scaled_width, scaled_length, color);
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

const SelectedPlane = enum(u8) {
    X = 0,
    Y,
    Z,
    None,

    fn selected(self: @This()) bool {
        return self != SelectedPlane.None;
    }

    fn asVector3(self: @This()) rl.Vector3 {
        const axis_x = Vector3{ .x = 1, .y = 0, .z = 0 };
        const axis_y = Vector3{ .x = 0, .y = 1, .z = 0 };
        const axis_z = Vector3{ .x = 0, .y = 0, .z = 1 };

        return switch (self) {
            SelectedPlane.X => axis_x,
            SelectedPlane.Y => axis_y,
            SelectedPlane.Z => axis_z,
            else => unreachable, // TODO: Should i return zero() or unreachable??
        };
    }
};

pub const Gizmo = struct {
    position: Vector3,
    rotations: Vector3,
    selected_plane: SelectedPlane = SelectedPlane.None,
    axis: [3]Axis = undefined,
    dragging: bool = false,
    rotating: bool = false,

    pub fn init() Gizmo {
        return Gizmo{
            .position = Vector3.zero(),
            .rotations = Vector3.zero(),
            .axis = [_]Axis{
                Axis.init(Color.red, AxisType.X),
                Axis.init(Color.green, AxisType.Y),
                Axis.init(Color.blue, AxisType.Z),
            },
        };
    }

    pub fn update(self: *Gizmo, camera: rl.Camera3D) void {
        Axis.update(&self.axis[0], self.position, camera.position);
        Axis.update(&self.axis[1], self.position, camera.position);
        Axis.update(&self.axis[2], self.position, camera.position);

        self.selectPlane(camera);
        self.updatePosition(rl.getFrameTime(),rl.getMouseDelta().normalize(), camera);
    }

    pub fn render(self: *Gizmo) void {
        Axis.render(self.axis[0], self.selected_plane == SelectedPlane.X);
        Axis.render(self.axis[1], self.selected_plane == SelectedPlane.Y);
        Axis.render(self.axis[2], self.selected_plane == SelectedPlane.Z);
    }

    fn getRayFromCamera(camera: rl.Camera3D) rl.Ray {
        const screenWidth: f32 = @floatFromInt(rl.getScreenWidth());
        const screenHeight: f32 = @floatFromInt(rl.getScreenHeight());
        return rl.getScreenToWorldRay(.{ .x = screenWidth / 2.0, .y = screenHeight / 2.0 }, camera);
    }

    fn selectPlane(self: *Gizmo, camera: rl.Camera3D) void {
        if (rl.isMouseButtonPressed(rl.MouseButton.mouse_button_left)) {
            const ray = getRayFromCamera(camera);
            self.selected_plane = SelectedPlane.None;

            inline for (0..3) |i| {
                if (self.axis[i].checkRayIntersection(ray)) {
                    self.selected_plane = @enumFromInt(i);
                    break;
                }
            }

            self.dragging = self.selected_plane.selected();
        }

        if (rl.isMouseButtonReleased(rl.MouseButton.mouse_button_left)) {
            self.dragging = false;
        }

        self.rotating = self.selected_plane.selected() and rl.isKeyDown(rl.KeyboardKey.key_r);
    }

    fn updatePosition(self: *Gizmo, dt: f32, mouse_delta: rl.Vector2, camera: rl.Camera3D) void {
        if (self.dragging) {
            const speed = 4.0;

            const selected_axis_vector = self.selected_plane.asVector3();
            const axis_start_3d = self.position;
            const axis_end_3d = self.position.add(selected_axis_vector);

            const axis_start_2d = rl.getWorldToScreen(axis_start_3d, camera);
            const axis_end_2d = rl.getWorldToScreen(axis_end_3d, camera);

            const axis_screen_vector = axis_end_2d.subtract(axis_start_2d).normalize();

            const mouse_movement_along_axis = mouse_delta.dotProduct(axis_screen_vector);

            const delta_position = selected_axis_vector.scale(mouse_movement_along_axis * speed * dt);
            self.position = self.position.add(delta_position);
        }

        if (self.rotating) {
            if (rl.isKeyPressed(rl.KeyboardKey.key_c)) {
                self.rotations = Vector3.zero();
            }

            const wheel_dir = -rl.getMouseWheelMove();
            const wheel_speed = 10.0;

            self.rotations = self.rotations.add(
                self.selected_plane.asVector3().scale(wheel_speed * wheel_dir * dt));
        }
    }
};