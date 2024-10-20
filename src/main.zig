export var AmdPowerXpressRequestHighPerformance: u32 = 0x1;
export var NvOptimusEnablement: u32 = 0x1;

const std = @import("std");
const rl = @import("raylib");
const rgui = @import("raygui");
const zopengl = @import("zopengl");
const zgl = zopengl.bindings;

const gizmo = @import("gizmo.zig");
const ids = @import("id.zig");

const resources = @import("res/resources.zig");
const res = @import("res/resource.zig");

const scene = @import("scene.zig");
const log = @import("log.zig");
const math = @import("math.zig");
const gpu = @import("gpu.zig");

const Vector3 = rl.Vector3;
const Vector2 = rl.Vector2;
const Camera3d = rl.Camera3D;
const Camera2d = rl.Camera2D;
const Color = rl.Color;
const KeyboardKey = rl.KeyboardKey;

const window_width = 1920;
const window_height = (9 * window_width) / 16;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

var models = resources.Models.init(allocator);

const AppMode = enum {
    Editor,
    Game,
};

fn getEnumCount(comptime T: type) usize {
    return @typeInfo(T).Enum.fields.len;
}

const GBufferTexture = enum(u32) {
    Shading = 0,
    Position = 1,
    Normals = 2,
    Albedo = 3,
    Depth = 4,

    pub fn getName(self: GBufferTexture) [*:0]const u8 {
        return switch (self) {
            .Position => "Position",
            .Normals => "Normals",
            .Albedo => "Albedo",
            .Shading => "Shading",
            .Depth => "Depth",
        };
    }
};

var light_ubo: gpu.PointLightUbo = undefined;
const MAX_POINT_LIGHTS = 100;

