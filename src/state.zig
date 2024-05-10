const std = @import("std");
const root = @import("root");
const Allocator = std.mem.Allocator;

const ioctl = @import("ioctl.zig");
const math = @import("math.zig");
const grid = @import("grid.zig");

const clear = root.CSI ++ "2J";
const halfBlock = "\u{2588}";
const block = "\u{2588}\u{2589}";
const erase = "  ";

fn Uint(comptime size: usize) type {
    return std.meta.Int(.unsigned, size);
}

const Grid = grid.Grid(Board);

pub const Board = struct {
    pub const Width = 64;
    pub const Height = 64;
    pub const BitIndex = std.math.Log2Int(Bits);
    const Bits = Uint(Width);

    bits: [Height]Bits,
    row: u32,
    col: u32,
    parent: *Grid,

    pub fn init(parent: *Grid, row: u32, col: u32) Board {
        return Board{
            .bits = [_]Bits{0} ** Height,
            .row = row,
            .col = col,
            .parent = parent,
        };
    }

    pub fn deinit(self: *Board, allocator: Allocator) void {
        self.parent.deinitParent(allocator, 0);
    }

    pub fn find(self: *Board, allocator: Allocator, x: i32, y: i32, comptime create: bool) if (create) Allocator.Error!*Board else ?*Board {
        const diffX = math.divFloor(x, Width);
        const diffY = math.divFloor(y, Height);

        if (diffX == 0 and diffY == 0)
            return self;

        const parentX = @as(i32, @intCast(self.col)) + diffX;
        const parentY = @as(i32, @intCast(self.row)) + diffY;

        const nextGen = if (create)
            try self.parent.find(allocator, parentX, parentY, create)
        else
            (self.parent.find(allocator, parentX, parentY, create) orelse return null);

        const row = math.mod(parentY, Grid.Height);
        const col = math.mod(parentX, Grid.Width);

        return if (create)
            nextGen.atOrCreate(allocator, row, col)
        else
            nextGen.at(row, col);
    }

    pub fn at(self: Board, row: usize, col: BitIndex) bool {
        return self.bits[row] & @as(Bits, 1) << col != 0;
    }

    pub fn flip(self: *Board, row: usize, col: BitIndex) void {
        self.bits[row] ^= @as(Bits, 1) << col;
    }
};

pub fn state(allocator: Allocator, writer: anytype) !State(@TypeOf(writer)) {
    const StateT = State(@TypeOf(writer));

    const ws = try ioctl.getWindowSize(2);
    const st = try StateT.init(allocator, ws.ws_col, ws.ws_row, writer);
    errdefer st.deinit();

    try writer.writeAll(clear);
    try st.flip();

    return st;
}

pub fn State(comptime Writer: type) type {
    return struct {
        const Self = @This();
        board: *Board,
        x: i32,
        y: i32,
        w: u16,
        h: u16,
        writer: Writer,
        allocator: Allocator,

        pub fn init(allocator: Allocator, width: u16, height: u16, writer: Writer) !Self {
            const parent = try allocator.create(Grid);
            errdefer allocator.destroy(parent);
            const board = try allocator.create(Board);

            parent.* = Grid.initParent(.{ .child = board });
            board.* = Board.init(parent, Grid.Height / 2, Grid.Width / 2);

            return Self{
                .board = board,
                .x = Board.Width / 2,
                .y = Board.Height / 2,
                .w = width,
                .h = height,
                .writer = writer,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: Self) void {
            self.board.deinit(self.allocator);
        }

        pub fn up(self: *Self) !void {
            self.board = try self.board.find(self.allocator, self.x, self.y - 1, true);
            self.y = math.mod(self.y - 1, Board.Height);
            try self.scrollDown(1);
            return self.flip();
        }

        pub fn down(self: *Self) !void {
            self.board = try self.board.find(self.allocator, self.x, self.y + 1, true);
            self.y = math.mod(self.y + 1, Board.Height);
            try self.scrollUp(1);
            return self.flip();
        }

        pub fn left(self: *Self) !void {
            self.board = try self.board.find(self.allocator, self.x - 1, self.y, true);
            self.x = math.mod(self.x - 1, Board.Width);
            self.board.flip(@intCast(self.y), @intCast(self.x));
            return self.redraw();
        }

        pub fn right(self: *Self) !void {
            self.board = try self.board.find(self.allocator, self.x + 1, self.y, true);
            self.x = math.mod(self.x + 1, Board.Width);
            self.board.flip(@intCast(self.y), @intCast(self.x));
            return self.redraw();
        }

        pub fn resize(self: *Self, newW: u16, newH: u16) !void {
            const oldW = self.w;
            const oldH = self.h;
            const oldCy = oldH / 2;
            const newCy = newH / 2;

            self.w = newW;
            self.h = newH;

            // some terminal emulators wrap text while others truncate lines
            // so just redraw if the width changes
            if (oldW != newW) {
                return self.redraw();
            } else if (oldCy < newCy) {
                try self.scrollDown(newCy - oldCy);
            } else if (oldCy > newCy) {
                try self.scrollUp(oldCy - newCy);
            }

            if (oldH + newCy - oldCy < newH)
                try self.drawRows(oldH + newCy - oldCy, newH);
        }

        fn flip(self: Self) !void {
            const cx = self.w / 4 * 2;
            const cy = self.h / 2;
            const row: usize = @intCast(self.y);
            const col: Board.BitIndex = @intCast(self.x);

            self.board.flip(row, col);
            const icon = if (self.board.at(row, col)) block else erase;

            return self.writer.print(root.CSI ++ "{d};{d}H{s}", .{ cy + 1, cx + 1, icon });
        }

        pub fn redraw(self: Self) !void {
            try self.writer.writeAll(clear);
            return self.drawRows(0, self.h);
        }

        fn scrollUp(self: Self, rows: usize) !void {
            try self.writer.print(root.CSI ++ "{d}S", .{rows});
            return self.drawRows(self.h - rows, self.h);
        }

        fn scrollDown(self: Self, rows: usize) !void {
            try self.writer.print(root.CSI ++ "{d}T", .{rows});
            return self.drawRows(0, rows);
        }

        fn drawRows(self: Self, from: usize, to: usize) !void {
            const firstRow = self.y - self.h / 2;
            const startCol = self.x - self.w / 4;
            const endCol = startCol + self.w / 2;

            try self.writer.print(root.CSI ++ "{d}H", .{from + 1});
            for (from..to) |y| {
                const row = firstRow + @as(i32, @intCast(y));
                try self.drawRow(row, startCol, endCol, self.w % 2 > 0);
            }
        }

        fn drawRow(self: Self, y: i32, fromX: i32, toX: i32, lastHalf: bool) !void {
            const row = math.mod(y, Board.Height);
            var x = fromX;
            while (x < toX) : (x += 1) {
                const icon = if (self.board.find(self.allocator, x, y, false)) |board| blk: {
                    const col = math.mod(x, Board.Width);
                    break :blk if (board.at(row, col)) block else erase;
                } else erase;
                try self.writer.writeAll(icon);
            }
            if (lastHalf) {
                if (self.board.find(self.allocator, toX, y, false)) |board| {
                    const col = math.mod(toX, Board.Width);
                    if (board.at(row, col))
                        return self.writer.writeAll(halfBlock);
                }
                try self.writer.writeByte(' ');
            }
        }
    };
}
