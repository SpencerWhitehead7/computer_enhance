const std = @import("std");
const Io = std.Io;
const debug = std.debug;
const fmt = std.fmt;
const mem = std.mem;
const process = std.process;

const json = @import("./haversine_json_parser.zig");
const ref = @import("./haversine_reference.zig");

pub fn main(init: process.Init) !void {
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

    const cwd = Io.Dir.cwd();
    const inFileDirPath = "homework/part2/inputs";
    const inFileDir = try cwd.openDir(io, inFileDirPath, .{});
    defer inFileDir.close(io);

    const inFileName = try fmt.allocPrint(a, "{d}.json", .{size});
    const outFileContents = try inFileDir.readFileAlloc(io, inFileName, a, Io.Limit.unlimited);

    var parser = json.Parser.init(outFileContents);
    const parsed = try parser.parse(a);

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

            debug.print("recordedSum:: {d}\ncalculatedSum:: {d}\ndifference:: {d}\n", .{ recordedSum, calculatedSum, recordedSum - calculatedSum });
        },
        inline else => return error.InvalidInput,
    }
}
