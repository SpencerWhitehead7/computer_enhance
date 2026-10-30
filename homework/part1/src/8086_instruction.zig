const std = @import("std");

pub const Register = enum {
    // zig fmt: off
    al, cl, dl, bl, ah, ch, dh, bh,
    ax, cx, dx, bx, sp, bp, si, di,
    // zig fmt: on

    pub fn format(s: Register, w: *std.Io.Writer) !void {
        try switch (s) {
            inline else => |v| w.writeAll(@tagName(v)),
        };
    }
};

const REGISTER_LOOKUP = [2][8]Register{
    .{ Register.al, Register.cl, Register.dl, Register.bl, Register.ah, Register.ch, Register.dh, Register.bh },
    .{ Register.ax, Register.cx, Register.dx, Register.bx, Register.sp, Register.bp, Register.si, Register.di },
};

pub const Memory = struct {
    regBase: ?Register = null,
    regPlus: ?Register = null,
    disp: ?ByteOrWord = null,

    pub fn init(mod: u2, rsm: u3, disp: ?ByteOrWord) Memory {
        return switch (rsm) {
            0b000 => .{
                .regBase = Register.bx,
                .regPlus = Register.si,
                .disp = disp,
            },
            0b001 => .{
                .regBase = Register.bx,
                .regPlus = Register.di,
                .disp = disp,
            },
            0b010 => .{
                .regBase = Register.bp,
                .regPlus = Register.si,
                .disp = disp,
            },
            0b011 => .{
                .regBase = Register.bp,
                .regPlus = Register.di,
                .disp = disp,
            },
            0b100 => .{
                .regBase = Register.si,
                .disp = disp,
            },
            0b101 => .{
                .regBase = Register.di,
                .disp = disp,
            },
            0b110 => switch (mod) {
                0b00 => .{
                    .disp = disp,
                },
                else => .{
                    .regBase = Register.bp,
                    .disp = disp,
                },
            },
            0b111 => .{
                .regBase = Register.bx,
                .disp = disp,
            },
        };
    }

    fn eacCycles(s: *const Memory) u8 {
        const dispExists = if (s.disp) |d| d.toU16() != 0 else false;
        const regBaseExists = s.regBase != null;
        const regPlusExists = s.regPlus != null;
        const isRegBaseBP = s.regBase == Register.bp;
        const isRegBaseBX = s.regBase == Register.bx;
        const isRegPlusDI = s.regPlus == Register.di;
        const isRegPlusSI = s.regPlus == Register.si;

        if (dispExists and !regBaseExists and !regPlusExists) {
            return 6;
        } else if (!dispExists and ((regBaseExists and !regPlusExists) or (!regBaseExists and regPlusExists))) {
            return 5;
        } else if (dispExists and ((regBaseExists and !regPlusExists) or (!regBaseExists and regPlusExists))) {
            return 9;
        } else if (!dispExists and regBaseExists and regPlusExists) {
            if ((isRegBaseBP and isRegPlusDI) or (isRegBaseBX and isRegPlusSI)) {
                return 7;
            } else if ((isRegBaseBP and isRegPlusSI) or (isRegBaseBX and isRegPlusDI)) {
                return 8;
            }
        } else if (dispExists and regBaseExists and regPlusExists) {
            if ((isRegBaseBP and isRegPlusDI) or (isRegBaseBX and isRegPlusSI)) {
                return 11;
            } else if ((isRegBaseBP and isRegPlusSI) or (isRegBaseBX and isRegPlusDI)) {
                return 12;
            } else {
                std.debug.print("invalid regBase or regPlus - only bp/bx and di/si supported :: {f}\n", .{s});
                unreachable;
            }
        }

        std.debug.print("invalid memory - must have at least one of regBase, regPlus, disp :: {f}\n", .{s});
        unreachable;
    }

    fn transferCycles(s: *const Memory, transferCount: ?u8) ?u8 {
        const tc = transferCount orelse return null;
        const d = s.disp orelse return null;

        return switch (d) {
            .byte => null,
            .word => |w| if (w % 2 != 0) 4 * tc else null,
        };
    }

    pub fn format(s: Memory, w: *std.Io.Writer) !void {
        try w.writeAll("[");

        if (s.regBase) |b| {
            try w.print("{f}", .{b});
            if (s.regPlus) |p| {
                try w.print(" + {f}", .{p});
            }
            if (s.disp) |d| {
                const i16d = d.toI16();
                if (i16d > 0) try w.print(" + {d}", .{i16d});
                if (i16d < 0) try w.print(" - {d}", .{@abs(i16d)});
            }
        } else if (s.disp) |d| {
            try w.print("{f}", .{std.fmt.alt(d, .formatSigned)});
        }

        try w.writeAll("]");
    }
};

pub const RegisterOrMemory = union(enum) {
    reg: Register,
    mem: Memory,

    pub fn format(s: RegisterOrMemory, w: *std.Io.Writer) !void {
        try switch (s) {
            inline else => |v| v.format(w),
        };
    }
};

pub const ByteOrWord = union(enum) {
    byte: u8,
    word: u16,

    pub fn initByte(byte: u8) ByteOrWord {
        return .{ .byte = byte };
    }

    pub fn initWord(loByte: u8, hiByte: u8) ByteOrWord {
        return .{ .word = @as(u16, hiByte) << 8 | loByte };
    }

    pub fn toU16(s: ByteOrWord) u16 {
        return switch (s) {
            inline else => |v| @as(u16, v),
        };
    }

    pub fn toI16(s: ByteOrWord) i16 {
        return switch (s) {
            .byte => |v| @as(i8, @bitCast(v)),
            .word => |v| @as(i16, @bitCast(v)),
        };
    }

    pub fn format(s: ByteOrWord, w: *std.Io.Writer) !void {
        try switch (s) {
            inline else => |v| w.print("{b}", .{v}),
        };
    }
    pub fn formatUnsigned(s: ByteOrWord, w: *std.Io.Writer) !void {
        try switch (s) {
            inline else => |v| w.print("{d}", .{v}),
        };
    }
    pub fn formatSigned(s: ByteOrWord, w: *std.Io.Writer) !void {
        try switch (s) {
            .byte => |v| w.print("{d}", .{@as(i8, @bitCast(v))}),
            .word => |v| w.print("{d}", .{@as(i16, @bitCast(v))}),
        };
    }

    fn widthLabel(s: ByteOrWord) *const [4:0]u8 {
        return switch (s) {
            .byte => "byte",
            .word => "word",
        };
    }

    fn offset(s: ByteOrWord) u8 {
        return switch (s) {
            .byte => 1,
            .word => 2,
        };
    }
};

