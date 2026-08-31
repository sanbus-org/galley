// Procedure hooks for the keyvalue grammar.
//
// Shows ProcedureArguments in action: the current node, its text, children,
// and source position, plus DropIfEmpty on empty tails. Author-defined
// grammar hooks arrive as hook_<name> — Key is annotated @print.
package main

import (
	"fmt"
	"os"
	"unsafe"

	galley "github.com/sanbus-org/galley/examples/go/demo/galley"
)

/*
#include <stdlib.h>
*/
import "C"

func textOf(session *galley.Session, node galley.Node) []byte {
	text, ok := session.Text(node)
	if !ok {
		return nil
	}
	return text
}

func nameOf(session *galley.Session, node galley.Node) string {
	bytes, ok := session.SymbolName(node)
	if !ok {
		return ""
	}
	return string(bytes)
}

func posOf(session *galley.Session, node galley.Node) (uint32, uint32) {
	line, column, _ := session.LineColumn(node)
	return line, column
}

func parseU(bytes []byte) uint {
	var value uint
	for _, b := range bytes {
		if b >= '0' && b <= '9' {
			value = value*10 + uint(b-'0')
		}
	}
	return value
}

func countPairs(session *galley.Session, node galley.Node) (uint, uint) {
	if nameOf(session, node) == "Pair" {
		text := textOf(session, node)
		number := text
		for i, b := range text {
			if b == ':' {
				number = text[i+1:]
				break
			}
		}
		return 1, parseU(number)
	}
	var count, total uint
	for _, child := range session.Children(node) {
		childCount, childSum := countPairs(session, child)
		count += childCount
		total += childSum
	}
	return count, total
}

func emit(line string) {
	_, _ = os.Stderr.WriteString(line)
}

//export reduction
func reduction(_ unsafe.Pointer) {}

//export reduction_Key
func reduction_Key(_ unsafe.Pointer) {}

//export reduction_PairList
func reduction_PairList(_ unsafe.Pointer) {}

//export reduction_KeyTail
func reduction_KeyTail(ptr unsafe.Pointer) {
	_ = galley.Args(ptr).DropIfEmpty()
}

//export reduction_NumberTail
func reduction_NumberTail(ptr unsafe.Pointer) {
	_ = galley.Args(ptr).DropIfEmpty()
}

//export reduction_PairListTail
func reduction_PairListTail(ptr unsafe.Pointer) {
	_ = galley.Args(ptr).DropIfEmpty()
}

//export hook_print
func hook_print(ptr unsafe.Pointer) {
	args := galley.Args(ptr)
	session := args.Session()
	node, ok := args.CurrentNode()
	if session == nil || !ok {
		return
	}
	line, column := posOf(session, node)
	emit(fmt.Sprintf("@print %q at %d:%d\n", string(textOf(session, node)), line, column))
}

//export reduction_Number
func reduction_Number(ptr unsafe.Pointer) {
	args := galley.Args(ptr)
	session := args.Session()
	node, ok := args.CurrentNode()
	if session == nil || !ok {
		return
	}
	line, column := posOf(session, node)
	emit(fmt.Sprintf("Number %s at %d:%d\n", string(textOf(session, node)), line, column))
}

//export reduction_Pair
func reduction_Pair(ptr unsafe.Pointer) {
	args := galley.Args(ptr)
	session := args.Session()
	node, ok := args.CurrentNode()
	if session == nil || !ok {
		return
	}
	line, column := posOf(session, node)
	text := string(textOf(session, node))
	key, number := text, ""
	for i := 0; i < len(text); i++ {
		if text[i] == ':' {
			key = text[:i]
			number = text[i+1:]
			break
		}
	}
	emit(fmt.Sprintf("Pair %s=%s (%d children) at %d:%d\n", key, number, session.ChildCount(node), line, column))
}

//export reduction_Document
func reduction_Document(ptr unsafe.Pointer) {
	args := galley.Args(ptr)
	session := args.Session()
	node, ok := args.CurrentNode()
	if session == nil || !ok {
		return
	}
	count, total := countPairs(session, node)
	emit(fmt.Sprintf("Document %d pairs, sum=%d\n", count, total))
}
