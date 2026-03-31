CC = gcc

# Flagi do kompilacji plików
CFLAGS = -Wall -Wextra -Wno-implicit-fallthrough -std=gnu23 -fPIC -O2

# Flagi dla linkera
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
	$(CC) $(CFLAGS) rstack_example.o -L. -lrstack -o rstack_example

rstack_example.o: rstack_example.c rstack.h
	$(CC) $(CFLAGS) -c $<

# Wymusza usuwanie plikow
clean:
	-rm -f *.o librstack.so rstack_example run_tests