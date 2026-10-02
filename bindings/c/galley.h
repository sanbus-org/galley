/*
 * C application-binary interface for generated Galley parsers.
 *
 * Link against the shared library produced for your language (for example
 * `libgalley-json-c.dylib` / `libgalley-json-c.so`) and include this header.
 *
 * Two doors, one core: post-parse accessors (galley_node_*, galley_tree_*,
 * galley_diagnostic_*) take a session handle and refuse with
 * galley_error_session_in_use while a parse is in flight; parse-time hook
 * code passes the parse's door (galley_procedure_door) to the galley_hook_*
 * twins, which take no lock. Concurrent use of one session is refused, not
 * serialized: a second caller gets galley_error_session_in_use, so hosts
 * coordinate sharing themselves; independent sessions on independent
 * threads still need no shared state.
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

/* Opaque parse-time door: the live state of one in-flight parse, obtained
 * from a hook's arguments with galley_procedure_door. */
typedef struct GalleyHookDoor GalleyHookDoor;

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
    /* A parse holds the session exclusively; the call is refused rather than
     * queued. Post-parse node/tree/diagnostic accessors return this while a
     * parse is in flight (hook code must use the galley_hook_* door). */
    galley_error_session_in_use           = -13,
    /* A walk cursor addresses a tree that no longer exists: the session was
     * parsed again since the cursor's generation (or never published it), or
     * in a hook the cursor belongs to another parse. Recreate the walk. */
    galley_error_stale_tree               = -14,
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

/* Host hooks. A library built with a host shim forwards its hooks to the
 * host language instead of to C functions; each session carries its own
 * enabled set, callback and handle, so independent sessions hook
 * independently, even across threads and across libraries. Libraries built
 * with C, C++, Rust, or Go hooks report zero hooks. */

/* Called on the parsing thread for each enabled hook. handle is the value
 * given to galley_session_set_hooks, index a hook index below
 * galley_hooks_count, and args the hook's arguments (valid only until the
 * call returns; pass them to the galley_procedure_* functions). */
typedef void (*GalleyHookDispatch)(void *handle, unsigned int index, void *args);

/* Number of hooks the library forwards. Hook indexes run 0 .. count-1 and
 * are fixed for the library's lifetime. */
size_t galley_hooks_count(void);

/* Name of hook index (reduction, reduction_<Variable>, or hook_<name>):
 * static storage valid for the process lifetime. NULL and 0 for an index out
 * of range. The pointer and the length are separate calls so every host
 * reads them as plain scalars. */
const char *galley_hooks_name_data(size_t index);
size_t galley_hooks_name_length(size_t index);

/* Replaces the session's host hook state in one step. enabled holds one
 * byte per hook, galley_hooks_count bytes in all (NULL with a zero count
 * enables none); a nonzero byte routes that hook to dispatch with handle.
 * Unenabled hooks return before any call. Takes the exclusive lease:
 * galley_error_session_in_use while a parse is in flight, so the set a parse
 * runs with is fixed for that parse. NULL enabled with a nonzero count, or a
 * count other than galley_hooks_count, returns galley_error_null_argument.
 * WebAssembly hosts pass a NULL dispatch and provide env.galley_host_dispatch
 * instead. */
long long galley_session_set_hooks(GalleySession *session, GalleyHookDispatch dispatch,
                                   void *handle, const unsigned char *enabled,
                                   size_t enabled_count);


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
/* Post-parse node access. Each call takes the session's read lock: while a
 * parse is in flight they refuse (0 / GALLEY_INVALID_NODE /
 * galley_error_session_in_use), and after a failed parse they refuse with
 * galley_error_invalid_node — last_result went stale. Hooks use the
 * galley_hook_* twins instead. */
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

/* Writes the parse generation of the session's published tree to
 * out_generation: the generation every node of that tree carries, equal to
 * what galley_hook_generation reported while that parse ran. Writes 0 when
 * nothing is published (no parse has succeeded) or the tree is stale (a
 * later parse began); real generations start at 1. Returns
 * galley_error_session_in_use, with 0 written, while a parse is in flight.
 * A node is live on this door exactly when its generation equals this
 * value. */
long long galley_published_generation(GalleySession *session,
                                      unsigned long long *out_generation);

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

/* The host-owned walk cursor: 40 bytes, no padding, the same layout on
 * every platform. Zero it before the first step (state
 * GALLEY_WALK_STATE_NOT_STARTED), set root (galley_root_node or any node),
 * generation (galley_published_generation; galley_hook_generation inside a
 * hook) and options, then step with galley_walk_next. The cursor holds the
 * whole walk: no native resource is allocated, and there is nothing to
 * destroy. */
