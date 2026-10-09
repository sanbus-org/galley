/* Procedure hooks for the keyvalue grammar.
 *
 * Shows ProcedureArguments in action: the current node, its text, children,
 * and source position, plus drop_if_empty on empty tails. Author-defined
 * grammar hooks arrive as hook_<name> — Key is annotated @print.
 *
 * Each hook receives its session and the ticket of its call. Tree queries go
 * through the parse's hook door: take it with galley_procedure_door, then use
 * galley_hook_*. The door is unshared by
 * construction and valid for the whole parse.
 *
 * Copy of examples/c/procedures.c plus the fixture_stash_session recording
 * below, which the C/C++ suite drives to assert the two doors mid-parse.
 */
#include <galley.h>
#include <stdatomic.h>
#include <stdio.h>
#include <string.h>

/* A hook is named by its session and the ticket of its call. */
static GalleyNodeAddress current_node(GalleySession *session, unsigned long long hook) {
    long long node = galley_procedure_current_node(session, hook);
    return node < 0 ? GALLEY_INVALID_NODE : (GalleyNodeAddress)node;
}

static GalleyHookDoor *procedure_door(GalleySession *session, unsigned long long hook) {
    GalleyHookDoor *door = NULL;
    galley_procedure_door(session, hook, &door);
    return door;
}

static int symbol_is(GalleyHookDoor *door, unsigned long long generation, GalleyNodeAddress node, const char *want) {
    const char *data = NULL;
    size_t len = 0;
    size_t want_len = strlen(want);
    if (galley_hook_node_symbol_name(door, generation, node, &data, &len) != galley_ok || data == NULL)
        return 0;
    return len == want_len && memcmp(data, want, want_len) == 0;
}

static int node_text(GalleyHookDoor *door, unsigned long long generation, GalleyNodeAddress node, const char **data, size_t *len) {
    *data = NULL;
    *len = 0;
    return galley_hook_node_text(door, generation, node, data, len) == galley_ok && *data != NULL;
}

static void node_pos(GalleyHookDoor *door, unsigned long long generation, GalleyNodeAddress node, unsigned *line, unsigned *column) {
    *line = 0;
    *column = 0;
    galley_hook_node_line_column(door, generation, node, line, column);
}

static unsigned parse_u(const char *data, size_t len) {
    unsigned value = 0;
    for (size_t i = 0; i < len; ++i) {
        if (data[i] >= '0' && data[i] <= '9')
            value = value * 10u + (unsigned)(data[i] - '0');
    }
    return value;
}

static void count_pairs(GalleyHookDoor *door, unsigned long long generation, GalleyNodeAddress node, unsigned *count, unsigned *sum) {
    if (symbol_is(door, generation, node, "Pair")) {
        const char *text = NULL;
        size_t len = 0;
        ++*count;
        if (node_text(door, generation, node, &text, &len)) {
            for (size_t i = 0; i < len; ++i) {
                if (text[i] == ':') {
                    *sum += parse_u(text + i + 1, len - i - 1);
                    break;
                }
            }
        }
        return;
    }
    long long child = galley_hook_node_first_child(door, generation, node);
    while (child >= 0 && (GalleyNodeAddress)child != GALLEY_INVALID_NODE) {
        count_pairs(door, generation, (GalleyNodeAddress)child, count, sum);
        child = galley_hook_node_next_sibling(door, generation, (GalleyNodeAddress)child);
    }
}

void reduction(GalleySession *session, unsigned long long hook) {
    (void)session;
    (void)hook;
}

void reduction_KeyTail(GalleySession *session, unsigned long long hook) { galley_procedure_drop_if_empty(session, hook); }
void reduction_NumberTail(GalleySession *session, unsigned long long hook) { galley_procedure_drop_if_empty(session, hook); }
void reduction_PairListTail(GalleySession *session, unsigned long long hook) { galley_procedure_drop_if_empty(session, hook); }
void reduction_PairList(GalleySession *session, unsigned long long hook) { (void)session; (void)hook; }
void reduction_Key(GalleySession *session, unsigned long long hook) { (void)session; (void)hook; }

