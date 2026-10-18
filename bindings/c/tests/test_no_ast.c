/* Refusals in a parser built without AST construction (`bindings/c/galley.h`).
 *
 * The same rule as with an AST: every call that reads or edits nodes checks
 * the generation first, and only a live generation gets past the check. In a
 * build without AST construction a live generation answers as a published
 * tree with no nodes: the count and the snapshot are 0, and every call that
 * addresses a node refuses with galley_error_invalid_node. A generation that
 * is not live, one before the first parse included, is the stale-tree
 * refusal, never a 0 answer.
 *
 * Linked against the no-AST fixture library built by the fixture's
 * CMakeLists.txt; run with ctest from the fixture build directory.
 */
#include <galley.h>

#include <stdio.h>
#include <string.h>

static const char *valid_sample = "alpha:12,beta:3";

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

/* Every generation-taking call of the session door, with `generation`. */
static void check_every_call(GalleySession *session, unsigned long long generation,
                             long long expected) {
    const char *data = NULL;
    size_t length = 0;
    unsigned long long start = 0, span = 0;
    unsigned line = 0, column = 0;
    GalleyNodeAddress head = GALLEY_INVALID_NODE;
    GalleyWalkCursor cursor;
    memset(&cursor, 0, sizeof cursor);
    cursor.generation = generation;
    CHECK(galley_node_count(session, generation) == expected);
    CHECK(galley_tree_snapshot(session, generation, NULL, NULL, NULL, NULL, NULL, NULL,
                               NULL, NULL, NULL, 0) == expected);
    CHECK(galley_node_child_count(session, generation, 0) == expected);
    CHECK(galley_node_first_child(session, generation, 0) == expected);
    CHECK(galley_node_text(session, generation, 0, &data, &length) == expected);
    CHECK(galley_node_symbol_name(session, generation, 0, &data, &length) == expected);
    CHECK(galley_node_span(session, generation, 0, &start, &span) == expected);
    CHECK(galley_node_line_column(session, generation, 0, &line, &column) == expected);
    CHECK(galley_tree_remove_self(session, generation, 0, &head) == expected);
    CHECK(galley_walk_next(session, &cursor) == expected);
}

/* Reserving storage is refused mid-parse in a build without AST construction
 * as well: the session-use check comes before the "nothing to reserve"
 * answer. The hook door answers the counts of the in-flight parse the same
 * way the session door answers a published tree with no nodes. Probed from a
 * hook of the running parse. */
static GalleySession *probed_session = NULL;
static long long reserve_in_hook = galley_ok;
static long long capacity_in_hook = galley_ok;
static long long snapshot_in_hook = galley_ok;

static int probe_dispatch(void *handle, unsigned int index, unsigned long long hook) {
    (void)handle;
    (void)index;
    GalleyHookDoor *door = NULL;
    unsigned long long hook_generation = 0;
    reserve_in_hook = galley_reserve_nodes(probed_session, 16);
    capacity_in_hook = galley_node_capacity(probed_session);
    if (galley_procedure_door(probed_session, hook, &door) == galley_ok &&
        galley_hook_generation(door, &hook_generation) == galley_ok) {
        snapshot_in_hook = galley_hook_tree_snapshot(door, hook_generation, NULL, NULL, NULL,
                                                     NULL, NULL, NULL, NULL, NULL, NULL, 0);
    }
    return 0;
}

static void test_reserve_is_refused_mid_parse(void) {
    GalleySession *session = NULL;
    CHECK(galley_session_create(NULL, &session) == galley_ok);
    size_t count = galley_hooks_count();
    unsigned char enabled[256];
    CHECK(session != NULL && count > 0 && count <= sizeof enabled);
    memset(enabled, 1, count);
    CHECK(galley_session_set_hooks(session, probe_dispatch, NULL, enabled, count) == galley_ok);
    probed_session = session;
    CHECK(galley_parse_sentinel(session, valid_sample) >= 0);
    CHECK(reserve_in_hook == galley_error_session_in_use);
    CHECK(capacity_in_hook == galley_error_session_in_use);
    CHECK(snapshot_in_hook == 0);
    CHECK(galley_reserve_nodes(session, 16) == galley_ok);
    galley_session_destroy(session);
}

/* A hook whose dispatch returns nonzero aborts the parse: the call returns
 * galley_error_hook_failed, the diagnostic of the failed parse is of kind
 * hook and positioned, nothing is published, the hook's ticket is dead, and
 * the session parses again. */
static unsigned long long failing_ticket = 0;
static unsigned failing_calls = 0;

static int failing_dispatch(void *handle, unsigned int index, unsigned long long hook) {
    (void)handle;
    (void)index;
    failing_ticket = hook;
    ++failing_calls;
    return 1;
}

