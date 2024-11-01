const std = @import("std");
const Type = std.builtin.Type;

const log = std.log;

pub const Command = struct {
    name: Name,
    description: ?[]const u8 = null,
    flags: []const Flag = &.{},
    positionals: []const Positional = &.{},
    subcommands: []const Command = &.{},

    pub const Name = union(enum) {
        root,
        subcommand: [:0]const u8,
    };

    pub fn Parsed(comptime command: Command) type {
        var fields = std.BoundedArray(Type.StructField, 3){};

        if (command.flags.len != 0) {
            const T = command.ParsedFlags();
            fields.appendAssumeCapacity(.{
                .name = "flags",
                .type = T,
                .alignment = @alignOf(T),
                .default_value = null,
                .is_comptime = false,
            });
        }

        if (command.positionals.len != 0) {
            const T = command.ParsedPositionals();
            fields.appendAssumeCapacity(.{
                .name = "positionals",
                .type = T,
                .alignment = @alignOf(T),
                .default_value = null,
                .is_comptime = false,
            });
        }

        if (command.subcommands.len != 0) {
            const T = ?command.ParsedSubcommand();
            fields.appendAssumeCapacity(.{
                .name = "subcommand",
                .type = T,
                .alignment = @alignOf(T),
                .default_value = null,
                .is_comptime = false,
            });
        }

        return @Type(.{ .Struct = .{
            .layout = .auto,
            .fields = fields.slice(),
            .decls = &.{},
            .is_tuple = false,
        } });
    }

    pub fn ParsedFlags(comptime command: Command) type {
        const flags = command.flags;
        var fields: [flags.len]Type.StructField = undefined;
        for (&fields, flags) |*field, flag| {
            const T = flag.Value();
            field.* = .{
                .name = flag.long,
                .type = T,
                .default_value = null,
                .is_comptime = false,
                .alignment = @alignOf(T),
            };
        }

        return @Type(Type{ .Struct = Type.Struct{
            .layout = .auto,
            .fields = &fields,
            .decls = &.{},
            .is_tuple = false,
        } });
    }

    pub fn ParsedPositionals(comptime command: Command) type {
        const positionals = command.positionals;
        var allow_required = true;
        for (positionals) |positional| {
            if (positional.required) {
                if (!allow_required) @compileError("all required positional arguments must come before all optional ones");
            } else {
                allow_required = false;
            }
        }

        var fields: [positionals.len]Type.StructField = undefined;
        for (&fields, positionals) |*field, positional| {
            const T = if (positional.required) [:0]const u8 else ?[:0]const u8;
            field.* = .{
                .name = positional.name,
                .type = T,
                .default_value = null,
                .is_comptime = false,
                .alignment = @alignOf(T),
            };
        }

        return @Type(Type{ .Struct = Type.Struct{
            .layout = .auto,
            .fields = &fields,
            .decls = &.{},
            .is_tuple = false,
        } });
    }

    pub fn ParsedSubcommand(comptime command: Command) type {
        const subcommands = command.subcommands;

        if (subcommands.len == 0) return noreturn;

        var fields_tag: [subcommands.len]Type.EnumField = undefined;
        for (&fields_tag, subcommands, 0..) |*field, subcommand, index| {
            field.* = .{
                .name = subcommand.name.subcommand,
                .value = index,
            };
        }
        const Tag = @Type(.{ .Enum = Type.Enum{
            .tag_type = std.math.IntFittingRange(0, subcommands.len -| 1),
            .fields = &fields_tag,
            .decls = &.{},
            .is_exhaustive = true,
        } });

        var fields_union: [subcommands.len]Type.UnionField = undefined;
        for (&fields_union, subcommands) |*field, subcommand| {
            // const name = comptime subcommand.name.subcommand;
            const T = subcommand.Parsed();
            field.* = .{
                .name = subcommand.name.subcommand,
                .type = T,
                .alignment = @alignOf(T),
            };
        }

        return @Type(Type{ .Union = Type.Union{
            .layout = .auto,
            .tag_type = Tag,
            .fields = &fields_union,
            .decls = &.{},
        } });
    }

    pub fn maxDepth(comptime command: Command) usize {
        var max_depth_children: usize = 0;
        for (command.subcommands) |subcommand| {
            max_depth_children = @max(max_depth_children, subcommand.maxDepth());
        }
        return 1 + max_depth_children;
    }

    pub fn emitHelp(
        command: Command,
        reason: enum { requested, misuse },
        ancestors: []const []const u8,
    ) !void {
        const stream = switch (reason) {
            .requested => std.io.getStdOut(),
            .misuse => std.io.getStdErr(),
        };

        var writer = std.io.bufferedWriter(stream.writer());
        try command.writeUsage(writer.writer(), ancestors);
        try writer.flush();
    }

    pub fn writeUsage(command: Command, writer: anytype, ancestors: []const []const u8) !void {
        if (command.description) |description| {
            try writer.print("{s}\n\n", .{
                std.mem.trim(u8, description, &std.ascii.whitespace),
            });
        }

        {
            try writer.print("Usage:", .{});
            for (ancestors) |ancestor| try writer.print(" {s}", .{ancestor});

            try writer.print(" [OPTIONS]", .{});

            var optional_count: usize = 0;
            for (command.positionals) |positional| {
                if (positional.required) {
                    try writer.print(" <{s}>", .{positional.name});
                } else {
                    try writer.print(" [<{s}>", .{positional.name});
                    optional_count += 1;
                }
            }
            try writer.writeByteNTimes(']', optional_count);

            if (command.subcommands.len != 0) {
                try writer.print(" [COMMAND]", .{});
            }
            try writer.print("\n\n", .{});
        }

        {
            try writer.print("Options:\n", .{});

            var longest_flag = "-h, --help".len;
            for (command.flags) |flag| {
                var counter = std.io.countingWriter(std.io.null_writer);
                try writeUsageFlagDefinition(flag, counter.writer());
                longest_flag = @max(longest_flag, counter.bytes_written);
            }

            for (command.flags) |flag| try writeFlagUsage(writer, flag, longest_flag);
            try writeFlagUsage(writer, .{ .long = "help", .short = 'h', .description = "print this help" }, longest_flag);
            try writer.print("\n", .{});
        }

        if (command.subcommands.len != 0) {
            try writer.print("Commands:\n", .{});

            var longest_command: usize = 0;
            for (command.subcommands) |subcommand| {
                longest_command = @max(longest_command, subcommand.name.subcommand.len);
            }

            for (command.subcommands) |subcommand| {
                const name = subcommand.name.subcommand;
                try writer.print("    {s}", .{name});
                try writer.writeByteNTimes(' ', longest_command - name.len);
                if (subcommand.description) |description| {
                    try writer.print("   {s}", .{std.mem.trim(u8, description, &std.ascii.whitespace)});
                }
                try writer.print("\n", .{});
            }
            try writer.print("\n", .{});
        }
    }

    fn writeUsageFlagDefinition(flag: Flag, writer: anytype) !void {
        if (flag.short) |short| {
            try writer.print("-{c}, --{s}", .{ short, flag.long });
        } else {
            try writer.print("    --{s}", .{flag.long});
        }

        if (flag.value) |value| {
            try writer.print(" <{s}>", .{value.name});
        }
    }

    fn writeFlagUsage(writer: anytype, flag: Flag, longest_flag: usize) !void {
        try writer.print("  ", .{});

        var counter = std.io.countingWriter(std.io.null_writer);
        try writeUsageFlagDefinition(flag, counter.writer());
        try writeUsageFlagDefinition(flag, writer);
        try writer.writeByteNTimes(' ', longest_flag - counter.bytes_written + 3);

        if (flag.description) |description| {
            try writer.print("{s}", .{std.mem.trim(u8, description, &std.ascii.whitespace)});
        }

        try writer.print("\n", .{});
    }
};

