/**
 * Low-level koffi bindings over `bindings/c/galley.h`.
 *
 * This is the single FFI boundary for the TypeScript bindings (mirroring
 * `bindings/python/_galley.c` and `bindings/go/assets/wrapper.go.tmpl`).
 * All higher-level `Session`/`Node` code goes through this module; no
 * caller touches koffi directly.
 */

import { Buffer } from "node:buffer";
import * as fs from "node:fs";
import { createRequire } from "node:module";
import * as os from "node:os";
import * as path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
const require = createRequire(import.meta.url);
// eslint-disable-next-line @typescript-eslint/no-require-imports
const koffi = require("koffi") as typeof import("koffi");

export type LibraryHandle = ReturnType<typeof koffi.load>;

// Cached library and path
let cached: GalleyFFI | null = null;
let cachedPath: string | null = null;

// Global struct definition — koffi keeps a process-wide type registry, so
// defining the same struct twice with the same name would throw
// "Duplicate type name". Define once for all loads.
const GalleyCOptionsType = koffi.struct("GalleyCOptions", {
  max_errors: "int",
  recovery_window: "int",
  stack_overflow_recovery: "int",
  syntax_error_stack_depth: "uint",
  verbosity: "int",
  ast_preallocation_ratio: "double",
  ast_preallocation_cap: "uint64_t",
});

export interface GalleyFFI {
  libPath: string;
  lib: LibraryHandle;
  // version / metadata
  galley_version: () => string;
  galley_parser_type: () => bigint | number;
  galley_error_recovery_mode: () => bigint | number;
  galley_has_ast: () => number;
  galley_has_procedures: () => number;
  galley_allows_no_ast_tree_procedures: () => number;
  galley_source_retention_enabled: () => number;
  galley_has_position_tracking: () => number;
  galley_has_input_streaming: () => number;
  galley_uses_verbatim: () => number;
  galley_stack_overflow_recovery_available: () => number;
  galley_symbol_count: () => bigint | number;
  galley_variable_count: () => bigint | number;
  galley_status_string: (status: bigint | number) => string | null;

  // symbol table
  galley_symbol_name: (
    session: bigint,
    index: bigint | number,
    outData: unknown[],
    outLen: unknown[],
  ) => bigint | number;
  galley_symbol_is_terminal: (session: bigint, index: bigint | number) => number;
  galley_variable_name: (
    session: bigint,
    index: bigint | number,
    outData: unknown[],
    outLen: unknown[],
  ) => bigint | number;

  // session
  galley_session_create: () => bigint;
  galley_session_create_ex: (options: unknown) => bigint;
  galley_session_destroy: (session: bigint) => void;
  galley_session_set_message_override: (
    session: bigint,
    name: string,
    nameLen: number | bigint,
    message: string,
    messageLen: number | bigint,
  ) => bigint | number;

  // parse
  galley_parse_sentinel: (session: bigint, input: string) => bigint | number;
  galley_parse: (session: bigint, data: unknown, len: number | bigint) => bigint | number;
  galley_parse_file: (session: bigint, p: string) => bigint | number;
  galley_last_position: (session: bigint, outLine: unknown[], outCol: unknown[]) => bigint | number;

