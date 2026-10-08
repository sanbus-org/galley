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
 * twins, which take no lock. The twins take the same arguments and answer the
 * same statuses as the session calls, apart from the handle (and no
 * galley_error_session_in_use: the door is unshared); the diagnostics twins
 * take no generation. Concurrent use of one session is refused, not
 * serialized: a second caller gets galley_error_session_in_use, so hosts
 * coordinate sharing themselves; independent sessions on independent
 * threads still need no shared state.
 *
 * A node is identified by the parse generation it belongs to as well as its
 * address, and every call that reads or edits one, on either door, takes
 * that generation and returns a status: the core refuses a generation that
 * is not the live tree's (galley_error_stale_tree), so a node of a dead
 * parse is never read, whatever the caller believes about the session. Read
 * the generation once with galley_root_node (session door) or
 * galley_hook_generation (hook door) and keep passing each node's own.
 * The check is one integer comparison and runs in every build.
 *
 * Node addresses, text pointers, input pointers and diagnostic strings
 * remain valid until the next parse on the same session or session
 * destruction; on the hook door, text and input pointers only until the
 * calling hook returns. A host copies them out before it hands anything
 * to its users.
 *
 * A hook is named by its session and a ticket (unsigned long long) the core
 * issues for that one call; the galley_procedure_* functions take the pair and
 * refuse with galley_error_stale_hook once the hook has returned, in every
 * build. Tickets are never reused.
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
 * from a hook's session and ticket with galley_procedure_door. */
typedef struct GalleyHookDoor GalleyHookDoor;

/* Stable node index into a session's AST storage. */
typedef unsigned long long GalleyNodeAddress;

/* Returned by tree queries when no node exists at that position. Every node
 * address and this sentinel are non-negative (INT64_MAX), so a call that
 * returns an address can report a negative status in the same long long. */
#define GALLEY_INVALID_NODE 0x7FFFFFFFFFFFFFFFULL

/* Returned by galley_node_variable_index and written to the snapshot's
 * variable column for a node that has no variable. Non-negative like
 * GALLEY_INVALID_NODE: only statuses are negative. */
#define GALLEY_NO_VARIABLE 0x7FFFFFFFFFFFFFFFLL

/* Status codes returned by galley_parse_sentinel, galley_parse, and the
 * accessor functions. Non-negative values are success and (for parse)
 * carry the number of bytes parsed; negative values are errors.
 *
 * A parse that reports galley_error_syntax or galley_error_semantic may still
 * have published its tree: one that ran to its end with recorded errors
 * (syntax errors the parser recovered from, or only semantic errors) serves
 * that tree through galley_root_node, with the damaged regions flagged as
 * recovered nodes (see GalleyWalkCursor), exactly like a successful parse.
 * Every other failure — an error the parser could not recover from, an
 * indentation or read error, stack overflow, out of memory — publishes
 * nothing. galley_root_node is the probe. */
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
    /* A node, tree edit, snapshot, or walk cursor carries a generation that
     * is not the door's live tree's. On the session door: the session parsed
     * again, the last parse failed and published nothing, or nothing was ever
     * published; re-read the tree with galley_root_node and use its nodes.
     * galley_last_input and galley_last_position follow the published tree the
     * same way. On
     * the hook door (galley_hook_*, galley_procedure_set_current_node): the
     * generation is not the running parse's (galley_hook_generation). Calls
     * on both doors pass the generation they address; the check runs in every
     * build, because it is a lifetime contract, not a misuse check. */
    galley_error_stale_tree               = -14,
    /* A galley_procedure_* call made with the ticket of a hook that has
     * returned: the arguments are valid only while their hook runs. */
    galley_error_stale_hook               = -15,
    /* A hook's dispatch returned nonzero: the parse stopped where the hook ran
     * and published nothing. The diagnostic is of kind
     * galley_diagnostic_kind_hook; the host keeps the cause of the failure. */
    galley_error_hook_failed              = -16,
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
 * galley_hooks_count, and hook the ticket of this call: pass it, with the
 * session, to the galley_procedure_* functions. It names the hook's arguments
 * only until the call returns. Returns zero to let the parse go on. Any other
 * value means the hook failed: the host keeps the cause, the parse stops where
 * the hook ran, publishes nothing, and the parse call returns
 * galley_error_hook_failed. A hook that wants the parse to go on reports a
 * semantic error instead. */
