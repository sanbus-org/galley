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
    fn galley_session_create(
        options: *const RawOptions,
        out_session: *mut *mut GalleySessionRaw,
    ) -> i64;
    fn galley_session_destroy(session: *mut GalleySessionRaw) -> i64;
    fn galley_parse_sentinel(session: *mut GalleySessionRaw, input: *const c_char) -> i64;
    fn galley_parse(session: *mut GalleySessionRaw, data: *const c_char, len: usize) -> i64;
    fn galley_parse_file(session: *mut GalleySessionRaw, path: *const c_char) -> i64;
    fn galley_node_count(session: *mut GalleySessionRaw, generation: u64) -> i64;
    fn galley_root_node(
        session: *mut GalleySessionRaw,
        out_root: *mut u64,
        out_generation: *mut u64,
    ) -> i64;
    fn galley_has_ast() -> i32;
    fn galley_node_child_count(session: *mut GalleySessionRaw, generation: u64, node: u64) -> i64;
    fn galley_node_first_child(session: *mut GalleySessionRaw, generation: u64, node: u64) -> i64;
    fn galley_node_last_child(session: *mut GalleySessionRaw, generation: u64, node: u64) -> i64;
    fn galley_node_next_sibling(session: *mut GalleySessionRaw, generation: u64, node: u64) -> i64;
    fn galley_node_prior_sibling(session: *mut GalleySessionRaw, generation: u64, node: u64)
        -> i64;
    fn galley_node_parent(session: *mut GalleySessionRaw, generation: u64, node: u64) -> i64;
    fn galley_node_variable_index(
        session: *mut GalleySessionRaw,
        generation: u64,
        node: u64,
    ) -> i64;
    fn galley_walk_next(session: *mut GalleySessionRaw, cursor: *mut RawWalkCursor) -> i64;
    fn galley_node_symbol_name(
        session: *mut GalleySessionRaw,
        generation: u64,
        node: u64,
        out_data: *mut *const c_char,
        out_len: *mut usize,
    ) -> i64;
    fn galley_node_text(
        session: *mut GalleySessionRaw,
        generation: u64,
        node: u64,
        out_data: *mut *const c_char,
        out_len: *mut usize,
    ) -> i64;
    fn galley_node_span(
        session: *mut GalleySessionRaw,
        generation: u64,
        node: u64,
        out_start: *mut u64,
        out_len: *mut u64,
    ) -> i64;
    fn galley_tree_snapshot(
        session: *mut GalleySessionRaw,
        generation: u64,
        out_parent: *mut u64,
        out_first_child: *mut u64,
        out_next: *mut u64,
        out_child_count: *mut u32,
        out_variable: *mut i64,
        out_span_start: *mut u64,
        out_span_len: *mut u64,
        out_is_semantic_error: *mut i32,
        out_is_recovered: *mut i32,
        capacity: u64,
    ) -> i64;
    fn galley_last_input(
        session: *mut GalleySessionRaw,
        out_data: *mut *const c_char,
        out_len: *mut usize,
    ) -> i64;
    fn galley_node_line_column(
        session: *mut GalleySessionRaw,
        generation: u64,
        node: u64,
        out_line: *mut u32,
        out_column: *mut u32,
    ) -> i64;
    fn galley_last_position(
        session: *mut GalleySessionRaw,
        out_line: *mut u32,
        out_column: *mut u32,
    ) -> i64;
    fn galley_has_diagnostic(session: *mut GalleySessionRaw, out_has: *mut i32) -> i64;
    fn galley_diagnostic_kind(session: *mut GalleySessionRaw) -> i64;
    fn galley_diagnostic_message(session: *mut GalleySessionRaw, out: *mut *const c_char) -> i64;
    fn galley_diagnostic_position(
        session: *mut GalleySessionRaw,
        out_offset: *mut u64,
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
        out_offset: *mut u64,
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
    fn galley_diagnostic_semantic(
        session: *mut GalleySessionRaw,
        out_variable: *mut *const c_char,
        out_variable_len: *mut usize,
        out_message: *mut *const c_char,
        out_message_len: *mut usize,
    ) -> i64;
    fn galley_recorded_semantic(
        session: *mut GalleySessionRaw,
        diag_index: u64,
        out_variable: *mut *const c_char,
        out_variable_len: *mut usize,
        out_message: *mut *const c_char,
        out_message_len: *mut usize,
    ) -> i64;
    fn galley_syntax_error_count(session: *mut GalleySessionRaw) -> i64;
    fn galley_semantic_error_count(session: *mut GalleySessionRaw) -> i64;
    fn galley_session_set_message_override(
        session: *mut GalleySessionRaw,
        name: *const c_char,
        name_len: usize,
        message: *const c_char,
        message_len: usize,
    ) -> i64;
    fn galley_hooks_count() -> usize;
    fn galley_hooks_name(index: usize, out_data: *mut *const c_char, out_len: *mut usize) -> i64;
    fn galley_symbol_count() -> u64;
    fn galley_symbol_name(
        session: *mut GalleySessionRaw,
        index: u64,
        out_data: *mut *const c_char,
        out_len: *mut usize,
    ) -> i64;
    fn galley_symbol_is_terminal(
        session: *mut GalleySessionRaw,
        index: u64,
        out_is_terminal: *mut i32,
    ) -> i64;
    fn galley_variable_count() -> u64;
    fn galley_variable_name(
        session: *mut GalleySessionRaw,
        index: u64,
        out_data: *mut *const c_char,
        out_len: *mut usize,
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

/// Runtime options for [`Session::with_options`]. Zero fields select the
/// library defaults. The core owns option validation: a negative
/// `max_errors` or `recovery_window` fails session creation with
/// [`Error::InvalidArgument`] instead of being clamped here.
#[derive(Debug, Clone)]
pub struct SessionOptions {
    pub max_errors: i32,
    pub recovery_window: i32,
    pub stack_overflow_recovery: bool,
    pub syntax_error_stack_depth: u32,
    /// Message overrides applied to the session after creation: when a
    /// syntax-error site's resolution chain contains the name, the site
    /// reports the message verbatim, ahead of grammar hooks and the
    /// built-in renderer.
    pub message_overrides: Vec<(String, String)>,
}

impl Default for SessionOptions {
    fn default() -> Self {
        SessionOptions {
            max_errors: 10,
            recovery_window: 500,
            stack_overflow_recovery: false,
            syntax_error_stack_depth: 0,
            message_overrides: Vec::new(),
        }
    }
}

/// Parse/lookup failure modes mirroring the status codes of the C API.
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
    /// A handle's tree is gone: the session parsed again since, the last
    /// parse published nothing, or nothing was ever published. One failure
    /// for every source that can find a tree gone, so a dead handle never
    /// reads as a live one and never answers an empty value.
    StaleTree,
    /// A procedure call made with the arguments of a hook that has returned.
    StaleHook,
    /// A host hook's dispatch reported failure and the parse stopped. Only a
    /// library built with a host shim returns it; Rust hooks cannot fail yet.
    HookFailed,
    /// An index outside the table it was read from: a hook name, a grammar
    /// symbol or variable name, or an expected-token or context-name index
    /// past its diagnostic's table.
    OutOfRange,
    /// A value in [`SessionOptions`] outside its domain. The core owns the
    /// check; the refused call carries the status.
    InvalidArgument,
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
            -16 => Error::HookFailed,
            -17 => Error::OutOfRange,
            -18 => Error::InvalidArgument,
            _ => Error::Internal,
        }
    }

    fn status(&self) -> i64 {
        match self {
            Error::NullArgument => -1,
            Error::Syntax => -2,
            Error::Semantic => -12,
            Error::Indentation => -3,
            Error::StackOverflow => -4,
            Error::AstCapacityExceeded => -5,
            Error::UnterminatedRawString => -6,
            Error::OutOfMemory => -7,
            Error::Internal => -8,
            Error::NoDiagnostic => -9,
            Error::InvalidNode => -10,
            Error::Io => -11,
            Error::SessionInUse => -13,
            Error::StaleTree => -14,
            Error::StaleHook => -15,
            Error::HookFailed => -16,
            Error::OutOfRange => -17,
            Error::InvalidArgument => -18,
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
/// a published tree has no nodes: [`Session::root_node`] reports no root,
/// [`Session::node_count`] and [`Session::snapshot`] answer 0, reads that
/// address a node refuse with [`Error::InvalidNode`], and tree editing
/// refuses.
pub fn has_ast() -> bool {
    unsafe { galley_has_ast() != 0 }
}

/// Number of hooks the linked library forwards to a host shim. A library
/// built with compiled hooks — Rust hooks included — reports zero.
pub fn hooks_count() -> usize {
    unsafe { galley_hooks_count() }
}

/// Name of the hook at `index` of the library's fixed hook table. Fails with
/// [`Error::OutOfRange`] at or past [`hooks_count`].
pub fn hooks_name(index: usize) -> Result<&'static [u8], Error> {
    let mut data: *const c_char = std::ptr::null();
    let mut len = 0usize;
    map_status(unsafe { galley_hooks_name(index, &mut data, &mut len) })?;
    Ok(bytes(data, len))
}

/// Number of grammar symbols (variables and terminals).
pub fn symbol_count() -> u64 {
    unsafe { galley_symbol_count() }
}

/// Number of grammar variables.
pub fn variable_count() -> u64 {
    unsafe { galley_variable_count() }
}

/// Handle to a node of one parse's AST: the core's parse generation the node
/// belongs to, and its address. Every read and edit hands the generation
/// back to the core, which refuses one it no longer holds with
/// [`Error::StaleTree`], so a handle from an earlier parse never reads the
/// node that took its address.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct NodeHandle {
    generation: u64,
    address: u64,
}