pub const Flag = struct {
    long: [:0]const u8,
    short: ?u8 = null,
    value: ?FlagValue = null,
    description: ?[]const u8 = null,

    fn Value(flag: Flag) type {
        const value = flag.value orelse return bool;
        return if (value.required) [:0]const u8 else ?[:0]const u8;
    }
};

pub const FlagValue = struct {
    name: []const u8,
    required: bool = false,
};

pub const Positional = struct {
    name: [:0]const u8,
    required: bool = true,
    default: ?[]const u8 = null,
    description: ?[]const u8 = null,
};

pub const ParseOptions = struct {
    alloc: std.mem.Allocator,
    args: ArgumentIterator,
};

pub fn parse(comptime command: Command, args: *ArgumentIterator) !command.Parsed() {
    std.debug.assert(command.name == .root);

    var buffer: [command.maxDepth()][:0]const u8 = undefined;
    var ancestors = AncestorStack{ .buffer = &buffer, .len = 0 };
    ancestors.push(args.next() orelse return error.ProgramMissing);
    return parseInner(command, args, &ancestors);
}

const AncestorStack = struct {
    buffer: [][:0]const u8,
    len: usize,

    pub fn push(stack: *AncestorStack, name: [:0]const u8) void {
        stack.buffer[stack.len] = name;
        stack.len += 1;
    }

    pub fn pop(stack: *AncestorStack) void {
        stack.len -= 1;
    }

    pub fn slice(stack: *const AncestorStack) []const [:0]const u8 {
        return stack.buffer[0..stack.len];
    }
};