const State = struct {
    now: f32 = 0,
    delta: f32 = 0,

    game_now: f32 = 0,
    game_delta: f32 = 0,

    mode: AppMode,
    main_camera: Camera3d,
    camera_mode: rl.CameraMode,
    mouse_delta: Vector2,

    objects: std.ArrayList(scene.SceneObject),

    touch_id: u32 = 0,

    dir: Vector2,
    gamepad: i32 = -1,

    gizmo: gizmo.Gizmo,

    render_target: rl.RenderTexture2D,
    picking_texture: rl.RenderTexture2D,

    gbuffer: gpu.GBuffer,
    gbuffer_shader: rl.Shader,
    gbuffer_texture_type: GBufferTexture = GBufferTexture.Shading,

    deferred_shading_shader: rl.Shader,
    //volume_light_shader: rl.Shader,

    volume_light_shader: *res.Res(rl.Shader) = undefined,
    text: *res.Res(res.Text) = undefined,

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

// todo: Optimize search
fn getSceneObjectById(id: u32) *scene.SceneObject {
    for (state.objects.items) |*obj| {
        if (obj.id == id) {
            return obj;
        }
    }

    unreachable;
}

pub fn getObjectIdFromPickingTex() i32 {
    const screen_width: f32 = @floatFromInt(rl.getScreenWidth());
    const screen_height: f32 = @floatFromInt(rl.getScreenHeight());
    const mouse_pos = Vector2.init(screen_width / 2.0, screen_height / 2.0);

    const image = rl.loadImageFromTexture(state.picking_texture.texture);
    defer rl.unloadImage(image);

    const picked_color = rl.getImageColor(image, @intFromFloat(mouse_pos.x), @intFromFloat(mouse_pos.y));
    return picked_color.toInt();
}

const Action = union(enum) {
    SelectObject: SelectObjectAction,
    MovedObject: MovedObjectAction,

    pub fn do(self: *const @This()) void {
        switch (self.*) {
            .SelectObject => |select_action| select_action.do(),
            .MovedObject => |moved_action| moved_action.do(),
        }
    }

    pub fn undo(self: *const @This()) void {
        switch (self.*) {
            .SelectObject => |select_action| select_action.undo(),
            .MovedObject => |moved_action| moved_action.undo(),
        }
    }

    pub fn select(id: u32, app_state: *State) Action {
        return .{ .SelectObject = SelectObjectAction.init(id, app_state) };
    }
};

const MovedObjectAction = struct {
    obj_id: u32,
    new_position: Vector3,
    new_rotation: Vector3,
    old_position: Vector3,
    old_rotation: Vector3,

    pub fn init(obj: *scene.SceneObject, old_p: Vector3, old_r: Vector3) @This() {
        return .{
            .obj_id = obj.id,
            .new_position = obj.position,
            .new_rotation = obj.rotations,
            .old_position = old_p,
            .old_rotation = old_r,
        };
    }

    pub fn do(self: *const @This()) void {
        const object = getSceneObjectById(self.obj_id);
        object.position = self.new_position;
        object.rotations = self.new_rotation;
    }

    pub fn undo(self: *const @This()) void {
        const object = getSceneObjectById(self.obj_id);
        object.position = self.old_position;
        object.rotations = self.old_rotation;

        log.info("move undo", .{});
    }
};

const SelectObjectAction = struct {
    state: *State,
    selected_obj_id: u32,
    last_selected_obj_id: u32,

    pub fn init(id: u32, app_state: *State) @This() {
        return .{
            .selected_obj_id = id,
            .state = app_state,
            .last_selected_obj_id = app_state.touch_id,
        };
    }

    pub fn do(self: *const @This()) void {
        std.debug.assert(self.selected_obj_id != self.state.touch_id);

        self.state.touch_id = self.selected_obj_id;
        if (self.state.touch_id > 0) {
            state.gizmo = gizmo.Gizmo.init(getSceneObjectById(self.state.touch_id));
        }

        log.info("Select id: %d", .{self.state.touch_id});
    }

    pub fn undo(self: *const @This()) void {
        self.state.touch_id = self.last_selected_obj_id;
        if (self.state.touch_id > 0) {
            state.gizmo = gizmo.Gizmo.init(getSceneObjectById(self.state.touch_id));
        }

        log.info("Undo: select id: %d", .{self.state.touch_id});
    }
};

var editor_actions = std.ArrayList(Action).init(allocator);
var completed_editor_actions = std.ArrayList(Action).init(allocator);

fn addAction(command: Action) void {
    editor_actions.append(command) catch |err| {
        std.debug.print("Failed to add command: {}\n", .{err});
        std.debug.assert(false);
    };
}

fn tryUndoCommands() void {
    if (!rl.isKeyDown(rl.KeyboardKey.key_left_control)) {
        return;
    }

    if (rl.isKeyPressed(rl.KeyboardKey.key_z)) {
        if (completed_editor_actions.items.len > 0) {
            completed_editor_actions.pop().undo();
        } else {
            log.info("Nothing to undo...", .{});
        }
    }
}

pub fn processCommands() void {
    for (editor_actions.items) |action| {
        action.do();
        completed_editor_actions.append(action) catch |err| {
            std.debug.print("Failed to add command: {}\n", .{err});
            return;
        };
    }

    editor_actions.resize(0) catch {};
}

fn updateEditor() void {
    state.delta = rl.getFrameTime();
    state.now += state.delta;

    const editor_gizmo = &state.gizmo;

    if (!rl.isKeyDown(rl.KeyboardKey.key_left_control)) {
        state.main_camera.update(rl.CameraMode.camera_free);
    }

    tryUndoCommands();
    var gizmo_was_active = false;
    if (state.touch_id > 0) {
        if (rl.isKeyDown(rl.KeyboardKey.key_left_control)) {
            if (rl.isKeyPressed(rl.KeyboardKey.key_q)) {
                editor_gizmo.changeMode(gizmo.Mode.Translation);
                log.info("translate", .{});
            } else if (rl.isKeyPressed(rl.KeyboardKey.key_w)) {
                editor_gizmo.changeMode(gizmo.Mode.Rotation);
                log.info("rotate", .{});
            }
        }

        editor_gizmo.update(state.main_camera);

        if (rl.isMouseButtonDown(rl.MouseButton.mouse_button_left)) {
            editor_gizmo.transform(state.main_camera);
        }

        gizmo_was_active = editor_gizmo.selected_axis.selected();

        if (rl.isMouseButtonReleased(rl.MouseButton.mouse_button_left)) {
            if (editor_gizmo.hasTransformed()) {
                addAction(.{ .MovedObject = MovedObjectAction.init(
                    editor_gizmo.obj,
                    editor_gizmo.initial_position,
                    editor_gizmo.initial_rotations,
                ) });
            }

            editor_gizmo.confirmTransformation();
        }
    }

    if (!gizmo_was_active and rl.isMouseButtonPressed(rl.MouseButton.mouse_button_left)) {
        const picked_id = getObjectIdFromPickingTex();
        if (picked_id > 0) {
            const object_id: u32 = @intCast(picked_id);
            if (object_id != state.touch_id) {
                addAction(Action.select(object_id, &state));
            }
        } else if (state.touch_id > 0) {
            addAction(Action.select(0, &state));
        }
    }

    if (rl.isKeyDown(rl.KeyboardKey.key_left_control)) {
        if (rl.isKeyPressed(rl.KeyboardKey.key_b)) {
            state.gbuffer_texture_type = @enumFromInt((@intFromEnum(state.gbuffer_texture_type) + 1) % getEnumCount(GBufferTexture));
            const name = state.gbuffer_texture_type.getName();
            log.info("Display gbuffer - %s", .{name});
        }
    }

    if (state.touch_id > 0 and rl.isKeyPressed(rl.KeyboardKey.key_c)) {
        addAction(Action.select(0, &state));
    }

    processCommands();
}

fn updateGame() void {
    state.game_delta = rl.getFrameTime();
    state.game_now += state.game_delta;

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

    const light = getSceneObjectById(13);
    const radius = 5.0;

    const dx = radius * std.math.sin(state.game_now);
    const dz = radius * std.math.cos(state.game_now);

    light.position = rl.Vector3.init(dx, light.position.y, dz);

    // const acceleration: f32 = 10.0;
    // const velocity = Vector2.scale(state.dir, acceleration * state.delta);
    //
    // const pos = state.objects.items[0].position;
    // state.objects.items[0].position = Vector3.add(pos, Vector3.init(velocity.x, 0.0, velocity.y));
}

fn update() !void {
    if (rl.isKeyPressed(KeyboardKey.key_f1)) {
        switchAppState();
    }

    if (rl.isKeyPressed(KeyboardKey.key_f10)) {
        rl.toggleFullscreen();
    }

    resources.update();

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
        rl.gl.rlEnableFramebuffer(target.id);

        target.texture = rl.loadTextureFromImage(rl.genImageColor(w, h, Color.blank));
        rl.setTextureFilter(target.texture, rl.TextureFilter.texture_filter_point);
        rl.setTextureWrap(target.texture, rl.TextureWrap.texture_wrap_clamp);

        rl.gl.rlFramebufferAttach(target.id, target.texture.id, @intFromEnum(rl.gl.rlFramebufferAttachType.rl_attachment_color_channel0), @intFromEnum(rl.gl.rlFramebufferAttachTextureType.rl_attachment_texture2d), 0);
        if (rl.gl.rlFramebufferComplete(target.id)) {
            rl.traceLog(rl.TraceLogLevel.log_info, rl.textFormat("FBO: [ID %i] Framebuffer object created successfully", .{target.id}));
        } else {
            unreachable;
        }
        rl.gl.rlDisableFramebuffer();
    } else {
        rl.traceLog(rl.TraceLogLevel.log_warning, "FBO: Framebuffer object can not be created");
        unreachable;
    }

    return target;
}

