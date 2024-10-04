const rl = @import("raylib");
const textFormat = rl.textFormat;

pub fn info(text: [*:0]const u8, args: anytype) void {
    rl.traceLog(rl.TraceLogLevel.log_info, rl.textFormat(text, args));
}

pub fn err(text: [*:0]const u8, args: anytype) void {
    rl.traceLog(rl.TraceLogLevel.log_error, rl.textFormat(text, args));
}
