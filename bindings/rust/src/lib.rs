#![allow(dead_code)]

//! Safe Rust bindings for Galley-generated parsers.
//!
//! Built on the C ABI (`bindings/c/capi.zig` / `galley.h`). Consumers call
//! [`build_helper::generate_and_link`] from their `build.rs` with a language
//! directory, then use [`Session`] to parse and inspect documents.
//!
//! Sessions are not thread-safe: use one per thread or guard externally.
//! Node handles, text slices, and diagnostics remain valid until the next
//! parse on the same session or session destruction; the borrow checker
//! enforces this.

// Every extern declaration exists for consumer code paths, even when a
// particular binary only exercises a subset.
#![allow(dead_code)]

pub mod build_helper;

use std::ffi::c_char;
use std::marker::PhantomData;
use std::path::Path;

/// Opaque session handle; never constructed in Rust.
enum GalleySessionRaw {}

extern "C" {
    fn galley_version() -> *const c_char;
    fn galley_session_create() -> *mut GalleySessionRaw;
    fn galley_session_create_ex(options: *const RawOptions) -> *mut GalleySessionRaw;
    fn galley_session_destroy(session: *mut GalleySessionRaw);
    fn galley_parse_sentinel(session: *mut GalleySessionRaw, input: *const c_char) -> i64;
    fn galley_parse(session: *mut GalleySessionRaw, data: *const c_char, len: usize) -> i64;
    fn galley_parse_file(session: *mut GalleySessionRaw, path: *const c_char) -> i64;
    fn galley_node_count(session: *mut GalleySessionRaw) -> u64;
    fn galley_root_node(session: *mut GalleySessionRaw) -> u64;
    fn galley_has_ast() -> i32;
    fn galley_node_is_valid(session: *mut GalleySessionRaw, node: u64) -> i32;
    fn galley_node_child_count(session: *mut GalleySessionRaw, node: u64) -> u32;
    fn galley_node_first_child(session: *mut GalleySessionRaw, node: u64) -> u64;
    fn galley_node_last_child(session: *mut GalleySessionRaw, node: u64) -> u64;
    fn galley_node_next_sibling(session: *mut GalleySessionRaw, node: u64) -> u64;
    fn galley_node_prior_sibling(session: *mut GalleySessionRaw, node: u64) -> u64;
    fn galley_node_parent(session: *mut GalleySessionRaw, node: u64) -> u64;
    fn galley_node_symbol_name(
        session: *mut GalleySessionRaw,
        node: u64,
        out_data: *mut *const c_char,
        out_len: *mut usize,
    ) -> i64;
    fn galley_node_text(
        session: *mut GalleySessionRaw,
        node: u64,
        out_data: *mut *const c_char,
        out_len: *mut usize,
    ) -> i64;
    fn galley_node_span(
        session: *mut GalleySessionRaw,
        node: u64,
        out_start: *mut u64,
        out_len: *mut u64,
    ) -> i64;
    fn galley_node_line_column(
        session: *mut GalleySessionRaw,
        node: u64,
        out_line: *mut u32,
        out_column: *mut u32,
    ) -> i64;
    fn galley_last_position(
        session: *mut GalleySessionRaw,
        out_line: *mut u32,
        out_column: *mut u32,
    ) -> i64;
    fn galley_has_diagnostic(session: *mut GalleySessionRaw) -> i32;
    fn galley_diagnostic_kind(session: *mut GalleySessionRaw) -> i64;
    fn galley_diagnostic_message(session: *mut GalleySessionRaw, out: *mut *const c_char) -> i64;
    fn galley_diagnostic_position(
        session: *mut GalleySessionRaw,
        out_line: *mut u32,
        out_column: *mut u32,
    ) -> i64;
    fn galley_diagnostic_unexpected_token(
        session: *mut GalleySessionRaw,
        out_data: *mut *const c_char,
        out_len: *mut usize,
    ) -> i64;
    fn galley_diagnostic_expected_count(session: *mut GalleySessionRaw) -> i64;
    fn galley_diagnostic_expected_at(
        session: *mut GalleySessionRaw,
        index: u64,
        out_data: *mut *const c_char,
        out_len: *mut usize,
    ) -> i64;
    fn galley_diagnostic_context_count(session: *mut GalleySessionRaw) -> i64;
    fn galley_diagnostic_context_at(
        session: *mut GalleySessionRaw,
        index: u64,
        out_data: *mut *const c_char,
        out_len: *mut usize,
    ) -> i64;
    fn galley_diagnostic_indentation(
        session: *mut GalleySessionRaw,
        out_spaces: *mut u32,
        out_width: *mut u32,
    ) -> i64;
    fn galley_recorded_diagnostic_count(session: *mut GalleySessionRaw) -> i64;
    fn galley_recorded_diagnostic_message(
        session: *mut GalleySessionRaw,
        diag_index: u64,
        out: *mut *const c_char,
    ) -> i64;
    fn galley_recorded_diagnostic_kind(session: *mut GalleySessionRaw, diag_index: u64) -> i64;
    fn galley_recorded_diagnostic_position(
        session: *mut GalleySessionRaw,
        diag_index: u64,
        out_line: *mut u32,
        out_column: *mut u32,
    ) -> i64;
    fn galley_recorded_unexpected_token(
        session: *mut GalleySessionRaw,
        diag_index: u64,
        out_data: *mut *const c_char,
        out_len: *mut usize,
    ) -> i64;
    fn galley_recorded_expected_count(session: *mut GalleySessionRaw, diag_index: u64) -> i64;
    fn galley_recorded_expected_token(
        session: *mut GalleySessionRaw,
        diag_index: u64,
        token_index: u64,
        out_data: *mut *const c_char,
        out_len: *mut usize,
    ) -> i64;
    fn galley_recorded_context_count(session: *mut GalleySessionRaw, diag_index: u64) -> i64;
    fn galley_recorded_context_name(
        session: *mut GalleySessionRaw,
        diag_index: u64,
        context_index: u64,
        out_data: *mut *const c_char,
        out_len: *mut usize,
    ) -> i64;
    fn galley_recorded_indentation(
        session: *mut GalleySessionRaw,
        diag_index: u64,
        out_spaces: *mut u32,
        out_width: *mut u32,
    ) -> i64;
    fn galley_status_string(status: i64) -> *const c_char;
}