void hook_print(GalleySession *session, unsigned long long hook) {
    GalleyHookDoor *door = procedure_door(session, hook);
    unsigned long long generation = 0;
    galley_hook_generation(door, &generation);
    GalleyNodeAddress node = current_node(session, hook);
    const char *text = NULL;
    size_t len = 0;
    unsigned line = 0, column = 0;
    if (node == GALLEY_INVALID_NODE)
        return;
    node_pos(door, generation, node, &line, &column);
    fputs("@print \"", stderr);
    if (node_text(door, generation, node, &text, &len))
        fwrite(text, 1, len, stderr);
    fprintf(stderr, "\" at %u:%u\n", line, column);
    fflush(stderr);
}

void reduction_Number(GalleySession *session, unsigned long long hook) {
    GalleyHookDoor *door = procedure_door(session, hook);
    unsigned long long generation = 0;
    galley_hook_generation(door, &generation);
    GalleyNodeAddress node = current_node(session, hook);
    const char *text = NULL;
    size_t len = 0;
    unsigned line = 0, column = 0;
    if (node == GALLEY_INVALID_NODE)
        return;
    node_pos(door, generation, node, &line, &column);
    fputs("Number ", stderr);
    if (node_text(door, generation, node, &text, &len))
        fwrite(text, 1, len, stderr);
    fprintf(stderr, " at %u:%u\n", line, column);
    fflush(stderr);
    if (text != NULL && parse_u(text, len) > 999) {
        static const char message[] = "value out of range";
        galley_procedure_report_semantic_error(session, hook, message, sizeof(message) - 1);
    }
}

/* The suite stashes the session before parsing. During the parse,
 * reduction_Pair keeps the first Pair's door and node, and reduction_Document
 * records what the parse-time door returns, what that earlier door still
 * returns from a later hook of the same parse, what the post-parse door
 * returns when reached through the stashed session, and the parse's
 * generation as the hook door and the stashed session report it. */
static GalleySession *stashed_session = NULL;
static long long hook_text_status = galley_ok;
/* Out-of-range tree edits through the hook door: insert children at, remove
 * children at, remove siblings. */
static long long hook_range_status[3] = {galley_ok, galley_ok, galley_ok};
static long long stashed_kind_status = galley_ok;
/* What galley_session_set_message_override answers from inside a hook. */
static long long stashed_override_status = galley_ok;
/* What the post-parse reads that describe a finished parse answer from
 * inside a hook: capacity, node count, last input, last position. */
enum { FIXTURE_STASHED_READS = 4 };
static long long stashed_read_status[FIXTURE_STASHED_READS];
static GalleyHookDoor *first_pair_door = NULL;
static GalleyNodeAddress first_pair_node = GALLEY_INVALID_NODE;
/* The ticket of the first Pair hook, kept past that hook's return. */
static unsigned long long first_pair_hook = 0;
/* What a later hook of the same parse gets from every galley_procedure_*
 * call made with that returned hook's ticket, and from the same calls made
 * with its own. */
enum { FIXTURE_STALE_HOOK_CALLS = 11 };
static long long stale_hook_status[FIXTURE_STALE_HOOK_CALLS];
static long long own_hook_status[FIXTURE_STALE_HOOK_CALLS];
static int later_hook_shares_door = 0;
static int hook_session_matches = 0;
static long long later_hook_child_count = -1;
static unsigned long long hook_generation = 0;
static long long hook_generation_status = galley_ok;
static GalleyNodeAddress stashed_root = GALLEY_INVALID_NODE;
static unsigned long long stashed_published_generation = 1;
static long long stashed_published_status = galley_ok;

