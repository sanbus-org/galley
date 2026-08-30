/* Procedure hooks for the keyvalue grammar.
 * Each function fires after the corresponding variable is reduced.
 * Author-defined grammar hooks arrive namespaced as `hook_<name>` — the
 * grammar annotates Key with `@print`, and the entry point is
 * `hook_print`, so it can never collide with unrelated symbols.
 *
 * Tree queries go through galley_procedure_session + galley_node_*.
 */
#include <galley.h>
#include <stdio.h>

static void note(const char *label, void *args) {
    GalleySession *session = galley_procedure_session(args);
    GalleyNodeAddress node = galley_procedure_current_node(args);
    const char *text = NULL;
    size_t len = 0;
    if (session != NULL && node != GALLEY_INVALID_NODE)
        (void)galley_node_text(session, node, &text, &len);
    (void)text;
    (void)len;
    fprintf(stderr, "[hook] %s\n", label);
}

void reduction(void *args)              { note("reduction", args); }
void hook_print(void *args)             { note("print (Key)", args); }
void reduction_Document(void *args)     { note("Document", args); }
void reduction_PairList(void *args)     { note("PairList", args); }
void reduction_PairListTail(void *args) {}
void reduction_Pair(void *args)         { note("Pair", args); }
void reduction_Key(void *args)          { note("Key", args); }
void reduction_KeyTail(void *args)      {}
void reduction_Number(void *args)       { note("Number", args); }
void reduction_NumberTail(void *args)   {}