pub const Cost = struct {
    baseCycles: u8,
    transferCount: ?u8 = null,
    memory: ?Memory = null,

    pub fn format(s: Cost, w: *std.Io.Writer) !void {
        if (s.memory) |mem| {
            const eacCycles = mem.eacCycles();
            if (mem.transferCycles(s.transferCount)) |transferCycles| {
                const totalCycles = s.baseCycles + eacCycles + transferCycles;
                try w.print("{d} ({d} + {d}eac + {d}p)", .{ totalCycles, s.baseCycles, eacCycles, transferCycles });
            } else {
                const totalCycles = s.baseCycles + eacCycles;
                try w.print("{d} ({d} + {d}eac)", .{ totalCycles, s.baseCycles, eacCycles });
            }
        } else {
            try w.print("{d}", .{s.baseCycles});
        }
    }
};

pub const Instruction = union(enum) {
    movRsmToFromRsm: MovRsmToFromRsm,
    movImmToRsm: MovImmToRsm,
    movImmToReg: MovImmToReg,
    movMemToAcc: MovMemToAcc,
    movAccToMem: MovAccToMem,
    // movRsmToSegR: MovRsmToSegR, // wtf are these?
    // movSegRToRsm: MovSegRToRsm, // wtf are these?

    addRsmToFromRsm: AddRsmToFromRsm,
    addImmToRsm: AddImmToRsm,
    addImmToAcc: AddImmToAcc,

    subRsmToFromRsm: SubRsmToFromRsm,
    subImmFromRsm: SubImmFromRsm,
    subImmFromAcc: SubImmFromAcc,

    cmpRsmAndR: CmpRsmAndR,
    cmpImmWithRsm: CmpImmWithRsm,
    cmpImmWithAcc: CmpImmWithAcc,

    retJe: RetJe,
    retJl: RetJl,
    retJle: RetJle,
    retJb: RetJb,
    retJbe: RetJbe,
    retJp: RetJp,
    retJo: RetJo,
    retJs: RetJs,
    retJne: RetJne,
    retJnl: RetJnl,
    retJnle: RetJnle,
    retJnb: RetJnb,
    retJnbe: RetJnbe,
    retJnp: RetJnp,
    retJno: RetJno,
    retJns: RetJns,
    retLoop: RetLoop,
    retLoopz: RetLoopz,
    retLoopnz: RetLoopnz,
    retJcxz: RetJcxz,

    pub fn fromInstructionStream(instructionStream: []const u8) Instruction {
        return switch (instructionStream[0]) {
            // mov
            // 100010dw
            0b10001000...0b10001011 => .{ .movRsmToFromRsm = MovRsmToFromRsm.fromInstructionStream(instructionStream) },
            // 1100011w
            0b11000110...0b11000111 => .{ .movImmToRsm = MovImmToRsm.fromInstructionStream(instructionStream) },
            // 1011wreg
            0b10110000...0b10111111 => .{ .movImmToReg = MovImmToReg.fromInstructionStream(instructionStream) },
            //  1010000w
            0b10100000...0b10100001 => .{ .movMemToAcc = MovMemToAcc.fromInstructionStream(instructionStream) },
            //  1010001w
            0b10100010...0b10100011 => .{ .movAccToMem = MovAccToMem.fromInstructionStream(instructionStream) },
            //  10001110 => movRsmToSegR,
            //  10001100 => movSegRToRsm,

            // add 000
            // 000000dw
            0b00000000...0b00000011 => .{ .addRsmToFromRsm = AddRsmToFromRsm.fromInstructionStream(instructionStream) },
            // 0000010w
            0b00000100...0b00000101 => .{ .addImmToAcc = AddImmToAcc.fromInstructionStream(instructionStream) },

            // sub 101
            // 001010dw
            0b00101000...0b00101011 => .{ .subRsmToFromRsm = SubRsmToFromRsm.fromInstructionStream(instructionStream) },
            // 0010110w
            0b00101100...0b00101101 => .{ .subImmFromAcc = SubImmFromAcc.fromInstructionStream(instructionStream) },

            // cmp 111
            // 001110dw
            0b00111000...0b00111011 => .{ .cmpRsmAndR = CmpRsmAndR.fromInstructionStream(instructionStream) },
            // 0011110w
            0b00111100...0b00111101 => .{ .cmpImmWithAcc = CmpImmWithAcc.fromInstructionStream(instructionStream) },

            // add, sub, cmp
            // 000, 101, 111
            // 100000sw
            0b10000000...0b10000011 => |byte| {
                // imm and rsm special case where you need to check the second byte
                return switch (instructionStream[1] >> 3 & 0b111) {
                    0b000 => .{ .addImmToRsm = AddImmToRsm.fromInstructionStream(instructionStream) },
                    0b101 => .{ .subImmFromRsm = SubImmFromRsm.fromInstructionStream(instructionStream) },
                    0b111 => .{ .cmpImmWithRsm = CmpImmWithRsm.fromInstructionStream(instructionStream) },
                    else => |nextByte| {
                        std.debug.print(
                            \\Instruction not supported:: {d}:: 0b{b:0>8}
                            \\nextByte:: {d}:: 0b{b:0>8}
                        ,
                            .{ byte, byte, nextByte, nextByte },
                        );
                        unreachable;
                    },
                };
            },

            // ret
            0b01110100 => .{ .retJe = RetJe{ .ipinc8 = @bitCast(instructionStream[1]) } },
            0b01111100 => .{ .retJl = RetJl{ .ipinc8 = @bitCast(instructionStream[1]) } },
            0b01111110 => .{ .retJle = RetJle{ .ipinc8 = @bitCast(instructionStream[1]) } },
            0b01110010 => .{ .retJb = RetJb{ .ipinc8 = @bitCast(instructionStream[1]) } },
            0b01110110 => .{ .retJbe = RetJbe{ .ipinc8 = @bitCast(instructionStream[1]) } },
            0b01111010 => .{ .retJp = RetJp{ .ipinc8 = @bitCast(instructionStream[1]) } },
            0b01110000 => .{ .retJo = RetJo{ .ipinc8 = @bitCast(instructionStream[1]) } },
            0b01111000 => .{ .retJs = RetJs{ .ipinc8 = @bitCast(instructionStream[1]) } },
            0b01110101 => .{ .retJne = RetJne{ .ipinc8 = @bitCast(instructionStream[1]) } },
            0b01111101 => .{ .retJnl = RetJnl{ .ipinc8 = @bitCast(instructionStream[1]) } },
            0b01111111 => .{ .retJnle = RetJnle{ .ipinc8 = @bitCast(instructionStream[1]) } },
            0b01110011 => .{ .retJnb = RetJnb{ .ipinc8 = @bitCast(instructionStream[1]) } },
            0b01110111 => .{ .retJnbe = RetJnbe{ .ipinc8 = @bitCast(instructionStream[1]) } },
            0b01111011 => .{ .retJnp = RetJnp{ .ipinc8 = @bitCast(instructionStream[1]) } },
            0b01110001 => .{ .retJno = RetJno{ .ipinc8 = @bitCast(instructionStream[1]) } },
            0b01111001 => .{ .retJns = RetJns{ .ipinc8 = @bitCast(instructionStream[1]) } },
            0b11100010 => .{ .retLoop = RetLoop{ .ipinc8 = @bitCast(instructionStream[1]) } },
            0b11100001 => .{ .retLoopz = RetLoopz{ .ipinc8 = @bitCast(instructionStream[1]) } },
            0b11100000 => .{ .retLoopnz = RetLoopnz{ .ipinc8 = @bitCast(instructionStream[1]) } },
            0b11100011 => .{ .retJcxz = RetJcxz{ .ipinc8 = @bitCast(instructionStream[1]) } },
            else => |byte| {
                std.debug.print("Instruction not supported:: {d}:: 0b{b:0>8}\n", .{ byte, byte });
                unreachable;
            },
        };
    }

    pub fn format(s: Instruction, w: *std.Io.Writer) !void {
        try switch (s) {
            .movRsmToFromRsm => |impl| impl.format(w),
            .movImmToRsm => |impl| impl.format(w),
            .movImmToReg => |impl| impl.format(w),
            .movMemToAcc => |impl| impl.format(w),
            .movAccToMem => |impl| impl.format(w),

            .addRsmToFromRsm => |impl| impl.format(w),
            .addImmToRsm => |impl| impl.format(w),
            .addImmToAcc => |impl| impl.format(w),

            .subRsmToFromRsm => |impl| impl.format(w),
            .subImmFromRsm => |impl| impl.format(w),
            .subImmFromAcc => |impl| impl.format(w),

            .cmpRsmAndR => |impl| impl.format(w),
            .cmpImmWithRsm => |impl| impl.format(w),
            .cmpImmWithAcc => |impl| impl.format(w),

            .retJe => |impl| w.print("je {d}", .{impl.ipinc8}),
            .retJl => |impl| w.print("jl {d}", .{impl.ipinc8}),
            .retJle => |impl| w.print("jle {d}", .{impl.ipinc8}),
            .retJb => |impl| w.print("jb {d}", .{impl.ipinc8}),
            .retJbe => |impl| w.print("jbe {d}", .{impl.ipinc8}),
            .retJp => |impl| w.print("jp {d}", .{impl.ipinc8}),
            .retJo => |impl| w.print("jo {d}", .{impl.ipinc8}),
            .retJs => |impl| w.print("js {d}", .{impl.ipinc8}),
            .retJne => |impl| w.print("jne {d}", .{impl.ipinc8}),
            .retJnl => |impl| w.print("jnl {d}", .{impl.ipinc8}),
            .retJnle => |impl| w.print("jnle {d}", .{impl.ipinc8}),
            .retJnb => |impl| w.print("jnb {d}", .{impl.ipinc8}),
            .retJnbe => |impl| w.print("jnbe {d}", .{impl.ipinc8}),
            .retJnp => |impl| w.print("jnp {d}", .{impl.ipinc8}),
            .retJno => |impl| w.print("jno {d}", .{impl.ipinc8}),
            .retJns => |impl| w.print("jns {d}", .{impl.ipinc8}),
            .retLoop => |impl| w.print("loop {d}", .{impl.ipinc8}),
            .retLoopz => |impl| w.print("loopz {d}", .{impl.ipinc8}),
            .retLoopnz => |impl| w.print("loopnz {d}", .{impl.ipinc8}),
            .retJcxz => |impl| w.print("jcxz {d}", .{impl.ipinc8}),
        };
    }

    pub fn formatWithCost(s: Instruction, w: *std.Io.Writer) !void {
        try switch (s) {
            .movRsmToFromRsm => |impl| w.print("{f}    ; {f}", .{ impl, impl.cost() }),
            .movImmToRsm => |impl| w.print("{f}    ; {f}", .{ impl, impl.cost() }),
            .movImmToReg => |impl| w.print("{f}    ; {f}", .{ impl, impl.cost() }),
            .movMemToAcc => |impl| w.print("{f}    ; {f}", .{ impl, impl.cost() }),
            .movAccToMem => |impl| w.print("{f}    ; {f}", .{ impl, impl.cost() }),

            .addRsmToFromRsm => |impl| w.print("{f}    ; {f}", .{ impl, impl.cost() }),
            .addImmToRsm => |impl| w.print("{f}    ; {f}", .{ impl, impl.cost() }),
            .addImmToAcc => |impl| w.print("{f}    ; cost not implemented", .{impl}),

            .subRsmToFromRsm => |impl| w.print("{f}    ; cost not implemented", .{impl}),
            .subImmFromRsm => |impl| w.print("{f}    ; cost not implemented", .{impl}),
            .subImmFromAcc => |impl| w.print("{f}    ; cost not implemented", .{impl}),

            .cmpRsmAndR => |impl| w.print("{f}    ; cost not implemented", .{impl}),
            .cmpImmWithRsm => |impl| w.print("{f}    ; cost not implemented", .{impl}),
            .cmpImmWithAcc => |impl| w.print("{f}    ; cost not implemented", .{impl}),

            .retJe => |impl| w.print("je {d}    ; cost not implemented", .{impl.ipinc8}),
            .retJl => |impl| w.print("jl {d}    ; cost not implemented", .{impl.ipinc8}),
            .retJle => |impl| w.print("jle {d}    ; cost not implemented", .{impl.ipinc8}),
            .retJb => |impl| w.print("jb {d}    ; cost not implemented", .{impl.ipinc8}),
            .retJbe => |impl| w.print("jbe {d}    ; cost not implemented", .{impl.ipinc8}),
            .retJp => |impl| w.print("jp {d}    ; cost not implemented", .{impl.ipinc8}),
            .retJo => |impl| w.print("jo {d}    ; cost not implemented", .{impl.ipinc8}),
            .retJs => |impl| w.print("js {d}    ; cost not implemented", .{impl.ipinc8}),
            .retJne => |impl| w.print("jne {d}    ; cost not implemented", .{impl.ipinc8}),
            .retJnl => |impl| w.print("jnl {d}    ; cost not implemented", .{impl.ipinc8}),
            .retJnle => |impl| w.print("jnle {d}    ; cost not implemented", .{impl.ipinc8}),
            .retJnb => |impl| w.print("jnb {d}    ; cost not implemented", .{impl.ipinc8}),
            .retJnbe => |impl| w.print("jnbe {d}    ; cost not implemented", .{impl.ipinc8}),
            .retJnp => |impl| w.print("jnp {d}    ; cost not implemented", .{impl.ipinc8}),
            .retJno => |impl| w.print("jno {d}    ; cost not implemented", .{impl.ipinc8}),
            .retJns => |impl| w.print("jns {d}    ; cost not implemented", .{impl.ipinc8}),
            .retLoop => |impl| w.print("loop {d}    ; cost not implemented", .{impl.ipinc8}),
            .retLoopz => |impl| w.print("loopz {d}    ; cost not implemented", .{impl.ipinc8}),
            .retLoopnz => |impl| w.print("loopnz {d}    ; cost not implemented", .{impl.ipinc8}),
            .retJcxz => |impl| w.print("jcxz {d}    ; cost not implemented", .{impl.ipinc8}),
        };
    }

    pub fn offset(s: Instruction) u8 {
        return switch (s) {
            .movRsmToFromRsm => |impl| impl.offset,
            .movImmToRsm => |impl| impl.offset,
            .movImmToReg => |impl| impl.offset,
            .movMemToAcc => |impl| impl.offset,
            .movAccToMem => |impl| impl.offset,

            .addRsmToFromRsm => |impl| impl.offset,
            .addImmToRsm => |impl| impl.offset,
            .addImmToAcc => |impl| impl.offset,

            .subRsmToFromRsm => |impl| impl.offset,
            .subImmFromRsm => |impl| impl.offset,
            .subImmFromAcc => |impl| impl.offset,

            .cmpRsmAndR => |impl| impl.offset,
            .cmpImmWithRsm => |impl| impl.offset,
            .cmpImmWithAcc => |impl| impl.offset,

            .retJe, .retJl, .retJle, .retJb, .retJbe, .retJp, .retJo, .retJs, .retJne, .retJnl, .retJnle, .retJnb, .retJnbe, .retJnp, .retJno, .retJns, .retLoop, .retLoopz, .retLoopnz, .retJcxz => 2,
        };
    }
};

