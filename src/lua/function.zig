//! Lua function handles. Arguments and results are passed on the state stack.

const std = @import("std");
const lua = @import("../root.zig");

pub const Function = struct {
    ref: lua.Ref,

    pub fn fromStack(state: *lua.State, idx: c_int) !Function {
        if (!state.isFunction(idx)) return error.TypeMismatch;
        return .{ .ref = lua.Ref.init(state, idx) };
    }

    pub fn push(self: Function) void {
        self.ref.push();
    }

    pub fn clone(self: Function) Function {
        return .{ .ref = self.ref.clone() };
    }

    pub fn deinit(self: *Function) void {
        self.ref.deinit();
    }

    /// Calls the function with the top `nargs` stack values as arguments.
    /// Results replace the arguments and the function on the stack.
    pub fn call(self: Function, nargs: c_int, nresults: c_int) lua.Error!void {
        const state = self.ref.state;
        self.push();
        state.insert(-(nargs + 1));
        try state.pcall(nargs, nresults, 0);
    }
};

test "function handles call with stack arguments" {
    var state = try lua.State.create();
    defer state.deinit();
    state.openLibs();

    var chunk = try state.loadString("return function(a, b) return a + b end");
    try chunk.call(0, 1);
    chunk.deinit();

    var add = try Function.fromStack(&state, -1);
    state.pop(1);
    defer add.deinit();

    state.pushInteger(20);
    state.pushInteger(22);
    try add.call(2, 1);
    defer state.pop(1);

    try std.testing.expectEqual(@as(lua.Integer, 42), state.toInteger(-1).?);
}

test "function failures surface as Zig errors" {
    var state = try lua.State.create();
    defer state.deinit();
    state.openLibs();

    var function = try state.loadString("return function() error('boom') end");
    try function.call(0, 1);
    function.deinit();

    var failing = try Function.fromStack(&state, -1);
    state.pop(1);
    defer failing.deinit();

    try std.testing.expectError(error.Runtime, failing.call(0, 0));

    const message = (try state.popErrorMessage(std.testing.allocator)).?;
    defer std.testing.allocator.free(message);
    try std.testing.expect(std.mem.indexOf(u8, message, "boom") != null);
}
