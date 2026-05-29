# Kompilator i linker
ASM = nasm
LD = ld

# Flagi
ASMFLAGS = -f elf64 -w+all -w+error -w-unknown-warning -w-reloc-rel
LDFLAGS = -pie -I /lib64/ld-linux-x86-64.so.2 --fatal-warnings

# Pliki
TARGET = discrete_fractal
OBJ = discrete_fractal.o
SRC = discrete_fractal.asm

# Pseudo-cele
.PHONY: all clean

# Domyślny cel uruchamiany po wpisaniu 'make'
all: $(TARGET)

# Konsolidacja (linkowanie)
$(TARGET): $(OBJ)
	$(LD) $(LDFLAGS) -o $(TARGET) $(OBJ)

# Asemblacja (kompilacja)
$(OBJ): $(SRC)
	$(ASM) $(ASMFLAGS) -o $(OBJ) $(SRC)

# Czyszczenie plików wynikowych po wpisaniu 'make clean'
clean:
	rm -f $(OBJ) $(TARGET)
