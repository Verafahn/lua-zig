//! Minimal example of embedding Lua in a Zig program using the high-level
//! wrapper. Run it with `zig build exp`.

const std = @import("std");
const lua = @import("lua");

/// Host function exposed to Lua as `host_greeting()`.
fn hostGreeting(raw: ?*lua.RawState) callconv(.c) c_int {
    var state = lua.State.wrap(raw orelse return 0);
    state.pushLiteral("Zig");
    return 1; // number of values returned to Lua
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.arena.allocator();

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var state = try lua.State.create();
    defer state.deinit();
    state.openLibs();

    state.pushCFunction(hostGreeting);
    state.setGlobal("host_greeting");

    var result = try state.evalString(allocator, @embedFile("minimal.lua"));
    defer result.deinit(allocator);

    try stdout.print("{s}\n", .{result.asString().?});
    try stdout.flush();
}
