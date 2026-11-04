const std = @import("std");
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const debug = std.debug;
const fmt = std.fmt;
const heap = std.heap;
const mem = std.mem;
const testing = std.testing;

const Token = union(enum) {
    // not handling bools, nulls, etc...
    openDict: void,
    closeDict: void,
    openList: void,
    closeList: void,
    colon: void,
    comma: void,
    string: []const u8,
    number: f64,
};

const Element = union(enum) {
    string: []const u8,
    number: f64,
    list: []const Element,
    dict: StringHashMap(Element),

    pub fn eql(s: @This(), o: Element) bool {
        switch (s) {
            .string => |v| return o == .string and mem.eql(u8, v, o.string),
            .number => |v| return o == .number and v == o.number,
            .list => |v| {
                if (o != .list or v.len != o.list.len) return false;

                for (0..v.len) |i| if (!v[i].eql(o.list[i])) return false;

                return true;
            },
            .dict => |v| {
                if (o != .dict or v.count() != o.dict.count()) return false;

                var vIt = v.iterator();
                while (vIt.next()) |entry| {
                    if (o.dict.get(entry.key_ptr.*)) |oVal| {
                        if (!entry.value_ptr.*.eql(oVal)) return false;
                    } else return false;
                }

                return true;
            },
        }
    }
};

pub const Parser = struct {
    input: []const u8,
    i: usize = 0,

    pub fn init(input: []const u8) Parser {
        return .{ .input = input };
    }

    // could be fun/improve performance (and definitely devX) to parse it into a known type
    pub fn parse(s: *@This(), a: mem.Allocator) !Element {
        const firstToken = try s.nextToken() orelse {
            return error.InvalidJSON;
        };

        return switch (firstToken) {
            .openDict => try s.parseDict(a),
            .openList => try s.parseList(a),
            .string => |v| {
                if (try s.nextToken() != null) return error.InvalidJSON;
                return .{ .string = v };
            },
            .number => |v| {
                if (try s.nextToken() != null) return error.InvalidJSON;
                return .{ .number = v };
            },
            inline else => error.InvalidJSON,
        };
    }

    fn nextToken(s: *@This()) !?Token {
        const hasMore = s.skipWhitespace();
        if (!hasMore) return null;

        switch (s.input[s.i]) {
            '{' => {
                s.i += 1;
                return .openDict;
            },
            '}' => {
                s.i += 1;
                return .closeDict;
            },
            '[' => {
                s.i += 1;
                return .openList;
            },
            ']' => {
                s.i += 1;
                return .closeList;
            },
            ':' => {
                s.i += 1;
                return .colon;
            },
            ',' => {
                s.i += 1;
                return .comma;
            },
            '"' => {
                // also potentially a key tho, depending solely on position within json
                const startIdx = s.i + 1;
                for (startIdx..s.input.len) |i| {
                    const c = s.input[i];
                    if (c == '"') {
                        s.i = i + 1;
                        return .{ .string = s.input[startIdx..i] };
                    }
                }
                return error.InvalidJSON;
            },
            '-', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' => {
                const startIdx = s.i;
                var endIdx = s.input.len;
                for (startIdx..s.input.len) |i| {
                    const c = s.input[i];
                    if (!isNumeric(c)) {
                        endIdx = i;
                        break;
                    }
                }
                s.i = endIdx;
                const number = fmt.parseFloat(f64, s.input[startIdx..endIdx]) catch {
                    return error.InvalidJSON;
                };
                return .{ .number = number };
            },
            else => return error.InvalidJSON,
        }
    }

    fn parseDict(s: *@This(), a: mem.Allocator) error{ InvalidJSON, OutOfMemory }!Element {
        var dict: StringHashMap(Element) = .init(a);

        while (try s.nextToken()) |key| {
            switch (key) {
                .closeDict => return .{ .dict = dict },
                .comma => continue,
                .string => |cKey| {
                    const colon = try s.nextToken() orelse return error.InvalidJSON;
                    switch (colon) {
                        .colon => {
                            const val = try s.nextToken() orelse return error.InvalidJSON;
                            switch (val) {
                                .openList => try dict.put(cKey, try s.parseList(a)),
                                .openDict => try dict.put(cKey, try s.parseDict(a)),
                                .string => |v| try dict.put(cKey, .{ .string = v }),
                                .number => |v| try dict.put(cKey, .{ .number = v }),
                                inline else => return error.InvalidJSON,
                            }
                        },
                        inline else => return error.InvalidJSON,
                    }
                },
                inline else => return error.InvalidJSON,
            }
        }

        return error.InvalidJSON;
    }

    fn parseList(s: *@This(), a: mem.Allocator) error{ InvalidJSON, OutOfMemory }!Element {
        var list: ArrayList(Element) = .empty;

        while (try s.nextToken()) |t| {
            switch (t) {
                .closeList => return .{ .list = try list.toOwnedSlice(a) },
                .comma => continue,
                .openList => try list.append(a, try s.parseList(a)),
                .openDict => try list.append(a, try s.parseDict(a)),
                .string => |v| try list.append(a, .{ .string = v }),
                .number => |v| try list.append(a, .{ .number = v }),
                inline else => return error.InvalidJSON,
            }
        }

        return error.InvalidJSON;
    }

    fn skipWhitespace(s: *@This()) bool {
        while (s.i < s.input.len) {
            if (!isWhitespace(s.input[s.i])) return true;
            s.i += 1;
        }

        return false;
    }
};