impl NodeHandle {
    /// Sentinel meaning "no node here". It belongs to no parse (generation
    /// 0 is never live), so every read and edit of it is refused with
    /// [`Error::StaleTree`].
    pub const INVALID: NodeHandle = NodeHandle {
        generation: 0,
        address: INVALID_ADDRESS,
    };

    /// Raw address backing this handle (indexes [`TreeSnapshot`] columns).
    pub fn index(self) -> u64 {
        self.address
    }
}

/// One pre-order step of a [`Walker`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct WalkStep {
    pub node: NodeHandle,
    pub depth: u32,
    pub is_semantic_error: bool,
    /// The node syntax-error recovery kept in place of damaged input; its
    /// span covers the input recovery skipped.
    pub is_recovered: bool,
}

/// Flat bulk read of the published parse (see [`Session::snapshot`]): one
/// entry per node address. Missing links read as [`NodeHandle::INVALID`],
/// missing variables as -1, spans index [`Session::last_input`], and
/// `is_semantic_error` and `is_recovered` carry the flags [`WalkStep`]
/// yields.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TreeSnapshot {
    /// The generation of the parse these columns describe; [`TreeSnapshot::node`]
    /// stamps it on the handles it makes.
    pub generation: u64,
    pub count: u64,
    pub parent: Vec<u64>,
    pub first_child: Vec<u64>,
    pub next: Vec<u64>,
    pub child_count: Vec<u32>,
    pub variable: Vec<i64>,
    pub span_start: Vec<u64>,
    pub span_len: Vec<u64>,
    pub is_semantic_error: Vec<bool>,
    pub is_recovered: Vec<bool>,
}

impl TreeSnapshot {
    /// The handle for column index `index` of this snapshot's parse. It goes
    /// stale with the snapshot: a later parse refuses it.
    pub fn node(&self, index: u64) -> NodeHandle {
        NodeHandle {
            generation: self.generation,
            address: index,
        }
    }
}

