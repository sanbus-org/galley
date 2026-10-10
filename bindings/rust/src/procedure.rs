// Opaque `ProcedureArguments` handle for Rust procedure hooks.
//
// This is the single source of truth for hook-shim types. Hook crates never
// reference this file by path: `build_helper::generate_and_link` embeds it
// (via `include_str!`) and materializes it into the consumer build's
// `OUT_DIR`, which the hooks file opens with
// `include!(concat!(env!("OUT_DIR"), "/galley_procedure_types.rs"))`.
// (Plain `//` comments: this file is `include!`d inside a module, where
// inner `//!` docs are illegal.)
// Tree queries call the `galley_hook_*` door of the parse (`ProcedureArguments::door`) —
// unshared by construction. A hook is named by its session and the ticket the core
// issued for the call; the arguments are per-hook state, valid only while their hook
// runs, and the core refuses every call made with the ticket of a hook that has
// returned (`Error::StaleHook`).

use std::ffi::{c_char, c_void};

/// `GALLEY_INVALID_NODE`: no node at that position. Non-negative like every
/// address.
const INVALID_ADDRESS: u64 = i64::MAX as u64;

/// `GALLEY_NO_VARIABLE`: the core's answer for a node without a variable.
const NO_VARIABLE: i64 = i64::MAX;

/// Handle to a node of the current parse's AST: the core's parse generation
/// and the node's address. The generation comes from the node's source —
/// `galley_hook_generation` for the current node, the parent node's for
/// every link — and is what the session door later checks.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct NodeHandle {
    generation: u64,
    address: u64,
}

impl NodeHandle {
    /// Sentinel meaning "no node here". Every read through the door refuses it
    /// as a stale tree (generation 0 is never live); `set_current_node` takes
    /// it as "clear the current node".
    pub const INVALID: NodeHandle = NodeHandle {
        generation: 0,
        address: INVALID_ADDRESS,
    };
}

/// Parse/lookup failure modes mirroring the C API status codes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    NullArgument,
    Syntax,
    Semantic,
    Indentation,
    StackOverflow,
    AstCapacityExceeded,
    UnterminatedRawString,
    OutOfMemory,
    Internal,
    NoDiagnostic,
    InvalidNode,
    Io,
    SessionInUse,
    /// The node's generation is not the generation of the parse that owns the
    /// door: the node is of another parse, or `NodeHandle::INVALID` read
    /// through the door (`set_current_node` takes it as "clear").
    StaleTree,
    /// A call made with the arguments of a hook that has returned.
    StaleHook,
}

impl Error {
    fn from_status(status: i64) -> Self {
        match status {
            -1 => Error::NullArgument,
            -2 => Error::Syntax,
            -12 => Error::Semantic,
            -3 => Error::Indentation,
            -4 => Error::StackOverflow,
            -5 => Error::AstCapacityExceeded,
            -6 => Error::UnterminatedRawString,
            -7 => Error::OutOfMemory,
            -8 => Error::Internal,
            -9 => Error::NoDiagnostic,
            -10 => Error::InvalidNode,
            -11 => Error::Io,
            -13 => Error::SessionInUse,
            -14 => Error::StaleTree,
            -15 => Error::StaleHook,
            _ => Error::Internal,
        }
    }
}

fn map_status(status: i64) -> Result<(), Error> {
    if status == 0 {
        Ok(())
    } else {
        Err(Error::from_status(status))
    }
}

/// Per-hook arguments: the current node, the reducing rule, the scanner
/// position, drop and replace, and semantic errors. A hook receives the
/// session and the ticket of its call as two parameters (`extern "C" fn
/// hook(session: *mut c_void, hook: u64)`) and runs its body inside
/// [`ProcedureArguments::with`], which hands the arguments to a closure and
/// nothing else: the closure's return type cannot borrow from them, and they
/// have no public constructor, no `Clone` and no `Copy`, so neither they nor
/// the door and slices borrowed from them can leave the hook. The core also
/// refuses every call made with the ticket of a hook that has returned.
#[derive(Debug)]
pub struct ProcedureArguments {
    session: *mut c_void,
    hook: u64,
}

/// Opaque parse-time door over one parse's node storage: tree reads go
/// through the `galley_hook_*` twins on it. Only the pointer is ABI-stable.
#[repr(C)]
pub struct HookDoor {
    _private: [u8; 0],
}

#[derive(Clone, Copy, Debug)]
pub struct Rule {
    pub header: u16,
    pub right_hand_side_index: u16,
}