  // node / tree
  galley_node_count: (session: bigint) => bigint | number;
  galley_reserve_nodes: (session: bigint, cap: bigint | number) => bigint | number;
  galley_node_capacity: (session: bigint) => bigint | number;
  galley_root_node: (session: bigint) => bigint | number;
  galley_node_is_valid: (session: bigint, node: bigint | number) => number;
  galley_node_child_count: (session: bigint, node: bigint | number) => number;
  galley_node_first_child: (session: bigint, node: bigint | number) => bigint | number;
  galley_node_last_child: (session: bigint, node: bigint | number) => bigint | number;
  galley_node_next_sibling: (session: bigint, node: bigint | number) => bigint | number;
  galley_node_prior_sibling: (session: bigint, node: bigint | number) => bigint | number;
  galley_node_parent: (session: bigint, node: bigint | number) => bigint | number;
  galley_walker_create: (
    session: bigint,
    node: bigint | number,
    skipSemanticErrors: number,
  ) => bigint;
  galley_walker_next: (
    walker: bigint,
    outNode: unknown[],
    outDepth: unknown[],
    outIsSemanticError: unknown[],
  ) => number;
  galley_walker_skip_children: (walker: bigint) => void;
  galley_walker_destroy: (walker: bigint) => void;
  galley_node_symbol_name: (
    session: bigint,
    node: bigint | number,
    outData: unknown[],
    outLen: unknown[],
  ) => bigint | number;
  galley_node_text: (
    session: bigint,
    node: bigint | number,
    outData: unknown[],
    outLen: unknown[],
  ) => bigint | number;
  galley_node_span: (
    session: bigint,
    node: bigint | number,
    outStart: unknown[],
    outLen: unknown[],
  ) => bigint | number;
  galley_node_line_column: (
    session: bigint,
    node: bigint | number,
    outLine: unknown[],
    outCol: unknown[],
  ) => bigint | number;
  galley_node_variable_index: (session: bigint, node: bigint | number) => bigint | number;

  // diagnostics (singular)
  galley_has_diagnostic: (session: bigint) => number;
  galley_diagnostic_kind: (session: bigint) => bigint | number;
  galley_diagnostic_message: (session: bigint, out: unknown[]) => bigint | number;
  galley_diagnostic_message_ansi: (session: bigint, out: unknown[]) => bigint | number;
  galley_diagnostic_position: (session: bigint, outLine: unknown[], outCol: unknown[]) => bigint | number;
  galley_diagnostic_unexpected_token: (
    session: bigint,
    outData: unknown[],
    outLen: unknown[],
  ) => bigint | number;
  galley_diagnostic_expected_count: (session: bigint) => bigint | number;
  galley_diagnostic_expected_at: (
    session: bigint,
    index: bigint | number,
    outData: unknown[],
    outLen: unknown[],
  ) => bigint | number;
  galley_diagnostic_context_count: (session: bigint) => bigint | number;
  galley_diagnostic_context_at: (
    session: bigint,
    index: bigint | number,
    outData: unknown[],
    outLen: unknown[],
  ) => bigint | number;
  galley_diagnostic_indentation: (
    session: bigint,
    outSpaces: unknown[],
    outWidth: unknown[],
  ) => bigint | number;
  galley_syntax_error_count: (session: bigint) => bigint | number;
  galley_semantic_error_count: (session: bigint) => bigint | number;
  galley_diagnostic_semantic: (
    session: bigint,
    outVariable: unknown[],
    outVariableLen: unknown[],
    outMessage: unknown[],
    outMessageLen: unknown[],
  ) => bigint | number;
  galley_recorded_semantic: (
    session: bigint,
    diagIndex: bigint | number,
    outVariable: unknown[],
    outVariableLen: unknown[],
    outMessage: unknown[],
    outMessageLen: unknown[],
  ) => bigint | number;

  // recovery (singular)
  galley_diagnostic_recovery_kind: (session: bigint) => bigint | number;
  galley_diagnostic_recovery_terminal: (
    session: bigint,
    outData: unknown[],
    outLen: unknown[],
  ) => bigint | number;
  galley_diagnostic_recovery_resume: (session: bigint, out: unknown[]) => bigint | number;
  galley_diagnostic_recovery_lhs_variable: (
    session: bigint,
    outData: unknown[],
    outLen: unknown[],
  ) => bigint | number;
  galley_diagnostic_recovery_production: (
    session: bigint,
    outVar: unknown[],
    outLen: unknown[],
    outIndex: unknown[],
  ) => bigint | number;
  galley_diagnostic_recovery_occurrence: (
    session: bigint,
    outParent: unknown[],
    outParentLen: unknown[],
    outRhs: unknown[],
    outSym: unknown[],
    outVar: unknown[],
    outVarLen: unknown[],
  ) => bigint | number;