// =================== PARSERS ===================

fn parseRsmAndRsm(instructionStream: []const u8) struct { RegisterOrMemory, RegisterOrMemory, u8 } {
    const b0 = instructionStream[0];
    const d: u1 = @intCast(b0 >> 1 & 1);
    const w: u1 = @intCast(b0 >> 0 & 1);

    const b1 = instructionStream[1];
    const mod: u2 = @intCast(b1 >> 6 & 0b11);
    const reg: u3 = @intCast(b1 >> 3 & 0b111);
    const rsm: u3 = @intCast(b1 >> 0 & 0b111);

    const disp = switch (mod) {
        0b00 => switch (rsm) {
            // special case (direct address with 16 bit displacement)
            0b110 => ByteOrWord.initWord(instructionStream[2], instructionStream[3]),
            else => null,
        },
        0b01 => ByteOrWord.initByte(instructionStream[2]),
        0b10 => ByteOrWord.initWord(instructionStream[2], instructionStream[3]),
        0b11 => null,
    };
    const dispOffset: u8 = if (disp) |v| v.offset() else 0;

    const register = RegisterOrMemory{ .reg = REGISTER_LOOKUP[w][reg] };
    const registerOrMemory = switch (mod) {
        0b11 => RegisterOrMemory{ .reg = REGISTER_LOOKUP[w][rsm] },
        else => RegisterOrMemory{ .mem = Memory.init(mod, rsm, disp) },
    };
    const dst, const src = switch (d) {
        0 => .{ registerOrMemory, register },
        1 => .{ register, registerOrMemory },
    };
    const offset = 2 + dispOffset;

    return .{ dst, src, offset };
}

