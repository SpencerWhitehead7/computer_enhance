const std = @import("std");

const instr = @import("./8086_instruction.zig");

const Simulator = struct {
    instructionStream: []const u8 = &.{},
    i: u64 = 0,

    ax: u16 = 0,
    bx: u16 = 0,
    cx: u16 = 0,
    dx: u16 = 0,

    bp: u16 = 0,
    di: u16 = 0,
    si: u16 = 0,
    sp: u16 = 0,

    pub fn format(s: Simulator, w: *std.Io.Writer) !void {
        try w.writeAll("Simulator{\n");
        try w.print("  instructionStream: {d} {any}\n", .{ s.instructionStream.len, s.instructionStream });
        try w.print("  i: {}\n", .{s.i});
        try w.print("  ax: {}\n", .{s.ax});
        try w.print("  bx: {}\n", .{s.bx});
        try w.print("  cx: {}\n", .{s.cx});
        try w.print("  dx: {}\n", .{s.dx});
        try w.print("  bp: {}\n", .{s.bp});
        try w.print("  di: {}\n", .{s.di});
        try w.print("  si: {}\n", .{s.si});
        try w.print("  sp: {}\n", .{s.sp});
        try w.writeAll("}\n");
    }

    fn diff(s: *Simulator, other: Simulator, w: *std.Io.Writer) !void {
        if (s.i != other.i) try w.print("i: {} -> {}\n", .{ s.i, other.i });
        if (s.ax != other.ax) try w.print("ax: {} -> {}\n", .{ s.ax, other.ax });
        if (s.bx != other.bx) try w.print("bx: {} -> {}\n", .{ s.bx, other.bx });
        if (s.cx != other.cx) try w.print("cx: {} -> {}\n", .{ s.cx, other.cx });
        if (s.dx != other.dx) try w.print("dx: {} -> {}\n", .{ s.dx, other.dx });
        if (s.bp != other.bp) try w.print("bp: {} -> {}\n", .{ s.bp, other.bp });
        if (s.di != other.di) try w.print("di: {} -> {}\n", .{ s.di, other.di });
        if (s.si != other.si) try w.print("si: {} -> {}\n", .{ s.si, other.si });
        if (s.sp != other.sp) try w.print("sp: {} -> {}\n", .{ s.sp, other.sp });
    }

    pub fn execute(s: Simulator, instructionStream: []const u8) Simulator {
        var sMut = s;
        sMut.instructionStream = instructionStream;
        sMut.i = 0;

        return sMut._execute();
    }

    fn _execute(s: Simulator) Simulator {
        var sMut = s;
        const instruction = instr.Instruction.fromInstructionStream(sMut.instructionStream[sMut.i..]);
        switch (instruction) {
            .movImmToReg => |i| sMut.movImmToReg(i),
            inline else => {
                std.debug.print("instruction not supported:: {f}\n", .{instruction});
                unreachable;
            },
        }

        sMut.i += instruction.offset();

        return if (sMut.i == sMut.instructionStream.len)
            sMut
        else
            sMut._execute();
    }

    fn setRegister(s: *Simulator, r: instr.Register, v: u16) void {
        switch (r) {
            .ax => s.ax = v,
            .bx => s.bx = v,
            .cx => s.cx = v,
            .dx => s.dx = v,
            .bp => s.bp = v,
            .di => s.di = v,
            .si => s.si = v,
            .sp => s.sp = v,
            inline else => {
                std.debug.print("byte registers not supported:: {f}\n", .{r});
                unreachable;
            },
        }
    }

    // movRsmToFromRsm
    // movImmToRsm
    fn movImmToReg(s: *Simulator, i: instr.MovImmToReg) void {
        s.setRegister(i.dst, i.src.toU16());
    }
    // movMemToAcc
    // movAccToMem
    // movRsmToSegR
    // movSegRToRsm
};

test "listing_0043_immediate_movs" {
    const sim: Simulator = .{};
    const finalSim = sim.execute(&[_]u8{ 184, 1, 0, 187, 2, 0, 185, 3, 0, 186, 4, 0, 188, 5, 0, 189, 6, 0, 190, 7, 0, 191, 8, 0 });

    try std.testing.expectEqual(1, finalSim.ax);
    try std.testing.expectEqual(2, finalSim.bx);
    try std.testing.expectEqual(3, finalSim.cx);
    try std.testing.expectEqual(4, finalSim.dx);
    try std.testing.expectEqual(5, finalSim.sp);
    try std.testing.expectEqual(6, finalSim.bp);
    try std.testing.expectEqual(7, finalSim.si);
    try std.testing.expectEqual(8, finalSim.di);
}
