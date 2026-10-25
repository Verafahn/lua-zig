const std = @import("std");
const lua = @import("lua.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);
    const outfile = try std.Io.Dir.cwd().createFile(io, args[1], .{});
    defer outfile.close(io);

    var buffer: [64]u8 = undefined;
    var writer = outfile.writer(io, &buffer);
    const w = &writer.interface;
    try w.writeAll("const lua = @import(\"lua.hpp\");\n\n");
    const decl_names = @typeInfo(lua).@"struct".decl_names;
    for (decl_names) |decl_name| {
        if (isLuaPublicApi(decl_name)) {
            try w.print("pub const {s} = lua.{s};\n", .{ decl_name, decl_name });
        }
    }
    try w.flush();
}

fn isLuaPublicApi(name: [:0]const u8) bool {
    return std.mem.startsWith(u8, name, "lua_") or
        std.mem.startsWith(u8, name, "luaL_") or
        std.mem.startsWith(u8, name, "luaopen_") or
        std.mem.startsWith(u8, name, "LUA_") or
        std.mem.startsWith(u8, name, "LUAL_") or
        std.mem.startsWith(u8, name, "LUALIB_API") or
        std.mem.startsWith(u8, name, "LUAMOD_API");
}
