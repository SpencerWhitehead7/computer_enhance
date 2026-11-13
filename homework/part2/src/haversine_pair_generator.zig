const std = @import("std");
const Io = std.Io;
const debug = std.debug;
const fmt = std.fmt;
const json = std.json;
const process = std.process;

const ref = @import("./haversine_reference.zig");
const types = @import("./haversine_types.zig");
const prof = @import("./profiler.zig");

pub fn main(init: process.Init) !void {
    const a = init.arena.allocator();
    const io = init.io;

    try prof.profiler.init(a);
    defer prof.profiler.deinit();

    const args = try init.minimal.args.toSlice(a);
    if (args.len != 3) {
        const usage =
            \\Call with uint seed and uint size (in thousands, <8,000)::
            \\zig run <filepath>/<filename> -- <seed> <size>
            \\e.g.::
            \\zig run src/haversine_input_generator.zig -- 42 8
            \\
        ;
        debug.print(usage, .{});
        return;
    }

    const inputSeed = args[1];
    const seed = fmt.parseInt(u64, inputSeed, 10) catch {
        debug.print("Failed to parse seed into u64:: {s}\n", .{inputSeed});
        return error.InvalidArgument;
    };

    const inputSize = args[2];
    const size = fmt.parseInt(u64, inputSize, 10) catch {
        debug.print("Failed to parse size into u64:: {s}\n", .{inputSize});
        return error.InvalidArgument;
    };
    if (size > 8_000) {
        debug.print("Size too large (max 8,000):: {d}\n", .{size});
        return error.InvalidArgument;
    }

    const cwd = Io.Dir.cwd();

    prof.profiler.beg("generate");
    const input = try types.Input.initRandom(a, size * 1_000, seed);
    prof.profiler.end();

    prof.profiler.beg("write");
    const outFileDirPath = "homework/part2/inputs";
    try cwd.createDirPath(io, outFileDirPath);
    const outFileDir = try cwd.openDir(io, outFileDirPath, .{});
    defer outFileDir.close(io);

    const outFileName = try fmt.allocPrint(a, "{d}.json", .{size});
    const outFile = try outFileDir.createFile(io, outFileName, .{});
    defer outFile.close(io);

    var buffer: [1024 * 4]u8 = undefined;
    var outFileWriter = outFile.writerStreaming(io, &buffer);

    try json.Stringify.value(input, .{ .whitespace = .indent_2 }, &outFileWriter.interface);

    try outFileWriter.flush();
    prof.profiler.end();

    debug.print("seed:: {d}, size:: {d}\noutput:: {f}\n", .{ seed, size, input });
}
