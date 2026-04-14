CC = gcc
CFLAGS = -Wall -Wextra -Wno-implicit-fallthrough -std=gnu23 -fPIC -O2
LDFLAGS = -shared -Wl,--wrap=malloc -Wl,--wrap=calloc -Wl,--wrap=realloc -Wl,--wrap=reallocarray -Wl,--wrap=free -Wl,--wrap=strdup -Wl,--wrap=strndup

.PHONY: all clean test

# Domyślny cel, wywoływany po wpisaniu samego 'make'
all: librstack.so

# Cel tworzący bibliotekę, dołącza rstack.o oraz oparty na wymaganiach memory_tests.o
librstack.so: rstack.o memory_tests.o
	$(CC) $(LDFLAGS) -o $@ $^

# Kompilacja plików źródłowych uwzględniająca zależności od nagłówków
rstack.o: rstack.c rstack.h
	$(CC) $(CFLAGS) -c $<

memory_tests.o: memory_tests.c memory_tests.h
	$(CC) $(CFLAGS) -c $<

# --- CELE OPCJONALNE (zgodne z sugestią z polecenia) ---
# Budowanie pliku z testami (rstack_example)
rstack_example.o: rstack_example.c rstack.h
	$(CC) $(CFLAGS) -c $<

rstack_example: rstack_example.o librstack.so
	$(CC) -Wall -Wextra -O2 $< -L. -Wl,-rpath,. -lrstack -o $@

# Szybkie wywołanie kompilacji testów
test: rstack_example

# Cel sprzątający
clean:
	rm -f *.o *.so rstack_example