/* The suite arms this around a parse it wants to observe mid-flight:
 * reduction_Document blocks below until the gate is released, holding the
 * session's exclusive lease while another thread calls into it. */
static atomic_int gate_armed = 0;
static atomic_int gate_entered = 0;
/* The session and ticket of the hook held at the gate, for the suite's calls
 * from other threads and other sessions. */
static GalleySession *gate_session = NULL;
static unsigned long long gate_hook = 0;

GalleySession *fixture_gate_session(void) { return gate_session; }

unsigned long long fixture_gate_hook(void) { return gate_hook; }

void fixture_arm_gate(void) {
    atomic_store(&gate_entered, 0);
    atomic_store(&gate_armed, 1);
}

int fixture_gate_entered(void) { return atomic_load(&gate_entered); }

void fixture_release_gate(void) { atomic_store(&gate_armed, 0); }

/* What reduction_Document recorded under fixture_stash_session: a walk of
 * the in-flight tree through the hook door (plain and pruning), rooted at
 * the reduction's node, and the same step through the session door, which
 * the in-flight parse refuses. */
#define FIXTURE_WALK_CAPACITY 128
static GalleyNodeAddress hook_walk_root = GALLEY_INVALID_NODE;
static GalleyNodeAddress hook_walk_node[FIXTURE_WALK_CAPACITY];
static unsigned hook_walk_depth[FIXTURE_WALK_CAPACITY];
static int hook_walk_count = 0;
static int hook_walk_skipped = 0;
static long long hook_walk_status = galley_ok;
static long long stashed_walk_status = galley_ok;

long long fixture_hook_walk_status(void) { return hook_walk_status; }

long long fixture_stashed_walk_status(void) { return stashed_walk_status; }

int fixture_hook_walk_count(void) { return hook_walk_count; }

int fixture_hook_walk_skipped(void) { return hook_walk_skipped; }

GalleyNodeAddress fixture_hook_walk_root(void) { return hook_walk_root; }

GalleyNodeAddress fixture_hook_walk_node(int index) {
    if (index < 0 || index >= FIXTURE_WALK_CAPACITY) return GALLEY_INVALID_NODE;
    return hook_walk_node[index];
}

unsigned fixture_hook_walk_depth(int index) {
    if (index < 0 || index >= FIXTURE_WALK_CAPACITY) return 0;
    return hook_walk_depth[index];
}

/* What reduction_Document recorded under fixture_stash_session: every
 * hook-door call that takes a node, called with the node of this parse
 * under four refusals. Variants: 0 the previous parse's generation, 1
 * generation 0, 2 an address outside the parse's node storage, 3 a NULL
 * door. The suite asserts the status of each call. */
enum { FIXTURE_PROBE_VARIANTS = 4, FIXTURE_PROBE_CALLS = 21 };
static long long probe_status[FIXTURE_PROBE_VARIANTS][FIXTURE_PROBE_CALLS];
/* Two-node edits through the hook door whose second node carries another
 * generation than the first: the four edits, each with the second generation
 * one behind and one ahead of the parse's. */
enum { FIXTURE_PAIR_CALLS = 8 };
static long long probe_pair_status[FIXTURE_PAIR_CALLS];
enum { FIXTURE_NULL_OUTPUT_CALLS = 8 };
static long long probe_null_output[FIXTURE_NULL_OUTPUT_CALLS];
static long long probe_current_node_kept, probe_set_current_status, probe_set_current_took;
static long long probe_clear_current_status, probe_clear_current_took;

