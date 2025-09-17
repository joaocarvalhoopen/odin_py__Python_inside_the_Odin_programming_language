// This is only an experiment to see if it works
// and to test the ergonomics of having Python code inside Odin code.
// License: MIT Oopen Source

package main

import "core:fmt"

import py "./odin_py"

main :: proc ( ) {
    
    fmt.printfln( "\n\nBegin odin_py...\n\n" )
    
    py.test_eval_01( )
    
    fmt.printfln( "\n\n...end odin_py.\n\n" )
}
