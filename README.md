# Lua on Zig

Zig build for Lua 5.5.1. Lua is pulled from `build.zig.zon` as a package dependency; the build produces a static `liblua`, the standalone `lua` and `luac` programs, installed headers whose `luaconf.h` reflects the selected configuration, Zig bindings generated with translate-c from those headers, and an embedding example. The bindings are wrapped in an idiomatic Zig API (`State`, `Table`, `Function`, `Value`, ...) exposed through a single public module (`lua`, rooted at `src/root.zig`) that links Lua and libc automatically. Requires Zig 0.17.0+ and no system Lua installation.

```sh
zig build                              # install liblua, lua, luac, headers
zig build uninstall                    # remove installed files
zig build test                         # C smoke test + Zig wrapper tests
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

exe.root_module.addImport("lua", lua.module("lua"));
```

`module("lua")` links liblua and libc automatically; no `linkLibrary` call is needed. `artifact("lua")` remains available for C interop, and `artifact("luac")` is the compiler. The installed `lua` executable is deliberately not an artifact, keeping `artifact("lua")` unambiguous.

## Zig API

The public module exposes a high-level wrapper under `@import("lua").lua`:

| Type | Purpose |
| --- | --- |
| `State` | interpreter: stack, globals, loading/calls, GC, registry refs, host helpers |
| `Table` | registry-backed table handle: get/set, typed getters, iteration, metatables |
| `Function` | callable handle; arguments/results use the state stack |
| `Userdata` | userdata handle with typed pointer/byte access |
| `Thread` | coroutine handle: create, status, `resumeCoroutine` |
| `Value` | owned value union (strings copied; handles keep registry refs) |

The raw generated C API remains available as `lua.c` for anything not covered by the wrapper. Handles own a registry reference (`clone`/`deinit`); `Value` owns its string or handle payload, with `takeString`/`takeTable`/`takeFunction`/`takeUserdata`/`takeThread` for moving handles out before `deinit`.

## Embedding

`zig build exp` runs [`examples/minimal.zig`](examples/minimal.zig). The core pattern:

```zig
const std = @import("std");
const lua = @import("lua").lua;

fn hostGreeting(raw: ?*lua.RawState) callconv(.c) c_int {
    var state = lua.State.wrap(raw orelse return 0);
    state.pushLiteral("Zig");
    return 1;
}

fn run(allocator: std.mem.Allocator) !void {
    var state = try lua.State.create();
    defer state.deinit();
    state.openLibs();
    state.register("host_greeting", hostGreeting);

    var result = try state.evalString(allocator,
        \\return string.format("%s via %s", host_greeting(), _VERSION)
    );
    defer result.deinit(allocator);
    std.debug.print("{s}\n", .{result.asString().?});
}
```

`src/bin/filter.zig` generates the private C-API module; `src/root.zig` is the only public entry point, re-exporting the wrapper. Translation runs at build time against the installed headers (including the generated `luaconf.h`), so numeric types and other configuration-dependent declarations always match the compiled library.

## Layout

```text
build.zig             project entry: target/optimize, translate-c bindings, example
build/                Lua C build: sources, options, flags, platforms, install, steps
src/root.zig          public module: re-exports the wrapper as `lua`
src/lua.zig           State, Value, Ref, errors, stack/global/call/GC API
src/lua/table.zig     Table handle, typed access, iteration
src/lua/function.zig  Function handle, calls
src/lua/userdata.zig  Userdata handle
src/lua/thread.zig    Coroutine handle, resume
src/bin/filter.zig    emits the private C API subset
examples/minimal.zig  embedding example
```

## License

MIT. Lua sources fetched from lua.org remain under Lua's MIT license (© 1994–2026 Lua.org, PUC-Rio).
