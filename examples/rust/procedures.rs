//! Procedure hooks for the keyvalue grammar, written in Rust.
//!
//! Shows ProcedureArguments in action: the current node, its text, children,
//! and source position, plus drop_if_empty on empty tails. Author-defined
//! grammar hooks arrive as `hook_<name>` — Key is annotated `@print`.

use std::ffi::c_void;
use std::io::Write;

mod procedure {
    include!(concat!(env!("OUT_DIR"), "/galley_procedure_types.rs"));
}
use procedure::{HookDoor, NodeHandle, ProcedureArguments};

fn write_stderr(message: &str) {
    let mut stderr = std::io::stderr().lock();
    let _ = stderr.write_all(message.as_bytes());
}

fn write_bytes(bytes: &[u8]) {
    let mut stderr = std::io::stderr().lock();
    let _ = stderr.write_all(bytes);
}

fn pos(door: &HookDoor, node: NodeHandle) -> (u32, u32) {
    door.line_column(node).unwrap_or((0, 0))
}

fn parse_u(bytes: &[u8]) -> u32 {
    let mut value = 0u32;
    for &byte in bytes {
        if byte.is_ascii_digit() {
            value = value * 10 + u32::from(byte - b'0');
        }
    }
    value
}

fn count_pairs(door: &HookDoor, node: NodeHandle) -> (u32, u32) {
    if door.symbol_name(node) == Ok(&b"Pair"[..]) {
        let text = door.text(node).unwrap_or(b"");
        let number = text.split(|&byte| byte == b':').nth(1).unwrap_or(b"");
        return (1, parse_u(number));
    }
    let mut count = 0u32;
    let mut total = 0u32;
    for child in door.children(node) {
        let Ok(child) = child else { break };
        let (child_count, child_sum) = count_pairs(door, child);
        count += child_count;
        total += child_sum;
    }
    (count, total)
}

#[no_mangle]
pub extern "C" fn reduction(_session: *mut c_void, _hook: u64) {}

#[no_mangle]
pub extern "C" fn reduction_Key(_session: *mut c_void, _hook: u64) {}

#[no_mangle]
pub extern "C" fn reduction_PairList(_session: *mut c_void, _hook: u64) {}

#[no_mangle]
pub extern "C" fn reduction_KeyTail(session: *mut c_void, hook: u64) {
    unsafe {
        ProcedureArguments::with(session, hook, |arguments| {
            let _ = arguments.drop_if_empty();
        })
    }
}

#[no_mangle]
pub extern "C" fn reduction_NumberTail(session: *mut c_void, hook: u64) {
    unsafe {
        ProcedureArguments::with(session, hook, |arguments| {
            let _ = arguments.drop_if_empty();
        })
    }
}

#[no_mangle]
pub extern "C" fn reduction_PairListTail(session: *mut c_void, hook: u64) {
    unsafe {
        ProcedureArguments::with(session, hook, |arguments| {
            let _ = arguments.drop_if_empty();
        })
    }
}

#[no_mangle]
pub extern "C" fn hook_print(session: *mut c_void, hook: u64) {
    unsafe {
        ProcedureArguments::with(session, hook, |arguments| {
            let Ok(door) = arguments.door() else {
                return;
            };
            let Ok(Some(node)) = arguments.current_node() else {
                return;
            };
            let (line, column) = pos(door, node);
            write_stderr("@print \"");
            write_bytes(door.text(node).unwrap_or(b""));
            write_stderr(&format!("\" at {line}:{column}\n"));
        })
    }
}

#[no_mangle]
pub extern "C" fn reduction_Number(session: *mut c_void, hook: u64) {
    unsafe {
        ProcedureArguments::with(session, hook, |arguments| {
            let Ok(door) = arguments.door() else {
                return;
            };
            let Ok(Some(node)) = arguments.current_node() else {
                return;
            };
            let (line, column) = pos(door, node);
            write_stderr("Number ");
            write_bytes(door.text(node).unwrap_or(b""));
            write_stderr(&format!(" at {line}:{column}\n"));
            if let Ok(value) = std::str::from_utf8(door.text(node).unwrap_or(b""))
                .unwrap_or("")
                .parse::<u64>()
            {
                if value > 999 {
                    let _ = arguments.report_semantic_error("value out of range");
                }
            }
        })
    }
}

#[no_mangle]
pub extern "C" fn reduction_Pair(session: *mut c_void, hook: u64) {
    unsafe {
        ProcedureArguments::with(session, hook, |arguments| {
            let Ok(door) = arguments.door() else {
                return;
            };
            let Ok(Some(node)) = arguments.current_node() else {
                return;
            };
            let (line, column) = pos(door, node);
            let text = door.text(node).unwrap_or(b"");
            let mut parts = text.splitn(2, |&byte| byte == b':');
            let key = parts.next().unwrap_or(b"");
            let number = parts.next().unwrap_or(b"");
            write_stderr("Pair ");
            write_bytes(key);
            write_stderr("=");
            write_bytes(number);
            write_stderr(&format!(
                " ({} children) at {line}:{column}\n",
                door.child_count(node).unwrap_or(0)
            ));
        })
    }
}

#[no_mangle]
pub extern "C" fn reduction_Document(session: *mut c_void, hook: u64) {
    unsafe {
        ProcedureArguments::with(session, hook, |arguments| {
            let Ok(door) = arguments.door() else {
                return;
            };
            let Ok(Some(node)) = arguments.current_node() else {
                return;
            };
            let (count, total) = count_pairs(door, node);
            write_stderr(&format!("Document {count} pairs, sum={total}\n"));
        })
    }
}