fn parseImmAndRsm(instructionStream: []const u8) struct { RegisterOrMemory, ByteOrWord, u8 } {
    const b0 = instructionStream[0];
    const s: u1 = @intCast(b0 >> 1 & 0b1);
    const w: u1 = @intCast(b0 >> 0 & 0b1);

    const b1 = instructionStream[1];
    const mod: u2 = @intCast(b1 >> 6 & 0b11);
    const rsm: u3 = @intCast(b1 >> 0 & 0b111);

    const disp = switch (mod) {
        0b00 => switch (rsm) {
            // special case (direct address with 16 bit displacement)
            0b110 => ByteOrWord.initWord(instructionStream[2], instructionStream[3]),
            else => null,
        },
        0b01 => ByteOrWord.initByte(instructionStream[2]),
        0b10 => ByteOrWord.initWord(instructionStream[2], instructionStream[3]),
        0b11 => null,
    };
    const dispOffset: u8 = if (disp) |v| v.offset() else 0;

    const dst = switch (mod) {
        0b11 => RegisterOrMemory{ .reg = REGISTER_LOOKUP[w][rsm] },
        else => RegisterOrMemory{ .mem = Memory.init(mod, rsm, disp) },
    };
    const src, const srcOffset: u8 = switch (w) {
        0 => .{ ByteOrWord.initByte(instructionStream[2 + dispOffset]), 1 },
        1 => switch (s) {
            0 => .{ ByteOrWord.initWord(instructionStream[2 + dispOffset], instructionStream[3 + dispOffset]), 2 },
            1 => .{ ByteOrWord.initWord(instructionStream[2 + dispOffset], 0), 1 },
        },
    };
    const offset = 2 + dispOffset + srcOffset;

    return .{ dst, src, offset };
}

