const std = @import("std");
const Allocator = std.mem.Allocator;

const math = @import("math.zig");

fn ptrFromAny(comptime T: type, ptr: *anyopaque) *T {
    return @ptrCast(@alignCast(ptr));
}

fn ptrFromAnyOpt(comptime T: type, ptr: ?*anyopaque) ?*T {
    return @ptrCast(@alignCast(ptr));
}

pub fn Grid(comptime Data: type, w: usize, h: usize) type {
    return struct {
        const Self = @This();

        pub const Width: comptime_int = w;
        pub const Height: comptime_int = h;

        const ItemTag = enum {
            grid,
            child,
        };
        const Item = *anyopaque;

        children: [Height][Width]?*anyopaque,
        row: u32,
        col: u32,
        parent: ?*Self,

        pub fn initChild(parent: *Self, row: u32, col: u32) Self {
            return .{
                .children = [_][Width]?*anyopaque{[_]?*anyopaque{null} ** Width} ** Height,
                .row = row,
                .col = col,
                .parent = parent,
            };
        }

        pub fn initParent(child: *anyopaque) Self {
            var self = Self{
                .children = [_][Width]?*anyopaque{[_]?*anyopaque{null} ** Width} ** Height,
                .row = undefined,
                .col = undefined,
                .parent = null,
            };
            self.children[Height / 2][Width / 2] = child;
            return self;
        }

        pub fn deinitChild(self: *Self, allocator: Allocator, level: usize) void {
            for (self.children) |children_row| {
                for (children_row) |maybe_child| {
                    if (maybe_child) |child| {
                        if (level > 0)
                            ptrFromAny(Self, child).deinitChild(allocator, level - 1)
                        else
                            allocator.destroy(ptrFromAny(Data, child));
                    }
                }
            }
            allocator.destroy(self);
        }

        pub fn deinitParent(self: *Self, allocator: Allocator, level: usize) void {
            if (self.parent) |parent|
                parent.deinitParent(allocator, level + 1)
            else
                self.deinitChild(allocator, level);
        }

        pub fn find(self: *Self, allocator: Allocator, x: i32, y: i32, comptime create: bool) if (create) Allocator.Error!*Self else ?*Self {
            const diffX = math.divFloor(x, Width);
            const diffY = math.divFloor(y, Height);

            if (diffX == 0 and diffY == 0)
                return self;

            if (self.parent == null) {
                if (!create)
                    return null;

                const parent = try allocator.create(Self);
                parent.* = initParent(self);

                self.parent = parent;
                self.row = Height / 2;
                self.col = Width / 2;
            }

            const parentX = @as(i32, @intCast(self.col)) + diffX;
            const parentY = @as(i32, @intCast(self.row)) + diffY;

            const nextGen = if (create)
                try self.parent.?.find(allocator, parentX, parentY, create)
            else
                (self.parent.?.find(allocator, parentX, parentY, create) orelse return null);

            const row = math.mod(parentY, Height);
            const col = math.mod(parentX, Width);

            return if (create)
                try nextGen.atOrCreateItem(allocator, .grid, row, col)
            else
                ptrFromAnyOpt(Self, nextGen.children[row][col]);
        }

        fn atOrCreateItem(self: *Self, allocator: Allocator, comptime itemTag: ItemTag, row: usize, col: usize) switch (itemTag) {
            .child => Allocator.Error!*Data,
            .grid => Allocator.Error!*Self,
        } {
            if (self.children[row][col]) |child| {
                return @ptrCast(@alignCast(child));
            }

            const child: *anyopaque = switch (itemTag) {
                .grid => sw: {
                    const child = try allocator.create(Self);
                    child.* = initChild(self, @intCast(row), @intCast(col));
                    break :sw child;
                },
                .child => sw: {
                    const child = try allocator.create(Data);
                    child.* = Data.init(self, @intCast(row), @intCast(col));
                    break :sw child;
                },
            };

            self.children[row][col] = child;
            return @ptrCast(@alignCast(child));
        }

        pub fn atOrCreate(self: *Self, allocator: Allocator, row: usize, col: usize) Allocator.Error!*Data {
            return try self.atOrCreateItem(allocator, .child, row, col);
        }

        pub fn at(self: *Self, row: usize, col: usize) ?*Data {
            return ptrFromAnyOpt(Data, self.children[row][col]);
        }
    };
}