typedef int (*GalleyHookDispatch)(void *handle, unsigned int index, unsigned long long hook);

/* Number of hooks the library forwards: every hook its parser binds, none
 * when procedures are disabled. Hook indexes run 0 .. count-1 and are fixed
 * for the library's lifetime. */
size_t galley_hooks_count(void);

/* Name of hook index, always an identifier: reduction, reduction_<Variable>,
 * reduction_<terminal stem> (reduction_terminal__x123 for "{"),
 * reduction_<Variable>_<RhsIndex>, or hook_<name>. Static storage valid for
 * the process lifetime. NULL and 0 for an index out
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

/* Writes the end position (1-based line and column) of the published parse;
 * writes zeros when the parser was built without position tracking. This one
 * and galley_last_input take no generation: they answer about the published
 * parse, not about a node, and refuse with galley_error_stale_tree whenever
 * nothing is published (before the first parse, after a parse that published
 * nothing, or once a later parse has begun) and with
 * galley_error_session_in_use while a parse is in flight. */
long long galley_last_position(GalleySession *session,
                               unsigned int *out_line, unsigned int *out_column);

/* Post-parse node access. Every call below that reads or edits nodes takes
 * the generation of the tree it addresses and returns a status, so a refusal
 * is never mistaken for an answer:
 *
 *   galley_error_session_in_use  a parse holds the session (hooks use the
 *                                galley_hook_* twins instead)
 *   galley_error_stale_tree      `generation` is not the published tree's:
 *                                reparsed, the last parse failed, or nothing
 *                                was ever published (generation 0 is never
 *                                live)
 *   galley_error_invalid_node    `node` is outside the live tree's storage
 *   galley_error_null_argument   a null session or output
 *
 * The generation check runs in every build: it is the lifetime contract
 * memory-safe hosts depend on, not a misuse check, and it costs one integer
 * comparison per call. Read it from galley_root_node (after a parse) or
 * galley_hook_generation (inside a hook) and pass the node's own thereafter.
 *
 * In a build without AST construction the generation check still comes first:
 * galley_node_count and galley_tree_snapshot answer 0 only for a live
 * generation.
 *
 * Calls that answer with one value (galley_node_count, galley_node_capacity,
 * galley_node_child_count, the five links, galley_node_variable_index) return it directly: a value >= 0
 * is the answer and a negative value is the status. A missing link is
 * GALLEY_INVALID_NODE and a node without a variable is GALLEY_NO_VARIABLE,
 * both real answers. Calls with several results keep out-parameters. */

/* Returns the number of AST nodes of the published tree (0 for a parser built
 * without AST construction), or a negative status. */
long long galley_node_count(GalleySession *session, unsigned long long generation);

/* Preallocates node storage for at least capacity nodes, avoiding growth
 * during subsequent parses. Returns galley_error_ast_capacity_exceeded when
 * the request exceeds the build's node limit. */
long long galley_reserve_nodes(GalleySession *session, unsigned long long capacity);

/* Returns the current node storage capacity in nodes (0 for a parser built
 * without AST construction), or a negative status:
 * galley_error_session_in_use while a parse is in flight,
 * galley_error_null_argument for a NULL session. */
long long galley_node_capacity(GalleySession *session);

/* Writes the root node of the published parse (the most recent success, or
 * failure that ran to its end with recorded errors) to *out_root and
 * the parse generation every node of that tree carries to *out_generation,
 * under one guard, so a caller never pairs a root with another parse's
 * generation. This is the only source of the published generation and the
 * one "is there a tree here" probe:
 *
 *   - nothing published (no parse has published, a later parse has begun, or
 *     a failed parse published nothing): galley_ok with
 *     GALLEY_INVALID_NODE and 0 written. Real generations start at 1, so 0
 *     never matches a live tree.
 *   - published in a parser built without AST construction: galley_ok with
 *     GALLEY_INVALID_NODE (there is no root) and the live generation, so
 *     galley_node_count answers 0 for it after the generation check.
 *   - a parse in flight: galley_error_session_in_use, nothing meaningful
 *     written.
 *   - a null session or output: galley_error_null_argument.
 *
 * The generation reported here is the one every galley_node_* / galley_tree_*
 * call below accepts. */