fn parseImmAndAcc(instructionStream: []const u8) struct { Register, ByteOrWord, u8 } {
    const b0 = instructionStream[0];
    const w: u1 = @intCast(b0 >> 0 & 0b1);

    const dst, const src = switch (w) {
        0 => .{ Register.al, ByteOrWord.initByte(instructionStream[1]) },
        1 => .{ Register.ax, ByteOrWord.initWord(instructionStream[1], instructionStream[2]) },
    };
    const offset = 1 + src.offset();

    return .{ dst, src, offset };
}

// =================== MOV = Move: ===================

pub const MovRsmToFromRsm = struct {
    dst: RegisterOrMemory,
    src: RegisterOrMemory,
    offset: u8,

    pub fn fromInstructionStream(instructionStream: []const u8) MovRsmToFromRsm {
        const dst, const src, const offset = parseRsmAndRsm(instructionStream);
        return .{ .dst = dst, .src = src, .offset = offset };
    }

    pub fn cost(s: *const MovRsmToFromRsm) Cost {
        return switch (s.dst) {
            .reg => switch (s.src) {
                .reg => .{ .baseCycles = 2 },
                .mem => |src| .{ .baseCycles = 8, .transferCount = 1, .memory = src },
            },
            .mem => |dst| switch (s.src) {
                .reg => .{ .baseCycles = 9, .transferCount = 1, .memory = dst },
                .mem => {
                    std.debug.print("memory - memory MOVs invalid:: {f}\n", .{s});
                    unreachable;
                },
            },
        };
    }

    pub fn format(s: *const MovRsmToFromRsm, w: *std.Io.Writer) !void {
        try w.print("mov {f}, {f}", .{ s.dst, s.src });
    }
};
pub const MovImmToRsm = struct {
    dst: RegisterOrMemory,
    src: ByteOrWord,
    offset: u8,

    pub fn fromInstructionStream(instructionStream: []const u8) MovImmToRsm {
        const b0 = instructionStream[0];
        const w: u1 = @intCast(b0 >> 0 & 0b1);

        const b1 = instructionStream[1];
        const mod: u2 = @intCast(b1 >> 6 & 0b11);
        const rsm: u3 = @intCast(b1 >> 0 & 0b111);

        const disp = switch (mod) {
            0b00 => switch (rsm) {
                // special case (direct address with 16 bit displacement)
                0b110 => ByteOrWord.initWord(instructionStream[2], instructionStream[3]),
                else => null,
            },
            0b01 => ByteOrWord.initByte(instructionStream[2]),
            0b10 => ByteOrWord.initWord(instructionStream[2], instructionStream[3]),
            0b11 => null,
        };
        const dispOffset: u8 = if (disp) |v| v.offset() else 0;

        const dst = switch (mod) {
            0b11 => RegisterOrMemory{ .reg = REGISTER_LOOKUP[w][rsm] },
            else => RegisterOrMemory{ .mem = Memory.init(mod, rsm, disp) },
        };
        const src = switch (w) {
            0 => ByteOrWord.initByte(instructionStream[2 + dispOffset]),
            1 => ByteOrWord.initWord(instructionStream[2 + dispOffset], instructionStream[3 + dispOffset]),
        };
        const offset = 2 + dispOffset + src.offset();

        return .{ .dst = dst, .src = src, .offset = offset };
    }

    pub fn cost(s: *const MovImmToRsm) Cost {
        return switch (s.dst) {
            .reg => .{ .baseCycles = 4 },
            .mem => |dst| .{ .baseCycles = 10, .transferCount = 1, .memory = dst },
        };
    }

    pub fn format(s: *const MovImmToRsm, w: *std.Io.Writer) !void {
        try switch (s.dst) {
            .reg => w.print("mov {f}, {f}", .{ s.dst, std.fmt.alt(s.src, .formatSigned) }),
            .mem => w.print("mov {f}, {s} {f}", .{ s.dst, s.src.widthLabel(), std.fmt.alt(s.src, .formatSigned) }),
        };
    }
};
pub const MovImmToReg = struct {
    dst: Register,
    src: ByteOrWord,
    offset: u8,

    pub fn fromInstructionStream(instructionStream: []const u8) MovImmToReg {
        const b0 = instructionStream[0];
        const w: u1 = @intCast(b0 >> 3 & 1);
        const reg: u3 = @intCast(b0 >> 0 & 0b111);

        const imm = switch (w) {
            0 => ByteOrWord.initByte(instructionStream[1]),
            1 => ByteOrWord.initWord(instructionStream[1], instructionStream[2]),
        };

        return .{
            .dst = REGISTER_LOOKUP[w][reg],
            .src = imm,
            .offset = 1 + imm.offset(),
        };
    }

    pub fn cost(_: *const MovImmToReg) Cost {
        return .{ .baseCycles = 4 };
    }

    pub fn format(s: *const MovImmToReg, w: *std.Io.Writer) !void {
        try w.print("mov {f}, {f}", .{ s.dst, std.fmt.alt(s.src, .formatSigned) });
    }
};
pub const MovMemToAcc = struct {
    dst: Register,
    src: Memory,
    offset: u8,

    pub fn fromInstructionStream(instructionStream: []const u8) MovMemToAcc {
        const b0 = instructionStream[0];
        const w: u1 = @intCast(b0 & 0b1);

        const register, const disp = switch (w) {
            0 => .{ Register.al, ByteOrWord.initByte(instructionStream[1]) },
            1 => .{ Register.ax, ByteOrWord.initWord(instructionStream[1], instructionStream[2]) },
        };

        return .{
            .dst = register,
            .src = Memory{ .disp = disp },
            .offset = 1 + disp.offset(),
        };
    }

    pub fn cost(_: *const MovMemToAcc) Cost {
        return .{ .baseCycles = 10 };
    }

    pub fn format(s: *const MovMemToAcc, w: *std.Io.Writer) !void {
        try w.print("mov {f}, {f}", .{ s.dst, s.src });
    }
};
pub const MovAccToMem = struct {
    dst: Memory,
    src: Register,
    offset: u8,

    pub fn fromInstructionStream(instructionStream: []const u8) MovAccToMem {
        const b0 = instructionStream[0];
        const w: u1 = @intCast(b0 & 0b1);

        const register, const disp = switch (w) {
            0 => .{ Register.al, ByteOrWord.initByte(instructionStream[1]) },
            1 => .{ Register.ax, ByteOrWord.initWord(instructionStream[1], instructionStream[2]) },
        };

        return .{
            .dst = Memory{ .disp = disp },
            .src = register,
            .offset = 1 + disp.offset(),
        };
    }

    pub fn cost(_: *const MovAccToMem) Cost {
        return .{ .baseCycles = 10 };
    }

    pub fn format(s: *const MovAccToMem, w: *std.Io.Writer) !void {
        try w.print("mov {f}, {f}", .{ s.dst, s.src });
    }
};
// MovRsmToSegR
// MovSegRToRsm

