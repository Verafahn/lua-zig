# Lua on Zig

A Zig build for Lua 5.5.1. Lua is fetched as a package dependency from `build.zig.zon`. The build produces a static `liblua`, the standalone `lua` and `luac` executables, installed headers (with a generated `luaconf.h` that reflects the selected configuration), Zig bindings generated via translate-c from those headers, and an embedding example.

The bindings are wrapped in an idiomatic Zig API (`State`, `Table`, `Function`, `Value`, ...) and exposed through a single public module (`lua`, rooted at `src/root.zig`) that links Lua and libc automatically. Requires Zig 0.17.0+; no system Lua installation is needed.

```sh
zig build                              # install liblua, lua, luac, headers
zig build test                         # C smoke test + Zig wrapper tests
zig build run -- -e 'print(_VERSION)'  # extra args are passed to the interpreter
zig build run -- script.lua
zig build exp                          # build and run the embedding example
zig build -Doptimize=fast              # optimized build
zig build --help                       # full list of steps and options
```

The first build requires network access to fetch Lua and the other declared dependencies.

## Outputs

```text
zig-out/
├── bin/lua[.exe]      standalone interpreter
├── bin/luac[.exe]     bytecode compiler
├── lib/liblua.a       static library (liblua.lib for COFF targets)
└── include/           lua.h lualib.h lauxlib.h lua.hpp
                       luaconf.h (generated) + luaconf_original.h
```

The installed `luaconf.h` is a generated wrapper that applies the selected options and then includes `luaconf_original.h`. This ensures ABI-affecting choices also apply to code that uses the installed headers.

## Options

Standard Zig options: `-Dtarget`, `-Dcpu`, `-Dofmt`, `-Doptimize={debug,safe,fast,small}`, `-Ddynamic-linker`.

Lua options map to `luaconf.h` and are applied to the C build, the installed `luaconf.h`, and therefore the generated bindings. They are also accepted as `b.dependency` options (without the `-D` prefix).

| Option | Macro | Default | Effect |
| --- | --- | --- | --- |
| `-Dreadline` | `LUA_USE_READLINE` | `false` | Link GNU readline into the Linux REPL |
| `-Dlua-use-c89` | `LUA_USE_C89` | `false` | Avoid C99 features; also selects `-std=c89`; fails on POSIX targets |
| `-Dlua-32bits` | `LUA_32BITS` | `false` | 32-bit `lua_Integer` and `lua_Number` |
| `-Dlua-compat-global` | `LUA_COMPAT_GLOBAL` | `true` | Keep `global` as a non-reserved word |
| `-Dlua-compat-mathlib` | `LUA_COMPAT_MATHLIB` | `false` | Keep removed math functions |
| `-Dlua-noconv-n2s` | `LUA_NOCVTN2S` | `false` | Disable number-to-string coercion |
| `-Dlua-noconv-s2n` | `LUA_NOCVTS2N` | `false` | Disable string-to-number coercion |
| `-Dlua-use-apicheck` | `LUA_USE_APICHECK` | `false` | Enable C API consistency checks |
| `-Dlua-no-builtin` | `LUA_NOBUILTIN` | `false` | Disable branch-prediction builtins |
| `-Dlua-path-default` | `LUA_PATH_DEFAULT` | header default | `package.path` templates |
| `-Dlua-cpath-default` | `LUA_CPATH_DEFAULT` | header default | `package.cpath` templates |
| `-Dlua-dirsep` | `LUA_DIRSEP` | platform default | Submodule directory separator |
| `-Dlua-readlinelib` | `LUA_READLINELIB` | `"libreadline.so"` on Linux | Runtime readline library name used by the REPL |

`LUA_IDSIZE`, `LUA_EXTRASPACE`, `LUAL_BUFFERSIZE`, `LUA_INT_TYPE`, and `LUA_FLOAT_TYPE` are not exposed as options: `luaconf.h` defines them unconditionally, so `-D` cannot override them. Edit the header directly, or use `-Dlua-32bits` for the common case.

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

ELF targets also set `rdynamic` (`-Wl,-E`) so that C modules loaded at runtime can resolve the Lua API.

## As a dependency

```sh
zig fetch --save git+https://github.com/Verafahn/lua-zig
```

```zig
const lua_dep = b.dependency("lua", .{
    .target = target,
    .optimize = optimize,
    .@"lua-32bits" = true, // any Lua option from above
});

exe.root_module.addImport("lua", lua_dep.module("lua"));
```

`b.dependency` exposes one module and three artifacts:

| Access | Kind | Contents |
| --- | --- | --- |
| `lua_dep.module("lua")` | Zig module | High-level wrapper rooted at `src/root.zig`; links `liblua` and libc automatically |
| `lua_dep.artifact("liblua")` | Static library | Artifact `liblua`, installed as `liblua.a` (`liblua.lib` for COFF targets); `linkLibrary` also propagates the installed headers |
| `lua_dep.artifact("lua")` | Executable | Standalone `lua` interpreter |
| `lua_dep.artifact("luac")` | Executable | `luac` bytecode compiler |

Linking `artifact("liblua")` propagates the include directory, so C code can include `<lua.h>`, `<lualib.h>`, and `<lauxlib.h>` directly. Within `module("lua")`, the raw generated C API is available as `@import("lua").c`.

Everything else — the translate-c output, the filtered C-API module, and the filter executable — is an implementation detail and not part of the public surface. No other modules, named lazy paths, or write-files are intended for consumption. The dependency accepts `.target`, `.optimize`, and every Lua option listed above.

## Embedding

`zig build exp` runs [`examples/minimal.zig`](examples/minimal.zig). The core pattern:

```zig
const std = @import("std");
const lua = @import("lua");

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

`src/bin/filter.zig` generates the private C-API module; `src/root.zig` is the only public entry point and re-exports the per-type handle modules under `src/lua/`. Translation runs at build time against the installed headers (including the generated `luaconf.h`), so numeric types and other configuration-dependent declarations always match the compiled library.

## License

MIT. Lua sources fetched from lua.org remain under Lua's MIT license (© 1994–2026 Lua.org, PUC-Rio).