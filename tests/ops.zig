const std = @import("std");
const VectorDB = @import("vector_db").VectorDB;
const Filter = @import("vector_db").Filter;
const testing = std.testing;

fn getTestIo() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

test "insert and search returns nearest neighbor" {
    const allocator = testing.allocator;

    var db = try VectorDB.init(allocator, 3);
    defer db.deinit();

    try db.insert(1, &[_]f32{ 1.0, 0.0, 0.0 });
    try db.insert(2, &[_]f32{ 0.0, 1.0, 0.0 });
    try db.insert(3, &[_]f32{ 0.0, 0.0, 1.0 });

    const query = [_]f32{ 1.0, 0.0, 0.0 };
    const results = try db.search(&query, 1, null);
    defer allocator.free(results);

    try testing.expectEqual(@as(usize, 1), results.len);
    try testing.expectEqual(@as(u64, 1), results[0].id);
    try testing.expectApproxEqAbs(@as(f32, 1.0), results[0].score, 1e-6);
}

test "metadata is returned in search results" {
    const allocator = testing.allocator;

    var db = try VectorDB.init(allocator, 2);
    defer db.deinit();

    try db.insert(10, &[_]f32{ 1.0, 0.0 });
    try db.setMetadata(10, "label", "hello");

    const query = [_]f32{ 1.0, 0.0 };
    const results = try db.search(&query, 1, null);
    defer allocator.free(results);

    try testing.expect(results[0].metadata != null);
    const value = results[0].metadata.?.get("label");
    try testing.expect(value != null);
    try testing.expectEqualStrings("hello", value.?);
}

test "deleted vector is excluded from search" {
    const allocator = testing.allocator;

    var db = try VectorDB.init(allocator, 2);
    defer db.deinit();

    try db.insert(1, &[_]f32{ 1.0, 0.0 });
    try db.insert(2, &[_]f32{ 0.9, 0.1 });

    try db.delete(1);

    const query = [_]f32{ 1.0, 0.0 };
    const results = try db.search(&query, 2, null);
    defer allocator.free(results);

    try testing.expectEqual(@as(usize, 1), results.len);
    try testing.expectEqual(@as(u64, 2), results[0].id);
}

test "filter eq string — match" {
    const allocator = testing.allocator;

    var db = try VectorDB.init(allocator, 3);
    defer db.deinit();

    try db.insert(1, &[_]f32{ 1.0, 0.0, 0.0 });
    try db.setMetadata(1, "category", "science");

    try db.insert(2, &[_]f32{ 0.9, 0.1, 0.0 });
    try db.setMetadata(2, "category", "art");

    try db.insert(3, &[_]f32{ 0.8, 0.2, 0.0 });
    try db.setMetadata(3, "category", "science");

    const query = [_]f32{ 1.0, 0.0, 0.0 };
    const filters = [_]Filter{.{ .eq = .{ .key = "category", .value = .{ .string = "science" } } }};
    const results = try db.search(&query, 10, &filters);
    defer allocator.free(results);

    try testing.expectEqual(@as(usize, 2), results.len);
    for (results) |r| {
        try testing.expect(r.id == 1 or r.id == 3);
    }
}

test "filter eq string — no match" {
    const allocator = testing.allocator;

    var db = try VectorDB.init(allocator, 3);
    defer db.deinit();

    try db.insert(1, &[_]f32{ 1.0, 0.0, 0.0 });
    try db.setMetadata(1, "category", "science");

    const query = [_]f32{ 1.0, 0.0, 0.0 };
    const filters = [_]Filter{.{ .eq = .{ .key = "category", .value = .{ .string = "art" } } }};
    const results = try db.search(&query, 10, &filters);
    defer allocator.free(results);

    try testing.expectEqual(@as(usize, 0), results.len);
}

test "filter gt int" {
    const allocator = testing.allocator;

    var db = try VectorDB.init(allocator, 2);
    defer db.deinit();

    try db.insert(1, &[_]f32{ 1.0, 0.0 });
    try db.setMetadata(1, "year", "2023");

    try db.insert(2, &[_]f32{ 0.9, 0.1 });
    try db.setMetadata(2, "year", "2019");

    try db.insert(3, &[_]f32{ 0.8, 0.2 });
    try db.setMetadata(3, "year", "2025");

    const query = [_]f32{ 1.0, 0.0 };
    const filters = [_]Filter{.{ .gt = .{ .key = "year", .value = .{ .int = 2020 } } }};
    const results = try db.search(&query, 10, &filters);
    defer allocator.free(results);

    try testing.expectEqual(@as(usize, 2), results.len);
    for (results) |r| {
        try testing.expect(r.id == 1 or r.id == 3);
    }
}

