// This is only an experiment to see if it works
// and to test the ergonomics of having Python code inside Odin code.
// License: MIT Oopen Source

package odin_py

import "core:fmt"
import "core:os"
import "core:strings"
import "core:slice"
import "core:time"
import "core:strconv"


// Assumimos a existência de bibliotecas para:
// - file_watcher : To observe the v_in diretory, to know when file are written to the diretory.
// - numpy : Allow numpy matrixes of f64 and complex128 ( P_np_matrix ).
// - json : for serialization / deserialization of lists and maps.

// Diretories
ODIN_PY_OUT_DIR :: "/dev/shm/odin_py/out/"    // Odin   ---->>> Python       Where Odin writes and Python reads.
ODIN_PY_IN_DIR  :: "/dev/shm/odin_py/in/"     // Python ---->>> Odin         Where Python writes and Odin reads.

// --- Tipos de dados (como no seu exemplo) ---
P_int       :: int
P_float     :: f64
P_string    :: string
// P_np_matrix :: numpy.Matrix       // Kind of matrix Numpy floats or complex f64.
// P_list      :: [ dynamic ]any     // Dynamic List.
// P_map       :: map[ string ]any   // Map.

// Auxilary function to write a generic variable.
write_variable_to_file :: proc(var_name: string, data: any) -> ( ok : bool ) {
    
    // 1. Find the type of the output variable and construct the filename.
    filename: string
    content: []byte
    
    switch type in data {
    case P_int:
        filename = fmt.aprintf( "%s%s", "p_int_", var_name )
        
        // content = make( [ ]byte, size_of( int ) )
        // strconv.write_int( content, ( ^i64 )( data.data )^ , 10 )
         
        tmp := fmt.aprintf( "%d", ( ^i64 )( data.data )^ )
        content = transmute( [ ]u8 )tmp
    case P_float:
        filename = fmt.aprintf( "%s%s", "p_float_", var_name )
        // content = make( [ ]byte, size_of( f64 ) )
        
        tmp := fmt.aprintf( "%g", ( ^f64 )( data.data )^ )
        content = transmute( [ ]u8 )tmp
    case P_string:
        filename = fmt.aprintf( "%s%s", "p_string_", var_name )
        content = transmute( [ ]u8 )( ( ^string )( data.data )^)

/*        
    case P_np_matrix:
        // Custom serialization for numpy.
        // First line : shape (ex: "100 50")
        // Next lines : data
        shape := numpy.get_shape( data )
        shape_str := fmt.tprintf( "%v %v", shape[ 0 ], shape[ 1 ] )
        data_flat := numpy.flatten( data )
        data_str := "blablabla"     // ... convert data_flat into a string of numbers seprarated by spaces.
        
        filename = fmt.aprintf( "%s%s", "p_np_array_2_", var_name )
        content = fmt.aprintf( "%s%s%s", shape_str, "\n", data_str )
        
    case P_list:
        filename = fmt.aprintf( "%s%s", "p_list_", var_name )
        content = json.marshal( data )   // Use a JSON Library
        
    case P_map:
        filename = fmt.aprintf( "%s%s", "p_map_", var_name )
        content = json.marshal( data )   // Use a JSON Library

*/

    case:
        fmt.eprintf("ERROR: Type of variable is not supported '%s' in py.eval( )\n", var_name )
        return
    }

    // 2. Write the file.
    path := fmt.aprintf( "%s%s", ODIN_PY_OUT_DIR, filename )
    ok    = os.write_entire_file( path, transmute( [ ]u8 )content )
    return ok
}

Var_in_out :: struct {

    name    : string,
    any_ptr : any,
}

Var_tmp :: struct {

    name      : string,
    any_ptr   : any,
    file_path : string, 
}

