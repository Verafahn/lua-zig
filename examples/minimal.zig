//! Minimal example of embedding the Lua interpreter in a Zig program.
//!
//! Run it with:
//!
//!     zig build exp
//!
//! The example creates a Lua state, loads the standard libraries, exposes a
//! Zig function to Lua, runs a chunk that calls back into it, and reads the
//! resulting global.

const std = @import("std");
const lua = @import("lua");

/// Host function exposed to Lua as `host_greeting()`.
fn hostGreeting(L: ?*lua.lua_State) callconv(.c) c_int {
    const state = L orelse return 0;
    _ = lua.lua_pushstring(state, "Zig");
    return 1; // number of values returned to Lua
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    // Create an isolated Lua state and load the standard libraries.
    const state = lua.luaL_newstate() orelse return error.OutOfMemory;
    defer lua.lua_close(state);

    lua.luaL_openlibs(state);

    // Make the Zig function available as a global Lua function.
    lua.lua_pushcfunction(state, hostGreeting);
    lua.lua_setglobal(state, "host_greeting");

    // Execute a chunk that calls back into Zig and stores a global.
    const chunk =
        \\local squares = {}
        \\for i = 1, 4 do
        \\    squares[i] = i * i
        \\end
        \\result = string.format(
        \\    "Hello from %s; interpreter: %s; squares: %s",
        \\    host_greeting(), _VERSION, table.concat(squares, ", "))
    ;

    // Load and run the chunk. luaL_dostring is a C macro; call the
    // underlying functions directly so the translation stays type-safe.
    if (lua.luaL_loadstring(state, chunk.ptr) != 0 or
        lua.lua_pcallk(state, 0, lua.LUA_MULTRET, 0, 0, null) != 0)
    {
        var len: usize = 0;
        const message = lua.lua_tolstring(state, -1, &len);
        if (message == null) return error.LuaError;
        try stdout.print("Lua error: {s}\n", .{message[0..len]});
        try stdout.flush();
        return error.LuaError;
    }

    // Fetch the global written by the chunk and print it from Zig.
    _ = lua.lua_getglobal(state, "result");
    var len: usize = 0;
    const result = lua.lua_tolstring(state, -1, &len);
    if (result == null) return error.MissingResult;

    try stdout.print("{s}\n", .{result[0..len]});
    try stdout.flush();
}
