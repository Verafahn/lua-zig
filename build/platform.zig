const std = @import("std");

/// Extra system libraries from SYSLIBS in the Makefile. libm and libdl are
/// part of libc for the targets Zig supports, so they need no explicit entry.
pub fn linkLibraries(
    module: *std.Build.Module,
    target: std.Target,
    use_readline: bool,
) void {
    switch (target.os.tag) {
        .linux => {
            if (use_readline) module.linkSystemLibrary("readline", .{});
        },
        .macos => module.linkSystemLibrary("readline", .{}),
        .freebsd, .openbsd, .netbsd, .dragonfly => module.linkSystemLibrary("edit", .{}),
        .illumos => module.linkSystemLibrary("dl", .{}),
        else => {},
    }
}

/// The Makefile passes `-Wl,-E` (export-dynamic) on ELF platforms, so C modules
/// loaded at runtime can resolve the Lua API symbols of the host executable.
pub fn needsExportDynamic(target: std.Target) bool {
    return switch (target.os.tag) {
        .linux, .freebsd, .openbsd, .netbsd, .dragonfly, .illumos => true,
        else => false,
    };
}
