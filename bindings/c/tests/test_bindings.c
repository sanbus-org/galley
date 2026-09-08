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

#include <stdio.h>
#include <string.h>

static const char *valid_sample = "alpha:12,beta:3";
static const char *broken_sample = "alpha:";
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
    CHECK(galley_node_count(session) > 0);
    GalleyNodeAddress root = galley_root_node(session);
    CHECK(root != GALLEY_INVALID_NODE);
    CHECK(galley_node_is_valid(session, root));
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
    CHECK(galley_node_count(session) == 38);
    with_nul[8] = '\0';
    CHECK(galley_parse(session, with_nul, strlen(valid_sample) + 1) == 8);
    /* NULL data with nonzero length is a null-argument error. */
    CHECK(galley_parse(session, NULL, 3) == galley_error_null_argument);
    galley_session_destroy(session);
}

static void test_walker(void) {
    GalleySession *session = make_session();
    CHECK(galley_parse_sentinel(session, valid_sample) >= 0);
    GalleyNodeAddress root = galley_root_node(session);
    GalleyWalker *walker = galley_walker_create(session, root, 0);
    CHECK(walker != NULL);
    unsigned long long visited = 0;
    int saw_root_at_zero = 0;
    GalleyNodeAddress node = GALLEY_INVALID_NODE;
    unsigned int depth = 0;
    while (galley_walker_next(walker, &node, &depth, NULL)) {
        ++visited;
        if (node == root && depth == 0) saw_root_at_zero = 1;
        const char *name_data = NULL;
        size_t name_len = 0;
        const char *text_data = NULL;
        size_t text_len = 0;
        if (galley_node_symbol_name(session, node, &name_data, &name_len) != galley_ok ||
            galley_node_text(session, node, &text_data, &text_len) != galley_ok) {
            break;
        }
    }
    CHECK(saw_root_at_zero);
    /* 38 nodes allocated, 33 reachable: dropped procedure nodes stay
     * allocated but unreachable (demo prints "38 AST nodes"). */
    CHECK(galley_node_count(session) == 38);
    CHECK(visited == 33);
    galley_walker_destroy(walker);
    galley_walker_destroy(NULL);
    CHECK(galley_walker_create(NULL, root, 0) == NULL);
    galley_session_destroy(session);
}

static void test_snapshot(void) {
    GalleySession *session = make_session();
    CHECK(galley_parse_sentinel(session, valid_sample) >= 0);
    unsigned long long count = galley_node_count(session);
    CHECK(count > 0);
    static GalleyNodeAddress parent[1024];
    static GalleyNodeAddress first_child[1024];
    static GalleyNodeAddress next[1024];
    static unsigned int child_count[1024];
    CHECK(count < 1024);
    CHECK(galley_tree_snapshot(session, parent, first_child, next, child_count,
                               NULL, NULL, NULL, count) == (long long)count);
    GalleyNodeAddress root = galley_root_node(session);
    CHECK(parent[root] == GALLEY_INVALID_NODE);
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
    CHECK(galley_tree_snapshot(NULL, parent, first_child, next, child_count,
                               NULL, NULL, NULL, count) == galley_error_null_argument);
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
    CHECK(galley_node_count(NULL) == 0);
    CHECK(galley_root_node(NULL) == GALLEY_INVALID_NODE);
    CHECK(galley_parse_sentinel(session, valid_sample) >= 0);
    GalleyNodeAddress bogus = galley_node_count(session) + 1000;
    CHECK(!galley_node_is_valid(session, bogus));
    CHECK(galley_node_child_count(session, bogus) == 0);
    CHECK(galley_node_first_child(session, bogus) == GALLEY_INVALID_NODE);
    const char *data = NULL;
    size_t len = 0;
    CHECK(galley_node_symbol_name(session, bogus, &data, &len) ==
          galley_error_invalid_node);
    galley_session_destroy(session);
}

static void test_reserve_nodes(void) {
    GalleySession *session = make_session();
    CHECK(galley_parse_sentinel(session, valid_sample) >= 0);
    unsigned long long count = galley_node_count(session);
    CHECK(galley_reserve_nodes(session, count) == galley_ok);
    CHECK(galley_node_capacity(session) >= count);
    galley_session_destroy(session);
}

static void test_tree_edit(void) {
    GalleySession *session = make_session();
    CHECK(galley_parse_sentinel(session, valid_sample) >= 0);
    GalleyNodeAddress root = galley_root_node(session);
    unsigned int before = galley_node_child_count(session, root);
    CHECK(before > 0);
    GalleyNodeAddress head = GALLEY_INVALID_NODE;
    CHECK(galley_tree_clean_children(session, root, &head) == galley_ok);
    CHECK(head != GALLEY_INVALID_NODE);
    CHECK(galley_node_child_count(session, root) == 0);
    CHECK(galley_tree_append_children(session, root, head) == galley_ok);
    CHECK(galley_node_child_count(session, root) == before);
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
    test_reserve_nodes();
    test_tree_edit();
    printf("%d tests, %d failures\n", ran, failures);
    return failures == 0 ? 0 : 1;
}