fn parseInner(comptime command: Command, args: *ArgumentIterator, ancestors: *AncestorStack) !command.Parsed() {
    var flags = BoundedStringMap(command.flags.len, [:0]const u8){};
    var positionals = std.BoundedArray([:0]const u8, command.positionals.len){};

    const subcommand: ?command.ParsedSubcommand() = parsing: {
        while (args.next()) |arg| {
            if (std.mem.startsWith(u8, arg, "--")) {
                // long flag: --foo --bar=123
                const name_end = std.mem.indexOfScalar(u8, arg, '=');
                const name = arg[2 .. name_end orelse arg.len];
                const value_inline = if (name_end) |end| arg[end + 1 ..] else null;

                if (name.len == 0) break; // found '--' everything else is positional

                const flag = for (command.flags) |flag| {
                    if (!std.mem.eql(u8, flag.long, name)) continue;
                    break flag;
                } else {
                    if (std.mem.eql(u8, name, "help")) {
                        try command.emitHelp(.requested, ancestors.slice());
                        std.process.exit(0);
                    }

                    command.emitHelp(.misuse, ancestors.slice()) catch {};
                    log.err("unknown flag '--{s}'", .{name});
                    return error.FlagUnexpected;
                };

                if (flag.value) |value| {
                    const text = value_inline orelse args.next() orelse {
                        command.emitHelp(.misuse, ancestors.slice()) catch {};
                        log.err("the flag '--{s}' expects a value '<{s}>'", .{ name, value.name });
                        return error.FlagMissingValue;
                    };
                    if (flags.put(flag.long, text) != null) {
                        command.emitHelp(.misuse, ancestors.slice()) catch {};
                        command.emitHelp(.misuse, ancestors.slice()) catch {};
                        log.err("duplicate flag '--{s}' specified multiple times", .{name});
                        return error.FlagDuplicate;
                    }
                } else {
                    if (value_inline) |value| {
                        command.emitHelp(.misuse, ancestors.slice()) catch {};
                        log.err("the flag '--{s}' did not expect a value, but found '{s}'", .{ name, value });
                        return error.FlagUnexpectedValue;
                    }
                    if (flags.put(flag.long, "") != null) {
                        command.emitHelp(.misuse, ancestors.slice()) catch {};
                        log.err("duplicate flag '--{s}' specified multiple times", .{name});
                        return error.FlagDuplicate;
                    }
                }
            } else if (std.mem.startsWith(u8, arg, "-")) {
                // short flag: -abc=123

                const names_end = std.mem.indexOfScalar(u8, arg, '=');
                const names = arg[1 .. names_end orelse arg.len];
                const value_inline = if (names_end) |end| arg[end + 1 ..] else null;

                for (0.., names) |index, name| {
                    const is_last = index == names.len - 1;

                    const flag = for (command.flags) |flag| {
                        if (flag.short != name) continue;
                        break flag;
                    } else {
                        if (name == 'h') {
                            try command.emitHelp(.requested, ancestors.slice());
                            std.process.exit(0);
                        }

                        log.err("unknown flag '-{c}'", .{name});
                        return error.FlagUnexpected;
                    };

                    if (flag.value) |value| {
                        if (!is_last) {
                            command.emitHelp(.misuse, ancestors.slice()) catch {};
                            log.err("the flag '-{c}' expects a value '<{s}>'", .{ name, value.name });
                            return error.FlagMissingValue;
                        }

                        const text = value_inline orelse args.next() orelse {
                            command.emitHelp(.misuse, ancestors.slice()) catch {};
                            log.err("the flag '-{c}' expects a value '<{s}>'", .{ name, value.name });
                            return error.FlagMissingValue;
                        };

                        if (flags.put(flag.long, text) != null) {
                            command.emitHelp(.misuse, ancestors.slice()) catch {};
                            log.err("duplicate flag '-{c}' (--{s}) specified multiple times", .{ name, flag.long });
                            return error.FlagDuplicate;
                        }
                    } else {
                        if (is_last) {
                            if (value_inline) |value| {
                                command.emitHelp(.misuse, ancestors.slice()) catch {};
                                log.err("the flag '-{c}' did not expect a value, but found '{s}'", .{ name, value });
                                return error.FlagUnexpectedValue;
                            }
                        }
                        if (flags.put(flag.long, "") != null) {
                            command.emitHelp(.misuse, ancestors.slice()) catch {};
                            log.err("duplicate flag '-{c}' (--{s}) specified multiple times", .{ name, flag.long });
                            return error.FlagDuplicate;
                        }
                    }
                }
            } else {
                // positional

                inline for (command.subcommands) |subcommand| {
                    const name = comptime subcommand.name.subcommand;
                    if (std.mem.eql(u8, arg, name)) {
                        ancestors.push(name);
                        defer ancestors.pop();
                        const inner = try parseInner(subcommand, args, ancestors);
                        break :parsing @unionInit(command.ParsedSubcommand(), name, inner);
                    }
                }

                const next_index = positionals.len;
                if (next_index >= command.positionals.len) {
                    command.emitHelp(.misuse, ancestors.slice()) catch {};
                    log.err("unexpected positional argument '{s}'", .{arg});
                    return error.PositionalUnexpected;
                }
                positionals.appendAssumeCapacity(arg);
            }
        }

        while (args.next()) |arg| {
            const next_index = positionals.len;
            if (next_index >= command.positionals.len) {
                command.emitHelp(.misuse, ancestors.slice()) catch {};
                log.err("unexpected positional argument '{s}'", .{arg});
                return error.PositionalUnexpected;
            }
            positionals.appendAssumeCapacity(arg);
        }

        break :parsing null;
    };

    var parsed: command.Parsed() = undefined;

    inline for (command.flags) |flag| {
        const found = flags.get(flag.long);
        if (flag.value) |value| {
            if (found) |x| {
                @field(parsed.flags, flag.long) = x;
            } else {
                if (value.required) {
                    command.emitHelp(.misuse, ancestors.slice()) catch {};
                    log.err("missing a value for required flag '--{s}'", .{flag.long});
                    return error.FlagMissingValue;
                } else {
                    @field(parsed.flags, flag.long) = null;
                }
            }
        } else {
            @field(parsed.flags, flag.long) = found != null;
        }
    }

    inline for (command.positionals, 0..) |positional, index| {
        if (index < positionals.len) {
            @field(parsed.positionals, positional.name) = positionals.get(index);
        } else if (positional.required) {
            command.emitHelp(.misuse, ancestors.slice()) catch {};
            log.err("missing value for positional argument '<{s}>'", .{positional.name});
            return error.PositionalMissing;
        } else {
            @field(parsed.positionals, positional.name) = null;
        }
    }

    if (@hasField(command.Parsed(), "subcommand")) {
        parsed.subcommand = subcommand;
    }

    return parsed;
}

