%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void yyerror(const char *s);
int yylex(void);

typedef enum {
    NODE_OBJECT,
    NODE_ARRAY,
    NODE_MEMBER,
    NODE_STRING,
    NODE_NUMBER,
    NODE_TRUE,
    NODE_FALSE,
    NODE_NULL
} NodeType;

typedef struct ASTNode {
    NodeType type;
    const char *text_start;
    size_t text_length;
    struct ASTNode *first_child;
    struct ASTNode *last_child;
    struct ASTNode *next_sibling;
} ASTNode;

typedef struct {
    unsigned short num_nulls;
    unsigned short num_arrays;
    unsigned short num_objects;
} NodePayload;

typedef struct AdvancedASTNode {
    NodeType type;
    const char *text_start;
    size_t text_length;
    struct AdvancedASTNode *first_child;
    struct AdvancedASTNode *last_child;
    struct AdvancedASTNode *parent;
    struct AdvancedASTNode *prior_sibling;
    struct AdvancedASTNode *next_sibling;
    NodePayload payload;
} AdvancedASTNode;

typedef struct {
    char *block;
    size_t size;
    size_t offset;
} Arena;

Arena *arena_create(size_t size) {
    Arena *a = (Arena *)malloc(sizeof(Arena));
    a->block = (char *)malloc(size);
    a->size = size;
    a->offset = 0;
    return a;
}

static inline void *arena_alloc(Arena *a, size_t size) {
    size_t aligned = (size + 7) & ~7;
    if (a->offset + aligned > a->size) {
        size_t next_size = a->size * 2;
        if (next_size < aligned) next_size = aligned;
        a->block = (char *)realloc(a->block, next_size);
        a->size = next_size;
    }
    void *ptr = a->block + a->offset;
    a->offset += aligned;
    return ptr;
}

void arena_destroy(Arena *a) {
    if (a) {
        free(a->block);
        free(a);
    }
}

// Global control state for the benchmarks
int bison_build_ast = 0;
int bison_build_advanced_ast = 0;
int bison_build_payload_ast = 0;
Arena *bison_current_arena = NULL;
void *bison_root_node = NULL;

static inline void *make_any_node(Arena *arena, NodeType type, const char *text, size_t length) {
    if (bison_build_advanced_ast || bison_build_payload_ast) {
        AdvancedASTNode *n = (AdvancedASTNode *)arena_alloc(arena, sizeof(AdvancedASTNode));
        n->type = type;
        n->text_start = text;
        n->text_length = length;
        n->first_child = NULL;
        n->last_child = NULL;
        n->parent = NULL;
        n->prior_sibling = NULL;
        n->next_sibling = NULL;
        
        n->payload.num_nulls = (type == NODE_NULL) ? 1 : 0;
        n->payload.num_arrays = (type == NODE_ARRAY) ? 1 : 0;
        n->payload.num_objects = (type == NODE_OBJECT) ? 1 : 0;
        
        return n;
    } else if (bison_build_ast) {
        ASTNode *n = (ASTNode *)arena_alloc(arena, sizeof(ASTNode));
        n->type = type;
        n->text_start = text;
        n->text_length = length;
        n->first_child = NULL;
        n->last_child = NULL;
        n->next_sibling = NULL;
        return n;
    }
    return NULL;
}

static inline void append_any_child(void *parent_ptr, void *child_ptr) {
    if (!parent_ptr || !child_ptr) return;
    if (bison_build_advanced_ast || bison_build_payload_ast) {
        AdvancedASTNode *parent = (AdvancedASTNode *)parent_ptr;
        AdvancedASTNode *child = (AdvancedASTNode *)child_ptr;
        child->parent = parent;
        if (!parent->first_child) {
            parent->first_child = child;
            parent->last_child = child;
            child->prior_sibling = NULL;
            child->next_sibling = NULL;
        } else {
            child->prior_sibling = parent->last_child;
            parent->last_child->next_sibling = child;
            parent->last_child = child;
            child->next_sibling = NULL;
        }
        
        if (bison_build_payload_ast) {
            parent->payload.num_nulls += child->payload.num_nulls;
            parent->payload.num_arrays += child->payload.num_arrays;
            parent->payload.num_objects += child->payload.num_objects;
        }
    } else if (bison_build_ast) {
        ASTNode *parent = (ASTNode *)parent_ptr;
        ASTNode *child = (ASTNode *)child_ptr;
        if (!parent->first_child) {
            parent->first_child = child;
            parent->last_child = child;
            child->next_sibling = NULL;
        } else {
            parent->last_child->next_sibling = child;
            parent->last_child = child;
            child->next_sibling = NULL;
        }
    }
}

