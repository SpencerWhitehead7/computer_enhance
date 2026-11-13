const std = @import("std");
const ArrayList = std.ArrayList;
const Io = std.Io;
const StringArrayHashMapUnmanaged = std.StringArrayHashMapUnmanaged;
const debug = std.debug;
const mem = std.mem;
const testing = std.testing;

const timers = @import("timers.zig");

const Timer = struct {
    label: []const u8 = "",
    children: ArrayList(*Timer) = .empty,
    begTS: u64 = 0,
    endTS: u64 = 0,

    fn init(comptime label: []const u8) Timer {
        return .{
            .label = label,
        };
    }

    fn deinit(s: *@This(), a: mem.Allocator) void {
        for (s.children.items) |c| {
            c.deinit(a);
            a.destroy(c);
        }

        s.children.deinit(a);
    }

    fn beg(s: *@This()) void {
        if (s.begTS != 0) {
            debug.print("cannot beg the same timer twice", .{});
            unreachable;
        }

        s.begTS = timers.readCPUTimer();
    }

    fn end(s: *@This()) void {
        if (s.begTS == 0) {
            debug.print("cannot end a timer which has not beg", .{});
            unreachable;
        }

        s.endTS = timers.readCPUTimer();
    }

    fn duration(s: *const @This()) u64 {
        return s.endTS - s.begTS;
    }

    fn report(s: *const @This(), depth: usize) void {
        // TODO calculate and print percentages
        const freq = @as(f64, @floatFromInt(timers.getCPUTimerFreq()));

        const totalDuration = s.duration();
        const totalDurationMs = (@as(f64, @floatFromInt(totalDuration)) / freq) * 1_000;

        var childrenDuration: u64 = 0;
        for (s.children.items) |c| childrenDuration += c.duration();
        const childrenDurationMs = (@as(f64, @floatFromInt(childrenDuration)) / freq) * 1_000;

        const selfDuration = totalDuration - childrenDuration;
        const selfDurationMs = (@as(f64, @floatFromInt(selfDuration)) / freq) * 1_000;

        for (0..depth) |_| debug.print(" ", .{});
        debug.print("{s}", .{s.label});
        const labelSectionLen = depth + s.label.len;
        if (labelSectionLen < 31) {
            for (0..(31 - depth - s.label.len)) |_| debug.print(" ", .{});
        }

        debug.print(
            " | {d: >14.2} | {d: >14.2} | {d: >15.2}\n",
            .{ totalDurationMs, selfDurationMs, childrenDurationMs },
        );
        for (s.children.items) |c| c.report(depth + 1);
    }
};

const TimerMerged = struct {
    label: []const u8,
    children: StringArrayHashMapUnmanaged(*TimerMerged) = .empty,
    duration: u64,

    fn init(a: mem.Allocator, timer: *const Timer) !TimerMerged {
        var children: StringArrayHashMapUnmanaged(*TimerMerged) = .empty;
        for (timer.children.items) |c| {
            const res = try children.getOrPut(a, c.label);
            if (res.found_existing) {
                try res.value_ptr.*.merge(a, c);
            } else {
                res.value_ptr.* = try a.create(TimerMerged);
                res.value_ptr.*.* = try TimerMerged.init(a, c);
            }
        }

        return .{
            .label = timer.label,
            .children = children,
            .duration = timer.endTS - timer.begTS,
        };
    }

    fn merge(s: *@This(), a: mem.Allocator, o: *const Timer) error{OutOfMemory}!void {
        s.duration += o.endTS - o.begTS;

        for (o.children.items) |c| {
            const res = try s.children.getOrPut(a, c.label);
            if (res.found_existing) {
                try res.value_ptr.*.merge(a, c);
            } else {
                res.value_ptr.* = try a.create(TimerMerged);
                res.value_ptr.*.* = try TimerMerged.init(a, c);
            }
        }
    }

    fn deinit(s: *@This(), a: mem.Allocator) void {
        for (s.children.values()) |c| {
            c.deinit(a);
            a.destroy(c);
        }

        s.children.deinit(a);
    }

    fn report(s: *const @This(), depth: usize) void {
        // TODO calculate and print percentages
        const freq = @as(f64, @floatFromInt(timers.getCPUTimerFreq()));

        const totalDurationMs = (@as(f64, @floatFromInt(s.duration)) / freq) * 1_000;

        var childrenDuration: u64 = 0;
        for (s.children.values()) |c| childrenDuration += c.duration;
        const childrenDurationMs = (@as(f64, @floatFromInt(childrenDuration)) / freq) * 1_000;

        const selfDuration = s.duration - childrenDuration;
        const selfDurationMs = (@as(f64, @floatFromInt(selfDuration)) / freq) * 1_000;

        for (0..depth) |_| debug.print(" ", .{});
        debug.print("{s}", .{s.label});
        const labelSectionLen = depth + s.label.len;
        if (labelSectionLen < 31) {
            for (0..(31 - depth - s.label.len)) |_| debug.print(" ", .{});
        }

        debug.print(
            " | {d: >14.2} | {d: >14.2} | {d: >15.2}\n",
            .{ totalDurationMs, selfDurationMs, childrenDurationMs },
        );
        for (s.children.values()) |c| c.report(depth + 1);
    }
};

