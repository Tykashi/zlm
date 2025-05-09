const std = @import("std");

const Manager = @import("lib/manager.zig").Manager;
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
