const std = @import("std");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next();
    const input_file_path = args.next() orelse {
        std.debug.print("Call with path to binary from CWD\n", .{});
        return error.MissingArgument;
    };

    const cwd = std.fs.cwd();

    const encoded = cwd.readFileAlloc(allocator, input_file_path, 512) catch |err| {
        std.debug.print("Error: {}\n", .{err});
        return;
    };
    defer allocator.free(encoded);

    std.debug.print("{any}\n\n", .{encoded});

    const decoded = decode(allocator, encoded) catch |err| {
        std.debug.print("Error: {}\n", .{err});
        return;
    };
    defer allocator.free(decoded);

    std.debug.print("{s}", .{decoded});
}

// there's probably way more kinds of errors I could/should check but whatever
const InstructionDecodeError = error{NotSupported};

const BYTE_REGISTERS = [8]*const [2:0]u8{ "al", "cl", "dl", "bl", "ah", "ch", "dh", "bh" };
const WORD_REGISTERS = [8]*const [2:0]u8{ "ax", "cx", "dx", "bx", "sp", "bp", "si", "di" };

const EAC = [_][]const u8{ "bx + si", "bx + di", "bp + si", "bp + di", "si", "di", "bp", "bx" };

fn decode(a: std.mem.Allocator, encoded: []const u8) ![]u8 {
    var decoded: std.ArrayList(u8) = .empty;
    errdefer decoded.deinit(a);
    try decoded.appendSlice(a, "bits 16\n\n");

    // add 000
    // rsmtofromrsm - 000000dw
    // immToRsm     - 100000sw
    // immToAcc     - 0000010w

    // sub 101
    // rsmtofromrsm - 001010dw
    // immFromRsm   - 100000sw
    // immFromAcc   - 0010110w

    // cmp 111
    // rsmAndR      - 001110dw
    // immWithRsm   - 100000sw
    // immWithAcc   - 0011110w

    // 0b11000100

    // je     0b01110100
    // jl     0b01111100
    // jle    0b01111110
    // jb     0b01110010
    // jbe    0b01110110
    // jp     0b01111010
    // jo     0b01110000
    // js     0b01111000
    // jne    0b01110101
    // jnl    0b01111101
    // jnle   0b01111111
    // jnb    0b01110011
    // jnbe   0b01110111
    // jnp    0b01111011
    // jno    0b01110001
    // jns    0b01111001
    // loop   0b11100010
    // loopz  0b11100001
    // loopnz 0b11100000
    // jcxz   0b11100011

    var i: u8 = 0;
    while (i < encoded.len) {
        const byte = encoded[i];
        const opcode = byte & 0b11000100;
        const inst_incr: struct { []const u8, u8 } = if (opcode == 0b00000000) blk: {
            break :blk try rsmAndRsm(a, encoded[i..]);
        } else if (opcode == 0b10000000) blk: {
            break :blk try immAndRsm(a, encoded[i..]);
        } else if (opcode == 0b00000100) blk: {
            break :blk try immAndAcc(a, encoded[i..]);
        } else if (byte == 0b01110100) blk: {
            break :blk .{ try std.fmt.allocPrint(a, "je {d}", .{@as(i8, @bitCast(encoded[i + 1]))}), 2 };
        } else if (byte == 0b01111100) blk: {
            break :blk .{ try std.fmt.allocPrint(a, "jl {d}", .{@as(i8, @bitCast(encoded[i + 1]))}), 2 };
        } else if (byte == 0b01111110) blk: {
            break :blk .{ try std.fmt.allocPrint(a, "jle {d}", .{@as(i8, @bitCast(encoded[i + 1]))}), 2 };
        } else if (byte == 0b01110010) blk: {
            break :blk .{ try std.fmt.allocPrint(a, "jb {d}", .{@as(i8, @bitCast(encoded[i + 1]))}), 2 };
        } else if (byte == 0b01110110) blk: {
            break :blk .{ try std.fmt.allocPrint(a, "jbe {d}", .{@as(i8, @bitCast(encoded[i + 1]))}), 2 };
        } else if (byte == 0b01111010) blk: {
            break :blk .{ try std.fmt.allocPrint(a, "jp {d}", .{@as(i8, @bitCast(encoded[i + 1]))}), 2 };
        } else if (byte == 0b01110000) blk: {
            break :blk .{ try std.fmt.allocPrint(a, "jo {d}", .{@as(i8, @bitCast(encoded[i + 1]))}), 2 };
        } else if (byte == 0b01111000) blk: {
            break :blk .{ try std.fmt.allocPrint(a, "js {d}", .{@as(i8, @bitCast(encoded[i + 1]))}), 2 };
        } else if (byte == 0b01110101) blk: {
            break :blk .{ try std.fmt.allocPrint(a, "jne {d}", .{@as(i8, @bitCast(encoded[i + 1]))}), 2 };
        } else if (byte == 0b01111101) blk: {
            break :blk .{ try std.fmt.allocPrint(a, "jnl {d}", .{@as(i8, @bitCast(encoded[i + 1]))}), 2 };
        } else if (byte == 0b01111111) blk: {
            break :blk .{ try std.fmt.allocPrint(a, "jnle {d}", .{@as(i8, @bitCast(encoded[i + 1]))}), 2 };
        } else if (byte == 0b01110011) blk: {
            break :blk .{ try std.fmt.allocPrint(a, "jnb {d}", .{@as(i8, @bitCast(encoded[i + 1]))}), 2 };
        } else if (byte == 0b01110111) blk: {
            break :blk .{ try std.fmt.allocPrint(a, "jnbe {d}", .{@as(i8, @bitCast(encoded[i + 1]))}), 2 };
        } else if (byte == 0b01111011) blk: {
            break :blk .{ try std.fmt.allocPrint(a, "jnp {d}", .{@as(i8, @bitCast(encoded[i + 1]))}), 2 };
        } else if (byte == 0b01110001) blk: {
            break :blk .{ try std.fmt.allocPrint(a, "jno {d}", .{@as(i8, @bitCast(encoded[i + 1]))}), 2 };
        } else if (byte == 0b01111001) blk: {
            break :blk .{ try std.fmt.allocPrint(a, "jns {d}", .{@as(i8, @bitCast(encoded[i + 1]))}), 2 };
        } else if (byte == 0b11100010) blk: {
            break :blk .{ try std.fmt.allocPrint(a, "loop {d}", .{@as(i8, @bitCast(encoded[i + 1]))}), 2 };
        } else if (byte == 0b11100001) blk: {
            break :blk .{ try std.fmt.allocPrint(a, "loopz {d}", .{@as(i8, @bitCast(encoded[i + 1]))}), 2 };
        } else if (byte == 0b11100000) blk: {
            break :blk .{ try std.fmt.allocPrint(a, "loopnz {d}", .{@as(i8, @bitCast(encoded[i + 1]))}), 2 };
        } else if (byte == 0b11100011) blk: {
            break :blk .{ try std.fmt.allocPrint(a, "jcxz {d}", .{@as(i8, @bitCast(encoded[i + 1]))}), 2 };
        } else {
            return InstructionDecodeError.NotSupported;
        };

        try decoded.appendSlice(a, inst_incr[0]);
        try decoded.appendSlice(a, "\n");
        a.free(inst_incr[0]);

        i += inst_incr[1];
    }

    return decoded.toOwnedSlice(a);
}

