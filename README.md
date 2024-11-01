
# `argparse`

A CLI argument parser for Zig.

## Features

- Flags
    - Supports both long and short versions (`--foo` and `-f`)
    - Can combine multiple short flags, as in `ls -lah`
    - Values are specified with either spaces or `=`, meaning these are equivalent:
        - `--foo 123`
        - `--foo=123`
    - Required and optional.
    - Default values.
- Positional arguments.
    - Required and optional.
    - Default values.
- Subcommands.
- Automatic help page generation.

## Usage

First, import this library:

```zig
const argparse = @import("argparse");
```

Then, you can define your root command:

```zig
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
```

Finally, parse the arguments passed to your executable:

```zig
const process_args = try std.process.ArgIterator.initWithAllocator(alloc);
var iterator = argparse.ArgumentIterator{ .process = process_args };
defer iterator.process.deinit();
const args = argparse.parse(command, &iterator) catch return 1;
```

If you then run your executable with `zig build run -- --help`, you should see the following:

```
builds your favourite software

Usage: handyman [OPTIONS] [COMMAND]

Options:
  -f, --foo            does something to your foo's
      --bar <amount>   pressure in your tires
  -h, --help           print this help

Commands:
    build   consults the IKEA manual
    check   ensures your program is bug-free
```

For a full example, see `src/example.zig`.