extern "C" {
    fn galley_procedure_door(session: *mut c_void, hook: u64, out_door: *mut *mut c_void) -> i64;
    fn galley_hook_generation(door: *mut c_void, out_generation: *mut u64) -> i64;
    fn galley_procedure_current_node(session: *mut c_void, hook: u64) -> i64;
    fn galley_procedure_set_current_node(
        session: *mut c_void,
        hook: u64,
        generation: u64,
        node: u64,
    ) -> i64;
    fn galley_procedure_rule_present(session: *mut c_void, hook: u64) -> i64;
    fn galley_procedure_rule_header(session: *mut c_void, hook: u64) -> i64;
    fn galley_procedure_rule_rhs_index(session: *mut c_void, hook: u64) -> i64;
    fn galley_procedure_context_line(session: *mut c_void, hook: u64) -> i64;
    fn galley_procedure_context_column(session: *mut c_void, hook: u64) -> i64;
    fn galley_procedure_drop_self(session: *mut c_void, hook: u64) -> i64;
    fn galley_procedure_drop_children(session: *mut c_void, hook: u64) -> i64;
    fn galley_procedure_drop_if_empty(session: *mut c_void, hook: u64) -> i64;
    fn galley_procedure_rule_right_hand_side(
        session: *mut c_void,
        hook: u64,
        out_data: *mut *const u16,
        out_length: *mut usize,
    ) -> i64;
    fn galley_procedure_rule_rhs_index_slice(
        session: *mut c_void,
        hook: u64,
        out_data: *mut *const u8,
        out_length: *mut usize,
    ) -> i64;
    fn galley_procedure_report_semantic_error(
        session: *mut c_void,
        hook: u64,
        message: *const c_char,
        message_len: usize,
    ) -> i64;
    fn galley_hook_node_text(
        door: *mut c_void,
        generation: u64,
        node: u64,
        out_data: *mut *const c_char,
        out_len: *mut usize,
    ) -> i64;
    fn galley_hook_node_child_count(door: *mut c_void, generation: u64, node: u64) -> i64;
    fn galley_hook_node_symbol_name(
        door: *mut c_void,
        generation: u64,
        node: u64,
        out_data: *mut *const c_char,
        out_len: *mut usize,
    ) -> i64;
    fn galley_hook_node_line_column(
        door: *mut c_void,
        generation: u64,
        node: u64,
        out_line: *mut u32,
        out_column: *mut u32,
    ) -> i64;
    fn galley_hook_node_parent(door: *mut c_void, generation: u64, node: u64) -> i64;
    fn galley_hook_node_first_child(door: *mut c_void, generation: u64, node: u64) -> i64;
    fn galley_hook_node_next_sibling(door: *mut c_void, generation: u64, node: u64) -> i64;
    fn galley_hook_node_last_child(door: *mut c_void, generation: u64, node: u64) -> i64;
    fn galley_hook_node_prior_sibling(door: *mut c_void, generation: u64, node: u64) -> i64;
    fn galley_hook_node_variable_index(door: *mut c_void, generation: u64, node: u64) -> i64;
    fn galley_hook_node_span(
        door: *mut c_void,
        generation: u64,
        node: u64,
        out_start: *mut u64,
        out_len: *mut u64,
    ) -> i64;
}

fn opt_handle(generation: u64, address: u64) -> Option<NodeHandle> {
    if address == NodeHandle::INVALID.address {
        None
    } else {
        Some(NodeHandle {
            generation,
            address,
        })
    }
}

fn value(status: i64) -> Result<u64, Error> {
    u64::try_from(status).map_err(|_| Error::from_status(status))
}

fn bytes<'a>(data: *const c_char, len: usize) -> &'a [u8] {
    if data.is_null() {
        return &[];
    }
    unsafe { std::slice::from_raw_parts(data.cast(), len) }
}

impl ProcedureArguments {
    /// Runs `body` with the arguments of the hook a hook function was called
    /// for. Nothing borrowed from the arguments (the door, the rule slices)
    /// can be returned from `body`.
    ///
    /// # Safety
    /// `session` and `hook` must be the two parameters the parser passed to
    /// the hook function, and this must run before that function returns.
    pub unsafe fn with<R>(
        session: *mut c_void,
        hook: u64,
        body: impl FnOnce(&mut ProcedureArguments) -> R,
    ) -> R {
        body(&mut ProcedureArguments { session, hook })
    }

