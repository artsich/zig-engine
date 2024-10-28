const builtin = @import("builtin");
const rl = @import("raylib");
const zopengl = @import("zopengl");
const zgl = zopengl.bindings;

pub fn UniformBuffer(comptime T: type) type {
    return struct {
        id: u32,
        bindPoint: u32,
        name: [*]const u8,
        const Self = @This();

        pub fn init(bindPoint: u32, name: [*]const u8) Self {
            var ubo: u32 = 0;
            zgl.genBuffers(1, &ubo);
            return Self{ .id = ubo, .bindPoint = bindPoint, .name = name };
        }

        pub fn upload(self: *@This(), data: []const T, usage: u32) void {
            const data_size = @sizeOf(T) * data.len;
            zgl.bindBuffer(zgl.UNIFORM_BUFFER, self.id);
            zgl.bufferData(zgl.UNIFORM_BUFFER, @intCast(data_size), data.ptr, usage);
        }

        pub fn bind(self: *@This()) void {
            zgl.bindBufferBase(zgl.UNIFORM_BUFFER, self.bindPoint, self.id);
        }

        pub fn destroy(self: *@This()) void {
            zgl.deleteBuffers(1, &self.id);
        }

        pub fn bindWithShader(self: *@This(), shader: rl.Shader) void {
            self.bind();
            const block_loc = zgl.getUniformBlockIndex(shader.id, self.name);
            zgl.uniformBlockBinding(shader.id, block_loc, 0);
        }
    };
}

pub const PointLightGpu = struct {
    pos: rl.Vector4,
    color: rl.Vector4,
    radius: f32,
    _pad0: f32 = 0,
    _pad1: f32 = 0,
    _pad2: f32 = 0,

    pub fn init(pos: rl.Vector3, color: rl.Color, radius: f32) @This() {
        return .{
            .pos = rl.Vector4.init(pos.x, pos.y, pos.z, 0.0),
            .color = rl.Color.normalize(color),
            .radius = radius,
        };
    }
};

pub const PointLightUbo = UniformBuffer(PointLightGpu);

const GL_READ_FRAMEBUFFER = 0x8CA8;
const GL_DRAW_FRAMEBUFFER = 0x8CA9;
const GL_DEPTH_BUFFER_BIT = 0x00000100;

pub const GBuffer = struct {
    framebuffer: u32,
    albedoSpec: u32,
    normals: u32,
    positions: u32,
    depth: u32,

    w: i32,
    h: i32,

    pub fn init(w: i32, h: i32) @This() {
        const scaled = asScaledFrameSize(w, h);
        const width = scaled[0];
        const height = scaled[1];

        const framebuffer = rl.gl.rlLoadFramebuffer();
        if (framebuffer == 0) {
            rl.traceLog(rl.TraceLogLevel.log_error, "Failed to create gbuffer.");
            unreachable;
        }

        rl.gl.rlEnableFramebuffer(framebuffer);
        defer rl.gl.rlDisableFramebuffer();

        const positionsTex = rl.gl.rlLoadTexture(null, width, height, @intFromEnum(rl.gl.rlPixelFormat.rl_pixelformat_uncompressed_r32g32b32), 1);
        const normalTex = rl.gl.rlLoadTexture(null, width, height, @intFromEnum(rl.gl.rlPixelFormat.rl_pixelformat_uncompressed_r32g32b32), 1);
        const albedoSpecTex = rl.gl.rlLoadTexture(null, width, height, @intFromEnum(rl.gl.rlPixelFormat.rl_pixelformat_uncompressed_r8g8b8a8), 1);

        rl.gl.rlActiveDrawBuffers(3);

        rl.gl.rlFramebufferAttach(framebuffer, positionsTex, @intFromEnum(rl.gl.rlFramebufferAttachType.rl_attachment_color_channel0), @intFromEnum(rl.gl.rlFramebufferAttachTextureType.rl_attachment_texture2d), 0);
        rl.gl.rlFramebufferAttach(framebuffer, normalTex, @intFromEnum(rl.gl.rlFramebufferAttachType.rl_attachment_color_channel1), @intFromEnum(rl.gl.rlFramebufferAttachTextureType.rl_attachment_texture2d), 0);
        rl.gl.rlFramebufferAttach(framebuffer, albedoSpecTex, @intFromEnum(rl.gl.rlFramebufferAttachType.rl_attachment_color_channel2), @intFromEnum(rl.gl.rlFramebufferAttachTextureType.rl_attachment_texture2d), 0);

        const depthTex = rl.gl.rlLoadTextureDepth(width, height, false);
        rl.gl.rlFramebufferAttach(framebuffer, depthTex, @intFromEnum(rl.gl.rlFramebufferAttachType.rl_attachment_depth), @intFromEnum(rl.gl.rlFramebufferAttachTextureType.rl_attachment_texture2d), 0);

        if (rl.gl.rlFramebufferComplete(framebuffer)) {
            rl.traceLog(rl.TraceLogLevel.log_info, rl.textFormat("FBO: [ID %i] Framebuffer object created successfully", .{framebuffer}));
        } else unreachable;

        rl.gl.rlDisableFramebuffer();

        return GBuffer{
            .framebuffer = framebuffer,
            .albedoSpec = albedoSpecTex,
            .normals = normalTex,
            .positions = positionsTex,
            .depth = depthTex,
            .w = width,
            .h = height,
        };
    }

    pub fn copyDepthToMain(self: @This()) void {
        rl.gl.rlBindFramebuffer(GL_READ_FRAMEBUFFER, self.framebuffer);
        rl.gl.rlBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);

        const main_size = getMainFrameSize();
        rl.gl.rlBlitFramebuffer(0, 0, self.w, self.h, 0, 0, main_size[0], main_size[1], GL_DEPTH_BUFFER_BIT);

        rl.gl.rlBindFramebuffer(GL_READ_FRAMEBUFFER, 0);
        rl.gl.rlBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
    }

    pub fn begin(self: @This()) void {
        zgl.bindFramebuffer(zgl.FRAMEBUFFER, self.framebuffer);
        rl.gl.rlViewport(0, 0, self.w, self.h);
    }

    pub fn clear(_: @This()) void {
        rl.gl.rlClearColor(0, 0, 0, 0);
        rl.gl.rlClearScreenBuffers();
    }

    pub fn end(_: @This()) void {
        zgl.bindFramebuffer(zgl.FRAMEBUFFER, 0);
        const main_size = getMainFrameSize();
        rl.gl.rlViewport(0, 0, main_size[0], main_size[1]);
    }

    fn getMainFrameSize() [2]i32 {
        return asScaledFrameSize(rl.gl.rlGetFramebufferWidth(), rl.gl.rlGetFramebufferHeight());
    }

    fn asScaledFrameSize(w: i32, h: i32) [2]i32 {
        if (comptime builtin.target.os.tag == .macos) {
            const dpi = rl.getWindowScaleDPI();
            const scale_x = dpi.x;
            const scale_y = dpi.y;

            const fb_width: f32 = @floatFromInt(w);
            const fb_height: f32 = @floatFromInt(h);

            const scaled_width: i32 = @intFromFloat(fb_width * scale_x);
            const scaled_height: i32 = @intFromFloat(fb_height * scale_y);

            return [2]i32{ scaled_width, scaled_height };
        } else {
            return [2]i32{ w, h };
        }
    }
};
