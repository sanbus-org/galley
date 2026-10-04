/* Behavioral tests for the Galley C bindings (`bindings/c/galley.h`).
 *
 * One dependency-free suite for both native legs: the fixture project in
 * bindings/c/test-fixture builds the fixture library from the shared
 * keyvalue grammar and compiles this file as C (test_bindings_c) and as
 * C++ (test_bindings_cpp, via a build-tree copy so the C target keeps
 * compiling as C). Run with ctest from the fixture build directory; the
 * binary prints one line per test and exits nonzero on the first failure
 * count.
 *
 * The suite is hermetic: fixed in-memory inputs only, no files, no
 * working-directory dependence. (File parsing is covered by demo.c.)
 */
#include <galley.h>

#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

static const char *valid_sample = "alpha:12,beta:3";
static const char *broken_sample = "alpha:";
/* Garbage before any symbol: recovery skips it all, so the parse publishes,
 * but there is no tree to hold a root. */
static const char *rootless_sample = "?";
/* Recovery skips `x,beta:` to resynchronize, then `2`: two recovered nodes. */
static const char *recovered_sample = "alpha:x,beta:2";
/* Parses, but a hook reports one semantic error on the Number `2000`. */
static const char *semantic_sample = "alpha:1,beta:2000";
static const char *multi_error_sample = "alpha:13x,beta:,gamma:q";

static int failures = 0;
static int ran = 0;