    /// The door of the parse this hook belongs to: tree reads go through it.
    /// Borrowed from these arguments, so it cannot outlive the hook. The core
    /// refuses a hook that has returned with [`Error::StaleHook`].
    pub fn door(&self) -> Result<&HookDoor, Error> {
        let mut door: *mut c_void = std::ptr::null_mut();
        map_status(unsafe { galley_procedure_door(self.session, self.hook, &mut door) })?;
        Ok(unsafe { &*(door as *const HookDoor) })
    }

    /// The node being reduced, `None` when there is none. The core's refusal
    /// (a hook that has returned, a null door) is an error, never a handle
    /// stamped with generation 0.
    pub fn current_node(&self) -> Result<Option<NodeHandle>, Error> {
        let mut door: *mut c_void = std::ptr::null_mut();
        map_status(unsafe { galley_procedure_door(self.session, self.hook, &mut door) })?;
        let mut generation = 0u64;
        map_status(unsafe { galley_hook_generation(door, &mut generation) })?;
        let node = value(unsafe { galley_procedure_current_node(self.session, self.hook) })?;
        Ok(opt_handle(generation, node))
    }

    /// Sets the current node, or clears it with `None`. The core checks the
    /// handle: [`Error::StaleTree`] for a handle of another parse,
    /// [`Error::InvalidNode`] for an address outside this parse's storage; a
    /// refused call leaves the current node as it was.
    pub fn set_current_node(&mut self, node: Option<NodeHandle>) -> Result<(), Error> {
        let handle = node.unwrap_or(NodeHandle::INVALID);
        map_status(unsafe {
            galley_procedure_set_current_node(
                self.session,
                self.hook,
                handle.generation,
                handle.address,
            )
        })
    }

    pub fn drop_self(&mut self) -> Result<(), Error> {
        map_status(unsafe { galley_procedure_drop_self(self.session, self.hook) })
    }

    pub fn drop_children(&mut self) -> Result<(), Error> {
        map_status(unsafe { galley_procedure_drop_children(self.session, self.hook) })
    }

    pub fn drop_if_empty(&mut self) -> Result<(), Error> {
        map_status(unsafe { galley_procedure_drop_if_empty(self.session, self.hook) })
    }

    /// Records a semantic error on the current node and returns the running
    /// total. Parsing continues; a syntax-clean parse with any semantic
    /// error fails the parse with `Error::Semantic`.
    pub fn report_semantic_error(&mut self, message: &str) -> Result<usize, Error> {
        let status = unsafe {
            galley_procedure_report_semantic_error(
                self.session,
                self.hook,
                message.as_ptr().cast(),
                message.len(),
            )
        };
        if status < 0 {
            Err(Error::from_status(status))
        } else {
            Ok(status as usize)
        }
    }

    /// The reducing rule, `None` when the hook runs for none. A hook that has
    /// returned is [`Error::StaleHook`].
    pub fn rule(&self) -> Result<Option<Rule>, Error> {
        if value(unsafe { galley_procedure_rule_present(self.session, self.hook) })? != 1 {
            return Ok(None);
        }
        let header = value(unsafe { galley_procedure_rule_header(self.session, self.hook) })?;
        let right_hand_side_index =
            value(unsafe { galley_procedure_rule_rhs_index(self.session, self.hook) })?;
        match (u16::try_from(header), u16::try_from(right_hand_side_index)) {
            (Ok(header), Ok(right_hand_side_index)) => Ok(Some(Rule {
                header,
                right_hand_side_index,
            })),
            _ => Ok(None),
        }
    }

    /// The scanner line, or the core's refusal.
    pub fn current_line(&self) -> Result<u32, Error> {
        Ok(value(unsafe { galley_procedure_context_line(self.session, self.hook) })? as u32)
    }

    /// The scanner column, or the core's refusal.
    pub fn current_column(&self) -> Result<u32, Error> {
        Ok(value(unsafe { galley_procedure_context_column(self.session, self.hook) })? as u32)
    }

    /// The rule's right-hand-side symbol indexes (static grammar storage),
    /// `None` when the hook has no rule.
    pub fn rule_right_hand_side(&self) -> Result<Option<&[u16]>, Error> {
        let mut data: *const u16 = std::ptr::null();
        let mut len = 0usize;
        match unsafe {
            galley_procedure_rule_right_hand_side(self.session, self.hook, &mut data, &mut len)
        } {
            0 if !data.is_null() => Ok(Some(unsafe { std::slice::from_raw_parts(data, len) })),
            0 | -10 => Ok(None),
            status => Err(Error::from_status(status)),
        }
    }

