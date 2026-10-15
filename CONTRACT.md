# Galley contract

What Galley promises its users. Every promise falls under exactly one section. Links lead to documentation for syntax and examples; only the sentences in this file are promises.

## 1. Grammar language

Galley's grammar language is fully specified: every grammar has one documented meaning under a given configuration.

1. A grammar is a set of [rules](docs/grammar_guidelines.md#1-file-structure--rule-syntax-grm-files), and each rule defines one variable with one or more productions.

2. The first rule of a grammar defines its start variable.
3. A [variable name](docs/grammar_guidelines.md#2-variable-naming--ast-generation) starts with an uppercase letter, or with an underscore followed by an uppercase letter, which marks a helper variable.
4. A terminal is a byte string, written in quotes or as a [raw string](docs/grammar_guidelines.md#3-terminal-symbols), or a [built-in byte class](docs/grammar_guidelines.md#3-terminal-symbols).
5. The built-in byte classes cover characters, digits, letters, operators, newline, space, the start and end of an indentation block, and UTF-8 bytes.
6. A byte class can [exclude specific terminals](docs/grammar_guidelines.md#3-terminal-symbols), which it then never matches.
7. Where two terminals share a prefix, the input is matched to the longest terminal that fits.
8. A grammar can carry [annotations](docs/grammar_guidelines.md) that attach hooks, flatten variables, declare synchronization points and mark verbatim capture.
9. A symbol annotated for [verbatim capture](docs/grammar_guidelines.md#8-verbatim-raw-capture-----) matches every input byte up to its terminator, without parsing those bytes.
10. With [indentation-sensitive input](docs/grammar_guidelines.md#6-indentation-sensitive-grammars) enabled, the block start and block end terminals match where the indentation of a line rises and falls.
11. With a [newline token after a block ends](docs/grammar_guidelines.md#6-indentation-sensitive-grammars) enabled, a newline is also matched where a block ends.

## 2. Parser generation

Galley turns a valid grammar into a parser, and rejects an invalid grammar before generating anything, stating what is wrong and where.

1. The [command-line tool](docs/configuration.md#generator-cli-options) and the [Zig library API](docs/using-galley.md#generate-parser-source-from-zig) generate the same parser source file from the same grammar.
2. A grammar is generated for exactly one [parsing strategy](docs/languages.md#choosing-between-ll-and-lr), LL or LR.
3. LL generation accepts every grammar that is LL(1) over its terminals, and every grammar that becomes LL(1) once shared prefixes of productions are [factored automatically](docs/grammar_guidelines.md#7-operator-precedence--ambiguity-free-expression-extraction); terminals are matched by longest match.
4. LR generation accepts every grammar that is [canonical LR(1)](docs/architecture.md#role-of-the-self-hosted-generator) over its terminals.
5. A grammar that its parsing strategy cannot parse without conflict, including an ambiguous grammar, is rejected with an [explanation](docs/architecture.md#ambiguity-diagnostics) of where the conflict comes from.
6. LR generation rejects a grammar in which two [hook placements](docs/procedures.md#hook-execution-order) cannot be told apart, and says which placements.
7. Every grammar error is reported as a line and column in the grammar source.
8. A rejected grammar writes no parser source and leaves every existing file unchanged.
9. When [requested](docs/configuration.md#generator-cli-options), generation rejects a grammar in which any production has no reduction hook.
10. Generation never overwrites a grammar, configuration or hook source file, and changes an error-message file only when [asked](docs/configuration.md#generator-cli-options) to fill in missing messages, keeping every existing one.
11. The same grammar and options always generate byte-identical parser source.
12. Automatic factoring of shared prefixes never changes the syntax tree or the order of explicitly attached hooks.

## 3. Parser options

Every parser recognizes its grammar's language. Each parser option is enabled or disabled when the parser is compiled; the set of values a parser is compiled with is its [configuration](docs/configuration.md#the-configzig-contract). A parser option that is not enabled costs nothing and adds nothing to the interface. Every meaningful configuration works, including one with no parser option enabled.

1. A parser's configuration, fixed when the parser is compiled, enables or disables each of these [parser options](docs/configuration.md#the-configzig-contract): the [syntax tree](#5-syntax-tree), [tree nodes for individual terminals](#5-syntax-tree), [hooks](#6-hooks), [error recovery](#7-errors-and-recovery), [line and column tracking](docs/configuration.md#the-configzig-contract), [reading a file in a bounded window](docs/configuration.md#the-configzig-contract), [indentation-sensitive input](#1-grammar-language), [a newline token after a block ends](#1-grammar-language), and [error message templates](#7-errors-and-recovery).
2. Tree nodes for individual terminals require the syntax tree or hooks, and enabling them with neither is refused when the parser is compiled.
3. A newline token after a block ends requires indentation-sensitive input, and enabling it without that is refused when the parser is compiled.
4. A grammar that uses the [block start or block end terminals](#1-grammar-language) is refused when the parser is compiled with indentation-sensitive input disabled.
5. Whether an input contains a syntax error does not depend on which parser options are enabled, except for the options that change the grammar's meaning: indentation-sensitive input and a newline token after a block ends.
6. The [maximum error count](#7-errors-and-recovery) and the [message overrides](#7-errors-and-recovery) are set per session.

## 4. Parsing and input

A parser accepts exactly the input that belongs to its grammar's language, regardless of how the input is supplied.

1. A parse reads its input from [bytes in memory, from a file](docs/using-galley.md#parse-input-from-zig), or from a source that the caller supplies.
2. A chunk of zero bytes from a caller-supplied source does not end the input; only the source's end signal does.
3. A parser reads input as bytes, applies no character-encoding conversion and does not check that the input is valid in any encoding.
4. A parse finishes within the call that started it.
5. The user can convert any offset in a parse's input into a line and column, whatever the configuration.

## 5. Syntax tree

When the syntax tree parser option is enabled, a parse produces a [syntax tree](docs/ast_node_allocations.md#1-structural-node-allocations-is_ast_enabled) whose shape follows the grammar and its annotations, and the user can read and edit that tree without corrupting it.

1. A parse builds one node for each occurrence of a grammar variable that it recognizes in the input, except for a variable whose name starts with an underscore.
2. Nothing in the subtree of a variable whose name starts with an underscore builds a node or runs a hook.
3. A variable declared [flattened](docs/grammar_guidelines.md#9-flattening) builds no node, and its children take its place among the children of its parent, in input order.
4. With [tree nodes for individual terminals](docs/ast_node_allocations.md#2-terminal-ast-allocations-ast-for-terminals) enabled, each terminal that the parser recognizes becomes a node among the children of the node for the variable that contains it.
5. Each node reports the variable or terminal it was built for.
6. Each node reports its span as a start offset and an end offset in the input, and its matched text is exactly the input bytes of that span.
7. A node's matched text stays readable after the caller releases its input.
8. From any node, the user can reach its parent, its children in input order, and its previous and next siblings.
9. The user can [walk](docs/bindings_c.md#walking-the-ast) the subtree under any node, visiting each node of it exactly once.
10. The user can [insert](docs/bindings_c.md#editing-the-tree) a node, or a chain of consecutive siblings, at a chosen position among the children of a chosen node.
11. The user can remove a node, or a chain of consecutive siblings, from the tree; each removed node keeps its subtree and is detached from the tree.
12. After every accepted edit, the parent, child and sibling relations of all nodes agree with one another.
13. An edit never changes the span of any other node.
14. Nodes inserted or removed by a hook during a parse are inserted or removed in the tree that the parse publishes.
15. When the user declares a [payload type](docs/procedures.md#custom-ast-node-payload), each node holds one value of that type, which the user can read and write.

## 6. Hooks

The user can attach code to points in the grammar ([hooks](docs/procedures.md)). The parser runs that code each time it recognizes the part of the grammar the code is attached to. The code can compute results, edit the syntax tree and report errors.

1. The user can [attach a hook](docs/procedures.md#explicit-hook-annotations) to a variable, to a production, or to one occurrence of a symbol in a production.
2. A hook named after a variable, after a production of the variable, or after a terminal, attaches to that part without an annotation (see [automatic hooks](docs/procedures.md#implicit--automatic-hooks)).

3. A hook runs only after the parser has recognized all of the part it is attached to.
4. Hooks attached to the same part run in a defined, [documented order](docs/procedures.md#hook-execution-order).
5. A hook written in Zig always runs when hooks are enabled.
6. Hooks written in a host language are [installed per session](docs/bindings_c.md#host-hooks): each session starts with a copy of its parser's default hooks, and runs exactly the hooks installed on it.
7. A hook receives the node for the part it is attached to and, unless it is a terminal hook, the production that matched.
8. The node that a hook receives has no parent when the hook runs.
9. Hooks [pass results upward](docs/procedures.md#no-ast-reduction-channel) through the payloads of their nodes, and the payload of the start symbol is returned with the parse result, with or without a syntax tree.
10. Without a syntax tree, a hook's tree edits have no effect.
11. A hook that reports a [semantic error](docs/procedures.md#semantic-errors) receives back the number of semantic errors recorded so far in the parse.
12. A hook that [fails](docs/procedures.md#failing-a-hook) stops the parse, and no further hook runs.
13. A hook does not run for a part that error recovery damaged.
14. Hooks of enclosing parts that are completed after an error recovery do run.

## 7. Errors and recovery

Every problem found during a parse, whether a syntax error or an error reported by a hook, is recorded with its location and a readable message. What the parser does after a syntax error is [defined](docs/syntax_error_recovery.md#syntax-error-recovery).

1. Each recorded error carries the byte offset in the input where it was found, and its line and column, except in two parsers without [line and column tracking](#3-parser-options): one that reads in a [bounded window](docs/configuration.md#the-configzig-contract), and an indentation-syntax parser streaming a file.
2. After a parse, the session holds the errors of that parse in the order they were recorded.
3. The user can [customize error messages](docs/syntax_error_recovery.md#syntax-error-messages) with [per-session overrides](docs/configuration.md#syntax-error-message-overrides), with compile-time templates, and with message functions written with the hooks.
4. The precedence among these customizations is defined and documented.
5. An error that none of these customizations covers has the built-in message, which names what was found and what was expected.
6. A parse stops when the number of syntax errors it has recorded reaches the [maximum error count](docs/configuration.md#runtime-api-options) of its session; semantic errors do not count toward that limit.
7. Without error recovery, the first syntax error stops the parse.
8. When the grammar declares [synchronization points](docs/grammar_guidelines.md#5-explicit-syntax-recovery-), the parser resumes after a syntax error only at a synchronization point.
9. If no synchronization point follows a syntax error before the end of the input, the parse fails.
10. A semantic error does not stop the parse.
11. A parse with semantic errors and no syntax errors reports a semantic-error failure and publishes its tree.
12. A semantic error marks the node held by the hook that reported it, and no other node.
13. A parse that recovered from syntax errors reports a syntax-error failure and publishes its tree.
14. A part of the published tree that the parser built while recovering is [marked as recovered](docs/syntax_error_recovery.md#recovered-trees).
15. A parse that has both syntax errors and semantic errors reports the syntax-error failure.
16. A parse that fails without having recovered publishes no tree.
17. The failure of a parse that publishes no tree states what happened and the position in the input where the parse stopped.

## 8. Platforms

Parsers run on the supported native platforms and on WebAssembly, and behave identically on all of them, except for the differences listed in [Platform differences](#platform-differences).

1. A parser runs on Unix-like systems (such as Linux, macOS and the BSDs) and on WebAssembly.
2. For the same grammar, configuration and input, every platform accepts the same input, builds the same tree, runs the same hooks in the same order and records the same errors, except for the differences listed in [Platform differences](#platform-differences).
3. One generated parser source file builds for every one of these platforms.

## 9. Sessions, lifetimes and concurrency

One parser can serve many parses, one after another or in parallel, and no parse affects another (see [concurrency](docs/concurrency.md)). The contract states how long each object stays valid and which uses of it may happen at the same time.

1. Any number of sessions, of one parser or of different parsers, can parse in parallel without the caller coordinating them.
2. A session may be used from any thread.
3. While a parse is running on a session, nothing except the hooks of that parse may use the session.
4. The hooks of a running parse may use only the tree that parse is building.
5. A parse publishes its result to its session.
6. A published tree stays valid until a parse begins on its session, whether that parse succeeds or fails, or until the session is closed.
7. A parse that is refused leaves the published tree valid.
8. Any number of threads may read a published tree at the same time.
9. An edit of a published tree cannot overlap any other read or edit of that tree.
10. A parse cannot start on a session, and the session cannot be closed, while a thread reads or edits its published tree.
11. A use of a session that the rules above do not allow is refused immediately; it never waits for the other use to finish.
12. The caller may release or change its input as soon as the call that parsed it returns.

## 10. Performance and footprint

Galley aims for [bare-metal parsing speed](docs/benchmarks.md) and a small footprint.

1. When the [syntax tree](#5-syntax-tree), [hooks](#6-hooks) and [verbatim capture](#1-grammar-language) are all disabled, [reading a file in a bounded window](#3-parser-options) keeps the memory a parse uses independent of the size of the file.

## 11. Safety and misuse

No input can make a parser corrupt memory or use resources without limit. Every misuse of the interface is detected, except that ReleaseFast and ReleaseSmall builds do not check tree edits. The correctness of hooks, and of tree edits in those builds, is the user's responsibility.

1. A use of the interface that breaks a rule of [section 9](#9-sessions-lifetimes-and-concurrency) is refused with an error.
2. A refused use changes nothing: the session, its published tree and its recorded errors stay as they were.
3. A refused use is reported as a refusal, distinct from the failure of a parse.
4. Except in ReleaseFast and ReleaseSmall builds, a tree edit that would corrupt the tree is detected and stops the program.
5. Through the C ABI, a tree edit with an index or count outside the tree is refused with an error in every build.
6. A parse that runs out of memory, runs out of tree storage, or fails to read its input fails its call and publishes no tree and no result.
7. Input nested deeper than its thread's stack can hold ends the process, unless the experimental [stack-overflow recovery](docs/architecture.md#optional-stack-overflow-recovery) is enabled on a platform that has it.

## 12. Core interface

Everything in this contract is available through the core interface, called directly from Zig or through the [C ABI](docs/bindings_c.md), and the behavior of every call is fully specified. Host-language bindings are built on this interface; the [bindings contract](bindings/CONTRACTS.md) states what each binding exposes.

1. Everything in this contract is available both from Zig and through the C ABI, except user-defined node payloads, which are available from Zig only.
2. A call made through the C ABI behaves as the same call made from Zig.
3. Both are available on every platform that [section 8](#8-platforms) lists.
4. The C ABI reports every failure as a numbered status code, and each status code has one number and one readable name.
5. Each of these outcomes has its own status code: a parse with syntax errors, a parse with semantic errors, a refused use, running out of memory, running out of tree storage, and failing to read the input.

## 13. Evolution

Galley's interface and behavior never change without a matching change to the contract. The contract states what compatibility users can rely on.

1. Until alpha begins, the Zig interface, the C ABI, the command-line tool and the library API may change in any way, with no compatibility promise.
2. Every consumer in the Galley project is changed in the same change as the interface it uses.
3. No change to the interface or to behavior is made without a matching change to this contract.
4. The compatibility that users can rely on after alpha will be stated in this contract before alpha begins.

## Platform differences

| Platform | Difference |
| --- | --- |
| Every platform except Linux and macOS | Experimental stack-overflow recovery is not available. |
