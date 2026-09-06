// Parses a small key/value document through the Galley C API, mirroring
// examples/c, examples/rust, and examples/go byte-for-byte in output.
#include <galley.h>

#include <cstdio>
#include <cstring>

namespace {

constexpr const char *kValidSample = "alpha:12,beta:3";
constexpr const char *kBrokenSample = "alpha:";
constexpr const char *kMultiErrorSample = "alpha:13x,beta:,gamma:q";

struct SessionGuard {
    GalleySession *session;
    explicit SessionGuard(GalleySession *handle) : session(handle) {}
    ~SessionGuard() {
        if (session != nullptr) galley_session_destroy(session);
    }
    SessionGuard(const SessionGuard &) = delete;
    SessionGuard &operator=(const SessionGuard &) = delete;
};

bool printTree(GalleySession &session, GalleyNodeAddress root) {
    GalleyWalker *walker = galley_walker_create(&session, root, 0);
    if (walker == nullptr) return false;
    GalleyNodeAddress node = GALLEY_INVALID_NODE;
    unsigned int depth = 0;
    while (galley_walker_next(walker, &node, &depth, nullptr)) {
        const char *name_data = nullptr;
        std::size_t name_len = 0;
        const char *text_data = nullptr;
        std::size_t text_len = 0;
        if (galley_node_symbol_name(&session, node, &name_data, &name_len) != galley_ok ||
            galley_node_text(&session, node, &text_data, &text_len) != galley_ok) {
            galley_walker_destroy(walker);
            return false;
        }

        for (unsigned i = 0; i <= depth; ++i) std::fputs("  ", stdout);
        unsigned int line = 0, column = 0;
        galley_node_line_column(&session, node, &line, &column);
        std::printf("%.*s [line %u, %zu bytes]\n",
                    static_cast<int>(name_len), name_data, line, text_len);
    }
    galley_walker_destroy(walker);
    return true;
}

}  // namespace

