//! Procedure hooks for the keyvalue grammar, written in Rust.
//!
//! Each function fires after the corresponding variable is reduced. The
//! build helper compiles this file with rustc into a static archive and
//! links it into the parser shared library; the hook bodies only write to
//! stderr, so no Galley API declarations are needed here.
//!
//! Author-defined grammar hooks arrive namespaced as `hook_<name>` — the
//! grammar annotates Key with `@print`, and the entry point is
//! `hook_print`, so it can never collide with unrelated symbols.

use std::io::Write;

/// Writes one hook note to stderr. Failures are ignored on purpose: a
/// closed stderr must not abort an otherwise healthy parse.
fn note(message: &str) {
    let mut stderr = std::io::stderr().lock();
    let _ = stderr.write_all(message.as_bytes());
}

#[no_mangle]
pub extern "C" fn reduction(_args: *mut core::ffi::c_void) {
    note("[hook] reduction\n");
}

#[no_mangle]
pub extern "C" fn reduction_Document(_args: *mut core::ffi::c_void) {
    note("[hook] Document\n");
}

#[no_mangle]
pub extern "C" fn reduction_PairList(_args: *mut core::ffi::c_void) {
    note("[hook] PairList\n");
}

#[no_mangle]
pub extern "C" fn reduction_PairListTail(_args: *mut core::ffi::c_void) {}

#[no_mangle]
pub extern "C" fn reduction_Pair(_args: *mut core::ffi::c_void) {
    note("[hook] Pair\n");
}

#[no_mangle]
pub extern "C" fn reduction_Key(_args: *mut core::ffi::c_void) {
    note("[hook] Key\n");
}

#[no_mangle]
pub extern "C" fn hook_print(_args: *mut core::ffi::c_void) {
    note("[hook] print (Key)\n");
}

#[no_mangle]
pub extern "C" fn reduction_KeyTail(_args: *mut core::ffi::c_void) {}

#[no_mangle]
pub extern "C" fn reduction_Number(_args: *mut core::ffi::c_void) {
    note("[hook] Number\n");
}

#[no_mangle]
pub extern "C" fn reduction_NumberTail(_args: *mut core::ffi::c_void) {}
