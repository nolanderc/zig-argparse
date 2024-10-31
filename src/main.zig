const std = @import("std");
const argparse = @import("argparse");

pub fn main() !u8 {
    const command = argparse.Command{
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

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    var iterator = argparse.ArgumentIterator{ .process = try std.process.ArgIterator.initWithAllocator(alloc) };
    defer iterator.process.deinit();

    const args = argparse.parse(command, &iterator) catch return 1;
    std.debug.print("{}", .{std.json.fmt(args, .{ .whitespace = .indent_2 })});

    return 0;
}