fn rsmAndRsm(a: std.mem.Allocator, encoded: []const u8) !struct { []const u8, u8 } {
    const b1 = encoded[0];
    const d = b1 & 0b00000010;
    const w = b1 & 0b00000001;

    const b2 = encoded[1];
    const mod = b2 & 0b11000000;
    const reg = (b2 & 0b00111000) >> 3;
    const rsm = b2 & 0b00000111;

    const registers = if (w == 0)
        BYTE_REGISTERS
    else
        WORD_REGISTERS;

    const op = getOp(encoded[0], encoded[1]);

    const disp: u16, const dispOffset: u8 = switch (mod) {
        // special case (direct address with 16 bit displacement)
        0b00000000 => if (rsm == 0b00000110) .{ (@as(u16, encoded[2 + 1]) << 8) | encoded[2], 2 } else .{ 0, 0 },
        0b01000000 => .{ encoded[2], 1 },
        0b10000000 => .{ (@as(u16, encoded[2 + 1]) << 8) | encoded[2], 2 },
        0b11000000 => .{ 0, 0 },
        else => unreachable,
    };

    const offset = 2 + dispOffset;

    return switch (mod) {
        0b00000000 => {
            const dst, const src = if (d == 0)
                .{ EAC[rsm], registers[reg] }
            else
                .{ registers[reg], EAC[rsm] };

            // special case (direct address with 16 bit displacement)
            if (rsm == 0b00000110) {
                return .{ try std.fmt.allocPrint(a, "{s} {s}, {d}", .{ op, dst, disp }), offset };
            }

            if (d == 0) {
                return .{ try std.fmt.allocPrint(a, "{s} [{s}], {s}", .{ op, dst, src }), offset };
            } else {
                return .{ try std.fmt.allocPrint(a, "{s} {s}, [{s}]", .{ op, dst, src }), offset };
            }
        },
        0b01000000 => if (d == 0)
            .{ try std.fmt.allocPrint(a, "{s} [{s} + {d}], {s}", .{ op, EAC[rsm], disp, registers[reg] }), offset }
        else
            .{ try std.fmt.allocPrint(a, "{s} {s}, [{s} + {d}]", .{ op, registers[reg], EAC[rsm], disp }), offset },
        0b10000000 => if (d == 0)
            .{ try std.fmt.allocPrint(a, "{s} [{s} + {d}], {s}", .{ op, EAC[rsm], disp, registers[reg] }), offset }
        else
            return .{ try std.fmt.allocPrint(a, "{s} {s}, [{s} + {d}]", .{ op, registers[reg], EAC[rsm], disp }), offset },
        0b11000000 => {
            const dst, const src = if (d == 0)
                .{ rsm, reg }
            else
                .{ reg, rsm };

            return .{ try std.fmt.allocPrint(a, "{s} {s}, {s}", .{ op, registers[dst], registers[src] }), offset };
        },
        else => unreachable,
    };
}

