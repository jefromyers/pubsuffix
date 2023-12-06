const std = @import("std");

const ParseErrors = error{
    ParseError,
};

pub const URL = struct {
    scheme: []const u8,
    user: ?[]const u8,
    password: ?[]const u8,
    host: ?[]const u8,
    domain: ?[]const u8,
    tld: ?[]const u8,
    port: ?u16,
    path: []const u8,
    query: ?[]const u8,
    fragment: ?[]const u8,
};

const SuffixError = error{
    InvalidSuffix,
};

const PublicSuffix = struct {
    const Suffix = struct {
        allocator: std.mem.Allocator,
        name: []const u8,
        children: std.StringHashMap(*Suffix),

        fn init(allocator: std.mem.Allocator, name: []const u8) !*Suffix {
            const suffix_ptr = try allocator.create(Suffix);
            suffix_ptr.*.allocator = allocator;
            suffix_ptr.*.name = name;
            suffix_ptr.*.children = std.StringHashMap(*Suffix).init(allocator);
            return suffix_ptr;
        }

        fn deinit(self: *Suffix) void {
            var it = self.children.keyIterator();
            while (it.next()) |k| {
                if (self.children.get(k.*)) |c| {
                    c.deinit();
                }
            }

            self.children.deinit();
            self.allocator.destroy(self);
        }

        pub fn add_suffix(self: *Suffix, name: []const u8) !*Suffix {
            const child_chk = self.children.get(name);
            if (child_chk) |c| {
                return c;
            }

            const child = try Suffix.init(self.allocator, name);
            try self.children.put(name, child);
            return child;
        }

        // XXX: Help see what is going on
        fn printSuffixTree(self: *const Suffix, indent: usize) void {
            var buffer: [256]u8 = undefined;
            var buffer_len: usize = 0;

            while (buffer_len < indent and buffer_len < buffer.len) : (buffer_len += 1) {
                buffer[buffer_len] = ' ';
            }

            const space = buffer[0..buffer_len];

            std.debug.print("{s} - {s}\n", .{ space, self.name });

            var it = self.children.keyIterator();
            while (it.next()) |key| {
                if (self.children.get(key.*)) |child| {
                    child.printSuffixTree(indent + 2);
                }
            }
        }
    };

    const Self = @This();
    allocator: std.mem.Allocator,
    root: *Suffix,

    pub fn init(allocator: std.mem.Allocator) !PublicSuffix {
        // XXX: Maybe we should embed a default?
        // https://ziglang.org/documentation/0.11.0/#embedFile
        const file = try std.fs.cwd().openFile("public_suffix_list.dat", .{ .mode = .read_only });
        defer file.close();

        const file_size = (try file.stat()).size;
        const contents = try file.readToEndAlloc(allocator, file_size);
        // XXX: It seems like we should free this but when we do we get a segfault
        // defer allocator.free(contents);

        const root = try Suffix.init(allocator, "ROOT");
        var ps = PublicSuffix{ .allocator = allocator, .root = root };
        var it = std.mem.split(u8, contents, "\n");
        while (it.next()) |line| {
            if (line.len == 0 or std.mem.startsWith(u8, line, "//")) {
                continue;
            }
            try ps.add_suffix(line);
        }
        return ps;
    }

    pub fn deinit(self: *const PublicSuffix) void {
        self.root.deinit();
    }

    pub fn print(self: *const PublicSuffix) void {
        self.root.printSuffixTree(0);
    }

    pub fn add_suffix(self: *const PublicSuffix, name: []const u8) !void {
        if (name.len == 0) {
            return SuffixError.InvalidSuffix;
        }

        var suffix = self.root;
        var it = std.mem.splitBackwards(u8, name, ".");
        while (it.next()) |suffix_name| {
            suffix = try suffix.add_suffix(suffix_name);
        }
    }

    // XXX: Add a modality to return the domain or just the TLD
    pub fn find_closest_suffix(self: *const PublicSuffix, name: []const u8) !?[]const u8 {
        if (name.len == 0) {
            return SuffixError.InvalidSuffix;
        }

        var suffix_list = std.ArrayList([]const u8).init(self.allocator);
        defer suffix_list.deinit();

        var suffix = self.root;
        var it = std.mem.splitBackwards(u8, name, ".");
        while (it.next()) |suffix_name| {
            if (suffix_name.len == 0) {
                continue;
            }

            if (suffix.children.get(suffix_name)) |child| {
                suffix = child;
                try suffix_list.append(child.name);
            } else {
                // If we want the domain?
                // try suffix_list.append(suffix_name);
                break;
            }
        }

        if (suffix_list.items.len == 0) {
            return null;
        }
        var buf: [255]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        const stream = fbs.writer();
        var total_written: usize = 0;

        // We need the suffixes in reverse order
        var i: usize = suffix_list.items.len;
        while (i > 0) : (i -= 1) {
            const itemList = suffix_list.items[i - 1];
            for (itemList) |item| {
                try stream.print("{c}", .{item});
                total_written += 1;
            }
            try stream.print(".", .{});
            total_written += 1;
        }

        // how do we free this?
        const heapBuffer = try self.allocator.alloc(u8, total_written);
        std.mem.copy(u8, heapBuffer, buf[0 .. total_written - 1]);

        return heapBuffer;
    }
};

pub const URLParser = struct {
    allocator: std.mem.Allocator,
    publicsuffix: PublicSuffix,

    pub fn init(allocator: std.mem.Allocator) !URLParser {
        // Here we would create the Publix Suffix Trie
        const publicsuffix = try PublicSuffix.init(allocator);
        return URLParser{ .allocator = allocator, .publicsuffix = publicsuffix };
    }

    pub fn parse(self: URLParser, url: []const u8) !URL {
        const uri = std.Uri.parse(url) catch return ParseErrors.ParseError;
        const tld = try self.publicsuffix.find_closest_suffix(uri.host.?);

        return URL{
            .scheme = uri.scheme,
            .user = uri.user,
            .password = uri.password,
            .host = uri.host,
            .domain = null,
            .tld = tld,
            .port = uri.port,
            .path = uri.path,
            .query = uri.query,
            .fragment = uri.fragment,
        };
    }
};