    /// The rule's right-hand-side index text (static grammar storage), `None`
    /// when the hook has no rule.
    pub fn rule_rhs_index_slice(&self) -> Result<Option<&[u8]>, Error> {
        let mut data: *const u8 = std::ptr::null();
        let mut len = 0usize;
        match unsafe {
            galley_procedure_rule_rhs_index_slice(self.session, self.hook, &mut data, &mut len)
        } {
            0 if !data.is_null() => Ok(Some(unsafe { std::slice::from_raw_parts(data, len) })),
            0 | -10 => Ok(None),
            status => Err(Error::from_status(status)),
        }
    }
}

impl HookDoor {
    fn as_ptr(&self) -> *mut c_void {
        self as *const _ as *mut c_void
    }

    /// One link, stamped with the generation of `node`; the core refuses a
    /// generation that is not this parse's with [`Error::StaleTree`].
    fn link(
        &self,
        read: unsafe extern "C" fn(*mut c_void, u64, u64) -> i64,
        node: NodeHandle,
    ) -> Result<Option<NodeHandle>, Error> {
        let address = value(unsafe { read(self.as_ptr(), node.generation, node.address) })?;
        Ok(opt_handle(node.generation, address))
    }

    /// Direct child count of `node`.
    pub fn child_count(&self, node: NodeHandle) -> Result<u32, Error> {
        Ok(value(unsafe {
            galley_hook_node_child_count(self.as_ptr(), node.generation, node.address)
        })? as u32)
    }

    pub fn parent(&self, node: NodeHandle) -> Result<Option<NodeHandle>, Error> {
        self.link(galley_hook_node_parent, node)
    }

    pub fn first_child(&self, node: NodeHandle) -> Result<Option<NodeHandle>, Error> {
        self.link(galley_hook_node_first_child, node)
    }

    pub fn last_child(&self, node: NodeHandle) -> Result<Option<NodeHandle>, Error> {
        self.link(galley_hook_node_last_child, node)
    }

    pub fn next_sibling(&self, node: NodeHandle) -> Result<Option<NodeHandle>, Error> {
        self.link(galley_hook_node_next_sibling, node)
    }

    pub fn prior_sibling(&self, node: NodeHandle) -> Result<Option<NodeHandle>, Error> {
        self.link(galley_hook_node_prior_sibling, node)
    }

    /// The children of `node`, first to last; a refusal ends the iteration
    /// after yielding it.
    pub fn children(
        &self,
        node: NodeHandle,
    ) -> impl Iterator<Item = Result<NodeHandle, Error>> + '_ {
        let mut next = self.first_child(node).transpose();
        std::iter::from_fn(move || {
            let current = next.take()?;
            if let Ok(handle) = current {
                next = self.next_sibling(handle).transpose();
            }
            Some(current)
        })
    }

    pub fn text(&self, node: NodeHandle) -> Result<&[u8], Error> {
        let mut data: *const c_char = std::ptr::null();
        let mut len = 0usize;
        map_status(unsafe {
            galley_hook_node_text(
                self.as_ptr(),
                node.generation,
                node.address,
                &mut data,
                &mut len,
            )
        })?;
        Ok(bytes(data, len))
    }

    pub fn symbol_name(&self, node: NodeHandle) -> Result<&[u8], Error> {
        let mut data: *const c_char = std::ptr::null();
        let mut len = 0usize;
        map_status(unsafe {
            galley_hook_node_symbol_name(
                self.as_ptr(),
                node.generation,
                node.address,
                &mut data,
                &mut len,
            )
        })?;
        Ok(bytes(data, len))
    }

    pub fn span(&self, node: NodeHandle) -> Result<(u64, u64), Error> {
        let mut start = 0u64;
        let mut len = 0u64;
        map_status(unsafe {
            galley_hook_node_span(
                self.as_ptr(),
                node.generation,
                node.address,
                &mut start,
                &mut len,
            )
        })?;
        Ok((start, len))
    }

    pub fn line_column(&self, node: NodeHandle) -> Result<(u32, u32), Error> {
        let mut line = 0u32;
        let mut column = 0u32;
        map_status(unsafe {
            galley_hook_node_line_column(
                self.as_ptr(),
                node.generation,
                node.address,
                &mut line,
                &mut column,
            )
        })?;
        Ok((line, column))
    }

    /// Raw variable index of `node`, or `None` when it has no variable.
    pub fn variable_index(&self, node: NodeHandle) -> Result<Option<u16>, Error> {
        let index = value(unsafe {
            galley_hook_node_variable_index(self.as_ptr(), node.generation, node.address)
        })?;
        Ok(if index == NO_VARIABLE as u64 {
            None
        } else {
            u16::try_from(index).ok()
        })
    }
}
