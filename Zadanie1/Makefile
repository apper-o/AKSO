CC = gcc
CFLAGS = -Wall -Wextra -Wno-implicit-fallthrough -std=gnu23 -fPIC -O2
LDFLAGS = -shared -Wl,--wrap=malloc -Wl,--wrap=calloc -Wl,--wrap=realloc -Wl,--wrap=reallocarray -Wl,--wrap=free -Wl,--wrap=strdup -Wl,--wrap=strndup

.PHONY: all clean test

all: librstack.so

# Budowa biblioteki dynamicznej
librstack.so: rstack.o memory_tests.o 
	$(CC) $(LDFLAGS) -o $@ $^

rstack.o: rstack.c rstack.h
	$(CC) $(CFLAGS) -c $<

memory_tests.o: memory_tests.c memory_tests.h
	$(CC) $(CFLAGS) -c $<

# Testowanie
test: rstack_example.o librstack.so
	$(CC) $(CFLAGS) rstack_example.o -L. -Wl,-rpath,. -lrstack -o rstack_example

rstack_example.o: rstack_example.c rstack.h
	$(CC) $(CFLAGS) -c $<

# Wymusza usuwanie plikow
clean:
	rm -f *.o *.so rstack_example