// Command hooks implements the keyvalue grammar's procedure hooks in Go.
//
// The gen command parses this file's //export directives, generates a Zig
// shim module with one slot per grammar hook, and registers these
// functions' addresses into those slots when the consumer binary starts.
// The parser library stays runtime-free: your code is compiled here, in
// the host binary, by its ordinary go build — it is only *called from*
// the library through plain function pointers.
package hooks

import (
	"os"
	"unsafe"

	galley "github.com/sanbus-org/galley/examples/go/galley"
)

/*
#include <stdlib.h>
*/
import "C"

func note(label string, ptr unsafe.Pointer) {
	args := galley.Args(ptr)
	if session := args.Session(); session != nil {
		if node, ok := args.CurrentNode(); ok {
			_, _ = session.Text(node)
			_ = session.ChildCount(node)
		}
	}
	os.Stderr.WriteString("[hook] " + label + "\n") //nolint:errcheck
}

//export reduction
func reduction(ptr unsafe.Pointer) {
	note("reduction", ptr)
}

//export reduction_Document
func reduction_Document(ptr unsafe.Pointer) {
	note("Document", ptr)
}

//export reduction_PairList
func reduction_PairList(ptr unsafe.Pointer) {
	note("PairList", ptr)
}

//export reduction_PairListTail
func reduction_PairListTail(_ unsafe.Pointer) {}

//export reduction_Pair
func reduction_Pair(ptr unsafe.Pointer) {
	note("Pair", ptr)
}

//export reduction_Key
func reduction_Key(ptr unsafe.Pointer) {
	note("Key", ptr)
}

//export hook_print
func hook_print(ptr unsafe.Pointer) {
	note("print (Key)", ptr)
}

//export reduction_KeyTail
func reduction_KeyTail(_ unsafe.Pointer) {}

//export reduction_Number
func reduction_Number(ptr unsafe.Pointer) {
	note("Number", ptr)
}

//export reduction_NumberTail
func reduction_NumberTail(_ unsafe.Pointer) {}