int main(int argc, char *argv[]) {
    std::printf("galley version: %s\n", galley_version());
    const GalleyCOptions options = {
        .max_errors = 10, /* explicit; zero selects the same default */
    };
    SessionGuard guard(galley_session_create_ex(&options));
    if (guard.session == nullptr) {
        std::fprintf(stderr, "failed to create a parser session\n");
        return 1;
    }
    GalleySession &session = *guard.session;
    if (galley_session_set_message_override(
            &session,
            "Number", sizeof("Number") - 1,
            "expected a number after ':' (digits only) at line {line}",
            sizeof("expected a number after ':' (digits only) at line {line}") - 1) != galley_ok) {
        std::fprintf(stderr, "failed to register the message override\n");
        return 1;
    }

    /* With a path argument: parse the file and nothing else. */
    if (argc > 1) {
        const long long parsed = galley_parse_file(&session, argv[1]);
        if (parsed < 0) {
            unsigned int line = 0, column = 0;
            const char *message = nullptr;
            galley_diagnostic_position(&session, &line, &column);
            galley_diagnostic_message(&session, &message);
            std::fprintf(stderr, "%s:%u:%u: %s\n", argv[1], line, column, message);
            return 1;
        }
        std::printf("parsed %lld bytes\n", parsed);
        return 0;
    }

    const long long parsed = galley_parse_sentinel(&session, kValidSample);
    if (parsed < 0) {
        std::fprintf(stderr, "unexpected failure: %s (%lld)\n",
                     galley_status_string(parsed), parsed);
        return 1;
    }

    /* Successful parse: walk the tree. */
    std::printf("parsed %lld bytes, %llu AST nodes\n",
                parsed, galley_node_count(&session));
    if (!galley_has_ast()) {
        std::puts("AST construction disabled; skipping tree walk");
    } else {
        const GalleyNodeAddress root = galley_root_node(&session);
        if (root == GALLEY_INVALID_NODE) {
            std::fprintf(stderr, "expected a root node\n");
            return 1;
        }
        if (!printTree(session, root)) {
            return 1;
        }
    }

    /* Failed parse: inspect the diagnostic. */
    if (galley_parse_sentinel(&session, kBrokenSample) >= 0) {
        std::fprintf(stderr, "expected the broken sample to fail\n");
        return 1;
    }
    unsigned int line = 0, column = 0;
    const char *message = nullptr;
    galley_diagnostic_position(&session, &line, &column);
    galley_diagnostic_message(&session, &message);
    std::printf("diagnostic at %u:%u: %s\n", line, column, message);

    const long long expected_count = galley_diagnostic_expected_count(&session);
    std::fputs("expected one of: ", stdout);
    for (long long i = 0; i < expected_count; ++i) {
        const char *token_data = nullptr;
        std::size_t token_len = 0;
        galley_diagnostic_expected_at(&session, static_cast<unsigned long long>(i),
                                      &token_data, &token_len);
        std::printf("%s'%.*s'", i == 0 ? "" : ", ",
                    static_cast<int>(token_len), token_data);
    }
    std::fputc('\n', stdout);
    const long long context_count = galley_diagnostic_context_count(&session);
    std::fputs("while parsing (innermost first):", stdout);
    for (long long i = 0; i < context_count; ++i) {
        const char *name_data = nullptr;
        std::size_t name_len = 0;
        galley_diagnostic_context_at(&session, static_cast<unsigned long long>(i),
                                     &name_data, &name_len);
        std::printf(" %.*s", static_cast<int>(name_len), name_data);
    }
    std::fputc('\n', stdout);

    /* Multi-error parse: every recorded diagnostic stays addressable. */
    if (galley_parse_sentinel(&session, kMultiErrorSample) >= 0) {
        std::fprintf(stderr, "expected the multi-error sample to fail\n");
        return 1;
    }
    const long long recorded_count = galley_recorded_diagnostic_count(&session);
    std::printf("recorded diagnostics: %lld\n", recorded_count);
    for (long long i = 0; i < recorded_count; ++i) {
        unsigned int recorded_line = 0, recorded_column = 0;
        galley_recorded_diagnostic_position(&session, static_cast<unsigned long long>(i),
                                            &recorded_line, &recorded_column);
        const long long kind = galley_recorded_diagnostic_kind(&session, static_cast<unsigned long long>(i));
        const char *kind_name = kind == galley_diagnostic_kind_syntax     ? "syntax"
                                : kind == galley_diagnostic_kind_indentation ? "indentation"
                                : kind == galley_diagnostic_kind_semantic    ? "semantic"
                                                                             : "none";
        const char *unexpected_data = nullptr;
        std::size_t unexpected_len = 0;
        galley_recorded_unexpected_token(&session, static_cast<unsigned long long>(i),
                                         &unexpected_data, &unexpected_len);
        std::printf("  [%lld] %s at %u:%u near '%.*s'\n",
                    i, kind_name, recorded_line, recorded_column,
                    static_cast<int>(unexpected_len), unexpected_data);
    }

    /* File parsing. */
    {
        constexpr const char *kPath = "/tmp/galley-cpp-example.json";
        FILE *file = std::fopen(kPath, "wb");
        if (file == nullptr) {
            std::fprintf(stderr, "failed to write %s\n", kPath);
            return 1;
        }
        std::fwrite(kValidSample, 1, std::strlen(kValidSample), file);
        std::fclose(file);

        const long long file_parsed = galley_parse_file(&session, kPath);
        if (file_parsed < 0) {
            std::fprintf(stderr, "file parse failed: %s (%lld)\n",
                         galley_status_string(file_parsed), file_parsed);
            return 1;
        }
        unsigned int end_line = 0, end_column = 0;
        galley_last_position(&session, &end_line, &end_column);
        std::printf("file parse: %lld bytes, ended at %u:%u\n",
                    file_parsed, end_line, end_column);

        /* Tree editing: detach the root's children, then reattach them. */
        if (galley_has_ast()) {
            const GalleyNodeAddress root = galley_root_node(&session);
            const unsigned int before = galley_node_child_count(&session, root);
            GalleyNodeAddress head = GALLEY_INVALID_NODE;
            if (galley_tree_clean_children(&session, root, &head) != galley_ok ||
                head == GALLEY_INVALID_NODE) {
                std::fprintf(stderr, "expected the root to have children\n");
                return 1;
            }
            const long long reattached = galley_tree_append_children(&session, root, head);
            if (reattached != galley_ok) {
                std::fprintf(stderr, "failed to reattach children: %s (%lld)\n",
                             galley_status_string(reattached), reattached);
                return 1;
            }
            std::printf("tree edit: %u children before, %u after reattach\n",
                        before, galley_node_child_count(&session, root));
        }
    }
    return 0;
}
