pub const Generator = struct {
    current: u32,

    pub fn init() @This() {
        return .{
            .current = 0,
        };
    }

    pub fn next(self: *@This()) u32 {
        const id = self.current + 1;
        self.current += 1;
        return id;
    }
};