long long galley_root_node(GalleySession *session,
                           GalleyNodeAddress *out_root,
                           unsigned long long *out_generation);

/* Returns the number of direct children of a node (0 for a leaf), or a
 * negative status. */
long long galley_node_child_count(GalleySession *session,
                                  unsigned long long generation,
                                  GalleyNodeAddress node);

/* Tree navigation: return the linked node's address, or GALLEY_INVALID_NODE
 * when the link does not exist (including the root's parent) — absence is a
 * non-negative, real answer — or a negative status for a refusal. */
long long galley_node_first_child(GalleySession *session,
                                  unsigned long long generation,
                                  GalleyNodeAddress node);
long long galley_node_last_child(GalleySession *session,
                                 unsigned long long generation,
                                 GalleyNodeAddress node);
long long galley_node_next_sibling(GalleySession *session,
                                   unsigned long long generation,
                                   GalleyNodeAddress node);
long long galley_node_prior_sibling(GalleySession *session,
                                    unsigned long long generation,
                                    GalleyNodeAddress node);
long long galley_node_parent(GalleySession *session,
                             unsigned long long generation,
                             GalleyNodeAddress node);

/* The host-owned walk cursor: 40 bytes, no padding, the same layout on
 * every platform. Zero it before the first step (state
 * GALLEY_WALK_STATE_NOT_STARTED), set root (the address from
 * galley_root_node or any node), generation (the one galley_root_node
 * reported; galley_hook_generation inside a hook) and options, then step with
 * galley_walk_next. The cursor holds the whole walk: no native resource is
 * allocated, and there is nothing to destroy. */