  // recorded
  galley_recorded_diagnostic_count: (session: bigint) => bigint | number;
  galley_recorded_diagnostic_kind: (session: bigint, idx: bigint | number) => bigint | number;
  galley_recorded_diagnostic_position: (
    session: bigint,
    idx: bigint | number,
    outLine: unknown[],
    outCol: unknown[],
  ) => bigint | number;
  galley_recorded_unexpected_token: (
    session: bigint,
    idx: bigint | number,
    outData: unknown[],
    outLen: unknown[],
  ) => bigint | number;
  galley_recorded_diagnostic_message: (session: bigint, idx: bigint | number, out: unknown[]) => bigint | number;
  galley_recorded_indentation: (
    session: bigint,
    idx: bigint | number,
    outSpaces: unknown[],
    outWidth: unknown[],
  ) => bigint | number;
  galley_recorded_expected_count: (session: bigint, idx: bigint | number) => bigint | number;
  galley_recorded_expected_token: (
    session: bigint,
    idx: bigint | number,
    tokenIdx: bigint | number,
    outData: unknown[],
    outLen: unknown[],
  ) => bigint | number;
  galley_recorded_context_count: (session: bigint, idx: bigint | number) => bigint | number;
  galley_recorded_context_name: (
    session: bigint,
    idx: bigint | number,
    ctxIdx: bigint | number,
    outData: unknown[],
    outLen: unknown[],
  ) => bigint | number;
  galley_recorded_recovery_kind: (session: bigint, idx: bigint | number) => bigint | number;
  galley_recorded_recovery_terminal: (
    session: bigint,
    idx: bigint | number,
    outData: unknown[],
    outLen: unknown[],
  ) => bigint | number;
  galley_recorded_recovery_resume: (session: bigint, idx: bigint | number, out: unknown[]) => bigint | number;
  galley_recorded_recovery_lhs_variable: (
    session: bigint,
    idx: bigint | number,
    outData: unknown[],
    outLen: unknown[],
  ) => bigint | number;
  galley_recorded_recovery_production: (
    session: bigint,
    idx: bigint | number,
    outVar: unknown[],
    outLen: unknown[],
    outIdx: unknown[],
  ) => bigint | number;
  galley_recorded_recovery_occurrence: (
    session: bigint,
    idx: bigint | number,
    outParent: unknown[],
    outParentLen: unknown[],
    outRhs: unknown[],
    outSym: unknown[],
    outVar: unknown[],
    outVarLen: unknown[],
  ) => bigint | number;

  // tree editing
  galley_tree_append_children: (session: bigint, parent: bigint | number, first: bigint | number) => bigint | number;
  galley_tree_insert_before: (session: bigint, target: bigint | number, first: bigint | number) => bigint | number;
  galley_tree_insert_after: (session: bigint, target: bigint | number, first: bigint | number) => bigint | number;
  galley_tree_remove_siblings: (
    session: bigint,
    node: bigint | number,
    count: number | bigint,
    outHead: unknown[],
  ) => bigint | number;
  galley_tree_remove_self: (session: bigint, node: bigint | number, outHead: unknown[]) => bigint | number;
  galley_tree_promote_children_over_wrapper: (session: bigint, wrapper: bigint | number, outHead: unknown[]) => bigint | number;
  galley_tree_clean_children: (session: bigint, node: bigint | number, outHead: unknown[]) => bigint | number;
  galley_tree_unlink_wrapper: (session: bigint, wrapper: bigint | number) => bigint | number;
  galley_tree_insert_children_at: (
    session: bigint,
    parent: bigint | number,
    index: number | bigint,
    first: bigint | number,
  ) => bigint | number;
  galley_tree_remove_children_at: (
    session: bigint,
    parent: bigint | number,
    index: number | bigint,
    count: number | bigint,
    outHead: unknown[],
  ) => bigint | number;

  // procedure dispatch (TypeScript shim)
  galley_install_typescript_dispatch: ((target: unknown) => void) | null;