#define CHECK(condition)                                                     \
    do {                                                                     \
        ++ran;                                                               \
        if (!(condition)) {                                                  \
            ++failures;                                                      \
            printf("not ok %d %s:%d: %s\n", ran, __FILE__, __LINE__, #condition); \
        } else {                                                             \
            printf("ok %d %s\n", ran, #condition);                            \
        }                                                                    \
    } while (0)

/* Unwraps a value-returning call: a negative status fails the check. */
static unsigned long long value_of(long long value) {
    CHECK(value >= 0);
    return value >= 0 ? (unsigned long long)value : 0;
}

static int contains_case_insensitive(const char *haystack, const char *needle) {
    size_t needle_len = strlen(needle);
    for (const char *p = haystack; *p != '\0'; ++p) {
        size_t i = 0;
        while (i < needle_len && p[i] != '\0' &&
               (p[i] | 32) == (needle[i] | 32)) {
            ++i;
        }
        if (i == needle_len) return 1;
    }
    return 0;
}

static GalleySession *make_session(void) {
    const GalleyCOptions options = {
        .max_errors = 10,
    };
    return galley_session_create_ex(&options);
}

/* One error is the limit: the parser raises at its first syntax error
 * instead of recovering from it, so a failing parse publishes nothing. */
static GalleySession *make_strict_session(void) {
    const GalleyCOptions options = {
        .max_errors = 1,
    };
    return galley_session_create_ex(&options);
}

static void test_version(void) {
    const char *version = galley_version();
    CHECK(version != NULL);
    CHECK(version[0] != '\0');
}

static void test_metadata_flags(void) {
    long long parser_type = galley_parser_type();
    CHECK(parser_type == galley_parser_type_ll || parser_type == galley_parser_type_lr);
    long long recovery = galley_error_recovery_mode();
    CHECK(recovery == galley_recovery_mode_disabled ||
          recovery == galley_recovery_mode_automatic ||
          recovery == galley_recovery_mode_explicit);
    CHECK(galley_has_ast() == 0 || galley_has_ast() == 1);
    CHECK(galley_has_procedures() == 0 || galley_has_procedures() == 1);
    CHECK(galley_allows_no_ast_tree_procedures() == 0 ||
          galley_allows_no_ast_tree_procedures() == 1);
    CHECK(galley_source_retention_enabled() == 0 || galley_source_retention_enabled() == 1);
    CHECK(galley_has_position_tracking() == 0 || galley_has_position_tracking() == 1);
    CHECK(galley_has_input_streaming() == 0 || galley_has_input_streaming() == 1);
    CHECK(galley_uses_verbatim() == 0 || galley_uses_verbatim() == 1);
    CHECK(galley_stack_overflow_recovery_available() == 0 ||
          galley_stack_overflow_recovery_available() == 1);
}

static void test_status_strings(void) {
    const char *syntax = galley_status_string(galley_error_syntax);
    CHECK(syntax != NULL);
    CHECK(contains_case_insensitive(syntax, "syntax"));
    CHECK(galley_status_string(999999) == NULL);
}

static void test_session_lifetime(void) {
    GalleySession *session = make_session();
    CHECK(session != NULL);
    galley_session_destroy(session);
    galley_session_destroy(NULL);
    session = galley_session_create_ex(NULL);
    CHECK(session != NULL);
    galley_session_destroy(session);
}

static void test_symbol_table(void) {
    GalleySession *session = make_session();
    unsigned long long count = galley_symbol_count();
    CHECK(count > 0);
    const char *data = NULL;
    size_t len = 0;
    CHECK(galley_symbol_name(session, 0, &data, &len) == galley_ok);
    CHECK(data != NULL && len > 0);
    CHECK(galley_symbol_is_terminal(session, 0) == 0 ||
          galley_symbol_is_terminal(session, 0) == 1);
    CHECK(galley_symbol_name(session, count, &data, &len) != galley_ok);
    CHECK(galley_variable_count() > 0);
    /* Symbol names live in static storage: no session needed. */
    CHECK(galley_symbol_name(NULL, 0, &data, &len) == galley_ok);
    CHECK(data != NULL && len > 0);
    galley_session_destroy(session);
}

static void test_valid_parse(void) {
    GalleySession *session = make_session();
    long long parsed = galley_parse_sentinel(session, valid_sample);
    CHECK(parsed == (long long)strlen(valid_sample));
    unsigned long long generation = 0, count = 0;
    GalleyNodeAddress root = GALLEY_INVALID_NODE;
    CHECK(galley_root_node(session, &root, &generation) == galley_ok);
    count = value_of(galley_node_count(session, generation));
    CHECK(count > 0);
    CHECK(root != GALLEY_INVALID_NODE);
    unsigned int line = 0, column = 0;
    CHECK(galley_last_position(session, &line, &column) == galley_ok);
    /* Matches the demo's file-parse readout (1:17), which the
     * cross-binding parity job covers byte-for-byte. */
    CHECK(line == 1 && column == (unsigned int)strlen(valid_sample) + 2);
    galley_session_destroy(session);
}

static void test_buffer_parse(void) {
    GalleySession *session = make_session();
    /* Exact-length buffer parse matches the sentinel parse. */
    CHECK(galley_parse(session, valid_sample, strlen(valid_sample)) ==
          (long long)strlen(valid_sample));
    /* NUL terminates input like the sentinel: trailing NUL parses the
     * same tree, a mid-input NUL returns the bytes before it. */
    char with_nul[32];
    memcpy(with_nul, valid_sample, strlen(valid_sample) + 1);
    CHECK(galley_parse(session, with_nul, strlen(valid_sample) + 1) ==
          (long long)strlen(valid_sample));
    unsigned long long generation = 0, count = 0;
    GalleyNodeAddress root = GALLEY_INVALID_NODE;
    CHECK(galley_root_node(session, &root, &generation) == galley_ok);
    count = value_of(galley_node_count(session, generation));
    CHECK(count == 38);
    with_nul[8] = '\0';
    CHECK(galley_parse(session, with_nul, strlen(valid_sample) + 1) == 8);
    /* NULL data with nonzero length is a null-argument error. */
    CHECK(galley_parse(session, NULL, 3) == galley_error_null_argument);
    galley_session_destroy(session);
}

/* The walk cursor is host-owned: zero it, bind it to the published
 * generation and any root, then step. Steps end by exhaustion (0), and a
 * done cursor keeps reporting completion; malformed bytes and null
 * arguments are refused instead of ending the walk silently. */
static void test_walker(void) {
    GalleySession *session = make_session();
    CHECK(galley_parse_sentinel(session, valid_sample) >= 0);
    /* 38 nodes allocated, 33 reachable: dropped procedure nodes stay
     * allocated but unreachable (demo prints "38 AST nodes"). */
    unsigned long long generation = 0, count = 0;
    GalleyNodeAddress root = GALLEY_INVALID_NODE;
    CHECK(galley_root_node(session, &root, &generation) == galley_ok);
    count = value_of(galley_node_count(session, generation));
    CHECK(count == 38);
    CHECK(generation >= 1);

    GalleyWalkCursor cursor;
    memset(&cursor, 0, sizeof cursor);
    cursor.generation = generation;
    cursor.root = root;
    unsigned long long visited = 0;
    int saw_root_at_zero = 0;
    long long status = 0;
    while ((status = galley_walk_next(session, &cursor)) == 1) {
        ++visited;
        if (cursor.current == root && cursor.depth == 0) saw_root_at_zero = 1;
        const char *name_data = NULL;
        size_t name_len = 0;
        const char *text_data = NULL;
        size_t text_len = 0;
        if (galley_node_symbol_name(session, generation, cursor.current, &name_data, &name_len) != galley_ok ||
            galley_node_text(session, generation, cursor.current, &text_data, &text_len) != galley_ok) {
            break;
        }
    }
    CHECK(status == 0); /* ended by exhaustion, not by an error */
    CHECK(saw_root_at_zero);
    CHECK(visited == 33);
    CHECK(galley_walk_next(session, &cursor) == 0);
    CHECK(galley_walk_next(session, &cursor) == 0);

    /* Null arguments and malformed cursor bytes are refused, and a failed
     * step leaves the cursor where it was: fixing the bytes walks the whole
     * tree again. The cursor still holds the finished walk; reset it first,
     * because a done cursor answers 0 before any session check. */
    memset(&cursor, 0, sizeof cursor);
    CHECK(galley_walk_next(NULL, &cursor) == galley_error_null_argument);
    CHECK(galley_walk_next(session, NULL) == galley_error_null_argument);
    memset(&cursor, 0, sizeof cursor);
    cursor.generation = generation;
    cursor.root = root;
    cursor.state = 99;
    CHECK(galley_walk_next(session, &cursor) == galley_error_invalid_node);
    cursor.state = GALLEY_WALK_STATE_NOT_STARTED;
    cursor.options = 0x04;
    CHECK(galley_walk_next(session, &cursor) == galley_error_invalid_node);
    cursor.options = 0;
    cursor.root = count;
    CHECK(galley_walk_next(session, &cursor) == galley_error_invalid_node);
    cursor.root = root;
    cursor.state = GALLEY_WALK_STATE_YIELDED;
    cursor.current = count;
    CHECK(galley_walk_next(session, &cursor) == galley_error_invalid_node);

    /* Depth beyond the node count is malformed too: refused before the
     * step could overflow depth + 1 or run an unbounded climb. */
    cursor.current = root;
    cursor.depth = (unsigned int)count;
    CHECK(galley_walk_next(session, &cursor) == galley_error_invalid_node);
    cursor.depth = 0xFFFFFFFFu;
    CHECK(galley_walk_next(session, &cursor) == galley_error_invalid_node);
    cursor.depth = 0;

    cursor.state = GALLEY_WALK_STATE_NOT_STARTED;
    cursor.current = 0;
    cursor.depth = 0;
    visited = 0;
    while ((status = galley_walk_next(session, &cursor)) == 1) ++visited;
    CHECK(status == 0);
    CHECK(visited == 33);
    galley_session_destroy(session);
}

/* Skipping children is a host-side state write — no native call. Skipping
 * the root prunes the whole tree; mid-tree it prunes that node's subtree
 * and the walk continues with what would have followed it. */
static void test_walk_skip_children(void) {
    GalleySession *session = make_session();
    CHECK(galley_parse_sentinel(session, valid_sample) >= 0);
    unsigned long long generation = 0;
    GalleyNodeAddress root = GALLEY_INVALID_NODE;
    CHECK(galley_root_node(session, &root, &generation) == galley_ok);

    GalleyWalkCursor cursor;
    memset(&cursor, 0, sizeof cursor);
    cursor.generation = generation;
    cursor.root = root;
    CHECK(galley_walk_next(session, &cursor) == 1);
    CHECK(cursor.current == root && cursor.depth == 0);
    cursor.state = GALLEY_WALK_STATE_YIELDED_SKIP_CHILDREN;
    CHECK(galley_walk_next(session, &cursor) == 0);
    CHECK(galley_walk_next(session, &cursor) == 0);

    /* Mid-tree: walk to the first interior node below the root and skip
     * it. Pair nodes always have children here, so one exists. */
    memset(&cursor, 0, sizeof cursor);
    cursor.generation = generation;
    cursor.root = root;
    int found = 0;
    while (galley_walk_next(session, &cursor) == 1) {
        if (cursor.depth >= 1 &&
            value_of(galley_node_first_child(session, generation, cursor.current)) !=
                GALLEY_INVALID_NODE) {
            found = 1;
            break;
        }
    }
    CHECK(found);
    if (found) {
        GalleyNodeAddress interior = cursor.current;
        unsigned interior_depth = cursor.depth;
        GalleyNodeAddress next_sibling =
            value_of(galley_node_next_sibling(session, generation, interior));
        cursor.state = GALLEY_WALK_STATE_YIELDED_SKIP_CHILDREN;
        long long status = galley_walk_next(session, &cursor);
        if (next_sibling != GALLEY_INVALID_NODE) {
            CHECK(status == 1);
            CHECK(cursor.current == next_sibling);
            CHECK(cursor.depth == interior_depth);
        } else {
            CHECK(status == 0);
        }
        while ((status = galley_walk_next(session, &cursor)) == 1) {}
        CHECK(status == 0);
    }
    galley_session_destroy(session);
}

static void test_snapshot(void) {
    GalleySession *session = make_session();
    CHECK(galley_parse_sentinel(session, valid_sample) >= 0);
    unsigned long long generation = 0, count = 0;
    GalleyNodeAddress root = GALLEY_INVALID_NODE;
    CHECK(galley_root_node(session, &root, &generation) == galley_ok);
    count = value_of(galley_node_count(session, generation));
    CHECK(count > 0);
    static GalleyNodeAddress parent[1024];
    static GalleyNodeAddress first_child[1024];
    static GalleyNodeAddress next[1024];
    static unsigned int child_count[1024];
    static long long variable[1024];
    static int is_semantic_error[1024];
    static int is_recovered[1024];
    CHECK(count < 1024);
    CHECK(galley_tree_snapshot(session, generation, parent, first_child, next, child_count,
                                  variable, NULL, NULL, is_semantic_error, is_recovered,
                                  count) == (long long)count);
    CHECK(parent[root] == GALLEY_INVALID_NODE);
    /* Every address and both sentinels are non-negative: only statuses are
     * negative, so a value-returning call can tell them apart. */
    CHECK(GALLEY_INVALID_NODE == 0x7FFFFFFFFFFFFFFFULL);
    CHECK(GALLEY_NO_VARIABLE == 0x7FFFFFFFFFFFFFFFLL);
    /* The variable column and galley_node_variable_index say the same thing
     * for every node, and a node without a variable reads GALLEY_NO_VARIABLE
     * in both. */
    int without_variable = 0;
    for (unsigned long long address = 0; address < count; ++address) {
        CHECK(variable[address] >= 0);
        CHECK(galley_node_variable_index(session, generation, address) == variable[address]);
        if (variable[address] == GALLEY_NO_VARIABLE) ++without_variable;
    }
    CHECK(without_variable > 0);
    /* first_child/next chains from the root revisit every reachable
     * node exactly; orphaned procedure nodes stay out of reach. */
    unsigned long long visited = 0;
    unsigned long long child_sum = 0;
    GalleyNodeAddress stack[1024];
    size_t stack_len = 0;
    stack[stack_len++] = root;
    while (stack_len > 0) {
        GalleyNodeAddress node = stack[--stack_len];
        ++visited;
        child_sum += child_count[node];
        for (GalleyNodeAddress child = first_child[node]; child != GALLEY_INVALID_NODE;
             child = next[child]) {
            stack[stack_len++] = child;
        }
    }
    CHECK(visited == 33);
    CHECK(child_sum == visited - 1);
    /* The snapshot's flag columns read what each cursor step yields, node
     * for node, over the same reachable set. */
    GalleyWalkCursor walk_cursor;
    memset(&walk_cursor, 0, sizeof walk_cursor);
    walk_cursor.generation = generation;
    walk_cursor.root = root;
    long long walk_status = 0;
    while ((walk_status = galley_walk_next(session, &walk_cursor)) == 1) {
        CHECK(((walk_cursor.flags & GALLEY_WALK_FLAG_SEMANTIC_ERROR) != 0) ==
              (is_semantic_error[walk_cursor.current] != 0));
        CHECK(((walk_cursor.flags & GALLEY_WALK_FLAG_RECOVERED) != 0) ==
              (is_recovered[walk_cursor.current] != 0));
    }
    CHECK(walk_status == 0);
    CHECK(galley_tree_snapshot(NULL, generation, parent, first_child, next, child_count,
                                  NULL, NULL, NULL, is_semantic_error, is_recovered,
                                  count) == galley_error_null_argument);
    galley_session_destroy(session);
}

static void test_syntax_diagnostic(void) {
    GalleySession *session = make_session();
    CHECK(galley_parse_sentinel(session, broken_sample) == galley_error_syntax);
    CHECK(galley_has_diagnostic(session));
    CHECK(galley_diagnostic_kind(session) == galley_diagnostic_kind_syntax);
    unsigned int line = 0, column = 0;
    const char *message = NULL;
    CHECK(galley_diagnostic_position(session, &line, &column) == galley_ok);
    CHECK(line == 1 && column == (unsigned int)strlen(broken_sample) + 1);
    CHECK(galley_diagnostic_message(session, &message) == galley_ok);
    CHECK(message != NULL && message[0] != '\0');
    long long expected_count = galley_diagnostic_expected_count(session);
    CHECK(expected_count > 0);
    const char *token_data = NULL;
    size_t token_len = 0;
    CHECK(galley_diagnostic_expected_at(session, 0, &token_data, &token_len) == galley_ok);
    CHECK(token_data != NULL && token_len > 0);
    CHECK(galley_diagnostic_context_count(session) > 0);
    const char *context_data = NULL;
    size_t context_len = 0;
    CHECK(galley_diagnostic_context_at(session, 0, &context_data, &context_len) == galley_ok);
    CHECK(context_data != NULL && context_len > 0);
    galley_session_destroy(session);
}

static void test_message_override(void) {
    GalleySession *session = make_session();
    const char *override_text = "expected digits here";
    CHECK(galley_session_set_message_override(session, "Number", strlen("Number"),
                                              override_text,
                                              strlen(override_text)) == galley_ok);
    CHECK(galley_parse_sentinel(session, broken_sample) == galley_error_syntax);
    const char *message = NULL;
    CHECK(galley_diagnostic_message(session, &message) == galley_ok);
    CHECK(message != NULL && strstr(message, override_text) != NULL);
    CHECK(galley_session_set_message_override(NULL, "Number", strlen("Number"), override_text,
                                              strlen(override_text)) ==
          galley_error_null_argument);
    galley_session_destroy(session);
}

static void test_recorded_diagnostics(void) {
    GalleySession *session = make_session();
    CHECK(galley_parse_sentinel(session, multi_error_sample) < 0);
    long long recorded = galley_recorded_diagnostic_count(session);
    /* Matches the demo readout (3 records, first at 1:9 near 'x'),
     * which the parity job covers byte-for-byte. */
    CHECK(recorded == 3);
    CHECK(galley_recorded_diagnostic_kind(session, 0) == galley_diagnostic_kind_syntax);
    unsigned int line = 0, column = 0;
    CHECK(galley_recorded_diagnostic_position(session, 0, &line, &column) == galley_ok);
    CHECK(line == 1 && column == 9);
    const char *unexpected_data = NULL;
    size_t unexpected_len = 0;
    CHECK(galley_recorded_unexpected_token(session, 0, &unexpected_data,
                                           &unexpected_len) == galley_ok);
    CHECK(unexpected_len == 1 && unexpected_data[0] == 'x');
    const char *message = NULL;
    CHECK(galley_recorded_diagnostic_message(session, 0, &message) == galley_ok);
    CHECK(message != NULL && message[0] != '\0');
    CHECK(galley_recorded_diagnostic_kind(session, (unsigned long long)recorded) ==
          galley_diagnostic_kind_none);
    galley_session_destroy(session);
}

static void test_semantic_error(void) {
    GalleySession *session = make_session();
    CHECK(galley_parse_sentinel(session, "alpha:1,beta:2000") == galley_error_semantic);
    CHECK(galley_has_diagnostic(session));
    CHECK(galley_diagnostic_kind(session) == galley_diagnostic_kind_semantic);
    CHECK(galley_semantic_error_count(session) == 1);
    const char *variable = NULL;
    size_t variable_len = 0;
    const char *message = NULL;
    size_t message_len = 0;
    CHECK(galley_diagnostic_semantic(session, &variable, &variable_len,
                                     &message, &message_len) == galley_ok);
    CHECK(variable_len == strlen("Number") && memcmp(variable, "Number", variable_len) == 0);
    CHECK(message_len == strlen("value out of range") &&
          memcmp(message, "value out of range", message_len) == 0);
    /* In-range values parse cleanly with no diagnostic. */
    CHECK(galley_parse_sentinel(session, valid_sample) >= 0);
    CHECK(!galley_has_diagnostic(session));
    galley_session_destroy(session);
}

static void test_error_paths(void) {
    GalleySession *session = make_session();
    CHECK(galley_parse_sentinel(NULL, valid_sample) == galley_error_null_argument);
    CHECK(galley_parse_sentinel(session, NULL) == galley_error_null_argument);
    unsigned long long generation = 0, count = 0;
    GalleyNodeAddress root = GALLEY_INVALID_NODE;
    CHECK(galley_node_count(NULL, 0) == galley_error_null_argument);
    CHECK(galley_root_node(NULL, &root, &generation) == galley_error_null_argument);
    CHECK(galley_root_node(session, NULL, &generation) == galley_error_null_argument);
    CHECK(galley_root_node(session, &root, NULL) == galley_error_null_argument);
    CHECK(galley_parse_sentinel(session, valid_sample) >= 0);
    CHECK(galley_root_node(session, &root, &generation) == galley_ok);
    count = value_of(galley_node_count(session, generation));
    GalleyNodeAddress bogus = count + 1000;
    CHECK(galley_node_child_count(session, generation, bogus) == galley_error_invalid_node);
    CHECK(galley_node_first_child(session, generation, bogus) == galley_error_invalid_node);
    const char *data = NULL;
    size_t len = 0;
    CHECK(galley_node_symbol_name(session, generation, bogus, &data, &len) ==
          galley_error_invalid_node);
    /* A null session is a null argument on every edit, as the header says. */
    GalleyNodeAddress head = GALLEY_INVALID_NODE;
    CHECK(galley_tree_append_children(NULL, generation, root, root) == galley_error_null_argument);
    CHECK(galley_tree_insert_before(NULL, generation, root, root) == galley_error_null_argument);
    CHECK(galley_tree_insert_after(NULL, generation, root, root) == galley_error_null_argument);
    CHECK(galley_tree_insert_children_at(NULL, generation, root, 0, root) == galley_error_null_argument);
    CHECK(galley_tree_remove_siblings(NULL, generation, root, 1, &head) == galley_error_null_argument);
    CHECK(galley_tree_remove_self(NULL, generation, root, &head) == galley_error_null_argument);
    CHECK(galley_tree_remove_children_at(NULL, generation, root, 0, 1, &head) == galley_error_null_argument);
    CHECK(galley_tree_clean_children(NULL, generation, root, &head) == galley_error_null_argument);
    galley_session_destroy(session);
}

/* Every session-door export that reads or edits nodes, in one place: with
 * `generation` each answers `status`. A new export joins this list, so no call
 * can ship without its generation refusal being exercised. */
static void check_every_call(GalleySession *session, unsigned long long generation,
                             GalleyNodeAddress node, long long status) {
    const char *data = NULL;
    size_t len = 0;
    unsigned long long span_start = 0, span_length = 0;
    unsigned int line = 0, column = 0;
    GalleyNodeAddress head = GALLEY_INVALID_NODE;
    CHECK(galley_node_count(session, generation) == status);
    CHECK(galley_node_child_count(session, generation, node) == status);
    CHECK(galley_node_first_child(session, generation, node) == status);
    CHECK(galley_node_last_child(session, generation, node) == status);
    CHECK(galley_node_next_sibling(session, generation, node) == status);
    CHECK(galley_node_prior_sibling(session, generation, node) == status);
    CHECK(galley_node_parent(session, generation, node) == status);
    CHECK(galley_node_variable_index(session, generation, node) == status);
    CHECK(galley_node_span(session, generation, node, &span_start, &span_length) == status);
    CHECK(galley_node_symbol_name(session, generation, node, &data, &len) == status);
    CHECK(galley_node_text(session, generation, node, &data, &len) == status);
    CHECK(galley_node_line_column(session, generation, node, &line, &column) == status);
    CHECK(galley_tree_snapshot(session, generation, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
                               NULL, NULL, 0) == status);
    CHECK(galley_tree_append_children(session, generation, node, node) == status);
    CHECK(galley_tree_insert_before(session, generation, node, node) == status);
    CHECK(galley_tree_insert_after(session, generation, node, node) == status);
    CHECK(galley_tree_insert_children_at(session, generation, node, 0, node) == status);
    CHECK(galley_tree_remove_siblings(session, generation, node, 1, &head) == status);
    CHECK(galley_tree_remove_self(session, generation, node, &head) == status);
    CHECK(galley_tree_remove_children_at(session, generation, node, 0, 1, &head) == status);
    CHECK(galley_tree_clean_children(session, generation, node, &head) == status);
}

/* The one generation gate of the session door. `galley_root_node` is the only
 * probe for a published tree, and every read and edit carries the generation
 * it addresses: before a parse, with generation 0, and with a generation a
 * later parse retired, the gate refuses with stale tree instead of answering.
 * No refusal is spelled as a value any more. */
static void test_published_result_gate(void) {
    GalleySession *session = make_strict_session();
    const char *data = NULL;
    size_t len = 0;
    unsigned long long generation = 99, count = 99;
    GalleyNodeAddress root = 0;

    /* Nothing published: root reports it as an answer, and generation 0 —
     * which is never live — is stale on every call. */
    CHECK(galley_root_node(session, &root, &generation) == galley_ok);
    CHECK(root == GALLEY_INVALID_NODE && generation == 0);
    check_every_call(session, 0, 0, galley_error_stale_tree);

    CHECK(galley_parse_sentinel(session, valid_sample) >= 0);
    CHECK(galley_root_node(session, &root, &generation) == galley_ok);
    CHECK(root != GALLEY_INVALID_NODE);
    const unsigned long long first_generation = generation;
    const GalleyNodeAddress first_root = root;
    CHECK(first_generation >= 1);
    CHECK(galley_node_text(session, first_generation, first_root, &data, &len) == galley_ok);
    /* Generation 0 is never live, even with a tree published. */
    check_every_call(session, 0, first_root, galley_error_stale_tree);

    /* A parse that really throws (the parser may not recover from it)
     * publishes nothing: the tree is gone and its generation is stale, and
     * root says so. */
    CHECK(galley_parse_sentinel(session, broken_sample) < 0);
    CHECK(galley_root_node(session, &root, &generation) == galley_ok);
    CHECK(root == GALLEY_INVALID_NODE && generation == 0);
    check_every_call(session, first_generation, first_root, galley_error_stale_tree);

    /* So is a successful parse: the parse-1 generation is refused on every
     * read, link and edit, whatever the address. */
    CHECK(galley_parse_sentinel(session, valid_sample) >= 0);
    unsigned long long second_generation = 0;
    GalleyNodeAddress second_root = GALLEY_INVALID_NODE;
    CHECK(galley_root_node(session, &second_root, &second_generation) == galley_ok);
    CHECK(second_generation > first_generation);
    /* The parse reuses the same addresses, so only the generation tells the
     * two trees apart. */
    CHECK(second_root == first_root);
    check_every_call(session, first_generation, first_root, galley_error_stale_tree);
    /* The live generation reads the very same addresses. */
    CHECK(galley_node_text(session, second_generation, second_root, &data, &len) ==
          galley_ok);
    count = value_of(galley_node_count(session, second_generation));
    CHECK(count > 0);
    galley_session_destroy(session);
}

/* The rendered-message cache belongs to one parse: a later parse — failed or
 * successful — never serves the message of the one before it. */
static void test_diagnostic_cache_follows_the_parse(void) {
    GalleySession *session = make_session();
    const char *message = NULL;
    char first[512];
    CHECK(galley_parse_sentinel(session, "alpha:") < 0);
    CHECK(galley_diagnostic_message(session, &message) == galley_ok);
    snprintf(first, sizeof first, "%s", message);
    CHECK(galley_parse_sentinel(session, "alpha:12,beta:") < 0);
    CHECK(galley_diagnostic_message(session, &message) == galley_ok);
    CHECK(strcmp(first, message) != 0);
    CHECK(galley_parse_sentinel(session, valid_sample) >= 0);
    CHECK(galley_diagnostic_message(session, &message) == galley_error_no_diagnostic);
    galley_session_destroy(session);
}

typedef struct {
    GalleySession *session;
    const char *message;
    const char *ansi;
    int refused;
    int mismatched;
} CacheReader;

/* Concurrent readers of one session hold the shared door together, so a
 * message already in the cache is never refused as session-in-use. */
static void *read_cached_messages(void *argument) {
    CacheReader *reader = (CacheReader *)argument;
    for (int i = 0; i < 20000; i++) {
        const char *message = NULL;
        const char *ansi = NULL;
        long long status = galley_diagnostic_message(reader->session, &message);
        long long ansi_status = galley_diagnostic_message_ansi(reader->session, &ansi);
        if (status == galley_error_session_in_use || ansi_status == galley_error_session_in_use) {
            reader->refused++;
        } else if (status != galley_ok || ansi_status != galley_ok ||
                   message != reader->message || ansi != reader->ansi) {
            reader->mismatched++;
        }
    }
    return NULL;
}

static void test_cached_diagnostic_serves_concurrent_readers(void) {
    GalleySession *session = make_session();
    const char *message = NULL;
    const char *ansi = NULL;
    CHECK(galley_parse_sentinel(session, broken_sample) < 0);
    CHECK(galley_diagnostic_message(session, &message) == galley_ok);
    CHECK(galley_diagnostic_message_ansi(session, &ansi) == galley_ok);
    CacheReader readers[4];
    pthread_t threads[4];
    for (int i = 0; i < 4; i++) {
        readers[i].session = session;
        readers[i].message = message;
        readers[i].ansi = ansi;
        readers[i].refused = 0;
        readers[i].mismatched = 0;
        CHECK(pthread_create(&threads[i], NULL, read_cached_messages, &readers[i]) == 0);
    }
    for (int i = 0; i < 4; i++) {
        pthread_join(threads[i], NULL);
        CHECK(readers[i].refused == 0);
        CHECK(readers[i].mismatched == 0);
    }
    galley_session_destroy(session);
}

static void test_reserve_nodes(void) {
    GalleySession *session = make_session();
    CHECK(galley_parse_sentinel(session, valid_sample) >= 0);
    unsigned long long generation = 0, count = 0;
    GalleyNodeAddress root = GALLEY_INVALID_NODE;
    CHECK(galley_root_node(session, &root, &generation) == galley_ok);
    count = value_of(galley_node_count(session, generation));
    CHECK(galley_reserve_nodes(session, count) == galley_ok);
    CHECK(galley_node_capacity(session) >= count);
    galley_session_destroy(session);
}

/* The edit gate is the read gate on the exclusive door: a stale generation
 * refuses before the edit reaches storage, and a retired generation never
 * edits the tree that replaced it. */
static void test_tree_edit(void) {
    GalleySession *session = make_session();
    CHECK(galley_parse_sentinel(session, valid_sample) >= 0);
    unsigned long long generation = 0;
    GalleyNodeAddress root = GALLEY_INVALID_NODE;
    CHECK(galley_root_node(session, &root, &generation) == galley_ok);
    unsigned int before = 0;
    before = (unsigned int)value_of(galley_node_child_count(session, generation, root));
    CHECK(before > 0);
    GalleyNodeAddress head = GALLEY_INVALID_NODE;
    CHECK(galley_tree_clean_children(session, generation, root, &head) == galley_ok);
    CHECK(head != GALLEY_INVALID_NODE);
    unsigned int after = 99;
    after = (unsigned int)value_of(galley_node_child_count(session, generation, root));
    CHECK(after == 0);
    CHECK(galley_tree_append_children(session, generation, root, head) == galley_ok);
    after = (unsigned int)value_of(galley_node_child_count(session, generation, root));
    CHECK(after == before);

    /* A reparse retires the generation: both the edit and the read that
     * would prove it landed are refused, so the new tree is untouched. */
    CHECK(galley_parse_sentinel(session, valid_sample) >= 0);
    unsigned long long live = 0;
    GalleyNodeAddress live_root = GALLEY_INVALID_NODE;
    CHECK(galley_root_node(session, &live_root, &live) == galley_ok);
    CHECK(galley_tree_clean_children(session, generation, root, &head) ==
          galley_error_stale_tree);
    unsigned int untouched = 99;
    untouched = (unsigned int)value_of(galley_node_child_count(session, live, live_root));
    CHECK(untouched == before);
    /* Generation 0 is never live, before any parse and after a failed one. */
    CHECK(galley_tree_append_children(session, 0, root, head) == galley_error_stale_tree);
    galley_session_destroy(session);
}

/* An index or count past the end is refused in every build, never read:
 * hosts hand these over unchecked. */
static void test_tree_edit_range(void) {
    GalleySession *session = make_session();
    CHECK(galley_parse_sentinel(session, valid_sample) >= 0);
    unsigned long long generation = 0;
    GalleyNodeAddress root = GALLEY_INVALID_NODE;
    CHECK(galley_root_node(session, &root, &generation) == galley_ok);
    unsigned int before = 0;
    before = (unsigned int)value_of(galley_node_child_count(session, generation, root));
    CHECK(before > 0);
    GalleyNodeAddress head = GALLEY_INVALID_NODE;
    CHECK(galley_tree_clean_children(session, generation, root, &head) == galley_ok);

    /* Insert: the child count is the last valid index. */
    CHECK(galley_tree_insert_children_at(session, generation, root, 1, head) == galley_error_invalid_node);
    CHECK(galley_tree_insert_children_at(session, generation, root, (size_t)-1, head) == galley_error_invalid_node);
    unsigned int after = 99;
    after = (unsigned int)value_of(galley_node_child_count(session, generation, root));
    CHECK(after == 0);
    CHECK(galley_tree_insert_children_at(session, generation, root, 0, head) == galley_ok);
    after = (unsigned int)value_of(galley_node_child_count(session, generation, root));
    CHECK(after == before);

    /* Remove children: the index must be a child, and index plus count must fit. */
    GalleyNodeAddress removed = GALLEY_INVALID_NODE;
    CHECK(galley_tree_remove_children_at(session, generation, root, before, 1, &removed) == galley_error_invalid_node);
    CHECK(galley_tree_remove_children_at(session, generation, root, 0, (size_t)before + 1, &removed) == galley_error_invalid_node);
    CHECK(galley_tree_remove_children_at(session, generation, root, (size_t)-1, 1, &removed) == galley_error_invalid_node);
    CHECK(galley_tree_remove_children_at(session, generation, root, 0, (size_t)-1, &removed) == galley_error_invalid_node);

    /* Remove siblings: the run must end at a sibling. */
    GalleyNodeAddress first = value_of(galley_node_first_child(session, generation, root));
    CHECK(first != GALLEY_INVALID_NODE);
    CHECK(galley_tree_remove_siblings(session, generation, first, (size_t)before + 1, &removed) == galley_error_invalid_node);
    CHECK(galley_tree_remove_siblings(session, generation, first, (size_t)-1, &removed) == galley_error_invalid_node);

    /* A count of 0 removes nothing, whatever the index. */
    removed = 0;
    CHECK(galley_tree_remove_children_at(session, generation, root, (size_t)-1, 0, &removed) == galley_ok);
    CHECK(removed == GALLEY_INVALID_NODE);
    removed = 0;
    CHECK(galley_tree_remove_siblings(session, generation, first, 0, &removed) == galley_ok);
    CHECK(removed == GALLEY_INVALID_NODE);

    after = (unsigned int)value_of(galley_node_child_count(session, generation, root));
    CHECK(after == before);
    galley_session_destroy(session);
}

/* The two doors of the split node/tree API, recorded mid-parse by
 * reduction_Document in the fixture's procedures.c after the stash ran
 * here: the parse-time door reads nodes while the parse holds the lock,
 * the door taken in an earlier hook of the same parse still reads from a
 * later hook, and the session door refuses the same call through the
 * stashed session. */
#ifdef __cplusplus
extern "C" {
#endif
void fixture_stash_session(GalleySession *session);
long long fixture_hook_text_status(void);
long long fixture_hook_range_status(int which);
long long fixture_stashed_kind_status(void);
int fixture_later_hook_shares_door(void);
long long fixture_later_hook_child_count(void);
unsigned long long fixture_hook_generation(void);
int fixture_hook_session_matches(void);
long long fixture_hook_generation_status(void);
unsigned long long fixture_stashed_published_generation(void);
long long fixture_stashed_published_status(void);
GalleyNodeAddress fixture_stashed_root(void);
long long fixture_hook_walk_status(void);
long long fixture_stashed_walk_status(void);
int fixture_hook_walk_count(void);
int fixture_hook_walk_skipped(void);
GalleyNodeAddress fixture_hook_walk_root(void);
GalleyNodeAddress fixture_hook_walk_node(int index);
unsigned fixture_hook_walk_depth(int index);
long long fixture_hook_probe_status(int variant, int call);
int fixture_hook_probe_calls(void);
long long fixture_hook_probe_current(int which);
long long fixture_hook_null_output_status(int call);
void fixture_arm_gate(void);
int fixture_gate_entered(void);
void fixture_release_gate(void);
#ifdef __cplusplus
}
#endif

static void test_hook_door(void) {
    GalleySession *session = make_session();
    fixture_stash_session(session);
    CHECK(galley_parse_sentinel(session, valid_sample) >= 0);
    fixture_stash_session(NULL);
    CHECK(fixture_hook_text_status() == galley_ok);
    /* The hook door range-checks host indexes and counts like the session door. */
    CHECK(fixture_hook_range_status(0) == galley_error_invalid_node);
    CHECK(fixture_hook_range_status(1) == galley_error_invalid_node);
    CHECK(fixture_hook_range_status(2) == galley_error_invalid_node);
    CHECK(fixture_stashed_kind_status() == galley_error_session_in_use);
    /* A hook finds its session from its arguments; NULL arguments find none. */
    CHECK(fixture_hook_session_matches() == 1);
    CHECK(galley_procedure_session(NULL) == NULL);
    CHECK(fixture_later_hook_shares_door() == 1);
    CHECK(fixture_later_hook_child_count() > 0);
    galley_session_destroy(session);
}

/* Every hook-door call that takes a node refuses the way its session twin
 * does, called from a hook of a second parse: the previous parse's
 * generation and generation 0 are stale, an address outside the parse's
 * storage is invalid, a NULL door is a null argument. The probe is the
 * last call, the snapshot, which names no address; the one before it is
 * galley_procedure_set_current_node, which takes the hook arguments (NULL in
 * the null variant). */
static void test_hook_refusals(void) {
    GalleySession *session = make_session();
    CHECK(galley_parse_sentinel(session, valid_sample) >= 0);
    fixture_stash_session(session);
    CHECK(galley_parse_sentinel(session, valid_sample) >= 0);
    fixture_stash_session(NULL);
    CHECK(fixture_hook_generation() >= 2);
    int calls = fixture_hook_probe_calls();
    CHECK(calls > 0);
    for (int call = 0; call < calls; ++call) {
        CHECK(fixture_hook_probe_status(0, call) == galley_error_stale_tree);
        CHECK(fixture_hook_probe_status(1, call) == galley_error_stale_tree);
        if (call == calls - 1)
            CHECK(fixture_hook_probe_status(2, call) >= 0);
        else
            CHECK(fixture_hook_probe_status(2, call) == galley_error_invalid_node);
        CHECK(fixture_hook_probe_status(3, call) == galley_error_null_argument);
    }
    /* Argument errors come before the gate on the hook door too. */
    for (int call = 0; call < 8; ++call)
        CHECK(fixture_hook_null_output_status(call) == galley_error_null_argument);
    /* set_current_node goes through the same gate: the refused calls above
     * left the current node alone, a live node sets, INVALID clears. */
    CHECK(fixture_hook_probe_current(0) == 1);
    CHECK(fixture_hook_probe_current(1) == galley_ok);
    CHECK(fixture_hook_probe_current(2) == 1);
    CHECK(fixture_hook_probe_current(3) == galley_ok);
    CHECK(fixture_hook_probe_current(4) == 1);
    galley_session_destroy(session);
}

/* Argument errors come before the gate: a NULL output pointer is
 * galley_error_null_argument whatever the generation says, as is a NULL
 * session. The snapshot's columns are optional, so it still answers the
 * gate. */
static void test_null_outputs_before_the_gate(void) {
    GalleySession *session = make_session();
    CHECK(galley_parse_sentinel(session, valid_sample) >= 0);
    unsigned long long generation = 0;
    GalleyNodeAddress root = GALLEY_INVALID_NODE;
    CHECK(galley_root_node(session, &root, &generation) == galley_ok);
    unsigned long long stale = generation + 1;
    GalleyNodeAddress head = GALLEY_INVALID_NODE;
    for (unsigned long long attempt = 0; attempt < 2; ++attempt) {
        unsigned long long used = attempt == 0 ? generation : stale;
        CHECK(galley_node_symbol_name(session, used, root, NULL, NULL) == galley_error_null_argument);
        CHECK(galley_node_text(session, used, root, NULL, NULL) == galley_error_null_argument);
        CHECK(galley_node_span(session, used, root, NULL, NULL) == galley_error_null_argument);
        CHECK(galley_node_line_column(session, used, root, NULL, NULL) == galley_error_null_argument);
        CHECK(galley_tree_remove_siblings(session, used, root, 1, NULL) == galley_error_null_argument);
        CHECK(galley_tree_clean_children(session, used, root, NULL) == galley_error_null_argument);
        CHECK(galley_tree_remove_children_at(session, used, root, 0, 1, NULL) == galley_error_null_argument);
    }
    CHECK(galley_tree_remove_siblings(NULL, generation, root, 1, &head) == galley_error_null_argument);
    CHECK(galley_tree_snapshot(session, stale, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 0) ==
          galley_error_stale_tree);
    galley_session_destroy(session);
}

/* The core stamps one generation per parse: the hook door reports it while
 * the parse runs, the session door reports it alongside the root afterwards,
 * and a failed parse publishes nothing. Mid-parse the session door refuses
 * even the probe. */
static void test_generations(void) {
    GalleySession *session = make_strict_session();
    unsigned long long published = 99;
    GalleyNodeAddress root = 0;
    CHECK(galley_root_node(session, &root, &published) == galley_ok);
    CHECK(published == 0 && root == GALLEY_INVALID_NODE);

    fixture_stash_session(session);
    CHECK(galley_parse_sentinel(session, valid_sample) >= 0);
    fixture_stash_session(NULL);
    unsigned long long first = fixture_hook_generation();
    CHECK(fixture_hook_generation_status() == galley_ok);
    CHECK(first >= 1);
    CHECK(fixture_stashed_published_status() == galley_error_session_in_use);
    CHECK(fixture_stashed_published_generation() == 0);
    CHECK(fixture_stashed_root() == GALLEY_INVALID_NODE);
    CHECK(galley_root_node(session, &root, &published) == galley_ok);
    CHECK(published == first);

    fixture_stash_session(session);
    CHECK(galley_parse_sentinel(session, valid_sample) >= 0);
    fixture_stash_session(NULL);
    CHECK(fixture_hook_generation() == first + 1);
    CHECK(galley_root_node(session, &root, &published) == galley_ok);
    CHECK(published == first + 1);

    CHECK(galley_parse_sentinel(session, broken_sample) < 0);
    CHECK(galley_root_node(session, &root, &published) == galley_ok);
    CHECK(published == 0 && root == GALLEY_INVALID_NODE);

    CHECK(galley_hook_generation(NULL, &published) == galley_error_null_argument);
    galley_session_destroy(session);
}

/* A cursor is bound to the parse generation it was created against: once
 * the session parses again — or nothing of that generation is live — the
 * next step reports stale tree, and the host recreates the walk. */
static void test_walk_stale(void) {
    GalleySession *session = make_session();
    GalleyWalkCursor cursor;

    /* No parse has ever published: there is no tree to step over. */
    memset(&cursor, 0, sizeof cursor);
    CHECK(galley_walk_next(session, &cursor) == galley_error_stale_tree);

    CHECK(galley_parse_sentinel(session, valid_sample) >= 0);
    unsigned long long generation = 0;
    GalleyNodeAddress root = GALLEY_INVALID_NODE;
    CHECK(galley_root_node(session, &root, &generation) == galley_ok);
    memset(&cursor, 0, sizeof cursor);
    cursor.generation = generation;
    cursor.root = root;
    CHECK(galley_walk_next(session, &cursor) == 1);

    /* A later successful parse retires the cursor. */
    CHECK(galley_parse_sentinel(session, valid_sample) >= 0);
    CHECK(galley_walk_next(session, &cursor) == galley_error_stale_tree);
    CHECK(galley_walk_next(session, &cursor) == galley_error_stale_tree);

    /* So does a failed one: nothing of the old generation stays live. */
    CHECK(galley_parse_sentinel(session, broken_sample) < 0);
    CHECK(galley_walk_next(session, &cursor) == galley_error_stale_tree);

    /* A cursor that never matched the published tree (generation 0) is
     * stale from the first step. */
    memset(&cursor, 0, sizeof cursor);
    CHECK(galley_parse_sentinel(session, valid_sample) >= 0);
    CHECK(galley_walk_next(session, &cursor) == galley_error_stale_tree);

    /* A finished cursor stays finished: done reports 0 before any session
     * or generation check, so a later parse cannot resurrect the walk as
     * a stale error. */
    unsigned long long live = 0;
    GalleyNodeAddress live_root = GALLEY_INVALID_NODE;
    CHECK(galley_root_node(session, &live_root, &live) == galley_ok);
    memset(&cursor, 0, sizeof cursor);
    cursor.generation = live;
    cursor.root = live_root;
    while (galley_walk_next(session, &cursor) == 1) {
    }
    CHECK(cursor.state == GALLEY_WALK_STATE_DONE);
    CHECK(galley_parse_sentinel(session, valid_sample) >= 0);
    CHECK(galley_walk_next(session, &cursor) == 0);
    CHECK(galley_walk_next(NULL, &cursor) == 0);
    galley_session_destroy(session);
}

/* Removing the yielded node between steps: the next step has no live
 * position to advance from and reports invalid node — again on the step
 * after that, since the cursor never moves past the failure. */
static void test_walk_removed_current(void) {
    GalleySession *session = make_session();
    CHECK(galley_parse_sentinel(session, valid_sample) >= 0);
    unsigned long long generation = 0;
    GalleyNodeAddress root = GALLEY_INVALID_NODE;
    CHECK(galley_root_node(session, &root, &generation) == galley_ok);

    GalleyWalkCursor cursor;
    memset(&cursor, 0, sizeof cursor);
    cursor.generation = generation;
    cursor.root = root;
    /* Walk to the first childless node below the root. */
    int found = 0;
    while (galley_walk_next(session, &cursor) == 1) {
        if (cursor.depth >= 1 &&
            galley_node_first_child(session, generation, cursor.current) ==
                (long long)GALLEY_INVALID_NODE) {
            found = 1;
            break;
        }
    }
    CHECK(found);
    if (found) {
        GalleyNodeAddress leaf = cursor.current;
        GalleyNodeAddress removed_head = GALLEY_INVALID_NODE;
        CHECK(galley_tree_remove_self(session, generation, leaf, &removed_head) == galley_ok);
        CHECK(removed_head == leaf);
        CHECK(galley_walk_next(session, &cursor) == galley_error_invalid_node);
        CHECK(galley_walk_next(session, &cursor) == galley_error_invalid_node);
    }
    galley_session_destroy(session);
}

struct WalkStep {
    GalleyNodeAddress node;
    unsigned depth;
};

/* Steps follow the live links: a node removed between steps disappears
 * from the remainder of the walk, and one re-inserted afterwards rejoins
 * it. */
static void test_walk_sees_edits(void) {
    GalleySession *session = make_session();
    CHECK(galley_parse_sentinel(session, valid_sample) >= 0);
    unsigned long long generation = 0;
    GalleyNodeAddress root = GALLEY_INVALID_NODE;
    CHECK(galley_root_node(session, &root, &generation) == galley_ok);

    struct WalkStep baseline[64];
    int total = 0;
    long long status;
    GalleyWalkCursor cursor;
    memset(&cursor, 0, sizeof cursor);
    cursor.generation = generation;
    cursor.root = root;
    while ((status = galley_walk_next(session, &cursor)) == 1) {
        if (total == 64) break;
        baseline[total].node = cursor.current;
        baseline[total].depth = cursor.depth;
        ++total;
    }
    CHECK(status == 0);
    CHECK(total == 33);

    /* Remove the root's first child between steps. */
    memset(&cursor, 0, sizeof cursor);
    cursor.generation = generation;
    cursor.root = root;
    CHECK(galley_walk_next(session, &cursor) == 1); /* root */
    GalleyNodeAddress removed = value_of(galley_node_first_child(session, generation, root));
    CHECK(removed != GALLEY_INVALID_NODE);
    CHECK(removed == baseline[1].node);
    GalleyNodeAddress removed_head = GALLEY_INVALID_NODE;
    CHECK(galley_tree_remove_self(session, generation, removed, &removed_head) == galley_ok);
    CHECK(removed_head == removed);

    /* The remainder walks the edited tree: everything the removed subtree
     * held — and only that — is gone from the sequence. */
    int skip = 2;
    while (skip < total && baseline[skip].depth > baseline[1].depth) ++skip;
    int walked = 0;
    int identical = 1;
    while ((status = galley_walk_next(session, &cursor)) == 1) {
        if (walked + skip >= total ||
            baseline[skip + walked].node != cursor.current ||
            baseline[skip + walked].depth != cursor.depth) {
            identical = 0;
        }
        ++walked;
    }
    CHECK(status == 0);
    CHECK(identical);
    CHECK(walked == total - skip);

    /* Re-insert the removed subtree: a fresh walk yields the restored
     * count again, including the node that was removed. */
    CHECK(galley_tree_append_children(session, generation, root, removed) == galley_ok);
    memset(&cursor, 0, sizeof cursor);
    cursor.generation = generation;
    cursor.root = root;
    int saw_removed = 0;
    int restored = 0;
    while ((status = galley_walk_next(session, &cursor)) == 1) {
        if (cursor.current == removed) saw_removed = 1;
        ++restored;
    }
    CHECK(status == 0);
    CHECK(restored == total);
    CHECK(saw_removed);
    galley_session_destroy(session);
}

typedef struct {
    GalleySession *session;
    long long parse_status;
} GatedParse;

static void *parse_while_gated(void *argument) {
    GatedParse *gated = (GatedParse *)argument;
    gated->parse_status = galley_parse_sentinel(gated->session, valid_sample);
    return NULL;
}

/* A parse holds the session exclusively for its whole run, hooks included:
 * a step from another thread mid-parse is refused as in-use, and the
 * cursor is stale once that parse publishes a new generation. The wait is
 * bounded — a gate never reached fails instead of hanging. */
static void test_walk_in_use(void) {
    GalleySession *session = make_session();
    CHECK(galley_parse_sentinel(session, valid_sample) >= 0);
    unsigned long long generation = 0;
    GalleyNodeAddress root = GALLEY_INVALID_NODE;
    CHECK(galley_root_node(session, &root, &generation) == galley_ok);

    GalleyWalkCursor cursor;
    memset(&cursor, 0, sizeof cursor);
    cursor.generation = generation;
    cursor.root = root;
    CHECK(galley_walk_next(session, &cursor) == 1);

    fixture_arm_gate();
    GatedParse gated = {session, 0};
    pthread_t parser;
    CHECK(pthread_create(&parser, NULL, parse_while_gated, &gated) == 0);
    struct timespec deadline;
    clock_gettime(CLOCK_MONOTONIC, &deadline);
    deadline.tv_sec += 10;
    int entered = 0;
    while (!entered) {
        entered = fixture_gate_entered();
        if (entered) break;
        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);
        if (now.tv_sec >= deadline.tv_sec) break;
        sched_yield();
    }
    CHECK(entered);
    if (entered) {
        CHECK(galley_walk_next(session, &cursor) == galley_error_session_in_use);
        /* A session-door read is refused the same way mid-parse: the gate
         * reports session in use before it ever compares generations. */
        CHECK(galley_node_child_count(session, generation, root) ==
              galley_error_session_in_use);
        GalleyNodeAddress mid_root = 0;
        unsigned long long mid_generation = 99;
        CHECK(galley_root_node(session, &mid_root, &mid_generation) ==
              galley_error_session_in_use);
    }
    fixture_release_gate();
    CHECK(pthread_join(parser, NULL) == 0);
    CHECK(gated.parse_status >= 0);

    /* The parse it waited for published a new generation: stale now. */
    CHECK(galley_walk_next(session, &cursor) == galley_error_stale_tree);
    CHECK(galley_node_child_count(session, generation, root) ==
          galley_error_stale_tree);
    galley_session_destroy(session);
}

/* Walking inside a hook goes through the parse's own door and sees the
 * in-flight tree: the same walk after the parse publishes reproduces it
 * node for node, while the session door refuses the same step mid-parse. */
static void test_walk_in_hook(void) {
    GalleySession *session = make_session();
    fixture_stash_session(session);
    CHECK(galley_parse_sentinel(session, valid_sample) >= 0);
    fixture_stash_session(NULL);

    CHECK(fixture_stashed_walk_status() == galley_error_session_in_use);
    CHECK(fixture_hook_walk_status() == 0);
    int hook_count = fixture_hook_walk_count();
    CHECK(hook_count > 0);
    CHECK(fixture_hook_walk_skipped() == hook_count); /* no semantic errors here */
    GalleyNodeAddress hook_root = fixture_hook_walk_root();

    unsigned long long generation = 0;
    GalleyNodeAddress root = GALLEY_INVALID_NODE;
    CHECK(galley_root_node(session, &root, &generation) == galley_ok);
    /* The hook's in-flight root is a live node of the published tree, read
     * through the published generation. */
    CHECK(galley_node_child_count(session, generation, hook_root) > 0);
    GalleyWalkCursor cursor;
    memset(&cursor, 0, sizeof cursor);
    cursor.generation = generation;
    cursor.root = hook_root;
    int index = 0;
    int identical = 1;
    long long status;
    while ((status = galley_walk_next(session, &cursor)) == 1) {
        if (index >= hook_count ||
            fixture_hook_walk_node(index) != cursor.current ||
            fixture_hook_walk_depth(index) != cursor.depth) {
            identical = 0;
        }
        ++index;
    }
    CHECK(status == 0);
    CHECK(identical);
    CHECK(index == hook_count);
    galley_session_destroy(session);
}

/* Semantic-error subtrees are marked during the parse, so a hook walking
 * with the prune option skips them where the plain walk yields them. */
static void test_walk_semantic_skip_in_hook(void) {
    GalleySession *session = make_session();
    fixture_stash_session(session);
    CHECK(galley_parse_sentinel(session, "alpha:1,beta:2000") == galley_error_semantic);
    fixture_stash_session(NULL);

    CHECK(fixture_hook_walk_status() == 0);
    int full = fixture_hook_walk_count();
    int pruned = fixture_hook_walk_skipped();
    CHECK(full > 0);
    CHECK(pruned < full); /* the flagged Number subtree was pruned */
    galley_session_destroy(session);
}


/* One walk step, remembered: what the host sees of a node. */
typedef struct {
    char symbol[32];
    unsigned long long start;
    unsigned long long length;
    int flags;
} Visit;

/* Walks the published tree from its root with `options` and records every
 * step; returns the number of steps. */
static int collect_walk(GalleySession *session, unsigned char options, Visit *visits, int capacity) {
    unsigned long long generation = 0;
    GalleyNodeAddress root = GALLEY_INVALID_NODE;
    GalleyWalkCursor cursor;
    int count = 0;
    CHECK(galley_root_node(session, &root, &generation) == galley_ok);
    CHECK(root != GALLEY_INVALID_NODE);
    memset(&cursor, 0, sizeof cursor);
    cursor.generation = generation;
    cursor.root = root;
    cursor.options = options;
    while (galley_walk_next(session, &cursor) == 1 && count < capacity) {
        const char *name = NULL;
        size_t name_length = 0;
        Visit *visit = &visits[count++];
        CHECK(galley_node_symbol_name(session, generation, cursor.current, &name,
                                      &name_length) == galley_ok);
        snprintf(visit->symbol, sizeof visit->symbol, "%.*s", (int)name_length, name);
        CHECK(galley_node_span(session, generation, cursor.current, &visit->start,
                               &visit->length) == galley_ok);
        visit->flags = cursor.flags;
    }
    return count;
}

static int count_flagged(const Visit *visits, int count, int flag) {
    int flagged = 0;
    for (int i = 0; i < count; ++i) {
        if (visits[i].flags & flag) ++flagged;
    }
    return flagged;
}

static const Visit *first_flagged(const Visit *visits, int count, int flag) {
    for (int i = 0; i < count; ++i) {
        if (visits[i].flags & flag) return &visits[i];
    }
    return NULL;
}

/* A parse that fails only with semantic errors parsed its input, so it
 * publishes its tree: the status is still the failure, the walk reports the
 * flagged node, the skip option prunes it, and last_input is that input. */
static void test_semantic_only_failure_publishes(void) {
    static Visit full[256], pruned[256];
    GalleySession *session = make_session();
    CHECK(galley_parse_sentinel(session, semantic_sample) == galley_error_semantic);

    unsigned long long generation = 0;
    GalleyNodeAddress root = GALLEY_INVALID_NODE;
    CHECK(galley_root_node(session, &root, &generation) == galley_ok);
    CHECK(root != GALLEY_INVALID_NODE && generation != 0);

    int full_count = collect_walk(session, 0, full, 256);
    CHECK(count_flagged(full, full_count, GALLEY_WALK_FLAG_SEMANTIC_ERROR) == 1);
    CHECK(count_flagged(full, full_count, GALLEY_WALK_FLAG_RECOVERED) == 0);
    const Visit *marked = first_flagged(full, full_count, GALLEY_WALK_FLAG_SEMANTIC_ERROR);
    CHECK(marked != NULL && strcmp(marked->symbol, "Number") == 0);
    CHECK(marked != NULL && marked->start == 13 && marked->length == 4);

    int pruned_count = collect_walk(session, GALLEY_WALK_SKIP_SEMANTIC_ERRORS, pruned, 256);
    CHECK(count_flagged(pruned, pruned_count, GALLEY_WALK_FLAG_SEMANTIC_ERROR) == 0);
    CHECK(pruned_count < full_count);
    /* Skipping the recovery flag changes nothing here: nothing is recovered. */
    CHECK(collect_walk(session, GALLEY_WALK_SKIP_RECOVERED, pruned, 256) == full_count);

    const char *input = NULL;
    size_t input_length = 0;
    CHECK(galley_last_input(session, &input, &input_length) == galley_ok);
    CHECK(input_length == strlen(semantic_sample) && memcmp(input, semantic_sample, input_length) == 0);
    unsigned int line = 0, column = 0;
    CHECK(galley_last_position(session, &line, &column) == galley_ok);
    CHECK(line == 1 && column == (unsigned int)strlen(semantic_sample) + 2);

    /* The next parse retires the errored tree's nodes. */
    CHECK(galley_parse_sentinel(session, valid_sample) >= 0);
    const char *text = NULL;
    size_t text_length = 0;
    CHECK(galley_node_text(session, generation, root, &text, &text_length) == galley_error_stale_tree);
    galley_session_destroy(session);
}

/* A syntax error the parser recovered from also publishes: the damaged
 * regions are recovered nodes spanning the input recovery skipped, and
 * skipping them leaves only undamaged nodes. */
static void test_recovered_failure_publishes(void) {
    static Visit full[256], pruned[256];
    GalleySession *session = make_session();
    CHECK(galley_parse_sentinel(session, recovered_sample) == galley_error_syntax);

    unsigned long long generation = 0, count = 0;
    GalleyNodeAddress root = GALLEY_INVALID_NODE;
    CHECK(galley_root_node(session, &root, &generation) == galley_ok);
    CHECK(root != GALLEY_INVALID_NODE && generation != 0);
    count = value_of(galley_node_count(session, generation));
    CHECK(count > 0);

    int full_count = collect_walk(session, 0, full, 256);
    CHECK(count_flagged(full, full_count, GALLEY_WALK_FLAG_SEMANTIC_ERROR) == 0);
    CHECK(count_flagged(full, full_count, GALLEY_WALK_FLAG_RECOVERED) == 2);
    const Visit *damaged = first_flagged(full, full_count, GALLEY_WALK_FLAG_RECOVERED);
    /* The damaged Number covers the input recovery skipped: `x,beta:`. */
    CHECK(damaged != NULL && strcmp(damaged->symbol, "Number") == 0);
    CHECK(damaged != NULL && damaged->start == 6 && damaged->length == 7);

    int pruned_count = collect_walk(session, GALLEY_WALK_SKIP_RECOVERED, pruned, 256);
    CHECK(count_flagged(pruned, pruned_count, GALLEY_WALK_FLAG_RECOVERED) == 0);
    CHECK(pruned_count == full_count - 2);
    for (int i = 0; i < pruned_count; ++i) {
        /* No undamaged node starts inside the damaged region. */
        CHECK(damaged == NULL || pruned[i].start < damaged->start ||
              pruned[i].start >= damaged->start + damaged->length);
    }

    /* The snapshot column reads what the walk reports, node for node. */
    static GalleyNodeAddress parent[1024];
    static int is_recovered[1024];
    CHECK(count < 1024);
    CHECK(galley_tree_snapshot(session, generation, parent, NULL, NULL, NULL, NULL, NULL, NULL,
                               NULL, is_recovered, count) == (long long)count);
    int flagged_in_snapshot = 0;
    for (unsigned long long address = 0; address < count; ++address) {
        if (is_recovered[address] && parent[address] != GALLEY_INVALID_NODE) ++flagged_in_snapshot;
    }
    CHECK(flagged_in_snapshot == 2);

    const char *input = NULL;
    size_t input_length = 0;
    CHECK(galley_last_input(session, &input, &input_length) == galley_ok);
    CHECK(input_length == strlen(recovered_sample) && memcmp(input, recovered_sample, input_length) == 0);
    unsigned int line = 0, column = 0;
    CHECK(galley_last_position(session, &line, &column) == galley_ok);

    CHECK(galley_parse_sentinel(session, valid_sample) >= 0);
    const char *text = NULL;
    size_t text_length = 0;
    CHECK(galley_node_text(session, generation, root, &text, &text_length) == galley_error_stale_tree);
    CHECK(galley_tree_snapshot(session, generation, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
                               NULL, 0) == galley_error_stale_tree);
    galley_session_destroy(session);
}

/* A parse the parser could not recover from publishes nothing: no root, no
 * input, no position, and the nodes of the tree before it are stale. */
static void test_unrecovered_failure_publishes_nothing(void) {
    GalleySession *session = make_strict_session();
    const char *input = NULL;
    size_t input_length = 0;
    unsigned int line = 0, column = 0;
    unsigned long long generation = 99;
    GalleyNodeAddress root = 0;

    CHECK(galley_parse_sentinel(session, valid_sample) >= 0);
    CHECK(galley_root_node(session, &root, &generation) == galley_ok);
    const unsigned long long before = generation;
    const GalleyNodeAddress before_root = root;
    CHECK(before != 0 && before_root != GALLEY_INVALID_NODE);

    CHECK(galley_parse_sentinel(session, broken_sample) == galley_error_syntax);
    CHECK(galley_root_node(session, &root, &generation) == galley_ok);
    CHECK(root == GALLEY_INVALID_NODE && generation == 0);
    CHECK(galley_last_input(session, &input, &input_length) == galley_error_stale_tree);
    CHECK(galley_last_position(session, &line, &column) == galley_error_stale_tree);
    check_every_call(session, before, before_root, galley_error_stale_tree);
    galley_session_destroy(session);
}

/* A failure can be published and still have no root: here recovery skipped
 * the whole input before the grammar's first symbol. root_node answers "no
 * tree" with the published generation, and the input is still served. */
static void test_published_failure_without_a_root(void) {
    GalleySession *session = make_session();
    CHECK(galley_parse_sentinel(session, rootless_sample) == galley_error_syntax);
    unsigned long long generation = 0;
    GalleyNodeAddress root = 0;
    CHECK(galley_root_node(session, &root, &generation) == galley_ok);
    CHECK(root == GALLEY_INVALID_NODE && generation != 0);
    const char *input = NULL;
    size_t input_length = 0;
    CHECK(galley_last_input(session, &input, &input_length) == galley_ok);
    CHECK(input_length == strlen(rootless_sample) && memcmp(input, rootless_sample, input_length) == 0);
    galley_session_destroy(session);
}

/* galley_last_input and galley_last_position follow the published tree: they
 * refuse before the first parse, and again whenever a parse published
 * nothing or a later parse has begun. */
static void test_last_reads_follow_the_published_tree(void) {
    GalleySession *session = make_session();
    const char *input = NULL;
    size_t input_length = 0;
    unsigned int line = 0, column = 0;

    CHECK(galley_last_input(session, &input, &input_length) == galley_error_stale_tree);
    CHECK(galley_last_position(session, &line, &column) == galley_error_stale_tree);
    CHECK(galley_last_input(NULL, &input, &input_length) == galley_error_null_argument);
    CHECK(galley_last_input(session, NULL, &input_length) == galley_error_null_argument);
    CHECK(galley_last_position(session, NULL, &column) == galley_error_null_argument);

    CHECK(galley_parse_sentinel(session, valid_sample) >= 0);
    CHECK(galley_last_input(session, &input, &input_length) == galley_ok);
    CHECK(input_length == strlen(valid_sample) && memcmp(input, valid_sample, input_length) == 0);
    CHECK(galley_last_position(session, &line, &column) == galley_ok);

    /* A failure that publishes serves its own input, not the success before. */
    CHECK(galley_parse_sentinel(session, broken_sample) == galley_error_syntax);
    CHECK(galley_last_input(session, &input, &input_length) == galley_ok);
    CHECK(input_length == strlen(broken_sample) && memcmp(input, broken_sample, input_length) == 0);

    /* One that publishes nothing serves nothing: not the input before it. */
    galley_session_destroy(session);
    session = make_strict_session();
    CHECK(galley_parse_sentinel(session, valid_sample) >= 0);
    CHECK(galley_parse_sentinel(session, broken_sample) < 0);
    CHECK(galley_last_input(session, &input, &input_length) == galley_error_stale_tree);
    CHECK(galley_last_position(session, &line, &column) == galley_error_stale_tree);
    galley_session_destroy(session);
}

int main(void) {
    test_version();
    test_metadata_flags();
    test_status_strings();
    test_session_lifetime();
    test_symbol_table();
    test_valid_parse();
    test_buffer_parse();
    test_walker();
    test_snapshot();
    test_syntax_diagnostic();
    test_message_override();
    test_recorded_diagnostics();
    test_semantic_error();
    test_error_paths();
    test_published_result_gate();
    test_diagnostic_cache_follows_the_parse();
    test_cached_diagnostic_serves_concurrent_readers();
    test_reserve_nodes();
    test_tree_edit();
    test_tree_edit_range();
    test_hook_door();
    test_hook_refusals();
    test_null_outputs_before_the_gate();
    test_generations();
    test_walk_skip_children();
    test_walk_stale();
    test_walk_removed_current();
    test_walk_sees_edits();
    test_walk_in_use();
    test_walk_in_hook();
    test_walk_semantic_skip_in_hook();
    test_semantic_only_failure_publishes();
    test_recovered_failure_publishes();
    test_unrecovered_failure_publishes_nothing();
    test_published_failure_without_a_root();
    test_last_reads_follow_the_published_tree();
    printf("%d tests, %d failures\n", ran, failures);
    return failures == 0 ? 0 : 1;
}
