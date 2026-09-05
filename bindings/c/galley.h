/*
 * C application-binary interface for generated Galley parsers.
 *
 * Link against the shared library produced for your language (for example
 * `libgalley-json-c.dylib` / `libgalley-json-c.so`) and include this header.
 * Sessions are not thread-safe: use one session per thread, or guard it
 * externally.
 *
 * Node addresses, text pointers, and diagnostic strings remain valid until
 * the next parse on the same session or session destruction.
 *
 * Scope notes: semantic payloads are unavailable; procedure hooks and
 * error-message hooks are compiled into the library from the consumer's
 * procedures and error-messages files (see the bindings docs).
 */
#ifndef GALLEY_H
#define GALLEY_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Opaque parsing-session handle. */
typedef struct GalleySession GalleySession;

/* Stable node index into a session's AST storage. */
typedef unsigned long long GalleyNodeAddress;

/* Returned by tree queries when no node exists at that position. */
#define GALLEY_INVALID_NODE 0xFFFFFFFFFFFFFFFFULL

/* Status codes returned by galley_parse_sentinel, galley_parse, and the
 * accessor functions. Non-negative values are success and (for parse)
 * carry the number of bytes parsed; negative values are errors. */
enum {
    galley_ok                             = 0,
    galley_error_null_argument            = -1,
    galley_error_syntax                   = -2,
    galley_error_indentation              = -3,
    galley_error_stack_overflow           = -4,
    galley_error_ast_capacity_exceeded    = -5,
    galley_error_unterminated_raw_string  = -6,
    galley_error_out_of_memory            = -7,
    galley_error_internal                 = -8,
    galley_error_no_diagnostic            = -9,
    galley_error_invalid_node             = -10,
    galley_error_io                       = -11,
    galley_error_semantic                 = -12,
};

/* Returns the build-supplied version string of this library. The pointer
 * remains valid for the lifetime of the process. */
const char *galley_version(void);

/* Build-configuration query flags. These describe how the library was
 * generated; several API surfaces degrade gracefully when the matching
 * feature is off (for example node queries when AST construction is
 * disabled). */
enum {
    galley_parser_type_ll = 0,
    galley_parser_type_lr = 1
};

enum {
    galley_recovery_mode_disabled  = 0,
    galley_recovery_mode_automatic = 1,
    galley_recovery_mode_explicit  = 2
};

/* Returns the parser family of this library. */
long long galley_parser_type(void);

/* Returns the generated error-recovery mode. */
long long galley_error_recovery_mode(void);

/* Feature flags: return nonzero when enabled. */
int galley_has_ast(void);                      /* AST construction */
int galley_has_procedures(void);               /* procedure hooks */
int galley_allows_no_ast_tree_procedures(void);/* tree helpers in no-AST mode */
int galley_source_retention_enabled(void);     /* session retains source text */
int galley_has_position_tracking(void);        /* line/column data meaningful */
int galley_has_input_streaming(void);          /* incremental input supported */
int galley_uses_verbatim(void);                /* grammar uses verbatim capture */
int galley_stack_overflow_recovery_available(void); /* platform support */

/* Grammar symbol table: variables and terminals declared by the grammar.
 * Names reference static storage valid for the process lifetime. Index
 * errors return galley_error_invalid_node. */
unsigned long long galley_symbol_count(void);
long long galley_symbol_name(GalleySession *session, unsigned long long index,
                             const char **out_data, size_t *out_len);
int galley_symbol_is_terminal(GalleySession *session, unsigned long long index);
unsigned long long galley_variable_count(void);
long long galley_variable_name(GalleySession *session, unsigned long long index,
                               const char **out_data, size_t *out_len);

/* Creates a parsing session, or returns NULL on initialization failure
 * (most commonly allocation failure). Destroy with
 * galley_session_destroy. */
GalleySession *galley_session_create(void);

/* Session creation options; zero/negative fields select runtime defaults. */
typedef struct GalleyCOptions {
    int max_errors;                        /* default 10 */
    int recovery_window;                   /* default 500 */
    int stack_overflow_recovery;           /* nonzero enables */
    unsigned int syntax_error_stack_depth; /* 0 = generated default */
    int verbosity;                         /* debug-build parse tracing */
    double ast_preallocation_ratio;        /* negative = default (2.0) */
    unsigned long long ast_preallocation_cap; /* 0 = default */
} GalleyCOptions;