fn loadRenderTextureDepthTex(width: i32, height: i32) rl.RenderTexture2D {
    var target: rl.RenderTexture2D = rl.RenderTexture2D.init(width, height);

    if (target.id > 0) {
        rl.gl.rlEnableFramebuffer(target.id);

        target.texture.id = rl.gl.rlLoadTexture(null, width, height, @intFromEnum(rl.gl.rlPixelFormat.rl_pixelformat_uncompressed_r8g8b8a8), 1);
        target.depth.id = rl.gl.rlLoadTextureDepth(width, height, false);

        rl.gl.rlFramebufferAttach(target.id, target.texture.id, @intFromEnum(rl.gl.rlFramebufferAttachType.rl_attachment_color_channel0), @intFromEnum(rl.gl.rlFramebufferAttachTextureType.rl_attachment_texture2d), 0);
        rl.gl.rlFramebufferAttach(target.id, target.depth.id, @intFromEnum(rl.gl.rlFramebufferAttachType.rl_attachment_depth), @intFromEnum(rl.gl.rlFramebufferAttachType.rl_attachment_color_channel0), 0);

        if (rl.gl.rlFramebufferComplete(target.id)) {
            rl.traceLog(rl.TraceLogLevel.log_info, rl.textFormat("FBO: [ID %i] Framebuffer object created successfully", .{target.id}));
        } else {
            unreachable;
        }

        rl.gl.rlDisableFramebuffer();
    } else {
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

        rl.gl.rlDisableColorBlend();
        defer rl.gl.rlEnableColorBlend();

        rl.beginMode3D(state.main_camera);
        {
            for (state.objects.items) |obj| {
                obj.renderForPicking();
            }
        }
        rl.endMode3D();
    }
}