pub const ArgumentIterator = union(enum) {
    slice: []const [:0]const u8,
    process: std.process.ArgIterator,

    pub fn next(args: *ArgumentIterator) ?[:0]const u8 {
        switch (args.*) {
            .slice => |*x| {
                if (x.len == 0) return null;
                const first = x.*[0];
                x.* = x.*[1..];
                return first;
            },
            .process => |*iter| return iter.next(),
        }
    }
};

fn BoundedStringMap(comptime capacity: usize, comptime T: type) type {
    return struct {
        entries: [capacity]Entry = undefined,
        len: usize = 0,

        const Entry = struct {
            key: []const u8,
            value: T,
        };

        const Self = @This();

        pub fn put(map: *Self, key: []const u8, value: T) ?T {
            for (map.entries[0..map.len]) |*entry| {
                if (std.mem.eql(u8, entry.key, key)) {
                    const old = entry.value;
                    entry.value = value;
                    return old;
                }
            } else {
                map.entries[map.len] = .{ .key = key, .value = value };
                map.len += 1;
                return null;
            }
        }

        pub fn get(map: *Self, key: []const u8) ?T {
            for (map.entries[0..map.len]) |*entry| {
                if (std.mem.eql(u8, entry.key, key)) {
                    return entry.value;
                }
            } else {
                return null;
            }
        }
    };
}

