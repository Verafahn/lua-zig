const std = @import("std");
const config = @import("config.zig");

/// Builds the compiler flags from the Makefile's CFLAGS, the luaconf.h options
/// selected through `config.Config`, and the platform-specific target settings.
pub fn forTarget(
    b: *std.Build,
    target: std.Target,
    options: config.Config,
) []const []const u8 {
    var flags: std.ArrayList([]const u8) = .empty;

    // CC= gcc -std=gnu99 (c89 target: -std=c89), CFLAGS= -O2 -Wall -Wextra.
    // The -O level comes from Zig's standard `-Doptimize` option instead of a
    // hard-coded -O2.
    append(b, &flags, if (options.use_c89) "-std=c89" else "-std=gnu99");
    append(b, &flags, "-Wall");
    append(b, &flags, "-Wextra");

    // luaconf.h configuration (see the `@@` annotations in that file).
    for (config.defines(b, options)) |define| {
        if (define.value) |value| {
            append(b, &flags, b.fmt("-D{s}={s}", .{ define.name, value }));
        } else {
            append(b, &flags, b.fmt("-D{s}", .{define.name}));
        }
    }

    appendPlatformFlags(b, &flags, target, options);
    return flags.items;
}

/// Platform settings from the Makefile's PLAT targets.
fn appendPlatformFlags(
    b: *std.Build,
    flags: *std.ArrayList([]const u8),
    target: std.Target,
    options: config.Config,
) void {
    switch (target.os.tag) {
        .linux => {
            append(b, flags, "-DLUA_USE_LINUX");
            if (options.readline) append(b, flags, "-DLUA_USE_READLINE");
        },
        .macos => {
            append(b, flags, "-DLUA_USE_MACOSX");
        },
        .freebsd, .openbsd, .netbsd, .dragonfly => {
            flags.appendSlice(b.allocator, &.{
                "-DLUA_USE_LINUX",
                "-DLUA_USE_READLINE",
                "-I/usr/include/edit",
            }) catch @panic("OOM");
        },
        .ios => {
            append(b, flags, "-DLUA_USE_IOS");
        },
        .illumos => {
            flags.appendSlice(b.allocator, &.{
                "-DLUA_USE_POSIX",
                "-DLUA_USE_DLOPEN",
                "-D_REENTRANT",
            }) catch @panic("OOM");
        },
        // Windows gets LUA_USE_WINDOWS from luaconf.h via _WIN32; everything
        // else falls back to the portable `generic` target.
        else => {},
    }
}

fn append(b: *std.Build, flags: *std.ArrayList([]const u8), flag: []const u8) void {
    flags.append(b.allocator, flag) catch @panic("OOM");
}
