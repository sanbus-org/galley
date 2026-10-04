// Procedure hooks for the keyvalue grammar.
package testfixture

import (
	"fmt"
	"os"
	"unsafe"

	galley "github.com/sanbus-org/galley/bindings/go/testfixture/galley"
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

// probeStaleReads reads a node of an earlier parse through the hook door
// with every capability, returning each call's error.
func probeStaleReads(door galley.HookDoor, node galley.Node) []error {
	var errs []error
	_, err := door.ChildCount(node)
	errs = append(errs, err)
	_, _, err = door.FirstChild(node)
	errs = append(errs, err)
	_, _, err = door.LastChild(node)
	errs = append(errs, err)
	_, _, err = door.NextSibling(node)
	errs = append(errs, err)
	_, _, err = door.PriorSibling(node)
	errs = append(errs, err)
	_, _, err = door.Parent(node)
	errs = append(errs, err)
	_, err = door.SymbolName(node)
	errs = append(errs, err)
	_, err = door.Text(node)
	errs = append(errs, err)
	_, _, err = door.Span(node)
	errs = append(errs, err)
	_, _, err = door.LineColumn(node)
	errs = append(errs, err)
	_, err = door.Children(node)
	errs = append(errs, err)
	_, _, err = door.Walk(node, false).Next()
	return append(errs, err)
}

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
	node, ok, err := args.CurrentNode()
	if err != nil || !ok {
		return
	}
	line, column := posOf(door, node)
	emit(fmt.Sprintf("@print %q at %d:%d\n", string(textOf(door, node)), line, column))
}

//export reduction_Number
func reduction_Number(ptr unsafe.Pointer) {
	args := galley.Args(ptr)
	door := args.Door()
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

// Recorded for door_test.go: the first Pair's door and node, and what that
// earlier door still answers from a later hook of the same parse. For
// walk_test.go: the walk reduction_Document ran over the in-flight tree
// through its hook door.
var (
	firstPairSeen       bool
	firstPairDoor       galley.HookDoor
	firstPairNode       galley.Node
	laterHookSharesDoor bool
	laterHookChildCount uint32
	hookWalkVisits      []galley.WalkStep
	hookWalkErr         error
	// sessionProbe is the session under test; reduction_Document reads its
	// root through the session door mid-parse, which the core refuses.
	sessionProbe *galley.Session
	hookRootErr  error
	// previousDocument is the Document node of the parse before, kept
	// across parses by door_test.go's stale test; staleReads records what
	// every hook-door read of it answered during the next parse.
	previousDocument galley.Node
	previousSeen     bool
	staleReads       []error
)

func resetDoorRecording() {
	firstPairSeen = false
	laterHookSharesDoor = false
	laterHookChildCount = 0
	hookWalkVisits = nil
	hookWalkErr = nil
	sessionProbe = nil
	hookRootErr = nil
	staleReads = nil
	previousSeen = false
	keptWalker, keptDoor, keptNode = nil, galley.HookDoor{}, galley.Node{}
	keptInHookWalkErr, keptInHookCountErr = nil, nil
	siblingParseErr, doorAfterSiblingErr = nil, nil
}

//export reduction_Pair
func reduction_Pair(ptr unsafe.Pointer) {
	args := galley.Args(ptr)
	door := args.Door()
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
	if !firstPairSeen {
		firstPairSeen = true
		firstPairDoor = door
		firstPairNode = node
	}
}

//export reduction_Document
func reduction_Document(ptr unsafe.Pointer) {
	args := galley.Args(ptr)
	door := args.Door()
	node, ok, err := args.CurrentNode()
	if err != nil || !ok {
		return
	}
	if sessionProbe != nil {
		_, _, hookRootErr = sessionProbe.RootNode()
	}
	if previousSeen {
		staleReads = probeStaleReads(door, previousDocument)
	}
	previousDocument, previousSeen = node, true
	count, total := countPairs(door, node)
	emit(fmt.Sprintf("Document %d pairs, sum=%d\n", count, total))
	if firstPairSeen {
		laterHookSharesDoor = firstPairDoor == door
		laterHookChildCount = childCountOf(firstPairDoor, firstPairNode)
	}
	// door_test.go's kept door: the door and a walker made from it, kept past
	// the parse. Inside this hook, both still work.
	// The kept walker is not stepped here: its first step is the first call
	// after the parse, the one a door that read the dead parse would answer.
	keptWalker, keptDoor, keptNode = door.Walk(node, false), door, node
	_, _, keptInHookWalkErr = door.Walk(node, false).Next()
	_, keptInHookCountErr = keptDoor.ChildCount(node)
	// door_test.go's sibling parse: another session parses to the end inside
	// this hook, and this parse's door must still work afterwards. The
	// sibling is cleared first, so its own hooks do not parse again.
	if sibling := siblingSession; sibling != nil {
		siblingSession = nil
		_, siblingParseErr = sibling.Parse([]byte("omega:7"))
		_, doorAfterSiblingErr = door.ChildCount(node)
	}
	// walk_test.go's hook walk: over this parse's in-flight tree, stepped
	// through the parse's own door.
	walker := door.Walk(node, false)
	for {
		step, ok, err := walker.Next()
		if err != nil {
			hookWalkErr = err
			break
		}
		if !ok {
			break
		}
		hookWalkVisits = append(hookWalkVisits, step)
	}
}

// A door and a walker a hook keeps (door_test.go), with the errors their calls
// answered inside that hook.
var (
	keptWalker         *galley.Walker
	keptDoor           galley.HookDoor
	keptNode           galley.Node
	keptInHookWalkErr  error
	keptInHookCountErr error
)

// door_test.go's sibling parse: the session parsed inside a hook, and what
// that parse and this parse's door answered afterwards.
var (
	siblingSession      *galley.Session
	siblingParseErr     error
	doorAfterSiblingErr error
)
