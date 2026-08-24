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
)

/*
#include <stdlib.h>
*/
import "C"

//export reduction
func reduction(_ unsafe.Pointer) {
	fmt_hook("reduction")
}

//export reduction_Document
func reduction_Document(_ unsafe.Pointer) {
	fmt_hook("Document")
}

//export reduction_PairList
func reduction_PairList(_ unsafe.Pointer) {
	fmt_hook("PairList")
}

//export reduction_PairListTail
func reduction_PairListTail(_ unsafe.Pointer) {}

//export reduction_Pair
func reduction_Pair(_ unsafe.Pointer) {
	fmt_hook("Pair")
}

//export reduction_Key
func reduction_Key(_ unsafe.Pointer) {
	fmt_hook("Key")
}

//export hook_print
func hook_print(_ unsafe.Pointer) {
	fmt_hook("print (Key)")
}

//export reduction_KeyTail
func reduction_KeyTail(_ unsafe.Pointer) {}

//export reduction_Number
func reduction_Number(_ unsafe.Pointer) {
	fmt_hook("Number")
}

//export reduction_NumberTail
func reduction_NumberTail(_ unsafe.Pointer) {}

func fmt_hook(name string) {
	os.Stderr.WriteString("[hook] " + name + "\n") //nolint:errcheck
}