  // procedure-hook state; tree queries use galley_node_* on the session
  galley_procedure_session: (args: bigint) => bigint;
  galley_procedure_current_node: (args: bigint) => bigint;
  galley_procedure_set_current_node: (args: bigint, node: bigint | number) => void;
  galley_procedure_drop_self: (args: bigint) => bigint | number;
  galley_procedure_drop_children: (args: bigint) => bigint | number;
  galley_procedure_drop_if_empty: (args: bigint) => bigint | number;
  galley_procedure_replace_with_children: (args: bigint) => bigint | number;
  galley_procedure_context_line: (args: bigint) => number;
  galley_procedure_context_column: (args: bigint) => number;
  galley_procedure_report_semantic_error: (
    args: bigint,
    message: string,
    messageLen: number | bigint,
  ) => bigint | number;

  // struct for options
  GalleyCOptions: ReturnType<typeof koffi.struct>;
}

// --- library discovery -------------------------------------------------

function defaultCacheDir(): string {
  const home = os.homedir();
  if (process.platform === "darwin") {
    return path.join(home, "Library", "Caches", "galley-bindings", "typescript", "capi");
  }
  if (process.platform === "win32") {
    const base = process.env.LOCALAPPDATA ?? os.tmpdir();
    return path.join(base, "galley-bindings", "typescript", "capi");
  }
  const base = process.env.XDG_CACHE_HOME ?? path.join(home, ".cache");
  return path.join(base, "galley-bindings", "typescript", "capi");
}

function libFileName(base = "galley-typescript"): string {
  if (process.platform === "darwin") return `lib${base}.dylib`;
  if (process.platform === "win32") return `${base}.dll`;
  return `lib${base}.so`;
}

function exists(p: string): boolean {
  try {
    fs.accessSync(p);
    return true;
  } catch {
    return false;
  }
}

export function findLibrary(explicit?: string): string {
  if (explicit && exists(explicit)) return path.resolve(explicit);
  if (process.env.GALLEY_LIBRARY_PATH && exists(process.env.GALLEY_LIBRARY_PATH)) {
    return path.resolve(process.env.GALLEY_LIBRARY_PATH);
  }
  // 1) cwd / language-dir copies (build.mjs copies lib next to grammar)
  const cwdCandidates = [
    path.join(process.cwd(), libFileName()),
    path.join(process.cwd(), libFileName("galley-typescript")),
    path.join(process.cwd(), "libgalley-typescript.dylib"),
    path.join(process.cwd(), "libgalley-typescript.so"),
    // also try language-dir relative to this file when run from dist
  ];
  for (const c of cwdCandidates) if (exists(c)) return c;

  // 2) cache dir (same as build.mjs prefix)
  const cacheLib = path.join(defaultCacheDir(), "lib", libFileName());
  if (exists(cacheLib)) return cacheLib;

  // 3) sibling examples/typescript for development
  try {
    const here = path.dirname(fileURLToPath(import.meta.url));
    const devCandidates = [
      path.join(here, "../../examples/typescript", libFileName()),
      path.join(here, "../../../examples/typescript", libFileName()),
    ];
    for (const c of devCandidates) if (exists(c)) return c;
  } catch {
    // ignore URL parsing errors in bundled contexts
  }

  // fallback: let koffi error with cache path
  return cacheLib;
}

// --- loader ------------------------------------------------------------

