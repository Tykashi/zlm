const std = @import("std");
const pg = @import("pg");
const zcont = @import("zcont");
const zlog = @import("zlog");
const Environment = @import("./environment.zig").Environment;
const Manager = @import("../../src/lib/manager.zig").Manager;
const PGConfig = struct {
    DB_HOST: []const u8,
    DB_PORT: u16,
    DB_USER: []const u8,
    DB_PASS: []const u8,
    DB_DATABASE: []const u8,
};

pub const PG = struct {
    pub const dependencies = [_]type{Environment};

    name: []const u8 = "PG",
    manager: *Manager,
    logger: zlog.Logger,
    pool: ?*pg.Pool = null,
    config: ?*PGConfig = null,

    pub fn init(manager: *Manager) !PG {
        return PG{
            .manager = manager,
            .logger = manager.logger.child("PG"),
            .pool = null,
            .config = null, // or a default state
        };
    }
    pub fn start(self: *PG, ctx: *zcont.Context) anyerror!void {
        _ = ctx;
        self.logger.log(.info, "Connecting to database", .{});

        const allocator = self.manager.allocator;
        const env = try self.manager.getComponent(Environment);
        const config = try allocator.create(PGConfig);
        try env.fill(PGConfig, config);

        self.config = config;

        const pool = pg.Pool.init(allocator, .{
            .size = 5,
            .connect = .{
                .host = config.DB_HOST,
                .port = config.DB_PORT,
            },
            .auth = .{
                .username = config.DB_USER,
                .password = config.DB_PASS,
                .database = config.DB_DATABASE,
                .timeout = 10_000,
            },
        }) catch |err| {
            self.logger.log(.@"error", "Failed to connect to database: {}", .{err});
            return err;
        };

        self.pool = pool;
    }

    pub fn stop(self: *PG, ctx: *zcont.Context) anyerror!void {
        _ = ctx;
        self.pool.?.deinit();
        self.logger.log(.info, "Connections cleared", .{});
    }

    pub fn query(self: *PG, query_string: []const u8, params: anytype) !*pg.Result {
        var conn = try self.pool.acquire();
        defer conn.release();
        return conn.query(query_string, params);
    }

    pub fn exec(self: *PG, query_string: []const u8, params: anytype) !void {
        _ = try self.pool.exec(query_string, params);
    }

    pub fn queryMapped(comptime T: type, self: *PG, allocator: std.mem.Allocator, query_string: []const u8, params: anytype) !std.ArrayList(T) {
        var result = try self.pool.queryOpts(query_string, params, .{ .column_names = true });
        defer result.deinit();

        var al = std.ArrayList(T).init(allocator);
        defer al.deinit();

        var mapper = result.mapper(T, .{});
        while (try mapper.next()) |row| {
            const copy = try allocator.dupe(T, &row);
            try al.append(copy.*);
        }

        return al;
    }
};