/* Creates a parsing session with explicit options. Passing NULL is
 * equivalent to galley_session_create. */
GalleySession *galley_session_create_ex(const GalleyCOptions *options);

/* Destroys a session created by galley_session_create. NULL is ignored. */
void galley_session_destroy(GalleySession *session);

/* Registers one message override: when a syntax-error site's resolution
 * chain contains name (an exact hook name, its variable-level family, or
 * the general "syntax_error"), the site reports message verbatim, taking
 * priority over grammar hooks and the built-in renderer. Both strings are
 * copied; the override persists for the session's lifetime. */
long long galley_session_set_message_override(GalleySession *session,
                                              const char *name, size_t name_len,
                                              const char *message, size_t message_len);


/* Parses one NUL-terminated input string. Returns the number of bytes
 * parsed on success, or a negative status code on failure. */
long long galley_parse_sentinel(GalleySession *session, const char *input);

/* Parses a byte buffer that may contain NUL bytes. Same return contract as
 * galley_parse_sentinel. */
long long galley_parse(GalleySession *session, const char *data, size_t len);

/* Parses the file at path. Returns the number of bytes parsed on success;
 * file access failures report galley_error_io. */
long long galley_parse_file(GalleySession *session, const char *path);

/* Writes the end position (1-based line and column) of the most recent
 * successful parse; writes zeros when the parser was built without
 * position tracking. */
long long galley_last_position(GalleySession *session,
                               unsigned int *out_line, unsigned int *out_column);

/* Returns the number of AST nodes allocated by the most recent successful
 * parse. Always 0 when the parser was built without AST construction. */
unsigned long long galley_node_count(GalleySession *session);

/* Preallocates node storage for at least capacity nodes, avoiding growth
 * during subsequent parses. Returns galley_error_ast_capacity_exceeded when
 * the request exceeds the build's node limit. */
long long galley_reserve_nodes(GalleySession *session, unsigned long long capacity);

/* Returns the current node storage capacity in nodes. */
unsigned long long galley_node_capacity(GalleySession *session);

/* Returns the root node address of the most recent successful parse, or
 * GALLEY_INVALID_NODE when there is none. */
GalleyNodeAddress galley_root_node(GalleySession *session);

/* Returns nonzero when address refers to a live node of the most recent
 * parse. */
int galley_node_is_valid(GalleySession *session, GalleyNodeAddress node);

/* Returns the number of direct children of a node, or 0 for invalid
 * nodes. */
unsigned int galley_node_child_count(GalleySession *session, GalleyNodeAddress node);

/* Tree navigation: return GALLEY_INVALID_NODE when the link does not exist
 * (including the root's parent). */
GalleyNodeAddress galley_node_first_child(GalleySession *session, GalleyNodeAddress node);
GalleyNodeAddress galley_node_last_child(GalleySession *session, GalleyNodeAddress node);
GalleyNodeAddress galley_node_next_sibling(GalleySession *session, GalleyNodeAddress node);
GalleyNodeAddress galley_node_prior_sibling(GalleySession *session, GalleyNodeAddress node);
GalleyNodeAddress galley_node_parent(GalleySession *session, GalleyNodeAddress node);

/* Writes the byte offset and length of a node's matched source span into
 * *out_start / *out_len. Offsets index the input of the most recent
 * parse. */
long long galley_node_span(GalleySession *session, GalleyNodeAddress node,
                           unsigned long long *out_start, unsigned long long *out_len);

/* Writes the grammar symbol name of a node (for example "ObjectMembers")
 * into *out_data / *out_len. The pointer references static storage valid
 * for the lifetime of the process. Terminal-only nodes report length 0.
 * Returns galley_ok or galley_error_invalid_node. */
long long galley_node_symbol_name(GalleySession *session, GalleyNodeAddress node,
                                  const char **out_data, size_t *out_len);

/* Returns the raw variable index of a node into the variable list (see
 * galley_variable_name), or -1 when the node has no variable. */
long long galley_node_variable_index(GalleySession *session, GalleyNodeAddress node);

/* Writes the source text matched by a node into *out_data / *out_len. The
 * pointer references the input of the most recent parse: keep that input
 * alive until the next parse (galley_parse_sentinel) or rely on the session,
 * which copies it (galley_parse). During an in-progress parse (procedure
 * hooks) the pointer references the live input of that parse. */
