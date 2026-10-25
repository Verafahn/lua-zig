//! Userdata handles. The raw memory can be accessed as bytes or as a typed
//! pointer via `as`.

const std = @import("std");
const lua = @import("../root.zig");

pub const Userdata = struct {
    ref: lua.Ref,

    pub fn fromStack(state: *lua.State, idx: c_int) !Userdata {
        if (!state.isUserdata(idx)) return error.TypeMismatch;
        return .{ .ref = lua.Ref.init(state, idx) };
    }

    pub fn push(self: Userdata) void {
        self.ref.push();
    }

    pub fn clone(self: Userdata) Userdata {
        return .{ .ref = self.ref.clone() };
    }

    pub fn deinit(self: *Userdata) void {
        self.ref.deinit();
    }

    pub fn pointer(self: Userdata) ?*anyopaque {
        const state = self.ref.state;
        self.push();
        defer state.pop(1);
        return state.toUserdataPtr(-1);
    }

    /// Size of the userdata block in bytes.
    pub fn size(self: Userdata) usize {
        const state = self.ref.state;
        self.push();
        defer state.pop(1);
        return state.rawLen(-1);
    }

    pub fn as(self: Userdata, comptime T: type) ?*T {
        const ptr = self.pointer() orelse return null;
        return @ptrCast(@alignCast(ptr));
    }
};

test "userdata handles expose typed memory" {
    var state = try lua.State.create();
    defer state.deinit();

    const value = state.newUserdataTyped(u32);
    value.* = 1234;

    var userdata = try Userdata.fromStack(&state, -1);
    state.pop(1);
    defer userdata.deinit();

    try std.testing.expectEqual(@as(usize, @sizeOf(u32)), userdata.size());
    try std.testing.expectEqual(@as(u32, 1234), userdata.as(u32).?.*);
}

test "byte userdata" {
    var state = try lua.State.create();
    defer state.deinit();

    const bytes = state.newUserdata(4);
    @memcpy(bytes, "abcd");

    var userdata = try Userdata.fromStack(&state, -1);
    state.pop(1);
    defer userdata.deinit();

    try std.testing.expectEqual(@as(usize, 4), userdata.size());
    try std.testing.expectEqualStrings(
        "abcd",
        @as([*]const u8, @ptrCast(userdata.pointer().?))[0..4],
    );
}
