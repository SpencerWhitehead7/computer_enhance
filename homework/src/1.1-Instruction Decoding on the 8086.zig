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
    NotModRegisterMode,
};

const BYTE_REGISTERS = [8]*const [2:0]u8{ "al", "cl", "dl", "bl", "ah", "ch", "dh", "bh" };
const WORD_REGISTERS = [8]*const [2:0]u8{ "ax", "cx", "dx", "bx", "sp", "bp", "si", "di" };

fn decode(allocator: std.mem.Allocator, encoded: []const u8) ![]u8 {
    var decoded: std.ArrayList(u8) = .empty;
    errdefer decoded.deinit(allocator);
    try decoded.appendSlice(allocator, "bits 16\n\n");

    var i: u8 = 0;
    while (i < encoded.len) : (i += 2) {
        const byte1 = encoded[i];
        const byte2 = encoded[i + 1];

        const opcode = byte1 & 0b11111100;
        if (opcode != 0b10001000) {
            return InstructionDecodeError.NotMov;
        }
        const d = byte1 & 0b00000010;
        const w = byte1 & 0b00000001;

        const mod = byte2 & 0b11000000;
        if (mod != 0b11000000) {
            return InstructionDecodeError.NotModRegisterMode;
        }
        const reg = (byte2 & 0b00111000) >> 3;
        const rsm = byte2 & 0b00000111;

        const dst, const src = if (d == 0)
            .{ rsm, reg }
        else
            .{ reg, rsm };

        const registers = if (w == 0)
            BYTE_REGISTERS
        else
            WORD_REGISTERS;

        try decoded.appendSlice(allocator, "mov" ++ " " ++
            registers[dst] ++ ", " ++ registers[src] ++ "\n");
    }

    return decoded.toOwnedSlice(allocator);
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
