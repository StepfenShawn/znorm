const std = @import("std");

const Node = struct {
    id: usize,
    vec: []f32,
    neighbors: std.ArrayList(std.ArrayList(usize)),

    const Self = @This();
    fn deinit(self: *Self, alloc: std.mem.Allocator) void {
        for (self.neighbors.items) |*x| {
            x.deinit(alloc);
        }
        self.neighbors.deinit(alloc);
    }
};

const HNSW = struct {
    alloc: std.mem.Allocator,
    nodes: std.ArrayList(Node),
    M: usize,
    ef_construct: usize,
    max_level: usize,
    entry_point: ?usize,
    rng: std.Random.DefaultPrng,

    const Self = @This();

    fn init(alloc: std.mem.Allocator, M: usize, ef_construct: usize) !Self {
        return Self{ .alloc = alloc, .nodes = std.ArrayList(Node).initCapacity(alloc, 0), .M = M, .ef_construct = ef_construct, .max_level = 0, .entry_point = null, .rng = std.Random.DefaultPrng.init(0x12345678) };
    }

    fn deinit(self: *HNSW) void {
        for (self.nodes.items) |*n| n.deinit();
        self.nodes.deinit();
    }
};