fn stencilLightPass(ligths_transforms: []const rl.Matrix) void {
    zgl.depthMask(0);
    zgl.colorMask(0, 0, 0, 0);
    zgl.stencilOp(zgl.KEEP, zgl.INCR_WRAP, zgl.KEEP);
    zgl.stencilFunc(zgl.ALWAYS, zgl.ZERO, 0xFF);

    // todo: fix this shit
    const default_shader = resources.default_material.shader;
    resources.default_material.shader = resources.instanced_shader;
    defer resources.default_material.shader = default_shader;

    rl.beginMode3D(state.main_camera);
    {
        zgl.cullFace(zgl.FRONT);
        resources.sphere_mesh.drawInstanced(resources.default_material, ligths_transforms);
    }
    rl.endMode3D();

    zgl.stencilOp(zgl.KEEP, zgl.DECR_WRAP, zgl.KEEP);
    rl.beginMode3D(state.main_camera);
    {
        zgl.cullFace(zgl.BACK);
        resources.sphere_mesh.drawInstanced(resources.default_material, ligths_transforms);
    }
    rl.endMode3D();

    zgl.colorMask(1, 1, 1, 1);
    zgl.depthMask(1);
}

fn lightPass() void {
    var transforms: [MAX_POINT_LIGHTS]rl.Matrix = undefined;
    var lights_found: usize = 0;
    for (state.objects.items) |obj| {
        if (obj.data == scene.ObjectData.Light) {
            transforms[lights_found] = math.getTransformMatrix(obj.position, rl.Vector3.one().scale(obj.data.Light.Point.radius), rl.Vector3.zero());
            lights_found += 1;
        }
    }
    const light_transforms = transforms[0..lights_found];

    zgl.enable(zgl.STENCIL_TEST);
    zgl.clear(zgl.STENCIL_BUFFER_BIT);

    stencilLightPass(light_transforms);

    zgl.stencilFunc(zgl.NOTEQUAL, zgl.ZERO, 0xff);
    zgl.cullFace(zgl.FRONT);
    rl.beginMode3D(state.main_camera);
    {
        rl.beginBlendMode(rl.BlendMode.blend_add_colors);
        zgl.disable(zgl.DEPTH_TEST);

        const light_shader = state.volume_light_shader.data.*;
        rl.gl.rlEnableShader(light_shader.id);

        light_shader.locs[@intFromEnum(rl.ShaderLocationIndex.shader_loc_vector_view)] =
            rl.getShaderLocation(light_shader, "camPos");
        light_shader.locs[@intFromEnum(rl.ShaderLocationIndex.shader_loc_matrix_model)] =
            rl.getShaderLocationAttrib(light_shader, "instanceTransform");

        const cameraPos: [3]f32 = .{ state.main_camera.position.x, state.main_camera.position.y, state.main_camera.position.z };
        const camPosIndexLoc: usize = @intCast(@intFromEnum(rl.ShaderLocationIndex.shader_loc_vector_view));
        rl.setShaderValue(light_shader, light_shader.locs[camPosIndexLoc], &cameraPos, rl.ShaderUniformDataType.shader_uniform_vec3);

        rl.gl.rlSetUniformSampler(rl.getShaderLocation(light_shader, "gPosition"), 1);
        rl.gl.rlSetUniformSampler(rl.getShaderLocation(light_shader, "gNormal"), 2);
        rl.gl.rlSetUniformSampler(rl.getShaderLocation(light_shader, "gAlbedoSpec"), 3);

        // zero slot is reserved by raylib!
        rl.gl.rlActiveTextureSlot(1);
        rl.gl.rlEnableTexture(state.gbuffer.positions);

        rl.gl.rlActiveTextureSlot(2);
        rl.gl.rlEnableTexture(state.gbuffer.normals);

        rl.gl.rlActiveTextureSlot(3);
        rl.gl.rlEnableTexture(state.gbuffer.albedoSpec);

        var light_id: usize = 0;
        var point_lights: [MAX_POINT_LIGHTS]gpu.PointLightGpu = undefined;

        for (state.objects.items) |obj| {
            if (obj.data == scene.ObjectData.Light) {
                point_lights[light_id] = gpu.PointLightGpu.init(obj.position, obj.color, obj.data.Light.Point.radius);
                light_id += 1;
            }
        }
        light_ubo.upload(point_lights[0..light_id], zgl.DYNAMIC_DRAW);
        light_ubo.bindWithShader(light_shader);

        resources.default_material.shader = light_shader;

        zgl.enable(zgl.FRAMEBUFFER_SRGB);
        resources.sphere_mesh.drawInstanced(resources.default_material, light_transforms);

        rl.gl.rlDisableShader();
    }
    rl.endMode3D();
    rl.endBlendMode();
    zgl.disable(zgl.FRAMEBUFFER_SRGB);

    zgl.enable(zgl.DEPTH_TEST);
    zgl.cullFace(zgl.BACK);

    zgl.disable(zgl.STENCIL_TEST);
}

