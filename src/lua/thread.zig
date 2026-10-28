//! Coroutine thread handles.

const std = @import("std");
const lua = @import("../root.zig");

pub const ResumeStatus = enum { ok, yield };

pub const ResumeResult = struct {
    status: ResumeStatus,
    nresults: c_int,
};

pub const Thread = struct {
    ref: lua.Ref,

    pub fn fromStack(state: *lua.State, idx: c_int) !Thread {
        if (!state.isThread(idx)) return error.TypeMismatch;
        return .{ .ref = lua.Ref.init(state, idx) };
    }

    /// Creates a coroutine whose body is `function`.
    pub fn create(state: *lua.State, function: lua.Function) lua.Error!Thread {
        const handle = lua.c.lua_newthread(state.raw) orelse return error.OutOfMemory;
        defer state.pop(1);

        const thread = try Thread.fromStack(state, -1);
        function.push();
        lua.c.lua_xmove(state.raw, handle, 1);
        return thread;
    }

    pub fn push(self: Thread) void {
        self.ref.push();
    }

    pub fn clone(self: Thread) Thread {
        return .{ .ref = self.ref.clone() };
    }

    pub fn deinit(self: *Thread) void {
        self.ref.deinit();
    }

    pub fn raw(self: Thread) ?*lua.RawState {
        const state = self.ref.state;
        self.push();
        defer state.pop(1);
        return state.toThreadPtr(-1);
    }

    pub fn status(self: Thread) lua.ThreadStatus {
        const handle = self.raw() orelse return .unknown;
        return lua.threadStatusFromC(lua.c.lua_status(handle));
    }

    pub fn isYieldable(self: Thread) bool {
        const handle = self.raw() orelse return false;
        return lua.c.lua_isyieldable(handle) != 0;
    }

    /// Resumes the coroutine. Arguments are taken from the top `nargs` values
    /// of the owning state's stack; results are pushed back onto that stack.
    pub fn resumeCoroutine(self: Thread, nargs: c_int) lua.Error!ResumeResult {
        const main = self.ref.state;
        const handle = self.raw() orelse return error.TypeMismatch;

        self.push();
        main.insert(-(nargs + 1));
        lua.c.lua_xmove(main.raw, handle, nargs);
        main.pop(1);

        var nresults: c_int = 0;
        const resume_status = lua.c.lua_resume(handle, main.raw, nargs, &nresults);

        if (resume_status == lua.c.LUA_OK or resume_status == lua.c.LUA_YIELD) {
            lua.c.lua_xmove(handle, main.raw, nresults);
            return .{
                .status = if (resume_status == lua.c.LUA_OK) .ok else .yield,
                .nresults = nresults,
            };
        }

        // Lua leaves the error object on the coroutine's stack.
        lua.c.lua_xmove(handle, main.raw, 1);
        try lua.statusToError(resume_status);
        unreachable;
    }
};

test "threads keep a coroutine alive" {
    var state = try lua.State.create();
    defer state.deinit();
    state.openLibs();

    var thread = try state.newThread();
    defer thread.deinit();

    try std.testing.expectEqual(lua.ThreadStatus.ok, thread.status());
    try std.testing.expect(thread.raw() != null);
}

test "coroutines yield and resume" {
    var state = try lua.State.create();
    defer state.deinit();
    state.openLibs();

    var chunk = try state.loadString(
        "return function() coroutine.yield(10); return 20 end",
    );
    try chunk.call(0, 1);
    chunk.deinit();

    var body = try lua.Function.fromStack(&state, -1);
    state.pop(1);
    defer body.deinit();

    var thread = try Thread.create(&state, body);
    defer thread.deinit();

    var result = try thread.resumeCoroutine(0);
    try std.testing.expectEqual(ResumeStatus.yield, result.status);
    try std.testing.expectEqual(@as(c_int, 1), result.nresults);
    try std.testing.expectEqual(@as(lua.Integer, 10), state.toInteger(-1).?);
    state.pop(1);

    result = try thread.resumeCoroutine(0);
    try std.testing.expectEqual(ResumeStatus.ok, result.status);
    try std.testing.expectEqual(@as(c_int, 1), result.nresults);
    try std.testing.expectEqual(@as(lua.Integer, 20), state.toInteger(-1).?);
    state.pop(1);
}