static inline const char *node_text_start(void *node) {
    if (!node) return NULL;
    return (bison_build_advanced_ast || bison_build_payload_ast) ? ((AdvancedASTNode *)node)->text_start : ((ASTNode *)node)->text_start;
}

static inline size_t node_text_length(void *node) {
    if (!node) return 0;
    return (bison_build_advanced_ast || bison_build_payload_ast) ? ((AdvancedASTNode *)node)->text_length : ((ASTNode *)node)->text_length;
}

size_t count_ast_nodes(void *node_ptr) {
    if (!node_ptr) return 0;
    size_t count = 1;
    if (bison_build_advanced_ast || bison_build_payload_ast) {
        AdvancedASTNode *node = (AdvancedASTNode *)node_ptr;
        AdvancedASTNode *child = node->first_child;
        while (child) {
            count += count_ast_nodes(child);
            child = child->next_sibling;
        }
    } else {
        ASTNode *node = (ASTNode *)node_ptr;
        ASTNode *child = node->first_child;
        while (child) {
            count += count_ast_nodes(child);
            child = child->next_sibling;
        }
    }
    return count;
}

void print_ast_recursive(FILE *f, void *node_ptr, int depth) {
    if (!node_ptr) return;
    for (int i = 0; i < depth; i++) fputs("  ", f);

    NodeType type = NODE_NULL;
    void *first_child = NULL;
    const char *text = NULL;
    size_t len = 0;

    if (bison_build_advanced_ast || bison_build_payload_ast) {
        AdvancedASTNode *node = (AdvancedASTNode *)node_ptr;
        type = node->type;
        first_child = node->first_child;
        text = node->text_start;
        len = node->text_length;
    } else {
        ASTNode *node = (ASTNode *)node_ptr;
        type = node->type;
        first_child = node->first_child;
        text = node->text_start;
        len = node->text_length;
    }

    const char *type_name = "UNKNOWN";
    switch (type) {
        case NODE_OBJECT: type_name = "OBJECT"; break;
        case NODE_ARRAY:  type_name = "ARRAY"; break;
        case NODE_MEMBER: type_name = "MEMBER"; break;
        case NODE_STRING: type_name = "STRING"; break;
        case NODE_NUMBER: type_name = "NUMBER"; break;
        case NODE_TRUE:   type_name = "TRUE"; break;
        case NODE_FALSE:  type_name = "FALSE"; break;
        case NODE_NULL:   type_name = "NULL"; break;
    }

    char preview[11];
    if (text && len > 0) {
        size_t n = len < 10 ? len : 10;
        for (size_t i = 0; i < n; i++) {
            char ch = text[i];
            if (ch == '\n' || ch == '\r' || ch == '\t') ch = ' ';
            preview[i] = ch;
        }
        preview[n] = '\0';
    } else {
        strcpy(preview, "");
    }

    fprintf(f, "- %s (%s)\n", type_name, preview);

    void *child = first_child;
    while (child) {
        print_ast_recursive(f, child, depth + 1);
        if (bison_build_advanced_ast || bison_build_payload_ast) {
            child = ((AdvancedASTNode *)child)->next_sibling;
        } else {
            child = ((ASTNode *)child)->next_sibling;
        }
    }
}

void print_ast_summary(void) {
    if (!bison_root_node) {
        printf("Bison AST: (no root node constructed)\n");
        return;
    }
    size_t total = count_ast_nodes(bison_root_node);
    printf("Bison AST validation: total nodes = %zu\n", total);
    if (bison_build_payload_ast) {
        AdvancedASTNode *root = (AdvancedASTNode *)bison_root_node;
        printf("Bison AST Payload metric counters: nulls=%hu, arrays=%hu, objects=%hu\n",
               root->payload.num_nulls, root->payload.num_arrays, root->payload.num_objects);
    }
    printf("Writing full recursive AST structural representation to bison-tree.txt...\n");
    FILE *f = fopen("bison-tree.txt", "w");
    if (f) {
        print_ast_recursive(f, bison_root_node, 0);
        fclose(f);
        printf("AST successfully written to bison-tree.txt\n");
    } else {
        printf("Error: Failed to open bison-tree.txt for writing\n");
    }
}