// =================== ADD = Add: ===================

pub const AddRsmToFromRsm = struct {
    dst: RegisterOrMemory,
    src: RegisterOrMemory,
    offset: u8,

    pub fn fromInstructionStream(instructionStream: []const u8) AddRsmToFromRsm {
        const dst, const src, const offset = parseRsmAndRsm(instructionStream);
        return .{ .dst = dst, .src = src, .offset = offset };
    }

    pub fn cost(s: *const AddRsmToFromRsm) Cost {
        return switch (s.dst) {
            .reg => switch (s.src) {
                .reg => .{ .baseCycles = 3 },
                .mem => |src| .{ .baseCycles = 9, .transferCount = 1, .memory = src },
            },
            .mem => |dst| switch (s.src) {
                .reg => .{ .baseCycles = 16, .transferCount = 2, .memory = dst },
                .mem => {
                    std.debug.print("memory - memory ADDs invalid:: {f}\n", .{s});
                    unreachable;
                },
            },
        };
    }

    pub fn format(s: *const AddRsmToFromRsm, w: *std.Io.Writer) !void {
        try w.print("add {f}, {f}", .{ s.dst, s.src });
    }
};
pub const AddImmToRsm = struct {
    dst: RegisterOrMemory,
    src: ByteOrWord,
    offset: u8,

    pub fn fromInstructionStream(instructionStream: []const u8) AddImmToRsm {
        const dst, const src, const offset = parseImmAndRsm(instructionStream);
        return .{ .dst = dst, .src = src, .offset = offset };
    }

    pub fn cost(s: *const AddImmToRsm) Cost {
        return switch (s.dst) {
            .reg => .{ .baseCycles = 4 },
            .mem => |dst| .{ .baseCycles = 17, .transferCount = 2, .memory = dst },
        };
    }

    pub fn format(s: *const AddImmToRsm, w: *std.Io.Writer) !void {
        try switch (s.dst) {
            .reg => w.print("add {f}, {f}", .{ s.dst, std.fmt.alt(s.src, .formatSigned) }),
            .mem => w.print("add {s} {f}, {f}", .{ s.src.widthLabel(), s.dst, std.fmt.alt(s.src, .formatSigned) }),
        };
    }
};
pub const AddImmToAcc = struct {
    dst: Register,
    src: ByteOrWord,
    offset: u8,

    pub fn fromInstructionStream(instructionStream: []const u8) AddImmToAcc {
        const dst, const src, const offset = parseImmAndAcc(instructionStream);
        return .{ .dst = dst, .src = src, .offset = offset };
    }

    pub fn format(s: *const AddImmToAcc, w: *std.Io.Writer) !void {
        try w.print("add {f}, {f}", .{ s.dst, std.fmt.alt(s.src, .formatSigned) });
    }
};

// =================== SUB = Subtract: ===================