test "filter lt int" {
    const allocator = testing.allocator;

    var db = try VectorDB.init(allocator, 2);
    defer db.deinit();

    try db.insert(1, &[_]f32{ 1.0, 0.0 });
    try db.setMetadata(1, "year", "2023");

    try db.insert(2, &[_]f32{ 0.9, 0.1 });
    try db.setMetadata(2, "year", "2019");

    const query = [_]f32{ 1.0, 0.0 };
    const filters = [_]Filter{.{ .lt = .{ .key = "year", .value = .{ .int = 2020 } } }};
    const results = try db.search(&query, 10, &filters);
    defer allocator.free(results);

    try testing.expectEqual(@as(usize, 1), results.len);
    try testing.expectEqual(@as(u64, 2), results[0].id);
}

test "filter multiple conditions (AND via slice)" {
    const allocator = testing.allocator;

    var db = try VectorDB.init(allocator, 2);
    defer db.deinit();

    try db.insert(1, &[_]f32{ 1.0, 0.0 });
    try db.addMetadata(1, &[_]VectorDB.MetadataEntry{
        .{ .key = "category", .value = "science" },
        .{ .key = "year", .value = "2023" },
    });

    try db.insert(2, &[_]f32{ 0.9, 0.1 });
    try db.addMetadata(2, &[_]VectorDB.MetadataEntry{
        .{ .key = "category", .value = "science" },
        .{ .key = "year", .value = "2018" },
    });

    try db.insert(3, &[_]f32{ 0.8, 0.2 });
    try db.addMetadata(3, &[_]VectorDB.MetadataEntry{
        .{ .key = "category", .value = "art" },
        .{ .key = "year", .value = "2023" },
    });

    const query = [_]f32{ 1.0, 0.0 };
    const filters = [_]Filter{
        .{ .eq = .{ .key = "category", .value = .{ .string = "science" } } },
        .{ .gt = .{ .key = "year", .value = .{ .int = 2020 } } },
    };
    const results = try db.search(&query, 10, &filters);
    defer allocator.free(results);

    try testing.expectEqual(@as(usize, 1), results.len);
    try testing.expectEqual(@as(u64, 1), results[0].id);
}

test "filter null returns all" {
    const allocator = testing.allocator;

    var db = try VectorDB.init(allocator, 2);
    defer db.deinit();

    try db.insert(1, &[_]f32{ 1.0, 0.0 });
    try db.insert(2, &[_]f32{ 0.9, 0.1 });

    const query = [_]f32{ 1.0, 0.0 };
    const results = try db.search(&query, 10, null);
    defer allocator.free(results);

    try testing.expectEqual(@as(usize, 2), results.len);
}

test "filter missing key excludes vector" {
    const allocator = testing.allocator;

    var db = try VectorDB.init(allocator, 2);
    defer db.deinit();

    try db.insert(1, &[_]f32{ 1.0, 0.0 });
    try db.setMetadata(1, "category", "science");

    try db.insert(2, &[_]f32{ 0.9, 0.1 });

    const query = [_]f32{ 1.0, 0.0 };
    const filters = [_]Filter{.{ .eq = .{ .key = "category", .value = .{ .string = "science" } } }};
    const results = try db.search(&query, 10, &filters);
    defer allocator.free(results);

    try testing.expectEqual(@as(usize, 1), results.len);
    try testing.expectEqual(@as(u64, 1), results[0].id);
}

test "filter explicit or" {
    const allocator = testing.allocator;

    var db = try VectorDB.init(allocator, 3);
    defer db.deinit();

    try db.insert(1, &[_]f32{ 1.0, 0.0, 0.0 });
    try db.setMetadata(1, "category", "science");

    try db.insert(2, &[_]f32{ 0.9, 0.1, 0.0 });
    try db.setMetadata(2, "category", "art");

    try db.insert(3, &[_]f32{ 0.8, 0.2, 0.0 });
    try db.setMetadata(3, "category", "music");

    const query = [_]f32{ 1.0, 0.0, 0.0 };
    const f = Filter{ .@"or" = &[_]Filter{
        .{ .eq = .{ .key = "category", .value = .{ .string = "science" } } },
        .{ .eq = .{ .key = "category", .value = .{ .string = "art" } } },
    } };
    const filters = [_]Filter{f};
    const results = try db.search(&query, 10, &filters);
    defer allocator.free(results);

    try testing.expectEqual(@as(usize, 2), results.len);
    for (results) |r| {
        try testing.expect(r.id == 1 or r.id == 2);
    }
}