// The main function for this module py.eval( )
eval :: proc( python_code: string, v_out : [ ]Var_in_out, v_in : [ ]Var_in_out ) {
    
    // 1 - Write, send data to Python.
    
    // 1.1. Clean up the two dirretories ( in and out ) so they are empty.
    // ODIN_PY_OUT_DIR and ODIN_PY_IN_DIR
    

/*
    // 1.2. Parse of the in and out variables inside the Python code 'in:' e 'out:'
    in_vars:  [dynamic]string
    out_vars: [dynamic]string
    
    lines := strings.split( python_code, "\n" )
    for line in lines {
    
        trimmed_line := strings.trim_space( line )
        if strings.has_prefix( trimmed_line, "in:" ) {
        
            vars_str := strings.trim_space( strings.trim_prefix( trimmed_line, "in:" ) )
            vars := strings.split( vars_str, "," )
            for v in vars {
           
                append( & in_vars, strings.trim_space( v ) )
            }
        }
        
        if strings.has_prefix( trimmed_line, "out:" ) {
        
            // Guardamos as vars de saída para saber o que ler mais tarde
            vars_str := strings.trim_space( strings.trim_prefix( trimmed_line, "out:" ) )
            vars := strings.split( vars_str, "," )
            for v in vars {
            
                append( & out_vars, strings.trim_space( v ) )
            }
        }
    }

*/
    
 
    // 1.3. Write v_out variables.
    for var in v_out {
        
        write_variable_to_file( var.name, var.any_ptr )
    }

    
    // 1.4. Write the file with the Pyhton code.
    python_code_filename_out := fmt.aprintf( "%s%s", ODIN_PY_OUT_DIR, "python_program" ) 
    os.write_entire_file( python_code_filename_out, transmute( [ ]u8 )python_code )

    // 1.5. Writting the 'end' file to signal Python to start execution in the out diretory.
    end_filename_out := fmt.aprintf( "%s%s", ODIN_PY_OUT_DIR, "end" ) 
    os.write_entire_file( end_filename_out, nil )
    

    
    
    
    // Read v_in
   
    
    // 2 - Reading ( Receiving results from Python )
    
    // 2.1. Waits for the file 'end' in the "in" directory.
    fmt.println( "Odin: Waiting for the execution of Python..." )
    end_file_path := fmt.aprintf( "%s%s", ODIN_PY_IN_DIR, "end" )
    for !os.exists( end_file_path ) {
        
        // Active Wait ( polling ). Implment somenting based on events (inotify) it would be better.
        time.sleep( 200 * time.Millisecond ) 
    }
    fmt.println( "Odin: 'end' received. Reading results.")

    
    // 2.2 Reads each variable in the v_in list.
    num_max_in_vars := 10
    dir_handler, _ := os.open( ODIN_PY_IN_DIR, os.O_RDONLY )
    result_files   : map[ string ](^Var_tmp)

    counter := 10
    
    for counter > 0 {    
    
        // Waits 1 second, should be less.
        // time.sleep( 1 )
        time.sleep( 500 * time.Microsecond )
        
        files_in_dir, _ := os.read_dir( dir_handler, num_max_in_vars )
        
        // Watis fot the 'end' file. 
        for filename in files_in_dir {
                  
            if filename.name == "end" {
        
                // Read every file!
                counter = -1
                break
            }
            
        }
        
        
        // Maps the variable name to it's complete path to have a easy access to the file.
        
        
        if counter == -1 {

            for file in files_in_dir {
                      
                if file.name != "end" {
            
                    // Collect all files!
                    for & var_data  in v_in {
                        
                        sufix : string = fmt.aprintf( "%s%s", "_", var_data.name )
                        if strings.has_suffix( file.name, sufix ) {
              
                            var_tmp : ^Var_tmp = new( Var_tmp )
                            var_tmp^ = Var_tmp{
                                            name = var_data.name,
                                            any_ptr = var_data.any_ptr,
                                            file_path = fmt.aprintf( "%s%s", ODIN_PY_IN_DIR, file.name ), 
                                        }
                            
                            result_files[ var_data.name ] = var_tmp
                            
                            fmt.printfln( "var name = %s", var_tmp^.name )
                            fmt.printfln( "any_ptr.data = %v, any_ptr.id = %v", (^int)(var_tmp^.any_ptr.data)^, var_tmp^.any_ptr.id )
                            
                            fmt.printfln( "file path = %s\n", var_tmp^.file_path )
                            
                            fmt.printfln( "file.name = %s\n", file.name )
                            
                        }
                    } // end for
                    
                } // end if
                
            } // end for
        }
        

         counter -= 1   
    }

    // 2.3. Read and deserialize the results, updating the local variables.
    for key_var_name, values_var_data in result_files {
        
        var_name  := values_var_data^.name
        any_ptr   := values_var_data^.any_ptr
        file_path := values_var_data^.file_path
        
        content_bytes, ok := os.read_entire_file( file_path )
        if !ok { continue }
        content_str := string( content_bytes )
        
        // Again, a 'switch' to update th correct variable.
        switch any_ptr.id {
        
        
        case P_int:
            ( ^int )( any_ptr.data )^, _ = strconv.parse_int( content_str, 10 )
            
            fmt.printfln("Odin: Updating variable %s = %d", var_name, ( ^int )( any_ptr.data )^ )
            
        case P_float:
            ( ^f64 )( any_ptr.data )^, _ = strconv.parse_f64( content_str )
            fmt.printfln("Odin: Updating variable %s = %g", var_name, ( ^f64 )( any_ptr.data )^ )
            
        case P_string:
             (^string)( any_ptr.data )^ = content_str 
            fmt.printfln("Odin: Updating variable %s = %d", var_name, ( ^string )( any_ptr.data )^ )
            
        }
    
        // 2.4. Delete all the file "in" the in diretory for the next call.    
//      os.remove( file_path )
        fmt.printfln( "Remove file %s", file_path )
    }
    
    // Remove "end" file.

    file_end := fmt.aprintf( "%s%s",ODIN_PY_IN_DIR, "end" )
//     os.remove( file_end )
    fmt.printfln( "Remove file %s", file_end )

    fmt.printfln("\nOdin: py.eval() concluído.\n")
}

