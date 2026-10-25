const std = @import("std");

const config = @import("config.zig");
const flags = @import("flags.zig");
const platform = @import("platform.zig");
const sources = @import("sources.zig");

/// Adds everything needed to build Lua: liblua, the stand-alone `lua` and
/// `luac` programs, installed headers, and the `run`/`test` steps. Returns the
/// `liblua` artifact so callers (e.g. the embedding example) can link it.
pub fn build(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.Optimize,
) *std.Build.Step.Compile {
    const options = config.read(b);

    const lua_dep = b.dependency("lua", .{});
    const src = lua_dep.path("src");
    const cflags = flags.forTarget(b, target.result, options);

    const lua_lib = addLibrary(b, src, target, optimize, cflags, options);

    const lua_exe = addProgram(b, .{
        .name = "lua",
        .source = sources.lua_program,
        .src = src,
        .target = target,
        .optimize = optimize,
        .cflags = cflags,
        .lua_lib = lua_lib,
        .config = options,
    });
    installInterpreter(b, lua_exe, target);

    const luac_exe = addProgram(b, .{
        .name = "luac",
        .source = sources.luac_program,
        .src = src,
        .target = target,
        .optimize = optimize,
        .cflags = cflags,
        .lua_lib = lua_lib,
        .config = options,
    });
    b.installArtifact(luac_exe);

    addSteps(b, lua_exe);
    return lua_lib;
}

fn addLibrary(
    b: *std.Build,
    src: std.Build.LazyPath,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.Optimize,
    cflags: []const []const u8,
    options: config.Config,
) *std.Build.Step.Compile {
    const module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    module.addIncludePath(src);
    module.addCSourceFiles(.{
        .root = src,
        .files = &sources.library,
        .flags = cflags,
    });
    platform.linkLibraries(module, target.result, options.readline);

    const lib = b.addLibrary(.{
        .name = "lua",
        .linkage = .static,
        .root_module = module,
    });

    for (sources.headers) |header| {
        lib.installHeader(src.path(b, header), header);
    }
    installConfigHeaders(b, lib, src, options);
    b.installArtifact(lib);
    return lib;
}

const ProgramOptions = struct {
    name: []const u8,
    source: []const u8,
    src: std.Build.LazyPath,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.Optimize,
    cflags: []const []const u8,
    lua_lib: *std.Build.Step.Compile,
    config: config.Config,
};

fn addProgram(b: *std.Build, options: ProgramOptions) *std.Build.Step.Compile {
    const module = b.createModule(.{
        .target = options.target,
        .optimize = options.optimize,
        .link_libc = true,
    });
    module.addIncludePath(options.src);
    module.addCSourceFiles(.{
        .root = options.src,
        .files = &.{options.source},
        .flags = options.cflags,
    });
    module.linkLibrary(options.lua_lib);
    platform.linkLibraries(module, options.target.result, options.config.readline);

    const exe = b.addExecutable(.{
        .name = options.name,
        .root_module = module,
    });
    exe.rdynamic = platform.needsExportDynamic(options.target.result);
    return exe;
}

/// liblua.a and the interpreter would both be artifacts named "lua", which
/// makes `dependency("lua", ...).artifact("lua")` ambiguous for dependents.
/// Installing the executable as a plain file keeps `artifact("lua")`
/// unambiguously pointing at the library while still producing
/// zig-out/bin/lua in the usual way.
fn installInterpreter(
    b: *std.Build,
    lua_exe: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
) void {
    const install_exe = b.addInstallFileWithDir(
        lua_exe.getEmittedBin(),
        .bin,
        b.fmt("lua{s}", .{target.result.exeFileExt()}),
    );
    b.getInstallStep().dependOn(&install_exe.step);

    if (lua_exe.producesPdbFile()) {
        const install_pdb = b.addInstallFileWithDir(
            lua_exe.getEmittedPdb(),
            .bin,
            "lua.pdb",
        );
        b.getInstallStep().dependOn(&install_pdb.step);
    }
}

fn addSteps(b: *std.Build, lua_exe: *std.Build.Step.Compile) void {
    const run_cmd = b.addRunArtifact(lua_exe);
    run_cmd.addPassthruArgs();
    const run_step = b.step("run", "Run the Lua stand-alone interpreter");
    run_step.dependOn(&run_cmd.step);

    // Mirrors `make test`, which executes `./lua -v`.
    const test_cmd = b.addRunArtifact(lua_exe);
    test_cmd.addArg("-v");
    test_cmd.skip_foreign_checks = true;
    const test_step = b.step("test", "Run the stand-alone interpreter's version check");
    test_step.dependOn(&test_cmd.step);
}

/// Installs a generated luaconf.h that applies the selected options and then
/// includes the original header (installed as luaconf_original.h). This keeps
/// ABI-affecting options such as LUA_32BITS in sync between the compiled
/// library and code that later includes the installed headers.
fn installConfigHeaders(
    b: *std.Build,
    lua_lib: *std.Build.Step.Compile,
    src: std.Build.LazyPath,
    options: config.Config,
) void {
    var parts: std.ArrayList([]const u8) = .empty;
    parts.append(b.allocator, "/* Generated by build.zig; do not edit. */\n" ++
        "#ifndef lua_build_config_h\n#define lua_build_config_h\n\n") catch
        @panic("OOM");
    for (config.defines(b, options)) |define| {
        if (define.value) |value| {
            parts.append(b.allocator, b.fmt("#define {s} {s}\n", .{
                define.name,
                value,
            })) catch @panic("OOM");
        } else {
            parts.append(b.allocator, b.fmt("#define {s}\n", .{define.name})) catch
                @panic("OOM");
        }
    }
    parts.append(b.allocator, "\n#include \"luaconf_original.h\"\n\n#endif\n") catch
        @panic("OOM");

    const contents = std.mem.concat(b.allocator, u8, parts.items) catch @panic("OOM");
    const wrapper = b.addWriteFiles().add("luaconf.h", contents);

    lua_lib.installHeader(wrapper, "luaconf.h");
    lua_lib.installHeader(src.path(b, "luaconf.h"), "luaconf_original.h");
}
