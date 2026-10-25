//! High-level, idiomatic Zig bindings for Lua 5.5.
//!
//! The C API is generated from the installed Lua headers and is available as
//! `c` as an escape hatch. Most code should use `State`, `Table`, `Function`,
//! `Userdata`, `Thread` and `Value`.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Raw, generated C bindings.
pub const c = @import("ffi");

pub const Table = @import("lua/table.zig").Table;
pub const Function = @import("lua/function.zig").Function;
pub const Userdata = @import("lua/userdata.zig").Userdata;
pub const Thread = @import("lua/thread.zig").Thread;

pub const Integer = c.lua_Integer;
pub const Number = c.lua_Number;
pub const CFunction = c.lua_CFunction;
pub const RawState = c.lua_State;

pub const registry_index = c.LUA_REGISTRYINDEX;
pub const multi_return = c.LUA_MULTRET;

pub const Error = error{
    OutOfMemory,
    Runtime,
    Syntax,
    Memory,
    ErrorInErrorHandler,
    File,
    TypeMismatch,
};

/// Lua value kinds, matching the C `LUA_T*` constants.
pub const Type = enum(c_int) {
    none = -1,
    nil = 0,
    boolean = 1,
    light_userdata = 2,
    number = 3,
    string = 4,
    table = 5,
    function = 6,
    userdata = 7,
    thread = 8,
    _,
};

pub const ArithOp = enum(c_int) {
    add = 0,
    sub = 1,
    mul = 2,
    mod = 3,
    pow = 4,
    div = 5,
    idiv = 6,
    band = 7,
    bor = 8,
    bxor = 9,
    shl = 10,
    shr = 11,
    unm = 12,
    bnot = 13,
};

pub const CompareOp = enum(c_int) {
    equal = 0,
    less_than = 1,
    less_equal = 2,
};

pub const ThreadStatus = enum {
    ok,
    yield,
    runtime_error,
    syntax_error,
    memory_error,
    error_in_error_handler,
    file_error,
    unknown,
};

pub fn statusToError(status: c_int) Error!void {
    return switch (status) {
        c.LUA_OK => {},
        c.LUA_ERRRUN => error.Runtime,
        c.LUA_ERRSYNTAX => error.Syntax,
        c.LUA_ERRMEM => error.OutOfMemory,
        c.LUA_ERRERR => error.ErrorInErrorHandler,
        c.LUA_ERRFILE => error.File,
        else => error.Runtime,
    };
}

pub fn threadStatusFromC(status: c_int) ThreadStatus {
    return switch (status) {
        c.LUA_OK => .ok,
        c.LUA_YIELD => .yield,
        c.LUA_ERRRUN => .runtime_error,
        c.LUA_ERRSYNTAX => .syntax_error,
        c.LUA_ERRMEM => .memory_error,
        c.LUA_ERRERR => .error_in_error_handler,
        c.LUA_ERRFILE => .file_error,
        else => .unknown,
    };
}