pub const Profiler = struct {
    comptime isEnabled: bool = true,

    a: mem.Allocator = undefined,
    root: Timer = undefined,
    stack: ArrayList(*Timer) = undefined,

    pub fn init(s: *@This(), a: mem.Allocator) !void {
        if (comptime !s.isEnabled) return;

        s.a = a;
        s.root = Timer.init("root");
        s.stack = try ArrayList(*Timer).initCapacity(a, 256);
        try s.stack.append(a, &s.root);

        s.root.beg();
    }

    pub fn deinit(s: *@This()) void {
        if (comptime !s.isEnabled) return;

        if (s.stack.items.len > 1) {
            debug.print("unbalanced block beg/end somewhere:: {any}", .{s.stack.items});
            unreachable;
        }

        s.root.end();

        // s.report();
        s.reportMerged();

        s.root.deinit(s.a);
        s.stack.deinit(s.a);
    }

    pub fn beg(s: *@This(), comptime label: []const u8) void {
        if (comptime !s.isEnabled) return;

        const child = s.a.create(Timer) catch {
            debug.panic(
                "{s}:: failed to allocate Timer {s}, Profiler failed",
                .{ label, label },
            );
        };
        child.* = Timer.init(label);

        const parent = s.stack.last();
        if (parent) |p| p.children.append(s.a, child) catch {
            debug.panic(
                "{s}:: failed to append Timer {s} to parent {s}, Profiler failed",
                .{ label, label, p.label },
            );
        };
        s.stack.append(s.a, child) catch {
            debug.panic(
                "{s}:: failed to append Timer {s} to stack, Profiler failed",
                .{ label, label },
            );
        };

        child.beg();
    }

    pub fn end(s: *@This()) void {
        if (comptime !s.isEnabled) return;

        const timer = s.stack.pop();
        if (timer) |t| t.end();
    }

    fn report(s: *const @This()) void {
        if (comptime !s.isEnabled) return;

        debug.print("\n", .{});
        debug.print("cpuFreq:: {d}\n", .{timers.getCPUTimerFreq()});
        debug.print(
            "{s: <31} | {s: >14} | {s: >14} | {s: >15}\n",
            .{ "label", "totalDuration", "selfDuration", "childrenDuration" },
        );
        debug.print(
            "{s:-<31}-+-{s:->14}-+-{s:->14}-+-{s:->15}\n",
            .{ "", "", "", "" },
        );

        const reportStart = timers.readCPUTimer();

        s.root.report(0);

        const reportEnd = timers.readCPUTimer();

        debug.print(
            "\n{d:.2}ms to report\n",
            .{@as(f64, @floatFromInt(reportEnd - reportStart)) / @as(f64, @floatFromInt(timers.getCPUTimerFreq())) * 1_000},
        );
        // profiling the profiler lmao

        debug.print("\n", .{});
    }

    fn reportMerged(s: *const @This()) void {
        if (comptime !s.isEnabled) return;

        debug.print("\n", .{});
        debug.print("cpuFreq:: {d}\n", .{timers.getCPUTimerFreq()});
        debug.print(
            "{s: <31} | {s: >14} | {s: >14} | {s: >15}\n",
            .{ "label", "totalDuration", "selfDuration", "childrenDuration" },
        );
        debug.print(
            "{s:-<31}-+-{s:->14}-+-{s:->14}-+-{s:->15}\n",
            .{ "", "", "", "" },
        );

        const reportStart = timers.readCPUTimer();

        var merged = TimerMerged.init(s.a, &s.root) catch |err| {
            debug.print("Consolidation failed:: {}", .{err});
            return;
        };
        merged.report(0);
        merged.deinit(s.a);

        const reportEnd = timers.readCPUTimer();

        debug.print(
            "\n{d:.2}ms to report\n",
            .{@as(f64, @floatFromInt(reportEnd - reportStart)) / @as(f64, @floatFromInt(timers.getCPUTimerFreq())) * 1_000},
        );

        debug.print("\n", .{});
    }
};

pub var profiler: Profiler = .{};

