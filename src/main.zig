const std = @import("std");
const c = @cImport(@cInclude("termkey.h"));

const board = @import("state.zig");
const ioctl = @import("ioctl.zig");

pub const CSI = "\x1b[";
const hideCur = CSI ++ "?25l";
const showCur = CSI ++ "?25h";
const reqCursorPos = CSI ++ "6n";

const help = centerMessage(
    \\use    <Arrow keys>                to move
    \\press  q                           to quit
);

fn centerMessage(helpStr: []const u8) struct {
    msg: []const u8,
    w: usize,
    h: usize,
} {
    var ret: []const u8 = "";
    var maxWidth: usize = 0;
    var height: usize = 0;
    var it = std.mem.splitScalar(u8, helpStr, '\n');

    inline while (it.next()) |line| {
        const fullBack = CSI ++ std.fmt.comptimePrint("{d}D", .{line.len});
        ret = ret ++ line ++ fullBack ++ CSI ++ "B";
        maxWidth = @max(maxWidth, line.len);
        height += 1;
    }

    const halfBack = CSI ++ std.fmt.comptimePrint("{d}D", .{maxWidth / 2 + 1});
    return .{ .msg = halfBack ++ CSI ++ "B" ++ ret, .w = maxWidth, .h = height };
}

fn writeAll(bytes: []const u8) std.posix.WriteError!void {
    var offset: usize = 0;

    while (offset < bytes.len) {
        offset += try std.posix.write(1, bytes[offset..]);
    }
}

fn sigwinchHandler(_: c_int) callconv(.C) void {
    writeAll(reqCursorPos) catch {};
}

fn updateDisplay(_: anytype) !void {}

fn handleUnicode(key: *const c.TermKeyKey, _: anytype) bool {
    return key.code.codepoint == 'Q' or key.code.codepoint == 'q';
}

fn handleKeysym(key: *const c.TermKeyKey, state: anytype) !void {
    switch (key.code.sym) {
        c.TERMKEY_SYM_UP => return state.up(),
        c.TERMKEY_SYM_DOWN => return state.down(),
        c.TERMKEY_SYM_LEFT => return state.left(),
        c.TERMKEY_SYM_RIGHT => return state.right(),
        else => {},
    }
}

fn handleWindow(_: *const c.TermKeyKey, state: anytype) !void {
    const ws = try ioctl.getWindowSize(2);
    return state.resize(ws.ws_col, ws.ws_row);
}

fn run(tk: *c.TermKey, state: anytype, bw: anytype) !void {
    var key: c.TermKeyKey = undefined;

    while (c.termkey_waitkey(tk, &key) == c.TERMKEY_RES_KEY) {
        switch (key.type) {
            c.TERMKEY_TYPE_UNICODE => if (handleUnicode(&key, state)) return,
            c.TERMKEY_TYPE_KEYSYM => try handleKeysym(&key, state),
            c.TERMKEY_TYPE_POSITION, c.TERMKEY_TYPE_FUNCTION => try handleWindow(&key, state),
            else => continue,
        }
        try bw.flush();
    }
}

pub fn main() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    // NOTE: we're using termkey, so we use the C allocator
    const allocator = std.heap.c_allocator;

    var sa: std.posix.Sigaction = .{
        .mask = std.posix.empty_sigset,
        .flags = std.posix.SA.RESTART,
        .handler = .{ .handler = sigwinchHandler },
    };
    var fds = [_]std.posix.pollfd{.{ .fd = 0, .events = std.posix.POLL.IN, .revents = undefined }};

    const tk = c.termkey_new(0, c.TERMKEY_FLAG_CTRLC | c.TERMKEY_FLAG_EINTR) orelse return error.TermkeyNew;
    defer c.termkey_destroy(tk);

    try std.posix.sigaction(std.posix.SIG.WINCH, &sa, null);

    var state = try board.state(allocator, stdout);
    defer state.deinit();

    try stdout.writeAll(hideCur);
    defer {
        stdout.print(showCur ++ CSI ++ "{d}H", .{state.h}) catch {};
        bw.flush() catch {};
    }

    if (state.w >= help.w + 4 and state.h > (help.h + 2) * 2)
        try stdout.writeAll(help.msg);

    try bw.flush();

    _ = try std.posix.poll(&fds, -1);

    try state.redraw();
    try bw.flush();

    try run(tk, &state, &bw);
}