fn renderDeferred() void {
    state.gbuffer.begin();
    {
        defer state.gbuffer.end();
        rl.gl.rlClearColor(0, 0, 0, 0);
        state.gbuffer.clear();

        rl.gl.rlDisableColorBlend();
        defer rl.gl.rlEnableColorBlend();

        rl.beginShaderMode(state.gbuffer_shader);
        defer rl.endShaderMode();

        rl.beginMode3D(state.main_camera);
        {
            defer rl.endMode3D();

            for (state.objects.items) |obj| {
                switch (obj.data) {
                    .Model => {
                        obj.data.Model.useShader(state.gbuffer_shader);
                        obj.render();
                    },
                    else => {},
                }
            }
        }
    }

    state.gbuffer.copyDepthTo(0);

    if (state.gbuffer_texture_type == GBufferTexture.Shading) {
        lightPass();
    } else {
        rl.drawTextureRec(rl.Texture2D{
            .id = switch (state.gbuffer_texture_type) {
                .Albedo => state.gbuffer.albedoSpec,
                .Normals => state.gbuffer.normals,
                .Position => state.gbuffer.positions,
                else => 0,
            },
            .width = window_width,
            .height = window_height,
            .mipmaps = 1,
            .format = rl.PixelFormat.pixelformat_uncompressed_r32g32b32,
        }, rl.Rectangle.init(0, 0, @floatFromInt(window_width), @floatFromInt(-window_height)), Vector2.init(0.0, 0.0), Color.white);
    }
}