/// The host-owned walk cursor, byte for byte `GalleyWalkCursor` from
/// `galley.h`: generation u64, root u64, current u64, depth u32, state u16,
/// options u8, flags u8, structure_version u64 — 40 bytes with the header's
/// layout. The core stamps `structure_version` on every step;
/// the host never reads it (zero-init here).
#[repr(C)]
#[derive(Clone, Copy)]
struct RawWalkCursor {
    generation: u64,
    root: u64,
    current: u64,
    depth: u32,
    state: u16,
    options: u8,
    flags: u8,
    structure_version: u64,
}

const _: () = assert!(std::mem::size_of::<RawWalkCursor>() == 40);

const WALK_STATE_YIELDED: u16 = 1;
const WALK_STATE_YIELDED_SKIP_CHILDREN: u16 = 2;
const WALK_OPTION_SKIP_SEMANTIC_ERRORS: u8 = 1;
const WALK_OPTION_SKIP_RECOVERED: u8 = 2;
const WALK_FLAG_SEMANTIC_ERROR: u8 = 1;
const WALK_FLAG_RECOVERED: u8 = 2;

/// Borrowing pre-order walker over the published parse's tree. The
/// walker owns no native resource — one host-side cursor stamped with the
/// session's published generation — so dropping it does nothing, and the
/// session's borrow is all it holds: no parse can start while it is alive,
/// which rules out stale walks outright. Created by [`Session::walk`].
///
/// A step yields [`Result`]: a failure — a removed current node, a
/// mid-parse session, a stale generation — ends the walk with the
/// library's error instead of stopping silently. The end of the walk is
/// not a failure: the core keeps answering success and leaves the no-node
/// sentinel in the cursor, which ends the iteration.
pub struct Walker<'session> {
    session: *mut GalleySessionRaw,
    cursor: RawWalkCursor,
    /// Set by the first failed step: iteration is over, so a consumer
    /// looping over the iterator terminates instead of re-asking a
    /// permanently failing step forever (Python's throw and Go's
    /// `(step, ok, err)` stop the loop the same way).
    finished: bool,
    _session: PhantomData<&'session Session>,
}

impl Iterator for Walker<'_> {
    type Item = Result<WalkStep, Error>;

    fn next(&mut self) -> Option<Result<WalkStep, Error>> {
        if self.finished {
            return None;
        }
        match unsafe { galley_walk_next(self.session, &mut self.cursor) } {
            // Every step that runs answers `galley_ok`; only a refusal is a
            // negative status, and a finished walk is the no-node sentinel in
            // the cursor rather than a status.
            status if status < 0 => {
                self.finished = true;
                Some(Err(Error::from_status(status)))
            }
            _ if self.cursor.current == INVALID_ADDRESS => None,
            _ => Some(Ok(WalkStep {
                node: NodeHandle {
                    generation: self.cursor.generation,
                    address: self.cursor.current,
                },
                depth: self.cursor.depth,
                is_semantic_error: self.cursor.flags & WALK_FLAG_SEMANTIC_ERROR != 0,
                is_recovered: self.cursor.flags & WALK_FLAG_RECOVERED != 0,
            })),
        }
    }
}

impl Walker<'_> {
    /// Prunes the children of the last yielded step; iteration continues
    /// with its next sibling. No effect without a last step. A host-side
    /// cursor state write; no native call.
    pub fn skip_children(&mut self) {
        if self.cursor.state == WALK_STATE_YIELDED {
            self.cursor.state = WALK_STATE_YIELDED_SKIP_CHILDREN;
        }
    }
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

/// Summary of the published parse.
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
    pub offset: u64,
    /// 1-based line of the failure; 0 when it has none.
    pub line: u32,
    pub column: u32,
    pub message: String,
    /// The parse's total syntax errors — the session door's
    /// `galley_syntax_error_count` — the same value on the current and every
    /// recorded snapshot of that parse.
    pub syntax_error_count: u64,
    /// The parse's total semantic errors — the session door's
    /// `galley_semantic_error_count` — the same value on the current and
    /// every recorded snapshot of that parse.
    pub semantic_error_count: u64,
    /// Byte token that was unexpected (syntax diagnostics only).
    pub unexpected_token: Vec<u8>,
    /// Tokens that would have been accepted (syntax diagnostics only).
    pub expected_tokens: Vec<Vec<u8>>,
    /// Innermost-first "while parsing" chain of a syntax diagnostic; a
    /// semantic diagnostic carries its single variable name. Empty for
    /// other kinds.
    pub context: Vec<String>,
    /// Indentation diagnostics only.
    pub indentation: Option<IndentationInfo>,
    /// (variable, message) for semantic diagnostics only.
    pub semantic: Option<(String, String)>,
}

#[derive(Debug, Default, PartialEq, Eq)]
pub enum DiagnosticKind {
    #[default]
    None,
    Syntax,
    Semantic,
    Indentation,
    Hook,
}

