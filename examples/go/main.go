// Command galley-go-example parses a small key/value document through the
// Galley Go bindings, mirroring examples/c, examples/cpp, and examples/rust
// byte-for-byte in output.
package main

import (
	"errors"
	"fmt"
	"os"

	galley "github.com/sanbus-org/galley/examples/go/galley"
)

//go:generate go run github.com/sanbus-org/galley/bindings/go/cmd/galley gen .

func printTree(session *galley.Session, node galley.Node, depth int) {
	name := ""
	if bytes, ok := session.SymbolName(node); ok {
		name = string(bytes)
	}
	textLength := 0
	if text, ok := session.Text(node); ok {
		textLength = len(text)
	}
	line, _, _ := session.LineColumn(node)

	for i := 0; i < depth; i++ {
		fmt.Print("  ")
	}
	fmt.Printf("%s [line %d, %d bytes]\n", name, line, textLength)

	for _, child := range session.Children(node) {
		printTree(session, child, depth+1)
	}
}

func main() {
	fmt.Printf("galley version: %s\n", galley.Version())
	session, err := galley.WithOptions(galley.DefaultOptions())
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to create a parser session\n")
		os.Exit(1)
	}
	defer session.Close()

	/* With a path argument: parse the file and nothing else. */
	args := os.Args[1:]
	if len(args) > 0 {
		parsed, err := session.ParseFile(args[0])
		if err != nil {
			var galleyErr galley.Error
			if diagnostic, ok := session.Diagnostic(); ok && errors.As(err, &galleyErr) {
				fmt.Fprintf(os.Stderr, "%s:%d:%d: %s\n", args[0], diagnostic.Line, diagnostic.Column, diagnostic.Message)
			} else {
				fmt.Fprintf(os.Stderr, "parse failed: %v\n", err)
			}
			os.Exit(1)
		}
		fmt.Printf("parsed %d bytes\n", parsed)
		return
	}

	/* Successful parse: walk the tree. */
	const validSample = "alpha:12,beta:3"
	parsed, err := session.ParseSentinel(validSample)
	if err != nil {
		fmt.Fprintf(os.Stderr, "unexpected failure: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("parsed %d bytes, %d AST nodes\n", parsed, session.NodeCount())
	if !galley.HasAST() {
		fmt.Println("AST construction disabled; skipping tree walk")
	} else if root, ok := session.RootNode(); ok {
		printTree(session, root, 1)
	}

	/* Failed parse: inspect the diagnostic. */
	if _, err := session.ParseSentinel("alpha:"); err == nil {
		fmt.Fprintf(os.Stderr, "expected the broken sample to fail\n")
		os.Exit(1)
	}
	diagnostic, ok := session.Diagnostic()
	if !ok {
		fmt.Fprintf(os.Stderr, "expected a diagnostic for the broken sample\n")
		os.Exit(1)
	}
	fmt.Printf("diagnostic at %d:%d: %s\n", diagnostic.Line, diagnostic.Column, diagnostic.Message)

	fmt.Print("expected one of: ")
	for index, token := range diagnostic.ExpectedTokens {
		if index != 0 {
			fmt.Print(", ")
		}
		fmt.Printf("'%s'", token)
	}
	fmt.Println()
	fmt.Print("while parsing (innermost first):")
	for _, name := range diagnostic.Context {
		fmt.Printf(" %s", name)
	}
	fmt.Println()

	/* File parsing. */
	const path = "/tmp/galley-go-example.json"
	if err := os.WriteFile(path, []byte(validSample), 0o644); err != nil {
		fmt.Fprintf(os.Stderr, "failed to write %s\n", path)
		os.Exit(1)
	}
	fileParsed, err := session.ParseFile(path)
	if err != nil {
		fmt.Fprintf(os.Stderr, "file parse failed: %v\n", err)
		os.Exit(1)
	}
	info, _ := session.Info()
	fmt.Printf("file parse: %d bytes, ended at %d:%d\n", fileParsed, info.EndLine, info.EndColumn)

	/* Tree editing: detach the root's children, then reattach them. */
	if galley.HasAST() {
		root, ok := session.RootNode()
		if !ok {
			fmt.Fprintf(os.Stderr, "expected a root node\n")
			os.Exit(1)
		}
		childrenBefore := session.ChildCount(root)
		head, headOk, err := session.TreeCleanChildren(root)
		if err != nil || !headOk {
			fmt.Fprintf(os.Stderr, "expected the root to have children\n")
			os.Exit(1)
		}
		if err := session.TreeAppendChildren(root, head); err != nil {
			fmt.Fprintf(os.Stderr, "failed to reattach children: %v\n", err)
			os.Exit(1)
		}
		fmt.Printf("tree edit: %d children before, %d after reattach\n", childrenBefore, session.ChildCount(root))
	}
}
