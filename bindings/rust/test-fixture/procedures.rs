//! Procedure hooks for the keyvalue grammar, written in Rust.
//!
//! Shows ProcedureArguments in action: the current node, its text, children,
//! and source position, plus drop_if_empty on empty tails. Author-defined
//! grammar hooks arrive as `hook_<name>` — Key is annotated `@print`.

use std::io::Write;
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::Mutex;

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

// What the Document hook records for the tests/hook_door.rs suite: the root
// of the previous parse is kept, and every hook-door read of it in the next
// parse must come back `Error::StaleTree`, while the running parse's own node
// still reads.
static PREVIOUS_ROOT: Mutex<Option<NodeHandle>> = Mutex::new(None);
static STALE_REFUSALS: AtomicU32 = AtomicU32::new(0);
static LIVE_READS: AtomicU32 = AtomicU32::new(0);

/// How many of the hook-door reads of the previous parse's root were refused
/// as a stale tree during the last parse.
#[no_mangle]
pub extern "C" fn fixture_hook_stale_refusals() -> u32 {
    STALE_REFUSALS.load(Ordering::SeqCst)
}

/// How many hook-door reads of the running parse's own node succeeded.
#[no_mangle]
pub extern "C" fn fixture_hook_live_reads() -> u32 {
    LIVE_READS.load(Ordering::SeqCst)
}

fn probe_hook_door(arguments: &mut ProcedureArguments, node: NodeHandle) {
    let mut previous = PREVIOUS_ROOT.lock().unwrap();
    if let Some(stale) = *previous {
        let door = arguments.door();
        let stale_error = Err(procedure::Error::StaleTree);
        let refusals = [
            door.text(stale).map(drop) == stale_error,
            door.symbol_name(stale).map(drop) == stale_error,
            door.span(stale).map(drop) == stale_error,
            door.line_column(stale).map(drop) == stale_error,
            door.child_count(stale).map(drop) == stale_error,
            door.variable_index(stale).map(drop) == stale_error,
            door.first_child(stale).map(drop) == stale_error,
            door.last_child(stale).map(drop) == stale_error,
            door.next_sibling(stale).map(drop) == stale_error,
            door.prior_sibling(stale).map(drop) == stale_error,
            door.parent(stale).map(drop) == stale_error,
            // children() yields the refusal, once, then ends.
            door.children(stale).map(|child| child.map(drop)).collect::<Vec<_>>() == [stale_error],
        ];
        let live = [
            door.text(node).is_ok(),
            door.symbol_name(node).is_ok(),
            door.span(node).is_ok(),
            door.line_column(node).is_ok(),
            door.child_count(node).is_ok(),
            door.variable_index(node).is_ok(),
            door.first_child(node).is_ok(),
            door.last_child(node).is_ok(),
            door.next_sibling(node).is_ok(),
            door.prior_sibling(node).is_ok(),
            door.parent(node).is_ok(),
            door.children(node).all(|child| child.is_ok()),
        ];
        let mut refused = refusals.iter().filter(|refused| **refused).count() as u32;
        let mut read = live.iter().filter(|read| **read).count() as u32;
        // set_current_node: a node of the previous parse is refused and the
        // current node stays; a node of this parse sets.
        let kept = arguments.current_node();
        if arguments.set_current_node(Some(stale)) == stale_error && arguments.current_node() == kept {
            refused += 1;
        }
        if arguments.set_current_node(Some(node)).is_ok() && arguments.current_node() == Ok(Some(node)) {
            read += 1;
        }
        STALE_REFUSALS.store(refused, Ordering::SeqCst);
        LIVE_READS.store(read, Ordering::SeqCst);
    }
    *previous = Some(node);
}

#[no_mangle]
pub extern "C" fn reduction(_arguments: &mut ProcedureArguments) {}

#[no_mangle]
pub extern "C" fn reduction_Key(_arguments: &mut ProcedureArguments) {}

#[no_mangle]
pub extern "C" fn reduction_PairList(_arguments: &mut ProcedureArguments) {}

#[no_mangle]
pub extern "C" fn reduction_KeyTail(arguments: &mut ProcedureArguments) {
    let _ = arguments.drop_if_empty();
}

#[no_mangle]
pub extern "C" fn reduction_NumberTail(arguments: &mut ProcedureArguments) {
    let _ = arguments.drop_if_empty();
}

#[no_mangle]
pub extern "C" fn reduction_PairListTail(arguments: &mut ProcedureArguments) {
    let _ = arguments.drop_if_empty();
}

#[no_mangle]
pub extern "C" fn hook_print(arguments: &mut ProcedureArguments) {
    let door = arguments.door();
    let Ok(Some(node)) = arguments.current_node() else {
        return;
    };
    let (line, column) = pos(door, node);
    write_stderr("@print \"");
    write_bytes(door.text(node).unwrap_or(b""));
    write_stderr(&format!("\" at {line}:{column}\n"));
}

#[no_mangle]
pub extern "C" fn reduction_Number(arguments: &mut ProcedureArguments) {
    let door = arguments.door();
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
}

#[no_mangle]
pub extern "C" fn reduction_Pair(arguments: &mut ProcedureArguments) {
    let door = arguments.door();
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
}

#[no_mangle]
pub extern "C" fn reduction_Document(arguments: &mut ProcedureArguments) {
    let Ok(Some(node)) = arguments.current_node() else {
        return;
    };
    probe_hook_door(arguments, node);
    let door = arguments.door();
    let (count, total) = count_pairs(door, node);
    write_stderr(&format!("Document {count} pairs, sum={total}\n"));
}
