const std = @import("std");

const instr = @import("./8086_instruction.zig");

fn decode(a: std.mem.Allocator, instructionStream: []const u8) ![]const u8 {
    var serialized = std.Io.Writer.Allocating.init(a);
    errdefer serialized.deinit();

    try serialized.writer.writeAll("bits 16\n\n");

    var i: u64 = 0;
    while (i < instructionStream.len) {
        const instruction = instr.Instruction.fromInstructionStream(instructionStream[i..]);

        try serialized.writer.print("{f}\n", .{instruction});

        i += instruction.offset();
    }

    return serialized.toOwnedSlice();
}

test "listing_0037_single_register_mov" {
    const a = std.testing.allocator;
    const instructionStream = [_]u8{ 137, 217 };
    const actual = try decode(a, &instructionStream);
    defer a.free(actual);

    const expected =
        \\bits 16
        \\
        \\mov cx, bx
        \\
    ;

    try std.testing.expectEqualStrings(expected, actual);
}

test "listing_0038_many_register_mov" {
    const a = std.testing.allocator;
    const instructionStream = [_]u8{ 137, 217, 136, 229, 137, 218, 137, 222, 137, 251, 136, 200, 136, 237, 137, 195, 137, 243, 137, 252, 137, 197 };
    const actual = try decode(a, &instructionStream);
    defer a.free(actual);

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
    const a = std.testing.allocator;
    const instructionStream = [_]u8{ 137, 222, 136, 198, 177, 12, 181, 244, 185, 12, 0, 185, 244, 255, 186, 108, 15, 186, 148, 240, 138, 0, 139, 27, 139, 86, 0, 138, 96, 4, 138, 128, 135, 19, 137, 9, 136, 10, 136, 110, 0 };
    const actual = try decode(a, &instructionStream);
    defer a.free(actual);

    const expected =
        \\bits 16
        \\
        // Register-to-register
        \\mov si, bx
        \\mov dh, al
        //
        // 8-bit immediate-to-register
        \\mov cl, 12
        \\mov ch, -12
        //
        // 16-bit immediate-to-register
        \\mov cx, 12
        \\mov cx, -12
        \\mov dx, 3948
        \\mov dx, -3948
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

// TODO, someday
// test "listing_0040_challenge_movs" {
//     const a = std.testing.allocator;
//     const instructionStream = [_]u8{ 139, 65, 219, 137, 140, 212, 254, 139, 87, 224, 198, 3, 7, 199, 133, 133, 3, 91, 1, 139, 46, 5, 0, 139, 30, 130, 13, 161, 251, 9, 161, 16, 0, 163, 250, 9, 163, 15, 0 };
//     const actual = try decode(a, &instructionStream);
//     defer a.free(actual);

//     const expected =
//         \\bits 16
//         \\
//         \\; Signed displacements
//         \\mov ax, [bx + di - 37]
//         \\mov [si - 300], cx
//         \\mov dx, [bx - 32]
//         \\
//         \\; Explicit sizes
//         \\mov [bp + di], byte 7
//         \\mov [di + 901], word 347
//         \\
//         \\; Direct address
//         \\mov bp, [5]
//         \\mov bx, [3458]
//         \\
//         \\; Memory-to-accumulator test
//         \\mov ax, [2555]
//         \\mov ax, [16]
//         \\
//         \\; Accumulator-to-memory test
//         \\mov [2554], ax
//         \\mov [15], ax
//         \\
//     ;

//     try std.testing.expectEqualStrings(expected, actual);
// }
