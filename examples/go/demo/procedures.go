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
func reduction(_ unsafe.Pointer, _hook C.ulonglong) {}

//export reduction_Key
func reduction_Key(_ unsafe.Pointer, _hook C.ulonglong) {}

//export reduction_PairList
func reduction_PairList(_ unsafe.Pointer, _hook C.ulonglong) {}

//export reduction_KeyTail
func reduction_KeyTail(session unsafe.Pointer, hook C.ulonglong) {
	_ = galley.Args(session, uint64(hook)).DropIfEmpty()
}

//export reduction_NumberTail
func reduction_NumberTail(session unsafe.Pointer, hook C.ulonglong) {
	_ = galley.Args(session, uint64(hook)).DropIfEmpty()
}

//export reduction_PairListTail
func reduction_PairListTail(session unsafe.Pointer, hook C.ulonglong) {
	_ = galley.Args(session, uint64(hook)).DropIfEmpty()
}

//export hook_print
func hook_print(session unsafe.Pointer, hook C.ulonglong) {
	args := galley.Args(session, uint64(hook))
	door, err := args.Door()
	if err != nil {
		return
	}
	node, ok, err := args.CurrentNode()
	if err != nil || !ok {
		return
	}
	line, column := posOf(door, node)
	emit(fmt.Sprintf("@print %q at %d:%d\n", string(textOf(door, node)), line, column))
}

//export reduction_Number
func reduction_Number(session unsafe.Pointer, hook C.ulonglong) {
	args := galley.Args(session, uint64(hook))
	door, err := args.Door()
	if err != nil {
		return
	}
	node, ok, err := args.CurrentNode()
	if err != nil || !ok {
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
func reduction_Pair(session unsafe.Pointer, hook C.ulonglong) {
	args := galley.Args(session, uint64(hook))
	door, err := args.Door()
	if err != nil {
		return
	}
	node, ok, err := args.CurrentNode()
	if err != nil || !ok {
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
func reduction_Document(session unsafe.Pointer, hook C.ulonglong) {
	args := galley.Args(session, uint64(hook))
	door, err := args.Door()
	if err != nil {
		return
	}
	node, ok, err := args.CurrentNode()
	if err != nil || !ok {
		return
	}
	count, total := countPairs(door, node)
	emit(fmt.Sprintf("Document %d pairs, sum=%d\n", count, total))
}
