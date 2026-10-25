//! Lua source and header lists, mirroring the upstream Makefile.

/// CORE_O: the Lua core.
pub const core = [_][]const u8{
    "lapi.c",    "lcode.c",    "lctype.c",  "ldebug.c", "ldo.c",
    "ldump.c",   "lfunc.c",    "lgc.c",     "llex.c",   "lmem.c",
    "lobject.c", "lopcodes.c", "lparser.c", "lstate.c", "lstring.c",
    "ltable.c",  "ltm.c",      "lundump.c", "lvm.c",    "lzio.c",
};

/// LIB_O: the standard libraries.
pub const libraries = [_][]const u8{
    "lauxlib.c", "lbaselib.c", "lcorolib.c", "ldblib.c",
    "liolib.c",  "lmathlib.c", "loadlib.c",  "loslib.c",
    "lstrlib.c", "ltablib.c",  "lutf8lib.c", "linit.c",
};

/// BASE_O: everything that goes into liblua.a.
pub const library = core ++ libraries;

/// The stand-alone programs, each compiled against liblua.a.
pub const lua_program = "lua.c";
pub const luac_program = "luac.c";

/// Headers installed alongside the library.
///
/// luaconf.h is not listed here: `lua.installConfigHeaders` generates a wrapper
/// that applies the selected configuration before including the original file.
pub const headers = [_][]const u8{
    "lua.h",
    "lualib.h",
    "lauxlib.h",
    "lua.hpp",
};