#define YYSTYPE_IS_DECLARED 1
typedef union {
    void *node;
    struct {
        const char *text;
        size_t length;
    } token;
} YYSTYPE;
%}

%token <token> STRING NUMBER TRUE FALSE NULL_TOK
%type <node> json value object array members member values

%%

json:
    value { if (bison_build_ast || bison_build_advanced_ast || bison_build_payload_ast) { bison_root_node = $1; } }
    ;

value:
    object { $$ = $1; }
    | array { $$ = $1; }
    | STRING { if (bison_build_ast || bison_build_advanced_ast || bison_build_payload_ast) { $$ = make_any_node(bison_current_arena, NODE_STRING, $1.text, $1.length); } }
    | NUMBER { if (bison_build_ast || bison_build_advanced_ast || bison_build_payload_ast) { $$ = make_any_node(bison_current_arena, NODE_NUMBER, $1.text, $1.length); } }
    | TRUE { if (bison_build_ast || bison_build_advanced_ast || bison_build_payload_ast) { $$ = make_any_node(bison_current_arena, NODE_TRUE, $1.text, $1.length); } }
    | FALSE { if (bison_build_ast || bison_build_advanced_ast || bison_build_payload_ast) { $$ = make_any_node(bison_current_arena, NODE_FALSE, $1.text, $1.length); } }
    | NULL_TOK { if (bison_build_ast || bison_build_advanced_ast || bison_build_payload_ast) { $$ = make_any_node(bison_current_arena, NODE_NULL, $1.text, $1.length); } }
    ;

object:
    '{' '}' { if (bison_build_ast || bison_build_advanced_ast || bison_build_payload_ast) { $$ = make_any_node(bison_current_arena, NODE_OBJECT, "{}", 2); } }
    | '{' members '}' { if (bison_build_ast || bison_build_advanced_ast || bison_build_payload_ast) { $$ = $2; } }
    ;

members:
    member { if (bison_build_ast || bison_build_advanced_ast || bison_build_payload_ast) { 
        void *obj = make_any_node(bison_current_arena, NODE_OBJECT, node_text_start($1), node_text_length($1)); 
        append_any_child(obj, $1); 
        $$ = obj; 
    } }
    | members ',' member { if (bison_build_ast || bison_build_advanced_ast || bison_build_payload_ast) { 
        append_any_child($1, $3); 
        if (bison_build_advanced_ast || bison_build_payload_ast) {
            ((AdvancedASTNode *)$1)->text_length = (node_text_start($3) + node_text_length($3)) - node_text_start($1);
        } else {
            ((ASTNode *)$1)->text_length = (node_text_start($3) + node_text_length($3)) - node_text_start($1);
        }
        $$ = $1; 
    } }
    ;

member:
    STRING ':' value { if (bison_build_ast || bison_build_advanced_ast || bison_build_payload_ast) { 
        const char *start = $1.text;
        size_t len = (node_text_start($3) + node_text_length($3)) - start;
        void *m = make_any_node(bison_current_arena, NODE_MEMBER, start, len); 
        append_any_child(m, $3); 
        $$ = m; 
    } }
    ;

array:
    '[' ']' { if (bison_build_ast || bison_build_advanced_ast || bison_build_payload_ast) { $$ = make_any_node(bison_current_arena, NODE_ARRAY, "[]", 2); } }
    | '[' values ']' { if (bison_build_ast || bison_build_advanced_ast || bison_build_payload_ast) { $$ = $2; } }
    ;

values:
    value { if (bison_build_ast || bison_build_advanced_ast || bison_build_payload_ast) { 
        void *arr = make_any_node(bison_current_arena, NODE_ARRAY, node_text_start($1), node_text_length($1)); 
        append_any_child(arr, $1); 
        $$ = arr; 
    } }
    | values ',' value { if (bison_build_ast || bison_build_advanced_ast || bison_build_payload_ast) { 
        append_any_child($1, $3); 
        if (bison_build_advanced_ast || bison_build_payload_ast) {
            ((AdvancedASTNode *)$1)->text_length = (node_text_start($3) + node_text_length($3)) - node_text_start($1);
        } else {
            ((ASTNode *)$1)->text_length = (node_text_start($3) + node_text_length($3)) - node_text_start($1);
        }
        $$ = $1; 
    } }
    ;

%%

void yyerror(const char *s) {
    (void)s;
}
