
# 🌀 ZLM — Zig Lifecycle Manager

**ZLM** is a lightweight, compile-time dependency injection and life-cycle orchestration system for Zig.

It lets you define components with life-cycle hooks and dependencies, and ensures they are initialized, started, and stopped in the correct order — all without reflection, macros, or runtime type information.

---

## 🚀 Features

- ✅ **Dependency injection** via compile-time type inspection  
- ✅ **Topological sort** of component startup based on dependencies  
- ✅ **Life-cycle hooks** (`init`, `start`, `stop`, `before_*`, `after_*`)  
- ✅ **Threaded or non-threaded startup** per component  
- ✅ **Graceful shutdown support with component**  
- ✅ **Minimal and fast?**

---

## 📦 Installation

1. Add the project as a dependency in your `build.zig.zon`:

    ```sh
    zig fetch --save git+https://github.com/Tykashi/zlm
    ```

2. In `build.zig`, add `zlm`, `zchan`, `zcont`, and `zlog` as dependencies:

    ```zig
    const zlm = b.dependency("zlm", .{
        .target = target,
        .optimize = optimize,
    });
    const zchan = b.dependency("zchan", .{
        .target = target,
        .optimize = optimize,
    });
    const zlog = b.dependency("zlog", .{
        .target = target,
        .optimize = optimize,
    });

    exe_mod.addImport("zlm", zlm.module("zlm"));
    exe_mod.addImport("zchan", zchan.module("zchan"));
    exe_mod.addImport("zlog", zlog.module("zlog"));
    ```

---

## 🧪 Usage

```zig
const std = @import("std");
const zlm = @import("zlm");
const Manager = @import("zlm").Manager;

const Environment = @import("environment.zig").Environment;
const SignalWatcher = @import("signalwatcher.zig").SignalWatcher;
const PG = @import("postgres.zig").PG;

const plan = Manager.planLifecycle(&[_]type{
    Environment,
    PG,
    SignalWatcher,
});

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    const manager = try Manager.init(allocator, .{});
    manager.bootstrap(plan) catch |err| {
        manager.logger.log(.@"error", "Failed to bootstrap: {}", .{err});
        return;
    };
    try manager.waitForShutdown(plan);
}
```