test "save and load preserves vectors" {
    const allocator = testing.allocator;
    const io = getTestIo();
    const file_path = "test_save_vectors.bin";

    {
        var db = try VectorDB.init(allocator, 3);
        defer db.deinit();

        try db.insert(1, &[_]f32{ 1.0, 0.0, 0.0 });
        try db.insert(2, &[_]f32{ 0.0, 1.0, 0.0 });

        try db.save(io, file_path);
    }

    {
        var db = try VectorDB.load(allocator, io, file_path);
        defer db.deinit();

        try testing.expectEqual(@as(usize, 2), db.ids.items.len);

        const query = [_]f32{ 1.0, 0.0, 0.0 };
        const results = try db.search(&query, 10, null);
        defer allocator.free(results);

        try testing.expectEqual(@as(usize, 2), results.len);
        try testing.expectEqual(@as(u64, 1), results[0].id);
    }

    std.Io.Dir.cwd().deleteFile(io, file_path) catch {};
}

test "save and load preserves metadata" {
    const allocator = testing.allocator;
    const io = getTestIo();
    const file_path = "test_save_meta.bin";

    {
        var db = try VectorDB.init(allocator, 3);
        defer db.deinit();

        try db.insert(1, &[_]f32{ 1.0, 0.0, 0.0 });
        try db.setMetadata(1, "category", "science");

        try db.insert(2, &[_]f32{ 0.0, 1.0, 0.0 });
        try db.setMetadata(2, "category", "art");

        try db.save(io, file_path);
    }

    {
        var db = try VectorDB.load(allocator, io, file_path);
        defer db.deinit();

        const meta1 = db.getMetadata(1);
        try testing.expect(meta1 != null);
        try testing.expectEqualStrings("science", meta1.?.get("category").?);

        const meta2 = db.getMetadata(2);
        try testing.expect(meta2 != null);
        try testing.expectEqualStrings("art", meta2.?.get("category").?);
    }

    std.Io.Dir.cwd().deleteFile(io, file_path) catch {};
}

test "save and load metadata with filter search" {
    const allocator = testing.allocator;
    const io = getTestIo();
    const file_path = "test_save_filter.bin";

    {
        var db = try VectorDB.init(allocator, 3);
        defer db.deinit();

        try db.insert(1, &[_]f32{ 1.0, 0.0, 0.0 });
        try db.setMetadata(1, "category", "science");

        try db.insert(2, &[_]f32{ 0.9, 0.1, 0.0 });
        try db.setMetadata(2, "category", "art");

        try db.insert(3, &[_]f32{ 0.8, 0.2, 0.0 });
        try db.setMetadata(3, "category", "science");

        try db.save(io, file_path);
    }

    {
        var db = try VectorDB.load(allocator, io, file_path);
        defer db.deinit();

        const query = [_]f32{ 1.0, 0.0, 0.0 };
        const filters = [_]Filter{.{ .eq = .{ .key = "category", .value = .{ .string = "science" } } }};
        const results = try db.search(&query, 10, &filters);
        defer allocator.free(results);

        try testing.expectEqual(@as(usize, 2), results.len);
        for (results) |r| {
            try testing.expect(r.id == 1 or r.id == 3);
        }
    }

    std.Io.Dir.cwd().deleteFile(io, file_path) catch {};
}

test "save and load with no metadata" {
    const allocator = testing.allocator;
    const io = getTestIo();
    const file_path = "test_save_nometa.bin";

    {
        var db = try VectorDB.init(allocator, 2);
        defer db.deinit();

        try db.insert(1, &[_]f32{ 1.0, 0.0 });
        try db.insert(2, &[_]f32{ 0.0, 1.0 });

        try db.save(io, file_path);
    }

    {
        var db = try VectorDB.load(allocator, io, file_path);
        defer db.deinit();

        try testing.expectEqual(@as(usize, 2), db.ids.items.len);
        try testing.expect(db.getMetadata(1) == null);
        try testing.expect(db.getMetadata(2) == null);
    }

    std.Io.Dir.cwd().deleteFile(io, file_path) catch {};
}