long long galley_node_text(GalleySession *session, GalleyNodeAddress node,
                           const char **out_data, size_t *out_len);

/* Returns nonzero when the previous parse produced a diagnostic. */
int galley_has_diagnostic(GalleySession *session);

/* Writes the rendered diagnostic message (plain text) into *out. The
 * string is NUL-terminated and remains valid until the next parse or
 * session destruction. Returns galley_error_no_diagnostic when the previous
 * parse succeeded. */
long long galley_diagnostic_message(GalleySession *session, const char **out);

/* Writes the 1-based line and column of a diagnostic. Returns
 * galley_error_no_diagnostic when the previous parse succeeded. */
long long galley_diagnostic_position(GalleySession *session,
                                     unsigned int *out_line, unsigned int *out_column);

/* Writes the unexpected token bytes of a syntax diagnostic into *out_data /
 * *out_len. Valid until the next parse. Returns galley_error_no_diagnostic
 * when there is no diagnostic or it is not a syntax error. */
long long galley_diagnostic_unexpected_token(GalleySession *session,
                                             const char **out_data, size_t *out_len);

/* Expected tokens of the current syntax diagnostic: the count, and the
 * token at index (0-based). Pointers reference session-retained state valid
 * until the next parse. Return galley_error_no_diagnostic when there is no
 * syntax diagnostic. */
long long galley_diagnostic_expected_count(GalleySession *session);
long long galley_diagnostic_expected_at(GalleySession *session, unsigned long long index,
                                        const char **out_data, size_t *out_len);

/* Innermost-first "while parsing" variable chain of the current syntax
 * diagnostic: the count, and the variable name at index (0-based). Names
 * reference static grammar storage valid for the process lifetime. */
long long galley_diagnostic_context_count(GalleySession *session);
long long galley_diagnostic_context_at(GalleySession *session, unsigned long long index,
                                       const char **out_data, size_t *out_len);

/* Writes the 1-based line and column of a node's first byte into
 * *out_line / *out_column. Scans the retained input, so cost is linear in
 * the offset. */
long long galley_node_line_column(GalleySession *session, GalleyNodeAddress node,
                                  unsigned int *out_line, unsigned int *out_column);

/* Writes the rendered diagnostic message with ANSI color escapes into *out.
 * Lifetime matches galley_diagnostic_message. */
long long galley_diagnostic_message_ansi(GalleySession *session, const char **out);

/* Tree editing. Chains passed to these functions must be detached orphans
 * (no parent, no prior). Node addresses are stable, so edits never
 * invalidate other addresses. Removed or detached chains remain allocated
 * and readable but are orphaned. */

/* Appends first_node (and its next-chain) as the last children of parent. */
long long galley_tree_append_children(GalleySession *session,
                                      GalleyNodeAddress parent, GalleyNodeAddress first_node);

/* Inserts first_node (and its chain) immediately before/after target among
 * its siblings. */
long long galley_tree_insert_before(GalleySession *session,
                                    GalleyNodeAddress target, GalleyNodeAddress first_node);
long long galley_tree_insert_after(GalleySession *session,
                                   GalleyNodeAddress target, GalleyNodeAddress first_node);

/* Removes count consecutive siblings starting at node (galley_tree_remove),
 * or just node itself (galley_tree_remove_self), detaching them from parent
 * and sibling chains. Writes the address of the first removed node to
 * out_head. */
long long galley_tree_remove_siblings(GalleySession *session, GalleyNodeAddress node,
                                      size_t count, GalleyNodeAddress *out_head);
long long galley_tree_remove_self(GalleySession *session, GalleyNodeAddress node,
                                  GalleyNodeAddress *out_head);

/* Splices the children of wrapper in place of the wrapper among its
 * siblings, writing the promoted chain head to out_head (GALLEY_INVALID_NODE
 * when the wrapper has no children). The wrapper is left detached. */
long long galley_tree_promote_children_over_wrapper(GalleySession *session,
                                                    GalleyNodeAddress wrapper,
                                                    GalleyNodeAddress *out_head);

/* Detaches all children of node, writing the detached chain head to
 * out_head (GALLEY_INVALID_NODE when there are none). */
