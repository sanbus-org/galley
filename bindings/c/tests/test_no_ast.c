/* Refusals in a parser built without AST construction (`bindings/c/galley.h`).
 *
 * The same rule as with an AST: every call that reads or edits nodes checks
 * the generation first, and only a live generation gets an answer. In a build
 * without AST construction that answer is "there are no nodes": 0 for the
 * count and the snapshot, no node to address for the rest. A generation that
 * is not live, one before the first parse included, is the stale-tree
 * refusal, never a 0.
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
 * answer. Probed from a hook of the running parse. */
static GalleySession *probed_session = NULL;
static long long reserve_in_hook = galley_ok;
static long long capacity_in_hook = galley_ok;

static void probe_dispatch(void *handle, unsigned int index, unsigned long long hook) {
    (void)handle;
    (void)index;
    (void)hook;
    reserve_in_hook = galley_reserve_nodes(probed_session, 16);
    capacity_in_hook = galley_node_capacity(probed_session);
}

static void test_reserve_is_refused_mid_parse(void) {
    GalleySession *session = galley_session_create();
    size_t count = galley_hooks_count();
    unsigned char enabled[256];
    CHECK(session != NULL && count > 0 && count <= sizeof enabled);
    memset(enabled, 1, count);
    CHECK(galley_session_set_hooks(session, probe_dispatch, NULL, enabled, count) == galley_ok);
    probed_session = session;
    CHECK(galley_parse_sentinel(session, valid_sample) >= 0);
    CHECK(reserve_in_hook == galley_error_session_in_use);
    CHECK(capacity_in_hook == galley_error_session_in_use);
    CHECK(galley_reserve_nodes(session, 16) == galley_ok);
    galley_session_destroy(session);
}

int main(void) {
    CHECK(galley_has_ast() == 0);
    GalleySession *session = galley_session_create();
    CHECK(session != NULL);
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

    /* A published parse has a generation and no root. */
    CHECK(galley_root_node(session, &root, &generation) == galley_ok);
    CHECK(root == GALLEY_INVALID_NODE && generation >= 1);
    CHECK(galley_node_count(session, generation) == 0);
    CHECK(galley_tree_snapshot(session, generation, NULL, NULL, NULL, NULL, NULL, NULL,
                               NULL, NULL, NULL, 0) == 0);
    CHECK(galley_node_child_count(session, generation, 0) == galley_error_invalid_node);
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
    printf("%d tests, %d failures\n", ran, failures);
    return failures == 0 ? 0 : 1;
}
