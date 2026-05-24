const std = @import("std");

const instr = @import("./8086_instruction.zig");

const Simulator = struct {
    instructionStream: []const u8 = &.{},
    ip: u16 = 0,

    ax: u16 = 0,
    bx: u16 = 0,
    cx: u16 = 0,
    dx: u16 = 0,

    bp: u16 = 0,
    di: u16 = 0,
    si: u16 = 0,
    sp: u16 = 0,

    flags: u16 = 0b0000_0000_0000_0000,
    // 0,0,0,0 - OF,DF,IF,TF _ SF,ZF,0,AF _ 0,PF,0,CF

    pub fn format(s: Simulator, w: *std.Io.Writer) !void {
        try w.writeAll("Simulator{\n");
        try w.print("  instructionStream: {d} {any}\n", .{ s.instructionStream.len, s.instructionStream });
        try w.print("  ip: {}\n", .{s.ip});
        try w.print("  ax: {}\n", .{s.ax});
        try w.print("  bx: {}\n", .{s.bx});
        try w.print("  cx: {}\n", .{s.cx});
        try w.print("  dx: {}\n", .{s.dx});
        try w.print("  bp: {}\n", .{s.bp});
        try w.print("  di: {}\n", .{s.di});
        try w.print("  si: {}\n", .{s.si});
        try w.print("  sp: {}\n", .{s.sp});
        try w.print("  SF: {}\n", .{s.getSF()});
        try w.print("  ZF: {}\n", .{s.getZF()});
        try w.writeAll("}\n");
    }

    fn diff(s: *Simulator, other: Simulator, w: *std.Io.Writer) !void {
        if (s.ip != other.ip) try w.print("ip: {} -> {}\n", .{ s.ip, other.ip });
        if (s.ax != other.ax) try w.print("ax: {} -> {}\n", .{ s.ax, other.ax });
        if (s.bx != other.bx) try w.print("bx: {} -> {}\n", .{ s.bx, other.bx });
        if (s.cx != other.cx) try w.print("cx: {} -> {}\n", .{ s.cx, other.cx });
        if (s.dx != other.dx) try w.print("dx: {} -> {}\n", .{ s.dx, other.dx });
        if (s.bp != other.bp) try w.print("bp: {} -> {}\n", .{ s.bp, other.bp });
        if (s.di != other.di) try w.print("di: {} -> {}\n", .{ s.di, other.di });
        if (s.si != other.si) try w.print("si: {} -> {}\n", .{ s.si, other.si });
        if (s.sp != other.sp) try w.print("sp: {} -> {}\n", .{ s.sp, other.sp });
        if (s.getSF() != other.getSF()) try w.print("SF: {} -> {}\n", .{ s.getSF(), other.getSF() });
        if (s.getZF() != other.getZF()) try w.print("ZF: {} -> {}\n", .{ s.getZF(), other.getZF() });
    }

    pub fn execute(s: Simulator, instructionStream: []const u8) Simulator {
        var sMut = s;
        sMut.instructionStream = instructionStream;
        sMut.ip = 0;

        return sMut._execute();
    }

    fn _execute(s: Simulator) Simulator {
        var sMut = s;
        const instruction = instr.Instruction.fromInstructionStream(sMut.instructionStream[sMut.ip..]);

        sMut.ip += instruction.offset();

        switch (instruction) {
            .movRsmToFromRsm => |i| sMut.rsmAndRsm(.{ .mov = i }),
            .movImmToReg => |i| sMut.movImmToReg(i),

            .addRsmToFromRsm => |i| sMut.rsmAndRsm(.{ .add = i }),
            .addImmToRsm => |i| sMut.immAndRsm(.{ .add = i }),

            .subRsmToFromRsm => |i| sMut.rsmAndRsm(.{ .sub = i }),
            .subImmFromRsm => |i| sMut.immAndRsm(.{ .sub = i }),

            .cmpRsmAndR => |i| sMut.rsmAndRsm(.{ .cmp = i }),
            .cmpImmWithRsm => |i| sMut.immAndRsm(.{ .cmp = i }),

            .retJne => |i| sMut.retJne(i),

            inline else => {
                std.debug.print("instruction not supported:: {f}\n", .{instruction});
                unreachable;
            },
        }

        return if (sMut.ip == sMut.instructionStream.len)
            sMut
        else
            sMut._execute();
    }

    fn getRegister(s: *const Simulator, r: instr.Register) u16 {
        return switch (r) {
            .ax => s.ax,
            .bx => s.bx,
            .cx => s.cx,
            .dx => s.dx,
            .bp => s.bp,
            .di => s.di,
            .si => s.si,
            .sp => s.sp,
            inline else => {
                std.debug.print("byte registers not supported:: {f}\n", .{r});
                unreachable;
            },
        };
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

    fn getZF(s: *const Simulator) bool {
        return (s.flags >> 6 & 1) > 0;
    }
    fn setZF(s: *Simulator, v: u16) void {
        const mask: u16 = 1 << 6;

        if (v == 0)
            s.flags |= mask
        else
            s.flags &= ~mask;
    }
    fn getSF(s: *const Simulator) bool {
        return (s.flags >> 7 & 1) > 0;
    }
    fn setSF(s: *Simulator, v: u16) void {
        const mask: u16 = 1 << 7;

        if ((v & (1 << 15)) > 0)
            s.flags |= mask
        else
            s.flags &= ~mask;
    }

    fn rsmAndRsm(s: *Simulator, i: RsmAndRsm) void {
        const result = blk: switch (i.dst()) {
            .reg => |dst| {
                switch (i.src()) {
                    .reg => |src| {
                        const dstVal = s.getRegister(dst);
                        const srcVal = s.getRegister(src);

                        switch (i) {
                            .mov => {
                                s.setRegister(dst, srcVal);
                                break :blk null;
                            },
                            .add => {
                                const result = dstVal +% srcVal;
                                s.setRegister(dst, result);
                                break :blk result;
                            },
                            .sub => {
                                const result = dstVal -% srcVal;
                                s.setRegister(dst, result);
                                break :blk result;
                            },
                            .cmp => break :blk dstVal -% srcVal,
                        }
                    },
                    .mem => |src| {
                        std.debug.print("memory srcs not supported (yet):: {f}\n", .{src});
                        unreachable;
                    },
                }
            },
            .mem => |dst| {
                std.debug.print("memory dsts not supported (yet):: {f}\n", .{dst});
                unreachable;
            },
        };

        if (result) |r| {
            s.setSF(r);
            s.setZF(r);
        }
    }

    fn immAndRsm(s: *Simulator, i: ImmAndRsm) void {
        const result = blk: switch (i.dst()) {
            .reg => |dst| {
                const dstVal = s.getRegister(dst);
                const srcVal = i.src().toU16();

                switch (i) {
                    // .mov => {
                    //     break :blk null;
                    // },
                    .add => {
                        const result = dstVal +% srcVal;
                        s.setRegister(dst, result);
                        break :blk result;
                    },
                    .sub => {
                        const result = dstVal -% srcVal;
                        s.setRegister(dst, result);
                        break :blk result;
                    },
                    .cmp => break :blk dstVal -% srcVal,
                }
            },
            .mem => |dst| {
                std.debug.print("memory dsts not supported (yet):: {f}\n", .{dst});
                unreachable;
            },
        };

        // if (result) |r| {
        s.setSF(result);
        s.setZF(result);
        // }
    }

    fn movImmToReg(s: *Simulator, i: instr.MovImmToReg) void {
        s.setRegister(i.dst, i.src.toU16());
    }
    // movMemToAcc
    // movAccToMem
    // movRsmToSegR
    // movSegRToRsm

    fn retJne(s: *Simulator, i: instr.RetJne) void {
        if (s.getZF()) {
            return;
        }

        if (i.ipinc8 >= 0)
            s.ip += @intCast(i.ipinc8)
        else
            s.ip -= @abs(i.ipinc8);
    }
};

const RsmAndRsm = union(enum) {
    mov: instr.MovRsmToFromRsm,
    add: instr.AddRsmToFromRsm,
    sub: instr.SubRsmToFromRsm,
    cmp: instr.CmpRsmAndR,

    fn dst(s: RsmAndRsm) instr.RegisterOrMemory {
        return switch (s) {
            inline else => |i| i.dst,
        };
    }

    fn src(s: RsmAndRsm) instr.RegisterOrMemory {
        return switch (s) {
            inline else => |i| i.src,
        };
    }
};

const ImmAndRsm = union(enum) {
    // mov: instr.MovImmToRsm,
    add: instr.AddImmToRsm,
    sub: instr.SubImmFromRsm,
    cmp: instr.CmpImmWithRsm,

    fn dst(s: ImmAndRsm) instr.RegisterOrMemory {
        return switch (s) {
            inline else => |i| i.dst,
        };
    }

    fn src(s: ImmAndRsm) instr.ByteOrWord {
        return switch (s) {
            inline else => |i| i.src,
        };
    }
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

test "listing_0044_register_movs" {
    const sim: Simulator = .{};
    const finalSim = sim.execute(&[_]u8{ 184, 1, 0, 187, 2, 0, 185, 3, 0, 186, 4, 0, 137, 196, 137, 221, 137, 206, 137, 215, 137, 226, 137, 233, 137, 243, 137, 248 });

    try std.testing.expectEqual(4, finalSim.ax);
    try std.testing.expectEqual(3, finalSim.bx);
    try std.testing.expectEqual(2, finalSim.cx);
    try std.testing.expectEqual(1, finalSim.dx);
    try std.testing.expectEqual(1, finalSim.sp);
    try std.testing.expectEqual(2, finalSim.bp);
    try std.testing.expectEqual(3, finalSim.si);
    try std.testing.expectEqual(4, finalSim.di);
}

test "listing_0046_add_sub_cmp" {
    const sim: Simulator = .{};
    const finalSim = sim.execute(&[_]u8{ 187, 3, 240, 185, 1, 15, 41, 203, 188, 230, 3, 189, 231, 3, 57, 229, 129, 197, 3, 4, 129, 237, 234, 7 });

    try std.testing.expectEqual(57602, finalSim.bx);
    try std.testing.expectEqual(3841, finalSim.cx);
    try std.testing.expectEqual(998, finalSim.sp);
    try std.testing.expectEqual(false, finalSim.getSF());
    try std.testing.expectEqual(true, finalSim.getZF());
}

test "listing_0048_ip_register" {
    const sim = Simulator{};
    const iStream = [_]u8{ 185, 200, 0, 137, 203, 129, 193, 232, 3, 187, 208, 7, 41, 217 };
    const finalSim = sim.execute(&iStream);

    try std.testing.expectEqual(2000, finalSim.bx);
    try std.testing.expectEqual(64736, finalSim.cx);
    try std.testing.expectEqual(iStream.len, finalSim.ip);
    try std.testing.expect(finalSim.getSF());
    try std.testing.expect(!finalSim.getZF());
}

test "listing_0049_conditional_jumps" {
    const sim = Simulator{};
    const iStream = [_]u8{ 185, 3, 0, 187, 232, 3, 131, 195, 10, 131, 233, 1, 117, 248 };
    const finalSim = sim.execute(&iStream);

    try std.testing.expectEqual(1030, finalSim.bx);
    try std.testing.expectEqual(iStream.len, finalSim.ip);
    try std.testing.expect(!finalSim.getSF());
    try std.testing.expect(finalSim.getZF());
}