typedef struct GalleyWalkCursor {
    unsigned long long generation;   /* parse generation the walk is bound to */
    unsigned long long root;         /* subtree root: steps never leave it */
    unsigned long long current;      /* last yielded node */
    unsigned int depth;              /* depth of current below root */
    unsigned short state;            /* GALLEY_WALK_STATE_* */
    unsigned char options;           /* GALLEY_WALK_SKIP_SEMANTIC_ERRORS */
    unsigned char is_semantic_error; /* 1 while current carries a semantic error */
    unsigned long long structure_version; /* stamped per step; re-verifies the
                                             position after structure edits */
} GalleyWalkCursor;

/* Cursor states: 0 not started (next step yields root), 1 yielded, 2 yielded
 * with children pruned, 3 done (every further step returns 0). */
enum {
    GALLEY_WALK_STATE_NOT_STARTED          = 0,
    GALLEY_WALK_STATE_YIELDED              = 1,
    GALLEY_WALK_STATE_YIELDED_SKIP_CHILDREN = 2,
    GALLEY_WALK_STATE_DONE                 = 3
};

/* Cursor option bit 0: prune subtrees rooted at semantic-error nodes
 * without yielding them. Any other bit is rejected with
 * galley_error_invalid_node. */
enum {
    GALLEY_WALK_SKIP_SEMANTIC_ERRORS = 1
};

#if defined(__cplusplus)
static_assert(sizeof(GalleyWalkCursor) == 40, "GalleyWalkCursor must be 40 bytes");
#else
_Static_assert(sizeof(GalleyWalkCursor) == 40, "GalleyWalkCursor must be 40 bytes");
#endif

/* Advances cursor to the next node of its subtree in pre-order, writing the
 * position into the cursor (current/depth/state/is_semantic_error/
 * structure_version). Returns 1 when a node was yielded, 0 when the walk is
 * done — a done cursor keeps returning 0 before any session or generation
 * check — or a negative status:
 * galley_error_stale_tree (the cursor's generation is not the session's
 * live tree — it was reparsed; recreate the walk),
 * galley_error_session_in_use (a parse is in flight),
 * galley_error_invalid_node (malformed cursor bytes, root/current/depth
 * outside the node storage, or a structure edit left current outside the
 * walk's root — removed, or moved elsewhere), or
 * galley_error_null_argument. Skip a yielded node's children by writing
 * state = GALLEY_WALK_STATE_YIELDED_SKIP_CHILDREN; the next step continues
 * with its next sibling. Edits between steps are visible; a step whose
 * position is no longer inside the walk's root (removed, or moved
 * elsewhere) raises invalid node. A step never leaving the walk's root is
 * guaranteed for cursors produced by galley_walk_next / galley_hook_walk_next;
 * a hand-forged cursor is bounds-checked but not otherwise trusted. */
long long galley_walk_next(GalleySession *session, GalleyWalkCursor *cursor);

/* Hook-time twin of galley_walk_next over the in-flight parse's tree,
 * reached through the parse's hook door. Same statuses; the cursor's
 * generation must be this parse's (galley_hook_generation). */
long long galley_hook_walk_next(GalleyHookDoor *door, GalleyWalkCursor *cursor);

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

/* Bulk read of the most recent successful parse in a single crossing.
 * Writes up to capacity entries of each non-null out array, one entry per
 * node address (address i fills slot i), and returns the total node count
 * (the same value galley_node_count reports; 0 without AST construction).
 * A null array skips that column. When capacity is smaller than the count,
 * only the address prefix [0, capacity) is written; call again with larger
 * buffers to get the whole tree. Returns galley_error_null_argument for a
 * null session.
 *
 * Columns mirror the per-node accessors: out_parent holds the parent
 * address (GALLEY_INVALID_NODE for the root), out_first_child the first
 * child, out_next the next sibling, out_child_count the direct child
 * count, out_variable the variable index (-1 when the node has none),
 * out_span_start/out_span_len the source span, out_is_semantic_error 1
 * where the node carries a semantic error (the flag galley_walk_next
 * records in the cursor), else 0. Together parent, first_child, and next
 * describe the whole tree without further calls. */
long long galley_tree_snapshot(GalleySession *session,
                               GalleyNodeAddress *out_parent,
                               GalleyNodeAddress *out_first_child,
                               GalleyNodeAddress *out_next,
                               unsigned int *out_child_count,
                               long long *out_variable,
                               unsigned long long *out_span_start,
                               unsigned long long *out_span_len,
                               int *out_is_semantic_error,
                               unsigned long long capacity);

/* Writes the source text matched by a node into *out_data / *out_len. The
 * pointer references the input of the most recent parse: keep that input
 * alive until the next parse (galley_parse_sentinel) or rely on the session,
 * which copies it (galley_parse). During an in-progress parse (procedure
 * hooks) the pointer references the live input of that parse. */
