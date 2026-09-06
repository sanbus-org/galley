/* Parses a small key/value document through the Galley C API, mirroring
 * examples/cpp, examples/rust, and examples/go byte-for-byte in output. */
#include <galley.h>

#include <stdio.h>
#include <string.h>

static const char *valid_sample = "alpha:12,beta:3";
static const char *broken_sample = "alpha:";
static const char *multi_error_sample = "alpha:13x,beta:,gamma:q";

static int print_tree(GalleySession *session, GalleyNodeAddress root) {
    GalleyWalker *walker = galley_walker_create(session, root, 0);
    if (walker == NULL) return 1;
    GalleyNodeAddress node;
    unsigned int depth;
    while (galley_walker_next(walker, &node, &depth, NULL)) {
        const char *name_data = NULL;
        size_t name_len = 0;
        const char *text_data = NULL;
        size_t text_len = 0;

        if (galley_node_symbol_name(session, node, &name_data, &name_len) != galley_ok ||
            galley_node_text(session, node, &text_data, &text_len) != galley_ok) {
            galley_walker_destroy(walker);
            return 1;
        }

        for (unsigned i = 0; i <= depth; ++i) fputs("  ", stdout);
        unsigned int line = 0, column = 0;
        galley_node_line_column(session, node, &line, &column);
        printf("%.*s [line %u, %zu bytes]\n", (int)name_len, name_data, line, text_len);
    }
    galley_walker_destroy(walker);
    return 0;
}

