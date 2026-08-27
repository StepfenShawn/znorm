const std = @import("std");
const VectorDB = @import("vector_db").VectorDB;
const Filter = @import("vector_db").Filter;
const testing = std.testing;

test "insert and search returns nearest neighbor" {
    const allocator = testing.allocator;

    var db = try VectorDB.init(allocator, 3);
    defer db.deinit();

    try db.insert(1, &[_]f32{ 1.0, 0.0, 0.0 }, null);
    try db.insert(2, &[_]f32{ 0.0, 1.0, 0.0 }, null);
    try db.insert(3, &[_]f32{ 0.0, 0.0, 1.0 }, null);

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

    var meta = std.StringHashMap([]const u8).init(allocator);
    try meta.put("label", "hello");
    try db.insert(10, &[_]f32{ 1.0, 0.0 }, meta);

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

    try db.insert(1, &[_]f32{ 1.0, 0.0 }, null);
    try db.insert(2, &[_]f32{ 0.9, 0.1 }, null);

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

    var m1 = std.StringHashMap([]const u8).init(allocator);
    try m1.put("category", "science");
    try db.insert(1, &[_]f32{ 1.0, 0.0, 0.0 }, m1);

    var m2 = std.StringHashMap([]const u8).init(allocator);
    try m2.put("category", "art");
    try db.insert(2, &[_]f32{ 0.9, 0.1, 0.0 }, m2);

    var m3 = std.StringHashMap([]const u8).init(allocator);
    try m3.put("category", "science");
    try db.insert(3, &[_]f32{ 0.8, 0.2, 0.0 }, m3);

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

    var m1 = std.StringHashMap([]const u8).init(allocator);
    try m1.put("category", "science");
    try db.insert(1, &[_]f32{ 1.0, 0.0, 0.0 }, m1);

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

    var m1 = std.StringHashMap([]const u8).init(allocator);
    try m1.put("year", "2023");
    try db.insert(1, &[_]f32{ 1.0, 0.0 }, m1);

    var m2 = std.StringHashMap([]const u8).init(allocator);
    try m2.put("year", "2019");
    try db.insert(2, &[_]f32{ 0.9, 0.1 }, m2);

    var m3 = std.StringHashMap([]const u8).init(allocator);
    try m3.put("year", "2025");
    try db.insert(3, &[_]f32{ 0.8, 0.2 }, m3);

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

    var m1 = std.StringHashMap([]const u8).init(allocator);
    try m1.put("year", "2023");
    try db.insert(1, &[_]f32{ 1.0, 0.0 }, m1);

    var m2 = std.StringHashMap([]const u8).init(allocator);
    try m2.put("year", "2019");
    try db.insert(2, &[_]f32{ 0.9, 0.1 }, m2);

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

    var m1 = std.StringHashMap([]const u8).init(allocator);
    try m1.put("category", "science");
    try m1.put("year", "2023");
    try db.insert(1, &[_]f32{ 1.0, 0.0 }, m1);

    var m2 = std.StringHashMap([]const u8).init(allocator);
    try m2.put("category", "science");
    try m2.put("year", "2018");
    try db.insert(2, &[_]f32{ 0.9, 0.1 }, m2);

    var m3 = std.StringHashMap([]const u8).init(allocator);
    try m3.put("category", "art");
    try m3.put("year", "2023");
    try db.insert(3, &[_]f32{ 0.8, 0.2 }, m3);

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

    try db.insert(1, &[_]f32{ 1.0, 0.0 }, null);
    try db.insert(2, &[_]f32{ 0.9, 0.1 }, null);

    const query = [_]f32{ 1.0, 0.0 };
    const results = try db.search(&query, 10, null);
    defer allocator.free(results);

    try testing.expectEqual(@as(usize, 2), results.len);
}

test "filter missing key excludes vector" {
    const allocator = testing.allocator;

    var db = try VectorDB.init(allocator, 2);
    defer db.deinit();

    var m1 = std.StringHashMap([]const u8).init(allocator);
    try m1.put("category", "science");
    try db.insert(1, &[_]f32{ 1.0, 0.0 }, m1);

    try db.insert(2, &[_]f32{ 0.9, 0.1 }, null);

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

    var m1 = std.StringHashMap([]const u8).init(allocator);
    try m1.put("category", "science");
    try db.insert(1, &[_]f32{ 1.0, 0.0, 0.0 }, m1);

    var m2 = std.StringHashMap([]const u8).init(allocator);
    try m2.put("category", "art");
    try db.insert(2, &[_]f32{ 0.9, 0.1, 0.0 }, m2);

    var m3 = std.StringHashMap([]const u8).init(allocator);
    try m3.put("category", "music");
    try db.insert(3, &[_]f32{ 0.8, 0.2, 0.0 }, m3);

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