/// A Lua interpreter state.
///
/// `deinit` closes the state; copies of a `State` do not own the state and
/// must not be deinitialized.
pub const State = struct {
    handle: *RawState,

    /// Creates a new state with Lua's default allocator.
    pub fn create() Error!State {
        const handle = c.luaL_newstate() orelse return error.OutOfMemory;
        return .{ .handle = handle };
    }

    /// Wraps a raw state without taking ownership. Useful inside C callbacks.
    pub fn wrap(handle: *RawState) State {
        return .{ .handle = handle };
    }

    /// Closes the state. Must be called exactly once for the owning `State`.
    pub fn deinit(self: *State) void {
        c.lua_close(self.handle);
        self.* = undefined;
    }

    /// Raw C state, for APIs not covered by this wrapper.
    pub fn raw(self: *State) *RawState {
        return self.handle;
    }

    pub fn version(self: *State) Number {
        return c.lua_version(self.handle);
    }

    pub fn openLibs(self: *State) void {
        c.luaL_openlibs(self.handle);
    }

    // -----------------------------------------------------------------
    // Stack
    // -----------------------------------------------------------------

    pub fn getTop(self: *State) c_int {
        return c.lua_gettop(self.handle);
    }

    pub fn absIndex(self: *State, idx: c_int) c_int {
        return c.lua_absindex(self.handle, idx);
    }

    pub fn checkStack(self: *State, extra: c_int) bool {
        return c.lua_checkstack(self.handle, extra) != 0;
    }

    pub fn setTop(self: *State, idx: c_int) void {
        c.lua_settop(self.handle, idx);
    }

    pub fn pop(self: *State, n: c_int) void {
        c.lua_settop(self.handle, -n - 1);
    }

    pub fn pushValue(self: *State, idx: c_int) void {
        c.lua_pushvalue(self.handle, idx);
    }

    pub fn copy(self: *State, from: c_int, to: c_int) void {
        c.lua_copy(self.handle, from, to);
    }

    pub fn remove(self: *State, idx: c_int) void {
        c.lua_remove(self.handle, idx);
    }

    pub fn insert(self: *State, idx: c_int) void {
        c.lua_insert(self.handle, idx);
    }

    pub fn replace(self: *State, idx: c_int) void {
        c.lua_replace(self.handle, idx);
    }

    pub fn rotate(self: *State, idx: c_int, n: c_int) void {
        c.lua_rotate(self.handle, idx, n);
    }

    pub fn xmove(self: *State, to: *State, n: c_int) void {
        c.lua_xmove(self.handle, to.handle, n);
    }

    // -----------------------------------------------------------------
    // Types and conversions
    // -----------------------------------------------------------------

    pub fn typeOf(self: *State, idx: c_int) Type {
        return @fromBackingInt(@intCast(c.lua_type(self.handle, idx)));
    }

    pub fn typeName(self: *State, value_type: Type) []const u8 {
        const ptr = c.lua_typename(self.handle, @backingInt(value_type));
        return ptr[0..std.mem.len(ptr)];
    }

    pub fn isNone(self: *State, idx: c_int) bool {
        return self.typeOf(idx) == .none;
    }

    pub fn isNil(self: *State, idx: c_int) bool {
        return self.typeOf(idx) == .nil;
    }

    pub fn isNoneOrNil(self: *State, idx: c_int) bool {
        return self.typeOf(idx) == .none or self.typeOf(idx) == .nil;
    }

    pub fn isBoolean(self: *State, idx: c_int) bool {
        return self.typeOf(idx) == .boolean;
    }

    pub fn isNumber(self: *State, idx: c_int) bool {
        return c.lua_isnumber(self.handle, idx) != 0;
    }

    pub fn isInteger(self: *State, idx: c_int) bool {
        return c.lua_isinteger(self.handle, idx) != 0;
    }

    pub fn isString(self: *State, idx: c_int) bool {
        return c.lua_isstring(self.handle, idx) != 0;
    }

    pub fn isTable(self: *State, idx: c_int) bool {
        return self.typeOf(idx) == .table;
    }

    pub fn isFunction(self: *State, idx: c_int) bool {
        return self.typeOf(idx) == .function;
    }

    pub fn isCFunction(self: *State, idx: c_int) bool {
        return c.lua_iscfunction(self.handle, idx) != 0;
    }

    pub fn isUserdata(self: *State, idx: c_int) bool {
        return self.typeOf(idx) == .userdata;
    }

    pub fn isLightUserdata(self: *State, idx: c_int) bool {
        return self.typeOf(idx) == .light_userdata;
    }

    pub fn isThread(self: *State, idx: c_int) bool {
        return self.typeOf(idx) == .thread;
    }

    pub fn toBoolean(self: *State, idx: c_int) bool {
        return c.lua_toboolean(self.handle, idx) != 0;
    }

    pub fn toInteger(self: *State, idx: c_int) ?Integer {
        var is_num: c_int = 0;
        const value = c.lua_tointegerx(self.handle, idx, &is_num);
        return if (is_num != 0) value else null;
    }

    pub fn toNumber(self: *State, idx: c_int) ?Number {
        var is_num: c_int = 0;
        const value = c.lua_tonumberx(self.handle, idx, &is_num);
        return if (is_num != 0) value else null;
    }

    /// Returns a borrowed string; it is valid while the value remains on the
    /// stack (or is otherwise reachable).
    pub fn toString(self: *State, idx: c_int) ?[]const u8 {
        var len: usize = 0;
        const ptr = c.lua_tolstring(self.handle, idx, &len);
        if (ptr == null) return null;
        return ptr[0..len];
    }

    pub fn dupeString(self: *State, allocator: Allocator, idx: c_int) !?[]u8 {
        const value = self.toString(idx) orelse return null;
        return try allocator.dupe(u8, value);
    }

    /// Like `toString`, but honors `__tostring` and returns an owned copy.
    pub fn toDisplayString(self: *State, allocator: Allocator, idx: c_int) !?[]u8 {
        var len: usize = 0;
        const ptr = c.luaL_tolstring(self.handle, idx, &len);
        if (ptr == null) return null;
        defer self.pop(1);
        return allocator.dupe(u8, ptr[0..len]);
    }

    pub fn toCFunction(self: *State, idx: c_int) ?CFunction {
        return c.lua_tocfunction(self.handle, idx);
    }

    pub fn toUserdataPtr(self: *State, idx: c_int) ?*anyopaque {
        return c.lua_touserdata(self.handle, idx);
    }

    pub fn toPointer(self: *State, idx: c_int) ?*const anyopaque {
        return c.lua_topointer(self.handle, idx);
    }

    pub fn toThreadPtr(self: *State, idx: c_int) ?*RawState {
        return c.lua_tothread(self.handle, idx);
    }

    pub fn rawLen(self: *State, idx: c_int) usize {
        return c.lua_rawlen(self.handle, idx);
    }

    // -----------------------------------------------------------------
    // Pushing values
    // -----------------------------------------------------------------

    pub fn pushNil(self: *State) void {
        c.lua_pushnil(self.handle);
    }

    pub fn pushBoolean(self: *State, value: bool) void {
        c.lua_pushboolean(self.handle, @intFromBool(value));
    }

    pub fn pushInteger(self: *State, value: Integer) void {
        c.lua_pushinteger(self.handle, value);
    }

    pub fn pushNumber(self: *State, value: Number) void {
        c.lua_pushnumber(self.handle, value);
    }

    pub fn pushSlice(self: *State, value: []const u8) void {
        _ = c.lua_pushlstring(self.handle, value.ptr, value.len);
    }

    pub fn pushString(self: *State, value: [:0]const u8) void {
        _ = c.lua_pushstring(self.handle, value.ptr);
    }

    pub fn pushLiteral(self: *State, comptime value: []const u8) void {
        _ = c.lua_pushlstring(self.handle, value.ptr, value.len);
    }

    pub fn pushLightUserdata(self: *State, ptr: ?*anyopaque) void {
        c.lua_pushlightuserdata(self.handle, ptr);
    }

    pub fn pushCFunction(self: *State, function: CFunction) void {
        _ = c.lua_pushcclosure(self.handle, function, 0);
    }

    pub fn pushClosure(self: *State, function: CFunction, upvalues: c_int) void {
        _ = c.lua_pushcclosure(self.handle, function, upvalues);
    }

    pub fn pushThread(self: *State) bool {
        return c.lua_pushthread(self.handle) != 0;
    }

    /// Pushes a C function and stores it in a global.
    pub fn register(self: *State, name: [:0]const u8, function: CFunction) void {
        self.pushCFunction(function);
        self.setGlobal(name);
    }

    // -----------------------------------------------------------------
    // Host function helpers
    // -----------------------------------------------------------------

    pub fn checkAny(self: *State, arg: c_int) void {
        c.luaL_checkany(self.handle, arg);
    }

    pub fn checkType(self: *State, arg: c_int, value_type: Type) void {
        c.luaL_checktype(self.handle, arg, @backingInt(value_type));
    }

    pub fn checkInteger(self: *State, arg: c_int) Integer {
        return c.luaL_checkinteger(self.handle, arg);
    }

    pub fn optInteger(self: *State, arg: c_int, default: Integer) Integer {
        return c.luaL_optinteger(self.handle, arg, default);
    }

    pub fn checkNumber(self: *State, arg: c_int) Number {
        return c.luaL_checknumber(self.handle, arg);
    }

    pub fn optNumber(self: *State, arg: c_int, default: Number) Number {
        return c.luaL_optnumber(self.handle, arg, default);
    }

    pub fn checkString(self: *State, arg: c_int) []const u8 {
        var len: usize = 0;
        const ptr = c.luaL_checklstring(self.handle, arg, &len);
        return ptr[0..len];
    }

    pub fn optString(self: *State, arg: c_int, default: [:0]const u8) []const u8 {
        var len: usize = 0;
        const ptr = c.luaL_optlstring(self.handle, arg, default.ptr, &len);
        return ptr[0..len];
    }

    pub fn argError(self: *State, arg: c_int, message: [:0]const u8) noreturn {
        _ = c.luaL_argerror(self.handle, arg, message.ptr);
        unreachable;
    }

    pub fn getMetaField(self: *State, idx: c_int, name: [:0]const u8) bool {
        return c.luaL_getmetafield(self.handle, idx, name.ptr) != 0;
    }

    pub fn callMeta(self: *State, idx: c_int, name: [:0]const u8) bool {
        return c.luaL_callmeta(self.handle, idx, name.ptr) != 0;
    }

    pub fn traceback(self: *State, message: ?[:0]const u8, level: c_int) void {
        c.luaL_traceback(
            self.handle,
            self.handle,
            if (message) |m| m.ptr else null,
            level,
        );
    }

    /// Loads a standard library through `luaL_requiref`.
    pub fn requireLib(self: *State, name: [:0]const u8, open_fn: CFunction) void {
        c.luaL_requiref(self.handle, name.ptr, open_fn, 1);
        self.pop(1);
    }

    /// Pushes any supported Zig value: nil, booleans, integers, floats,
    /// strings, `Value`, `Table`, `Function`, `Userdata`, or `Thread`.
    pub fn pushAny(self: *State, value: anytype) void {
        const T = @TypeOf(value);
        if (T == Value) return value.push(self);
        if (T == Table) {
            std.debug.assert(value.ref.state == self);
            return value.push();
        }
        if (T == Function) {
            std.debug.assert(value.ref.state == self);
            return value.push();
        }
        if (T == Userdata) {
            std.debug.assert(value.ref.state == self);
            return value.push();
        }
        if (T == Thread) {
            std.debug.assert(value.ref.state == self);
            return value.push();
        }
        if (T == CFunction) return self.pushCFunction(value);

        switch (@typeInfo(T)) {
            .null => self.pushNil(),
            .bool => self.pushBoolean(value),
            .int, .comptime_int => self.pushInteger(@intCast(value)),
            .float, .comptime_float => self.pushNumber(@floatCast(value)),
            .optional => {
                if (value) |inner| self.pushAny(inner) else self.pushNil();
            },
            .pointer => |info| {
                if (info.size == .slice and info.child == u8) {
                    self.pushSlice(value);
                } else if (info.size == .one) {
                    switch (@typeInfo(info.child)) {
                        .array => |array| {
                            if (array.child != u8) {
                                @compileError("unsupported Lua value type: " ++ @typeName(T));
                            }
                            self.pushSlice(value[0..]);
                        },
                        else => @compileError("unsupported Lua pointer type: " ++ @typeName(T)),
                    }
                } else {
                    @compileError("unsupported Lua pointer type: " ++ @typeName(T));
                }
            },
            else => @compileError("unsupported Lua value type: " ++ @typeName(T)),
        }
    }

    // -----------------------------------------------------------------
    // Globals and fields
    // -----------------------------------------------------------------

    pub fn pushGlobal(self: *State, name: [:0]const u8) Type {
        return @fromBackingInt(@intCast(c.lua_getglobal(self.handle, name.ptr)));
    }

    pub fn setGlobal(self: *State, name: [:0]const u8) void {
        c.lua_setglobal(self.handle, name.ptr);
    }

    pub fn setGlobalValue(self: *State, name: [:0]const u8, value: anytype) void {
        self.pushAny(value);
        self.setGlobal(name);
    }

    pub fn getGlobalValue(self: *State, allocator: Allocator, name: [:0]const u8) !Value {
        _ = self.pushGlobal(name);
        return self.popValue(allocator);
    }

    pub fn pushGlobalTable(self: *State) void {
        _ = c.lua_rawgeti(self.handle, registry_index, @as(Integer, c.LUA_RIDX_GLOBALS));
    }

    pub fn globalTable(self: *State) Table {
        self.pushGlobalTable();
        defer self.pop(1);
        return Table.fromStack(self, -1) catch unreachable;
    }

    pub fn pushField(self: *State, idx: c_int, name: [:0]const u8) Type {
        return @fromBackingInt(@intCast(c.lua_getfield(self.handle, idx, name.ptr)));
    }

    pub fn setField(self: *State, idx: c_int, name: [:0]const u8) void {
        c.lua_setfield(self.handle, idx, name.ptr);
    }

    pub fn pushTable(self: *State, idx: c_int) Type {
        return @fromBackingInt(@intCast(c.lua_gettable(self.handle, idx)));
    }

    pub fn setTable(self: *State, idx: c_int) void {
        c.lua_settable(self.handle, idx);
    }

    pub fn pushIntegerField(self: *State, idx: c_int, key: Integer) Type {
        return @fromBackingInt(@intCast(c.lua_geti(self.handle, idx, key)));
    }

    pub fn setIntegerField(self: *State, idx: c_int, key: Integer) void {
        c.lua_seti(self.handle, idx, key);
    }

    pub fn rawGet(self: *State, idx: c_int) Type {
        return @fromBackingInt(@intCast(c.lua_rawget(self.handle, idx)));
    }

    pub fn rawSet(self: *State, idx: c_int) void {
        c.lua_rawset(self.handle, idx);
    }

    pub fn rawGetInteger(self: *State, idx: c_int, key: Integer) Type {
        return @fromBackingInt(@intCast(c.lua_rawgeti(self.handle, idx, key)));
    }

    pub fn rawSetInteger(self: *State, idx: c_int, key: Integer) void {
        c.lua_rawseti(self.handle, idx, key);
    }

    pub fn rawGetPointer(self: *State, idx: c_int, ptr: ?*const anyopaque) Type {
        return @fromBackingInt(@intCast(c.lua_rawgetp(self.handle, idx, ptr)));
    }

    pub fn rawSetPointer(self: *State, idx: c_int, ptr: ?*const anyopaque) void {
        c.lua_rawsetp(self.handle, idx, ptr);
    }

    pub fn createTable(self: *State, array_size: c_int, record_size: c_int) void {
        c.lua_createtable(self.handle, array_size, record_size);
    }

    pub fn newTable(self: *State) Table {
        self.createTable(0, 0);
        defer self.pop(1);
        return Table.fromStack(self, -1) catch unreachable;
    }

    pub fn newThread(self: *State) Error!Thread {
        _ = c.lua_newthread(self.handle) orelse return error.OutOfMemory;
        defer self.pop(1);
        return Thread.fromStack(self, -1);
    }

    pub fn length(self: *State, idx: c_int) Integer {
        return c.luaL_len(self.handle, idx);
    }

    pub fn next(self: *State, idx: c_int) bool {
        return c.lua_next(self.handle, idx) != 0;
    }

    pub fn concat(self: *State, count: c_int) void {
        c.lua_concat(self.handle, count);
    }

    pub fn rawEqual(self: *State, idx1: c_int, idx2: c_int) bool {
        return c.lua_rawequal(self.handle, idx1, idx2) != 0;
    }

    pub fn compare(self: *State, idx1: c_int, idx2: c_int, op: CompareOp) bool {
        return c.lua_compare(self.handle, idx1, idx2, @backingInt(op)) != 0;
    }

    pub fn arith(self: *State, op: ArithOp) void {
        c.lua_arith(self.handle, @backingInt(op));
    }

    // -----------------------------------------------------------------
    // Metatables and userdata
    // -----------------------------------------------------------------

    pub fn getMetatable(self: *State, idx: c_int) bool {
        return c.lua_getmetatable(self.handle, idx) != 0;
    }

    pub fn setMetatable(self: *State, idx: c_int) void {
        _ = c.lua_setmetatable(self.handle, idx);
    }

    pub fn newMetatable(self: *State, name: [:0]const u8) bool {
        return c.luaL_newmetatable(self.handle, name.ptr) != 0;
    }

    /// Sets the metatable named `name` on the value at the top of the stack.
    pub fn setNamedMetatable(self: *State, name: [:0]const u8) void {
        c.luaL_setmetatable(self.handle, name.ptr);
    }

    pub fn testUserdata(self: *State, idx: c_int, name: [:0]const u8) ?*anyopaque {
        return c.luaL_testudata(self.handle, idx, name.ptr);
    }

    /// Allocates userdata and returns a writable byte slice.
    pub fn newUserdata(self: *State, size: usize) []u8 {
        const ptr = c.lua_newuserdatauv(self.handle, size, 0) orelse
            self.raise("out of memory");
        const bytes: [*]u8 = @ptrCast(ptr);
        return bytes[0..size];
    }

    /// Allocates userdata sized and aligned for `T`.
    pub fn newUserdataTyped(self: *State, comptime T: type) *T {
        const ptr = c.lua_newuserdatauv(self.handle, @sizeOf(T), 0) orelse
            self.raise("out of memory");
        return @ptrCast(@alignCast(ptr));
    }

    pub fn toUserdata(self: *State, comptime T: type, idx: c_int) ?*T {
        const ptr = c.lua_touserdata(self.handle, idx) orelse return null;
        return @ptrCast(@alignCast(ptr));
    }

    pub fn getIUserValue(self: *State, idx: c_int, n: c_int) Type {
        return @fromBackingInt(@intCast(c.lua_getiuservalue(self.handle, idx, n)));
    }

    pub fn setIUserValue(self: *State, idx: c_int, n: c_int) Type {
        return @fromBackingInt(@intCast(c.lua_setiuservalue(self.handle, idx, n)));
    }

    // -----------------------------------------------------------------
    // Calls, loading and errors
    // -----------------------------------------------------------------

    pub fn call(self: *State, nargs: c_int, nresults: c_int) void {
        c.lua_callk(self.handle, nargs, nresults, 0, null);
    }

    pub fn pcall(self: *State, nargs: c_int, nresults: c_int, error_func: c_int) Error!void {
        const status = c.lua_pcallk(
            self.handle,
            nargs,
            nresults,
            error_func,
            0,
            null,
        );
        try statusToError(status);
    }

    pub fn loadBuffer(
        self: *State,
        code: []const u8,
        chunk_name: ?[:0]const u8,
        mode: ?[:0]const u8,
    ) Error!void {
        const status = c.luaL_loadbufferx(
            self.handle,
            code.ptr,
            code.len,
            if (chunk_name) |name| name.ptr else null,
            if (mode) |m| m.ptr else null,
        );
        try statusToError(status);
    }

    /// Loads a chunk and returns it as a callable handle.
    pub fn loadString(self: *State, code: []const u8) Error!Function {
        try self.loadBuffer(code, "=(string)", null);
        defer self.pop(1);
        return Function.fromStack(self, -1);
    }

    pub fn doString(self: *State, code: []const u8) Error!void {
        try self.loadBuffer(code, "=(dostring)", null);
        try self.pcall(0, 0, 0);
    }

    /// Executes a chunk that returns exactly one value.
    pub fn evalString(self: *State, allocator: Allocator, code: []const u8) Error!Value {
        try self.loadBuffer(code, "=(eval)", null);
        try self.pcall(0, 1, 0);
        return self.popValue(allocator);
    }

    /// Loads a file and returns it as a callable handle.
    pub fn loadFile(self: *State, path: [:0]const u8) Error!Function {
        const status = c.luaL_loadfilex(self.handle, path.ptr, null);
        try statusToError(status);
        defer self.pop(1);
        return Function.fromStack(self, -1);
    }

    pub fn doFile(self: *State, path: [:0]const u8) Error!void {
        const status = c.luaL_loadfilex(self.handle, path.ptr, null);
        try statusToError(status);
        try self.pcall(0, 0, 0);
    }

    /// Raises a Lua error from a host function.
    pub fn raise(self: *State, message: []const u8) noreturn {
        _ = c.lua_pushlstring(self.handle, message.ptr, message.len);
        _ = c.lua_error(self.handle);
        unreachable;
    }

    /// Pops the error object left behind by a failed `pcall`/`load`.
    pub fn popErrorMessage(self: *State, allocator: Allocator) !?[]u8 {
        if (self.getTop() == 0) return null;
        const message = try self.dupeString(allocator, -1);
        self.pop(1);
        return message;
    }

    // -----------------------------------------------------------------
    // Registry references
    // -----------------------------------------------------------------

    pub fn createRef(self: *State, idx: c_int) c_int {
        const absolute = c.lua_absindex(self.handle, idx);
        c.lua_pushvalue(self.handle, absolute);
        return c.luaL_ref(self.handle, registry_index);
    }

    pub fn releaseRef(self: *State, reference: c_int) void {
        c.luaL_unref(self.handle, registry_index, reference);
    }

    pub fn pushRef(self: *State, reference: c_int) void {
        _ = c.lua_rawgeti(self.handle, registry_index, reference);
    }

    // -----------------------------------------------------------------
    // Values
    // -----------------------------------------------------------------

    pub fn toValue(self: *State, allocator: Allocator, idx: c_int) Error!Value {
        return switch (self.typeOf(idx)) {
            .none => error.TypeMismatch,
            .nil => .nil,
            .boolean => .{ .boolean = self.toBoolean(idx) },
            .number => if (self.isInteger(idx))
                .{ .integer = self.toInteger(idx).? }
            else
                .{ .number = self.toNumber(idx).? },
            .string => .{ .string = try allocator.dupe(u8, self.toString(idx).?) },
            .table => .{ .table = try Table.fromStack(self, idx) },
            .function => .{ .function = try Function.fromStack(self, idx) },
            .userdata => .{ .userdata = try Userdata.fromStack(self, idx) },
            .thread => .{ .thread = try Thread.fromStack(self, idx) },
            .light_userdata => .{ .light_userdata = self.toUserdataPtr(idx) },
            _ => error.TypeMismatch,
        };
    }

    pub fn popValue(self: *State, allocator: Allocator) Error!Value {
        const value = try self.toValue(allocator, -1);
        self.pop(1);
        return value;
    }

    // -----------------------------------------------------------------
    // Garbage collection
    // -----------------------------------------------------------------

    pub fn collectGarbage(self: *State) void {
        _ = c.lua_gc(self.handle, c.LUA_GCCOLLECT, @as(c_int, 0));
    }

    pub fn stopGarbageCollector(self: *State) void {
        _ = c.lua_gc(self.handle, c.LUA_GCSTOP, @as(c_int, 0));
    }

    pub fn restartGarbageCollector(self: *State) void {
        _ = c.lua_gc(self.handle, c.LUA_GCRESTART, @as(c_int, 0));
    }

    pub fn garbageCollectorStep(self: *State, kilobytes: c_int) bool {
        return c.lua_gc(self.handle, c.LUA_GCSTEP, kilobytes) != 0;
    }

    pub fn isGarbageCollectorRunning(self: *State) bool {
        return c.lua_gc(self.handle, c.LUA_GCISRUNNING, @as(c_int, 0)) != 0;
    }

    pub fn garbageCollectorCount(self: *State) usize {
        const kb = c.lua_gc(self.handle, c.LUA_GCCOUNT, @as(c_int, 0));
        const bytes = c.lua_gc(self.handle, c.LUA_GCCOUNTB, @as(c_int, 0));
        return @as(usize, @intCast(kb)) * 1024 + @as(usize, @intCast(bytes));
    }
};

