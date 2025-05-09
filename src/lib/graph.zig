const std = @import("std");
const shortTypeName = @import("../lib/manager.zig").shortTypeName;
pub const Node = struct {
    name: []const u8,
    dependencies: []const []const u8,
    instance: ?*anyopaque,
    thread: ?std.Thread = null,
    is_running: bool = false,
};

pub const Graph = struct {
    allocator: std.mem.Allocator,
    nodes: std.StringHashMap(Node),

    pub fn init(allocator: std.mem.Allocator) Graph {
        return Graph{
            .allocator = allocator,
            .nodes = std.StringHashMap(Node).init(allocator),
        };
    }

    pub fn addNode(self: *Graph, comptime T: type, dependencies: []const []const u8) !void {
        const name = shortTypeName(T);
        const node = Node{
            .name = name,
            .dependencies = dependencies,
            .instance = null,
        };
        try self.nodes.put(name, node);
    }

    pub fn topoSort(self: *Graph) ![]const []const u8 {
        var visited = std.StringHashMap(bool).init(self.allocator);
        var tempMark = std.StringHashMap(bool).init(self.allocator);
        var result = std.ArrayList([]const u8).init(self.allocator);

        var it = self.nodes.iterator();
        while (it.next()) |entry| {
            try visitNode(self, entry.key_ptr.*, &visited, &tempMark, &result);
        }

        return result.toOwnedSlice();
    }
};

fn visitNode(
    graph: *Graph,
    name: []const u8,
    visited: *std.StringHashMap(bool),
    tempMark: *std.StringHashMap(bool),
    result: *std.ArrayList([]const u8),
) !void {
    if (visited.contains(name)) return;
    if (tempMark.contains(name)) return error.CyclicDependency;

    try tempMark.put(name, true);

    const node = graph.nodes.get(name) orelse return error.UnknownNode;
    for (node.dependencies) |dep| {
        try visitNode(graph, dep, visited, tempMark, result);
    }

    try visited.put(name, true);
    _ = tempMark.remove(name);
    try result.append(name);
}
