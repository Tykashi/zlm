**ZLM** is a lightweight, compile-time dependency injection and life-cycle orchestration system for Zig.

It lets you define components with life-cycle hooks and dependencies, and ensures they are initialized, started, and stopped in the correct order — all without reflection, macros, or runtime type information.

> **Zero runtime reflection. Fully type-safe. Minimal overhead.**

---

## 🚀 Features

- ✅ **Dependency injection** via compile-time type inspection
- ✅ **Topological sort** of component startup based on dependencies
- ✅ **Life-cycle hooks** (`init`, `start`, `stop`, `before_*`, `after_*`)
- ✅ **Threaded or non-threaded startup** per component
- ✅ **Graceful shutdown support**
- ✅ **Minimal and fast**

---

## 📦 Installation
1. Add the project as a dependency in your `build.zig.zon`:
```
zig fetch --save git+https://github.com/Tykashi/zlm
```

2. In `build.zig`, add `zlm` as a dependency:
```
```zig
const zlm = b.dependency("zlm", .{
    .target = target,
    .optimize = optimize,
});

// Wherever you configure your executable:
exe.root_module.addImport("zlm", zlm.module("zlm"));
```

## ⚠️ Warnings

ZLM is **experimental** and still under early development. While its design emphasizes performance and compile-time safety, please consider the following caveats before using it in production:

- 🔍 **Memory leaks are possible:** 
  - Components created via `Manager.bootstrap()` are never freed.
  - The `Manager` itself and its internal `StringHashMap` of components are not deallocated on shutdown.
  - If your components allocate memory, it's your responsibility to release it inside their `.stop()` or `.after_stop()` hooks.

- 🧼 **No automatic tear down:**
  - `Manager.shutdown()` orchestrates the life-cycle tear down by calling hooks (`before_stop`, `stop`, `after_stop`), but does **not** deallocate memory or destroy resources.

- 🧪 **Not yet production-hardened:**
  - While stable for demos, CLI tools, and small services, it has not been battle-tested in long-running or high-concurrency environments.

---

### 🛠 Recommendations

- Always clean up your component's resources in `stop()` or `after_stop()`.
- Consider wrapping heap allocations in arenas or use scoped allocators if available.
- If you're embedding ZLM in a larger system, ensure shutdown flows reclaim memory appropriately.

---

Contributions welcome! Help improve memory handling or add full cleanup support by opening a PR.
