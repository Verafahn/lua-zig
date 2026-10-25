//! Lua table handles. A `Table` owns a registry reference, so it keeps the
//! table alive independently of the stack.

const std = @import("std");
const lua = @import("../root.zig");

pub const Table = struct {
    ref: lua.Ref,

    pub fn init(state: *lua.State) Table {
        state.createTable(0, 0);
        defer state.pop(1);
        return .{ .ref = lua.Ref.init(state, -1) };
    }

    pub fn fromStack(state: *lua.State, idx: c_int) !Table {
        if (!state.isTable(idx)) return error.TypeMismatch;
        return .{ .ref = lua.Ref.init(state, idx) };
    }

    pub fn push(self: Table) void {
        self.ref.push();
    }

    pub fn clone(self: Table) Table {
        return .{ .ref = self.ref.clone() };
    }

    pub fn deinit(self: *Table) void {
        self.ref.deinit();
    }

    /// Reads and owns a value, honoring `__index`.
    pub fn get(self: Table, allocator: std.mem.Allocator, key: anytype) !lua.Value {
        self.pushKeyed(key, false);
        return self.ref.state.popValue(allocator);
    }

    /// Reads and owns a value without invoking metamethods.
    pub fn getRaw(self: Table, allocator: std.mem.Allocator, key: anytype) !lua.Value {
        self.pushKeyed(key, true);
        return self.ref.state.popValue(allocator);
    }

    pub fn getInteger(self: Table, key: anytype) ?lua.Integer {
        self.pushKeyed(key, false);
        defer self.ref.state.pop(1);
        return self.ref.state.toInteger(-1);
    }

    pub fn getNumber(self: Table, key: anytype) ?lua.Number {
        self.pushKeyed(key, false);
        defer self.ref.state.pop(1);
        return self.ref.state.toNumber(-1);
    }

    pub fn getBoolean(self: Table, key: anytype) ?bool {
        self.pushKeyed(key, false);
        defer self.ref.state.pop(1);
        return if (self.ref.state.isBoolean(-1)) self.ref.state.toBoolean(-1) else null;
    }

    pub fn getString(self: Table, allocator: std.mem.Allocator, key: anytype) !?[]u8 {
        self.pushKeyed(key, false);
        defer self.ref.state.pop(1);
        return self.ref.state.dupeString(allocator, -1);
    }

    pub fn getTable(self: Table, key: anytype) !?Table {
        self.pushKeyed(key, false);
        defer self.ref.state.pop(1);
        if (!self.ref.state.isTable(-1)) return null;
        return try Table.fromStack(self.ref.state, -1);
    }

    pub fn getFunction(self: Table, key: anytype) !?lua.Function {
        self.pushKeyed(key, false);
        defer self.ref.state.pop(1);
        if (!self.ref.state.isFunction(-1)) return null;
        return try lua.Function.fromStack(self.ref.state, -1);
    }

    /// Writes a value, honoring `__newindex`.
    pub fn set(self: Table, key: anytype, value: anytype) void {
        const state = self.ref.state;
        self.push();
        state.pushAny(key);
        state.pushAny(value);
        state.setTable(-3);
        state.pop(1);
    }

    /// Writes a value without invoking metamethods.
    pub fn setRaw(self: Table, key: anytype, value: anytype) void {
        const state = self.ref.state;
        self.push();
        state.pushAny(key);
        state.pushAny(value);
        state.rawSet(-3);
        state.pop(1);
    }

    /// `#table`, honoring `__len`.
    pub fn length(self: Table) lua.Integer {
        const state = self.ref.state;
        self.push();
        defer state.pop(1);
        return state.length(-1);
    }

    pub fn rawLength(self: Table) usize {
        const state = self.ref.state;
        self.push();
        defer state.pop(1);
        return state.rawLen(-1);
    }

    pub fn metatable(self: Table) !?Table {
        const state = self.ref.state;
        self.push();
        defer state.pop(1);
        if (!state.getMetatable(-1)) return null;
        defer state.pop(1);
        return try Table.fromStack(state, -1);
    }

    pub fn setMetatable(self: Table, meta: Table) void {
        const state = self.ref.state;
        std.debug.assert(meta.ref.state == state);
        self.push();
        meta.push();
        state.setMetatable(-2);
        state.pop(1);
    }

    fn pushKeyed(self: Table, key: anytype, comptime raw: bool) void {
        const state = self.ref.state;
        self.push();
        state.pushAny(key);
        if (raw) {
            _ = state.rawGet(-2);
        } else {
            _ = state.pushTable(-2);
        }
        state.remove(-2);
    }

    pub const Entry = struct {
        key: lua.Value,
        value: lua.Value,

        pub fn deinit(self: *Entry, allocator: std.mem.Allocator) void {
            self.key.deinit(allocator);
            self.value.deinit(allocator);
        }
    };

    pub const Iterator = struct {
        table: Table,
        allocator: std.mem.Allocator,
        key_ref: c_int,
        finished: bool,

        pub fn deinit(self: *Iterator) void {
            if (self.key_ref != lua.c.LUA_NOREF) {
                self.table.ref.state.releaseRef(self.key_ref);
                self.key_ref = lua.c.LUA_NOREF;
            }
            self.table.deinit();
        }

        pub fn next(self: *Iterator) !?Entry {
            if (self.finished) return null;

            const state = self.table.ref.state;
            self.table.push();
            if (self.key_ref != lua.c.LUA_NOREF) {
                state.pushRef(self.key_ref);
            } else {
                state.pushNil();
            }

            if (!state.next(-2)) {
                // lua_next already popped the key; only the table remains.
                state.pop(1);
                if (self.key_ref != lua.c.LUA_NOREF) {
                    state.releaseRef(self.key_ref);
                    self.key_ref = lua.c.LUA_NOREF;
                }
                self.finished = true;
                return null;
            }

            // Stack: table, key, value.
            const key = state.toValue(self.allocator, -2) catch |err| {
                state.pop(3);
                return err;
            };
            const value = state.toValue(self.allocator, -1) catch |err| {
                var owned_key = key;
                owned_key.deinit(self.allocator);
                state.pop(3);
                return err;
            };

            if (self.key_ref != lua.c.LUA_NOREF) state.releaseRef(self.key_ref);
            self.key_ref = state.createRef(-2);
            state.pop(3);

            return .{ .key = key, .value = value };
        }
    };

    pub fn iterator(self: Table, allocator: std.mem.Allocator) Iterator {
        return .{
            .table = self.clone(),
            .allocator = allocator,
            .key_ref = lua.c.LUA_NOREF,
            .finished = false,
        };
    }
};

