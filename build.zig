const std = @import("std");

const lua = @import("build/lua.zig");

/// Project entry point.
///
/// Everything related to building Lua's C sources lives under `build/`.
/// The code below is specific to this Zig project: selecting the build target
/// and generating Zig bindings for the example program.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lua_lib = lua.build(b, target, optimize);

    // ---------------------------------------------------------------------
    // Zig bindings and example
    // ---------------------------------------------------------------------
    const gen_lua_api = b.addExecutable(.{
        .name = "lua_filter",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/filter.zig"),
            .target = b.graph.host,
            .optimize = .safe,
        }),
    });
    const run_gen_lua_api = b.addRunArtifact(gen_lua_api);
    const lua_api_file = run_gen_lua_api.addOutputFileArg2("lua.zig", .{});

    const lua_module = b.addModule("lua", .{
        .root_source_file = lua_api_file,
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "lua.hpp",
                .module = b.createModule(.{
                    .root_source_file = b.path("src/lua.zig"),
                    .target = target,
                    .optimize = optimize,
                }),
            },
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
