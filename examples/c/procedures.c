/* Procedure hooks for the keyvalue grammar.
 *
 * Shows ProcedureArguments in action: the current node, its text, children,
 * and source position, plus drop_if_empty on empty tails. Author-defined
 * grammar hooks arrive as hook_<name> — Key is annotated @print.
 *
 * Tree queries go through the parse's hook door: take it from the arguments
 * with galley_procedure_door, then use galley_hook_*. The door is unshared by
 * construction and valid for the whole parse.
 */
#include <galley.h>
#include <stdio.h>
#include <string.h>

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

void reduction(void *args) {
    (void)args;
}

void reduction_KeyTail(void *args) { galley_procedure_drop_if_empty(args); }
void reduction_NumberTail(void *args) { galley_procedure_drop_if_empty(args); }
void reduction_PairListTail(void *args) { galley_procedure_drop_if_empty(args); }
void reduction_PairList(void *args) { (void)args; }
void reduction_Key(void *args) { (void)args; }

void hook_print(void *args) {
    GalleyHookDoor *door = galley_procedure_door(args);
    unsigned long long generation = 0;
    galley_hook_generation(door, &generation);
    GalleyNodeAddress node = galley_procedure_current_node(args);
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

void reduction_Number(void *args) {
    GalleyHookDoor *door = galley_procedure_door(args);
    unsigned long long generation = 0;
    galley_hook_generation(door, &generation);
    GalleyNodeAddress node = galley_procedure_current_node(args);
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
        galley_procedure_report_semantic_error(args, message, sizeof(message) - 1);
    }
}

void reduction_Pair(void *args) {
    GalleyHookDoor *door = galley_procedure_door(args);
    unsigned long long generation = 0;
    galley_hook_generation(door, &generation);
    GalleyNodeAddress node = galley_procedure_current_node(args);
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
}

void reduction_Document(void *args) {
    GalleyHookDoor *door = galley_procedure_door(args);
    unsigned long long generation = 0;
    galley_hook_generation(door, &generation);
    GalleyNodeAddress node = galley_procedure_current_node(args);
    unsigned count = 0, sum = 0;
    if (node == GALLEY_INVALID_NODE)
        return;
    count_pairs(door, generation, node, &count, &sum);
    fprintf(stderr, "Document %u pairs, sum=%u\n", count, sum);
    fflush(stderr);
}
