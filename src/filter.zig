const std = @import("std");

pub const FilterValue = union(enum) {
    string: []const u8,
    int: i64,
    float: f64,
    bool: bool,
};

pub const Filter = union(enum) {
    eq: struct { key: []const u8, value: FilterValue },
    neq: struct { key: []const u8, value: FilterValue },
    gt: struct { key: []const u8, value: FilterValue },
    gte: struct { key: []const u8, value: FilterValue },
    lt: struct { key: []const u8, value: FilterValue },
    lte: struct { key: []const u8, value: FilterValue },
    @"and": []const Filter,
    @"or": []const Filter,
};

pub fn evaluateAll(filters: []const Filter, metadata: ?std.StringHashMap([]const u8)) !bool {
    for (filters) |f| {
        if (!try evaluate(f, metadata)) return false;
    }
    return true;
}

pub fn evaluate(filter: Filter, metadata: ?std.StringHashMap([]const u8)) !bool {
    return switch (filter) {
        .eq => |c| cmp(c.key, c.value, metadata, .eq),
        .neq => |c| cmp(c.key, c.value, metadata, .neq),
        .gt => |c| cmp(c.key, c.value, metadata, .gt),
        .gte => |c| cmp(c.key, c.value, metadata, .gte),
        .lt => |c| cmp(c.key, c.value, metadata, .lt),
        .lte => |c| cmp(c.key, c.value, metadata, .lte),
        .@"and" => |filters| {
            for (filters) |f| {
                if (!try evaluate(f, metadata)) return false;
            }
            return true;
        },
        .@"or" => |filters| {
            for (filters) |f| {
                if (try evaluate(f, metadata)) return true;
            }
            return false;
        },
    };
}

const Op = enum { eq, neq, gt, gte, lt, lte };

fn cmp(key: []const u8, value: FilterValue, metadata: ?std.StringHashMap([]const u8), op: Op) !bool {
    const meta = metadata orelse return false;
    const stored = meta.get(key) orelse return false;
    return switch (value) {
        .string => |v| cmpString(stored, v, op),
        .int => |v| cmpInt(stored, v, op),
        .float => |v| cmpFloat(stored, v, op),
        .bool => |v| cmpBool(stored, v, op),
    };
}

fn cmpString(stored: []const u8, value: []const u8, op: Op) bool {
    const eq = std.mem.eql(u8, stored, value);
    return switch (op) {
        .eq => eq,
        .neq => !eq,
        .gt => std.mem.order(u8, stored, value) == .gt,
        .gte => std.mem.order(u8, stored, value) != .lt,
        .lt => std.mem.order(u8, stored, value) == .lt,
        .lte => std.mem.order(u8, stored, value) != .gt,
    };
}

fn cmpInt(stored: []const u8, value: i64, op: Op) !bool {
    const parsed = std.fmt.parseInt(i64, stored, 10) catch return error.InvalidFilterValue;
    return switch (op) {
        .eq => parsed == value,
        .neq => parsed != value,
        .gt => parsed > value,
        .gte => parsed >= value,
        .lt => parsed < value,
        .lte => parsed <= value,
    };
}

fn cmpFloat(stored: []const u8, value: f64, op: Op) !bool {
    const parsed = std.fmt.parseFloat(f64, stored) catch return error.InvalidFilterValue;
    return switch (op) {
        .eq => parsed == value,
        .neq => parsed != value,
        .gt => parsed > value,
        .gte => parsed >= value,
        .lt => parsed < value,
        .lte => parsed <= value,
    };
}

fn cmpBool(stored: []const u8, value: bool, op: Op) !bool {
    const parsed: bool = if (std.mem.eql(u8, stored, "true"))
        true
    else if (std.mem.eql(u8, stored, "false"))
        false
    else
        return error.InvalidFilterValue;
    return switch (op) {
        .eq => parsed == value,
        .neq => parsed != value,
        .gt, .gte, .lt, .lte => return error.InvalidFilterValue,
    };
}