test "save and load with deleted vectors" {
    const allocator = testing.allocator;
    const io = getTestIo();
    const file_path = "test_save_deleted.bin";

    {
        var db = try VectorDB.init(allocator, 2);
        defer db.deinit();

        try db.insert(1, &[_]f32{ 1.0, 0.0 });
        try db.setMetadata(1, "category", "science");

        try db.insert(2, &[_]f32{ 0.0, 1.0 });
        try db.setMetadata(2, "category", "art");

        try db.delete(1);
        try db.save(io, file_path);
    }

    {
        var db = try VectorDB.load(allocator, io, file_path);
        defer db.deinit();

        try testing.expectEqual(@as(usize, 1), db.ids.items.len);
        try testing.expectEqual(@as(u64, 2), db.ids.items[0]);

        const meta2 = db.getMetadata(2);
        try testing.expect(meta2 != null);
        try testing.expectEqualStrings("art", meta2.?.get("category").?);

        try testing.expect(db.getMetadata(1) == null);
    }

    std.Io.Dir.cwd().deleteFile(io, file_path) catch {};
}

test "save and load with multiple metadata keys" {
    const allocator = testing.allocator;
    const io = getTestIo();
    const file_path = "test_save_multi_meta.bin";

    {
        var db = try VectorDB.init(allocator, 3);
        defer db.deinit();

        try db.insert(1, &[_]f32{ 1.0, 0.0, 0.0 });
        try db.addMetadata(1, &[_]VectorDB.MetadataEntry{
            .{ .key = "category", .value = "science" },
            .{ .key = "year", .value = "2023" },
            .{ .key = "author", .value = "alice" },
        });

        try db.insert(2, &[_]f32{ 0.0, 1.0, 0.0 });
        try db.addMetadata(2, &[_]VectorDB.MetadataEntry{
            .{ .key = "category", .value = "art" },
            .{ .key = "year", .value = "2024" },
        });

        try db.save(io, file_path);
    }

    {
        var db = try VectorDB.load(allocator, io, file_path);
        defer db.deinit();

        const meta1 = db.getMetadata(1);
        try testing.expect(meta1 != null);
        try testing.expectEqualStrings("science", meta1.?.get("category").?);
        try testing.expectEqualStrings("2023", meta1.?.get("year").?);
        try testing.expectEqualStrings("alice", meta1.?.get("author").?);

        const meta2 = db.getMetadata(2);
        try testing.expect(meta2 != null);
        try testing.expectEqualStrings("art", meta2.?.get("category").?);
        try testing.expectEqualStrings("2024", meta2.?.get("year").?);
    }

    std.Io.Dir.cwd().deleteFile(io, file_path) catch {};
}

test "update replaces vector and keeps metadata" {
    const allocator = testing.allocator;

    var db = try VectorDB.init(allocator, 3);
    defer db.deinit();

    try db.insert(1, &[_]f32{ 1.0, 0.0, 0.0 });
    try db.setMetadata(1, "category", "science");

    // 把 id=1 的向量改到靠近 id=3 的方向,搜索结果应随之改变。
    try db.update(1, &[_]f32{ 0.0, 0.0, 1.0 });

    const query = [_]f32{ 0.0, 0.0, 1.0 };
    const results = try db.search(&query, 1, null);
    defer allocator.free(results);

    try testing.expectEqual(@as(u64, 1), results[0].id);
    const value = results[0].metadata.?.get("category");
    try testing.expectEqualStrings("science", value.?);
}

test "update on missing id returns IDNotFound" {
    const allocator = testing.allocator;

    var db = try VectorDB.init(allocator, 3);
    defer db.deinit();

    try db.insert(1, &[_]f32{ 1.0, 0.0, 0.0 });
    try testing.expectError(error.IDNotFound, db.update(99, &[_]f32{ 0.0, 1.0, 0.0 }));
}

test "update rejects wrong dimension" {
    const allocator = testing.allocator;

    var db = try VectorDB.init(allocator, 3);
    defer db.deinit();

    try db.insert(1, &[_]f32{ 1.0, 0.0, 0.0 });
    try testing.expectError(error.InvalidDimension, db.update(1, &[_]f32{ 0.0, 1.0 }));
}
