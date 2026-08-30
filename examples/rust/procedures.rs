//! Procedure hooks for the keyvalue grammar, written in Rust.
//!
//! Each function fires after the corresponding variable is reduced. The
//! build helper compiles this file with rustc into a static archive and
//! links it into the parser shared library.
//!
//! Author-defined grammar hooks arrive namespaced as `hook_<name>` — the
//! grammar annotates Key with `@print`, and the entry point is
//! `hook_print`, so it can never collide with unrelated symbols.

use std::io::Write;

#[path = "../../bindings/rust/src/procedure.rs"]
mod procedure;
use procedure::ProcedureArguments;

/// Writes one hook note to stderr. Failures are ignored on purpose: a
/// closed stderr must not abort an otherwise healthy parse.
fn note(message: &str) {
    let mut stderr = std::io::stderr().lock();
    let _ = stderr.write_all(message.as_bytes());
}

fn note_node(label: &str, arguments: &ProcedureArguments) {
    if let Some(node) = arguments.current_node() {
        let _ = arguments.text(node);
        let _ = arguments.child_count(node);
    }
    note(label);
}

#[no_mangle]
pub extern "C" fn reduction(arguments: &mut ProcedureArguments) {
    note_node("[hook] reduction\n", arguments);
}

#[no_mangle]
pub extern "C" fn reduction_Document(arguments: &mut ProcedureArguments) {
    note_node("[hook] Document\n", arguments);
}

#[no_mangle]
pub extern "C" fn reduction_PairList(arguments: &mut ProcedureArguments) {
    note_node("[hook] PairList\n", arguments);
}

#[no_mangle]
pub extern "C" fn reduction_PairListTail(_arguments: &mut ProcedureArguments) {}

#[no_mangle]
pub extern "C" fn reduction_Pair(arguments: &mut ProcedureArguments) {
    note_node("[hook] Pair\n", arguments);
}

#[no_mangle]
pub extern "C" fn reduction_Key(arguments: &mut ProcedureArguments) {
    note_node("[hook] Key\n", arguments);
}

#[no_mangle]
pub extern "C" fn hook_print(arguments: &mut ProcedureArguments) {
    note_node("[hook] print (Key)\n", arguments);
}

#[no_mangle]
pub extern "C" fn reduction_KeyTail(_arguments: &mut ProcedureArguments) {}

#[no_mangle]
pub extern "C" fn reduction_Number(arguments: &mut ProcedureArguments) {
    note_node("[hook] Number\n", arguments);
}

#[no_mangle]
pub extern "C" fn reduction_NumberTail(_arguments: &mut ProcedureArguments) {}
