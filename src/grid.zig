const std = @import("std");
const Allocator = std.mem.Allocator;

const math = @import("math.zig");

pub fn Grid(comptime Data: type) type {
    return struct {
        const Self = @This();

        pub const Width = 16;
        pub const Height = 16;

        const ItemTag = enum {
            grid,
            child,
        };
        const Item = extern union {
            // optional extern union of pointers is twice as big
            ptr: ?*anyopaque,
            grid: *Self,
            child: *Data,
        };

        children: [Height][Width]Item,
        row: u32,
        col: u32,
        parent: ?*Self,

        pub fn initChild(parent: *Self, row: u32, col: u32) Self {
            return .{
                .children = [_][Width]Item{[_]Item{.{ .ptr = null }} ** Width} ** Height,
                .row = row,
                .col = col,
                .parent = parent,
            };
        }

        pub fn initParent(child: Item) Self {
            var self = Self{
                .children = [_][Width]Item{[_]Item{.{ .ptr = null }} ** Width} ** Height,
                .row = undefined,
                .col = undefined,
                .parent = null,
            };
            self.children[Height / 2][Width / 2] = child;
            return self;
        }

        pub fn deinitChild(self: *Self, allocator: Allocator, level: usize) void {
            for (self.children) |children_row| {
                for (children_row) |child| {
                    if (child.ptr != null) {
                        if (level > 0)
                            child.grid.deinitChild(allocator, level - 1)
                        else
                            allocator.destroy(child.child);
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
                parent.* = initParent(.{ .grid = self });

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
                (try nextGen.atOrCreateItem(allocator, .grid, row, col)).grid
            else if (nextGen.children[row][col].ptr != null)
                nextGen.children[row][col].grid
            else
                null;
        }

        fn atOrCreateItem(self: *Self, allocator: Allocator, itemTag: ItemTag, row: usize, col: usize) Allocator.Error!Item {
            if (self.children[row][col].ptr != null)
                return self.children[row][col];

            const child = switch (itemTag) {
                .grid => sw: {
                    const child = Item{ .grid = try allocator.create(Self) };
                    child.grid.* = initChild(self, @intCast(row), @intCast(col));
                    break :sw child;
                },
                .child => sw: {
                    const child = Item{ .child = try allocator.create(Data) };
                    child.child.* = Data.init(self, @intCast(row), @intCast(col));
                    break :sw child;
                },
            };

            self.children[row][col] = child;
            return child;
        }

        pub fn atOrCreate(self: *Self, allocator: Allocator, row: usize, col: usize) Allocator.Error!*Data {
            return (try self.atOrCreateItem(allocator, .child, row, col)).child;
        }

        pub fn at(self: *Self, row: usize, col: usize) ?*Data {
            return if (self.children[row][col].ptr != null)
                self.children[row][col].child
            else
                null;
        }
    };
}
