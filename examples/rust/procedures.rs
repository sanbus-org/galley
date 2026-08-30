//! Procedure hooks for the keyvalue grammar, written in Rust.
//!
//! Shows ProcedureArguments in action: the current node, its text, children,
//! and source position, plus drop_if_empty on empty tails. Author-defined
//! grammar hooks arrive as `hook_<name>` — Key is annotated `@print`.

use std::io::Write;

#[path = "../../bindings/rust/src/procedure.rs"]
mod procedure;
use procedure::{NodeHandle, ProcedureArguments};

fn write_stderr(message: &str) {
    let mut stderr = std::io::stderr().lock();
    let _ = stderr.write_all(message.as_bytes());
}

fn write_bytes(bytes: &[u8]) {
    let mut stderr = std::io::stderr().lock();
    let _ = stderr.write_all(bytes);
}

fn pos(arguments: &ProcedureArguments, node: NodeHandle) -> (u32, u32) {
    arguments.line_column(node).unwrap_or((0, 0))
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

fn count_pairs(arguments: &ProcedureArguments, node: NodeHandle) -> (u32, u32) {
    if arguments.symbol_name(node) == Some(b"Pair") {
        let text = arguments.text(node).unwrap_or(b"");
        let number = text.split(|&byte| byte == b':').nth(1).unwrap_or(b"");
        return (1, parse_u(number));
    }
    let mut count = 0u32;
    let mut total = 0u32;
    for child in arguments.children(node) {
        let (child_count, child_sum) = count_pairs(arguments, child);
        count += child_count;
        total += child_sum;
    }
    (count, total)
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
    let Some(node) = arguments.current_node() else {
        return;
    };
    let (line, column) = pos(arguments, node);
    write_stderr("@print \"");
    write_bytes(arguments.text(node).unwrap_or(b""));
    write_stderr(&format!("\" at {line}:{column}\n"));
}

#[no_mangle]
pub extern "C" fn reduction_Number(arguments: &mut ProcedureArguments) {
    let Some(node) = arguments.current_node() else {
        return;
    };
    let (line, column) = pos(arguments, node);
    write_stderr("Number ");
    write_bytes(arguments.text(node).unwrap_or(b""));
    write_stderr(&format!(" at {line}:{column}\n"));
}

#[no_mangle]
pub extern "C" fn reduction_Pair(arguments: &mut ProcedureArguments) {
    let Some(node) = arguments.current_node() else {
        return;
    };
    let (line, column) = pos(arguments, node);
    let text = arguments.text(node).unwrap_or(b"");
    let mut parts = text.splitn(2, |&byte| byte == b':');
    let key = parts.next().unwrap_or(b"");
    let number = parts.next().unwrap_or(b"");
    write_stderr("Pair ");
    write_bytes(key);
    write_stderr("=");
    write_bytes(number);
    write_stderr(&format!(
        " ({} children) at {line}:{column}\n",
        arguments.child_count(node)
    ));
}

#[no_mangle]
pub extern "C" fn reduction_Document(arguments: &mut ProcedureArguments) {
    let Some(node) = arguments.current_node() else {
        return;
    };
    let (count, total) = count_pairs(arguments, node);
    write_stderr(&format!("Document {count} pairs, sum={total}\n"));
}
