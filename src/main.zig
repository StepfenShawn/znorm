const std = @import("std");

pub const VectorDB = struct {
    allocator: std.mem.Allocator,
    dim: usize,
    ids: std.ArrayListUnmanaged(u64),
    vectors: std.ArrayListUnmanaged([]f32),
    deleted: std.ArrayListUnmanaged(bool),

    pub fn init(allocator: std.mem.Allocator, dim: usize) !VectorDB {
        return VectorDB{
            .allocator = allocator,
            .dim = dim,
            .ids = .{ .items = &[0]u64{}, .capacity = 0 },
            .vectors = .{ .items = &[0][]f32{}, .capacity = 0 },
            .deleted = .{ .items = &[0]bool{}, .capacity = 0 },
        };
    }

    pub fn deinit(self: *VectorDB) void {
        for (self.vectors.items) |vec| {
            self.allocator.free(vec);
        }
        self.vectors.deinit(self.allocator);
        self.ids.deinit(self.allocator);
        self.deleted.deinit(self.allocator);
    }

    pub fn insert(self: *VectorDB, id: u64, vector: []const f32) !void {
        if (vector.len != self.dim) {
            return error.InvalidDimension;
        }

        const vec_copy = try self.allocator.alloc(f32, self.dim);
        @memcpy(vec_copy, vector);

        try self.ids.append(self.allocator, id);
        try self.vectors.append(self.allocator, vec_copy);
        try self.deleted.append(self.allocator, false);
    }

    pub fn delete(self: *VectorDB, id: u64) !void {
        for (self.ids.items, 0..) |existing_id, i| {
            if (existing_id == id) {
                self.deleted.items[i] = true;
                return;
            }
        }
        return error.IDNotFound;
    }

    pub fn display(self: *const VectorDB) void {
        std.debug.print("VectorDB (dim={}):\n", .{self.dim});
        for (self.ids.items, self.vectors.items, self.deleted.items) |id, vec, deleted| {
            std.debug.print("   id={d}, vec=[", .{id});
            for (vec, 0..) |v, i| {
                if (i > 0) std.debug.print(", ", .{});
                std.debug.print("{d:.2}", .{v});
            }
            std.debug.print("], deleted={}\n", .{deleted});
        }
    }
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var db = try VectorDB.init(allocator, 3);
    defer db.deinit();

    try db.insert(1, &[_]f32{ 1.0, 0.0, 0.0 });
    try db.insert(2, &[_]f32{ 0.0, 1.0, 0.0 });
    try db.insert(3, &[_]f32{ 0.0, 0.0, 1.0 });

    db.display();

    std.debug.print("Hello, World!\n", .{});
}
