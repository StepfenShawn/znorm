# znorm

A blazing fast vector database written in pure Zig.

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
var db = try VectorDB.init(allocator, 384);
defer db.deinit();

try db.insert(1, vector, .{ .{"category", "docs"} });

const results = try db.search(query_vector, 10, null);
```

## Build

```bash
zig build           # Build library
zig build test      # Run tests
zig build run       # Run example
```

## License

MIT