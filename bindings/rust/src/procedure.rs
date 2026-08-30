//! Opaque `ProcedureArguments` handle for Rust procedure hooks.
//!
//! Hook crates include this file with `#[path]` (they cannot depend on
//! `galley_bindings` without a build cycle). Tree queries call
//! `galley_node_*` on the session from `galley_procedure_session`.

use std::ffi::{c_char, c_void};

/// Stable handle to a node in the current parse's AST.
#[repr(transparent)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct NodeHandle(pub u64);

impl NodeHandle {
    /// Sentinel meaning "no node here".
    pub const INVALID: NodeHandle = NodeHandle(u64::MAX);
}

/// Parse/lookup failure modes mirroring the C API status codes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    NullArgument,
    Syntax,
    Indentation,
    StackOverflow,
    AstCapacityExceeded,
    UnterminatedRawString,
    OutOfMemory,
    Internal,
    NoDiagnostic,
    InvalidNode,
    Io,
}

impl Error {
    fn from_status(status: i64) -> Self {
        match status {
            -1 => Error::NullArgument,
            -2 => Error::Syntax,
            -3 => Error::Indentation,
            -4 => Error::StackOverflow,
            -5 => Error::AstCapacityExceeded,
            -6 => Error::UnterminatedRawString,
            -7 => Error::OutOfMemory,
            -8 => Error::Internal,
            -9 => Error::NoDiagnostic,
            -10 => Error::InvalidNode,
            -11 => Error::Io,
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

enum GalleySessionRaw {}

/// Opaque procedure-hook argument. Only the pointer is ABI-stable.
#[repr(C)]
pub struct ProcedureArguments {
    _private: [u8; 0],
}

#[derive(Clone, Copy, Debug)]
pub struct Rule {
    pub header: u16,
    pub right_hand_side_index: u16,
}

extern "C" {
    fn galley_procedure_session(arguments: *mut c_void) -> *mut GalleySessionRaw;
    fn galley_procedure_current_node(arguments: *mut c_void) -> u64;
    fn galley_procedure_set_current_node(arguments: *mut c_void, node: u64);
    fn galley_procedure_rule_present(arguments: *mut c_void) -> i32;
    fn galley_procedure_rule_header(arguments: *mut c_void) -> i64;
    fn galley_procedure_rule_rhs_index(arguments: *mut c_void) -> i64;
    fn galley_procedure_context_line(arguments: *mut c_void) -> u32;
    fn galley_procedure_context_column(arguments: *mut c_void) -> u32;
    fn galley_procedure_drop_self(arguments: *mut c_void) -> i64;
    fn galley_procedure_drop_children(arguments: *mut c_void) -> i64;
    fn galley_procedure_drop_if_empty(arguments: *mut c_void) -> i64;
    fn galley_procedure_replace_with_children(arguments: *mut c_void) -> i64;
    fn galley_procedure_left_recursive_reduction(arguments: *mut c_void) -> i64;
    fn galley_procedure_right_recursive_reduction(arguments: *mut c_void) -> i64;
    fn galley_procedure_rule_right_hand_side(
        arguments: *mut c_void,
        out_data: *mut *const u16,
        out_length: *mut usize,
    ) -> i64;
    fn galley_procedure_rule_rhs_index_slice(
        arguments: *mut c_void,
        out_data: *mut *const u8,
        out_length: *mut usize,
    ) -> i64;
    fn galley_node_text(
        session: *mut GalleySessionRaw,
        node: u64,
        out_data: *mut *const c_char,
        out_len: *mut usize,
    ) -> i64;
    fn galley_node_child_count(session: *mut GalleySessionRaw, node: u64) -> u32;
    fn galley_node_symbol_name(
        session: *mut GalleySessionRaw,
        node: u64,
        out_data: *mut *const c_char,
        out_len: *mut usize,
    ) -> i64;
    fn galley_node_line_column(
        session: *mut GalleySessionRaw,
        node: u64,
        out_line: *mut u32,
        out_column: *mut u32,
    ) -> i64;
    fn galley_node_parent(session: *mut GalleySessionRaw, node: u64) -> u64;
    fn galley_node_first_child(session: *mut GalleySessionRaw, node: u64) -> u64;
    fn galley_node_next_sibling(session: *mut GalleySessionRaw, node: u64) -> u64;
    fn galley_node_last_child(session: *mut GalleySessionRaw, node: u64) -> u64;
    fn galley_node_prior_sibling(session: *mut GalleySessionRaw, node: u64) -> u64;
    fn galley_node_variable_index(session: *mut GalleySessionRaw, node: u64) -> i64;
    fn galley_node_span(
        session: *mut GalleySessionRaw,
        node: u64,
        out_start: *mut u64,
        out_len: *mut u64,
    ) -> i64;
}

fn opt_handle(value: u64) -> Option<NodeHandle> {
    if value == NodeHandle::INVALID.0 {
        None
    } else {
        Some(NodeHandle(value))
    }
}

fn bytes<'a>(data: *const c_char, len: usize) -> &'a [u8] {
    if data.is_null() {
        return &[];
    }
    unsafe { std::slice::from_raw_parts(data.cast(), len) }
}

impl ProcedureArguments {
    fn as_ptr(&self) -> *mut c_void {
        self as *const _ as *mut c_void
    }

    fn session_ptr(&self) -> Option<*mut GalleySessionRaw> {
        let ptr = unsafe { galley_procedure_session(self.as_ptr()) };
        if ptr.is_null() {
            None
        } else {
            Some(ptr)
        }
    }

    pub fn current_node(&self) -> Option<NodeHandle> {
        opt_handle(unsafe { galley_procedure_current_node(self.as_ptr()) })
    }

    /// Sets the current node, or clears it with `None`.
    ///
    /// # Safety
    ///
    /// `node` must be `None` or a live handle from this parse. Tree helpers
    /// index the allocator with it and do not bounds-check.
    pub unsafe fn set_current_node(&mut self, node: Option<NodeHandle>) {
        let handle = node.unwrap_or(NodeHandle::INVALID);
        unsafe { galley_procedure_set_current_node(self.as_ptr(), handle.0) }
    }

    pub fn drop_self(&mut self) -> Result<(), Error> {
        map_status(unsafe { galley_procedure_drop_self(self.as_ptr()) })
    }

    pub fn drop_children(&mut self) -> Result<(), Error> {
        map_status(unsafe { galley_procedure_drop_children(self.as_ptr()) })
    }

    pub fn drop_if_empty(&mut self) -> Result<(), Error> {
        map_status(unsafe { galley_procedure_drop_if_empty(self.as_ptr()) })
    }

    pub fn replace_with_children(&mut self) -> Result<(), Error> {
        map_status(unsafe { galley_procedure_replace_with_children(self.as_ptr()) })
    }

    pub fn left_recursive_reduction(&mut self) -> Result<(), Error> {
        map_status(unsafe { galley_procedure_left_recursive_reduction(self.as_ptr()) })
    }

    pub fn right_recursive_reduction(&mut self) -> Result<(), Error> {
        map_status(unsafe { galley_procedure_right_recursive_reduction(self.as_ptr()) })
    }

    pub fn rule(&self) -> Option<Rule> {
        let present = unsafe { galley_procedure_rule_present(self.as_ptr()) };
        if present == 0 {
            return None;
        }
        let header = unsafe { galley_procedure_rule_header(self.as_ptr()) };
        let right_hand_side_index = unsafe { galley_procedure_rule_rhs_index(self.as_ptr()) };
        if !(0..=u16::MAX as i64).contains(&header)
            || !(0..=u16::MAX as i64).contains(&right_hand_side_index)
        {
            return None;
        }
        Some(Rule {
            header: header as u16,
            right_hand_side_index: right_hand_side_index as u16,
        })
    }

    pub fn current_line(&self) -> u32 {
        unsafe { galley_procedure_context_line(self.as_ptr()) }
    }

    pub fn current_column(&self) -> u32 {
        unsafe { galley_procedure_context_column(self.as_ptr()) }
    }

    pub fn rule_right_hand_side(&self) -> Option<&[u16]> {
        let mut data: *const u16 = std::ptr::null();
        let mut len = 0usize;
        let status =
            unsafe { galley_procedure_rule_right_hand_side(self.as_ptr(), &mut data, &mut len) };
        if status != 0 || data.is_null() {
            None
        } else {
            Some(unsafe { std::slice::from_raw_parts(data, len) })
        }
    }

    pub fn rule_rhs_index_slice(&self) -> Option<&[u8]> {
        let mut data: *const u8 = std::ptr::null();
        let mut len = 0usize;
        let status =
            unsafe { galley_procedure_rule_rhs_index_slice(self.as_ptr(), &mut data, &mut len) };
        if status != 0 || data.is_null() {
            None
        } else {
            Some(unsafe { std::slice::from_raw_parts(data, len) })
        }
    }

    pub fn child_count(&self, node: NodeHandle) -> u32 {
        let Some(session) = self.session_ptr() else {
            return 0;
        };
        unsafe { galley_node_child_count(session, node.0) }
    }

    pub fn parent(&self, node: NodeHandle) -> Option<NodeHandle> {
        let session = self.session_ptr()?;
        opt_handle(unsafe { galley_node_parent(session, node.0) })
    }

    pub fn first_child(&self, node: NodeHandle) -> Option<NodeHandle> {
        let session = self.session_ptr()?;
        opt_handle(unsafe { galley_node_first_child(session, node.0) })
    }

    pub fn last_child(&self, node: NodeHandle) -> Option<NodeHandle> {
        let session = self.session_ptr()?;
        opt_handle(unsafe { galley_node_last_child(session, node.0) })
    }

    pub fn next_sibling(&self, node: NodeHandle) -> Option<NodeHandle> {
        let session = self.session_ptr()?;
        opt_handle(unsafe { galley_node_next_sibling(session, node.0) })
    }

    pub fn prior_sibling(&self, node: NodeHandle) -> Option<NodeHandle> {
        let session = self.session_ptr()?;
        opt_handle(unsafe { galley_node_prior_sibling(session, node.0) })
    }

    pub fn children(&self, node: NodeHandle) -> impl Iterator<Item = NodeHandle> + '_ {
        let mut next = self.first_child(node);
        std::iter::from_fn(move || {
            let current = next?;
            next = self.next_sibling(current);
            Some(current)
        })
    }

    pub fn text(&self, node: NodeHandle) -> Option<&[u8]> {
        let session = self.session_ptr()?;
        let mut data: *const c_char = std::ptr::null();
        let mut len = 0usize;
        if unsafe { galley_node_text(session, node.0, &mut data, &mut len) } != 0 {
            return None;
        }
        Some(bytes(data, len))
    }

    pub fn symbol_name(&self, node: NodeHandle) -> Option<&[u8]> {
        let session = self.session_ptr()?;
        let mut data: *const c_char = std::ptr::null();
        let mut len = 0usize;
        if unsafe { galley_node_symbol_name(session, node.0, &mut data, &mut len) } != 0 {
            return None;
        }
        Some(bytes(data, len))
    }

    pub fn span(&self, node: NodeHandle) -> Option<(u64, u64)> {
        let session = self.session_ptr()?;
        let mut start = 0u64;
        let mut len = 0u64;
        if unsafe { galley_node_span(session, node.0, &mut start, &mut len) } != 0 {
            return None;
        }
        Some((start, len))
    }

    pub fn line_column(&self, node: NodeHandle) -> Option<(u32, u32)> {
        let session = self.session_ptr()?;
        let mut line = 0u32;
        let mut column = 0u32;
        if unsafe { galley_node_line_column(session, node.0, &mut line, &mut column) } != 0 {
            return None;
        }
        Some((line, column))
    }

    pub fn variable_index(&self, node: NodeHandle) -> Option<u16> {
        let session = self.session_ptr()?;
        let value = unsafe { galley_node_variable_index(session, node.0) };
        if value < 0 {
            None
        } else {
            u16::try_from(value).ok()
        }
    }
}
