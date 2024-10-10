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
