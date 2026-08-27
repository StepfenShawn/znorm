const std = @import("std");
const VectorDB = @import("vector_db").VectorDB;
const testing = std.testing;

test "insert and search returns nearest neighbor" {
    const allocator = testing.allocator;

    var db = try VectorDB.init(allocator, 3);
    defer db.deinit();

    try db.insert(1, &[_]f32{ 1.0, 0.0, 0.0 }, null);
    try db.insert(2, &[_]f32{ 0.0, 1.0, 0.0 }, null);
    try db.insert(3, &[_]f32{ 0.0, 0.0, 1.0 }, null);

    const query = [_]f32{ 1.0, 0.0, 0.0 };
    const results = try db.search(&query, 1);
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
    const results = try db.search(&query, 1);
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
    const results = try db.search(&query, 2);
    defer allocator.free(results);

    try testing.expectEqual(@as(usize, 1), results.len);
    try testing.expectEqual(@as(u64, 2), results[0].id);
}