static void probe_calls(GalleySession *session, unsigned long long hook, GalleyHookDoor *door, unsigned long long generation,
                        GalleyNodeAddress node, GalleyNodeAddress other, long long *out) {
    const char *data = NULL;
    size_t len = 0;
    unsigned long long start = 0, length = 0;
    unsigned line = 0, column = 0;
    GalleyNodeAddress head = GALLEY_INVALID_NODE;
    int i = 0;
    out[i++] = galley_hook_node_child_count(door, generation, node);
    out[i++] = galley_hook_node_first_child(door, generation, node);
    out[i++] = galley_hook_node_last_child(door, generation, node);
    out[i++] = galley_hook_node_next_sibling(door, generation, node);
    out[i++] = galley_hook_node_prior_sibling(door, generation, node);
    out[i++] = galley_hook_node_parent(door, generation, node);
    out[i++] = galley_hook_node_variable_index(door, generation, node);
    out[i++] = galley_hook_node_symbol_name(door, generation, node, &data, &len);
    out[i++] = galley_hook_node_text(door, generation, node, &data, &len);
    out[i++] = galley_hook_node_span(door, generation, node, &start, &length);
    out[i++] = galley_hook_node_line_column(door, generation, node, &line, &column);
    out[i++] = galley_hook_tree_append_children(door, generation, node, generation, node);
    out[i++] = galley_hook_tree_insert_before(door, generation, node, generation, node);
    out[i++] = galley_hook_tree_insert_after(door, generation, node, generation, node);
    out[i++] = galley_hook_tree_remove_siblings(door, generation, node, 1, &head);
    out[i++] = galley_hook_tree_remove_self(door, generation, node, &head);
    out[i++] = galley_hook_tree_clean_children(door, generation, node, &head);
    out[i++] = galley_hook_tree_insert_children_at(door, generation, node, 0, generation, node);
    out[i++] = galley_hook_tree_remove_children_at(door, generation, node, 0, 1, &head);
    out[i++] = galley_procedure_set_current_node(session, hook, generation, other);
    out[i++] = galley_hook_tree_snapshot(door, generation, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 0);
}

long long fixture_hook_pair_status(int call) {
    if (call < 0 || call >= FIXTURE_PAIR_CALLS) return galley_ok;
    return probe_pair_status[call];
}

static void probe_pair_edits(GalleyHookDoor *door, unsigned long long generation, GalleyNodeAddress node) {
    int i = 0;
    for (int variant = 0; variant < 2; ++variant) {
        unsigned long long other = variant == 0 ? generation - 1 : generation + 1;
        probe_pair_status[i++] = galley_hook_tree_append_children(door, generation, node, other, node);
        probe_pair_status[i++] = galley_hook_tree_insert_before(door, generation, node, other, node);
        probe_pair_status[i++] = galley_hook_tree_insert_after(door, generation, node, other, node);
        probe_pair_status[i++] = galley_hook_tree_insert_children_at(door, generation, node, 0, other, node);
    }
}

static void probe_hook_refusals(GalleySession *session, unsigned long long hook, GalleyHookDoor *door, unsigned long long generation,
                                GalleyNodeAddress node) {
    /* A live node other than the current one, so a refused set_current_node
     * is told apart from one that set the node it was already on. */
    long long child = galley_hook_node_first_child(door, generation, node);
    GalleyNodeAddress other = child >= 0 ? (GalleyNodeAddress)child : GALLEY_INVALID_NODE;
    GalleyNodeAddress outside = (GalleyNodeAddress)1 << 40;
    probe_pair_edits(door, generation, node);
    probe_calls(session, hook, door, generation - 1, node, other, probe_status[0]);
    probe_calls(session, hook, door, 0, node, other, probe_status[1]);
    probe_calls(session, hook, door, generation, outside, outside, probe_status[2]);
    probe_calls(NULL, hook, NULL, generation, node, other, probe_status[3]);
    /* A NULL output is reported before the generation is looked at: with
     * generation 0 (stale) these still answer null argument. */
    {
        int n = 0;
        probe_null_output[n++] = galley_hook_node_symbol_name(door, 0, node, NULL, NULL);
        probe_null_output[n++] = galley_hook_node_text(door, 0, node, NULL, NULL);
        probe_null_output[n++] = galley_hook_node_span(door, 0, node, NULL, NULL);
        probe_null_output[n++] = galley_hook_node_line_column(door, 0, node, NULL, NULL);
        probe_null_output[n++] = galley_hook_tree_remove_siblings(door, 0, node, 1, NULL);
        probe_null_output[n++] = galley_hook_tree_remove_self(door, 0, node, NULL);
        probe_null_output[n++] = galley_hook_tree_clean_children(door, 0, node, NULL);
        probe_null_output[n++] = galley_hook_tree_remove_children_at(door, 0, node, 0, 1, NULL);
    }
    /* Every refused set_current_node above left the current node as it was;
     * a live node sets, and GALLEY_INVALID_NODE clears without a generation. */
    probe_current_node_kept = current_node(session, hook) == node;
    probe_set_current_status = galley_procedure_set_current_node(session, hook, generation, other);
    probe_set_current_took = other != GALLEY_INVALID_NODE && current_node(session, hook) == other;
    probe_clear_current_status = galley_procedure_set_current_node(session, hook, 0, GALLEY_INVALID_NODE);
    probe_clear_current_took = current_node(session, hook) == GALLEY_INVALID_NODE;
    galley_procedure_set_current_node(session, hook, generation, node);
}