test "tables store primitives across stack changes" {
    var state = try lua.State.create();
    defer state.deinit();
    state.openLibs();

    var table = lua.Table.init(&state);
    defer table.deinit();

    table.set("name", "Lua");
    table.set(1, @as(lua.Integer, 10));
    table.set(true, false);

    const name = (try table.getString(std.testing.allocator, "name")).?;
    defer std.testing.allocator.free(name);
    try std.testing.expectEqualStrings("Lua", name);
    try std.testing.expectEqual(@as(?lua.Integer, 10), table.getInteger(1));
    try std.testing.expectEqual(@as(?bool, false), table.getBoolean(true));
    try std.testing.expectEqual(@as(lua.Integer, 1), table.length());
}

test "tables return table and function handles" {
    var state = try lua.State.create();
    defer state.deinit();
    state.openLibs();

    var table = lua.Table.init(&state);
    defer table.deinit();

    var nested = lua.Table.init(&state);
    defer nested.deinit();
    nested.set("x", @as(lua.Integer, 7));
    table.set("nested", nested);

    var child = (try table.getTable("nested")).?;
    defer child.deinit();
    try std.testing.expectEqual(@as(?lua.Integer, 7), child.getInteger("x"));

    var chunk = try state.loadString("return function(a, b) return a + b end");
    try chunk.call(0, 1);
    chunk.deinit();
    var add = try lua.Function.fromStack(&state, -1);
    state.pop(1);
    defer add.deinit();
    table.set("add", add);

    var add_from_table = (try table.getFunction("add")).?;
    defer add_from_table.deinit();
    state.pushInteger(20);
    state.pushInteger(22);
    try add_from_table.call(2, 1);
    try std.testing.expectEqual(@as(lua.Integer, 42), state.toInteger(-1).?);
    state.pop(1);
}

test "table iteration" {
    var state = try lua.State.create();
    defer state.deinit();

    var table = lua.Table.init(&state);
    defer table.deinit();
    table.set("a", @as(lua.Integer, 1));
    table.set("b", @as(lua.Integer, 2));
    table.set("c", @as(lua.Integer, 3));

    var iterator = table.iterator(std.testing.allocator);
    defer iterator.deinit();

    var sum: lua.Integer = 0;
    var count: usize = 0;
    while (try iterator.next()) |entry_value| {
        var entry = entry_value;
        defer entry.deinit(std.testing.allocator);
        sum += entry.value.asInteger().?;
        count += 1;
    }

    try std.testing.expectEqual(@as(usize, 3), count);
    try std.testing.expectEqual(@as(lua.Integer, 6), sum);
}

test "table metatables honor __index" {
    var state = try lua.State.create();
    defer state.deinit();

    var fallback = lua.Table.init(&state);
    defer fallback.deinit();
    fallback.set("x", @as(lua.Integer, 7));

    var meta = lua.Table.init(&state);
    defer meta.deinit();
    meta.set("__index", fallback);

    var table = lua.Table.init(&state);
    defer table.deinit();
    table.setMetatable(meta);

    try std.testing.expectEqual(@as(?lua.Integer, 7), table.getInteger("x"));

    var read_back = (try table.metatable()).?;
    defer read_back.deinit();
    var index_table = (try read_back.getTable("__index")).?;
    defer index_table.deinit();
    try std.testing.expectEqual(@as(?lua.Integer, 7), index_table.getInteger("x"));
}
