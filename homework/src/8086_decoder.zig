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

test "listing_0040_challenge_movs" {
    const a = std.testing.allocator;
    const instructionStream = [_]u8{ 139, 65, 219, 137, 140, 212, 254, 139, 87, 224, 198, 3, 7, 199, 133, 133, 3, 91, 1, 139, 46, 5, 0, 139, 30, 130, 13, 161, 251, 9, 161, 16, 0, 163, 250, 9, 163, 15, 0 };
    const actual = try decode(a, &instructionStream);
    defer a.free(actual);

    const expected =
        \\bits 16
        \\
        // Signed displacements
        \\mov ax, [bx + di - 37]
        \\mov [si - 300], cx
        \\mov dx, [bx - 32]
        //
        // Explicit sizes
        \\mov [bp + di], byte 7
        \\mov [di + 901], word 347
        //
        // Direct address
        \\mov bp, [5]
        \\mov bx, [3458]
        //
        // Memory-to-accumulator test
        \\mov ax, [2555]
        \\mov ax, [16]
        //
        // Accumulator-to-memory test
        \\mov [2554], ax
        \\mov [15], ax
        \\
    ;

    try std.testing.expectEqualStrings(expected, actual);
}

test "listing_0041_add_sub_cmp_jnz" {
    const a = std.testing.allocator;
    const instructionStream = [_]u8{ 3, 24, 3, 94, 0, 131, 198, 2, 131, 197, 2, 131, 193, 8, 3, 94, 0, 3, 79, 2, 2, 122, 4, 3, 123, 6, 1, 24, 1, 94, 0, 1, 94, 0, 1, 79, 2, 0, 122, 4, 1, 123, 6, 128, 7, 34, 131, 130, 232, 3, 29, 3, 70, 0, 2, 0, 1, 216, 0, 224, 5, 232, 3, 4, 226, 4, 9, 43, 24, 43, 94, 0, 131, 238, 2, 131, 237, 2, 131, 233, 8, 43, 94, 0, 43, 79, 2, 42, 122, 4, 43, 123, 6, 41, 24, 41, 94, 0, 41, 94, 0, 41, 79, 2, 40, 122, 4, 41, 123, 6, 128, 47, 34, 131, 41, 29, 43, 70, 0, 42, 0, 41, 216, 40, 224, 45, 232, 3, 44, 226, 44, 9, 59, 24, 59, 94, 0, 131, 254, 2, 131, 253, 2, 131, 249, 8, 59, 94, 0, 59, 79, 2, 58, 122, 4, 59, 123, 6, 57, 24, 57, 94, 0, 57, 94, 0, 57, 79, 2, 56, 122, 4, 57, 123, 6, 128, 63, 34, 131, 62, 226, 18, 29, 59, 70, 0, 58, 0, 57, 216, 56, 224, 61, 232, 3, 60, 226, 60, 9, 117, 2, 117, 252, 117, 250, 117, 252, 116, 254, 124, 252, 126, 250, 114, 248, 118, 246, 122, 244, 112, 242, 120, 240, 117, 238, 125, 236, 127, 234, 115, 232, 119, 230, 123, 228, 113, 226, 121, 224, 226, 222, 225, 220, 224, 218, 227, 216 };
    const actual = try decode(a, &instructionStream);
    defer a.free(actual);

    const expected =
        \\bits 16
        \\
        \\add bx, [bx + si]
        \\add bx, [bp]
        \\add si, 2
        \\add bp, 2
        \\add cx, 8
        \\add bx, [bp]
        \\add cx, [bx + 2]
        \\add bh, [bp + si + 4]
        \\add di, [bp + di + 6]
        \\add [bx + si], bx
        \\add [bp], bx
        \\add [bp], bx
        \\add [bx + 2], cx
        \\add [bp + si + 4], bh
        \\add [bp + di + 6], di
        \\add byte [bx], 34
        \\add word [bp + si + 1000], 29
        \\add ax, [bp]
        \\add al, [bx + si]
        \\add ax, bx
        \\add al, ah
        \\add ax, 1000
        \\add al, -30
        \\add al, 9
        //
        \\sub bx, [bx + si]
        \\sub bx, [bp]
        \\sub si, 2
        \\sub bp, 2
        \\sub cx, 8
        \\sub bx, [bp]
        \\sub cx, [bx + 2]
        \\sub bh, [bp + si + 4]
        \\sub di, [bp + di + 6]
        \\sub [bx + si], bx
        \\sub [bp], bx
        \\sub [bp], bx
        \\sub [bx + 2], cx
        \\sub [bp + si + 4], bh
        \\sub [bp + di + 6], di
        \\sub byte [bx], 34
        \\sub word [bx + di], 29
        \\sub ax, [bp]
        \\sub al, [bx + si]
        \\sub ax, bx
        \\sub al, ah
        \\sub ax, 1000
        \\sub al, -30
        \\sub al, 9
        //
        \\cmp bx, [bx + si]
        \\cmp bx, [bp]
        \\cmp si, 2
        \\cmp bp, 2
        \\cmp cx, 8
        \\cmp bx, [bp]
        \\cmp cx, [bx + 2]
        \\cmp bh, [bp + si + 4]
        \\cmp di, [bp + di + 6]
        \\cmp [bx + si], bx
        \\cmp [bp], bx
        \\cmp [bp], bx
        \\cmp [bx + 2], cx
        \\cmp [bp + si + 4], bh
        \\cmp [bp + di + 6], di
        \\cmp byte [bx], 34
        \\cmp word [4834], 29
        \\cmp ax, [bp]
        \\cmp al, [bx + si]
        \\cmp ax, bx
        \\cmp al, ah
        \\cmp ax, 1000
        \\cmp al, -30
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