long long fixture_hook_null_output_status(int call) {
    if (call < 0 || call >= FIXTURE_NULL_OUTPUT_CALLS) return galley_ok;
    return probe_null_output[call];
}

long long fixture_hook_probe_current(int which) {
    switch (which) {
    case 0: return probe_current_node_kept;
    case 1: return probe_set_current_status;
    case 2: return probe_set_current_took;
    case 3: return probe_clear_current_status;
    default: return probe_clear_current_took;
    }
}

long long fixture_hook_probe_status(int variant, int call) {
    if (variant < 0 || variant >= FIXTURE_PROBE_VARIANTS || call < 0 || call >= FIXTURE_PROBE_CALLS)
        return galley_ok;
    return probe_status[variant][call];
}

int fixture_hook_probe_calls(void) { return FIXTURE_PROBE_CALLS; }

void fixture_stash_session(GalleySession *session) {
    stashed_session = session;
    if (session == NULL)
        return;
    first_pair_door = NULL;
    first_pair_node = GALLEY_INVALID_NODE;
    first_pair_hook = 0;
    memset(stale_hook_status, 0, sizeof stale_hook_status);
    memset(stashed_read_status, 0, sizeof stashed_read_status);
    stashed_override_status = galley_ok;
    memset(own_hook_status, 0, sizeof own_hook_status);
    later_hook_shares_door = 0;
    later_hook_child_count = -1;
    hook_range_status[0] = hook_range_status[1] = hook_range_status[2] = galley_ok;
    hook_generation = 0;
    hook_generation_status = galley_ok;
    stashed_root = GALLEY_INVALID_NODE;
    stashed_published_generation = 1;
    stashed_published_status = galley_ok;
    hook_walk_root = GALLEY_INVALID_NODE;
    hook_walk_count = 0;
    hook_walk_skipped = 0;
    hook_walk_status = galley_ok;
    stashed_walk_status = galley_ok;
    memset(probe_status, 0, sizeof probe_status);
    memset(probe_null_output, 0, sizeof probe_null_output);
}

unsigned long long fixture_first_pair_hook(void) { return first_pair_hook; }

int fixture_stale_hook_calls(void) { return FIXTURE_STALE_HOOK_CALLS; }

long long fixture_stale_hook_status(int call) {
    if (call < 0 || call >= FIXTURE_STALE_HOOK_CALLS) return galley_ok;
    return stale_hook_status[call];
}

long long fixture_own_hook_status(int call) {
    if (call < 0 || call >= FIXTURE_STALE_HOOK_CALLS) return galley_ok;
    return own_hook_status[call];
}

