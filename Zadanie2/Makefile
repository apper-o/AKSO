# Kompilatory i flagi
AS = nasm
ASFLAGS = -f elf64 -w+all -w+error

CC = gcc
CFLAGS = -Wall -Wextra -std=c23 -O2
LDFLAGS = -z noexecstack

# Nazwa pliku wynikowego
TARGET = arithmetic_sequence_example_c

# Wymagane pliki obiektowe
OBJS = arithmetic_sequence.o arithmetic_sequence_example_c.o

# Domyślna reguła (odpala się po wpisaniu samego 'make')
all: $(TARGET)

# Linkowanie plików obiektowych w plik wykonywalny
$(TARGET): $(OBJS)
	$(CC) $(LDFLAGS) -o $(TARGET) $(OBJS)

# Kompilacja kodu w C
arithmetic_sequence_example_c.o: arithmetic_sequence_example.c
	$(CC) -c $(CFLAGS) -o arithmetic_sequence_example_c.o arithmetic_sequence_example.c

# Kompilacja Asemblera
arithmetic_sequence.o: arithmetic_sequence.asm
	$(AS) $(ASFLAGS) -o arithmetic_sequence.o arithmetic_sequence.asm

# Czyszczenie wygenerowanych plików
clean:
	rm -f $(OBJS) $(TARGET)

.PHONY: all clean
