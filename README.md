# znorm

A Zig-native memory engine for on-device AI agents. No GC, no libc, no cloud.  

## Features

- **Vector storage** - Store high-dimensional vectors with associated metadata
- **Cosine similarity search** - Fast nearest-neighbor queries using cosine distance
- **Metadata filtering** - Filter results by custom key-value metadata
- **Persistence** - Save/load database to binary format (ZVDB)
- **Zero dependencies** - Pure Zig standard library

## Quick Start

```bash
zig build run
```

## Usage

```zig
const std = @import("std");
const VectorDB = @import("vector_db.zig").VectorDB;

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.page_allocator;
    var db = try VectorDB.init(allocator, 3);
    defer db.deinit();

    var meta1 = std.StringHashMap([]const u8).init(allocator);
    try meta1.put("title", "red");
    try meta1.put("category", "color");
    try db.insert(1, &[_]f32{ 1.0, 0.0, 0.0 }, meta1);

    db.display();

    const results = try db.search(query_vector, 10, null);
    defer allocator.free(results);
    for (results) |res| {
        std.debug.print("ID: {}, Score: {d:.3}\n", .{ res.id, res.score });
    }
}
```

## Build

```bash
zig build           # Build library
zig build test      # Run tests
zig build run       # Run example
```

## License

MIT