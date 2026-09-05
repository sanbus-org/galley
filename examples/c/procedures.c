/* Procedure hooks for the keyvalue grammar.
 *
 * Shows ProcedureArguments in action: the current node, its text, children,
 * and source position, plus drop_if_empty on empty tails. Author-defined
 * grammar hooks arrive as hook_<name> — Key is annotated @print.
 *
 * Tree queries go through galley_procedure_session + galley_node_*.
 */
#include <galley.h>
#include <stdio.h>
#include <string.h>

static int symbol_is(GalleySession *session, GalleyNodeAddress node, const char *want) {
    const char *data = NULL;
    size_t len = 0;
    size_t want_len = strlen(want);
    if (galley_node_symbol_name(session, node, &data, &len) != galley_ok || data == NULL)
        return 0;
    return len == want_len && memcmp(data, want, want_len) == 0;
}

static int node_text(GalleySession *session, GalleyNodeAddress node, const char **data, size_t *len) {
    *data = NULL;
    *len = 0;
    return galley_node_text(session, node, data, len) == galley_ok && *data != NULL;
}

static void node_pos(GalleySession *session, GalleyNodeAddress node, unsigned *line, unsigned *column) {
    *line = 0;
    *column = 0;
    galley_node_line_column(session, node, line, column);
}

static unsigned parse_u(const char *data, size_t len) {
    unsigned value = 0;
    for (size_t i = 0; i < len; ++i) {
        if (data[i] >= '0' && data[i] <= '9')
            value = value * 10u + (unsigned)(data[i] - '0');
    }
    return value;
}

static void count_pairs(GalleySession *session, GalleyNodeAddress node, unsigned *count, unsigned *sum) {
    if (symbol_is(session, node, "Pair")) {
        const char *text = NULL;
        size_t len = 0;
        ++*count;
        if (node_text(session, node, &text, &len)) {
            for (size_t i = 0; i < len; ++i) {
                if (text[i] == ':') {
                    *sum += parse_u(text + i + 1, len - i - 1);
                    break;
                }
            }
        }
        return;
    }
    GalleyNodeAddress child = galley_node_first_child(session, node);
    while (child != GALLEY_INVALID_NODE) {
        count_pairs(session, child, count, sum);
        child = galley_node_next_sibling(session, child);
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
    GalleySession *session = galley_procedure_session(args);
    GalleyNodeAddress node = galley_procedure_current_node(args);
    const char *text = NULL;
    size_t len = 0;
    unsigned line = 0, column = 0;
    if (session == NULL || node == GALLEY_INVALID_NODE)
        return;
    node_pos(session, node, &line, &column);
    fputs("@print \"", stderr);
    if (node_text(session, node, &text, &len))
        fwrite(text, 1, len, stderr);
    fprintf(stderr, "\" at %u:%u\n", line, column);
    fflush(stderr);
}

void reduction_Number(void *args) {
    GalleySession *session = galley_procedure_session(args);
    GalleyNodeAddress node = galley_procedure_current_node(args);
    const char *text = NULL;
    size_t len = 0;
    unsigned line = 0, column = 0;
    if (session == NULL || node == GALLEY_INVALID_NODE)
        return;
    node_pos(session, node, &line, &column);
    fputs("Number ", stderr);
    if (node_text(session, node, &text, &len))
        fwrite(text, 1, len, stderr);
    fprintf(stderr, " at %u:%u\n", line, column);
    fflush(stderr);
    if (text != NULL && parse_u(text, len) > 999) {
        static const char message[] = "value out of range";
        galley_procedure_report_semantic_error(args, message, sizeof(message) - 1);
    }
}

void reduction_Pair(void *args) {
    GalleySession *session = galley_procedure_session(args);
    GalleyNodeAddress node = galley_procedure_current_node(args);
    const char *text = NULL;
    size_t len = 0;
    unsigned line = 0, column = 0;
    unsigned children;
    size_t colon = 0;
    if (session == NULL || node == GALLEY_INVALID_NODE)
        return;
    node_pos(session, node, &line, &column);
    children = galley_node_child_count(session, node);
    fputs("Pair ", stderr);
    if (node_text(session, node, &text, &len)) {
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
    GalleySession *session = galley_procedure_session(args);
    GalleyNodeAddress node = galley_procedure_current_node(args);
    unsigned count = 0, sum = 0;
    if (session == NULL || node == GALLEY_INVALID_NODE)
        return;
    count_pairs(session, node, &count, &sum);
    fprintf(stderr, "Document %u pairs, sum=%u\n", count, sum);
    fflush(stderr);
}
