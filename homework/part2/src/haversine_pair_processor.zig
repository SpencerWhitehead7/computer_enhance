const std = @import("std");
const Io = std.Io;
const debug = std.debug;
const fmt = std.fmt;
const mem = std.mem;
const process = std.process;

const json = @import("./haversine_json_parser.zig");
const ref = @import("./haversine_reference.zig");
const timers = @import("./timers.zig");

pub fn main(init: process.Init) !void {
    const setupStart = timers.readCPUTimer();

    const a = init.arena.allocator();
    const io = init.io;

    const args = try init.minimal.args.toSlice(a);
    if (args.len != 2) {
        const usage =
            \\Call with uint size matching input filename::
            \\zig run <filepath>/<filename> -- <seed> <size>
            \\e.g.::
            \\zig run src/haversine_input_generator.zig -- 8
            \\retrieves `homework/part2/inputs/8.json`
            \\
        ;
        debug.print(usage, .{});
        return;
    }

    const inputSize = args[1];
    const size = fmt.parseInt(u64, inputSize, 10) catch {
        debug.print("Failed to parse size into u64:: {s}\n", .{inputSize});
        return error.InvalidArgument;
    };

    const setupEnd = timers.readCPUTimer();
    const ioStart = timers.readCPUTimer();

    const cwd = Io.Dir.cwd();
    const inFileDirPath = "homework/part2/inputs";
    const inFileDir = try cwd.openDir(io, inFileDirPath, .{});
    defer inFileDir.close(io);

    const inFileName = try fmt.allocPrint(a, "{d}.json", .{size});
    const outFileContents = try inFileDir.readFileAlloc(io, inFileName, a, Io.Limit.unlimited);

    const ioEnd = timers.readCPUTimer();
    const parseStart = timers.readCPUTimer();

    var parser = json.Parser.init(outFileContents);
    const parsed = try parser.parse(a);

    const parseEnd = timers.readCPUTimer();
    const calculateStart = timers.readCPUTimer();
    var calculateEnd: u64 = 0;
    var printStart: u64 = 0;
    var printEnd: u64 = 0;

    // holy shit is this unwieldy - all the unwrapping from not being parsed into a known shape
    // that'd be a fun follow up, probably make it faster too
    switch (parsed) {
        .dict => |d| {
            const recordedSumV = d.get("sum") orelse return error.InvalidInput;
            const recordedSum = switch (recordedSumV) {
                .number => |v| v,
                inline else => return error.InvalidInput,
            };
            const pairsV = d.get("pairs") orelse return error.InvalidInput;
            const pairs = switch (pairsV) {
                .list => |v| v,
                inline else => return error.InvalidInput,
            };

            var calculatedSum: f64 = 0;
            for (pairs) |p| {
                switch (p) {
                    .list => |l| {
                        const p0 = l[0];
                        const p1 = l[1];

                        const x0 = blk: switch (p0) {
                            .dict => |cp| {
                                const y = cp.get("x") orelse return error.InvalidInput;
                                switch (y) {
                                    .number => |n| break :blk n,
                                    inline else => return error.InvalidInput,
                                }
                            },
                            inline else => return error.InvalidInput,
                        };
                        const y0 = blk: switch (p0) {
                            .dict => |cp| {
                                const y = cp.get("y") orelse return error.InvalidInput;
                                switch (y) {
                                    .number => |n| break :blk n,
                                    inline else => return error.InvalidInput,
                                }
                            },
                            inline else => return error.InvalidInput,
                        };
                        const x1 = blk: switch (p1) {
                            .dict => |cp| {
                                const y = cp.get("x") orelse return error.InvalidInput;
                                switch (y) {
                                    .number => |n| break :blk n,
                                    inline else => return error.InvalidInput,
                                }
                            },
                            inline else => return error.InvalidInput,
                        };
                        const y1 = blk: switch (p1) {
                            .dict => |cp| {
                                const y = cp.get("y") orelse return error.InvalidInput;
                                switch (y) {
                                    .number => |n| break :blk n,
                                    inline else => return error.InvalidInput,
                                }
                            },
                            inline else => return error.InvalidInput,
                        };

                        calculatedSum += ref.haversine(x0, y0, x1, y1);
                    },
                    inline else => return error.InvalidInput,
                }
            }

            calculateEnd = timers.readCPUTimer();
            printStart = timers.readCPUTimer();

            debug.print("recordedSum:: {d}\ncalculatedSum:: {d}\ndifference:: {d}\n", .{ recordedSum, calculatedSum, recordedSum - calculatedSum });

            printEnd = timers.readCPUTimer();
        },
        inline else => return error.InvalidInput,
    }

    const cpuFreq = timers.estimateCPUTimerFreq(io, 100_000);
    const fcpuFreq = @as(f64, @floatFromInt(cpuFreq));

    const totalTicksElapsed = printEnd - setupStart;
    const ftotalTicksElapsed = @as(f64, @floatFromInt(totalTicksElapsed));

    const totalMsElapsed = (ftotalTicksElapsed / fcpuFreq) * 1_000;

    debug.print("\ncpuFreq:: {d}\n", .{cpuFreq});
    debug.print(
        "{s:<12} | {d:>16} | {d:>16.2} {s:>32}\n",
        .{ "total::", totalTicksElapsed, totalMsElapsed, "(measured, not summed)" },
    );

    debug.print(
        "\n{s:<12} | {s:>16} | {s:>16} | {s:>6}\n",
        .{ "Phase", "Ticks", "Time (ms)", "%" },
    );
    debug.print(
        "{s:-<12}-+-{s:->16}-+-{s:->16}-+-{s:->6}\n",
        .{ "", "", "", "" },
    );

    printElapsed("setup", ftotalTicksElapsed, fcpuFreq, setupStart, setupEnd);
    printElapsed("io", ftotalTicksElapsed, fcpuFreq, ioStart, ioEnd);
    printElapsed("parse", ftotalTicksElapsed, fcpuFreq, parseStart, parseEnd);
    printElapsed("calculate", ftotalTicksElapsed, fcpuFreq, calculateStart, calculateEnd);
    printElapsed("print", ftotalTicksElapsed, fcpuFreq, printStart, printEnd);
}

fn printElapsed(label: []const u8, ftotalTicksElapsed: f64, fcpuFreq: f64, start: u64, end: u64) void {
    const ticksElapsed = end - start;
    const fTicksElapsed = @as(f64, @floatFromInt(ticksElapsed));

    const msElapsed = (fTicksElapsed / fcpuFreq) * 1_000;
    const percent = (fTicksElapsed / ftotalTicksElapsed) * 100;

    debug.print(
        "{s:<12} | {d:>16} | {d:>16.2} | {d:>6.2}\n",
        .{ label, ticksElapsed, msElapsed, percent },
    );
}