/* Every galley_procedure_* call made with one hook's ticket, in the order the
 * suite expects. The calls that change the parse run only for a ticket the
 * suite expects to be refused (`mutating`); a live ticket records 0 there. */
static void procedure_calls(GalleySession *session, unsigned long long hook, long long *out, int mutating) {
    GalleyHookDoor *door = NULL;
    const char *message = "late";
    const unsigned short *right_hand_side = NULL;
    size_t length = 0;
    int i = 0;
    out[i++] = galley_procedure_door(session, hook, &door);
    out[i++] = galley_procedure_current_node(session, hook);
    out[i++] = galley_procedure_rule_present(session, hook);
    out[i++] = galley_procedure_rule_header(session, hook);
    out[i++] = galley_procedure_rule_right_hand_side(session, hook, &right_hand_side, &length);
    out[i++] = galley_procedure_context_line(session, hook);
    out[i++] = galley_procedure_context_column(session, hook);
    out[i++] = mutating ? galley_procedure_drop_self(session, hook) : 0;
    out[i++] = mutating ? galley_procedure_drop_children(session, hook) : 0;
    out[i++] = mutating ? galley_procedure_report_semantic_error(session, hook, message, 4) : 0;
    out[i++] = mutating ? galley_procedure_set_current_node(session, hook, 0, GALLEY_INVALID_NODE) : 0;
}

long long fixture_hook_text_status(void) { return hook_text_status; }

long long fixture_hook_range_status(int which) { return hook_range_status[which]; }

long long fixture_stashed_kind_status(void) { return stashed_kind_status; }

long long fixture_stashed_override_status(void) { return stashed_override_status; }

long long fixture_stashed_read_status(int which) {
    if (which < 0 || which >= FIXTURE_STASHED_READS) return galley_ok;
    return stashed_read_status[which];
}

int fixture_later_hook_shares_door(void) { return later_hook_shares_door; }

long long fixture_later_hook_child_count(void) { return later_hook_child_count; }

int fixture_hook_session_matches(void) { return hook_session_matches; }

unsigned long long fixture_hook_generation(void) { return hook_generation; }

long long fixture_hook_generation_status(void) { return hook_generation_status; }

unsigned long long fixture_stashed_published_generation(void) { return stashed_published_generation; }

long long fixture_stashed_published_status(void) { return stashed_published_status; }

GalleyNodeAddress fixture_stashed_root(void) { return stashed_root; }

void reduction_Pair(GalleySession *session, unsigned long long hook) {
    GalleyHookDoor *door = procedure_door(session, hook);
    unsigned long long generation = 0;
    galley_hook_generation(door, &generation);
    GalleyNodeAddress node = current_node(session, hook);
    const char *text = NULL;
    size_t len = 0;
    unsigned line = 0, column = 0;
    unsigned children;
    size_t colon = 0;
    if (node == GALLEY_INVALID_NODE)
        return;
    node_pos(door, generation, node, &line, &column);
    children = (unsigned)galley_hook_node_child_count(door, generation, node);
    fputs("Pair ", stderr);
    if (node_text(door, generation, node, &text, &len)) {
        while (colon < len && text[colon] != ':')
            ++colon;
        fwrite(text, 1, colon, stderr);
        fputc('=', stderr);
        if (colon < len)
            fwrite(text + colon + 1, 1, len - colon - 1, stderr);
    }
    fprintf(stderr, " (%u children) at %u:%u\n", children, line, column);
    fflush(stderr);
    if (stashed_session != NULL)
        hook_session_matches = session == stashed_session;
    if (stashed_session != NULL && first_pair_door == NULL) {
        first_pair_door = door;
        first_pair_node = node;
        first_pair_hook = hook;
    }
}