typedef struct GalleyWalkCursor {
    unsigned long long generation;   /* parse generation the walk is bound to */
    unsigned long long root;         /* subtree root: steps never leave it */
    unsigned long long current;      /* last yielded node */
    unsigned int depth;              /* depth of current below root */
    unsigned short state;            /* GALLEY_WALK_STATE_* */
    unsigned char options;           /* GALLEY_WALK_SKIP_* bits */
    unsigned char flags;             /* GALLEY_WALK_FLAG_* bits of current */
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

/* Cursor option bits: GALLEY_WALK_SKIP_SEMANTIC_ERRORS prunes subtrees rooted
 * at semantic-error nodes without yielding them, GALLEY_WALK_SKIP_RECOVERED
 * those rooted at recovered nodes (the nodes syntax-error recovery kept in
 * place of damaged input), so a walk with both yields only undamaged,
 * valid nodes. Any other bit is rejected with galley_error_invalid_node. */
enum {
    GALLEY_WALK_SKIP_SEMANTIC_ERRORS = 1,
    GALLEY_WALK_SKIP_RECOVERED       = 2
};

/* Flag bits galley_walk_next records in the cursor for the node it yielded:
 * a hook reported a semantic error on it, or it is a recovered node. A
 * recovered node spans the input recovery skipped: the damaged variable's own
 * node under LL parsing (with the children parsed before the damage), and a
 * placeholder under LR parsing, which builds no node before a rule completes
 * (it carries no children, and no variable under automatic recovery). */
enum {
    GALLEY_WALK_FLAG_SEMANTIC_ERROR = 1,
    GALLEY_WALK_FLAG_RECOVERED      = 2
};

#if defined(__cplusplus)
static_assert(sizeof(GalleyWalkCursor) == 40, "GalleyWalkCursor must be 40 bytes");
#else
_Static_assert(sizeof(GalleyWalkCursor) == 40, "GalleyWalkCursor must be 40 bytes");
#endif

/* Advances cursor to the next node of its subtree in pre-order, writing the
 * position into the cursor (current/depth/state/flags/
 * structure_version). Returns 1 when a node was yielded, 0 when the walk is
 * done — a done cursor keeps returning 0 while its generation is live — or a
 * negative status:
 * galley_error_stale_tree (the cursor's generation is not the session's
 * live tree — it was reparsed, whether or not the walk had finished;
 * recreate the walk),
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
 * reached through the parse's hook door. Same statuses, except that the
 * door is unshared by construction, so it never answers
 * galley_error_session_in_use; the cursor's generation must be this parse's
 * (galley_hook_generation), else galley_error_stale_tree. */
long long galley_hook_walk_next(GalleyHookDoor *door, GalleyWalkCursor *cursor);

/* Writes the byte offset and length of a node's matched source span into
 * *out_start / *out_len. Offsets index the input of the published parse. */
long long galley_node_span(GalleySession *session, unsigned long long generation,
                           GalleyNodeAddress node,
                           unsigned long long *out_start, unsigned long long *out_len);

/* Writes the grammar symbol name of a node (for example "ObjectMembers")
 * into *out_data / *out_len. The pointer references static storage valid
 * for the lifetime of the process. Terminal-only nodes report length 0. */
long long galley_node_symbol_name(GalleySession *session, unsigned long long generation,
                                  GalleyNodeAddress node,
                                  const char **out_data, size_t *out_len);

/* Returns the raw variable index of a node into the variable list (see
 * galley_variable_name), GALLEY_NO_VARIABLE when the node has none, or a
 * negative status. */
long long galley_node_variable_index(GalleySession *session, unsigned long long generation,
                                     GalleyNodeAddress node);

/* Bulk read of the published tree in a single crossing.
 * Writes up to capacity entries of each non-null out array, one entry per
 * node address (address i fills slot i), and returns the total node count
 * (the same value galley_node_count reports for `generation`; 0 without AST
 * construction).
 * A null array skips that column. When capacity is smaller than the count,
 * only the address prefix [0, capacity) is written; call again with larger
 * buffers to get the whole tree. Returns galley_error_null_argument for a
 * null session, and galley_error_stale_tree when a parse ran since the
 * generation was read, so a snapshot never mixes two trees.
 *
 * Columns mirror the per-node accessors: out_parent holds the parent
 * address (GALLEY_INVALID_NODE for the root), out_first_child the first
 * child, out_next the next sibling, out_child_count the direct child
 * count, out_variable the variable index (GALLEY_NO_VARIABLE when the node has none),
 * out_span_start/out_span_len the source span, out_is_semantic_error 1
 * where the node carries a semantic error and out_is_recovered 1 where it is
 * a recovered node (the flags galley_walk_next records in the cursor), else
 * 0. Together parent, first_child, and next describe the whole tree without
 * further calls. */
long long galley_tree_snapshot(GalleySession *session,
                               unsigned long long generation,
                               GalleyNodeAddress *out_parent,
                               GalleyNodeAddress *out_first_child,
                               GalleyNodeAddress *out_next,
                               unsigned int *out_child_count,
                               long long *out_variable,
                               unsigned long long *out_span_start,
                               unsigned long long *out_span_len,
                               int *out_is_semantic_error,
                               int *out_is_recovered,
                               unsigned long long capacity);

/* Writes the source text matched by a node into *out_data / *out_len. The
 * pointer references the input of the most recent parse: keep that input
 * alive until the next parse (galley_parse_sentinel) or rely on the session,
 * which copies it (galley_parse). During an in-progress parse (procedure
 * hooks) the pointer references the live input of that parse and is valid
 * only until the calling hook returns. */
long long galley_node_text(GalleySession *session, unsigned long long generation,
                           GalleyNodeAddress node,
                           const char **out_data, size_t *out_len);

/* Writes the retained input of the published parse into *out_data /
 * *out_len: exactly the parsed bytes (no sentinel or padding) — the buffer
 * that snapshot spans and node texts index. Same lifetime as
 * galley_node_text. Follows the published tree like galley_last_position:
 * galley_error_stale_tree whenever nothing is published (before the first
 * parse included), galley_error_session_in_use while a parse is in flight.
 * Inside a hook use galley_hook_last_input for the live input of the
 * in-progress parse. */
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
long long galley_node_line_column(GalleySession *session, unsigned long long generation,
                                  GalleyNodeAddress node,
                                  unsigned int *out_line, unsigned int *out_column);

/* Writes the rendered diagnostic message with ANSI color escapes into *out.
 * Lifetime matches galley_diagnostic_message. */
long long galley_diagnostic_message_ansi(GalleySession *session, const char **out);

/* Tree editing. Chains passed to these functions must be detached orphans
 * (no parent, no prior). Node addresses are stable, so edits never
 * invalidate other addresses. Removed or detached chains remain allocated
 * and readable but are orphaned. Post-parse edits take the exclusive lock and
 * the same generation gate as every other session-door call:
 * galley_error_session_in_use while a parse is in flight, and
 * galley_error_stale_tree for a generation that is not the published tree's
 * (an address from a dead parse, or a parse-2 address paired with a parse-1
 * generation); hook-time edits use the galley_hook_tree_* twins. Misuse other
 * than an out-of-range index or count (see the calls below) is undefined
 * behavior in release builds; Debug builds check it and abort the process on
 * failure, for every tree edit including insert_before, insert_after and
 * append_children. */

/* The edits that take a second node (append_children, insert_before,
 * insert_after, insert_children_at) take each node's own generation:
 * `generation` is parent's or target's, `first_generation` the chain head's.
 * Both must name the live tree; nodes of two different parses are refused by
 * the core with galley_error_stale_tree, so a host never compares generations
 * across nodes. */

/* Appends first_node (and its next-chain) as the last children of parent. */
long long galley_tree_append_children(GalleySession *session,
                                      unsigned long long generation,
                                      GalleyNodeAddress parent,
                                      unsigned long long first_generation,
                                      GalleyNodeAddress first_node);

/* Inserts first_node (and its chain) immediately before/after target among
 * its siblings. */
long long galley_tree_insert_before(GalleySession *session,
                                    unsigned long long generation,
                                    GalleyNodeAddress target,
                                    unsigned long long first_generation,
                                    GalleyNodeAddress first_node);
long long galley_tree_insert_after(GalleySession *session,
                                   unsigned long long generation,
                                   GalleyNodeAddress target,
                                   unsigned long long first_generation,
                                   GalleyNodeAddress first_node);

/* Removes count consecutive siblings starting at node (galley_tree_remove),
 * or just node itself (galley_tree_remove_self), detaching them from parent
 * and sibling chains. Writes the address of the first removed node to
 * out_head. A count of 0 is a no-op that returns galley_ok with an invalid
 * head; a count larger than the siblings remaining from node returns
 * galley_error_invalid_node in every build. Other misuse is undefined
 * behavior in release builds; Debug builds check it and abort the process
 * on failure. */
long long galley_tree_remove_siblings(GalleySession *session,
                                      unsigned long long generation,
                                      GalleyNodeAddress node,
                                      size_t count, GalleyNodeAddress *out_head);
long long galley_tree_remove_self(GalleySession *session,
                                  unsigned long long generation,
                                  GalleyNodeAddress node,
                                  GalleyNodeAddress *out_head);

/* Detaches all children of node, writing the detached chain head to
 * out_head (GALLEY_INVALID_NODE when there are none). */
long long galley_tree_clean_children(GalleySession *session,
                                     unsigned long long generation,
                                     GalleyNodeAddress node,
                                     GalleyNodeAddress *out_head);

/* Inserts first_node (and its chain) into the children of parent at index.
 * An index equal to the child count appends; a larger index returns
 * galley_error_invalid_node in every build. Other misuse (a chain that is
 * still attached, or that contains parent or one of its ancestors) is
 * undefined behavior in release builds; Debug builds check it and abort the
 * process on failure. */
long long galley_tree_insert_children_at(GalleySession *session,
                                         unsigned long long generation,
                                         GalleyNodeAddress parent, size_t index,
                                         unsigned long long first_generation,
                                         GalleyNodeAddress first_node);

/* Removes count consecutive children of parent starting at child index,
 * writing the detached chain head to out_head. A count of 0 is a no-op that
 * returns galley_ok with an invalid head, whatever the index; an index and
 * count that reach past the last child return galley_error_invalid_node in
 * every build. */
long long galley_tree_remove_children_at(GalleySession *session,
                                         unsigned long long generation,
                                         GalleyNodeAddress parent,
                                         size_t index, size_t count,
                                         GalleyNodeAddress *out_head);

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
    galley_diagnostic_kind_semantic    = 3,
    galley_diagnostic_kind_hook        = 4
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

/* A hook is named by its session and the ticket of its call (see
 * GalleyHookDispatch; a hook compiled into the library receives the same
 * pair). Parse-time tree access does not go through them: take the parse's
 * door with galley_procedure_door and pass that to the galley_hook_* twins
 * below — no session handle, no lock, valid for the whole parse. The calls
 * directly below are per-hook state that does not exist on a finished session
 * or outside their hook: the current node, the reducing rule, scanner
 * line/column, and the drop/replace channel. Every one answers with a status
 * (or, for a value, a result >= 0 and a negative status otherwise) and
 * refuses a ticket whose hook has returned with galley_error_stale_hook;
 * galley_error_null_argument is a NULL session or output. galley_tree_remove_self
 * is not a substitute for galley_procedure_drop_self. */
long long galley_procedure_door(GalleySession *session, unsigned long long hook,
                                GalleyHookDoor **out_door);

/* Writes the parse generation of the parse that owns door to out_generation:
 * the generation of every node its hooks see, and of the tree it publishes
 * if it succeeds (galley_root_node reports it afterwards).
 * Constant for the whole parse; takes no lock. Returns
 * galley_error_null_argument for a NULL door or output. */
long long galley_hook_generation(GalleyHookDoor *door, unsigned long long *out_generation);

/* The hook's current node, or GALLEY_INVALID_NODE when it has none. */
long long galley_procedure_current_node(GalleySession *session, unsigned long long hook);
/* Sets the hook's current node to a node of the parse that owns the hook, or
 * clears it with GALLEY_INVALID_NODE (no generation check). The node goes
 * through the hook door's check: galley_error_stale_tree for a generation that
 * is not that parse's (0 never is), galley_error_invalid_node for an address
 * outside its node storage. A refused call leaves the current node as it was.
 * In a build without AST construction there is no current node: clearing
 * succeeds and any other node is galley_error_invalid_node. */
long long galley_procedure_set_current_node(GalleySession *session, unsigned long long hook,
                                            unsigned long long generation,
                                            GalleyNodeAddress node);
/* 1 when the hook runs for a grammar rule, else 0. */
long long galley_procedure_rule_present(GalleySession *session, unsigned long long hook);
/* galley_error_invalid_node when the hook has no rule. */
long long galley_procedure_rule_header(GalleySession *session, unsigned long long hook);
long long galley_procedure_rule_rhs_index(GalleySession *session, unsigned long long hook);
long long galley_procedure_rule_right_hand_side(GalleySession *session, unsigned long long hook,
                                                const unsigned short **out_data, size_t *out_len);
long long galley_procedure_rule_rhs_index_slice(GalleySession *session, unsigned long long hook,
                                                const char **out_data, size_t *out_len);
/* Scanner line and column during the hook (0 without position tracking). */
long long galley_procedure_context_line(GalleySession *session, unsigned long long hook);
long long galley_procedure_context_column(GalleySession *session, unsigned long long hook);
long long galley_procedure_drop_self(GalleySession *session, unsigned long long hook);
long long galley_procedure_drop_children(GalleySession *session, unsigned long long hook);
long long galley_procedure_drop_if_empty(GalleySession *session, unsigned long long hook);
long long galley_procedure_replace_with_children(GalleySession *session, unsigned long long hook);
long long galley_procedure_left_recursive_reduction(GalleySession *session, unsigned long long hook);
long long galley_procedure_right_recursive_reduction(GalleySession *session, unsigned long long hook);
long long galley_procedure_report_semantic_error(GalleySession *session, unsigned long long hook,
                                                 const char *message, size_t message_len);

/* ---------------------------------------------------------------------------
 * Parse-time hook door: the same node/tree/diagnostic cores as above, reached
 * through the door of the parse instead of a session handle, with the same
 * parameters, returns and generation check as the session twins. The
 * current parse owns the session exclusively, so these take no lock —
 * unshared by construction. A door is the same pointer for every hook of
 * one parse and dies when that parse ends: keep it for the parse, drop it
 * after. Text and
 * input pointers are the exception and are valid only until the hook that
 * made the call returns; diagnostic strings stay valid until the next parse.
 * Post-parse code uses the galley_node_* / galley_tree_* /
 * galley_diagnostic_* session door, which refuses while a parse is in flight
 * with galley_error_session_in_use.
 * ------------------------------------------------------------------------- */

/* Node reads and tree edits: the same parameters and returns as the session
 * twin of the same name, with the door in place of the session — so a call
 * site can switch twins by changing its first argument. Each takes the
 * node's generation and checks it first: galley_error_stale_tree unless it
 * is the generation of the parse that owns the door (generation 0 is never
 * live), galley_error_invalid_node for an address outside that parse's node
 * storage, galley_error_null_argument for a NULL door or output. The door is
 * unshared by construction, so there is no lock and no session-in-use
 * refusal. Read the generation once with galley_hook_generation. Links and
 * counts return a value >= 0 (GALLEY_INVALID_NODE for a missing link) or a
 * negative status; GALLEY_NO_VARIABLE is a variable index answer. */
long long galley_hook_node_child_count(GalleyHookDoor *door, unsigned long long generation, GalleyNodeAddress node);
long long galley_hook_node_first_child(GalleyHookDoor *door, unsigned long long generation, GalleyNodeAddress node);
long long galley_hook_node_last_child(GalleyHookDoor *door, unsigned long long generation, GalleyNodeAddress node);
long long galley_hook_node_next_sibling(GalleyHookDoor *door, unsigned long long generation, GalleyNodeAddress node);
long long galley_hook_node_prior_sibling(GalleyHookDoor *door, unsigned long long generation, GalleyNodeAddress node);
long long galley_hook_node_parent(GalleyHookDoor *door, unsigned long long generation, GalleyNodeAddress node);
long long galley_hook_node_symbol_name(GalleyHookDoor *door, unsigned long long generation, GalleyNodeAddress node,
                                        const char **out_data, size_t *out_len);
/* Text pointers reference the in-flight parse's input and are valid only
 * until the hook that made the call returns. */
long long galley_hook_node_text(GalleyHookDoor *door, unsigned long long generation, GalleyNodeAddress node,
                                const char **out_data, size_t *out_len);
long long galley_hook_node_span(GalleyHookDoor *door, unsigned long long generation, GalleyNodeAddress node,
                                unsigned long long *out_start, unsigned long long *out_len);
long long galley_hook_node_line_column(GalleyHookDoor *door, unsigned long long generation, GalleyNodeAddress node,
                                       unsigned int *out_line, unsigned int *out_column);
long long galley_hook_node_variable_index(GalleyHookDoor *door, unsigned long long generation, GalleyNodeAddress node);
long long galley_hook_last_input(GalleyHookDoor *door, const char **out_data, size_t *out_len);

/* Tree edits; same contracts as the galley_tree_* door (detached-orphan
 * chains, stable addresses). */
long long galley_hook_tree_append_children(GalleyHookDoor *door, unsigned long long generation,
                                           GalleyNodeAddress parent,
                                           unsigned long long first_generation, GalleyNodeAddress first_node);
long long galley_hook_tree_insert_before(GalleyHookDoor *door, unsigned long long generation,
                                         GalleyNodeAddress target,
                                         unsigned long long first_generation, GalleyNodeAddress first_node);
long long galley_hook_tree_insert_after(GalleyHookDoor *door, unsigned long long generation,
                                        GalleyNodeAddress target,
                                        unsigned long long first_generation, GalleyNodeAddress first_node);
long long galley_hook_tree_remove_siblings(GalleyHookDoor *door, unsigned long long generation,
                                           GalleyNodeAddress node, size_t count, GalleyNodeAddress *out_head);
long long galley_hook_tree_remove_self(GalleyHookDoor *door, unsigned long long generation,
                                       GalleyNodeAddress node, GalleyNodeAddress *out_head);
long long galley_hook_tree_clean_children(GalleyHookDoor *door, unsigned long long generation,
                                          GalleyNodeAddress node, GalleyNodeAddress *out_head);
long long galley_hook_tree_insert_children_at(GalleyHookDoor *door, unsigned long long generation,
                                              GalleyNodeAddress parent, size_t index,
                                              unsigned long long first_generation, GalleyNodeAddress first_node);
long long galley_hook_tree_remove_children_at(GalleyHookDoor *door, unsigned long long generation,
                                              GalleyNodeAddress parent, size_t index, size_t count,
                                              GalleyNodeAddress *out_head);
long long galley_hook_tree_snapshot(GalleyHookDoor *door, unsigned long long generation,
                                    GalleyNodeAddress *out_parent,
                                    GalleyNodeAddress *out_first_child,
                                    GalleyNodeAddress *out_next,
                                    unsigned int *out_child_count,
                                    long long *out_variable,
                                    unsigned long long *out_span_start,
                                    unsigned long long *out_span_len,
                                    int *out_is_semantic_error,
                                    int *out_is_recovered,
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