pub const SubRsmToFromRsm = struct {
    dst: RegisterOrMemory,
    src: RegisterOrMemory,
    offset: u8,

    pub fn fromInstructionStream(instructionStream: []const u8) SubRsmToFromRsm {
        const dst, const src, const offset = parseRsmAndRsm(instructionStream);
        return .{ .dst = dst, .src = src, .offset = offset };
    }

    pub fn format(s: *const SubRsmToFromRsm, w: *std.Io.Writer) !void {
        try w.print("sub {f}, {f}", .{ s.dst, s.src });
    }
};
pub const SubImmFromRsm = struct {
    dst: RegisterOrMemory,
    src: ByteOrWord,
    offset: u8,

    pub fn fromInstructionStream(instructionStream: []const u8) SubImmFromRsm {
        const dst, const src, const offset = parseImmAndRsm(instructionStream);
        return .{ .dst = dst, .src = src, .offset = offset };
    }

    pub fn format(s: *const SubImmFromRsm, w: *std.Io.Writer) !void {
        try switch (s.dst) {
            .reg => w.print("sub {f}, {f}", .{ s.dst, std.fmt.alt(s.src, .formatSigned) }),
            .mem => w.print("sub {s} {f}, {f}", .{ s.src.widthLabel(), s.dst, std.fmt.alt(s.src, .formatSigned) }),
        };
    }
};
pub const SubImmFromAcc = struct {
    dst: Register,
    src: ByteOrWord,
    offset: u8,

    pub fn fromInstructionStream(instructionStream: []const u8) SubImmFromAcc {
        const dst, const src, const offset = parseImmAndAcc(instructionStream);
        return .{ .dst = dst, .src = src, .offset = offset };
    }

    pub fn format(s: *const SubImmFromAcc, w: *std.Io.Writer) !void {
        try w.print("sub {f}, {f}", .{ s.dst, std.fmt.alt(s.src, .formatSigned) });
    }
};

// =================== CMP = Compare: ===================

pub const CmpRsmAndR = struct {
    dst: RegisterOrMemory,
    src: RegisterOrMemory,
    offset: u8,

    pub fn fromInstructionStream(instructionStream: []const u8) CmpRsmAndR {
        const dst, const src, const offset = parseRsmAndRsm(instructionStream);
        return .{ .dst = dst, .src = src, .offset = offset };
    }

    pub fn format(s: *const CmpRsmAndR, w: *std.Io.Writer) !void {
        try w.print("cmp {f}, {f}", .{ s.dst, s.src });
    }
};
pub const CmpImmWithRsm = struct {
    dst: RegisterOrMemory,
    src: ByteOrWord,
    offset: u8,

    pub fn fromInstructionStream(instructionStream: []const u8) CmpImmWithRsm {
        const dst, const src, const offset = parseImmAndRsm(instructionStream);
        return .{ .dst = dst, .src = src, .offset = offset };
    }

    pub fn format(s: *const CmpImmWithRsm, w: *std.Io.Writer) !void {
        try switch (s.dst) {
            .reg => w.print("cmp {f}, {f}", .{ s.dst, std.fmt.alt(s.src, .formatSigned) }),
            .mem => w.print("cmp {s} {f}, {f}", .{ s.src.widthLabel(), s.dst, std.fmt.alt(s.src, .formatSigned) }),
        };
    }
};
pub const CmpImmWithAcc = struct {
    dst: Register,
    src: ByteOrWord,
    offset: u8,

    pub fn fromInstructionStream(instructionStream: []const u8) CmpImmWithAcc {
        const dst, const src, const offset = parseImmAndAcc(instructionStream);
        return .{ .dst = dst, .src = src, .offset = offset };
    }

    pub fn format(s: *const CmpImmWithAcc, w: *std.Io.Writer) !void {
        try w.print("cmp {f}, {f}", .{ s.dst, std.fmt.alt(s.src, .formatSigned) });
    }
};

// =================== RET = Return from CALL: ===================

pub const RetJe = struct {
    ipinc8: i8,
};
pub const RetJl = struct {
    ipinc8: i8,
};
pub const RetJle = struct {
    ipinc8: i8,
};
pub const RetJb = struct {
    ipinc8: i8,
};
pub const RetJbe = struct {
    ipinc8: i8,
};
pub const RetJp = struct {
    ipinc8: i8,
};
pub const RetJo = struct {
    ipinc8: i8,
};
pub const RetJs = struct {
    ipinc8: i8,
};
pub const RetJne = struct {
    ipinc8: i8,
};
pub const RetJnl = struct {
    ipinc8: i8,
};
pub const RetJnle = struct {
    ipinc8: i8,
};
pub const RetJnb = struct {
    ipinc8: i8,
};
pub const RetJnbe = struct {
    ipinc8: i8,
};
pub const RetJnp = struct {
    ipinc8: i8,
};
pub const RetJno = struct {
    ipinc8: i8,
};
pub const RetJns = struct {
    ipinc8: i8,
};
pub const RetLoop = struct {
    ipinc8: i8,
};
pub const RetLoopz = struct {
    ipinc8: i8,
};
pub const RetLoopnz = struct {
    ipinc8: i8,
};
pub const RetJcxz = struct {
    ipinc8: i8,
};

