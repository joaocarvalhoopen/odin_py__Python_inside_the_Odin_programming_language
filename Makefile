all:
	odin build . -out:odin_py.exe -o:speed

clean:
	rm -f odin_py.exe

run:
	./odin_py.exe