long long galley_tree_clean_children(GalleySession *session, GalleyNodeAddress node,
                                     GalleyNodeAddress *out_head);

/* Inserts first_node (and its chain) into the children of parent at index.
 * An index equal to the child count appends. */
long long galley_tree_insert_children_at(GalleySession *session, GalleyNodeAddress parent,
                                         size_t index, GalleyNodeAddress first_node);

/* Removes count consecutive children of parent starting at child index,
 * writing the detached chain head to out_head. */
long long galley_tree_remove_children_at(GalleySession *session, GalleyNodeAddress parent,
                                         size_t index, size_t count,
                                         GalleyNodeAddress *out_head);

/* Detaches wrapper from its parent and sibling chains without touching its
 * children. */
long long galley_tree_unlink_wrapper(GalleySession *session, GalleyNodeAddress wrapper);

/* Renders a status code as a static, NUL-terminated description, or NULL
 * when the code is unknown. The returned pointer remains valid for the
 * lifetime of the process. */
const char *galley_status_string(long long status);

/* Diagnostic classification and structured recovery information.
 *
 * Kinds and enum values: */
enum {
    galley_diagnostic_kind_none        = 0,
    galley_diagnostic_kind_syntax      = 1,
    galley_diagnostic_kind_indentation = 2,
    galley_diagnostic_kind_semantic    = 3
};

enum {
    galley_recovery_target_none        = 0,
    galley_recovery_target_lhs_variable = 1,
    galley_recovery_target_production  = 2,
    galley_recovery_target_occurrence  = 3
};

enum {
    galley_resume_before = 0,
    galley_resume_after  = 1
};

/* Returns the kind of the current diagnostic (galley_diagnostic_kind_none
 * when the previous parse succeeded). */
long long galley_diagnostic_kind(GalleySession *session);

/* Returns how many syntax errors the most recent recovery-enabled parse
 * recorded. Fail-fast parses report at most one. */
long long galley_syntax_error_count(GalleySession *session);

/* Returns how many semantic errors the most recent parse recorded. */
long long galley_semantic_error_count(GalleySession *session);

/* Writes the variable and message of a semantic diagnostic. Returns
 * galley_error_no_diagnostic when there is no diagnostic or it is not a
 * semantic error. */
long long galley_diagnostic_semantic(GalleySession *session,
                                     const char **out_variable, size_t *out_variable_len,
                                     const char **out_message, size_t *out_message_len);

/* Writes the indentation width and emitted spaces of an indentation
 * diagnostic. Returns galley_error_no_diagnostic when there is no
 * diagnostic or it is not an indentation diagnostic. */
long long galley_diagnostic_indentation(GalleySession *session,
                                        unsigned int *out_spaces,
                                        unsigned int *out_indentation_width);

/* Recovery information attached to the current syntax diagnostic (when the
 * parser was built with error recovery). All accessors return
 * galley_error_no_diagnostic when there is no diagnostic, it is not a
 * syntax error, or the field does not apply to the target kind. */
long long galley_diagnostic_recovery_kind(GalleySession *session);
long long galley_diagnostic_recovery_terminal(GalleySession *session,
                                              const char **out_data, size_t *out_len);
long long galley_diagnostic_recovery_resume(GalleySession *session, long long *out);
long long galley_diagnostic_recovery_lhs_variable(GalleySession *session,
                                                  const char **out_data, size_t *out_len);
long long galley_diagnostic_recovery_production(GalleySession *session,
                                                const char **out_variable, size_t *out_variable_len,
                                                unsigned int *out_rhs_index);
long long galley_diagnostic_recovery_occurrence(GalleySession *session,
                                                const char **out_parent_variable, size_t *out_parent_variable_len,
                                                unsigned int *out_rhs_index, unsigned int *out_symbol_index,
                                                const char **out_variable, size_t *out_variable_len);

/* Recorded diagnostics of the most recent parse. Every diagnostic the parse
 * recorded (bounded by its error limit) stays addressable by diag_index
 * (0-based, in recording order) until the next parse begins. The singular
 * accessors above remain available for the most recent diagnostic.
 *
 * galley_recorded_diagnostic_count returns how many diagnostics were
 * retained; out-of-range indexes return galley_error_no_diagnostic (kind
 * accessors return galley_diagnostic_kind_none /
 * galley_recovery_target_none). */
