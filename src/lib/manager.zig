const std = @import("std");
const Graph = @import("./graph.zig").Graph;
const zlog = @import("zlog");
const zchan = @import("zchan");
const zon = @import("build");

const Dep = struct {
    name: []const u8,
    deps: []const []const u8,
};

pub const ZLMStartPlan = struct {
    type_table: []const type,
    name_table: []const []const u8,
    start_order: []const []const u8,
};

pub const Manager = struct {
    allocator: std.mem.Allocator,
    components: std.StringHashMap(*anyopaque),
    logger: *zlog.Logger,
    graph: Graph,
    msgChan: *zchan.Channel(ManagerControlMessage),

    pub fn init(allocator: std.mem.Allocator, config: anytype) !*Manager {
        const self = try allocator.create(Manager);
        const msgChan = try allocator.create(zchan.Channel(ManagerControlMessage));
        self.* = .{
            .allocator = allocator,
            .components = std.StringHashMap(*anyopaque).init(allocator),
            .logger = try allocator.create(zlog.Logger),
            .graph = Graph.init(allocator),
            .msgChan = msgChan,
        };
        self.logger.* = zlog.Logger.init(allocator, "ZLM", true);
        _ = config;
        return self;
    }

    pub fn bootstrap(self: *Manager, plan: ZLMStartPlan) !void {
        Manager.printZLMHeader(plan.start_order);

        for (plan.start_order) |name| {
            var found = false;
            inline for (plan.type_table) |T| {
                if (std.mem.eql(u8, shortTypeName(T), name)) {
                    const instance = try self.allocator.create(T);
                    instance.* = T.init(self) catch {
                        self.logger.log(.@"error", "Failed to init {s}", .{shortTypeName(T)});
                        return;
                    };
                    try self.components.put(name, instance);

                    const typed: *T = instance;

                    if (@hasDecl(T, "before_start")) {
                        try typed.before_start();
                    }

                    if (@hasDecl(T, "threaded") and T.threaded) {
                        const thread = try std.Thread.spawn(.{}, T.start, .{typed});
                        self.logger.log(.info, "Thread created for {s}", .{name});
                        try thread.setName(name);
                    } else {
                        try typed.start();
                    }

                    if (@hasDecl(T, "after_start")) {
                        try typed.after_start();
                    }

                    found = true;
                    break;
                }
            }
            if (!found) return error.TypeNotFound;
        }
    }

    pub fn getComponent(self: *Manager, comptime T: type) !*T {
        const name = shortTypeName(T);
        const ptr = self.components.get(name) orelse return error.ComponentNotFound;
        return @ptrCast(@alignCast(ptr));
    }

    pub fn planLifecycle(comptime component_list: []const type) ZLMStartPlan {
        var names: []const []const u8 = &.{};
        var deps: []const Dep = &.{};

        inline for (component_list) |component| {
            const name = shortTypeName(component);

            if (!@hasDecl(component, "start")) @compileError(name ++ " missing .start()");
            if (!@hasDecl(component, "stop")) @compileError(name ++ " missing .stop()");
            if (!@hasDecl(component, "init")) @compileError(name ++ " missing .init()");

            names = names ++ &[_][]const u8{name};

            var dep_list: []const []const u8 = &.{};
            if (@hasDecl(component, "dependencies")) {
                inline for (component.dependencies) |dep| {
                    dep_list = dep_list ++ &[_][]const u8{shortTypeName(dep)};
                }
            }

            deps = deps ++ &[_]Dep{.{ .name = name, .deps = dep_list }};
        }

        const sorted = topoSortFromDepTable(deps);

        return ZLMStartPlan{
            .type_table = component_list,
            .name_table = names,
            .start_order = sorted,
        };
    }

    pub fn waitForShutdown(self: *Manager, plan: ZLMStartPlan) !void {
        self.logger.log(.info, "Waiting for shutdown", .{});
        const msg = self.msgChan.recv();
        switch (msg) {
            .Shutdown => {
                self.logger.log(.info, "Shutdown requested {}", .{msg});
                try self.shutdown(plan);
            },
            else => {
                self.logger.log(.warn, "Unhandled control message: {}", .{msg});
            },
        }
    }

    pub fn shutdown(self: *Manager, plan: ZLMStartPlan) !void {
        self.logger.log(.info, "Gracefully shutting down", .{});

        var i: usize = plan.start_order.len;
        while (i > 0) {
            i -= 1;
            const name = plan.start_order[i];

            var found = false;
            inline for (plan.type_table) |T| {
                if (std.mem.eql(u8, shortTypeName(T), name)) {
                    self.logger.log(.info, "======================", .{});
                    const ptr = self.components.get(name) orelse return;
                    const typed: *T = @ptrCast(@alignCast(ptr));

                    if (@hasDecl(T, "before_stop")) {
                        self.logger.log(.info, "Running {s}.before_stop()", .{name});
                        typed.before_stop() catch |err| {
                            self.logger.log(.warn, "Error running {s}.before_stop(): {}", .{ name, err });
                        };
                    }

                    // If it has stop(), call it
                    if (@hasDecl(T, "stop")) {
                        self.logger.log(.info, "Running {s}.stop()", .{name});
                        typed.stop() catch |err| {
                            self.logger.log(.warn, "Error running {s}.stop(): {}", .{ name, err });
                        };
                    }
                    if (@hasDecl(T, "after_stop")) {
                        self.logger.log(.info, "Running {s}.after_stop()", .{name});
                        typed.after_stop() catch |err| {
                            self.logger.log(.warn, "Error running {s}.after_stop(): {}", .{ name, err });
                        };
                    }

                    found = true;
                    break;
                }
            }

            if (!found) {
                self.logger.log(.warn, "Unknown component during shutdown: {s}", .{name});
            }
        }

        self.logger.log(.info, "All components stopped", .{});
    }

    pub fn printZLMHeader(start_order: []const []const u8) void {
        const bold = "\x1b[1m";
        const reset = "\x1b[0m";
        const blue = "\x1b[34m";
        const cyan = "\x1b[36m";
        const gray = "\x1b[90m";

        std.debug.print("\n{s}────────────────────────────────────────────{s}\n", .{ gray, reset });
        std.debug.print("  {s}🌀 {s}{s}ZLM{s} — Zig Lifecycle Manager — {s}v{s}{s}\n", .{ blue, reset, bold, reset, cyan, zon.version, reset });
        std.debug.print("{s}────────────────────────────────────────────{s}\n", .{ gray, reset });
        std.debug.print("  {s}Components:{s} {d}\n", .{ bold, reset, start_order.len });
        std.debug.print("  {s}Startup Order:{s}\n", .{ bold, reset });
        for (start_order, 0..) |name, idx| {
            std.debug.print("    {s}{d: >2}. {s}{s}\n", .{ cyan, idx + 1, name, reset });
        }
        std.debug.print("{s}────────────────────────────────────────────{s}\n\n", .{ gray, reset });
    }
};