#[repr(C)]
struct RawOptions {
    max_errors: i32,
    recovery_window: i32,
    stack_overflow_recovery: i32,
    syntax_error_stack_depth: u32,
    verbosity: i32,
    ast_preallocation_ratio: f64,
    ast_preallocation_cap: u64,
}

/// Runtime options for [`Session::with_options`]. Zero/negative fields select
/// library defaults.
#[derive(Debug, Clone, Copy)]
pub struct SessionOptions {
    pub max_errors: i32,
    pub recovery_window: i32,
    pub stack_overflow_recovery: bool,
    pub syntax_error_stack_depth: u32,
}

impl Default for SessionOptions {
    fn default() -> Self {
        SessionOptions {
            max_errors: 10,
            recovery_window: 500,
            stack_overflow_recovery: false,
            syntax_error_stack_depth: 0,
        }
    }
}

/// Parse/lookup failure modes mirroring the status codes of the C API.
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

    fn status(&self) -> i64 {
        match self {
            Error::NullArgument => -1,
            Error::Syntax => -2,
            Error::Indentation => -3,
            Error::StackOverflow => -4,
            Error::AstCapacityExceeded => -5,
            Error::UnterminatedRawString => -6,
            Error::OutOfMemory => -7,
            Error::Internal => -8,
            Error::NoDiagnostic => -9,
            Error::InvalidNode => -10,
            Error::Io => -11,
        }
    }

    /// Static description of this error, straight from the library.
    pub fn description(&self) -> &'static str {
        unsafe { cstr(galley_status_string(self.status())).unwrap_or("unknown error") }
    }
}

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.description())
    }
}

impl std::error::Error for Error {}

unsafe fn cstr(ptr: *const c_char) -> Option<&'static str> {
    if ptr.is_null() {
        return None;
    }
    let mut len = 0usize;
    while *ptr.add(len) != 0 {
        len += 1;
    }
    Some(std::str::from_utf8_unchecked(std::slice::from_raw_parts(
        ptr.cast(),
        len,
    )))
}

fn bytes<'a>(data: *const c_char, len: usize) -> &'a [u8] {
    if data.is_null() {
        return &[];
    }
    unsafe { std::slice::from_raw_parts(data.cast(), len) }
}

