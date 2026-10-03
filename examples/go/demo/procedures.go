// Procedure hooks for the keyvalue grammar.
//
// Shows ProcedureArguments in action: the current node, its text, children,
// and source position, plus DropIfEmpty on empty tails. Author-defined
// grammar hooks arrive as hook_<name> — Key is annotated @print.
//
// Tree queries go through the parse's hook door: take it from the arguments
// with Door, then use its NodeDoor methods. The door is unshared by
// construction and valid for the whole parse.
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

func textOf(door galley.NodeDoor, node galley.Node) []byte {
	text, err := door.Text(node)
	if err != nil {
		return nil
	}
	return text
}

func nameOf(door galley.NodeDoor, node galley.Node) string {
	bytes, err := door.SymbolName(node)
	if err != nil {
		return ""
	}
	return string(bytes)
}

func posOf(door galley.NodeDoor, node galley.Node) (uint32, uint32) {
	line, column, _ := door.LineColumn(node)
	return line, column
}

func childCountOf(door galley.NodeDoor, node galley.Node) uint32 {
	count, _ := door.ChildCount(node)
	return count
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

func countPairs(door galley.NodeDoor, node galley.Node) (uint, uint) {
	if nameOf(door, node) == "Pair" {
		text := textOf(door, node)
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
	children, _ := door.Children(node)
	for _, child := range children {
		childCount, childSum := countPairs(door, child)
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
	door := args.Door()
	node, ok := args.CurrentNode()
	if !ok {
		return
	}
	line, column := posOf(door, node)
	emit(fmt.Sprintf("@print %q at %d:%d\n", string(textOf(door, node)), line, column))
}

//export reduction_Number
func reduction_Number(ptr unsafe.Pointer) {
	args := galley.Args(ptr)
	door := args.Door()
	node, ok := args.CurrentNode()
	if !ok {
		return
	}
	line, column := posOf(door, node)
	emit(fmt.Sprintf("Number %s at %d:%d\n", string(textOf(door, node)), line, column))
	var value uint64
	for _, digit := range textOf(door, node) {
		if digit < '0' || digit > '9' {
			return
		}
		value = value*10 + uint64(digit-'0')
	}
	if value > 999 {
		_, _ = args.ReportSemanticError("value out of range")
	}
}

//export reduction_Pair
func reduction_Pair(ptr unsafe.Pointer) {
	args := galley.Args(ptr)
	door := args.Door()
	node, ok := args.CurrentNode()
	if !ok {
		return
	}
	line, column := posOf(door, node)
	text := string(textOf(door, node))
	key, number := text, ""
	for i := 0; i < len(text); i++ {
		if text[i] == ':' {
			key = text[:i]
			number = text[i+1:]
			break
		}
	}
	emit(fmt.Sprintf("Pair %s=%s (%d children) at %d:%d\n", key, number, childCountOf(door, node), line, column))
}

//export reduction_Document
func reduction_Document(ptr unsafe.Pointer) {
	args := galley.Args(ptr)
	door := args.Door()
	node, ok := args.CurrentNode()
	if !ok {
		return
	}
	count, total := countPairs(door, node)
	emit(fmt.Sprintf("Document %d pairs, sum=%d\n", count, total))
}