static void test_failing_hook_aborts_the_parse(void) {
    GalleySession *session = NULL;
    CHECK(galley_session_create(NULL, &session) == galley_ok);
    size_t count = galley_hooks_count();
    unsigned char enabled[256];
    GalleyNodeAddress root = 0;
    unsigned long long generation = 99;
    unsigned long long offset = 0;
    unsigned line = 0, column = 0;
    const char *message = NULL;
    CHECK(session != NULL && count > 0 && count <= sizeof enabled);
    memset(enabled, 1, count);
    CHECK(galley_session_set_hooks(session, failing_dispatch, NULL, enabled, count) == galley_ok);

    CHECK(galley_parse_sentinel(session, valid_sample) == galley_error_hook_failed);
    CHECK(failing_calls == 1);
    CHECK(strcmp(galley_status_string(galley_error_hook_failed), "hook failed") == 0);
    CHECK(galley_diagnostic_kind(session) == galley_diagnostic_kind_hook);
    CHECK(galley_diagnostic_position(session, &offset, &line, &column) == galley_ok);
    CHECK(line >= 1 && column >= 1);
    CHECK(galley_diagnostic_message(session, &message) == galley_ok);
    CHECK(message != NULL && strstr(message, "HookError") != NULL);
    CHECK(galley_root_node(session, &root, &generation) == galley_ok);
    CHECK(root == GALLEY_INVALID_NODE && generation == 0);
    CHECK(galley_last_position(session, &line, &column) == galley_error_stale_tree);
    CHECK(galley_procedure_current_node(session, failing_ticket) == galley_error_stale_hook);

    /* The session is reusable: a parse with no failing hook publishes. */
    CHECK(galley_session_set_hooks(session, NULL, NULL, NULL, 0) == galley_ok);
    CHECK(galley_parse_sentinel(session, valid_sample) >= 0);
    CHECK(galley_diagnostic_kind(session) == galley_diagnostic_kind_none);
    CHECK(galley_root_node(session, &root, &generation) == galley_ok);
    CHECK(generation >= 1);
    galley_session_destroy(session);
}

int main(void) {
    CHECK(galley_has_ast() == 0);
    GalleySession *session = NULL;
    CHECK(galley_session_create(NULL, &session) == galley_ok);
    GalleyNodeAddress root = 0;
    unsigned long long generation = 99;
    const char *input = NULL;
    size_t input_length = 0;
    unsigned line = 0, column = 0;

    /* Nothing published: no generation is live, 0 included. */
    CHECK(galley_root_node(session, &root, &generation) == galley_ok);
    CHECK(root == GALLEY_INVALID_NODE && generation == 0);
    check_every_call(session, 0, galley_error_stale_tree);
    check_every_call(session, 1, galley_error_stale_tree);
    CHECK(galley_last_input(session, &input, &input_length) == galley_error_stale_tree);
    CHECK(galley_last_position(session, &line, &column) == galley_error_stale_tree);
    CHECK(galley_node_capacity(session) == 0);

    CHECK(galley_parse_sentinel(session, valid_sample) >= 0);

    /* A published parse has a generation, no root, and no nodes: the counts
     * answer 0 and a node address refuses. */
    CHECK(galley_root_node(session, &root, &generation) == galley_ok);
    CHECK(root == GALLEY_INVALID_NODE && generation >= 1);
    CHECK(galley_node_count(session, generation) == 0);
    CHECK(galley_tree_snapshot(session, generation, NULL, NULL, NULL, NULL, NULL, NULL,
                               NULL, NULL, NULL, 0) == 0);
    CHECK(galley_node_child_count(session, generation, 0) == galley_error_invalid_node);
    /* Every other read that addresses a node refuses too: the generation
     * is live, but there is no node storage to address. */
    const char *data = NULL;
    size_t length = 0;
    unsigned long long start = 0, span = 0;
    unsigned line_read = 0, column_read = 0;
    CHECK(galley_node_first_child(session, generation, 0) == galley_error_invalid_node);
    CHECK(galley_node_next_sibling(session, generation, 0) == galley_error_invalid_node);
    CHECK(galley_node_text(session, generation, 0, &data, &length) == galley_error_invalid_node);
    CHECK(galley_node_symbol_name(session, generation, 0, &data, &length) == galley_error_invalid_node);
    CHECK(galley_node_span(session, generation, 0, &start, &span) == galley_error_invalid_node);
    CHECK(galley_node_line_column(session, generation, 0, &line_read, &column_read) ==
          galley_error_invalid_node);
    {
        GalleyWalkCursor cursor;
        memset(&cursor, 0, sizeof cursor);
        cursor.generation = generation;
        CHECK(galley_walk_next(session, &cursor) == galley_error_invalid_node);
    }
    CHECK(galley_last_input(session, &input, &input_length) == galley_ok);
    CHECK(input_length == strlen(valid_sample) && memcmp(input, valid_sample, input_length) == 0);
    CHECK(galley_last_position(session, &line, &column) == galley_ok);
    /* The generation check still comes first: any other generation is stale. */
    check_every_call(session, 0, galley_error_stale_tree);
    check_every_call(session, generation + 1, galley_error_stale_tree);

    /* A later parse retires the generation. */
    const unsigned long long first = generation;
    CHECK(galley_parse_sentinel(session, valid_sample) >= 0);
    CHECK(galley_root_node(session, &root, &generation) == galley_ok);
    CHECK(generation > first);
    check_every_call(session, first, galley_error_stale_tree);
    CHECK(galley_node_count(session, generation) == 0);

    galley_session_destroy(session);
    test_reserve_is_refused_mid_parse();
    test_failing_hook_aborts_the_parse();
    printf("%d tests, %d failures\n", ran, failures);
    return failures == 0 ? 0 : 1;
}
