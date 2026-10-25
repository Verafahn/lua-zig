# Lua on Zig

Zig build for Lua 5.5.1. Lua is pulled from `build.zig.zon` as a package dependency; the build produces a static `liblua`, the standalone `lua` and `luac` programs, installed headers whose `luaconf.h` reflects the selected configuration, Zig bindings generated with translate-c from those headers, and an embedding example. The bindings are exposed through a single public module (`lua`, rooted at `src/root.zig`). Requires Zig 0.17.0+ and no system Lua installation.

```sh
zig build                              # install liblua, lua, luac, headers
zig build uninstall                    # remove installed files
zig build test                         # runs `lua -v`
zig build run -- -e 'print(_VERSION)'  # extra args are passed to the interpreter
zig build run -- script.lua
zig build exp                          # build and run the embedding example
zig build -Doptimize=ReleaseFast       # optimized build
zig build --help                       # full list of steps and options
```

The first build needs network access to fetch Lua and the other declared dependencies.

## Outputs

```text
zig-out/
├── bin/lua[.exe]      standalone interpreter
├── bin/luac[.exe]     bytecode compiler
├── lib/liblua.a       static library
└── include/           lua.h lualib.h lauxlib.h lua.hpp
                       luaconf.h (generated) + luaconf_original.h
```

The installed `luaconf.h` is a generated wrapper that applies the selected options and then includes `luaconf_original.h`, so ABI-affecting choices also apply to code using the installed headers.

## Options

Standard Zig options: `-Dtarget`, `-Dcpu`, `-Dofmt`, `-Doptimize={debug,safe,fast,small}`, `-Ddynamic-linker`.

Lua options map to `luaconf.h` and are applied to the C build, the installed `luaconf.h`, and therefore the generated bindings:

| Option | Macro | Default | Effect |
| --- | --- | --- | --- |
| `-Dreadline` | `LUA_USE_READLINE` | `false` | Linux REPL links GNU readline |
| `-Dlua-use-c89` | `LUA_USE_C89` | `false` | Avoid C99 features; also selects `-std=c89`; fails on POSIX targets |
| `-Dlua-32bits` | `LUA_32BITS` | `false` | 32-bit `lua_Integer` and `lua_Number` |
| `-Dlua-compat-global` | `LUA_COMPAT_GLOBAL` | `true` | Keep `global` as a non-reserved word |
| `-Dlua-compat-mathlib` | `LUA_COMPAT_MATHLIB` | `false` | Keep removed math functions |
| `-Dlua-noconv-n2s` | `LUA_NOCVTN2S` | `false` | Disable number-to-string coercion |
| `-Dlua-noconv-s2n` | `LUA_NOCVTS2N` | `false` | Disable string-to-number coercion |
| `-Dlua-use-apicheck` | `LUA_USE_APICHECK` | `false` | C API consistency checks |
| `-Dlua-no-builtin` | `LUA_NOBUILTIN` | `false` | No branch-prediction builtins |
| `-Dlua-path-default` | `LUA_PATH_DEFAULT` | header default | `package.path` templates |
| `-Dlua-cpath-default` | `LUA_CPATH_DEFAULT` | header default | `package.cpath` templates |
| `-Dlua-dirsep` | `LUA_DIRSEP` | platform default | Submodule directory separator |
| `-Dlua-readlinelib` | `LUA_READLINELIB` | `"libreadline.so"` on Linux | REPL's runtime readline library name |

`LUA_IDSIZE`, `LUA_EXTRASPACE`, `LUAL_BUFFERSIZE`, `LUA_INT_TYPE` and `LUA_FLOAT_TYPE` are not exposed: `luaconf.h` defines them unconditionally, so `-D` cannot override them. Edit the header or use `-Dlua-32bits` for the common case.

## Platforms

| Target | Defines | Link libraries |
| --- | --- | --- |
| Linux | `LUA_USE_LINUX` | readline only with `-Dreadline` |
| macOS | `LUA_USE_MACOSX` | readline |
| FreeBSD / OpenBSD / NetBSD / DragonFly | `LUA_USE_LINUX`, `LUA_USE_READLINE`, `-I/usr/include/edit` | edit |
| iOS | `LUA_USE_IOS` | — |
| illumos | `LUA_USE_POSIX`, `LUA_USE_DLOPEN`, `_REENTRANT` | dl |
| Windows | `LUA_USE_WINDOWS` via `_WIN32` | — |
| Other | generic | — |

ELF targets also set `rdynamic` (`-Wl,-E`) so C modules loaded at runtime can resolve the Lua API.

## As a dependency

```zig
// build.zig.zon
.dependencies = .{
    .lua = .{ .path = "../lua" }, // or use `zig fetch --save <url>`
},
```

```zig
const lua = b.dependency("lua", .{
    .target = target,
    .optimize = optimize,
    .@"lua-32bits" = true, // any Lua option is valid here
});

exe.root_module.link_libc = true;
exe.root_module.linkLibrary(lua.artifact("lua"));
exe.root_module.addImport("lua", lua.module("lua"));
```

`artifact("lua")` is the static library, `artifact("luac")` the compiler, and `module("lua")` the public facade (`src/root.zig`), which re-exports the generated bindings as `lua` (use `@import("lua").lua`). The installed `lua` executable is deliberately not an artifact, keeping `artifact("lua")` unambiguous.

## Embedding

`zig build exp` runs [`examples/minimal.zig`](examples/minimal.zig). The core pattern:

```zig
const std = @import("std");
const lua = @import("lua").lua;

fn hostGreeting(L: ?*lua.lua_State) callconv(.c) c_int {
    const state = L orelse return 0;
    _ = lua.lua_pushstring(state, "Zig");
    return 1;
}

fn run() !void {
    const L = lua.luaL_newstate() orelse return error.OutOfMemory;
    defer lua.lua_close(L);
    lua.luaL_openlibs(L);

    lua.lua_pushcfunction(L, hostGreeting);
    lua.lua_setglobal(L, "host_greeting");

    const chunk =
        \\result = string.format("%s via %s", _VERSION, host_greeting())
    ;
    if (lua.luaL_loadstring(L, chunk.ptr) != 0 or
        lua.lua_pcallk(L, 0, lua.LUA_MULTRET, 0, 0, null) != 0) return error.LuaError;

    _ = lua.lua_getglobal(L, "result");
    var len: usize = 0;
    const result = lua.lua_tolstring(L, -1, &len);
    if (result == null) return error.MissingResult;
    std.debug.print("{s}\n", .{result[0..len]});
}
```

`src/bin/filter.zig` generates the bindings module, and `src/root.zig` is the only public entry point, re-exporting it as `lua`. Translation runs at build time against the installed headers (including the generated `luaconf.h`), so `lua_Integer`, `lua_Number`, and other configuration-dependent declarations always match the compiled library. translate-c's `luaL_dostring` output is not type-correct (the macro `NULL` becomes `?*anyopaque`), hence the explicit `luaL_loadstring` + `lua_pcallk` above.

## Layout

```text
build.zig             project entry: target/optimize, translate-c bindings, example
build/                Lua C build: sources, options, flags, platforms, install, steps
src/root.zig          public module entry, re-exports bindings as `lua`
src/bin/filter.zig    emits the public API subset of the translate-c output
examples/minimal.zig  embedding example
```

## License

MIT. Lua sources fetched from lua.org remain under Lua's MIT license (© 1994–2026 Lua.org, PUC-Rio).