export function loadLibrary(explicitPath?: string): GalleyFFI {
  const normalizedExplicit = explicitPath ? path.resolve(explicitPath) : undefined;
  if (cached && (!normalizedExplicit || cachedPath === normalizedExplicit)) return cached;

  const libPath = findLibrary(normalizedExplicit);
  if (!exists(libPath)) {
    throw new Error(
      `Galley shared library not found at ${libPath}.\n` +
        `Build it first: npx galley-typescript-bindings <language-dir>\n` +
        `or set GALLEY_LIBRARY_PATH=/path/to/${libFileName()}`,
    );
  }

  const lib = koffi.load(libPath);

  const ffi: GalleyFFI = {
    libPath,
    lib,
    GalleyCOptions: GalleyCOptionsType,

    galley_version: lib.func("str galley_version()"),
    galley_parser_type: lib.func("int64_t galley_parser_type()"),
    galley_error_recovery_mode: lib.func("int64_t galley_error_recovery_mode()"),
    galley_has_ast: lib.func("int galley_has_ast()"),
    galley_has_procedures: lib.func("int galley_has_procedures()"),
    galley_allows_no_ast_tree_procedures: lib.func("int galley_allows_no_ast_tree_procedures()"),
    galley_source_retention_enabled: lib.func("int galley_source_retention_enabled()"),
    galley_has_position_tracking: lib.func("int galley_has_position_tracking()"),
    galley_has_input_streaming: lib.func("int galley_has_input_streaming()"),
    galley_uses_verbatim: lib.func("int galley_uses_verbatim()"),
    galley_stack_overflow_recovery_available: lib.func(
      "int galley_stack_overflow_recovery_available()",
    ),
    galley_symbol_count: lib.func("uint64_t galley_symbol_count()"),
    galley_variable_count: lib.func("uint64_t galley_variable_count()"),
    galley_status_string: lib.func("str galley_status_string(int64_t status)"),

    galley_symbol_name: lib.func(
      "int64_t galley_symbol_name(void *session, uint64_t index, _Out_ void **out_data, _Out_ size_t *out_len)",
    ),
    galley_symbol_is_terminal: lib.func("int galley_symbol_is_terminal(void *session, uint64_t index)"),
    galley_variable_name: lib.func(
      "int64_t galley_variable_name(void *session, uint64_t index, _Out_ void **out_data, _Out_ size_t *out_len)",
    ),

    galley_session_create: lib.func("void *galley_session_create()"),
    galley_session_create_ex: lib.func("void *galley_session_create_ex(GalleyCOptions *options)"),
    galley_session_destroy: lib.func("void galley_session_destroy(void *session)"),
    galley_session_set_message_override: lib.func(
      "int64_t galley_session_set_message_override(void *session, str name, size_t name_len, str message, size_t message_len)",
    ),

    galley_parse_sentinel: lib.func("int64_t galley_parse_sentinel(void *session, str input)"),
    galley_parse: lib.func("int64_t galley_parse(void *session, const void *data, size_t len)"),
    galley_parse_file: lib.func("int64_t galley_parse_file(void *session, str path)"),
    galley_last_position: lib.func(
      "int64_t galley_last_position(void *session, _Out_ uint32_t *out_line, _Out_ uint32_t *out_column)",
    ),

    galley_node_count: lib.func("uint64_t galley_node_count(void *session)"),
    galley_reserve_nodes: lib.func("int64_t galley_reserve_nodes(void *session, uint64_t capacity)"),
    galley_node_capacity: lib.func("uint64_t galley_node_capacity(void *session)"),
    galley_root_node: lib.func("uint64_t galley_root_node(void *session)"),
    galley_node_is_valid: lib.func("int galley_node_is_valid(void *session, uint64_t node)"),
    galley_node_child_count: lib.func("uint32_t galley_node_child_count(void *session, uint64_t node)"),
    galley_node_first_child: lib.func("uint64_t galley_node_first_child(void *session, uint64_t node)"),
    galley_node_last_child: lib.func("uint64_t galley_node_last_child(void *session, uint64_t node)"),
    galley_node_next_sibling: lib.func("uint64_t galley_node_next_sibling(void *session, uint64_t node)"),
    galley_node_prior_sibling: lib.func("uint64_t galley_node_prior_sibling(void *session, uint64_t node)"),
    galley_node_parent: lib.func("uint64_t galley_node_parent(void *session, uint64_t node)"),
    galley_walker_create: lib.func("void *galley_walker_create(void *session, uint64_t node, int skip_semantic_errors)"),
    galley_walker_next: lib.func(
      "int galley_walker_next(void *walker, _Out_ uint64_t *out_node, _Out_ uint32_t *out_depth, _Out_ int *out_is_semantic_error)",
    ),
    galley_walker_skip_children: lib.func("void galley_walker_skip_children(void *walker)"),
    galley_walker_destroy: lib.func("void galley_walker_destroy(void *walker)"),
    galley_node_symbol_name: lib.func(
      "int64_t galley_node_symbol_name(void *session, uint64_t node, _Out_ void **out_data, _Out_ size_t *out_len)",
    ),
    galley_node_text: lib.func(
      "int64_t galley_node_text(void *session, uint64_t node, _Out_ void **out_data, _Out_ size_t *out_len)",
    ),
    galley_node_span: lib.func(
      "int64_t galley_node_span(void *session, uint64_t node, _Out_ uint64_t *out_start, _Out_ uint64_t *out_len)",
    ),
    galley_node_line_column: lib.func(
      "int64_t galley_node_line_column(void *session, uint64_t node, _Out_ uint32_t *out_line, _Out_ uint32_t *out_column)",
    ),
    galley_node_variable_index: lib.func("int64_t galley_node_variable_index(void *session, uint64_t node)"),

    galley_has_diagnostic: lib.func("int galley_has_diagnostic(void *session)"),
    galley_diagnostic_kind: lib.func("int64_t galley_diagnostic_kind(void *session)"),
    galley_diagnostic_message: lib.func("int64_t galley_diagnostic_message(void *session, _Out_ str *out)"),
    galley_diagnostic_message_ansi: lib.func(
      "int64_t galley_diagnostic_message_ansi(void *session, _Out_ str *out)",
    ),
    galley_diagnostic_position: lib.func(
      "int64_t galley_diagnostic_position(void *session, _Out_ uint32_t *out_line, _Out_ uint32_t *out_column)",
    ),
    galley_diagnostic_unexpected_token: lib.func(
      "int64_t galley_diagnostic_unexpected_token(void *session, _Out_ void **out_data, _Out_ size_t *out_len)",
    ),
    galley_diagnostic_expected_count: lib.func("int64_t galley_diagnostic_expected_count(void *session)"),
    galley_diagnostic_expected_at: lib.func(
      "int64_t galley_diagnostic_expected_at(void *session, uint64_t index, _Out_ void **out_data, _Out_ size_t *out_len)",
    ),
    galley_diagnostic_context_count: lib.func("int64_t galley_diagnostic_context_count(void *session)"),
    galley_diagnostic_context_at: lib.func(
      "int64_t galley_diagnostic_context_at(void *session, uint64_t index, _Out_ void **out_data, _Out_ size_t *out_len)",
    ),
    galley_diagnostic_indentation: lib.func(
      "int64_t galley_diagnostic_indentation(void *session, _Out_ uint32_t *out_spaces, _Out_ uint32_t *out_width)",
    ),
    galley_syntax_error_count: lib.func("int64_t galley_syntax_error_count(void *session)"),
    galley_diagnostic_recovery_kind: lib.func("int64_t galley_diagnostic_recovery_kind(void *session)"),
    galley_diagnostic_recovery_terminal: lib.func(
      "int64_t galley_diagnostic_recovery_terminal(void *session, _Out_ void **out_data, _Out_ size_t *out_len)",
    ),
    galley_diagnostic_recovery_resume: lib.func(
      "int64_t galley_diagnostic_recovery_resume(void *session, _Out_ int64_t *out)",
    ),
    galley_diagnostic_recovery_lhs_variable: lib.func(
      "int64_t galley_diagnostic_recovery_lhs_variable(void *session, _Out_ void **out_data, _Out_ size_t *out_len)",
    ),
    galley_diagnostic_recovery_production: lib.func(
      "int64_t galley_diagnostic_recovery_production(void *session, _Out_ void **out_var, _Out_ size_t *out_var_len, _Out_ uint32_t *out_rhs)",
    ),
    galley_diagnostic_recovery_occurrence: lib.func(
      "int64_t galley_diagnostic_recovery_occurrence(void *session, _Out_ void **out_parent, _Out_ size_t *out_parent_len, _Out_ uint32_t *out_rhs, _Out_ uint32_t *out_sym, _Out_ void **out_var, _Out_ size_t *out_var_len)",
    ),

    galley_recorded_diagnostic_count: lib.func("int64_t galley_recorded_diagnostic_count(void *session)"),
    galley_recorded_diagnostic_kind: lib.func(
      "int64_t galley_recorded_diagnostic_kind(void *session, uint64_t diag_index)",
    ),
    galley_recorded_diagnostic_position: lib.func(
      "int64_t galley_recorded_diagnostic_position(void *session, uint64_t diag_index, _Out_ uint32_t *out_line, _Out_ uint32_t *out_column)",
    ),
    galley_recorded_unexpected_token: lib.func(
      "int64_t galley_recorded_unexpected_token(void *session, uint64_t diag_index, _Out_ void **out_data, _Out_ size_t *out_len)",
    ),
    galley_recorded_diagnostic_message: lib.func(
      "int64_t galley_recorded_diagnostic_message(void *session, uint64_t diag_index, _Out_ str *out)",
    ),
    galley_recorded_indentation: lib.func(
      "int64_t galley_recorded_indentation(void *session, uint64_t diag_index, _Out_ uint32_t *out_spaces, _Out_ uint32_t *out_width)",
    ),
    galley_recorded_expected_count: lib.func(
      "int64_t galley_recorded_expected_count(void *session, uint64_t diag_index)",
    ),
    galley_recorded_expected_token: lib.func(
      "int64_t galley_recorded_expected_token(void *session, uint64_t diag_index, uint64_t token_index, _Out_ void **out_data, _Out_ size_t *out_len)",
    ),
    galley_recorded_context_count: lib.func(
      "int64_t galley_recorded_context_count(void *session, uint64_t diag_index)",
    ),
    galley_recorded_context_name: lib.func(
      "int64_t galley_recorded_context_name(void *session, uint64_t diag_index, uint64_t ctx_index, _Out_ void **out_data, _Out_ size_t *out_len)",
    ),
    galley_recorded_recovery_kind: lib.func(
      "int64_t galley_recorded_diagnostic_recovery_kind(void *session, uint64_t diag_index)",
    ),
    galley_recorded_recovery_terminal: lib.func(
      "int64_t galley_recorded_recovery_terminal(void *session, uint64_t diag_index, _Out_ void **out_data, _Out_ size_t *out_len)",
    ),
    galley_recorded_recovery_resume: lib.func(
      "int64_t galley_recorded_recovery_resume(void *session, uint64_t diag_index, _Out_ int64_t *out)",
    ),
    galley_recorded_recovery_lhs_variable: lib.func(
      "int64_t galley_recorded_recovery_lhs_variable(void *session, uint64_t diag_index, _Out_ void **out_data, _Out_ size_t *out_len)",
    ),
    galley_recorded_recovery_production: lib.func(
      "int64_t galley_recorded_recovery_production(void *session, uint64_t diag_index, _Out_ void **out_var, _Out_ size_t *out_var_len, _Out_ uint32_t *out_rhs)",
    ),
    galley_recorded_recovery_occurrence: lib.func(
      "int64_t galley_recorded_recovery_occurrence(void *session, uint64_t diag_index, _Out_ void **out_parent, _Out_ size_t *out_parent_len, _Out_ uint32_t *out_rhs, _Out_ uint32_t *out_sym, _Out_ void **out_var, _Out_ size_t *out_var_len)",
    ),

    galley_tree_append_children: lib.func(
      "int64_t galley_tree_append_children(void *session, uint64_t parent, uint64_t first)",
    ),
    galley_tree_insert_before: lib.func(
      "int64_t galley_tree_insert_before(void *session, uint64_t target, uint64_t first)",
    ),
    galley_tree_insert_after: lib.func(
      "int64_t galley_tree_insert_after(void *session, uint64_t target, uint64_t first)",
    ),
    galley_tree_remove_siblings: lib.func(
      "int64_t galley_tree_remove_siblings(void *session, uint64_t node, size_t count, _Out_ uint64_t *out_head)",
    ),
    galley_tree_remove_self: lib.func(
      "int64_t galley_tree_remove_self(void *session, uint64_t node, _Out_ uint64_t *out_head)",
    ),
    galley_tree_promote_children_over_wrapper: lib.func(
      "int64_t galley_tree_promote_children_over_wrapper(void *session, uint64_t wrapper, _Out_ uint64_t *out_head)",
    ),
    galley_tree_clean_children: lib.func(
      "int64_t galley_tree_clean_children(void *session, uint64_t node, _Out_ uint64_t *out_head)",
    ),
    galley_tree_unlink_wrapper: lib.func("int64_t galley_tree_unlink_wrapper(void *session, uint64_t wrapper)"),
    galley_tree_insert_children_at: lib.func(
      "int64_t galley_tree_insert_children_at(void *session, uint64_t parent, size_t index, uint64_t first)",
    ),
    galley_tree_remove_children_at: lib.func(
      "int64_t galley_tree_remove_children_at(void *session, uint64_t parent, size_t index, size_t count, _Out_ uint64_t *out_head)",
    ),

    galley_install_typescript_dispatch: (() => {
      try {
        return lib.func("void galley_install_typescript_dispatch(void *target)") as unknown as (
          target: unknown,
        ) => void;
      } catch {
        return null;
      }
    })(),

    galley_procedure_session: lib.func("void *galley_procedure_session(void *args)"),
    galley_procedure_current_node: lib.func("uint64_t galley_procedure_current_node(void *args)"),
    galley_procedure_set_current_node: lib.func(
      "void galley_procedure_set_current_node(void *args, uint64_t node)",
    ),
    galley_procedure_drop_self: lib.func("int64_t galley_procedure_drop_self(void *args)"),
    galley_procedure_drop_children: lib.func("int64_t galley_procedure_drop_children(void *args)"),
    galley_procedure_drop_if_empty: lib.func("int64_t galley_procedure_drop_if_empty(void *args)"),
    galley_procedure_replace_with_children: lib.func(
      "int64_t galley_procedure_replace_with_children(void *args)",
    ),
    galley_procedure_context_line: lib.func("uint32_t galley_procedure_context_line(void *args)"),
    galley_procedure_context_column: lib.func(
      "uint32_t galley_procedure_context_column(void *args)",
    ),
    galley_procedure_report_semantic_error: lib.func(
      "int64_t galley_procedure_report_semantic_error(void *args, str message, size_t message_len)",
    ),
    galley_diagnostic_semantic: lib.func(
      "int64_t galley_diagnostic_semantic(void *session, _Out_ void **out_variable, _Out_ size_t *out_variable_len, _Out_ void **out_message, _Out_ size_t *out_message_len)",
    ),
    galley_recorded_semantic: lib.func(
      "int64_t galley_recorded_semantic(void *session, uint64_t diag_index, _Out_ void **out_variable, _Out_ size_t *out_variable_len, _Out_ void **out_message, _Out_ size_t *out_message_len)",
    ),
    galley_semantic_error_count: lib.func("int64_t galley_semantic_error_count(void *session)"),
  };

  cached = ffi;
  cachedPath = libPath;
  return ffi;
}

// Helpers -----------------------------------------------------------------

export function toBigInt(v: bigint | number): bigint {
  return typeof v === "bigint" ? v : BigInt(v);
}

export function isOk(status: bigint | number): boolean {
  const n = typeof status === "bigint" ? status : BigInt(status);
  return n >= 0n;
}

export function toNumber(v: bigint | number): number {
  return typeof v === "bigint" ? Number(v) : v;
}

/** Copy (ptr,len) into Uint8Array owning its bytes. */
export function copyBytes(ptr: bigint, len: bigint | number): Uint8Array {
  const l = typeof len === "bigint" ? Number(len) : len;
  if (ptr === 0n || l === 0) return new Uint8Array(0);
  // koffi.decode with array copies
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const arr = koffi.decode(ptr as any, koffi.array("uint8_t", l)) as Uint8Array;
  // copy to detach from underlying memory that koffi may reuse
  return new Uint8Array(arr);
}

export function copyStringBytes(ptr: bigint, len: bigint | number): string {
  return Buffer.from(copyBytes(ptr, len)).toString("utf-8");
}