test "RET tests" {
    const a = std.testing.allocator;

    _ = struct {
        test "RetJe" {
            const inst = Instruction{ .retJe = RetJe{ .ipinc8 = -7 } };
            const serialized = try std.fmt.allocPrint(a, "{f}", .{inst});
            defer a.free(serialized);

            try std.testing.expectEqual(inst.offset(), 2);
            try std.testing.expectEqualStrings(serialized, "je -7");
        }
        test "RetJl" {
            const inst = Instruction{ .retJl = RetJl{ .ipinc8 = -7 } };
            const serialized = try std.fmt.allocPrint(a, "{f}", .{inst});
            defer a.free(serialized);

            try std.testing.expectEqual(inst.offset(), 2);
            try std.testing.expectEqualStrings(serialized, "jl -7");
        }
        test "RetJle" {
            const inst = Instruction{ .retJle = RetJle{ .ipinc8 = -7 } };
            const serialized = try std.fmt.allocPrint(a, "{f}", .{inst});
            defer a.free(serialized);

            try std.testing.expectEqual(inst.offset(), 2);
            try std.testing.expectEqualStrings(serialized, "jle -7");
        }
        test "RetJb" {
            const inst = Instruction{ .retJb = RetJb{ .ipinc8 = -7 } };
            const serialized = try std.fmt.allocPrint(a, "{f}", .{inst});
            defer a.free(serialized);

            try std.testing.expectEqual(inst.offset(), 2);
            try std.testing.expectEqualStrings(serialized, "jb -7");
        }
        test "RetJbe" {
            const inst = Instruction{ .retJbe = RetJbe{ .ipinc8 = -7 } };
            const serialized = try std.fmt.allocPrint(a, "{f}", .{inst});
            defer a.free(serialized);

            try std.testing.expectEqual(inst.offset(), 2);
            try std.testing.expectEqualStrings(serialized, "jbe -7");
        }
        test "RetJp" {
            const inst = Instruction{ .retJp = RetJp{ .ipinc8 = -7 } };
            const serialized = try std.fmt.allocPrint(a, "{f}", .{inst});
            defer a.free(serialized);

            try std.testing.expectEqual(inst.offset(), 2);
            try std.testing.expectEqualStrings(serialized, "jp -7");
        }
        test "RetJo" {
            const inst = Instruction{ .retJo = RetJo{ .ipinc8 = -7 } };
            const serialized = try std.fmt.allocPrint(a, "{f}", .{inst});
            defer a.free(serialized);

            try std.testing.expectEqual(inst.offset(), 2);
            try std.testing.expectEqualStrings(serialized, "jo -7");
        }
        test "RetJs" {
            const inst = Instruction{ .retJs = RetJs{ .ipinc8 = -7 } };
            const serialized = try std.fmt.allocPrint(a, "{f}", .{inst});
            defer a.free(serialized);

            try std.testing.expectEqual(inst.offset(), 2);
            try std.testing.expectEqualStrings(serialized, "js -7");
        }
        test "RetJne" {
            const inst = Instruction{ .retJne = RetJne{ .ipinc8 = -7 } };
            const serialized = try std.fmt.allocPrint(a, "{f}", .{inst});
            defer a.free(serialized);

            try std.testing.expectEqual(inst.offset(), 2);
            try std.testing.expectEqualStrings(serialized, "jne -7");
        }
        test "RetJnl" {
            const inst = Instruction{ .retJnl = RetJnl{ .ipinc8 = -7 } };
            const serialized = try std.fmt.allocPrint(a, "{f}", .{inst});
            defer a.free(serialized);

            try std.testing.expectEqual(inst.offset(), 2);
            try std.testing.expectEqualStrings(serialized, "jnl -7");
        }
        test "RetJnle" {
            const inst = Instruction{ .retJnle = RetJnle{ .ipinc8 = -7 } };
            const serialized = try std.fmt.allocPrint(a, "{f}", .{inst});
            defer a.free(serialized);

            try std.testing.expectEqual(inst.offset(), 2);
            try std.testing.expectEqualStrings(serialized, "jnle -7");
        }
        test "RetJnb" {
            const inst = Instruction{ .retJnb = RetJnb{ .ipinc8 = -7 } };
            const serialized = try std.fmt.allocPrint(a, "{f}", .{inst});
            defer a.free(serialized);

            try std.testing.expectEqual(inst.offset(), 2);
            try std.testing.expectEqualStrings(serialized, "jnb -7");
        }
        test "RetJnbe" {
            const inst = Instruction{ .retJnbe = RetJnbe{ .ipinc8 = -7 } };
            const serialized = try std.fmt.allocPrint(a, "{f}", .{inst});
            defer a.free(serialized);

            try std.testing.expectEqual(inst.offset(), 2);
            try std.testing.expectEqualStrings(serialized, "jnbe -7");
        }
        test "RetJnp" {
            const inst = Instruction{ .retJnp = RetJnp{ .ipinc8 = -7 } };
            const serialized = try std.fmt.allocPrint(a, "{f}", .{inst});
            defer a.free(serialized);

            try std.testing.expectEqual(inst.offset(), 2);
            try std.testing.expectEqualStrings(serialized, "jnp -7");
        }
        test "RetJno" {
            const inst = Instruction{ .retJno = RetJno{ .ipinc8 = -7 } };
            const serialized = try std.fmt.allocPrint(a, "{f}", .{inst});
            defer a.free(serialized);

            try std.testing.expectEqual(inst.offset(), 2);
            try std.testing.expectEqualStrings(serialized, "jno -7");
        }
        test "RetJns" {
            const inst = Instruction{ .retJns = RetJns{ .ipinc8 = -7 } };
            const serialized = try std.fmt.allocPrint(a, "{f}", .{inst});
            defer a.free(serialized);

            try std.testing.expectEqual(inst.offset(), 2);
            try std.testing.expectEqualStrings(serialized, "jns -7");
        }
        test "RetLoop" {
            const inst = Instruction{ .retLoop = RetLoop{ .ipinc8 = -7 } };
            const serialized = try std.fmt.allocPrint(a, "{f}", .{inst});
            defer a.free(serialized);

            try std.testing.expectEqual(inst.offset(), 2);
            try std.testing.expectEqualStrings(serialized, "loop -7");
        }
        test "RetLoopz" {
            const inst = Instruction{ .retLoopz = RetLoopz{ .ipinc8 = -7 } };
            const serialized = try std.fmt.allocPrint(a, "{f}", .{inst});
            defer a.free(serialized);

            try std.testing.expectEqual(inst.offset(), 2);
            try std.testing.expectEqualStrings(serialized, "loopz -7");
        }
        test "RetLoopnz" {
            const inst = Instruction{ .retLoopnz = RetLoopnz{ .ipinc8 = -7 } };
            const serialized = try std.fmt.allocPrint(a, "{f}", .{inst});
            defer a.free(serialized);

            try std.testing.expectEqual(inst.offset(), 2);
            try std.testing.expectEqualStrings(serialized, "loopnz -7");
        }
        test "RetJcxz" {
            const inst = Instruction{ .retJcxz = RetJcxz{ .ipinc8 = -7 } };
            const serialized = try std.fmt.allocPrint(a, "{f}", .{inst});
            defer a.free(serialized);

            try std.testing.expectEqual(inst.offset(), 2);
            try std.testing.expectEqualStrings(serialized, "jcxz -7");
        }
    };
}
