%{
typedef union {
    void *node;
    struct {
        const char *text;
        size_t length;
    } token;
} YYSTYPE;
#define YYSTYPE_IS_DECLARED 1

#include "parser.h"
%}

%option fast
%option noyywrap
%option nounput
%option noinput
%option nodefault

%%
[ \t\r\n]+             ; /* Ignore whitespace */
"{"                     return '{';
"}"                     return '}';
"["                     return '[';
"]"                     return ']';
":"                     return ':';
","                     return ',';
"true"                  { yylval.token.text = yytext; yylval.token.length = yyleng; return TRUE; }
"false"                 { yylval.token.text = yytext; yylval.token.length = yyleng; return FALSE; }
"null"                  { yylval.token.text = yytext; yylval.token.length = yyleng; return NULL_TOK; }
\"([^\"\\]|\\.)*\"      { yylval.token.text = yytext; yylval.token.length = yyleng; return STRING; }
[-]?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)? { yylval.token.text = yytext; yylval.token.length = yyleng; return NUMBER; }
.                       return yytext[0];
%%

int yywrap() { return 1; }