fn render() !void {
    rl.beginDrawing();
    defer rl.endDrawing();
    rl.clearBackground(rl.Color.black);

    renderPickingTexture();
    renderDeferred();

    // render visual tools
    rl.beginMode3D(state.main_camera);
    rl.drawGrid(100.0, 1.0);

    // draw lights
    for (state.objects.items) |obj| {
        switch (obj.data) {
            .Light => {
                obj.render();
            },
            else => {},
        }
    }

    rl.endMode3D();

    if (state.touch_id > 0 and state.mode == AppMode.Editor) {
        rl.beginMode3D(state.main_camera);
        rl.gl.rlDisableDepthTest();

        const touched_obj = getSceneObjectById(state.touch_id);
        touched_obj.renderBounds();
        state.gizmo.render();
        const pos = touched_obj.position;
        const rot = touched_obj.rotations;
        const id = touched_obj.id;

        rl.endMode3D();

        rl.drawText(rl.textFormat("ID: %d", .{id}), 10, 150, 30, Color.green);
        rl.drawText(rl.textFormat("Pos: { %.2f, %.2f, %.2f }", .{ pos.x, pos.y, pos.z }), 10, 180, 30, Color.green);
        rl.drawText(rl.textFormat("Angle: { %.3f, %.3f, %.3f }", .{ rot.x, rot.y, rot.z }), 10, 220, 30, Color.green);
        rl.drawText(rl.textFormat("Mode: %s", .{state.gizmo.mode.toString()}), 10, 260, 30, Color.green);
    }

    // render glyphs
    rl.beginMode2D(rl.Camera2D{
        .offset = Vector2.zero(),
        .rotation = 0,
        .target = Vector2.zero(),
        .zoom = 1,
    });

    rl.gl.rlDisableDepthTest();
    // render 2d
    rl.drawText(rl.textFormat("Fps: %d, Delta: %.6f", .{ rl.getFPS(), state.delta }), 10, 10, 30, Color.green);

    if (state.gamepad >= 0) {
        rl.drawText(rl.textFormat("GP%d: %s", .{ state.gamepad, rl.getGamepadName(state.gamepad) }), 10, 50, 30, rl.Color.black);
    } else {
        rl.drawText("GP: NOT DETECTED", 10, 50, 30, Color.gray);
    }

    rl.drawText(rl.textFormat("Dynamic text: %s", .{state.text.data.str.ptr}), 10, 500, 30, rl.Color.green);

    const screenWidth = rl.getScreenWidth();
    const screenHeight = rl.getScreenHeight();
    rl.drawText(rl.textFormat("%dx%d", .{ screenWidth, screenHeight }), 10, 90, 30, rl.Color.green);

    drawCursor();
    rl.endMode2D();
    rl.gl.rlEnableDepthTest();
}

pub const GlProc = *const anyopaque;

pub fn getProcAddress(procname: [*:0]const u8) ?GlProc {
    return glfwGetProcAddress(procname);
}
extern fn glfwGetProcAddress(procname: [*:0]const u8) ?GlProc;

