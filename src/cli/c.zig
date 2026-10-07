//! Hand-written C ABI bindings for the three `time.h` interfaces the CLI
//! uses: format a wall-clock timestamp for display. Zig 0.17 removed
//! `@cImport`; these are stable POSIX signatures (the Windows CRT exports
//! the same names).
const std = @import("std");

/// MSVC's `time_t` is 64-bit (`__time64_t`); `std.c.time_t` reports `void`
/// on Windows, so name that width explicitly.
pub const time_t = if (std.c.time_t == void) i64 else std.c.time_t;

/// Opaque: the CLI shuttles `struct tm` from `localtime` to `strftime`
/// without reading its fields, so no layout is needed here.
pub const tm = opaque {};

pub extern "c" fn localtime(timer: *const time_t) ?*tm;
pub extern "c" fn strftime(
    buffer: [*]u8,
    maxsize: usize,
    format: [*:0]const u8,
    timeptr: *const tm,
) usize;