int main(int argc, char **argv) {
    printf("galley version: %s\n", galley_version());
    const GalleyCOptions options = {
        .max_errors = 10, /* explicit; zero selects the same default */
    };
    GalleySession *session = galley_session_create_ex(&options);
    if (session == NULL) {
        fprintf(stderr, "failed to create a parser session\n");
        return 1;
    }
    if (galley_session_set_message_override(
            session,
            "Number", sizeof("Number") - 1,
            "expected a number after ':' (digits only) at line {line}",
            sizeof("expected a number after ':' (digits only) at line {line}") - 1) != galley_ok) {
        fprintf(stderr, "failed to register the message override\n");
        galley_session_destroy(session);
        return 1;
    }

    /* With a path argument: parse the file and nothing else. */
    if (argc > 1) {
        long long parsed = galley_parse_file(session, argv[1]);
        if (parsed < 0) {
            unsigned int line = 0, column = 0;
            const char *message = NULL;
            galley_diagnostic_position(session, &line, &column);
            galley_diagnostic_message(session, &message);
            fprintf(stderr, "%s:%u:%u: %s\n", argv[1], line, column, message);
            galley_session_destroy(session);
            return 1;
        }
        printf("parsed %lld bytes\n", parsed);
        galley_session_destroy(session);
        return 0;
    }

    /* Successful parse: walk the tree. */
    long long parsed = galley_parse_sentinel(session, valid_sample);
    if (parsed < 0) {
        fprintf(stderr, "unexpected failure: %s (%lld)\n",
                galley_status_string(parsed), parsed);
        galley_session_destroy(session);
        return 1;
    }
    printf("parsed %lld bytes, %llu AST nodes\n",
           parsed, galley_node_count(session));
    if (galley_has_ast()) {
        GalleyNodeAddress root = galley_root_node(session);
        if (root == GALLEY_INVALID_NODE) {
            fprintf(stderr, "expected a root node\n");
            galley_session_destroy(session);
            return 1;
        }
        if (print_tree(session, root) != 0) {
            galley_session_destroy(session);
            return 1;
        }
    } else {
        puts("AST construction disabled; skipping tree walk");
    }

    /* Failed parse: inspect the diagnostic. */
    parsed = galley_parse_sentinel(session, broken_sample);
    if (parsed >= 0) {
        fprintf(stderr, "expected the broken sample to fail\n");
        galley_session_destroy(session);
        return 1;
    }
    unsigned int line = 0, column = 0;
    const char *message = NULL;
    galley_diagnostic_position(session, &line, &column);
    galley_diagnostic_message(session, &message);
    printf("diagnostic at %u:%u: %s\n", line, column, message);

    long long expected_count = galley_diagnostic_expected_count(session);
    fputs("expected one of: ", stdout);
    for (long long i = 0; i < expected_count; ++i) {
        const char *token_data = NULL;
        size_t token_len = 0;
        galley_diagnostic_expected_at(session, (unsigned long long)i, &token_data, &token_len);
        printf("%s'%.*s'", i == 0 ? "" : ", ", (int)token_len, token_data);
    }
    fputc('\n', stdout);

    long long context_count = galley_diagnostic_context_count(session);
    fputs("while parsing (innermost first):", stdout);
    for (long long i = 0; i < context_count; ++i) {
        const char *name_data = NULL;
        size_t name_len = 0;
        galley_diagnostic_context_at(session, (unsigned long long)i, &name_data, &name_len);
        printf(" %.*s", (int)name_len, name_data);
    }
    fputc('\n', stdout);

    /* Multi-error parse: every recorded diagnostic stays addressable. */
    parsed = galley_parse_sentinel(session, multi_error_sample);
    if (parsed >= 0) {
        fprintf(stderr, "expected the multi-error sample to fail\n");
        galley_session_destroy(session);
        return 1;
    }
    long long recorded_count = galley_recorded_diagnostic_count(session);
    printf("recorded diagnostics: %lld\n", recorded_count);
    for (long long i = 0; i < recorded_count; ++i) {
        unsigned int recorded_line = 0, recorded_column = 0;
        galley_recorded_diagnostic_position(session, (unsigned long long)i,
                                            &recorded_line, &recorded_column);
        long long kind = galley_recorded_diagnostic_kind(session, (unsigned long long)i);
        const char *kind_name = kind == galley_diagnostic_kind_syntax     ? "syntax"
                                : kind == galley_diagnostic_kind_indentation ? "indentation"
                                : kind == galley_diagnostic_kind_semantic    ? "semantic"
                                                                             : "none";
        const char *unexpected_data = NULL;
        size_t unexpected_len = 0;
        galley_recorded_unexpected_token(session, (unsigned long long)i,
                                         &unexpected_data, &unexpected_len);
        printf("  [%lld] %s at %u:%u near '%.*s'\n",
               i, kind_name, recorded_line, recorded_column,
               (int)unexpected_len, unexpected_data);
    }

    /* File parsing. */
    const char *path = "/tmp/galley-c-example.json";
    FILE *file = fopen(path, "wb");
    if (file == NULL) {
        fprintf(stderr, "failed to write %s\n", path);
        galley_session_destroy(session);
        return 1;
    }
    fwrite(valid_sample, 1, strlen(valid_sample), file);
    fclose(file);
    parsed = galley_parse_file(session, path);
    if (parsed < 0) {
        fprintf(stderr, "file parse failed: %s (%lld)\n",
                galley_status_string(parsed), parsed);
        galley_session_destroy(session);
        return 1;
    }
    unsigned int end_line = 0, end_column = 0;
    galley_last_position(session, &end_line, &end_column);
    printf("file parse: %lld bytes, ended at %u:%u\n", parsed, end_line, end_column);

    /* Tree editing: detach the root's children, then reattach them. */
    if (galley_has_ast()) {
        GalleyNodeAddress root = galley_root_node(session);
        unsigned int child_count_before = galley_node_child_count(session, root);
        GalleyNodeAddress head = GALLEY_INVALID_NODE;
        if (galley_tree_clean_children(session, root, &head) != galley_ok ||
            head == GALLEY_INVALID_NODE) {
            fprintf(stderr, "expected the root to have children\n");
            galley_session_destroy(session);
            return 1;
        }
        long long reattached = galley_tree_append_children(session, root, head);
        if (reattached != galley_ok) {
            fprintf(stderr, "failed to reattach children: %s (%lld)\n",
                    galley_status_string(reattached), reattached);
            galley_session_destroy(session);
            return 1;
        }
        printf("tree edit: %u children before, %u after reattach\n",
               child_count_before, galley_node_child_count(session, root));
    }

    galley_session_destroy(session);
    return 0;
}