long long galley_recorded_diagnostic_count(GalleySession *session);

/* Kind, position, unexpected token, and rendered message of a recorded
 * diagnostic; the indentation width and spaces of a recorded indentation
 * diagnostic. Messages use the built-in generic renderer and remain valid
 * until the next parse. */
long long galley_recorded_diagnostic_kind(GalleySession *session, unsigned long long diag_index);
long long galley_recorded_diagnostic_position(GalleySession *session, unsigned long long diag_index,
                                              unsigned int *out_line, unsigned int *out_column);
long long galley_recorded_unexpected_token(GalleySession *session, unsigned long long diag_index,
                                           const char **out_data, size_t *out_len);
long long galley_recorded_diagnostic_message(GalleySession *session, unsigned long long diag_index,
                                             const char **out);
long long galley_recorded_indentation(GalleySession *session, unsigned long long diag_index,
                                      unsigned int *out_spaces, unsigned int *out_indentation_width);
long long galley_recorded_semantic(GalleySession *session, unsigned long long diag_index,
                                   const char **out_variable, size_t *out_variable_len,
                                   const char **out_message, size_t *out_message_len);

/* Expected tokens and "while parsing" context chain of a recorded
 * diagnostic. */
long long galley_recorded_expected_count(GalleySession *session, unsigned long long diag_index);
long long galley_recorded_expected_token(GalleySession *session, unsigned long long diag_index,
                                         unsigned long long token_index,
                                         const char **out_data, size_t *out_len);
long long galley_recorded_context_count(GalleySession *session, unsigned long long diag_index);
long long galley_recorded_context_name(GalleySession *session, unsigned long long diag_index,
                                       unsigned long long context_index,
                                       const char **out_data, size_t *out_len);

/* Recovery information attached to a recorded diagnostic. */
long long galley_recorded_recovery_kind(GalleySession *session, unsigned long long diag_index);
long long galley_recorded_recovery_terminal(GalleySession *session, unsigned long long diag_index,
                                            const char **out_data, size_t *out_len);
long long galley_recorded_recovery_resume(GalleySession *session, unsigned long long diag_index,
                                          long long *out);
long long galley_recorded_recovery_lhs_variable(GalleySession *session, unsigned long long diag_index,
                                                const char **out_data, size_t *out_len);
long long galley_recorded_recovery_production(GalleySession *session, unsigned long long diag_index,
                                              const char **out_variable, size_t *out_variable_len,
                                              unsigned int *out_rhs_index);
long long galley_recorded_recovery_occurrence(GalleySession *session, unsigned long long diag_index,
                                              const char **out_parent_variable, size_t *out_parent_variable_len,
                                              unsigned int *out_rhs_index, unsigned int *out_symbol_index,
                                              const char **out_variable, size_t *out_variable_len);

/* Procedure hooks receive an opaque ProcedureArguments pointer. Tree queries
 * and edits use the session from galley_procedure_session with the ordinary
 * galley_node_* / galley_tree_* functions. The remaining calls below are
 * parse-time state that does not exist on a finished session: the current
 * node, the reducing rule, scanner line/column, and the drop/replace channel
 * (args.node_address). galley_tree_remove_self is not a substitute for
 * galley_procedure_drop_self. */
GalleySession *galley_procedure_session(void *args);
unsigned long long galley_procedure_current_node(void *args);
void galley_procedure_set_current_node(void *args, unsigned long long node);
int galley_procedure_rule_present(void *args);
long long galley_procedure_rule_header(void *args);
long long galley_procedure_rule_rhs_index(void *args);
long long galley_procedure_rule_right_hand_side(void *args, const unsigned short **out_data, size_t *out_len);
long long galley_procedure_rule_rhs_index_slice(void *args, const char **out_data, size_t *out_len);
unsigned int galley_procedure_context_line(void *args);
unsigned int galley_procedure_context_column(void *args);
long long galley_procedure_drop_self(void *args);
long long galley_procedure_drop_children(void *args);
long long galley_procedure_drop_if_empty(void *args);
long long galley_procedure_replace_with_children(void *args);
long long galley_procedure_left_recursive_reduction(void *args);
long long galley_procedure_right_recursive_reduction(void *args);
long long galley_procedure_report_semantic_error(void *args, const char *message, size_t message_len);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* GALLEY_H */
