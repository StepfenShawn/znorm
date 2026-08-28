# znorm

A Zig-native memory engine for AI agents. No GC, no libc, no cloud.  

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

    // Metadata is managed entirely by the DB: no caller-owned HashMap needed.
    try db.insert(1, &[_]f32{ 1.0, 0.0, 0.0 });
    try db.setMetadata(1, "title", "red");
    try db.setMetadata(1, "category", "color");

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