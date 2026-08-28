const std = @import("std");
const VectorDB = @import("vector_db.zig").VectorDB;

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.page_allocator;

    var db = try VectorDB.init(allocator, 3);
    defer db.deinit();

    try db.insert(1, &[_]f32{ 1.0, 0.0, 0.0 });
    try db.setMetadata(1, "title", "红色");
    try db.setMetadata(1, "category", "颜色");

    try db.insert(2, &[_]f32{ 0.0, 1.0, 0.0 });
    try db.setMetadata(2, "title", "绿色");
    try db.setMetadata(2, "category", "颜色");

    try db.insert(3, &[_]f32{ 0.0, 0.0, 1.0 });
    try db.setMetadata(3, "title", "蓝色");
    try db.setMetadata(3, "category", "颜色");

    try db.update(3, &[_]f32{ 0.0, 0.0, 0.5 });

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