/// Shared owning reference into Lua's registry.
pub const Ref = struct {
    state: *State,
    index: c_int,

    pub fn init(state: *State, idx: c_int) Ref {
        return .{ .state = state, .index = state.createRef(idx) };
    }

    pub fn push(self: Ref) void {
        self.state.pushRef(self.index);
    }

    pub fn clone(self: Ref) Ref {
        self.push();
        return .{
            .state = self.state,
            .index = c.luaL_ref(self.state.handle, registry_index),
        };
    }

    pub fn deinit(self: *Ref) void {
        self.state.releaseRef(self.index);
        self.* = undefined;
    }
};

/// An owned Lua value.
///
/// Strings are copied with the allocator passed to `deinit`/`clone`; reference
/// values own a registry reference. Copying a `Value` without `clone` is a
/// double-free hazard.
pub const Value = union(enum) {
    nil,
    boolean: bool,
    integer: Integer,
    number: Number,
    string: []u8,
    table: Table,
    function: Function,
    userdata: Userdata,
    thread: Thread,
    light_userdata: ?*anyopaque,

    pub fn push(self: Value, state: *State) void {
        switch (self) {
            .nil => state.pushNil(),
            .boolean => |value| state.pushBoolean(value),
            .integer => |value| state.pushInteger(value),
            .number => |value| state.pushNumber(value),
            .string => |value| state.pushSlice(value),
            .table => |value| {
                std.debug.assert(value.ref.state == state);
                value.push();
            },
            .function => |value| {
                std.debug.assert(value.ref.state == state);
                value.push();
            },
            .userdata => |value| {
                std.debug.assert(value.ref.state == state);
                value.push();
            },
            .thread => |value| {
                std.debug.assert(value.ref.state == state);
                value.push();
            },
            .light_userdata => |value| state.pushLightUserdata(value),
        }
    }

    pub fn deinit(self: *Value, allocator: Allocator) void {
        switch (self.*) {
            .string => |value| allocator.free(value),
            .table => |*value| value.deinit(),
            .function => |*value| value.deinit(),
            .userdata => |*value| value.deinit(),
            .thread => |*value| value.deinit(),
            else => {},
        }
        self.* = .nil;
    }

    pub fn clone(self: Value, allocator: Allocator) !Value {
        return switch (self) {
            .string => |value| .{ .string = try allocator.dupe(u8, value) },
            .table => |value| .{ .table = value.clone() },
            .function => |value| .{ .function = value.clone() },
            .userdata => |value| .{ .userdata = value.clone() },
            .thread => |value| .{ .thread = value.clone() },
            else => self,
        };
    }

    pub fn isNil(self: Value) bool {
        return self == .nil;
    }

    pub fn asBoolean(self: Value) ?bool {
        return switch (self) {
            .boolean => |value| value,
            else => null,
        };
    }

    pub fn asInteger(self: Value) ?Integer {
        return switch (self) {
            .integer => |value| value,
            else => null,
        };
    }

    pub fn asNumber(self: Value) ?Number {
        return switch (self) {
            .integer => |value| @floatFromInt(value),
            .number => |value| value,
            else => null,
        };
    }

    pub fn asString(self: Value) ?[]const u8 {
        return switch (self) {
            .string => |value| value,
            else => null,
        };
    }

    /// Moves the string out of the value, leaving it nil.
    pub fn takeString(self: *Value) ?[]u8 {
        return switch (self.*) {
            .string => |value| blk: {
                self.* = .nil;
                break :blk value;
            },
            else => null,
        };
    }

    /// Moves the table handle out of the value, leaving it nil.
    pub fn takeTable(self: *Value) ?Table {
        return switch (self.*) {
            .table => |value| blk: {
                self.* = .nil;
                break :blk value;
            },
            else => null,
        };
    }

    /// Moves the function handle out of the value, leaving it nil.
    pub fn takeFunction(self: *Value) ?Function {
        return switch (self.*) {
            .function => |value| blk: {
                self.* = .nil;
                break :blk value;
            },
            else => null,
        };
    }

    /// Moves the userdata handle out of the value, leaving it nil.
    pub fn takeUserdata(self: *Value) ?Userdata {
        return switch (self.*) {
            .userdata => |value| blk: {
                self.* = .nil;
                break :blk value;
            },
            else => null,
        };
    }

    /// Moves the thread handle out of the value, leaving it nil.
    pub fn takeThread(self: *Value) ?Thread {
        return switch (self.*) {
            .thread => |value| blk: {
                self.* = .nil;
                break :blk value;
            },
            else => null,
        };
    }
};

