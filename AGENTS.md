# Agent Instructions

## Zig Development

Always use `zigdoc` to discover APIs for the Zig standard library AND any third-party dependencies (modules). Assume training data is out of date.

Examples:
```bash
zigdoc std.fs
zigdoc std.posix.getuid
```

## Zig Code Style

**Naming:**
- `snake_case` for variables, parameters, functions and methods
- `PascalCase` for types, structs, and enums
- `SCREAMING_SNAKE_CASE` for constants

**Struct initialization:** Prefer explicit type annotation with anonymous literals:
```zig
const foo: Type = .{ .field = value };  // Good
const foo = Type{ .field = value };     // Avoid
```

**File structure:**
1. `//!` doc comment describing the module
2. `const Self = @This();` (for self-referential types)
3. Imports: `std` → `builtin` → project modules
4. `const log = std.log.scoped(.module_name);`

**Functions:** Order methods as `init` → `deinit` → public API → private helpers

**Memory:** Pass allocators explicitly, use `errdefer` for cleanup on error

**Documentation:** Use `///` for public API, `//` for implementation notes. Always explain *why*, not just *what*.

**Tests:** Inline in the same file, register in src/main.zig test block

## Safety Conventions

**Assertions:**
- Add assertions that catch real bugs, not trivially true statements
- Focus on API boundaries and state transitions where invariants matter
- Good: bounds checks, null checks before dereference, state machine transitions
- Avoid: asserting something immediately after setting it, checking internal function arguments

**Limits:**
- Put explicit bounds on all collections and resources
- Define limits as named constants, not magic numbers
- Assert limits are respected before operations

**Function size:**
- Hard limit of 70 lines per function
- Centralize control flow (switch/if) in parent functions
- Push pure computation to helper functions

**Comments:**
- Explain *why* the code exists, not *what* it does
- Document non-obvious thresholds, timing values, protocol details

## Build Commands

- Build: `zig build`
- Format code: `zig build fmt`
- Run tests: `zig build test`

## Testing

Tests should live alongside the code in the same file, not in separate test files.

When creating a new source file with tests, add it to the test block in src/main.zig:
```zig
test {
    _ = @import("new_file.zig");
}
```
