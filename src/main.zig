const std = @import("std");
const VectorDB = @import("vector_db.zig").VectorDB;

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.page_allocator;

    var db = try VectorDB.init(allocator, 3);
    defer db.deinit();

    var meta1 = std.StringHashMap([]const u8).init(allocator);
    try meta1.put("title", "红色");
    try meta1.put("category", "颜色");
    try db.insert(1, &[_]f32{ 1.0, 0.0, 0.0 }, meta1);

    var meta2 = std.StringHashMap([]const u8).init(allocator);
    try meta2.put("title", "绿色");
    try meta2.put("category", "颜色");
    try db.insert(2, &[_]f32{ 0.0, 1.0, 0.0 }, meta2);

    var meta3 = std.StringHashMap([]const u8).init(allocator);
    try meta3.put("title", "蓝色");
    try meta3.put("category", "颜色");
    try db.insert(3, &[_]f32{ 0.0, 0.0, 1.0 }, meta3);

    db.display();

    const query = [_]f32{ 1.0, 0.5, 0.0 };
    const results = try db.search(&query, 2, null);
    defer allocator.free(results);

    std.debug.print("Top 2 results:\n", .{});
    for (results) |res| {
        std.debug.print("ID: {}, Score: {d:.3}\n", .{ res.id, res.score });
    }
    try db.save(init.io, "mydb.bin");
}
