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

fn add(raw: ?*lua.RawState) callconv(.c) c_int {
    var state = lua.State.wrap(raw orelse return 0);
    const i = state.toInteger(1) orelse return 0;
    state.pushInteger(i + 1);
    return 1;
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var state = try lua.State.create();
    defer state.deinit();
    state.openLibs();

    state.pushCFunction(&hostGreeting);
    state.setGlobal("host_greeting");
    state.pushCFunction(&add);
    state.setGlobal("add");

    var result = try state.evalString(gpa, @embedFile("minimal.lua"));
    defer result.deinit(gpa);

    try stdout.print("{s}\n", .{result.asString().?});
    try stdout.flush();
}
