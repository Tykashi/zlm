/// # Environment Component
///
/// Loads environment variables from a `.env` file into a runtime-accessible map,
/// allowing other components to retrieve configuration via typed accessors.
///
/// ## Features:
/// - Parses `.env` file into a string map
/// - Provides typed access with `get`, `getInt`, and `fill`
/// - Graceful handling of malformed lines and missing values
///
/// ## Example:
/// ```zig
/// const env = try manager.getComponent(Environment);
/// const value = env.get("MY_KEY") orelse "default";
/// ```
///
/// Use `fill()` to auto-populate a struct from environment values:
/// ```zig
/// const config = try allocator.create(MyConfig);
/// try env.fill(MyConfig, config);
/// ```
///
/// ## Notes:
/// - Keys and values are not trimmed or sanitized
/// - Unknown or unsupported field types in `fill()` will cause compile-time errors
///
const std = @import("std");
const zcont = @import("zcont");
const zlog = @import("zlog");
const Manager = @import("../../src/lib/manager.zig").Manager;

const MAX_SIZE: usize = 1024;

pub const Environment = struct {
    name: []const u8 = "Environment",
    manager: *Manager,
    map: std.StringHashMap([]const u8),
    logger: zlog.Logger,
    pub const dependencies = [_]type{};

    pub fn init(manager: *Manager) !Environment {
        return Environment{
            .name = "Environment",
            .map = std.StringHashMap([]const u8).init(std.heap.page_allocator),
            .manager = manager,
            .logger = manager.logger.child("Environment"),
        };
    }

    pub fn get(self: *Environment, key: []const u8) ?[]const u8 {
        return self.map.get(key);
    }

    pub fn getInt(self: *Environment, key: []const u8) u16 {
        if (self.map.get(key)) |val| {
            return std.fmt.parseInt(u16, val, 10) catch 0;
        }
        return 0;
    }

    pub fn start(self: *Environment, ctx: ?*zcont.Context) anyerror!void {
        _ = ctx;
        self.logger.log(.info, "Environment start!", .{});

        const allocator = std.heap.page_allocator;
        const file = try std.fs.cwd().openFile(".env", .{});
        const rdr = file.reader();
        var line_buffer: [MAX_SIZE]u8 = undefined;

        while (true) {
            const line = try rdr.readUntilDelimiterOrEof(&line_buffer, '\n');
            if (line) |v| {
                var split = std.mem.splitScalar(u8, v, '=');
                if (split.next()) |key| {
                    const value = split.rest();
                    const key_copy = try allocator.dupe(u8, key);
                    const value_copy = try allocator.dupe(u8, value);
                    try self.map.put(key_copy, value_copy);
                } else {
                    self.logger.log(.@"error", "Malformed line in .env file: {s}", .{v});
                }
            } else break;
        }

        self.logger.log(.info, "Environment Loaded", .{});
    }

    pub fn stop(self: *Environment, ctx: *zcont.Context) anyerror!void {
        self.logger.log(.info, "Environment stop!", .{});
        _ = ctx;
        // No resource to clean up in current implementation
    }

    pub fn before_start(self: *Environment, ctx: *zcont.Context) anyerror!void {
        self.logger.log(.info, "Environment before_start!", .{});
        _ = ctx;
    }

    pub fn after_start(self: *Environment, ctx: *zcont.Context) anyerror!void {
        self.logger.log(.info, "Environment after_start!", .{});
        _ = ctx;
    }

    pub fn before_stop(
        self: *Environment,
        ctx: *zcont.Context,
    ) anyerror!void {
        self.logger.log(.info, "Environment before_stop!", .{});
        _ = ctx;
    }

    pub fn after_stop(self: *Environment, ctx: *zcont.Context) anyerror!void {
        self.logger.log(.info, "Environment after_stop!", .{});
        _ = ctx;
    }
    pub fn fill(self: *Environment, comptime T: type, target: *T) !void {
        const type_info = @typeInfo(T);
        switch (type_info) {
            .@"struct" => |s| {
                inline for (s.fields) |field| {
                    const name = field.name;
                    const field_type = field.type;

                    if (field_type == []const u8) {
                        const val = self.get(name) orelse {
                            self.logger.log(.@"error", "Missing Environment Variable: {s}", .{name});
                            return error.MissingEnvironmentVariable;
                        };
                        @field(target.*, name) = val;
                    } else if (field_type == u16) {
                        const val = self.getInt(name);
                        @field(target.*, name) = val;
                    } else {
                        @compileError("Unsupported field type in Environment.fill: " ++ @typeName(field_type));
                    }
                }
            },
            else => @compileError("Environment.fill expects a struct"),
        }
    }
};
