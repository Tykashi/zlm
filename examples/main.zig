const std = @import("std");

// ┌────────────────────────────────────────────────────────┐
// │                 ZLM Application Entry                 │
// └────────────────────────────────────────────────────────┘
//
// Requirements:
// - You **must** have a `.env` file in your working directory.
//   It should define all necessary environment variables used
//   by your components (e.g., database connection info).
//
// Example `.env`:
//
//     DB_HOST=localhost
//     DB_PORT=5432
//     DB_USER=postgres
//     DB_PASS=secret
//     DB_DATABASE=mydb
//
// - These variables will be parsed during `Environment.start()`
//   and injected into any component that declares a `PGConfig`-like
//   struct via `env.fill(PGConfig, config_ptr)`.
//
// Instructions:
// - Follow `build.zig.zon` install guidance for ZLM.
// - Review `components/skeleton.zig` for lifecycle hook examples.
// - Customize your components and add to the plan list below.
//

// ZLM import
const zlm = @import("zlm");
const Manager = zlm.Manager;

// Components
const PG = @import("components/postgres.zig").PG;
const Environment = @import("components/environment.zig").Environment;
const SignalWatcher = @import("components/signalwatcher.zig").SignalWatcher;

const plan = Manager.planLifecycle(&[_]type{ PG, Environment, SignalWatcher });

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    const manager = try Manager.init(allocator, .{});
    try manager.bootstrap(plan);
    try manager.waitForShutdown(plan);
}