fn contains(list: []const []const u8, item: []const u8) bool {
    for (list) |x| {
        if (std.mem.eql(u8, x, item)) return true;
    }
    return false;
}

fn topoSortFromDepTable(comptime dep_table: []const Dep) []const []const u8 {
    var result: []const []const u8 = &.{};
    var visited = std.StaticBitSet(256).initEmpty();
    var temp = std.StaticBitSet(256).initEmpty();
    var names: []const []const u8 = &.{};

    inline for (dep_table) |entry| {
        names = names ++ &[_][]const u8{entry.name};
    }

    inline for (dep_table) |entry| {
        visit(entry.name, dep_table, &visited, &temp, &result, names);
    }

    return result;
}

fn visit(
    comptime name: []const u8,
    comptime dep_table: []const Dep,
    visited: *std.StaticBitSet(256),
    temp: *std.StaticBitSet(256),
    result: *[]const []const u8,
    names: []const []const u8,
) void {
    const idx = indexOfName(names, name);
    if (visited.isSet(idx)) return;
    if (temp.isSet(idx)) @compileError("Cyclic dependency detected involving: " ++ name);

    temp.set(idx);

    const entry = for (dep_table) |e| {
        if (std.mem.eql(u8, e.name, name)) break e;
    } else unreachable;

    inline for (entry.deps) |dep| {
        visit(dep, dep_table, visited, temp, result, names);
    }

    visited.set(idx);
    temp.unset(idx);
    result.* = result.* ++ &[_][]const u8{name};
}

fn indexOfName(names: []const []const u8, target: []const u8) usize {
    inline for (names, 0..) |n, i| {
        if (std.mem.eql(u8, n, target)) return i;
    }
    @compileError("Name not found: " ++ target);
}

pub fn shortTypeName(comptime T: type) []const u8 {
    const full = @typeName(T);
    const idx = std.mem.lastIndexOfScalar(u8, full, '.') orelse return full;
    return full[idx + 1 ..];
}

pub const ManagerControlMessage = union(enum) {
    Shutdown: ShutdownInfo,
    Custom: CustomCommand,
};

pub const ShutdownInfo = struct {
    reason: []const u8,
    requested_by: []const u8,
};

pub const CustomCommand = struct {
    command: []const u8,
    metadata: ?[]const u8 = null,
};