Var :: proc ( var_name : string, val_ptr: ^$T ) -> Var_in_out {
  
    res := Var_in_out{ var_name, any{ data = val_ptr, id = typeid_of( T ) } }
    return res
}

test_eval_01 :: proc ( ) {
    
    a       : P_int = 10
    b       : P_float = 5.1415 
    res     : P_float = 0.0
    val_string : P_string = "couves"
             
    eval( `
in: a, b, val_string

def add( a, b ):
    c = a + b
    print( "a + b = ", a, " + ", b, " = ", c )
    return c
    
print( "Olápe odin_py!", val_string )
res = add( a, b )

out: res
`,

        v_out = {
                Var( "a", & a ),
                Var( "b", & b ),
                Var( "val_string", & val_string ),
            },
        v_in = {
                Var( "res", & res ),
            },
        
    )
    
    fmt.printfln( "a + b = %v + %v = res = %v", a, b, res )  

}























/*
v_out = {
            Var{ "a", any{ data = & a, id = typeid_of( int ) } },
            Var{ "b", any{ data = & b, id = typeid_of( int ) } },
            Var{ "val_string", any{ data = & a, id = typeid_of( string ) } },
        },
v_in = {
            Var{ "c", any{ data = & c, id = typeid_of( int ) } },
        },

*/




/*

test_eval_05 :: proc ( ) {
    
    a   : P_np_matrix
    b   : P_np_matrix
    c   : P_np_matrix
    val_1 : P_int = 10
    val_2 : P_f64 = 3.14 
    val_3 : P_str = "couves"
    list_a : P_list
    map_a  : P_Map 
    
    append( & lista, 10 )
    
    py.eval( `
    
        in: a, b, c
        in: val_1, val_2, val_3
        in: list_a, map_a 
    
    
        def bla( var_1 ):
       	    print( "bla", var_1 )	
    
        print( "Olá mundo do Python!" )
        bla( couves )
        c = a + b
        c *= a / b 
    
        out: c
        out: map_a
    ` )
    
    py.get_np_ref( c, 2, 3 ) = py.get_np( c, 4, 5 ) + 2  
      
}

*/
