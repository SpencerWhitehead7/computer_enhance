const std = @import("std");

// 8086 user manual, starting at 4-18

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

    const encoded = cwd.readFileAlloc(allocator, input_file_path, 64) catch |err| {
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
const InstructionDecodeError = error{
    NotMov,
};

const BYTE_REGISTERS = [8]*const [2:0]u8{ "al", "cl", "dl", "bl", "ah", "ch", "dh", "bh" };
const WORD_REGISTERS = [8]*const [2:0]u8{ "ax", "cx", "dx", "bx", "sp", "bp", "si", "di" };

const EAC = [_][]const u8{ "bx + si", "bx + di", "bp + si", "bp + di", "si", "di", "bp", "bx" };

fn decode(allocator: std.mem.Allocator, encoded: []const u8) ![]u8 {
    var decoded: std.ArrayList(u8) = .empty;
    errdefer decoded.deinit(allocator);
    try decoded.appendSlice(allocator, "bits 16\n\n");

    var i: u8 = 0;
    while (i < encoded.len) {
        const byte = encoded[i];
        const inst_incr = if (byte & 0b11111100 == 0b10001000) blk: {
            break :blk try rsmToFromR(allocator, encoded[i..]);
        } else if (byte & 0b11111110 == 0b11000110) blk: {
            break :blk try immToRsm();
        } else if (byte & 0b11110000 == 0b10110000) blk: {
            break :blk try immToR(allocator, encoded[i..]);
        } else if (byte & 0b11111110 == 0b10100000) blk: {
            break :blk try memToAcc();
        } else if (byte & 0b11111110 == 0b10100010) blk: {
            break :blk try accToMem();
        } else if (byte & 0b11111111 == 0b10001110) blk: {
            break :blk try rsmToSegR();
        } else if (byte & 0b11111111 == 0b10001100) blk: {
            break :blk try segRToRsm();
        } else {
            return InstructionDecodeError.NotMov;
        };

        try decoded.appendSlice(allocator, inst_incr[0]);
        try decoded.appendSlice(allocator, "\n");
        allocator.free(inst_incr[0]);

        i += inst_incr[1];
    }

    return decoded.toOwnedSlice(allocator);
}

fn rsmToFromR(allocator: std.mem.Allocator, encoded: []const u8) !struct { []const u8, u8 } {
    const b1 = encoded[0];
    const b2 = encoded[1];
    const d = b1 & 0b00000010;
    const w = b1 & 0b00000001;

    const mod = b2 & 0b11000000;
    const reg = (b2 & 0b00111000) >> 3;
    const rsm = b2 & 0b00000111;

    const registers = if (w == 0)
        BYTE_REGISTERS
    else
        WORD_REGISTERS;

    switch (mod) {
        0b00000000 => {
            const dst, const src = if (d == 0)
                .{ EAC[rsm], registers[reg] }
            else
                .{ registers[reg], EAC[rsm] };

            // special case (direct address with 16 bit displacement)
            if (rsm == 0b00000110) {
                const dispLo = encoded[2];
                const dispHi = encoded[3];
                const disp = (@as(u16, dispHi) << 8) | dispLo;

                return .{ try std.fmt.allocPrint(allocator, "mov {s}, {d}", .{ dst, disp }), 4 };
            }

            if (d == 0) {
                return .{ try std.fmt.allocPrint(allocator, "mov [{s}], {s}", .{ dst, src }), 2 };
            } else {
                return .{ try std.fmt.allocPrint(allocator, "mov {s}, [{s}]", .{ dst, src }), 2 };
            }
        },
        0b01000000 => {
            const dispLo = encoded[2];
            const disp = dispLo;

            if (d == 0) {
                if (disp != 0) {
                    return .{ try std.fmt.allocPrint(allocator, "mov [{s} + {d}], {s}", .{ EAC[rsm], disp, registers[reg] }), 3 };
                } else {
                    return .{ try std.fmt.allocPrint(allocator, "mov [{s}], {s}", .{ EAC[rsm], registers[reg] }), 3 };
                }
            } else {
                if (disp != 0) {
                    return .{ try std.fmt.allocPrint(allocator, "mov {s}, [{s} + {d}]", .{ registers[reg], EAC[rsm], disp }), 3 };
                } else {
                    return .{ try std.fmt.allocPrint(allocator, "mov {s}, [{s}]", .{ registers[reg], EAC[rsm] }), 3 };
                }
            }
        },
        0b10000000 => {
            const dispLo = encoded[2];
            const dispHi = encoded[3];
            const disp = (@as(u16, dispHi) << 8) | dispLo;

            if (d == 0) {
                if (disp != 0) {
                    return .{ try std.fmt.allocPrint(allocator, "mov [{s} + {d}], {s}", .{ EAC[rsm], disp, registers[reg] }), 4 };
                } else {
                    return .{ try std.fmt.allocPrint(allocator, "mov [{s}], {s}", .{ EAC[rsm], registers[reg] }), 4 };
                }
            } else {
                if (disp != 0) {
                    return .{ try std.fmt.allocPrint(allocator, "mov {s}, [{s} + {d}]", .{ registers[reg], EAC[rsm], disp }), 4 };
                } else {
                    return .{ try std.fmt.allocPrint(allocator, "mov {s}, [{s}]", .{ registers[reg], EAC[rsm] }), 4 };
                }
            }
        },
        0b11000000 => {
            const dst, const src = if (d == 0)
                .{ rsm, reg }
            else
                .{ reg, rsm };

            return .{ try std.fmt.allocPrint(allocator, "mov {s}, {s}", .{ registers[dst], registers[src] }), 2 };
        },
        else => unreachable,
    }
}

fn immToRsm() !struct { []const u8, u8 } {
    return .{ "", 2 };
}

fn immToR(allocator: std.mem.Allocator, encoded: []const u8) !struct { []const u8, u8 } {
    const b1 = encoded[0];
    const w = b1 & 0b00001000;
    const reg = b1 & 0b00000111;

    if (w == 0) {
        const imm = encoded[1];

        return .{ try std.fmt.allocPrint(allocator, "mov {s}, {d}", .{ BYTE_REGISTERS[reg], imm }), 2 };
    } else {
        const imm = (@as(u16, encoded[2]) << 8) | encoded[1];

        return .{ try std.fmt.allocPrint(allocator, "mov {s}, {d}", .{ WORD_REGISTERS[reg], imm }), 3 };
    }
}

fn memToAcc() !struct { []const u8, u8 } {
    return .{ "", 2 };
}

fn accToMem() !struct { []const u8, u8 } {
    return .{ "", 2 };
}

fn rsmToSegR() !struct { []const u8, u8 } {
    return .{ "", 2 };
}

fn segRToRsm() !struct { []const u8, u8 } {
    return .{ "", 2 };
}

test "listing_0037_single_register_mov" {
    const allocator = std.testing.allocator;
    const actual = try decode(allocator, &[_]u8{ 137, 217 });
    defer allocator.free(actual);

    const expected =
        \\bits 16
        \\
        \\mov cx, bx
        \\
    ;

    try std.testing.expectEqualStrings(expected, actual);
}

test "listing_0038_many_register_mov" {
    const allocator = std.testing.allocator;
    const actual = try decode(allocator, &[_]u8{ 137, 217, 136, 229, 137, 218, 137, 222, 137, 251, 136, 200, 136, 237, 137, 195, 137, 243, 137, 252, 137, 197 });
    defer allocator.free(actual);

    const expected =
        \\bits 16
        \\
        \\mov cx, bx
        \\mov ch, ah
        \\mov dx, bx
        \\mov si, bx
        \\mov bx, di
        \\mov al, cl
        \\mov ch, ch
        \\mov bx, ax
        \\mov bx, si
        \\mov sp, di
        \\mov bp, ax
        \\
    ;

    try std.testing.expectEqualStrings(expected, actual);
}

test "listing_0039_more_movs" {
    const allocator = std.testing.allocator;
    const actual = try decode(allocator, &[_]u8{ 137, 222, 136, 198, 177, 12, 181, 244, 185, 12, 0, 185, 244, 255, 186, 108, 15, 186, 148, 240, 138, 0, 139, 27, 139, 86, 0, 138, 96, 4, 138, 128, 135, 19, 137, 9, 136, 10, 136, 110, 0 });
    defer allocator.free(actual);

    const expected =
        \\bits 16
        \\
        //
        // Register-to-register
        \\mov si, bx
        \\mov dh, al
        //
        // 8-bit immediate-to-register
        \\mov cl, 12
        \\mov ch, 244
        // originally -12; u8 wraparound
        //
        // 16-bit immediate-to-register
        \\mov cx, 12
        \\mov cx, 65524
        // originally -12; u16 wraparound
        \\mov dx, 3948
        \\mov dx, 61588
        // originally -3948; u16 wraparound
        //
        // Source address calculation
        \\mov al, [bx + si]
        \\mov bx, [bp + di]
        \\mov dx, [bp]
        //
        // Source address calculation plus 8-bit displacement
        \\mov ah, [bx + si + 4]
        //
        // Source address calculation plus 16-bit displacement
        \\mov al, [bx + si + 4999]
        //
        // Dest address calculation
        \\mov [bx + di], cx
        \\mov [bp + si], cl
        \\mov [bp], ch
        \\
    ;

    try std.testing.expectEqualStrings(expected, actual);
}

// TODO, someday:: implement the other 5 opcodes so this works
test "listing_0040_challenge_movs" {
    const allocator = std.testing.allocator;
    const actual = try decode(allocator, &[_]u8{ 139, 65, 219, 137, 140, 212, 254, 139, 87, 224, 198, 3, 7, 199, 133, 133, 3, 91, 1, 139, 46, 5, 0, 139, 30, 130, 13, 161, 251, 9, 161, 16, 0, 163, 250, 9, 163, 15, 0 });
    defer allocator.free(actual);

    const expected =
        \\bits 16
        \\
        \\; Signed displacements
        \\mov ax, [bx + di - 37]
        \\mov [si - 300], cx
        \\mov dx, [bx - 32]
        \\
        \\; Explicit sizes
        \\mov [bp + di], byte 7
        \\mov [di + 901], word 347
        \\
        \\; Direct address
        \\mov bp, [5]
        \\mov bx, [3458]
        \\
        \\; Memory-to-accumulator test
        \\mov ax, [2555]
        \\mov ax, [16]
        \\
        \\; Accumulator-to-memory test
        \\mov [2554], ax
        \\mov [15], ax
        \\
    ;

    try std.testing.expectEqualStrings(expected, actual);
}
