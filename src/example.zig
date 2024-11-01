const std = @import("std");
const argparse = @import("argparse");

pub fn main() !u8 {
    const command = argparse.Command{
        .name = "handyman",
        .description = "builds your favourite software",
        .flags = &.{
            .{ .long = "foo", .short = 'f', .description = "does something to your foo's" },
            .{ .long = "bar", .value = .{ .name = "amount" }, .description = "pressure in your tires" },
        },
        .subcommands = &.{
            .{
                .name = "build",
                .description = "consults the IKEA manual",
                .flags = &.{.{ .long = "watch", .description = "re-run when any source file changes" }},
                .positionals = &.{.{ .name = "path", .description = "path to your source file" }},
            },
            .{
                .name = "check",
                .description = "ensures your program is bug-free",
                .flags = &.{.{ .long = "verify", .description = "ensures your program is bug-free" }},
            },
        },
    };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    var iterator = argparse.ArgumentIterator{ .process = try std.process.ArgIterator.initWithAllocator(alloc) };
    defer iterator.process.deinit();

    const args = argparse.parse(command, &iterator) catch return 1;

    if (args.flags.foo) {
        std.debug.print("doing stuff to your foo's!\n", .{});
    }

    if (args.flags.bar) |bar| {
        std.debug.print("ensuring your tires are inflated to {s} bars\n", .{bar});
    }

    const subcommand = args.subcommand orelse {
        try command.emitHelp(.misuse, &.{});
        return 1;
    };

    switch (subcommand) {
        .build => |build| {
            std.debug.print("assembling your furniture...\n", .{});
            if (build.flags.watch) {
                std.debug.print("watching your file '{s}' closely\n", .{build.positionals.path});
            }
        },
        .check => |check| {
            std.debug.print("checking furniture for any bugs\n", .{});
            if (check.flags.verify) {
                std.debug.print("taking an extra hard look...\n", .{});
            }
        },
    }

    return 0;
}