pub fn main() anyerror!void {
    defer {
        _ = gpa.deinit();
    }

    rl.initWindow(window_width, window_height, "Game 1");
    rl.setWindowState(.{
        .window_resizable = false,
        // .vsync_hint = true,
        // .msaa_4x_hint = true,
        // .window_highdpi = true,
    });

    rl.setTargetFPS(9999);
    rl.disableCursor();

    try zopengl.loadCoreProfile(getProcAddress, 3, 3);
    defer rl.closeWindow();

    resources.init(allocator);
    defer resources.deinit(allocator);

    state = .{
        .mode = AppMode.Editor,
        .camera_mode = rl.CameraMode.camera_free,
        .main_camera = .{ .position = Vector3.init(0.0, 10.0, 10.0), .target = Vector3.zero(), .up = Vector3.init(0.0, 1.0, 0.0), .fovy = 45.0, .projection = rl.CameraProjection.camera_perspective },
        .dir = Vector2.init(0.0, 0.0),
        .mouse_delta = Vector2.zero(),
        .gizmo = undefined,
        .render_target = loadRenderTextureDepthTex(window_width, window_height),
        .picking_texture = loadPickingTexture(window_width, window_height),
        .objects = std.ArrayList(scene.SceneObject).init(allocator),
        .gbuffer = gpu.GBuffer.init(window_width, window_height),
        .gbuffer_shader = rl.loadShader("res/shaders/gbuffer.vs.glsl", "res/shaders/gbuffer.fs.glsl"),
        .deferred_shading_shader = rl.loadShader("res/shaders/deferred_shading.vs.glsl", "res/shaders/deferred_shading.fs.glsl"),
    };

    state.volume_light_shader = resources.load(rl.Shader, "res/shaders/stencil_light.shader", allocator);
    defer resources.unload(rl.Shader, state.volume_light_shader, allocator);

    state.text = resources.load(res.Text, "res/simple.txt", allocator);
    defer resources.unload(res.Text, state.text, allocator);

    light_ubo = gpu.PointLightUbo.init(0, "PointLights");
    defer light_ubo.destroy();

    // shader setup
    state.gbuffer_shader.locs[@intFromEnum(rl.SHADER_LOC_MAP_DIFFUSE)] = rl.getShaderLocation(state.gbuffer_shader, "diffuseTexture");
    state.gbuffer_shader.locs[@intFromEnum(rl.SHADER_LOC_MAP_SPECULAR)] = rl.getShaderLocation(state.gbuffer_shader, "specularTexture");
    state.gbuffer_shader.locs[@intFromEnum(rl.ShaderLocationIndex.shader_loc_map_normal)] = rl.getShaderLocation(state.gbuffer_shader, "normalTexture");

    state.deferred_shading_shader.locs[@intFromEnum(rl.ShaderLocationIndex.shader_loc_vector_view)] = rl.getShaderLocation(state.deferred_shading_shader, "camPos");
    rl.gl.rlEnableShader(state.deferred_shading_shader.id);
    rl.gl.rlSetUniformSampler(rl.getShaderLocation(state.deferred_shading_shader, "gPosition"), 1);
    rl.gl.rlSetUniformSampler(rl.getShaderLocation(state.deferred_shading_shader, "gNormal"), 2);
    rl.gl.rlSetUniformSampler(rl.getShaderLocation(state.deferred_shading_shader, "gAlbedoSpec"), 3);
    rl.gl.rlDisableShader();

    // todo: this should be set during initialization...

    // -----

    log.info("SHADER: sheders set up.", .{});

    try state.objects.append(scene.createPlane(Vector3.init(0.0, 0.1, 0.0), Vector2.init(10.0, 10.0), Color.dark_gray));
    var wall = scene.createPlane(Vector3.init(0, 5, -5), Vector2.init(10.0, 10.0), Color.dark_gray);
    wall.rotations = Vector3.init(3.14 / 2.0, 0.0, 0.0);
    try state.objects.append(wall);

    var wall2 = scene.createPlane(Vector3.init(10, 5, -5), Vector2.init(10.0, 10.0), Color.dark_gray);
    wall2.rotations = Vector3.init(3.14 / 2.0, -1.0, 0.0);
    try state.objects.append(wall2);

    var wall3 = scene.createPlane(Vector3.init(-10, 5, -5), Vector2.init(10.0, 10.0), Color.dark_gray);
    wall3.rotations = Vector3.init(3.14 / 2.0, 1.0, 0.0);
    try state.objects.append(wall3);

    try state.objects.append(scene.createCube(Vector3.init(2, 1, 2), Vector3.init(2, 2, 2), Color.dark_purple));
    try state.objects.append(scene.createCube(Vector3.init(9, 3, 9), Vector3.init(4, 4, 4), Color.magenta));
    try state.objects.append(scene.createCube(Vector3.init(5, 2, 5), Vector3.init(3, 3, 3), Color.sky_blue));

    try state.objects.append(scene.createModel(Vector3.init(0.0, 2.0, 0.0), "res/models/Suzanne.gltf", &models));
    var nanosuit = scene.createModel(Vector3.init(3.0, -0.5, 3.0), "res/models/bin/nanosuit.glb", &models);
    nanosuit.scale = Vector3.scale(Vector3.one(), 0.25);
    try state.objects.append(nanosuit);
    try state.objects.append(scene.createModel(Vector3.init(-2.0, 1.0, 0.0), "res/models/bin/cyborg.glb", &models)); // todo: model shit, specular is not loaded
    var error_model = scene.createModel(Vector3.init(2.0, 8.0, 0.0), "res/models/bin/error_text.glb", &models);
    error_model.scale = Vector3.one().scale(50);
    error_model.rotations = Vector3.init(0.0, 0.0, 3.14 / 2.0);
    try state.objects.append(error_model);
    try state.objects.append(scene.createLight(Vector3.init(3, 2, 0), Color.white, 5.0));
    try state.objects.append(scene.createLight(Vector3.init(-5, 2, 0), Color.white, 5.0));
    try state.objects.append(scene.createLight(Vector3.init(0, 2, 7), Color.white, 5.0));

    log.info("MODELS: Models loaded.", .{});

    defer unloadRenderTextureDepthTex(state.render_target);
    defer unloadRenderTextureDepthTex(state.picking_texture);
    defer state.objects.deinit();
    defer models.unloadModels();
    defer rl.unloadShader(state.gbuffer_shader);
    defer rl.unloadShader(state.deferred_shading_shader);
    defer editor_actions.deinit();
    defer completed_editor_actions.deinit();

    while (!rl.windowShouldClose()) {
        try update();
        try render();
    }
}
