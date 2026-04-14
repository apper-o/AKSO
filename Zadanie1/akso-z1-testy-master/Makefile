CC = gcc
# Jesli u siebie na laptopie uzywasz gcc-14 i gnu2x, to wpisz tutaj:
# CC = gcc-14
# CFLAGS = -Wall -Wextra -Wno-implicit-fallthrough -std=gnu2x -fPIC -O2
CFLAGS = -Wall -Wextra -Wno-implicit-fallthrough -std=gnu23 -fPIC -O2
LDFLAGS = -shared -Wl,--wrap=malloc -Wl,--wrap=calloc -Wl,--wrap=realloc -Wl,--wrap=reallocarray -Wl,--wrap=free -Wl,--wrap=strdup -Wl,--wrap=strndup

.PHONY: all clean test test_toster

# Domyślny cel
all: librstack.so

# Cel tworzący bibliotekę
librstack.so: rstack.o memory_tests.o
	$(CC) $(LDFLAGS) -o $@ $^

rstack.o: rstack.c rstack.h
	$(CC) $(CFLAGS) -c $<

memory_tests.o: memory_tests.c memory_tests.h
	$(CC) $(CFLAGS) -c $<

# --- TESTY OFICJALNE ---
rstack_example.o: rstack_example.c rstack.h
	$(CC) $(CFLAGS) -c $<

rstack_example: rstack_example.o librstack.so
	$(CC) -Wall -Wextra -O2 $< -L. -Wl,-rpath,. -lrstack -o $@

test: rstack_example
	./rstack_example zero

# --- TESTY STUDENCKIE (TOSTER) ---
tester: test1.c test2.c test3.c test4.c test5.c test6.c test7.c test8.c test9.c test10.c toster.c librstack.so
	$(CC) $(CFLAGS) test*.c toster.c -L. -Wl,-rpath,. -lrstack -o $@

test_toster: tester librstack.so
	valgrind --error-exitcode=1 --leak-check=full ./tester all
	bash diff_all.sh

# Cel sprzątający
clean:
	rm -f *.o *.so rstack_example tester