fn immAndRsm(a: std.mem.Allocator, encoded: []const u8) !struct { []const u8, u8 } {
    const b1 = encoded[0];
    const s = b1 & 0b00000010;
    const w = b1 & 0b00000001;
    const sw = s & w;

    const b2 = encoded[1];
    const mod = b2 & 0b11000000;
    const rsm = b2 & 0b00000111;

    const registers = if (w == 0)
        BYTE_REGISTERS
    else
        WORD_REGISTERS;

    const op = getOp(encoded[0], encoded[1]);

    const disp: u16, const dispOffset: u8 = switch (mod) {
        // special case (direct address with 16 bit displacement)
        0b00000000 => if (rsm == 0b00000110) .{ (@as(u16, encoded[2 + 1]) << 8) | encoded[2], 2 } else .{ 0, 0 },
        0b01000000 => .{ encoded[2], 1 },
        0b10000000 => .{ (@as(u16, encoded[2 + 1]) << 8) | encoded[2], 2 },
        0b11000000 => .{ 0, 0 },
        else => unreachable,
    };

    const imm: i16, const immOffset: u8 = switch (sw) {
        0b00000000 => .{ encoded[2 + dispOffset], 1 },
        0b00000001 => .{ (@as(i16, encoded[2 + dispOffset + 1]) << 8) | @as(i16, encoded[2 + dispOffset]), 2 },
        0b00000010 => .{ encoded[2 + dispOffset], 1 },
        0b00000011 => .{ @as(i16, encoded[2 + dispOffset]), 1 },
        else => unreachable,
    };

    const wbSpecifier = if (w == 1) "word" else "byte";

    const offset = 2 + dispOffset + immOffset;

    return switch (mod) {
        // special case (direct address with 16 bit displacement)
        0b00000000 => if (rsm == 0b00000110)
            .{ try std.fmt.allocPrint(a, "{s} {s} [{d}], {d}", .{ op, wbSpecifier, disp, imm }), offset }
        else
            .{ try std.fmt.allocPrint(a, "{s} {s} [{s}], {d}", .{ op, wbSpecifier, EAC[rsm], imm }), offset },
        0b01000000 => .{ try std.fmt.allocPrint(a, "{s} {s} [{s} + {d}], {d}", .{ op, wbSpecifier, EAC[rsm], disp, imm }), offset },
        0b10000000 => .{ try std.fmt.allocPrint(a, "{s} {s} [{s} + {d}], {d}", .{ op, wbSpecifier, EAC[rsm], disp, imm }), offset },
        0b11000000 => .{ try std.fmt.allocPrint(a, "{s} {s}, {d}", .{ op, registers[rsm], imm }), offset },
        else => unreachable,
    };
}