/// Version string reported by the library.
pub fn version() -> &'static str {
    unsafe { cstr(galley_version()).unwrap_or("") }
}

/// Whether the linked parser was built with AST construction. When false,
/// all node and tree-editing methods return `None` / errors.
pub fn has_ast() -> bool {
    unsafe { galley_has_ast() != 0 }
}

/// Stable handle to a node in the most recent parse's AST.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct NodeHandle(u64);

impl NodeHandle {
    /// Sentinel meaning "no node here".
    pub const INVALID: NodeHandle = NodeHandle(u64::MAX);
}

/// A parsing session. Not thread-safe; not cloneable.
///
/// Results borrow from the session: they stay valid until the next parse or
/// drop, which the lifetimes on accessor methods express.
pub struct Session {
    inner: *mut GalleySessionRaw,
    /// The session owns OS threads and is not safe to move across them.
    _not_send: PhantomData<*const ()>,
}

unsafe impl Send for Session {}

/// Summary of one successful parse.
#[derive(Debug)]
pub struct ParseInfo {
    pub root: Option<NodeHandle>,
    /// End position when the parser was built with position tracking.
    pub end_position: Option<(u32, u32)>,
}

/// Structured diagnostic captured after a failed parse. Owned copy.
#[derive(Debug, Default)]
pub struct Diagnostic {
    pub kind: DiagnosticKind,
    pub line: u32,
    pub column: u32,
    pub message: String,
    pub unexpected_token: Vec<u8>,
    pub expected_tokens: Vec<Vec<u8>>,
    /// Innermost-first "while parsing" chain (syntax only).
    pub context: Vec<String>,
    /// Indentation diagnostics only.
    pub indentation: Option<IndentationInfo>,
}

#[derive(Debug, Default, PartialEq, Eq)]
pub enum DiagnosticKind {
    #[default]
    None,
    Syntax,
    Indentation,
}

#[derive(Debug)]
pub struct IndentationInfo {
    pub spaces: u32,
    pub indentation_width: u32,
}

impl Session {
    /// Creates a session with default options.
    pub fn new() -> Result<Self, Error> {
        Self::with_options(SessionOptions::default())
    }

    /// Creates a session with explicit runtime options.
    pub fn with_options(options: SessionOptions) -> Result<Self, Error> {
        let raw = RawOptions {
            max_errors: options.max_errors,
            recovery_window: options.recovery_window,
            stack_overflow_recovery: options.stack_overflow_recovery as i32,
            syntax_error_stack_depth: options.syntax_error_stack_depth,
            verbosity: 0,
            ast_preallocation_ratio: -1.0,
            ast_preallocation_cap: 0,
        };
        let inner = unsafe { galley_session_create_ex(&raw) };
        if inner.is_null() {
            return Err(Error::OutOfMemory);
        }
        Ok(Session {
            inner,
            _not_send: PhantomData,
        })
    }

    fn status_to_result(&self, status: i64) -> Result<usize, Error> {
        usize::try_from(status).map_err(|_| Error::from_status(status))
    }

    /// Parses a byte buffer that may contain NUL bytes.
    pub fn parse(&mut self, input: &[u8]) -> Result<usize, Error> {
        self.status_to_result(unsafe {
            galley_parse(self.inner, input.as_ptr().cast(), input.len())
        })
    }

    /// Parses a NUL-terminated string.
    pub fn parse_sentinel(&mut self, input: &str) -> Result<usize, Error> {
        let c_input = std::ffi::CString::new(input).map_err(|_| Error::NullArgument)?;
        self.status_to_result(unsafe { galley_parse_sentinel(self.inner, c_input.as_ptr()) })
    }

    /// Parses the file at `path`.
    pub fn parse_file(&mut self, path: impl AsRef<Path>) -> Result<usize, Error> {
        let c_path = std::ffi::CString::new(path.as_ref().as_os_str().as_encoded_bytes())
            .map_err(|_| Error::NullArgument)?;
        self.status_to_result(unsafe { galley_parse_file(self.inner, c_path.as_ptr()) })
    }

