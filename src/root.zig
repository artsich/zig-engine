const std = @import("std");
const testing = std.testing;

test "True" {
    try testing.expect(true);
}