fn immAndAcc(a: std.mem.Allocator, encoded: []const u8) !struct { []const u8, u8 } {
    const b1 = encoded[0];
    const w = b1 & 0b00000001;

    const op = getOp(encoded[0], encoded[1]);
    const reg, const imm, const offset: u8 = if (w == 0)
        .{ "al", encoded[1], 2 }
    else
        .{ "ax", (@as(u16, encoded[2]) << 8) | encoded[1], 3 };

    return .{ try std.fmt.allocPrint(a, "{s} {s}, {d}", .{ op, reg, imm }), offset };
}

fn getOp(instByte: u8, nextByte: u8) *const [3:0]u8 {
    const opcode = instByte & 0b11000100;
    const opByte = if (opcode == 0b10000000) nextByte else instByte;
    const opFlag = opByte & 0b00111000;
    return switch (opFlag) {
        0b00000000 => "add",
        0b00101000 => "sub",
        0b00111000 => "cmp",
        else => unreachable,
    };
}

test "listing_0041_add_sub_cmp_jnz" {
    const allocator = std.testing.allocator;
    const actual = try decode(allocator, &[_]u8{ 3, 24, 3, 94, 0, 131, 198, 2, 131, 197, 2, 131, 193, 8, 3, 94, 0, 3, 79, 2, 2, 122, 4, 3, 123, 6, 1, 24, 1, 94, 0, 1, 94, 0, 1, 79, 2, 0, 122, 4, 1, 123, 6, 128, 7, 34, 131, 130, 232, 3, 29, 3, 70, 0, 2, 0, 1, 216, 0, 224, 5, 232, 3, 4, 226, 4, 9, 43, 24, 43, 94, 0, 131, 238, 2, 131, 237, 2, 131, 233, 8, 43, 94, 0, 43, 79, 2, 42, 122, 4, 43, 123, 6, 41, 24, 41, 94, 0, 41, 94, 0, 41, 79, 2, 40, 122, 4, 41, 123, 6, 128, 47, 34, 131, 41, 29, 43, 70, 0, 42, 0, 41, 216, 40, 224, 45, 232, 3, 44, 226, 44, 9, 59, 24, 59, 94, 0, 131, 254, 2, 131, 253, 2, 131, 249, 8, 59, 94, 0, 59, 79, 2, 58, 122, 4, 59, 123, 6, 57, 24, 57, 94, 0, 57, 94, 0, 57, 79, 2, 56, 122, 4, 57, 123, 6, 128, 63, 34, 131, 62, 226, 18, 29, 59, 70, 0, 58, 0, 57, 216, 56, 224, 61, 232, 3, 60, 226, 60, 9, 117, 2, 117, 252, 117, 250, 117, 252, 116, 254, 124, 252, 126, 250, 114, 248, 118, 246, 122, 244, 112, 242, 120, 240, 117, 238, 125, 236, 127, 234, 115, 232, 119, 230, 123, 228, 113, 226, 121, 224, 226, 222, 225, 220, 224, 218, 227, 216 });
    defer allocator.free(actual);

    const expected =
        \\bits 16
        \\
        \\add bx, [bx + si]
        \\add bx, [bp + 0]
        \\add si, 2
        \\add bp, 2
        \\add cx, 8
        \\add bx, [bp + 0]
        \\add cx, [bx + 2]
        \\add bh, [bp + si + 4]
        \\add di, [bp + di + 6]
        \\add [bx + si], bx
        \\add [bp + 0], bx
        \\add [bp + 0], bx
        \\add [bx + 2], cx
        \\add [bp + si + 4], bh
        \\add [bp + di + 6], di
        \\add byte [bx], 34
        \\add word [bp + si + 1000], 29
        \\add ax, [bp + 0]
        \\add al, [bx + si]
        \\add ax, bx
        \\add al, ah
        \\add ax, 1000
        // originally -30; u8 wraparound
        \\add al, 226
        \\add al, 9
        //
        \\sub bx, [bx + si]
        \\sub bx, [bp + 0]
        \\sub si, 2
        \\sub bp, 2
        \\sub cx, 8
        \\sub bx, [bp + 0]
        \\sub cx, [bx + 2]
        \\sub bh, [bp + si + 4]
        \\sub di, [bp + di + 6]
        \\sub [bx + si], bx
        \\sub [bp + 0], bx
        \\sub [bp + 0], bx
        \\sub [bx + 2], cx
        \\sub [bp + si + 4], bh
        \\sub [bp + di + 6], di
        \\sub byte [bx], 34
        \\sub word [bx + di], 29
        \\sub ax, [bp + 0]
        \\sub al, [bx + si]
        \\sub ax, bx
        \\sub al, ah
        \\sub ax, 1000
        // originally -30; u8 wraparound
        \\sub al, 226
        \\sub al, 9
        //
        \\cmp bx, [bx + si]
        \\cmp bx, [bp + 0]
        \\cmp si, 2
        \\cmp bp, 2
        \\cmp cx, 8
        \\cmp bx, [bp + 0]
        \\cmp cx, [bx + 2]
        \\cmp bh, [bp + si + 4]
        \\cmp di, [bp + di + 6]
        \\cmp [bx + si], bx
        \\cmp [bp + 0], bx
        \\cmp [bp + 0], bx
        \\cmp [bx + 2], cx
        \\cmp [bp + si + 4], bh
        \\cmp [bp + di + 6], di
        \\cmp byte [bx], 34
        \\cmp word [4834], 29
        \\cmp ax, [bp + 0]
        \\cmp al, [bx + si]
        \\cmp ax, bx
        \\cmp al, ah
        \\cmp ax, 1000
        // originally -30; u8 wraparound
        \\cmp al, 226
        \\cmp al, 9
        //
        // \\test_label0:
        // originally jne test_label1
        \\jne 2
        // originally jne test_label0
        \\jne -4
        // \\test_label1:
        // originally jne test_label0
        \\jne -6
        // originally jne test_label1
        \\jne -4
        //
        // \\label:
        // originally all were to label
        \\je -2
        \\jl -4
        \\jle -6
        \\jb -8
        \\jbe -10
        \\jp -12
        \\jo -14
        \\js -16
        \\jne -18
        \\jnl -20
        \\jnle -22
        \\jnb -24
        \\jnbe -26
        \\jnp -28
        \\jno -30
        \\jns -32
        \\loop -34
        \\loopz -36
        \\loopnz -38
        \\jcxz -40
        \\
    ;

    try std.testing.expectEqualStrings(expected, actual);
}
