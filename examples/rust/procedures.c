/* Procedure hooks for the keyvalue grammar.
 * Each function fires after the corresponding variable is reduced.
 * Author-defined grammar hooks arrive namespaced as `hook_<name>` — the
 * grammar annotates Key with `@print`, and the entry point is `hook_print`,
 * so it can never collide with other symbols.
 *
 * These implementations are compiled into the shared library by Galley's
 * consumer build file; the Rust binary only talks to the C API.
 */
#include <stdio.h>

void reduction(void *args)              { fprintf(stderr, "[hook] reduction\n"); }
void reduction_Document(void *args)     { fprintf(stderr, "[hook] Document\n"); }
void reduction_PairList(void *args)     { fprintf(stderr, "[hook] PairList\n"); }
void reduction_PairListTail(void *args) {}
void reduction_Pair(void *args)         { fprintf(stderr, "[hook] Pair\n"); }
void reduction_Key(void *args)          { fprintf(stderr, "[hook] Key\n"); }
void hook_print(void *args)             { fprintf(stderr, "[hook] print (Key)\n"); }
void reduction_KeyTail(void *args)      {}
void reduction_Number(void *args)       { fprintf(stderr, "[hook] Number\n"); }
void reduction_NumberTail(void *args)   {}
