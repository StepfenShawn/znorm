const std = @import("std");
const filter_mod = @import("filter.zig");
pub const Filter = filter_mod.Filter;

pub const QueryResult = struct {
    id: u64,
    score: f32,
    metadata: ?std.StringHashMap([]const u8) = null,
};

pub const VectorDB = struct {
    allocator: std.mem.Allocator,
    dim: usize,
    ids: std.ArrayListUnmanaged(u64),
    vectors: std.ArrayList(f32),
    deleted: std.ArrayListUnmanaged(bool),
    metadata: std.AutoHashMap(u64, std.StringHashMap([]const u8)),

    pub fn init(allocator: std.mem.Allocator, dim: usize) !VectorDB {
        return VectorDB{
            .allocator = allocator,
            .dim = dim,
            .ids = .{ .items = &[0]u64{}, .capacity = 0 },
            .vectors = .empty,
            .deleted = .{ .items = &[0]bool{}, .capacity = 0 },
            .metadata = std.AutoHashMap(u64, std.StringHashMap([]const u8)).init(allocator),
        };
    }

    pub fn deinit(self: *VectorDB) void {
        self.vectors.deinit(self.allocator);
        self.ids.deinit(self.allocator);
        self.deleted.deinit(self.allocator);
        // Free each key/value string owned by insert/setMetadata before freeing
        // the inner HashMap, so the allocator doesn't leak the duped strings.
        var it = self.metadata.iterator();
        while (it.next()) |entry| {
            var meta_it = entry.value_ptr.iterator();
            while (meta_it.next()) |kv| {
                self.allocator.free(kv.key_ptr.*);
                self.allocator.free(kv.value_ptr.*);
            }
            entry.value_ptr.deinit();
        }
        self.metadata.deinit();
    }

    pub fn insert(self: *VectorDB, id: u64, vector: []const f32) !void {
        if (vector.len != self.dim) {
            return error.InvalidDimension;
        }

        try self.ids.append(self.allocator, id);
        try self.vectors.appendSlice(self.allocator, vector);
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

    pub fn update(self: *VectorDB, id: u64, vector: []const f32) !void {
        if (vector.len != self.dim) {
            return error.InvalidDimension;
        }
        for (self.ids.items, 0..) |existing_id, i| {
            if (existing_id != id) continue;
            if (self.deleted.items[i]) break;
            const dst = self.vectors.items[i * self.dim ..][0..self.dim];
            @memcpy(dst, vector);
            return;
        }
        return error.IDNotFound;
    }

    pub fn cosSimilarity(a: []const f32, b: []const f32) f32 {
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

    pub fn search(self: *const VectorDB, query: []const f32, k: usize, filter: ?[]const Filter) ![]QueryResult {
        if (query.len != self.dim) {
            return error.InvalidDimension;
        }
        const CandidateType = struct { idx: usize, score: f32 };
        var candidates = try std.ArrayList(CandidateType).initCapacity(self.allocator, 0);
        defer candidates.deinit(self.allocator);

        for (self.ids.items, 0..) |_, i| {
            if (self.deleted.items[i]) continue;
            if (filter) |f| {
                const meta = self.metadata.get(self.ids.items[i]);
                if (!try filter_mod.evaluateAll(f, meta)) continue;
            }
            const vec = self.vectors.items[i * self.dim ..][0..self.dim];
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
            const id = self.ids.items[item.idx];
            const meta = self.metadata.get(id);
            result[j] = .{
                .id = id,
                .score = item.score,
                .metadata = meta,
            };
        }
        return result;
    }

    pub fn getMetadata(self: *VectorDB, id: u64) ?*const std.StringHashMap([]const u8) {
        return self.metadata.getPtr(id);
    }

    pub fn setMetadata(self: *VectorDB, id: u64, key: []const u8, value: []const u8) !void {
        const gop = try self.metadata.getOrPut(id);
        if (!gop.found_existing) {
            gop.value_ptr.* = std.StringHashMap([]const u8).init(self.allocator);
        }
        try gop.value_ptr.*.put(
            try self.allocator.dupe(u8, key),
            try self.allocator.dupe(u8, value),
        );
    }

    pub const MetadataEntry = struct {
        key: []const u8,
        value: []const u8,
    };

    pub fn addMetadata(self: *VectorDB, id: u64, items: []const MetadataEntry) !void {
        for (items) |it| {
            try self.setMetadata(id, it.key, it.value);
        }
    }

    pub fn deleteMetadataKey(self: *VectorDB, id: u64, key: []const u8) void {
        if (self.metadata.getPtr(id)) |meta| {
            if (meta.fetchRemove(key)) |kv| {
                self.allocator.free(kv.key);
                self.allocator.free(kv.value);
            }
        }
    }

    pub fn getMetadataValue(self: *const VectorDB, id: u64, key: []const u8) ?[]const u8 {
        const meta = self.metadata.get(id) orelse return null;
        return meta.get(key);
    }

    pub fn removeMetadata(self: *VectorDB, id: u64) void {
        if (self.metadata.fetchRemove(id)) |kv| {
            // Mirror deinit's cleanup: free owned key/value strings before the
            // HashMap itself. fetchRemove already removed the outer entry.
            var meta_it = kv.value.iterator();
            while (meta_it.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                self.allocator.free(entry.value_ptr.*);
            }
            kv.value.deinit();
        }
    }

    pub fn display(self: *const VectorDB) void {
        std.debug.print("VectorDB (dim={}):\n", .{self.dim});
        for (self.ids.items, 0..) |id, i| {
            const vec = self.vectors.items[i * self.dim ..][0..self.dim];
            std.debug.print("   id={d}, vec=[", .{id});
            for (vec, 0..) |v, j| {
                if (j > 0) std.debug.print(", ", .{});
                std.debug.print("{d:.2}", .{v});
            }
            std.debug.print("], deleted={}", .{self.deleted.items[i]});
            if (self.metadata.get(id)) |meta| {
                std.debug.print(", metadata={{", .{});
                var it = meta.iterator();
                var first = true;
                while (it.next()) |entry| {
                    if (!first) std.debug.print(", ", .{});
                    std.debug.print("\"{s}\": \"{s}\"", .{ entry.key_ptr.*, entry.value_ptr.* });
                    first = false;
                }
                std.debug.print("}}", .{});
            }
            std.debug.print("\n", .{});
        }
    }

    pub fn save(self: *const VectorDB, io: std.Io, file_path: []const u8) !void {
        const dir = std.Io.Dir.cwd();
        const file = try dir.createFile(io, file_path, .{});
        defer file.close(io);
        var buffer: [4096]u8 = undefined;
        var writer = file.writer(io, &buffer);

        //  format: "ZVDB" | u64 dim | u64 count | [id+vec]* | u64 meta_count | [id+kv_count+key_value_pairs]*
        try writer.interface.writeAll("ZVDB");
        try writer.interface.writeInt(u64, self.dim, .little);
        var count: u64 = 0;
        for (self.deleted.items) |del| {
            if (!del) count += 1;
        }
        try writer.interface.writeInt(u64, count, .little);

        for (self.ids.items, 0..) |id, i| {
            if (self.deleted.items[i]) continue;
            try writer.interface.writeInt(u64, id, .little);
            const vec = self.vectors.items[i * self.dim ..][0..self.dim];
            for (vec) |v| {
                const bytes = std.mem.asBytes(&v);
                try writer.interface.writeAll(bytes);
            }
        }

        // Metadata section: count of entries with metadata, then for each entry
        // the id, key/value count, and key/value pairs with length-prefixed
        // strings. Deleted vectors' metadata is skipped since they aren't counted.
        var meta_count: u64 = 0;
        for (self.ids.items, 0..) |id, i| {
            if (self.deleted.items[i]) continue;
            if (self.metadata.contains(id)) meta_count += 1;
        }
        try writer.interface.writeInt(u64, meta_count, .little);

        for (self.ids.items, 0..) |id, i| {
            if (self.deleted.items[i]) continue;
            if (self.metadata.get(id)) |meta| {
                try writer.interface.writeInt(u64, id, .little);
                const kv_count: u32 = @intCast(meta.count());
                try writer.interface.writeInt(u32, kv_count, .little);
                var kv_it = meta.iterator();
                while (kv_it.next()) |kv| {
                    const key = kv.key_ptr.*;
                    const val = kv.value_ptr.*;
                    try writer.interface.writeInt(u32, @intCast(key.len), .little);
                    try writer.interface.writeAll(key);
                    try writer.interface.writeInt(u32, @intCast(val.len), .little);
                    try writer.interface.writeAll(val);
                }
            }
        }

        try writer.interface.flush();
    }

    pub fn load(allocator: std.mem.Allocator, io: std.Io, file_path: []const u8) !VectorDB {
        const file = try std.Io.Dir.cwd().openFile(io, file_path, .{});
        defer file.close(io);
        var buffer: [4096]u8 = undefined;
        var reader = file.reader(io, &buffer);

        //  format: "ZVDB" | u64 dim | u64 count | [id+vec]* | u64 meta_count | [id+kv_count+key_value_pairs]*
        const magic = try reader.interface.takeArray(4);
        if (!std.mem.eql(u8, &magic.*, "ZVDB")) return error.InvalidFile;

        const dim = try reader.interface.takeInt(u64, .little);
        const count = try reader.interface.takeInt(u64, .little);

        var db = try VectorDB.init(allocator, @as(usize, @intCast(dim)));
        const count_usize = @as(usize, @intCast(count));
        try db.ids.ensureTotalCapacity(allocator, count_usize);
        try db.vectors.ensureTotalCapacity(allocator, count_usize * @as(usize, @intCast(dim)));
        try db.deleted.ensureTotalCapacity(allocator, count_usize);

        for (0..count_usize) |_| {
            const id = try reader.interface.takeInt(u64, .little);
            const vec = try allocator.alloc(f32, @as(usize, @intCast(dim)));
            defer allocator.free(vec);
            for (vec) |*v| {
                const buf = try reader.interface.takeArray(4);
                v.* = @bitCast(buf.*);
            }
            try db.ids.append(allocator, id);
            try db.vectors.appendSlice(allocator, vec);
            try db.deleted.append(allocator, false);
        }

        // Read metadata section: each entry's key/value pairs are duped into
        // owned memory so the DB owns them independently of the reader buffer.
        const meta_count = try reader.interface.takeInt(u64, .little);
        for (0..@as(usize, @intCast(meta_count))) |_| {
            const id = try reader.interface.takeInt(u64, .little);
            const kv_count = try reader.interface.takeInt(u32, .little);
            var meta = std.StringHashMap([]const u8).init(allocator);
            for (0..@as(usize, @intCast(kv_count))) |_| {
                const key_len = try reader.interface.takeInt(u32, .little);
                const key_buf = try reader.interface.take(key_len);
                const key = try allocator.dupe(u8, key_buf);
                const val_len = try reader.interface.takeInt(u32, .little);
                const val_buf = try reader.interface.take(val_len);
                const val = try allocator.dupe(u8, val_buf);
                try meta.put(key, val);
            }
            try db.metadata.put(id, meta);
        }

        return db;
    }
};
