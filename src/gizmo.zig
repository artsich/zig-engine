const math = @import("std").math;
const rl = @import("raylib");
const SceneObject = @import("scene.zig").SceneObject;

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
        const distance_to_camera = rl.Vector3.distance(self.position, camera_position);

        const base_size = 1.2;
        const base_length = 1.0;

        self.len_scale_factor = base_length * distance_to_camera / 10.0;
        self.width_scale_factor = base_size * distance_to_camera / 10.0;
    }

    pub fn render(self: Axis, selected: bool) void {
        const scaled_length = self.length * self.len_scale_factor;
        const scaled_width = self.width * self.width_scale_factor;

        const color = if (selected) Color.init(176, 196, 222, 255) else self.color;

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

const SelectedAxis = enum(u8) {
    X = 0,
    Y,
    Z,
    None,

    pub fn selected(self: @This()) bool {
        return self != SelectedAxis.None;
    }

    fn asVector3(self: @This()) rl.Vector3 {
        const axis_x = Vector3{ .x = 1, .y = 0, .z = 0 };
        const axis_y = Vector3{ .x = 0, .y = 1, .z = 0 };
        const axis_z = Vector3{ .x = 0, .y = 0, .z = 1 };

        return switch (self) {
            SelectedAxis.X => axis_x,
            SelectedAxis.Y => axis_y,
            SelectedAxis.Z => axis_z,
            else => Vector3.zero(),
        };
    }
};

pub const Mode = enum(u8) {
    Translation,
    Rotation,

    pub fn toString(self: @This()) [*:0]const u8 {
        return switch (self) {
            .Translation => "Translation",
            .Rotation => "Rotation",
        };
    }
};

pub const Gizmo = struct {
    selected_axis: SelectedAxis = SelectedAxis.None,
    axis: [3]Axis = undefined,
    obj: *SceneObject,
    mode: Mode,

    initial_position: Vector3,
    initial_rotations: Vector3,

    pub fn init(scene_object: *SceneObject) Gizmo {
        return .{
            .mode = Mode.Translation,
            .obj = scene_object,
            .initial_position = scene_object.position,
            .initial_rotations = scene_object.rotations,
            .axis = [_]Axis{
                Axis.init(Color.red, AxisType.X),
                Axis.init(Color.green, AxisType.Y),
                Axis.init(Color.blue, AxisType.Z),
            },
        };
    }

    pub fn changeMode(self: *@This(), mode: Mode) void {
        self.mode = mode;
    }

    pub fn render(self: *Gizmo) void {
        if (self.selected_axis == SelectedAxis.None) {
            inline for (self.axis) |axis| {
                Axis.render(axis, false);
            }
        } else {
            const index: usize = @intFromEnum(self.selected_axis);
            Axis.render(self.axis[index], true);
        }
    }

    pub fn update(self: *Gizmo, camera: rl.Camera3D) void {
        inline for (0..3) |i| {
            self.axis[i].update(self.obj.position, camera.position);
        }
    }

    pub fn transform(self: *@This(), camera: rl.Camera3D) void {
        self.activate(camera);

        if (self.selected_axis.selected()) {
            switch (self.mode) {
                .Translation => self.translate(camera),
                .Rotation => self.rotate(),
            }
        }
    }

    pub fn confirmTransformation(self: *Gizmo) void {
        self.selected_axis = SelectedAxis.None;
    }

    pub fn hasTransformed(self: *@This()) bool {
        return self.obj.position.equals(self.initial_position) == 0 or
            self.obj.rotations.equals(self.initial_rotations) == 0;
    }

    fn activate(self: *Gizmo, camera: rl.Camera3D) void {
        if (self.selected_axis.selected()) {
            return;
        }

        const ray = getRayFromCamera(camera);

        inline for (0..3) |i| {
            if (self.axis[i].checkRayIntersection(ray)) {
                self.selected_axis = @enumFromInt(i);
                self.initial_position = self.obj.position;
                self.initial_rotations = self.obj.rotations;
                break;
            }
        }
    }

    fn translate(self: *Gizmo, camera: rl.Camera3D) void {
        const speed = 10.0;

        const selected_axis_vector = self.selected_axis.asVector3();

        const axis_start_3d = self.obj.position;
        const axis_end_3d = self.obj.position.add(selected_axis_vector);

        const axis_start_2d = rl.getWorldToScreen(axis_start_3d, camera);
        const axis_end_2d = rl.getWorldToScreen(axis_end_3d, camera);

        const axis_screen_vector = axis_end_2d.subtract(axis_start_2d).normalize();
        const mouse_delta = rl.getMouseDelta().normalize();
        const mouse_movement_along_axis = mouse_delta.dotProduct(axis_screen_vector);

        const delta_position = selected_axis_vector.scale(mouse_movement_along_axis * speed * rl.getFrameTime());
        self.obj.position = self.obj.position.add(delta_position);
    }

    fn rotate(self: *Gizmo) void {
        const mouse_delta = rl.getMouseDelta();
        if (mouse_delta.x != 0 or mouse_delta.y != 0) {
            const base_rotation_speed = math.degreesToRadians(10);
            const rotation_speed = base_rotation_speed * rl.getFrameTime();

            const axis_vector = self.selected_axis.asVector3();
            const delta_rotation = axis_vector.scale(mouse_delta.x * rotation_speed);

            self.obj.rotations = self.obj.rotations.add(delta_rotation);
        }
    }

    fn getRayFromCamera(camera: rl.Camera3D) rl.Ray {
        const screenWidth: f32 = @floatFromInt(rl.getScreenWidth());
        const screenHeight: f32 = @floatFromInt(rl.getScreenHeight());
        return rl.getScreenToWorldRay(.{ .x = screenWidth / 2.0, .y = screenHeight / 2.0 }, camera);
    }
};