test "Timer" {
    _ = struct {
        test "basic" {
            var t = Timer.init("testBasic");
            defer t.deinit(testing.allocator);

            t.report(0);
        }
    };
}

test "Profiler" {
    _ = struct {
        test "no block" {
            var p: Profiler = .{};
            try p.init(testing.allocator);

            try testing.expect(p.root.begTS != 0);
            try testing.expect(p.root.endTS == 0);
            try testing.expectEqual(0, p.root.children.items.len);
            try testing.expectEqual(1, p.stack.items.len);
            try testing.expectEqual(p.root, p.stack.items[0].*);

            p.deinit();

            try testing.expect(p.root.endTS != 0);
        }

        test "one block" {
            var p: Profiler = .{};
            try p.init(testing.allocator);
            defer p.deinit();

            try testing.expectEqual(0, p.root.children.items.len);
            try testing.expectEqual(1, p.stack.items.len);

            try p.beg("block");
            {
                try testing.expectEqual(1, p.root.children.items.len);
                try testing.expectEqual(2, p.stack.items.len);
                try testing.expectEqual(p.root.children.items[0].*, p.stack.items[1].*);
                try testing.expect(p.root.children.items[0].begTS != 0);
                try testing.expect(p.root.children.items[0].endTS == 0);
            }
            p.end();

            try testing.expectEqual(1, p.root.children.items.len);
            try testing.expectEqual(1, p.stack.items.len);
            try testing.expect(p.root.children.items[0].endTS != 0);
        }

        test "multiple blocks" {
            var p: Profiler = .{};
            try p.init(testing.allocator);
            defer p.deinit();

            try testing.expectEqual(0, p.root.children.items.len);
            try testing.expectEqual(1, p.stack.items.len);

            try p.beg("block0");
            {
                try testing.expectEqual(1, p.root.children.items.len);
                try testing.expectEqual(2, p.stack.items.len);
                try testing.expectEqual(p.root.children.items[0].*, p.stack.items[1].*);
            }
            p.end();

            try testing.expectEqual(1, p.root.children.items.len);
            try testing.expectEqual(1, p.stack.items.len);

            try p.beg("block1");
            {
                try testing.expectEqual(2, p.root.children.items.len);
                try testing.expectEqual(2, p.stack.items.len);
                try testing.expectEqual(p.root.children.items[1].*, p.stack.items[1].*);
            }
            p.end();

            try testing.expectEqual(2, p.root.children.items.len);
            try testing.expectEqual(1, p.stack.items.len);
        }

        test "nested blocks" {
            var p: Profiler = .{};
            try p.init(testing.allocator);
            defer p.deinit();

            try testing.expectEqual(0, p.root.children.items.len);
            try testing.expectEqual(1, p.stack.items.len);

            try p.beg("block");
            {
                try testing.expectEqual(1, p.root.children.items.len);
                try testing.expectEqual(0, p.root.children.items[0].children.items.len);
                try testing.expectEqual(2, p.stack.items.len);
                try testing.expectEqual(p.root.children.items[0].*, p.stack.items[1].*);

                try p.beg("subblock");
                {
                    try testing.expectEqual(1, p.root.children.items.len);
                    try testing.expectEqual(1, p.root.children.items[0].children.items.len);
                    try testing.expectEqual(0, p.root.children.items[0].children.items[0].children.items.len);
                    try testing.expectEqual(3, p.stack.items.len);
                    try testing.expectEqual(p.root.children.items[0].*, p.stack.items[1].*);
                    try testing.expectEqual(p.root.children.items[0].children.items[0].*, p.stack.items[2].*);
                }
                p.end();

                try testing.expectEqual(1, p.root.children.items.len);
                try testing.expectEqual(1, p.root.children.items[0].children.items.len);
                try testing.expectEqual(0, p.root.children.items[0].children.items[0].children.items.len);
                try testing.expectEqual(2, p.stack.items.len);
                try testing.expectEqual(p.root.children.items[0].*, p.stack.items[1].*);
            }
            p.end();

            try testing.expectEqual(1, p.root.children.items.len);
            try testing.expectEqual(1, p.root.children.items[0].children.items.len);
            try testing.expectEqual(0, p.root.children.items[0].children.items[0].children.items.len);
            try testing.expectEqual(1, p.stack.items.len);
        }

        // test "unbalanced blocks" { there does not appear to be a reasonable way to test panics
        //     var p: Profiler = .{};
        //     try p.init(testing.allocator);

        //     try p.beg("block");

        //     try testing.expectError(unreachable, p.deinit());
        // }
    };
}

// 7 seconds with all profiling off
// 8 with "standard" profiling
