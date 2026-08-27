const std = @import("std");
const filter = @import("filter");
const Filter = filter.Filter;
const evaluateAll = filter.evaluateAll;
const testing = std.testing;

test "eq string match" {
    var meta = std.StringHashMap([]const u8).init(testing.allocator);
    defer meta.deinit();
    try meta.put("category", "science");

    const f = Filter{ .eq = .{ .key = "category", .value = .{ .string = "science" } } };
    try testing.expect(try filter.evaluate(f, meta));
}

test "eq string no match" {
    var meta = std.StringHashMap([]const u8).init(testing.allocator);
    defer meta.deinit();
    try meta.put("category", "science");

    const f = Filter{ .eq = .{ .key = "category", .value = .{ .string = "art" } } };
    try testing.expect(!try filter.evaluate(f, meta));
}

test "neq string" {
    var meta = std.StringHashMap([]const u8).init(testing.allocator);
    defer meta.deinit();
    try meta.put("category", "science");

    const f = Filter{ .neq = .{ .key = "category", .value = .{ .string = "art" } } };
    try testing.expect(try filter.evaluate(f, meta));
}

test "gt int" {
    var meta = std.StringHashMap([]const u8).init(testing.allocator);
    defer meta.deinit();
    try meta.put("year", "2023");

    const f = Filter{ .gt = .{ .key = "year", .value = .{ .int = 2022 } } };
    try testing.expect(try filter.evaluate(f, meta));
}

test "gt int no match" {
    var meta = std.StringHashMap([]const u8).init(testing.allocator);
    defer meta.deinit();
    try meta.put("year", "2023");

    const f = Filter{ .gt = .{ .key = "year", .value = .{ .int = 2023 } } };
    try testing.expect(!try filter.evaluate(f, meta));
}

test "lte int" {
    var meta = std.StringHashMap([]const u8).init(testing.allocator);
    defer meta.deinit();
    try meta.put("year", "2023");

    const f = Filter{ .lte = .{ .key = "year", .value = .{ .int = 2023 } } };
    try testing.expect(try filter.evaluate(f, meta));
}

test "missing key returns false" {
    var meta = std.StringHashMap([]const u8).init(testing.allocator);
    defer meta.deinit();
    try meta.put("category", "science");

    const f = Filter{ .eq = .{ .key = "missing", .value = .{ .string = "x" } } };
    try testing.expect(!try filter.evaluate(f, meta));
}

test "null metadata returns false" {
    const f = Filter{ .eq = .{ .key = "x", .value = .{ .string = "y" } } };
    try testing.expect(!try filter.evaluate(f, null));
}

test "parse error on invalid int" {
    var meta = std.StringHashMap([]const u8).init(testing.allocator);
    defer meta.deinit();
    try meta.put("year", "abc");

    const f = Filter{ .gt = .{ .key = "year", .value = .{ .int = 2022 } } };
    try testing.expectError(error.InvalidFilterValue, filter.evaluate(f, meta));
}

test "parse error on invalid bool" {
    var meta = std.StringHashMap([]const u8).init(testing.allocator);
    defer meta.deinit();
    try meta.put("active", "maybe");

    const f = Filter{ .eq = .{ .key = "active", .value = .{ .bool = true } } };
    try testing.expectError(error.InvalidFilterValue, filter.evaluate(f, meta));
}

test "gt float" {
    var meta = std.StringHashMap([]const u8).init(testing.allocator);
    defer meta.deinit();
    try meta.put("score", "3.14");

    const f = Filter{ .gt = .{ .key = "score", .value = .{ .float = 3.0 } } };
    try testing.expect(try filter.evaluate(f, meta));
}

test "bool eq true" {
    var meta = std.StringHashMap([]const u8).init(testing.allocator);
    defer meta.deinit();
    try meta.put("active", "true");

    const f = Filter{ .eq = .{ .key = "active", .value = .{ .bool = true } } };
    try testing.expect(try filter.evaluate(f, meta));
}

test "bool eq false" {
    var meta = std.StringHashMap([]const u8).init(testing.allocator);
    defer meta.deinit();
    try meta.put("active", "false");

    const f = Filter{ .eq = .{ .key = "active", .value = .{ .bool = false } } };
    try testing.expect(try filter.evaluate(f, meta));
}

test "and via slice" {
    var meta = std.StringHashMap([]const u8).init(testing.allocator);
    defer meta.deinit();
    try meta.put("category", "science");
    try meta.put("year", "2023");

    const filters = [_]Filter{
        .{ .eq = .{ .key = "category", .value = .{ .string = "science" } } },
        .{ .gt = .{ .key = "year", .value = .{ .int = 2020 } } },
    };
    try testing.expect(try evaluateAll(&filters, meta));
}

test "and via slice one fails" {
    var meta = std.StringHashMap([]const u8).init(testing.allocator);
    defer meta.deinit();
    try meta.put("category", "science");
    try meta.put("year", "2019");

    const filters = [_]Filter{
        .{ .eq = .{ .key = "category", .value = .{ .string = "science" } } },
        .{ .gt = .{ .key = "year", .value = .{ .int = 2020 } } },
    };
    try testing.expect(!try evaluateAll(&filters, meta));
}

test "explicit or" {
    var meta = std.StringHashMap([]const u8).init(testing.allocator);
    defer meta.deinit();
    try meta.put("category", "art");

    const f = Filter{ .@"or" = &[_]Filter{
        .{ .eq = .{ .key = "category", .value = .{ .string = "science" } } },
        .{ .eq = .{ .key = "category", .value = .{ .string = "art" } } },
    } };
    try testing.expect(try filter.evaluate(f, meta));
}

test "explicit or all fail" {
    var meta = std.StringHashMap([]const u8).init(testing.allocator);
    defer meta.deinit();
    try meta.put("category", "music");

    const f = Filter{ .@"or" = &[_]Filter{
        .{ .eq = .{ .key = "category", .value = .{ .string = "science" } } },
        .{ .eq = .{ .key = "category", .value = .{ .string = "art" } } },
    } };
    try testing.expect(!try filter.evaluate(f, meta));
}