/// The diagnostic a [`Session::diagnostic_snapshot`] read names.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DiagnosticSource {
    /// The most recent diagnostic of the last parse — the one a failed parse
    /// stopped on, with its message rendered through grammar hooks and
    /// overrides.
    Current,
    /// The diagnostic recorded at this 0-based index, in recording order.
    Recorded(u64),
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

    /// Creates a session with explicit runtime options. The core owns option
    /// validation: an out-of-domain value fails with
    /// [`Error::InvalidArgument`].
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
        let mut inner: *mut GalleySessionRaw = std::ptr::null_mut();
        map_status(unsafe { galley_session_create(&raw, &mut inner) })?;
        if inner.is_null() {
            return Err(Error::Internal);
        }
        let session = Session {
            inner,
            _not_send: PhantomData,
        };
        // Overrides are fixed while a parse runs; each install either takes
        // or is refused, and a refusal fails session creation instead of
        // being dropped.
        for (name, message) in &options.message_overrides {
            let status = unsafe {
                galley_session_set_message_override(
                    session.inner,
                    name.as_ptr().cast(),
                    name.len(),
                    message.as_ptr().cast(),
                    message.len(),
                )
            };
            if status != 0 {
                // A just-created session cannot hold a parse, so destroy
                // cannot be refused; the override status is the failure.
                unsafe { galley_session_destroy(session.inner) };
                return Err(Error::from_status(status));
            }
        }
        Ok(session)
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

    /// Parses a string. The caller's bytes are passed by pointer and length;
    /// this does not allocate or copy in the binding. Interior NUL bytes are
    /// valid and are parsed as data, matching [`parse`].
    pub fn parse_sentinel(&mut self, input: &str) -> Result<usize, Error> {
        self.parse(input.as_bytes())
    }

    /// Parses the file at `path`.
    pub fn parse_file(&mut self, path: impl AsRef<Path>) -> Result<usize, Error> {
        let c_path = std::ffi::CString::new(path.as_ref().as_os_str().as_encoded_bytes())
            .map_err(|_| Error::NullArgument)?;
        self.status_to_result(unsafe { galley_parse_file(self.inner, c_path.as_ptr()) })
    }

    /// Summary of the published parse: `Ok(None)` when the parser was built
    /// without AST construction, an error when the session refuses a read —
    /// [`Error::SessionInUse`] while a parse runs, and, with AST
    /// construction, [`Error::StaleTree`] when nothing is published (before
    /// the first parse, or after one that published nothing).
    pub fn info(&self) -> Result<Option<ParseInfo>, Error> {
        // The published state is read even without AST construction, so a
        // root-tier refusal is never skipped in favor of an empty answer.
        // The info surface describes the published tree, which a no-AST
        // build does not have, so the answer is `Ok(None)`.
        let root = self.published()?.0;
        if !has_ast() {
            return Ok(None);
        }
        let mut line = 0u32;
        let mut column = 0u32;
        map_status(unsafe { galley_last_position(self.inner, &mut line, &mut column) })?;
        Ok(Some(ParseInfo {
            root,
            end_position: Some((line, column)),
        }))
    }

    /// The published tree's root and the generation every one of its nodes
    /// carries, read from the core in one call: the only source of that
    /// generation and the only "is there a tree here" probe. Nothing
    /// published is `(None, 0)`; a refusal is an error.
    ///
    /// Every handle it makes carries that generation, which each later read
    /// hands back to the core.
    fn published(&self) -> Result<(Option<NodeHandle>, u64), Error> {
        let mut root = invalid_raw();
        let mut generation = 0u64;
        let status = unsafe { galley_root_node(self.inner, &mut root, &mut generation) };
        if status < 0 {
            return Err(Error::from_status(status));
        }
        Ok((opt_handle(generation, root), generation))
    }

    /// One session-door link, stamped with the generation of `node`; the
    /// core refuses a generation it no longer holds.
    fn link(
        &self,
        read: unsafe extern "C" fn(*mut GalleySessionRaw, u64, u64) -> i64,
        node: NodeHandle,
    ) -> Result<Option<NodeHandle>, Error> {
        let address = value(unsafe { read(self.inner, node.generation, node.address) })?;
        Ok(opt_handle(node.generation, address))
    }

    /// Number of AST nodes in the published tree (0 in a build without AST
    /// construction, where a live tree has no nodes).
    ///
    /// Fails with [`Error::StaleTree`] when nothing is published.
    pub fn node_count(&self) -> Result<u64, Error> {
        self.node_count_in(self.published()?.1)
    }

    /// The node count of the tree `generation` names; the core refuses a
    /// generation it does not hold, 0 included.
    fn node_count_in(&self, generation: u64) -> Result<u64, Error> {
        value(unsafe { galley_node_count(self.inner, generation) })
    }

    /// Root node of the published tree: `Ok(Some)` is the root, `Ok(None)`
    /// means nothing is published (or the parser has no AST), and an error is
    /// the core's refusal, such as [`Error::SessionInUse`] while a parse runs.
    /// The one "is there a tree here" probe: the published state is read
    /// first, so a refusal is never skipped in favor of an empty answer.
    pub fn root_node(&self) -> Result<Option<NodeHandle>, Error> {
        Ok(self.published()?.0)
    }

    /// Direct child count of `node`.
    pub fn child_count(&self, node: NodeHandle) -> Result<u32, Error> {
        Ok(
            value(unsafe { galley_node_child_count(self.inner, node.generation, node.address) })?
                as u32,
        )
    }

    pub fn first_child(&self, node: NodeHandle) -> Result<Option<NodeHandle>, Error> {
        self.link(galley_node_first_child, node)
    }
    pub fn last_child(&self, node: NodeHandle) -> Result<Option<NodeHandle>, Error> {
        self.link(galley_node_last_child, node)
    }
    pub fn next_sibling(&self, node: NodeHandle) -> Result<Option<NodeHandle>, Error> {
        self.link(galley_node_next_sibling, node)
    }
    pub fn prior_sibling(&self, node: NodeHandle) -> Result<Option<NodeHandle>, Error> {
        self.link(galley_node_prior_sibling, node)
    }
    pub fn parent(&self, node: NodeHandle) -> Result<Option<NodeHandle>, Error> {
        self.link(galley_node_parent, node)
    }

    /// Raw variable index of `node`, or `None` when it has no variable.
    pub fn variable_index(&self, node: NodeHandle) -> Result<Option<i64>, Error> {
        let index = value(unsafe {
            galley_node_variable_index(self.inner, node.generation, node.address)
        })?;
        Ok(if index == NO_VARIABLE {
            None
        } else {
            Some(index as i64)
        })
    }

    /// Flat bulk read of the published parse in a single call: one
    /// entry per node address. Walk `parent`/`first_child`/`next` directly
    /// instead of one call per node; `variable` holds -1 for nodes without
    /// a variable and spans index [`Session::last_input`].
    ///
    /// Every leg carries one generation, so a parse that runs in between
    /// fails instead of returning columns that mix two trees.
    ///
    /// Fails with [`Error::StaleTree`] when nothing is published, and with
    /// [`Error::SessionInUse`] while a parse holds the session.
    pub fn snapshot(&self) -> Result<TreeSnapshot, Error> {
        // One read of the core fixes the generation every leg carries, so a
        // parse in between fails the count or the columns instead of mixing
        // two trees.
        let generation = self.published()?.1;
        let count = self.node_count_in(generation)? as usize;
        let mut parent = vec![INVALID_ADDRESS; count];
        let mut first_child = vec![INVALID_ADDRESS; count];
        let mut next = vec![INVALID_ADDRESS; count];
        let mut child_count = vec![0u32; count];
        let mut variable = vec![-1i64; count];
        let mut span_start = vec![0u64; count];
        let mut span_len = vec![0u64; count];
        let mut is_semantic_error = vec![0i32; count];
        let mut is_recovered = vec![0i32; count];
        let total = unsafe {
            galley_tree_snapshot(
                self.inner,
                generation,
                parent.as_mut_ptr(),
                first_child.as_mut_ptr(),
                next.as_mut_ptr(),
                child_count.as_mut_ptr(),
                variable.as_mut_ptr(),
                span_start.as_mut_ptr(),
                span_len.as_mut_ptr(),
                is_semantic_error.as_mut_ptr(),
                is_recovered.as_mut_ptr(),
                count as u64,
            )
        };
        if total < 0 {
            return Err(Error::from_status(total));
        }
        if total as u64 != count as u64 {
            return Err(Error::Internal);
        }
        Ok(TreeSnapshot {
            generation,
            count: count as u64,
            parent,
            first_child,
            next,
            child_count,
            variable: variable
                .into_iter()
                .map(|index| {
                    if index == NO_VARIABLE as i64 {
                        -1
                    } else {
                        index
                    }
                })
                .collect(),
            span_start,
            span_len,
            is_semantic_error: is_semantic_error
                .into_iter()
                .map(|flag| flag != 0)
                .collect(),
            is_recovered: is_recovered.into_iter().map(|flag| flag != 0).collect(),
        })
    }

    /// Retained input of the published parse: the buffer snapshot spans
    /// index. Follows the published tree like every node read: fails with
    /// [`Error::StaleTree`] whenever nothing is published (before the first
    /// parse included), and with [`Error::SessionInUse`] while a parse runs.
    pub fn last_input(&self) -> Result<&[u8], Error> {
        unsafe {
            let mut data: *const c_char = std::ptr::null();
            let mut len = 0usize;
            let status = galley_last_input(self.inner, &mut data, &mut len);
            if status < 0 {
                return Err(Error::from_status(status));
            }
            Ok(std::slice::from_raw_parts(data as *const u8, len))
        }
    }

    /// Pre-order walker over the subtree rooted at `root`, yielding one
    /// [`WalkStep`] per node with the root at depth 0. The walker owns no
    /// native resource — one host-side cursor stamped with the session's
    /// published generation — and borrows the session, so no new parse can
    /// invalidate it mid-walk. An invalid root or a build without AST
    /// construction answers `Err(`[`Error::InvalidNode`]`)` at the first
    /// step.
    pub fn walk(
        &self,
        root: NodeHandle,
        skip_semantic_errors: bool,
        skip_recovered: bool,
    ) -> Walker<'_> {
        // The walk is bound to the tree `root` came from: the cursor carries
        // the root's own generation, which the core checks at every step.
        Walker {
            session: self.inner,
            cursor: RawWalkCursor {
                generation: root.generation,
                root: root.address,
                current: 0,
                depth: 0,
                state: 0,
                options: (if skip_semantic_errors {
                    WALK_OPTION_SKIP_SEMANTIC_ERRORS
                } else {
                    0
                }) | (if skip_recovered {
                    WALK_OPTION_SKIP_RECOVERED
                } else {
                    0
                }),
                flags: 0,
                structure_version: 0,
            },
            finished: false,
            _session: PhantomData,
        }
    }

    /// Children of `node`, first to last.
    pub fn children(
        &self,
        node: NodeHandle,
    ) -> Result<impl Iterator<Item = Result<NodeHandle, Error>> + '_, Error> {
        // Each step hands the core the node's own generation, so a parse
        // that retires the tree mid-iteration ends the walk with an error
        // instead of a stale address.
        let mut next = self.first_child(node)?;
        Ok(std::iter::from_fn(move || {
            let current = next?;
            match self.next_sibling(current) {
                Ok(sibling) => {
                    next = sibling;
                    Some(Ok(current))
                }
                Err(error) => {
                    next = None;
                    Some(Err(error))
                }
            }
        }))
    }

    /// Grammar symbol name of `node` (e.g. `"ObjectMembers"`); empty for a
    /// node with no symbol.
    pub fn symbol_name<'a>(&'a self, node: NodeHandle) -> Result<&'a [u8], Error> {
        let mut data: *const c_char = std::ptr::null();
        let mut len = 0usize;
        map_status(unsafe {
            galley_node_symbol_name(
                self.inner,
                node.generation,
                node.address,
                &mut data,
                &mut len,
            )
        })?;
        Ok(bytes(data, len))
    }

    /// Source text matched by `node`; borrows the session's retained input.
    pub fn text<'a>(&'a self, node: NodeHandle) -> Result<&'a [u8], Error> {
        let mut data: *const c_char = std::ptr::null();
        let mut len = 0usize;
        map_status(unsafe {
            galley_node_text(
                self.inner,
                node.generation,
                node.address,
                &mut data,
                &mut len,
            )
        })?;
        Ok(bytes(data, len))
    }

    /// Byte span (offset into the parse input, length) of `node`.
    pub fn span(&self, node: NodeHandle) -> Result<(u64, u64), Error> {
        let mut start = 0u64;
        let mut len = 0u64;
        map_status(unsafe {
            galley_node_span(
                self.inner,
                node.generation,
                node.address,
                &mut start,
                &mut len,
            )
        })?;
        Ok((start, len))
    }

    /// 1-based line/column of `node`'s first byte.
    pub fn line_column(&self, node: NodeHandle) -> Result<(u32, u32), Error> {
        let mut l = 0u32;
        let mut c = 0u32;
        map_status(unsafe {
            galley_node_line_column(self.inner, node.generation, node.address, &mut l, &mut c)
        })?;
        Ok((l, c))
    }

    // ---- Grammar tables ------------------------------------------------

    /// Name of the grammar symbol at `index` (a variable or a terminal).
    /// Fails with [`Error::OutOfRange`] at or past [`symbol_count`].
    pub fn symbol_name_at(&self, index: u64) -> Result<&[u8], Error> {
        let mut data: *const c_char = std::ptr::null();
        let mut len = 0usize;
        map_status(unsafe { galley_symbol_name(self.inner, index, &mut data, &mut len) })?;
        Ok(bytes(data, len))
    }

    /// Whether the symbol at `index` is a terminal, false for a variable.
    /// Fails with [`Error::OutOfRange`] at or past [`symbol_count`].
    pub fn symbol_is_terminal(&self, index: u64) -> Result<bool, Error> {
        let mut is_terminal = 0i32;
        map_status(unsafe { galley_symbol_is_terminal(self.inner, index, &mut is_terminal) })?;
        Ok(is_terminal != 0)
    }

    /// Name of the grammar variable at `index`. Fails with
    /// [`Error::OutOfRange`] at or past [`variable_count`].
    pub fn variable_name_at(&self, index: u64) -> Result<&[u8], Error> {
        let mut data: *const c_char = std::ptr::null();
        let mut len = 0usize;
        map_status(unsafe { galley_variable_name(self.inner, index, &mut data, &mut len) })?;
        Ok(bytes(data, len))
    }

    // ---- Diagnostics ---------------------------------------------------

    /// Whether the last parse recorded a diagnostic. `Ok(false)` means it
    /// recorded none; a refusal — a parse in flight, say — is an error, never
    /// `Ok(false)`.
    pub fn has_diagnostic(&self) -> Result<bool, Error> {
        let mut has = 0i32;
        map_status(unsafe { galley_has_diagnostic(self.inner, &mut has) })?;
        Ok(has != 0)
    }

    /// Reads one diagnostic through the one path: the kind first, then
    /// exactly the fields that kind carries, every refusal raised.
    /// `Current` names the most recent one — the diagnostic a failed parse
    /// stopped on — and `Recorded(index)` the diagnostic at that 0-based
    /// position, in recording order. Both messages are the rendered text
    /// with grammar hooks and overrides applied. Fails with
    /// [`Error::NoDiagnostic`] when the source names nothing: a clean parse
    /// for `Current`, an index at or past the recorded diagnostics for
    /// `Recorded`. Never answers an empty snapshot for a refusal. Every
    /// snapshot also carries the parse's `syntax_error_count` and
    /// `semantic_error_count` totals.
    pub fn diagnostic_snapshot(&self, source: DiagnosticSource) -> Result<Diagnostic, Error> {
        let kind = match source {
            DiagnosticSource::Current => {
                diagnostic_kind(unsafe { galley_diagnostic_kind(self.inner) })?
            }
            DiagnosticSource::Recorded(index) => {
                diagnostic_kind(unsafe { galley_recorded_diagnostic_kind(self.inner, index) })?
            }
        };
        if kind == DiagnosticKind::None {
            return Err(Error::NoDiagnostic);
        }
        let mut snapshot = Diagnostic {
            kind,
            ..Diagnostic::default()
        };

        // Position and message: every kind carries both.
        match source {
            DiagnosticSource::Current => map_status(unsafe {
                galley_diagnostic_position(
                    self.inner,
                    &mut snapshot.offset,
                    &mut snapshot.line,
                    &mut snapshot.column,
                )
            })?,
            DiagnosticSource::Recorded(index) => map_status(unsafe {
                galley_recorded_diagnostic_position(
                    self.inner,
                    index,
                    &mut snapshot.offset,
                    &mut snapshot.line,
                    &mut snapshot.column,
                )
            })?,
        }
        let mut message: *const c_char = std::ptr::null();
        match source {
            DiagnosticSource::Current => {
                map_status(unsafe { galley_diagnostic_message(self.inner, &mut message) })?
            }
            DiagnosticSource::Recorded(index) => map_status(unsafe {
                galley_recorded_diagnostic_message(self.inner, index, &mut message)
            })?,
        }
        snapshot.message = unsafe { cstr(message) }.unwrap_or("").to_owned();

        // The parse's totals, not the record's: read from the session for
        // either source, so every snapshot of a parse carries the same two.
        snapshot.syntax_error_count = value(unsafe { galley_syntax_error_count(self.inner) })?;
        snapshot.semantic_error_count = value(unsafe { galley_semantic_error_count(self.inner) })?;

        // The kind's own fields; an accessor refuses a record it does not
        // fit, so each is read only for the kind whose fields it is.
        match snapshot.kind {
            DiagnosticKind::Syntax => {
                let mut data: *const c_char = std::ptr::null();
                let mut len = 0usize;
                match source {
                    DiagnosticSource::Current => map_status(unsafe {
                        galley_diagnostic_unexpected_token(self.inner, &mut data, &mut len)
                    })?,
                    DiagnosticSource::Recorded(index) => map_status(unsafe {
                        galley_recorded_unexpected_token(self.inner, index, &mut data, &mut len)
                    })?,
                }
                snapshot.unexpected_token = bytes(data, len).to_vec();

                let count = match source {
                    DiagnosticSource::Current => {
                        value(unsafe { galley_diagnostic_expected_count(self.inner) })?
                    }
                    DiagnosticSource::Recorded(index) => {
                        value(unsafe { galley_recorded_expected_count(self.inner, index) })?
                    }
                };
                for token_index in 0..count {
                    let mut data: *const c_char = std::ptr::null();
                    let mut len = 0usize;
                    match source {
                        DiagnosticSource::Current => map_status(unsafe {
                            galley_diagnostic_expected_at(
                                self.inner,
                                token_index,
                                &mut data,
                                &mut len,
                            )
                        })?,
                        DiagnosticSource::Recorded(index) => map_status(unsafe {
                            galley_recorded_expected_token(
                                self.inner,
                                index,
                                token_index,
                                &mut data,
                                &mut len,
                            )
                        })?,
                    }
                    snapshot.expected_tokens.push(bytes(data, len).to_vec());
                }
                snapshot.context = self.context_names(source)?;
            }
            DiagnosticKind::Semantic => {
                let mut variable: *const c_char = std::ptr::null();
                let mut variable_len = 0usize;
                let mut semantic_message: *const c_char = std::ptr::null();
                let mut semantic_message_len = 0usize;
                match source {
                    DiagnosticSource::Current => map_status(unsafe {
                        galley_diagnostic_semantic(
                            self.inner,
                            &mut variable,
                            &mut variable_len,
                            &mut semantic_message,
                            &mut semantic_message_len,
                        )
                    })?,
                    DiagnosticSource::Recorded(index) => map_status(unsafe {
                        galley_recorded_semantic(
                            self.inner,
                            index,
                            &mut variable,
                            &mut variable_len,
                            &mut semantic_message,
                            &mut semantic_message_len,
                        )
                    })?,
                }
                snapshot.semantic = Some((
                    String::from_utf8_lossy(bytes(variable, variable_len)).into_owned(),
                    String::from_utf8_lossy(bytes(semantic_message, semantic_message_len))
                        .into_owned(),
                ));
                snapshot.context = self.context_names(source)?;
            }
            DiagnosticKind::Indentation => {
                let mut spaces = 0u32;
                let mut width = 0u32;
                match source {
                    DiagnosticSource::Current => map_status(unsafe {
                        galley_diagnostic_indentation(self.inner, &mut spaces, &mut width)
                    })?,
                    DiagnosticSource::Recorded(index) => map_status(unsafe {
                        galley_recorded_indentation(self.inner, index, &mut spaces, &mut width)
                    })?,
                }
                snapshot.indentation = Some(IndentationInfo {
                    spaces,
                    indentation_width: width,
                });
            }
            DiagnosticKind::Hook | DiagnosticKind::None => {}
        }
        Ok(snapshot)
    }

    /// The context chain of the diagnostic `source` names: innermost-first
    /// variable names for a syntax diagnostic, the single variable for a
    /// semantic one.
    fn context_names(&self, source: DiagnosticSource) -> Result<Vec<String>, Error> {
        let count = match source {
            DiagnosticSource::Current => {
                value(unsafe { galley_diagnostic_context_count(self.inner) })?
            }
            DiagnosticSource::Recorded(index) => {
                value(unsafe { galley_recorded_context_count(self.inner, index) })?
            }
        };
        let mut names = Vec::with_capacity(count as usize);
        for context_index in 0..count {
            let mut data: *const c_char = std::ptr::null();
            let mut len = 0usize;
            match source {
                DiagnosticSource::Current => map_status(unsafe {
                    galley_diagnostic_context_at(self.inner, context_index, &mut data, &mut len)
                })?,
                DiagnosticSource::Recorded(index) => map_status(unsafe {
                    galley_recorded_context_name(
                        self.inner,
                        index,
                        context_index,
                        &mut data,
                        &mut len,
                    )
                })?,
            }
            names.push(unsafe { cstr(data) }.unwrap_or("").to_owned());
        }
        Ok(names)
    }

    /// Structured diagnostic of the failed parse, if any: the one the parse
    /// stopped on (the most recently recorded), with its message rendered
    /// through the grammar's error-message hooks and overrides. `Ok(None)`
    /// when the last parse recorded none; a refusal is an error, never
    /// `Ok(None)`.
    pub fn diagnostic(&self) -> Result<Option<Diagnostic>, Error> {
        if !self.has_diagnostic()? {
            return Ok(None);
        }
        Ok(Some(self.diagnostic_snapshot(DiagnosticSource::Current)?))
    }

    /// Structured diagnostic recorded at `index` (0-based, in recording
    /// order) during the last parse. Fails with [`Error::NoDiagnostic`] at
    /// or past the recorded count, never with an empty snapshot.
    pub fn diagnostic_at(&self, index: u64) -> Result<Diagnostic, Error> {
        self.diagnostic_snapshot(DiagnosticSource::Recorded(index))
    }

    /// Structured diagnostics of the last parse, in recording order. Owned
    /// copies; empty when the parse recorded none. A refusal — a parse in
    /// flight, say — is an error, never an empty list.
    pub fn diagnostics(&self) -> Result<Vec<Diagnostic>, Error> {
        let count = value(unsafe { galley_recorded_diagnostic_count(self.inner) })?;
        let mut out = Vec::with_capacity(count as usize);
        for index in 0..count {
            out.push(self.diagnostic_at(index)?);
        }
        Ok(out)
    }

    // ---- Tree editing -------------------------------------------------
    // Chains passed in must be detached orphans. Addresses are stable, so
    // edits never invalidate other handles.

    pub fn tree_append_children(&self, parent: NodeHandle, chain: NodeHandle) -> Result<(), Error> {
        unsafe extern "C" {
            fn galley_tree_append_children(
                s: *mut GalleySessionRaw,
                g: u64,
                p: u64,
                first_generation: u64,
                f: u64,
            ) -> i64;
        }
        // Each node crosses with its own generation; the core refuses a pair
        // from two parses.
        map_status(unsafe {
            galley_tree_append_children(
                self.inner,
                parent.generation,
                parent.address,
                chain.generation,
                chain.address,
            )
        })
    }

    pub fn tree_insert_before(&self, target: NodeHandle, chain: NodeHandle) -> Result<(), Error> {
        unsafe extern "C" {
            fn galley_tree_insert_before(
                s: *mut GalleySessionRaw,
                g: u64,
                t: u64,
                first_generation: u64,
                f: u64,
            ) -> i64;
        }
        map_status(unsafe {
            galley_tree_insert_before(
                self.inner,
                target.generation,
                target.address,
                chain.generation,
                chain.address,
            )
        })
    }

    pub fn tree_insert_after(&self, target: NodeHandle, chain: NodeHandle) -> Result<(), Error> {
        unsafe extern "C" {
            fn galley_tree_insert_after(
                s: *mut GalleySessionRaw,
                g: u64,
                t: u64,
                first_generation: u64,
                f: u64,
            ) -> i64;
        }
        map_status(unsafe {
            galley_tree_insert_after(
                self.inner,
                target.generation,
                target.address,
                chain.generation,
                chain.address,
            )
        })
    }

    pub fn tree_remove_siblings(
        &self,
        node: NodeHandle,
        count: usize,
    ) -> Result<Option<NodeHandle>, Error> {
        unsafe extern "C" {
            fn galley_tree_remove_siblings(
                s: *mut GalleySessionRaw,
                g: u64,
                n: u64,
                c: usize,
                h: *mut u64,
            ) -> i64;
        }
        let mut head = invalid_raw();
        map_status(unsafe {
            galley_tree_remove_siblings(self.inner, node.generation, node.address, count, &mut head)
        })?;
        Ok(opt_handle(node.generation, head))
    }

    pub fn tree_remove_self(&self, node: NodeHandle) -> Result<Option<NodeHandle>, Error> {
        unsafe extern "C" {
            fn galley_tree_remove_self(
                s: *mut GalleySessionRaw,
                g: u64,
                n: u64,
                h: *mut u64,
            ) -> i64;
        }
        let mut head = invalid_raw();
        map_status(unsafe {
            galley_tree_remove_self(self.inner, node.generation, node.address, &mut head)
        })?;
        Ok(opt_handle(node.generation, head))
    }

    pub fn tree_clean_children(&self, node: NodeHandle) -> Result<Option<NodeHandle>, Error> {
        unsafe extern "C" {
            fn galley_tree_clean_children(
                s: *mut GalleySessionRaw,
                g: u64,
                n: u64,
                h: *mut u64,
            ) -> i64;
        }
        let mut head = invalid_raw();
        map_status(unsafe {
            galley_tree_clean_children(self.inner, node.generation, node.address, &mut head)
        })?;
        Ok(opt_handle(node.generation, head))
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
                g: u64,
                p: u64,
                i: usize,
                first_generation: u64,
                f: u64,
            ) -> i64;
        }
        map_status(unsafe {
            galley_tree_insert_children_at(
                self.inner,
                parent.generation,
                parent.address,
                index,
                chain.generation,
                chain.address,
            )
        })
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
                g: u64,
                p: u64,
                i: usize,
                c: usize,
                h: *mut u64,
            ) -> i64;
        }
        let mut head = invalid_raw();
        map_status(unsafe {
            galley_tree_remove_children_at(
                self.inner,
                parent.generation,
                parent.address,
                index,
                count,
                &mut head,
            )
        })?;
        Ok(opt_handle(parent.generation, head))
    }
}

