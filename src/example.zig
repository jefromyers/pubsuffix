const std = @import("std");
const url = @import("src/url.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    const up = try url.URLParser.init(allocator);
    // const u = try up.parse("https://jef.ro");
    const u = try up.parse("https://www.miss.bouquet.co.uk");

    std.debug.print("Host: {s}\n", .{u.host orelse "none"});
    std.debug.print("TLD : {s}\n", .{u.tld orelse "none"});
    // TODO: Add a modaility to find_closest_suffix to return tld or domain
}
