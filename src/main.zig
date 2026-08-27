const std = @import("std");

const QueryResult = struct { id: u64, score: f32 };

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

    fn cosSimilarity(a: []const f32, b: []const f32) f32 {
        var dot: f32 = 0.0;
        var norm_a: f32 = 0.0;
        var norm_b: f32 = 0.0;
        for (a, b) |x, y| {
            dot += x * y;
            norm_a += x * x;
            norm_b += y * y;
        }
        if (norm_a == 0.0 or norm_b == 0.0) return 0.0;
        return dot / (@sqrt(norm_a) * @sqrt(norm_b));
    }

    pub fn search(self: *const VectorDB, query: []const f32, k: usize) ![]QueryResult {
        if (query.len != self.dim) {
            return error.InvalidDimension;
        }
        const CandidateType = struct { idx: usize, score: f32 };
        var candidates = try std.ArrayList(CandidateType).initCapacity(self.allocator, 0);
        defer candidates.deinit(self.allocator);

        for (self.vectors.items, 0..) |vec, i| {
            if (self.deleted.items[i]) continue;
            const score = cosSimilarity(query, vec);
            try candidates.append(self.allocator, .{ .idx = i, .score = score });
        }

        std.mem.sort(CandidateType, candidates.items, {}, struct {
            fn cmp(_: void, a: @TypeOf(candidates.items[0]), b: @TypeOf(candidates.items[0])) bool {
                return a.score > b.score;
            }
        }.cmp);

        const result_len = @min(k, candidates.items.len);
        const result = try self.allocator.alloc(QueryResult, result_len);
        for (candidates.items[0..result_len], 0..) |item, j| {
            result[j] = .{ .id = self.ids.items[item.idx], .score = item.score };
        }
        return result;
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

    pub fn save(self: *const VectorDB, io: std.Io, file_path: []const u8) !void {
        const dir = std.Io.Dir.cwd();
        const file = try dir.createFile(io, file_path, .{});
        defer file.close(io);
        var buffer: [4096]u8 = undefined;
        var writer = file.writer(io, &buffer);

        try writer.interface.writeAll("ZVDB");
        try writer.interface.writeInt(u64, self.dim, .little);
        var count: u64 = 0;
        for (self.deleted.items) |del| {
            if (!del) count += 1;
        }
        try writer.interface.writeInt(u64, count, .little);

        for (self.ids.items, self.vectors.items, self.deleted.items) |id, vec, del| {
            if (del) continue;
            try writer.interface.writeInt(u64, id, .little);
            for (vec) |v| {
                const bytes = std.mem.asBytes(&v);
                try writer.interface.writeAll(bytes);
            }
        }

        try writer.interface.flush();
    }

    pub fn load(allocator: std.mem.Allocator, io: std.Io, file_path: []const u8) !VectorDB {
        const file = try std.Io.Dir.cwd().openFile(io, file_path, .{});
        defer file.close(io);
        var buffer: [4096]u8 = undefined;
        var reader = file.reader(io, &buffer);

        const magic = try reader.interface.takeArray(4);
        if (!std.mem.eql(u8, &magic.*, "ZVDB")) return error.InvalidFile;

        const dim = try reader.interface.takeInt(u64, .little);
        const count = try reader.interface.takeInt(u64, .little);

        var db = try VectorDB.init(allocator, @as(usize, @intCast(dim)));
        try db.ids.ensureTotalCapacity(allocator, @as(usize, @intCast(count)));
        try db.vectors.ensureTotalCapacity(allocator, @as(usize, @intCast(count)));
        try db.deleted.ensureTotalCapacity(allocator, @as(usize, @intCast(count)));

        for (0..@as(usize, @intCast(count))) |_| {
            const id = try reader.interface.takeInt(u64, .little);
            const vec = try allocator.alloc(f32, @as(usize, @intCast(dim)));
            for (vec) |*v| {
                const buf = try reader.interface.takeArray(4);
                v.* = @bitCast(buf.*);
            }
            try db.ids.append(allocator, id);
            try db.vectors.append(allocator, vec);
            try db.deleted.append(allocator, false);
        }
        return db;
    }
};

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.page_allocator;

    var db = try VectorDB.init(allocator, 3);
    defer db.deinit();

    try db.insert(1, &[_]f32{ 1.0, 0.0, 0.0 });
    try db.insert(2, &[_]f32{ 0.0, 1.0, 0.0 });
    try db.insert(3, &[_]f32{ 0.0, 0.0, 1.0 });

    db.display();

    const query = [_]f32{ 1.0, 0.5, 0.0 };
    const results = try db.search(&query, 2);
    defer allocator.free(results);

    std.debug.print("Top 2 results:\n", .{});
    for (results) |res| {
        std.debug.print("ID: {}, Score: {d:.3}\n", .{ res.id, res.score });
    }
    try db.save(init.io, "mydb.bin");
}