/// `GALLEY_INVALID_NODE`: no node at that position. Non-negative like every
/// address, so a value-returning call can report a negative status.
const INVALID_ADDRESS: u64 = i64::MAX as u64;

/// `GALLEY_NO_VARIABLE`: the core's answer for a node without a variable.
const NO_VARIABLE: u64 = i64::MAX as u64;

fn invalid_raw() -> u64 {
    INVALID_ADDRESS
}

/// A value-returning session-door call answers with its value, always
/// non-negative, or a negative status.
fn value(status: i64) -> Result<u64, Error> {
    u64::try_from(status).map_err(|_| Error::from_status(status))
}

fn opt_handle(generation: u64, address: u64) -> Option<NodeHandle> {
    if address == INVALID_ADDRESS {
        None
    } else {
        Some(NodeHandle {
            generation,
            address,
        })
    }
}

/// One diagnostic kind code — the C enum value — as an enum, or the status
/// that refused the read. Only a status is negative; the none kind is a real
/// value.
fn diagnostic_kind(status: i64) -> Result<DiagnosticKind, Error> {
    match status {
        0 => Ok(DiagnosticKind::None),
        1 => Ok(DiagnosticKind::Syntax),
        2 => Ok(DiagnosticKind::Indentation),
        3 => Ok(DiagnosticKind::Semantic),
        4 => Ok(DiagnosticKind::Hook),
        refused => Err(Error::from_status(refused)),
    }
}

