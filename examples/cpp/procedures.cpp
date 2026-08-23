// Procedure hooks for the keyvalue grammar.
// Author-defined grammar hooks arrive namespaced as `hook_<name>` — the
// grammar annotates Key with `@print`, and the entry point is `hook_print`,
// so it can never collide with unrelated symbols.
//
// Compiled by zig together with the shared library, so this translation
// unit sticks to C library headers.
#include <stdio.h>

extern "C" {
void reduction(void *)              { fprintf(stderr, "[hook] reduction\n"); }
void reduction_Document(void *)     { fprintf(stderr, "[hook] Document\n"); }
void reduction_PairList(void *)     { fprintf(stderr, "[hook] PairList\n"); }
void reduction_PairListTail(void *) {}
void reduction_Pair(void *)         { fprintf(stderr, "[hook] Pair\n"); }
void reduction_Key(void *)          { fprintf(stderr, "[hook] Key\n"); }
void hook_print(void *)             { fprintf(stderr, "[hook] print (Key)\n"); }
void reduction_KeyTail(void *)      {}
void reduction_Number(void *)       { fprintf(stderr, "[hook] Number\n"); }
void reduction_NumberTail(void *)   {}
}