    /// Summary of the most recent successful parse, when AST construction is
    /// enabled.
    pub fn info(&self) -> Option<ParseInfo> {
        if !has_ast() {
            return None;
        }
        let mut line = 0u32;
        let mut column = 0u32;
        unsafe { galley_last_position(self.inner, &mut line, &mut column) };
        Some(ParseInfo {
            root: self.root_node(),
            end_position: Some((line, column)),
        })
    }

    /// Number of AST nodes in the last successful parse (0 without AST).
    pub fn node_count(&self) -> u64 {
        unsafe { galley_node_count(self.inner) }
    }

    fn raw_link(&self, f: impl FnOnce(*mut GalleySessionRaw) -> u64) -> Option<NodeHandle> {
        opt_handle(f(self.inner))
    }

    /// Root node of the last successful parse.
    pub fn root_node(&self) -> Option<NodeHandle> {
        if !has_ast() {
            return None;
        }
        self.raw_link(|s| unsafe { galley_root_node(s) })
    }

    /// Whether `node` refers to a live node of the last parse.
    pub fn node_is_valid(&self, node: NodeHandle) -> bool {
        unsafe { galley_node_is_valid(self.inner, node.0) != 0 }
    }

    /// Direct child count of `node`.
    pub fn child_count(&self, node: NodeHandle) -> u32 {
        unsafe { galley_node_child_count(self.inner, node.0) }
    }

    pub fn first_child(&self, node: NodeHandle) -> Option<NodeHandle> {
        self.raw_link(|s| unsafe { galley_node_first_child(s, node.0) })
    }
    pub fn last_child(&self, node: NodeHandle) -> Option<NodeHandle> {
        self.raw_link(|s| unsafe { galley_node_last_child(s, node.0) })
    }
    pub fn next_sibling(&self, node: NodeHandle) -> Option<NodeHandle> {
        self.raw_link(|s| unsafe { galley_node_next_sibling(s, node.0) })
    }
    pub fn prior_sibling(&self, node: NodeHandle) -> Option<NodeHandle> {
        self.raw_link(|s| unsafe { galley_node_prior_sibling(s, node.0) })
    }
    pub fn parent(&self, node: NodeHandle) -> Option<NodeHandle> {
        self.raw_link(|s| unsafe { galley_node_parent(s, node.0) })
    }