// ---------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------

test "state executes code and reads globals" {
    var state = try State.create();
    defer state.deinit();
    state.openLibs();

    try state.doString("answer = 40 + 2");
    _ = state.pushGlobal("answer");
    defer state.pop(1);

    try std.testing.expectEqual(@as(Integer, 42), state.toInteger(-1).?);
}

test "evalString returns an owned string" {
    var state = try State.create();
    defer state.deinit();
    state.openLibs();

    var value = try state.evalString(std.testing.allocator, "return 'hello ' .. _VERSION");
    defer value.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("hello Lua 5.5", value.string);
}

test "syntax errors leave a readable message" {
    var state = try State.create();
    defer state.deinit();

    try std.testing.expectError(error.Syntax, state.doString("function"));

    const message = (try state.popErrorMessage(std.testing.allocator)).?;
    defer std.testing.allocator.free(message);
    try std.testing.expect(message.len != 0);
}

test "stack manipulation" {
    var state = try State.create();
    defer state.deinit();

    state.pushInteger(1);
    state.pushInteger(2);
    state.pushInteger(3);
    try std.testing.expectEqual(@as(c_int, 3), state.getTop());

    state.insert(1);
    try std.testing.expectEqual(@as(Integer, 3), state.toInteger(1).?);
    try std.testing.expectEqual(@as(Integer, 1), state.toInteger(2).?);

    state.remove(1);
    try std.testing.expectEqual(@as(c_int, 2), state.getTop());
}