void reduction_Document(GalleySession *session, unsigned long long hook) {
    GalleyHookDoor *door = procedure_door(session, hook);
    unsigned long long generation = 0;
    galley_hook_generation(door, &generation);
    GalleyNodeAddress node = current_node(session, hook);
    unsigned count = 0, sum = 0;
    const char *recorded = NULL;
    size_t recorded_len = 0;
    GalleyWalkCursor refused;
    GalleyWalkCursor walk;
    unsigned long long walk_generation = 0;
    if (atomic_load(&gate_armed)) {
        gate_session = session;
        gate_hook = hook;
        atomic_store(&gate_entered, 1);
        while (atomic_load(&gate_armed)) {
            /* Held here until the suite finishes its mid-parse call. */
        }
    }
    if (node == GALLEY_INVALID_NODE)
        return;
    if (stashed_session != NULL) {
        hook_text_status = galley_hook_node_text(door, generation, node, &recorded, &recorded_len);
        {
            GalleyNodeAddress ignored = GALLEY_INVALID_NODE;
            hook_range_status[0] = galley_hook_tree_insert_children_at(door, generation, node, (size_t)-1, generation, node);
            hook_range_status[1] = galley_hook_tree_remove_children_at(door, generation, node, (size_t)-1, 1, &ignored);
            hook_range_status[2] = galley_hook_tree_remove_siblings(door, generation, node, (size_t)-1, &ignored);
        }
        stashed_kind_status = galley_diagnostic_kind(stashed_session);
        stashed_override_status = galley_session_set_message_override(
            stashed_session, "Number", 6, "set from a hook", 15);
        {
            const char *input = NULL;
            size_t input_length = 0;
            unsigned int last_line = 0, last_column = 0;
            stashed_read_status[0] = galley_node_capacity(stashed_session);
            stashed_read_status[1] = galley_node_count(stashed_session, generation);
            stashed_read_status[2] = galley_last_input(stashed_session, &input, &input_length);
            stashed_read_status[3] = galley_last_position(stashed_session, &last_line, &last_column);
        }
        hook_generation_status = galley_hook_generation(door, &hook_generation);
        stashed_published_status = galley_root_node(stashed_session, &stashed_root, &stashed_published_generation);
        if (first_pair_hook != 0) {
            procedure_calls(session, first_pair_hook, stale_hook_status, 1);
            procedure_calls(session, hook, own_hook_status, 0);
        }
        if (first_pair_door != NULL) {
            later_hook_shares_door = first_pair_door == door;
            later_hook_child_count = galley_hook_node_child_count(first_pair_door, generation, first_pair_node);
        }
        /* Two doors, one step: the session door is refused while the parse
         * holds the lease, and the hook door walks the in-flight tree rooted
         * at this reduction's node — once plain, once pruning semantic-error
         * subtrees. */
        memset(&refused, 0, sizeof refused);
        stashed_walk_status = galley_walk_next(stashed_session, &refused);
        hook_walk_root = node;
        hook_walk_status = galley_hook_generation(door, &walk_generation);
        probe_hook_refusals(session, hook, door, generation, node);
        if (hook_walk_status == galley_ok) {
            memset(&walk, 0, sizeof walk);
            walk.generation = walk_generation;
            walk.root = node;
            for (;;) {
                hook_walk_status = galley_hook_walk_next(door, &walk);
                if (hook_walk_status != 1) break;
                if (hook_walk_count < FIXTURE_WALK_CAPACITY) {
                    hook_walk_node[hook_walk_count] = walk.current;
                    hook_walk_depth[hook_walk_count] = walk.depth;
                }
                ++hook_walk_count;
            }
            memset(&walk, 0, sizeof walk);
            walk.generation = walk_generation;
            walk.root = node;
            walk.options = GALLEY_WALK_SKIP_SEMANTIC_ERRORS;
            for (;;) {
                if (galley_hook_walk_next(door, &walk) != 1) break;
                ++hook_walk_skipped;
            }
        }
    }
    count_pairs(door, generation, node, &count, &sum);
    fprintf(stderr, "Document %u pairs, sum=%u\n", count, sum);
    fflush(stderr);
}
