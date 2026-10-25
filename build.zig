const std = @import("std");

const lua = @import("build/lua.zig");
const translate_c = @import("translate_c");

/// Project entry point.
///
/// Lua's C build logic lives under `build/`. Everything here is project
/// specific: target/optimize selection, Zig bindings generated with translate-c
/// from the installed Lua headers, and the embedding example.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lua_lib = lua.build(b, target, optimize);

    // Translate the installed headers, including the generated luaconf.h, so
    // the bindings always match the configuration the library was built with.
    const tc = b.dependency("translate_c", .{});
    const headers = b.addWriteFiles().add("lua_headers.h",
        \\#include <lua.h>
        \\#include <lualib.h>
        \\#include <lauxlib.h>
        \\
    );
    const translator = translate_c.Translator.init(tc, .{
        .name = "lua",
        .c_source_file = headers,
        .target = target,
        .optimize = optimize,
    });
    translator.addIncludePath(lua_lib.getEmittedIncludeTree());

    // Keep only the public Lua API in the module exposed to users.
    const filter = b.addExecutable(.{
        .name = "lua_filter",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/filter.zig"),
            .target = b.graph.host,
            .optimize = .safe,
            .imports = &.{
                .{ .name = "lua.hpp", .module = translator.mod },
            },
        }),
    });
    const run_filter = b.addRunArtifact(filter);
    const lua_module_file = run_filter.addOutputFileArg2("lua.zig", .{});

    const lua_module = b.addModule("lua", .{
        .root_source_file = lua_module_file,
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "lua.hpp", .module = translator.mod },
        },
    });

    const example_module = b.createModule(.{
        .root_source_file = b.path("examples/minimal.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "lua", .module = lua_module },
        },
    });
    example_module.linkLibrary(lua_lib);

    const example = b.addExecutable(.{
        .name = "exp-minimal",
        .root_module = example_module,
    });
    const run_example = b.addRunArtifact(example);
    const example_step = b.step("exp", "Build and run the minimal embedding example");
    example_step.dependOn(&run_example.step);
}