test "values keep reference types alive" {
    var state = try State.create();
    defer state.deinit();
    state.openLibs();

    var value = try state.evalString(std.testing.allocator, "return { answer = 42 }");
    defer value.deinit(std.testing.allocator);

    var table = value.takeTable().?;
    defer table.deinit();

    try std.testing.expectEqual(@as(?Integer, 42), table.getInteger("answer"));
}

test "garbage collector controls" {
    var state = try State.create();
    defer state.deinit();
    state.openLibs();

    const before = state.garbageCollectorCount();
    try std.testing.expect(before > 0);
    try std.testing.expect(state.isGarbageCollectorRunning());

    state.stopGarbageCollector();
    try std.testing.expect(!state.isGarbageCollectorRunning());
    state.restartGarbageCollector();
    state.collectGarbage();
}

fn hostAdd(raw: ?*RawState) callconv(.c) c_int {
    var state = State.wrap(raw orelse return 0);
    const a = state.checkInteger(1);
    const b = state.checkInteger(2);
    state.pushInteger(a + b);
    return 1;
}

test "host functions check arguments" {
    var state = try State.create();
    defer state.deinit();
    state.openLibs();

    state.register("host_add", hostAdd);

    var value = try state.evalString(std.testing.allocator, "return host_add(20, 22)");
    defer value.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(?Integer, 42), value.asInteger());
}

test {
    _ = @import("lua/table.zig");
    _ = @import("lua/function.zig");
    _ = @import("lua/userdata.zig");
    _ = @import("lua/thread.zig");
}
