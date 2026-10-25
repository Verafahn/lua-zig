const std = @import("std");

/// Options mirroring the `@@` configuration points in luaconf.h that can be
/// overridden from the compiler command line. They can be set either directly:
///
///     zig build -Dlua-32bits=true -Dlua-path-default='./?.lua;./?/init.lua'
///
/// or from a dependent build script:
///
///     const lua = b.dependency("lua", .{ .@"lua-32bits" = true });
///
/// Macros that luaconf.h defines unconditionally (LUA_IDSIZE, LUA_EXTRASPACE,
/// LUAL_BUFFERSIZE, LUA_INT_TYPE and LUA_FLOAT_TYPE) cannot be overridden with
/// -D because the header would redefine them; the upstream Makefile requires
/// editing luaconf.h for those, so no build option is provided here.
pub const Config = struct {
    // Platform/REPL option from the Makefile's `linux-readline` target.
    readline: bool,
    // LUA_USE_C89
    use_c89: bool,
    // LUA_32BITS
    use_32bits: bool,
    // LUA_COMPAT_GLOBAL (defaults to 1 in luaconf.h)
    compat_global: bool,
    // LUA_COMPAT_MATHLIB
    compat_mathlib: bool,
    // LUA_NOCVTN2S
    noconv_n2s: bool,
    // LUA_NOCVTS2N
    noconv_s2n: bool,
    // LUA_USE_APICHECK
    use_apicheck: bool,
    // LUA_NOBUILTIN
    no_builtin: bool,
    // LUA_PATH_DEFAULT
    path_default: ?[]const u8,
    // LUA_CPATH_DEFAULT
    cpath_default: ?[]const u8,
    // LUA_DIRSEP
    dirsep: ?[]const u8,
    // LUA_READLINELIB
    readlinelib: ?[]const u8,
};

/// Declares all luaconf.h build options and reads their values from the
/// command line or from `b.dependency` options.
pub fn read(b: *std.Build) Config {
    return .{
        .readline = b.option(
            bool,
            "readline",
            "LUA_USE_READLINE: link the lua REPL against GNU readline (Linux only)",
        ) orelse false,
        .use_c89 = b.option(
            bool,
            "lua-use-c89",
            "LUA_USE_C89: avoid non-ISO-C89 features (also selects -std=c89)",
        ) orelse false,
        .use_32bits = b.option(
            bool,
            "lua-32bits",
            "LUA_32BITS: use 32-bit integers and 32-bit floats",
        ) orelse false,
        .compat_global = b.option(
            bool,
            "lua-compat-global",
            "LUA_COMPAT_GLOBAL: keep 'global' as a non-reserved word [default: true]",
        ) orelse true,
        .compat_mathlib = b.option(
            bool,
            "lua-compat-mathlib",
            "LUA_COMPAT_MATHLIB: keep deprecated math library functions",
        ) orelse false,
        .noconv_n2s = b.option(
            bool,
            "lua-noconv-n2s",
            "LUA_NOCVTN2S: disable automatic number-to-string coercion",
        ) orelse false,
        .noconv_s2n = b.option(
            bool,
            "lua-noconv-s2n",
            "LUA_NOCVTS2N: disable automatic string-to-number coercion",
        ) orelse false,
        .use_apicheck = b.option(
            bool,
            "lua-use-apicheck",
            "LUA_USE_APICHECK: enable consistency checks on the C API",
        ) orelse false,
        .no_builtin = b.option(
            bool,
            "lua-no-builtin",
            "LUA_NOBUILTIN: do not use compiler builtins for branch prediction",
        ) orelse false,
        .path_default = b.option(
            []const u8,
            "lua-path-default",
            "LUA_PATH_DEFAULT: default template list for package.path",
        ),
        .cpath_default = b.option(
            []const u8,
            "lua-cpath-default",
            "LUA_CPATH_DEFAULT: default template list for package.cpath",
        ),
        .dirsep = b.option(
            []const u8,
            "lua-dirsep",
            "LUA_DIRSEP: directory separator used for submodules",
        ),
        .readlinelib = b.option(
            []const u8,
            "lua-readlinelib",
            "LUA_READLINELIB: readline shared library loaded by the REPL",
        ),
    };
}

pub const Define = struct {
    name: []const u8,
    value: ?[]const u8 = null,
};

/// Returns the macros for every luaconf.h option that was set. They are used
/// both as compiler flags and in the generated luaconf.h, so the installed
/// headers always match the way the library was built.
pub fn defines(b: *std.Build, config: Config) []const Define {
    var list: std.ArrayList(Define) = .empty;

    if (config.use_c89) appendDefine(b, &list, "LUA_USE_C89", null);
    if (config.use_32bits) appendDefine(b, &list, "LUA_32BITS", null);
    if (!config.compat_global) appendDefine(b, &list, "LUA_COMPAT_GLOBAL", "0");
    if (config.compat_mathlib) appendDefine(b, &list, "LUA_COMPAT_MATHLIB", null);
    if (config.noconv_n2s) appendDefine(b, &list, "LUA_NOCVTN2S", null);
    if (config.noconv_s2n) appendDefine(b, &list, "LUA_NOCVTS2N", null);
    if (config.use_apicheck) appendDefine(b, &list, "LUA_USE_APICHECK", null);
    if (config.no_builtin) appendDefine(b, &list, "LUA_NOBUILTIN", null);

    if (config.path_default) |value| {
        appendDefine(b, &list, "LUA_PATH_DEFAULT", cStringLiteral(b, value));
    }
    if (config.cpath_default) |value| {
        appendDefine(b, &list, "LUA_CPATH_DEFAULT", cStringLiteral(b, value));
    }
    if (config.dirsep) |value| {
        appendDefine(b, &list, "LUA_DIRSEP", cStringLiteral(b, value));
    }
    if (config.readlinelib) |value| {
        appendDefine(b, &list, "LUA_READLINELIB", cStringLiteral(b, value));
    }

    return list.items;
}

fn appendDefine(
    b: *std.Build,
    list: *std.ArrayList(Define),
    name: []const u8,
    value: ?[]const u8,
) void {
    list.append(b.allocator, .{ .name = name, .value = value }) catch @panic("OOM");
}

/// Formats `value` as a C string literal (including the surrounding quotes) so
/// it can be passed through -D, where e.g. Windows path separators would
/// otherwise be interpreted as escape sequences.
fn cStringLiteral(b: *std.Build, value: []const u8) []const u8 {
    const allocator = b.allocator;
    var out: std.ArrayList(u8) = .empty;
    out.append(allocator, '"') catch @panic("OOM");
    for (value) |byte| {
        switch (byte) {
            '\\', '"' => {
                out.append(allocator, '\\') catch @panic("OOM");
                out.append(allocator, byte) catch @panic("OOM");
            },
            '\n' => out.appendSlice(allocator, "\\n") catch @panic("OOM"),
            '\r' => out.appendSlice(allocator, "\\r") catch @panic("OOM"),
            '\t' => out.appendSlice(allocator, "\\t") catch @panic("OOM"),
            else => out.append(allocator, byte) catch @panic("OOM"),
        }
    }
    out.append(allocator, '"') catch @panic("OOM");
    return out.items;
}