fn checkParse(comptime command: Command, args: []const [:0]const u8, expected: command.Parsed()) !void {
    var iterator = ArgumentIterator{ .slice = args };
    const parsed: command.Parsed() = try parse(command, &iterator);
    try expectEqualJson(expected, parsed);
}

fn expectEqualJson(expected: anytype, found: anytype) !void {
    const alloc = std.testing.allocator;

    const string_expected = try std.json.stringifyAlloc(std.testing.allocator, expected, .{ .whitespace = .indent_2 });
    defer alloc.free(string_expected);

    const string_found = try std.json.stringifyAlloc(std.testing.allocator, found, .{ .whitespace = .indent_2 });
    defer alloc.free(string_found);

    try std.testing.expectEqualStrings(string_expected, string_found);
}

test "parse flags" {
    try checkParse(
        Command{
            .name = .root,
            .flags = &.{
                Flag{ .long = "foo" },
                Flag{ .long = "bar", .value = .{ .name = "value" } },
                Flag{ .long = "quux", .short = 'q' },
            },
        },
        &.{ "my-exe", "--foo", "--bar=baz", "-q" },
        .{ .flags = .{ .foo = true, .bar = "baz", .quux = true } },
    );
}

test "parse positionals" {
    try checkParse(
        Command{
            .name = .root,
            .positionals = &.{ .{ .name = "number" }, .{ .name = "path" } },
        },
        &.{ "my-exe", "123", "./path/to/thingy" },
        .{ .positionals = .{ .number = "123", .path = "./path/to/thingy" } },
    );
}

test "parse subcommand" {
    try checkParse(
        Command{
            .name = .root,
            .subcommands = &.{.{
                .name = .{ .subcommand = "build" },
                .flags = &.{.{ .long = "watch" }},
            }},
        },
        &.{ "zig", "build", "--watch" },
        .{ .subcommand = .{ .build = .{ .flags = .{ .watch = true } } } },
    );
}

fn checkUsage(comptime command: Command, expected: []const u8) !void {
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();
    try command.writeUsage(buffer.writer(), &.{"<program>"});
    try std.testing.expectEqualStrings(expected, buffer.items);
}

test "help flag" {
    try std.testing.expectError(error.PrintHelp, checkParse(
        .{
            .name = .root,
            .flags = &.{
                .{ .long = "foo", .short = 'f', .description = "does something to your foo's" },
                .{ .long = "bar", .value = .{ .name = "count" }, .description = "number of gold bars to produce" },
            },
        },
        &.{ "my-exe", "--foo", "--help" },
        undefined,
    ));
}

test "print usage" {
    const command = Command{
        .name = .root,
        .flags = &.{
            .{ .long = "foo", .short = 'f', .description = "does something to your foo's" },
            .{ .long = "bar", .value = .{ .name = "count" }, .description = "number of gold bars to produce" },
        },
        .subcommands = &.{
            .{
                .name = .{ .subcommand = "build" },
                .description = "consults the IKEA manual",
                .flags = &.{.{ .long = "watch", .description = "re-run when any source file changes" }},
                .positionals = &.{.{ .name = "path" }},
            },
            .{
                .name = .{ .subcommand = "check" },
                .description = "ensures your program is bug-free",
                .flags = &.{.{ .long = "verify", .description = "ensures your program is bug-free" }},
            },
        },
        .description = "builds your favourite software",
    };

    try checkUsage(command,
        \\builds your favourite software
        \\
        \\Usage: <program> [OPTIONS] [COMMAND]
        \\
        \\Options:
        \\  -f, --foo           does something to your foo's
        \\      --bar <count>   number of gold bars to produce
        \\  -h, --help          print this help
        \\
        \\Commands:
        \\    build   consults the IKEA manual
        \\    check   ensures your program is bug-free
        \\
        \\
    );

    try checkUsage(command.subcommands[0],
        \\consults the IKEA manual
        \\
        \\Usage: <program> [OPTIONS] <path>
        \\
        \\Options:
        \\      --watch   re-run when any source file changes
        \\  -h, --help    print this help
        \\
        \\
    );
}
