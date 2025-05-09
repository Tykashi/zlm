const std = @import("std");
const posix = std.posix;
const zlog = @import("zlog");
const zcont = @import("zcont");
const Manager = @import("../../src/lib/manager.zig").Manager;
const ManagerControlMessage = @import("../../src/lib/manager.zig").ManagerControlMessage;
const zchan = @import("zchan");

// global atomic for safe signal handling
var signal_flag = std.atomic.Value(bool).init(false);

// C-callable top-level signal handler
export fn sig_handler(_: c_int) callconv(.C) void {
    signal_flag.store(true, .seq_cst);
}

pub const SignalWatcher = struct {
    pub const dependencies = [_]type{};
    pub const threaded = true;
    name: []const u8 = "SignalWatcher",
    logger: zlog.Logger,
    manager: *Manager,
    chan: *zchan.Channel(ManagerControlMessage),

    pub fn init(manager: *Manager) !SignalWatcher {
        return SignalWatcher{
            .name = "SignalWatcher",
            .logger = manager.logger.child("SignalWatcher"),
            .manager = manager,
            .chan = manager.msgChan,
        };
    }

    pub fn start(self: *SignalWatcher, _: ?*zcont.Context) anyerror!void {
        const action = posix.Sigaction{
            .handler = .{ .handler = sig_handler },
            .mask = posix.empty_sigset,
            .flags = 0,
        };

        _ = posix.sigaction(posix.SIG.INT, &action, null);
        _ = posix.sigaction(posix.SIG.TERM, &action, null);

        self.logger.log(.info, "Signal handlers registered", .{});

        while (true) {
            std.time.sleep(10_000_000);
            if (signal_flag.load(.seq_cst)) {
                self.logger.log(.info, "Signal received, sending Shutdown...", .{});
                self.chan.send(.{
                    .Shutdown = .{
                        .reason = "Received SIGINT/SIGTERM",
                        .requested_by = "SignalWatcher",
                    },
                });
                break;
            }
        }
    }

    pub fn stop(self: *SignalWatcher, _: *zcont.Context) anyerror!void {
        self.logger.log(.info, "SignalWatcher stop", .{});
    }
};
