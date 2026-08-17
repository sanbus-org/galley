//! Default `runtime_options` module for external consumers of galley's runtime.
//!
//! Galley's runtime resolves every option through `@hasDecl`, so this empty
//! module yields the built-in defaults: runtime tests disabled, no AST memory
//! benchmark, and the build-mode syntax error stack depth. Consumers that want
//! to override an option provide their own options module instead of importing
//! this one.
