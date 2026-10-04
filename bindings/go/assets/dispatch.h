// The door choice, written once: one dispatch function per node capability.
// A door is a session or one parse's hook door; the galley_node_* and
// galley_hook_node_* families take the same arguments after the handle and
// answer the same statuses, so the Go side builds a galley_go_door and never
// branches on which family answers.
typedef struct {
    GalleySession *session;
    GalleyHookDoor *hook;
} galley_go_door;

#define GALLEY_GO_LINK(name)                                                             \
    static long long galley_go_##name(galley_go_door door, unsigned long long generation, \
                                      GalleyNodeAddress node) {                          \
        return door.hook != NULL ? galley_hook_##name(door.hook, generation, node)       \
                                 : galley_##name(door.session, generation, node);        \
    }

#define GALLEY_GO_PAIR(name, first_type, second_type)                                    \
    static long long galley_go_##name(galley_go_door door, unsigned long long generation, \
                                      GalleyNodeAddress node, first_type *first,         \
                                      second_type *second) {                             \
        return door.hook != NULL                                                         \
                   ? galley_hook_##name(door.hook, generation, node, first, second)      \
                   : galley_##name(door.session, generation, node, first, second);       \
    }

GALLEY_GO_LINK(node_child_count)
GALLEY_GO_LINK(node_first_child)
GALLEY_GO_LINK(node_last_child)
GALLEY_GO_LINK(node_next_sibling)
GALLEY_GO_LINK(node_prior_sibling)
GALLEY_GO_LINK(node_parent)
GALLEY_GO_PAIR(node_symbol_name, const char *, size_t)
GALLEY_GO_PAIR(node_text, const char *, size_t)
GALLEY_GO_PAIR(node_span, unsigned long long, unsigned long long)
GALLEY_GO_PAIR(node_line_column, unsigned int, unsigned int)

static long long galley_go_walk_next(galley_go_door door, GalleyWalkCursor *cursor) {
    return door.hook != NULL ? galley_hook_walk_next(door.hook, cursor)
                             : galley_walk_next(door.session, cursor);
}