fn isWhitespace(c: u8) bool {
    return mem.containsAtLeastScalar(u8, &ASCII_WHITESPACE, c, 1);
}

fn isNumeric(c: u8) bool {
    // - and . and digits
    return c == 45 or c == 46 or (c >= 48 and c <= 57);
}

const ASCII_WHITESPACE = [_]u8{ 9, 10, 11, 12, 13, 32, 133 };

test "parseJSON" {
    _ = struct {
        var arena: heap.ArenaAllocator = .init(testing.allocator);
        var a: mem.Allocator = undefined;

        fn setup() void {
            a = arena.allocator();
        }
        fn teardown() void {
            _ = arena.reset(.free_all);
        }

        test "empty" {
            setup();

            const input = "";

            var parser = Parser.init(input);
            const err = parser.parse(a);

            try testing.expectError(error.InvalidJSON, err);

            teardown();
        }
        test "all whitespace" {
            setup();

            const input = "  \n  ";

            var parser = Parser.init(input);
            const err = parser.parse(a);

            try testing.expectError(error.InvalidJSON, err);

            teardown();
        }
        test "string:: empty" {
            setup();

            const input = "\"\"";
            const expected = Element{ .string = "" };

            var parser = Parser.init(input);
            const actual = try parser.parse(a);

            try testing.expect(actual.eql(expected));

            teardown();
        }
        test "string:: oneChar" {
            setup();

            const input = "\"a\"";
            const expected = Element{ .string = "a" };

            var parser = Parser.init(input);
            const actual = try parser.parse(a);

            try testing.expect(actual.eql(expected));

            teardown();
        }
        test "string:: multiChar" {
            setup();

            const input = "\"ab\"";
            const expected = Element{ .string = "ab" };

            var parser = Parser.init(input);
            const actual = try parser.parse(a);

            try testing.expect(actual.eql(expected));

            teardown();
        }
        test "string:: unterminated" {
            setup();

            const input = "\"abc  ";

            var parser = Parser.init(input);
            const err = parser.parse(a);

            try testing.expectError(error.InvalidJSON, err);

            teardown();
        }
        test "number:: no decimal" {
            setup();

            const input = "1";
            const expected = Element{ .number = 1 };

            var parser = Parser.init(input);
            const actual = try parser.parse(a);

            try testing.expect(actual.eql(expected));

            teardown();
        }
        test "number:: decimal" {
            setup();

            const input = "1.1";
            const expected = Element{ .number = 1.1 };

            var parser = Parser.init(input);
            const actual = try parser.parse(a);

            try testing.expect(actual.eql(expected));

            teardown();
        }
        test "number:: negative no decimal" {
            setup();

            const input = "-1";
            const expected = Element{ .number = -1 };

            var parser = Parser.init(input);
            const actual = try parser.parse(a);

            try testing.expect(actual.eql(expected));

            teardown();
        }
        test "number:: negative decimal" {
            setup();

            const input = "-1.1";
            const expected = Element{ .number = -1.1 };

            var parser = Parser.init(input);
            const actual = try parser.parse(a);

            try testing.expect(actual.eql(expected));

            teardown();
        }
        test "list:: empty" {
            setup();

            const input = "[]";
            const expected = Element{ .list = &.{} };

            var parser = Parser.init(input);
            const actual = try parser.parse(a);

            try testing.expect(actual.eql(expected));

            teardown();
        }
        test "list:: nested" {
            setup();

            const input = "[[]]";
            const expected = Element{ .list = &.{Element{ .list = &.{} }} };

            var parser = Parser.init(input);
            const actual = try parser.parse(a);

            try testing.expect(actual.eql(expected));

            teardown();
        }
        test "list:: elements" {
            setup();

            const input = "[\"abc\", 123]";
            const expected = Element{ .list = &.{
                Element{ .string = "abc" },
                Element{ .number = 123 },
            } };

            var parser = Parser.init(input);
            const actual = try parser.parse(a);

            try testing.expect(actual.eql(expected));

            teardown();
        }
        test "list:: nested elements" {
            setup();

            const input = "[[\"abc\"], [123]]";
            const expected = Element{ .list = &.{
                Element{ .list = &.{Element{ .string = "abc" }} },
                Element{ .list = &.{Element{ .number = 123 }} },
            } };

            var parser = Parser.init(input);
            const actual = try parser.parse(a);

            try testing.expect(actual.eql(expected));

            teardown();
        }
        test "dict:: empty" {
            setup();

            const input = "{}";
            const expected = Element{ .dict = .init(a) };

            var parser = Parser.init(input);
            const actual = try parser.parse(a);

            try testing.expect(actual.eql(expected));

            teardown();
        }
        test "dict:: nested" {
            setup();

            const input = "{\"k\":{}}";
            var dict = StringHashMap(Element).init(a);
            try dict.put("k", .{ .dict = .init(a) });
            const expected = Element{ .dict = dict };

            var parser = Parser.init(input);
            const actual = try parser.parse(a);

            try testing.expect(actual.eql(expected));

            teardown();
        }
        test "dict:: elements" {
            setup();

            const input = "{\"k0\": \"abc\", \"k1\": 123}";
            var dict = StringHashMap(Element).init(a);
            try dict.put("k0", .{ .string = "abc" });
            try dict.put("k1", .{ .number = 123 });
            const expected = Element{ .dict = dict };

            var parser = Parser.init(input);
            const actual = try parser.parse(a);

            try testing.expect(actual.eql(expected));

            teardown();
        }
        test "dict:: nested elements" {
            setup();

            const input = "{\"k0\":{\"k00\": \"abc\"}, \"k1\":{\"k11\": 123}}";
            var strNested = StringHashMap(Element).init(a);
            try strNested.put("k00", .{ .string = "abc" });
            var numNested = StringHashMap(Element).init(a);
            try numNested.put("k11", .{ .number = 123 });
            var dict = StringHashMap(Element).init(a);
            try dict.put("k0", .{ .dict = strNested });
            try dict.put("k1", .{ .dict = numNested });
            const expected = Element{ .dict = dict };

            var parser = Parser.init(input);
            const actual = try parser.parse(a);

            try testing.expect(actual.eql(expected));

            teardown();
        }
        test "the one thing it actually NEEDS to parse" {
            setup();

            const input =
                \\{
                \\  "size": 2,
                \\  "seed": 9001,
                \\  "sum": 123,
                \\  "pairs": [
                \\    [
                \\      {
                \\        "x": 1.11,
                \\        "y": 1.12
                \\      },
                \\      {
                \\        "x": -1.21,
                \\        "y": -1.22
                \\      }
                \\    ],
                \\    [
                \\      {
                \\        "x": 2.11,
                \\        "y": 2.12
                \\      },
                \\      {
                \\        "x": -2.21,
                \\        "y": -2.22
                \\      }
                \\    ],
                \\  ]
                \\}
            ;

            var pair11 = StringHashMap(Element).init(a);
            try pair11.put("x", .{ .number = 1.11 });
            try pair11.put("y", .{ .number = 1.12 });
            var pair12 = StringHashMap(Element).init(a);
            try pair12.put("x", .{ .number = -1.21 });
            try pair12.put("y", .{ .number = -1.22 });
            var pair21 = StringHashMap(Element).init(a);
            try pair21.put("x", .{ .number = 2.11 });
            try pair21.put("y", .{ .number = 2.12 });
            var pair22 = StringHashMap(Element).init(a);
            try pair22.put("x", .{ .number = -2.21 });
            try pair22.put("y", .{ .number = -2.22 });
            const pairs = &.{
                Element{ .list = &.{
                    Element{ .dict = pair11 },
                    Element{ .dict = pair12 },
                } },
                Element{ .list = &.{
                    Element{ .dict = pair21 },
                    Element{ .dict = pair22 },
                } },
            };

            var dict = StringHashMap(Element).init(a);
            try dict.put("size", .{ .number = 2 });
            try dict.put("seed", .{ .number = 9001 });
            try dict.put("sum", .{ .number = 123 });
            try dict.put("pairs", .{ .list = pairs });
            const expected = Element{ .dict = dict };

            var parser = Parser.init(input);
            const actual = try parser.parse(a);

            try testing.expect(actual.eql(expected));

            teardown();
        }
    };
}
