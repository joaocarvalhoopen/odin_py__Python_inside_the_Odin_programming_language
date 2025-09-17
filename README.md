# odin_py - Python inside the Odin programming language
A simple experiment to test the ergonomics of the thing.

## Description
This allows to make Python code inside the Odin code and run it, and pass the variables from Odin to Python, currently for int, float and str, latter for numpy arrays, list and map. <br>
This is only an experiment. <br>
This uses the ```/dev/shm/odin_py``` Linux RAM Disk, so it's fast and doesn't where the disk.

## How does the code look like

``` Odin

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

```

## How to run


``` bash
# Run the Python server.

python odin_py_eval.py 
```

``` bash
# Run the Odin program.

make
make run
```

``` bash
# The Linux RAM disk

cd /dev/shm/
tree odin_py

# Currently the cleaning of the files is commented for the tests.

cd /dev/shm/odin_py/in/
rm -f *

cd /dev/shm/odin_py/out/
rm -f *

```

## The variables passed

``` bash

(base) joaocarvalho@soundofsilence:/dev/shm/odin_py> tree
.
├── in
└── out

3 directories, 0 files
(base) joaocarvalho@soundofsilence:/dev/shm/odin_py> tree
.
├── in
│   ├── end
│   └── p_float_res
└── out
    ├── end
    ├── p_float_b
    ├── p_int_a
    ├── p_string_val_string
    └── python_program

```


## License
MIT Open Source License.

## Have fun
Best regards, <br>
João Carvalho