long long galley_node_text(GalleySession *session, GalleyNodeAddress node,
                           const char **out_data, size_t *out_len);

/* Writes the retained input of the most recent parse into *out_data /
 * *out_len: exactly the parsed bytes (no sentinel or padding) — the buffer
 * that snapshot spans and node texts index. Same lifetime as
 * galley_node_text. Empty (length 0) before the first parse.
 * During an in-progress parse (procedure hooks) it references the live
 * input of that parse. */
long long galley_last_input(GalleySession *session,
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
 * and readable but are orphaned. Post-parse edits take the exclusive lock:
 * galley_error_session_in_use while a parse is in flight,
 * galley_error_invalid_node for an address from a dead parse; hook-time
 * edits use the galley_hook_tree_* twins. */

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
 * Post-parse accessors take the session's read lock without a generation
 * check: diagnostics outlive the parse that produced them (including a
 * failed one), but a call during an in-flight parse refuses with
 * galley_error_session_in_use. Hooks use the galley_hook_* twins.
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
long long galley_recorded_diagnostic_recovery_kind(GalleySession *session, unsigned long long diag_index);
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

/* Procedure hooks receive an opaque ProcedureArguments pointer, valid only
 * while that hook runs. Parse-time tree access does not go through it: take
 * the parse's door with galley_procedure_door and pass that to the
 * galley_hook_* twins below — no session handle, no lock, valid for the
 * whole parse. The calls directly below are per-hook state that does not
 * exist on a finished session or outside their hook: the current node, the
 * reducing rule, scanner line/column, and the drop/replace channel
 * (args.node_address). galley_tree_remove_self is not a substitute for
 * galley_procedure_drop_self. */
GalleyHookDoor *galley_procedure_door(void *args);

/* Writes the parse generation of the parse that owns door to out_generation:
 * the generation of every node its hooks see, and of the tree it publishes
 * if it succeeds (galley_published_generation reports it afterwards).
 * Constant for the whole parse; takes no lock. Returns
 * galley_error_null_argument for a NULL door or output. */
long long galley_hook_generation(GalleyHookDoor *door, unsigned long long *out_generation);
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

/* ---------------------------------------------------------------------------
 * Parse-time hook door: the same node/tree/diagnostic cores as above, reached
 * through the door of the parse instead of a session handle. The current
 * parse owns the session exclusively, so these take no lock — unshared by
 * construction. A door is the same pointer for every hook of one parse and
 * dies when that parse ends: keep it for the parse, drop it after. Text and
 * input pointers are the exception and are valid only until the hook that
 * made the call returns; diagnostic strings stay valid until the next parse.
 * Post-parse code uses the galley_node_* / galley_tree_* /
 * galley_diagnostic_* session door, which refuses while a parse is in flight
 * with galley_error_session_in_use.
 * ------------------------------------------------------------------------- */

/* Node reads. */
int galley_hook_node_is_valid(GalleyHookDoor *door, GalleyNodeAddress node);
unsigned int galley_hook_node_child_count(GalleyHookDoor *door, GalleyNodeAddress node);
GalleyNodeAddress galley_hook_node_first_child(GalleyHookDoor *door, GalleyNodeAddress node);
GalleyNodeAddress galley_hook_node_last_child(GalleyHookDoor *door, GalleyNodeAddress node);
GalleyNodeAddress galley_hook_node_next_sibling(GalleyHookDoor *door, GalleyNodeAddress node);
GalleyNodeAddress galley_hook_node_prior_sibling(GalleyHookDoor *door, GalleyNodeAddress node);
GalleyNodeAddress galley_hook_node_parent(GalleyHookDoor *door, GalleyNodeAddress node);
long long galley_hook_node_symbol_name(GalleyHookDoor *door, GalleyNodeAddress node,
                                        const char **out_data, size_t *out_len);
long long galley_hook_node_text(GalleyHookDoor *door, GalleyNodeAddress node,
                                const char **out_data, size_t *out_len);
long long galley_hook_node_span(GalleyHookDoor *door, GalleyNodeAddress node,
                                unsigned long long *out_start, unsigned long long *out_len);
long long galley_hook_node_line_column(GalleyHookDoor *door, GalleyNodeAddress node,
                                       unsigned int *out_line, unsigned int *out_column);
long long galley_hook_node_variable_index(GalleyHookDoor *door, GalleyNodeAddress node);
long long galley_hook_last_input(GalleyHookDoor *door, const char **out_data, size_t *out_len);

/* Tree edits; same contracts as the galley_tree_* door (detached-orphan
 * chains, stable addresses). */
long long galley_hook_tree_append_children(GalleyHookDoor *door,
                                           GalleyNodeAddress parent, GalleyNodeAddress first_node);
long long galley_hook_tree_insert_before(GalleyHookDoor *door,
                                         GalleyNodeAddress target, GalleyNodeAddress first_node);
long long galley_hook_tree_insert_after(GalleyHookDoor *door,
                                        GalleyNodeAddress target, GalleyNodeAddress first_node);
long long galley_hook_tree_remove_siblings(GalleyHookDoor *door, GalleyNodeAddress node,
                                           size_t count, GalleyNodeAddress *out_head);
long long galley_hook_tree_remove_self(GalleyHookDoor *door, GalleyNodeAddress node,
                                       GalleyNodeAddress *out_head);
long long galley_hook_tree_promote_children_over_wrapper(GalleyHookDoor *door,
                                                         GalleyNodeAddress wrapper,
                                                         GalleyNodeAddress *out_head);
long long galley_hook_tree_clean_children(GalleyHookDoor *door, GalleyNodeAddress node,
                                          GalleyNodeAddress *out_head);
long long galley_hook_tree_insert_children_at(GalleyHookDoor *door, GalleyNodeAddress parent,
                                              size_t index, GalleyNodeAddress first_node);
long long galley_hook_tree_remove_children_at(GalleyHookDoor *door, GalleyNodeAddress parent,
                                              size_t index, size_t count,
                                              GalleyNodeAddress *out_head);
long long galley_hook_tree_unlink_wrapper(GalleyHookDoor *door, GalleyNodeAddress wrapper);
long long galley_hook_tree_snapshot(GalleyHookDoor *door,
                                    GalleyNodeAddress *out_parent,
                                    GalleyNodeAddress *out_first_child,
                                    GalleyNodeAddress *out_next,
                                    unsigned int *out_child_count,
                                    long long *out_variable,
                                    unsigned long long *out_span_start,
                                    unsigned long long *out_span_len,
                                    int *out_is_semantic_error,
                                    unsigned long long capacity);

/* Current-diagnostic reads of the in-flight parse (recorded-*
 * accessors are post-parse only and have no hook twin). */
int galley_hook_has_diagnostic(GalleyHookDoor *door);
long long galley_hook_diagnostic_message(GalleyHookDoor *door, const char **out);
long long galley_hook_diagnostic_message_ansi(GalleyHookDoor *door, const char **out);
long long galley_hook_diagnostic_position(GalleyHookDoor *door,
                                          unsigned int *out_line, unsigned int *out_column);
long long galley_hook_diagnostic_unexpected_token(GalleyHookDoor *door,
                                                  const char **out_data, size_t *out_len);
long long galley_hook_diagnostic_expected_count(GalleyHookDoor *door);
long long galley_hook_diagnostic_expected_at(GalleyHookDoor *door, unsigned long long index,
                                             const char **out_data, size_t *out_len);
long long galley_hook_diagnostic_context_count(GalleyHookDoor *door);
long long galley_hook_diagnostic_context_at(GalleyHookDoor *door, unsigned long long index,
                                            const char **out_data, size_t *out_len);
long long galley_hook_diagnostic_kind(GalleyHookDoor *door);
long long galley_hook_syntax_error_count(GalleyHookDoor *door);
long long galley_hook_semantic_error_count(GalleyHookDoor *door);
long long galley_hook_diagnostic_semantic(GalleyHookDoor *door,
                                          const char **out_variable, size_t *out_variable_len,
                                          const char **out_message, size_t *out_message_len);
long long galley_hook_diagnostic_indentation(GalleyHookDoor *door,
                                             unsigned int *out_spaces,
                                             unsigned int *out_indentation_width);
long long galley_hook_diagnostic_recovery_kind(GalleyHookDoor *door);
long long galley_hook_diagnostic_recovery_terminal(GalleyHookDoor *door,
                                                   const char **out_data, size_t *out_len);
long long galley_hook_diagnostic_recovery_resume(GalleyHookDoor *door, long long *out);
long long galley_hook_diagnostic_recovery_lhs_variable(GalleyHookDoor *door,
                                                       const char **out_data, size_t *out_len);
long long galley_hook_diagnostic_recovery_production(GalleyHookDoor *door,
                                                     const char **out_variable, size_t *out_variable_len,
                                                     unsigned int *out_rhs_index);
long long galley_hook_diagnostic_recovery_occurrence(GalleyHookDoor *door,
                                                     const char **out_parent_variable, size_t *out_parent_variable_len,
                                                     unsigned int *out_rhs_index, unsigned int *out_symbol_index,
                                                     const char **out_variable, size_t *out_variable_len);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* GALLEY_H */
