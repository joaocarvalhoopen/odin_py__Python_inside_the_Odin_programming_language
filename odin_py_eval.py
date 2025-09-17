# This is only an experiment to see if it works
# and to test the ergonomics of having Python code inside Odin code.
# License: MIT Oopen Source

# To install
# 
# conda create --name odin_py python=3.13
# 
# conda activate odin_py
# 
# pip install watchdog numpy

import os
import sys
import time
import json
import numpy as np
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

# We use /dev/shm to comunicate in memory, and thats much faster then MVME and doesn't deterioriate the NVME.
BASE_DIR = "/dev/shm/odin_py"
# Odin --->>> Python       Diretory where Odin writes and Python reads.
ODIN_OUT_DIR = os.path.join( BASE_DIR, "out" )
# Python --->>> Odin       Diretory where Python writes and Odin reads.
ODIN_IN_DIR = os.path.join( BASE_DIR, "in" )

class OdinPythonBridge:
    """
    This class manages the life cycle of the communiucation between Odin and Python.
    Mode 1: Listens for variable files, for a program code file and waits for
            the 'end' file that marks the end of the communication.
    Mode 2: Executes the program and writes back the results.
    """

    def __init__( self ):
        self.reset_state( )
        self._ensure_dirs_exist( )
        print( f"Observing the diretory for input (Python) variable : {ODIN_OUT_DIR}" )
        print( f"Writing the results of execution in: {ODIN_IN_DIR}" )

    def _ensure_dirs_exist( self ):
        """Assures that the directories of communication exist."""
        os.makedirs( ODIN_OUT_DIR, exist_ok=True )
        os.makedirs( ODIN_IN_DIR, exist_ok=True )

    def reset_state( self ):
        """Clean the state to prepare for the next execution."""
        print("\n===> Reinicializing the state and waitting for the next new task.")
        self.variable_context  = {'np': np}  # Execution context of numpy is pre-imported
        self.python_code       = ""
        self.in_vars           = set( )
        self.out_vars          = set( )
        self.input_file_paths  = [ ] # Lista de (var_name, absolute_path)
        self.program_file_path = None
        self.end_file_path     = None
        self.ready_to_execute  = False

    def _deserialize_numpy_array( self, path ):
        """Read an numpy array from a text file."""
        with open( path, 'r' ) as f:
            try:
                # The first line contains the 'shape' of the matrix ( ex: "5 10" )
                shape_str = f.readline( ).strip( )
                shape = tuple( map( int, shape_str.split( ) ) )
                # The rest of the file has the data
                data = np.loadtxt( f )
                return data.reshape( shape )
            except Exception as e:
                print( f"Erro ao deserializar array numpy de '{path}': {e}" )
                return None

    def _process_variable_file( self, path ):
        """Process one file for a variable, deserialize it and add it to the context."""
        filename = os.path.basename( path )
        parts = filename.split( '_', 2 )
        if len( parts ) < 3:
            print( f"WARNING: The following filename was ignored ( invalid format ): {filename}" )
            return

        prefix, type_id, var_name = f"p_{parts[1]}", parts[1], parts[2]
        
        print( f"  Reading the variable '{var_name}' of type '{type_id}' from '{filename}'")

        with open( path, 'r' ) as f:
            content = f.read( )

        try:
            if type_id == 'int':
                self.variable_context[ var_name ] = int( content )
            elif type_id == 'float':
                self.variable_context[ var_name ] = float( content )
            elif type_id == 'string':
                self.variable_context[ var_name ] = content
            elif type_id in [ 'np_array_1', 'np_array_2', 'np_array_3' ]:
                # np.loadtxt is suficient for 1D and 2D. For 3D we need a Custom strategy.
                self.variable_context[ var_name ] = self._deserialize_numpy_array( path )
            elif type_id == 'list' or type_id == 'map':
                self.variable_context[ var_name ] = json.loads( content )
            else:
                print( f"WARNING: Unknown Type  '{type_id}' in file {filename}" )
                return
            
            self.input_file_paths.append( path )

        except (ValueError, json.JSONDecodeError) as e:
            print(f"ERROR: It was not possible to process the file {filename}. Invalid content. Error: {e}")

    def _parse_and_store_program(self, path):
        """Read the program code file, and extract the variables 'in'/'out' and the program code."""
        print( f"  Reading the program code file: {os.path.basename(path)}" )
        self.program_file_path = path
        code_lines = [ ]
        with open( path, 'r' ) as f:
            for line in f:
                stripped_line = line.strip( )
                if stripped_line.startswith( 'in:' ):
                    # Ex: "in: a, b, c" -> ["a", "b", "c"]
                    var_names = [ v.strip( ) for v in stripped_line[ 3: ].split( ',' ) ]
                    self.in_vars.update( var_names )
                elif stripped_line.startswith( 'out:' ):
                    var_names = [ v.strip( ) for v in stripped_line[ 4: ].split( ',' ) ]
                    self.out_vars.update( var_names )
                else:
                    code_lines.append( line )
        self.python_code = "".join( code_lines )
        print(f"    Pyhton input variable detected: {self.in_vars}")
        print(f"    Python output variables detected: {self.out_vars}")


    def handle_new_file( self, path ):
        """Function called by watchdog when the file is closed."""
        filename = os.path.basename( path )
        if filename == 'python_program':
            self._parse_and_store_program( path )
        elif filename == 'end':
            print( "File signal 'end' received. Preparing for Pyhton program code execution.")
            self.end_file_path = path
            self.ready_to_execute = True
        else:
            self._process_variable_file( path )

    def _serialize_numpy_array( self, arr ):
        """Serialize a numpy array to text: shape in the first line, followed by data."""
        shape_str = ' '.join( map( str, arr.shape ) )
        # We use repr to maintain the maximum precision of floats.
        data_str = np.array2string( arr.flatten( ), separator=' ', max_line_width=np.inf, formatter={'float_kind':lambda x: repr(x)} )
        # np.array2string adds [ e ], that we need to remove.
        data_str = data_str.replace( '[', '' ).replace( ']', '' ).strip( )
        return f"{shape_str}\n{data_str}"

    def _infer_type_and_get_prefix( self, var ):
        """Infer the prefix of the filename from the type of the variable in Python."""
        if isinstance( var, int ): return 'p_int_'
        if isinstance( var, float ): return 'p_float_'
        if isinstance( var, str ): return 'p_str_'
        if isinstance( var, list ): return 'p_list_'
        if isinstance( var, dict ): return 'p_map_'
        if isinstance( var, np.ndarray ):
            if var.ndim == 1: return 'p_np_array_1_'
            if var.ndim == 2: return 'p_np_array_2_'
            if var.ndim == 3: return 'p_np_array_3_'
            raise TypeError( f"Numpy array with dimensions {var.ndim} is not supported." )
        raise TypeError( f"Type of output variable not supported: {type(var)}" )

    def execute_and_write_results(self):
        """Executes the code and writes the ouput variables."""
        print( "\nBeginning the execution of Python code..." )
        try:
            # Executs the code in our context of variables.
            exec( self.python_code, self.variable_context )
            print( "===> Successefull Execution of Python program code." )
        except Exception as e:
            print( f"ERROR WHILE EXECUTING PYTHON, Odin CODE:\n{e}" )
            # Even in case of error, we try to write to the 'out' variables that may exist.
        
        print("\n===>Writting the output variables.")
        for var_name in self.out_vars:
            if var_name not in self.variable_context:
                print( f"WARNING: The out variable '{var_name}' was no found in the context after an execution." )
                continue

            var_value = self.variable_context[ var_name ]
            try:
                prefix = self._infer_type_and_get_prefix( var_value )
                filename = f"{prefix}{var_name}"
                path = os.path.join( ODIN_IN_DIR, filename )

                print( f"  Writting the variable '{var_name}' in '{filename}'" )

                content_to_write = ""
                if prefix in [ 'p_int_', 'p_float_' ]:
                    content_to_write = repr( var_value ) # We use repr for maximum precision.
                elif prefix == 'p_str_':
                    content_to_write = var_value
                elif prefix in [ 'p_list_', 'p_map_' ]:
                    content_to_write = json.dumps( var_value, indent=4 )
                elif prefix.startswith( 'p_np_array' ):
                    content_to_write = self._serialize_numpy_array( var_value )

                with open( path, 'w' ) as f:
                    f.write( content_to_write )

            except TypeError as e:
                print( f"ERROR: It was not possible to serialize the variable '{var_name}': {e}")
        
        # Write the file 'end' to sgnal Odin that we finish writting the output variables.
        with open( os.path.join( ODIN_IN_DIR, 'end' ), 'w' ) as f:
            pass
        print( "Signal 'end' written to the 'out' diretory." )

    def cleanup_input_files(self):
        """Deletes all the in input files that where processed."""
        print("\n---> Delecting the input files.")
        all_files_to_delete = self.input_file_paths
        if self.program_file_path:
            all_files_to_delete.append( self.program_file_path )
        if self.end_file_path:
            all_files_to_delete.append( self.end_file_path )

        for path in all_files_to_delete:
            try:
                # jnc
                # os.remove( path )
                print( f"  Removed: {os.path.basename(path)}" )
            except OSError as e:
                print( f"WARNINGO: It was not possible to remove the file '{path}': {e}" )


class WatcherEventHandler( FileSystemEventHandler ):
    def __init__( self, bridge ):
        self.bridge = bridge

    def on_closed( self, event ):
        """Called when the file is closed in the observed diretory."""
        if not event.is_directory:
            self.bridge.handle_new_file( event.src_path )

def main():
    """Main function that runs the infinite loop of the service."""
    bridge = OdinPythonBridge( )
    
    while True:
        # MODE 1: Listenning
        bridge.reset_state( )
        
        event_handler = WatcherEventHandler( bridge )
        observer = Observer( )
        observer.schedule( event_handler, ODIN_OUT_DIR, recursive=False )
        observer.start( )

        try:
            while not bridge.ready_to_execute:
                time.sleep( 0.1 )
        except KeyboardInterrupt:
            observer.stop( )
            observer.join( )
            print("\nService terminated by the user.")
            sys.exit( 0 )
        
        observer.stop( )
        observer.join( )

        # MODE 2: Execution of Python code.
        bridge.execute_and_write_results( )
        bridge.cleanup_input_files( )
        # The while cicle restarts with the a call to reset_state( ) and going back to the MODE 1 Listenning.

if __name__ == "__main__":
    main()