fn map_status(status: i64) -> Result<(), Error> {
    if status == 0 {
        Ok(())
    } else {
        Err(Error::from_status(status))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_error_status_round_trips() {
        for error in [
            Error::NullArgument,
            Error::Syntax,
            Error::Semantic,
            Error::Indentation,
            Error::StackOverflow,
            Error::AstCapacityExceeded,
            Error::UnterminatedRawString,
            Error::OutOfMemory,
            Error::Internal,
            Error::NoDiagnostic,
            Error::InvalidNode,
            Error::Io,
            Error::SessionInUse,
            Error::StaleTree,
            Error::StaleHook,
            Error::HookFailed,
            Error::OutOfRange,
            Error::InvalidArgument,
        ] {
            assert_eq!(Error::from_status(error.status()), error);
        }
    }

    #[test]
    fn the_new_statuses_carry_their_codes() {
        assert_eq!(Error::OutOfRange.status(), -17);
        assert_eq!(Error::InvalidArgument.status(), -18);
    }

    #[test]
    fn an_unknown_status_is_internal() {
        assert_eq!(Error::from_status(-999), Error::Internal);
        assert_eq!(Error::from_status(7), Error::Internal);
    }

    #[test]
    fn only_negative_values_are_statuses() {
        assert_eq!(diagnostic_kind(0), Ok(DiagnosticKind::None));
        assert_eq!(diagnostic_kind(1), Ok(DiagnosticKind::Syntax));
        assert_eq!(diagnostic_kind(2), Ok(DiagnosticKind::Indentation));
        assert_eq!(diagnostic_kind(3), Ok(DiagnosticKind::Semantic));
        assert_eq!(diagnostic_kind(4), Ok(DiagnosticKind::Hook));
        assert_eq!(diagnostic_kind(-9), Err(Error::NoDiagnostic));
        assert_eq!(diagnostic_kind(-17), Err(Error::OutOfRange));
    }
}