    /// Children of `node`, first to last.
    pub fn children(&self, node: NodeHandle) -> impl Iterator<Item = NodeHandle> + '_ {
        let mut next = self.first_child(node);
        std::iter::from_fn(move || {
            let current = next?;
            next = self.next_sibling(current);
            Some(current)
        })
    }

    /// Grammar symbol name of `node` (e.g. `"ObjectMembers"`), or `None`
    /// when the node has no symbol.
    pub fn symbol_name<'a>(&'a self, node: NodeHandle) -> Option<&'a [u8]> {
        unsafe {
            let mut data: *const c_char = std::ptr::null();
            let mut len = 0usize;
            if galley_node_symbol_name(self.inner, node.0, &mut data, &mut len) != 0 {
                return None;
            }
            Some(bytes(data, len))
        }
    }

    /// Source text matched by `node`; borrows the session's retained input.
    pub fn text<'a>(&'a self, node: NodeHandle) -> Option<&'a [u8]> {
        unsafe {
            let mut data: *const c_char = std::ptr::null();
            let mut len = 0usize;
            if galley_node_text(self.inner, node.0, &mut data, &mut len) != 0 {
                return None;
            }
            Some(bytes(data, len))
        }
    }

    /// Byte span (offset into the parse input, length) of `node`.
    pub fn span(&self, node: NodeHandle) -> Option<(u64, u64)> {
        unsafe {
            let mut start = 0u64;
            let mut len = 0u64;
            if galley_node_span(self.inner, node.0, &mut start, &mut len) != 0 {
                return None;
            }
            Some((start, len))
        }
    }

    /// 1-based line/column of `node`'s first byte.
    pub fn line_column(&self, node: NodeHandle) -> Option<(u32, u32)> {
        unsafe {
            let mut l = 0u32;
            let mut c = 0u32;
            if galley_node_line_column(self.inner, node.0, &mut l, &mut c) != 0 {
                return None;
            }
            Some((l, c))
        }
    }

    /// Builds an owned snapshot of the diagnostic recorded at `diag_index`
    /// (0-based, in recording order) of the most recent parse. The message
    /// always uses the built-in generic renderer.
    fn recorded_diagnostic_at(&self, diag_index: u64) -> Option<Diagnostic> {
        let mut d = Diagnostic::default();
        unsafe {
            if galley_recorded_diagnostic_position(
                self.inner,
                diag_index,
                &mut d.line,
                &mut d.column,
            ) != 0
            {
                return None;
            }

            d.kind = match galley_recorded_diagnostic_kind(self.inner, diag_index) {
                1 => DiagnosticKind::Syntax,
                2 => DiagnosticKind::Indentation,
                _ => DiagnosticKind::None,
            };

            let mut msg: *const c_char = std::ptr::null();
            if galley_recorded_diagnostic_message(self.inner, diag_index, &mut msg) == 0 {
                d.message = cstr(msg).unwrap_or("").to_owned();
            }

            let mut tok: *const c_char = std::ptr::null();
            let mut tl = 0usize;
            if galley_recorded_unexpected_token(self.inner, diag_index, &mut tok, &mut tl) == 0 {
                d.unexpected_token = bytes(tok, tl).to_vec();
            }

            for i in 0..galley_recorded_expected_count(self.inner, diag_index).max(0) as u64 {
                let mut td: *const c_char = std::ptr::null();
                let mut tdl = 0usize;
                if galley_recorded_expected_token(self.inner, diag_index, i, &mut td, &mut tdl) == 0
                {
                    d.expected_tokens.push(bytes(td, tdl).to_vec());
                }
            }

            for i in 0..galley_recorded_context_count(self.inner, diag_index).max(0) as u64 {
                let mut cd: *const c_char = std::ptr::null();
                let mut cdl = 0usize;
                if galley_recorded_context_name(self.inner, diag_index, i, &mut cd, &mut cdl) == 0 {
                    d.context.push(cstr(cd).unwrap_or("").to_owned());
                }
            }

            let mut sp = 0u32;
            let mut iw = 0u32;
            if galley_recorded_indentation(self.inner, diag_index, &mut sp, &mut iw) == 0 {
                d.indentation = Some(IndentationInfo {
                    spaces: sp,
                    indentation_width: iw,
                });
            }
        }
        Some(d)
    }

    /// Structured diagnostics of the failed parse, in recording order. Owned
    /// copies; empty when the parse succeeded.
    pub fn diagnostics(&self) -> Vec<Diagnostic> {
        let count = unsafe { galley_recorded_diagnostic_count(self.inner) }.max(0) as u64;
        let mut out = Vec::with_capacity(count as usize);
        for i in 0..count {
            if let Some(d) = self.recorded_diagnostic_at(i) {
                out.push(d);
            }
        }
        out
    }

    /// Structured diagnostic of the failed parse, if any (the most recently
    /// recorded one). Owned copy. Its message prefers the text rendered by
    /// the grammar's error-message hooks during the parse.
    pub fn diagnostic(&self) -> Option<Diagnostic> {
        let count = unsafe { galley_recorded_diagnostic_count(self.inner) };
        if count <= 0 {
            return None;
        }
        let mut d = self.recorded_diagnostic_at((count - 1) as u64)?;
        unsafe {
            let mut msg: *const c_char = std::ptr::null();
            if galley_diagnostic_message(self.inner, &mut msg) == 0 {
                d.message = cstr(msg).unwrap_or("").to_owned();
            }
        }
        Some(d)
    }

    // ---- Tree editing -------------------------------------------------
    // Chains passed in must be detached orphans. Addresses are stable, so
    // edits never invalidate other handles.

    pub fn tree_append_children(&self, parent: NodeHandle, chain: NodeHandle) -> Result<(), Error> {
        unsafe extern "C" {
            fn galley_tree_append_children(s: *mut GalleySessionRaw, p: u64, f: u64) -> i64;
        }
        map_status(unsafe { galley_tree_append_children(self.inner, parent.0, chain.0) })
    }

    pub fn tree_insert_before(&self, target: NodeHandle, chain: NodeHandle) -> Result<(), Error> {
        unsafe extern "C" {
            fn galley_tree_insert_before(s: *mut GalleySessionRaw, t: u64, f: u64) -> i64;
        }
        map_status(unsafe { galley_tree_insert_before(self.inner, target.0, chain.0) })
    }

    pub fn tree_insert_after(&self, target: NodeHandle, chain: NodeHandle) -> Result<(), Error> {
        unsafe extern "C" {
            fn galley_tree_insert_after(s: *mut GalleySessionRaw, t: u64, f: u64) -> i64;
        }
        map_status(unsafe { galley_tree_insert_after(self.inner, target.0, chain.0) })
    }

    pub fn tree_remove_siblings(
        &self,
        node: NodeHandle,
        count: usize,
    ) -> Result<Option<NodeHandle>, Error> {
        unsafe extern "C" {
            fn galley_tree_remove_siblings(
                s: *mut GalleySessionRaw,
                n: u64,
                c: usize,
                h: *mut u64,
            ) -> i64;
        }
        let mut head = invalid_raw();
        map_status(unsafe { galley_tree_remove_siblings(self.inner, node.0, count, &mut head) })?;
        Ok(opt_handle(head))
    }

    pub fn tree_remove_self(&self, node: NodeHandle) -> Result<Option<NodeHandle>, Error> {
        unsafe extern "C" {
            fn galley_tree_remove_self(s: *mut GalleySessionRaw, n: u64, h: *mut u64) -> i64;
        }
        let mut head = invalid_raw();
        map_status(unsafe { galley_tree_remove_self(self.inner, node.0, &mut head) })?;
        Ok(opt_handle(head))
    }

    pub fn tree_promote_children_over_wrapper(
        &self,
        wrapper: NodeHandle,
    ) -> Result<Option<NodeHandle>, Error> {
        unsafe extern "C" {
            fn galley_tree_promote_children_over_wrapper(
                s: *mut GalleySessionRaw,
                w: u64,
                h: *mut u64,
            ) -> i64;
        }
        let mut head = invalid_raw();
        map_status(unsafe {
            galley_tree_promote_children_over_wrapper(self.inner, wrapper.0, &mut head)
        })?;
        Ok(opt_handle(head))
    }

    pub fn tree_clean_children(&self, node: NodeHandle) -> Result<Option<NodeHandle>, Error> {
        unsafe extern "C" {
            fn galley_tree_clean_children(s: *mut GalleySessionRaw, n: u64, h: *mut u64) -> i64;
        }
        let mut head = invalid_raw();
        map_status(unsafe { galley_tree_clean_children(self.inner, node.0, &mut head) })?;
        Ok(opt_handle(head))
    }

    pub fn tree_unlink_wrapper(&self, wrapper: NodeHandle) -> Result<(), Error> {
        unsafe extern "C" {
            fn galley_tree_unlink_wrapper(s: *mut GalleySessionRaw, w: u64) -> i64;
        }
        map_status(unsafe { galley_tree_unlink_wrapper(self.inner, wrapper.0) })
    }

    pub fn tree_insert_children_at(
        &self,
        parent: NodeHandle,
        index: usize,
        chain: NodeHandle,
    ) -> Result<(), Error> {
        unsafe extern "C" {
            fn galley_tree_insert_children_at(
                s: *mut GalleySessionRaw,
                p: u64,
                i: usize,
                f: u64,
            ) -> i64;
        }
        map_status(unsafe { galley_tree_insert_children_at(self.inner, parent.0, index, chain.0) })
    }

    pub fn tree_remove_children_at(
        &self,
        parent: NodeHandle,
        index: usize,
        count: usize,
    ) -> Result<Option<NodeHandle>, Error> {
        unsafe extern "C" {
            fn galley_tree_remove_children_at(
                s: *mut GalleySessionRaw,
                p: u64,
                i: usize,
                c: usize,
                h: *mut u64,
            ) -> i64;
        }
        let mut head = invalid_raw();
        map_status(unsafe {
            galley_tree_remove_children_at(self.inner, parent.0, index, count, &mut head)
        })?;
        Ok(opt_handle(head))
    }
}

fn invalid_raw() -> u64 {
    u64::MAX
}

fn opt_handle(raw: u64) -> Option<NodeHandle> {
    if raw == u64::MAX {
        None
    } else {
        Some(NodeHandle(raw))
    }
}

fn map_status(status: i64) -> Result<(), Error> {
    if status == 0 {
        Ok(())
    } else {
        Err(Error::from_status(status))
    }
}
