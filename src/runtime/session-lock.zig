//! The session's fail-fast reader/writer lock. Every acquisition is a try:
//! it never blocks, and it is refused only while the opposite mode is held
//! (a reader refuses a writer, a writer refuses everyone). A refusal is never
//! spurious, which `std.Io.RwLock.tryLockShared` does not guarantee: it can
//! return false under reader contention with no writer present, and the
//! shared-access contract in docs/concurrency.md needs that never to happen.
const std = @import("std");

const SessionLock = @This();

/// Bit 0 is the writer; the remaining bits count readers.
state: std.atomic.Value(usize) = .init(0),

const writer: usize = 1;
const reader: usize = 2;

pub const init: SessionLock = .{};

/// Takes shared access. Fails only while a writer holds the lock.
pub fn tryLockShared(self: *SessionLock) bool {
    var current = self.state.load(.monotonic);
    while (current & writer == 0) {
        current = self.state.cmpxchgWeak(current, current + reader, .acquire, .monotonic) orelse return true;
    }
    return false;
}

pub fn unlockShared(self: *SessionLock) void {
    const previous = self.state.fetchSub(reader, .release);
    std.debug.assert(previous >= reader and previous & writer == 0);
}

/// Takes exclusive access. Fails only while any reader or writer holds the lock.
pub fn tryLock(self: *SessionLock) bool {
    return self.state.cmpxchgStrong(0, writer, .acquire, .monotonic) == null;
}

pub fn unlock(self: *SessionLock) void {
    const previous = self.state.swap(0, .release);
    std.debug.assert(previous == writer);
}

test "shared holders coexist and exclude the writer" {
    var lock: SessionLock = .init;
    try std.testing.expect(lock.tryLockShared());
    try std.testing.expect(lock.tryLockShared());
    try std.testing.expect(!lock.tryLock());
    lock.unlockShared();
    try std.testing.expect(!lock.tryLock());
    lock.unlockShared();
    try std.testing.expect(lock.tryLock());
}

test "the writer excludes readers and other writers" {
    var lock: SessionLock = .init;
    try std.testing.expect(lock.tryLock());
    try std.testing.expect(!lock.tryLockShared());
    try std.testing.expect(!lock.tryLock());
    lock.unlock();
    try std.testing.expect(lock.tryLockShared());
    lock.unlockShared();
}

const reader_count = 8;
const iterations = 200_000;

fn contendedReader(lock: *SessionLock, refused: *std.atomic.Value(usize)) void {
    for (0..iterations) |_| {
        if (lock.tryLockShared()) lock.unlockShared() else _ = refused.fetchAdd(1, .monotonic);
    }
}

test "readers are never refused while no writer exists" {
    var lock: SessionLock = .init;
    var refused: std.atomic.Value(usize) = .init(0);
    var threads: [reader_count]std.Thread = undefined;
    for (&threads) |*thread| thread.* = try std.Thread.spawn(.{}, contendedReader, .{ &lock, &refused });
    for (threads) |thread| thread.join();
    try std.testing.expectEqual(@as(usize, 0), refused.load(.monotonic));
    try std.testing.expect(lock.tryLock());
}

fn contendedMixed(lock: *SessionLock, inside_writer: *std.atomic.Value(usize), inside_readers: *std.atomic.Value(usize), violations: *std.atomic.Value(usize), writes: bool) void {
    for (0..iterations) |_| {
        if (writes) {
            if (lock.tryLock()) {
                if (inside_readers.load(.acquire) != 0 or inside_writer.fetchAdd(1, .acq_rel) != 0) _ = violations.fetchAdd(1, .monotonic);
                _ = inside_writer.fetchSub(1, .acq_rel);
                lock.unlock();
            }
        } else if (lock.tryLockShared()) {
            _ = inside_readers.fetchAdd(1, .acq_rel);
            if (inside_writer.load(.acquire) != 0) _ = violations.fetchAdd(1, .monotonic);
            _ = inside_readers.fetchSub(1, .acq_rel);
            lock.unlockShared();
        }
    }
}

test "a writer never overlaps a reader or another writer" {
    var lock: SessionLock = .init;
    var inside_writer: std.atomic.Value(usize) = .init(0);
    var inside_readers: std.atomic.Value(usize) = .init(0);
    var violations: std.atomic.Value(usize) = .init(0);
    var threads: [reader_count]std.Thread = undefined;
    for (&threads, 0..) |*thread, index| {
        thread.* = try std.Thread.spawn(.{}, contendedMixed, .{ &lock, &inside_writer, &inside_readers, &violations, index % 4 == 0 });
    }
    for (threads) |thread| thread.join();
    try std.testing.expectEqual(@as(usize, 0), violations.load(.monotonic));
}
