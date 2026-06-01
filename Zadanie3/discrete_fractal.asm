global _start

READ_BUFFER_SIZE equ 4096
RULES_TABLE_SIZE equ 128

BUFFER_INITIAL_SIZE equ 4194304
RULES_INITIAL_SIZE equ 1048576

SYS_MMAP equ 9

PROT_READ     equ 1
PROT_WRITE    equ 2
MAP_PRIVATE   equ 2
MAP_ANONYMOUS equ 32

SYS_MREMAP      equ 25
MREMAP_MAYMOVE  equ 1

SYS_WRITE equ 1
STDOUT    equ 1

SYS_MUNMAP equ 11

SYS_EXIT equ 60

ASCII_ZERO equ 48
ASCII_NINE equ 57
ASCII_NEWLINE equ 10
ASCII_LOW equ 33
ASCII_HIGH equ 126

section .data
    rules_buf_base  dq 0                                ; Rule buffer base (saved after parsing is complete)
    max_rule_size dq 1                                  ; Maximal rule size (used in memory allocation)
    
    rules_buf_end dq 0                                  ; Pointer to the end of the rule buffer
    buf_A_end     dq 0                                  ; Pointer to the end of buffer A

section .bss 
    read_buffer resb READ_BUFFER_SIZE                   ; Allocates memory for reading buffer
    rules_table resq RULES_TABLE_SIZE                   ; Allocates memory for rules table

section .text

_start:
    cmp     qword [rsp], 2                              ; Checks if the amount of args is equal to 2
    jne     exit_error                                  ; If not, returns error

    mov     rsi, [rsp + 16]                             ; rsi = pointer to the most significant digit of n
    xor     rbx, rbx                                    ; Prepares rbx to store n
    mov     r8d, 0xFFFFFFFF                             ; r8 = 2^32 - 1 

; ========================================================================
; Reads and validates the range of number n. 
; rbx = n
; ========================================================================
parse_n_loop:
    movzx   ecx, byte [rsi]                             ; Saves current digit in ecx as a char
    test    ecx, ecx                                    ; If ecx = 0, end reading
    jz      allocate_memory                             ; Jumps to memory allocation if end of string

    sub     ecx, ASCII_ZERO                             ; Verifies whether a character is a number
    cmp     ecx, 9                                      ; Checks if the character is > 9 or < 0
    ja      exit_error                                  ; Jumps to error if not a valid digit

    lea     rbx, [rbx + rbx*4]                          ; rbx = rbx * 5
    lea     rbx, [rcx + rbx*2]                          ; rbx = rbx * 2 + digit (in total: rbx * 10 + digit)
    
    cmp     rbx, r8                                     ; If rbx > 2^32-1, exit with error
    ja      exit_error                                  ; Exits program if the number is too large
    
    inc     rsi                                         ; Increments pointer to the next digit
    jmp     parse_n_loop                                ; Loops back to parse the next digit

; ========================================================================
; Allocates memory for main structures.
; Sets:
; rbp = Buffer A base (buffer A stores initial sequence)
; r12 = Buffer A pointer
; r13 = Buffer rules base
; r14 = Buffer rules pointer
; r15 = Current reading state (used in the next section)
; ========================================================================
allocate_memory:
    mov     eax, SYS_MMAP                               ; syscall: 9 (sys_mmap)
    xor     edi, edi                                    ; addr: NULL
    mov     esi, BUFFER_INITIAL_SIZE                    ; length: 4 MB  
    mov     edx, PROT_READ | PROT_WRITE                 ; prot: PROT_READ (1) | PROT_WRITE (2)
    mov     r10d, MAP_PRIVATE | MAP_ANONYMOUS           ; flags: MAP_PRIVATE (2) | MAP_ANONYMOUS (32)
    or      r8, -1                                      ; fd: -1 (no file descriptor)
    xor     r9d, r9d                                    ; offset: 0
    syscall                                             ; Executes the mmap system call

    test    rax, rax                                    ; Checks for an error (rax < 0)
    js      exit_error                                  ; Jumps to error if mmap failed

    mov     rbp, rax                                    ; rbp = Buffer A base address
    mov     r12, rax                                    ; r12 = Buffer A current pointer
    lea     r11, [rax + BUFFER_INITIAL_SIZE - 1]        ; -1 for '\0' symbol
    mov     [rel buf_A_end], r11                        ; Saves the end address of Buffer A

    mov     eax, SYS_MMAP                               ; syscall: 9 (sys_mmap)
    mov     esi, RULES_INITIAL_SIZE                     ; length: 4 MB  
    syscall                                             ; Executes the mmap system call

    test    rax, rax                                    ; Checks for an error (rax < 0)
    js      exit_error                                  ; Jumps to error if mmap failed

    mov     r13, rax                                    ; r13 = Buffer rules base address
    mov     r14, rax                                    ; r14 = Buffer rules current pointer
    lea     r11, [rax + RULES_INITIAL_SIZE - 1]         ; -1 for '\0' symbol
    mov     [rel rules_buf_end], r11                    ; Saves the end address of the rules buffer

    xor     r15d, r15d                                  ; r15 = reading state (0)
; ========================================================================
; Reads input to a buffer using syscall (initial sequence and rules)
; Modifies:
; r9 = sequence length for the next iteration
; ========================================================================
read_loop:
    xor     eax, eax                                    ; syscall: sys_read (0)
    xor     edi, edi                                    ; fd: stdin (0)
    lea     rsi, [rel read_buffer]                      ; Passes buffer address
    mov     edx, READ_BUFFER_SIZE                       ; Max input size
    syscall                                             ; Executes the read system call

    test    rax, rax                                    ; Checks the number of bytes read
    js      exit_error                                  ; If rax < 0, return error
    jz      eof_reached                                 ; If rax = 0, EOF (end of file) reached

    mov     r9, rax                                     ; Saves the length of the read sequence in r9
; ========================================================================
; Saves input reading a single character in every iteration
; Assumptions:
; rax = sequence length
; rsi = read_buffer pointer
; r8 = current rule size
; ========================================================================
parse_loop:
    dec     r9d                                         ; Decrements the remaining byte count
    js      read_loop                                   ; If r9d < 0, read another chunk from stdin

    movzx   edx, byte [rsi]                             ; rdx = current symbol from the buffer
    inc     rsi                                         ; Increments pointer to the next symbol

    cmp     dl, ASCII_NEWLINE                           ; Checks if the symbol is a newline character
    jz      parse_newline                               ; If yes, process the newline

    lea     ecx, [rdx - ASCII_LOW]                      ; Checks if current symbol is a correct ASCII character
    cmp     ecx, ASCII_HIGH - ASCII_LOW                 ; Verifies against the valid ASCII range
    ja      exit_error                                  ; If out of bounds, exit with error

    cmp     r15d, 1                                     ; Checks the current parsing state
    js      .parse_init                                 ; If state < 1 (0), parse initial sequence
    jz      .parse_symbol                               ; If state == 1, parse the symbol for a rule

.parse_rule:
    cmp     r14, [rel rules_buf_end]                    ; Checks if current rules_buffer has enough memory
    jb      .store_rule                                 ; If it does, skip expansion

    push    rsi                                         ; Saves current read buffer pointer on the stack

    mov     rsi, [rel rules_buf_end]                    ; Loads the end of the rules buffer
    sub     rsi, r13                                    ; rsi = old_size
    inc     rsi                                         ; Adds 1 for the '\0' symbol
    mov     rdi, r13                                    ; base_addr = current rule buffer base
    call    expand_memory                               ; rax = new base address, rdx = new size

    pop     rsi                                         ; Restores read buffer pointer from the stack

    sub     r14, r13                                    ; r14 = offset (current pointer - old base)
    add     r14, rax                                    ; r14 = new base address + offset
    mov     r13, rax                                    ; r13 = new base address

    add     rax, rdx                                    ; rax = new base + new size
    dec     rax                                         ; -1 to reserve space for '\0'
    mov     [rel rules_buf_end], rax                    ; Saves new end of the rules buffer

.store_rule:
    mov     byte [r14], dl                              ; Saves the current symbol in the rule buffer
    inc     r14                                         ; Increments rule buffer pointer
    inc     r8                                          ; Increments current rule size
    jmp     parse_loop                                  ; Jumps back to process the next character

.parse_init:
    cmp     r12, [rel buf_A_end]                        ; Checks if A buffer has enough memory
    jb      .store_init                                 ; If it does, skip expansion

    push    rsi                                         ; Saves current read buffer pointer on the stack

    mov     rsi, [rel buf_A_end]                        ; Loads the end of buffer A
    sub     rsi, rbp                                    ; rsi = old_size
    inc     rsi                                         ; Adds 1 for the '\0' symbol
    mov     rdi, rbp                                    ; base_addr = current buffer A base
    call    expand_memory                               ; rax = new base address, rdx = new size

    pop     rsi                                         ; Restores read buffer pointer from the stack

    sub     r12, rbp                                    ; r12 = offset (current pointer - old base)
    add     r12, rax                                    ; r12 = new base address + offset
    mov     rbp, rax                                    ; rbp = new base address
    
    add     rax, rdx                                    ; rax = new base + new size
    dec     rax                                         ; -1 to reserve space for '\0'
    mov     [rel buf_A_end], rax                        ; Saves new end of buffer A

.store_init:
    mov     byte [r12], dl                              ; Saves the initial sequence symbol in buffer A
    inc     r12                                         ; Increments buffer A pointer
    jmp     parse_loop                                  ; Jumps back to process the next character

.parse_symbol:
    lea     rdi, [rel rules_table]                      ; Loads the base address of the rules table
    mov     r10, [rdi + rdx*8]                          ; r10 = current rule pointer for this symbol
    
    test    r10, r10                                    ; Check for rule duplicates (r10 > 0)
    jnz     exit_error                                  ; If duplicate exists, exit with error

    mov     rax, r14                                    ; rax = current rule buffer pointer
    sub     rax, r13                                    ; Calculates offset relative to the base (r14 - r13)
    inc     rax                                         ; Adds 1 to avoid storing 0 (reserved for null)
    mov     [rdi + rdx*8], rax                          ; Stores the offset value in the rules table

    inc     r15                                         ; Swap state to reading rule (state = 2)
    xor     r8d, r8d                                    ; Current rule size = 0

    jmp     parse_loop                                  ; Jumps back to process the next character

; ========================================================================
; Parse section when newline is detected. 
; Chooses a path based on the current state (r15).
; ========================================================================
parse_newline:
    cmp     r15d, 1                                     ; Checks current state
    jz      parse_loop                                  ; If r15 = 1, go back to the main loop (no rule has been added)
    js      .parse_newline_init                         ; If r15 = 0, end initial sequence
    
.parse_newline_symbol:
    mov     byte [r14], 0                               ; Saves '\0' at the end of the rule
    inc     r14                                         ; Increments rule buffer pointer
    dec     r15                                         ; Decrements current state (prepares for reading a symbol)

    cmp     r8, [rel max_rule_size]                     ; Updates maximum rule size
    jle     .skip_update                                ; If current rule size <= max, skip update
    mov     [rel max_rule_size], r8                     ; Otherwise, save the new max rule size

.skip_update:
    jmp     parse_loop                                  ; Jumps back to process the next character

.parse_newline_init:
    mov     byte [r12], 0                               ; Saves '\0' to terminate the initial sequence
    inc     r12                                         ; Increments buffer A pointer
    inc     r15                                         ; Increments current state (prepares for reading a symbol)
    jmp     parse_loop                                  ; Jumps back to process the next character

; ========================================================================
; Final section of parsing. 
; ========================================================================
eof_reached:
    cmp     r15d, 1                                     ; Checks current state
    jz      main_init                                   ; If r15 = 1, skip to main initialization
    js      .eof_init                                   ; If r15 = 0, finish initial sequence on EOF

.eof_rule:
    mov     byte [r14], 0                               ; Marks the end of a rule with \0
    cmp     r8, [rel max_rule_size]                     ; Updates max_rule_size
    jle     .skip_eof_update                            ; If current rule size <= max, skip update
    mov     [rel max_rule_size], r8                     ; Otherwise, save the new max rule size

.skip_eof_update:
    jmp     main_init                                   ; Proceeds to main simulation initialization

.eof_init:
    mov     byte [r12], 0                               ; Marks the end of the sequence with '\0'
    xor     ebx, ebx                                    ; n = 0 (no rules provided)
    jmp     main_init                                   ; No rules means we can already print the word

; ========================================================================
; Allocates data for main simulation. Creates buffer B.
; ========================================================================
main_init:
    mov     [rel rules_buf_base], r13                   ; Saves pointer to rule buffer base
    mov     r9, r12                                     ; r9 stores current end of buffer A

    mov     r12, rbp                                    ; r12 = restored buffer A base
    mov     r14, [rel buf_A_end]                        ; r14 = buffer A max end address

    test    rbx, rbx                                    ; Special case n = 0
    jz      print_result                                ; If n = 0, print the initial word directly

    mov     eax, SYS_MMAP                               ; syscall: 9 (sys_mmap)
    xor     edi, edi                                    ; addr: NULL
    mov     esi, BUFFER_INITIAL_SIZE                    ; length: 4 MB
    mov     edx, PROT_READ | PROT_WRITE                 ; prot: PROT_READ | PROT_WRITE
    mov     r10d, MAP_PRIVATE | MAP_ANONYMOUS           ; flags: MAP_PRIVATE | MAP_ANONYMOUS
    or      r8, -1                                      ; fd: -1 (no file descriptor)
    xor     r9d, r9d                                    ; offset: 0
    syscall                                             ; Executes mmap to allocate Buffer B

    test    rax, rax                                    ; Checks for allocation errors
    js      exit_error                                  ; If rax < 0, jump to error handler
    mov     r13, rax                                    ; r13 = pointer to Buffer B base
    lea     r15, [rax + BUFFER_INITIAL_SIZE - 1]        ; r15 = pointer to Buffer B end
    mov     r8, [rel max_rule_size]                     ; r8 = maximum rule size

; ========================================================================
; Does main simulation.
; Assigned registers:
; rbx = n
; r8 = max_rule_size
; r12 = buffer A base
; r14 = buffer A end
; r13 = buffer B base
; r15 = buffer B end 
; Sets:
; rcx = pointer to the rule for a specific character
; rdi = buffer B pointer
; rsi = buffer A pointer
; ========================================================================
    align    16                                         ; Aligns the loop to a 16-byte boundary for performance
main_loop:
    mov     rsi, r12                                    ; rsi = source buffer (Buffer A) pointer
    mov     rdi, r13                                    ; rdi = destination buffer (Buffer B) pointer
    
.process_symbol:
    movzx   edx, byte [rsi]                             ; Gets a single character from the source buffer
    test    edx, edx                                    ; Checks if the current character is '\0'
    jz      .iteration_end                              ; If end of string, finish this iteration
    inc     rsi                                         ; Increases pointer for the next character

    lea     rax, [rdi + r8]                             ; rax = buffer B current pointer + max_rule_size
    cmp     rax, r15                                    ; Checks if rax is greater than buffer B end
    jae     .expand_write_buffer                        ; If so, expands the destination buffer

.write_ready:
    lea     rax, [rel rules_table]                      ; rax = base address of rules table
    mov     rcx, [rax + rdx*8]                          ; Loads the rule offset for the current symbol
    test    rcx, rcx                                    ; Checks if a rule exists for this symbol
    jz      .copy_symbol                                ; If there is no rule, copies the symbol directly
    
    dec     rcx                                         ; Subtracts 1 to retrieve the actual offset
    add     rcx, [rel rules_buf_base]                   ; Adds the base address of the rule buffer

.copy_rule:
    movzx   eax, byte [rcx]                             ; Copies current symbol from the rule
    test    eax, eax                                    ; If current symbol is '\0', end rule copying
    jz      .process_symbol                             ; Go back to process the next symbol in the sequence
    mov     byte [rdi], al                              ; Saves current char from rule in the destination buffer
    inc     rcx                                         ; Increments rule pointer
    inc     rdi                                         ; Increments destination buffer pointer
    jmp     .copy_rule                                  ; Loops to copy the rest of the rule

.copy_symbol:
    mov     byte [rdi], dl                              ; Copies the raw symbol directly to the write buffer
    inc     rdi                                         ; Increments destination buffer pointer
    jmp     .process_symbol                             ; Jumps back to process the next symbol

.expand_write_buffer:
    mov     rbp, rsi                                    ; Saves current source pointer (Buffer A)
    mov     r9, rdi                                     ; r9 = current destination pointer
    sub     r9, r13                                     ; r9 = offset within the destination buffer

    mov     rsi, r15                                    ; rsi = destination buffer end pointer
    sub     rsi, r13                                    ; Calculates current size of destination buffer
    inc     rsi                                         ; rsi = old_size (+1 for '\0')
    mov     rdi, r13                                    ; rdi = base_addr of destination buffer
    call    expand_memory                               ; rax = new base address, rdx = new size

    mov     r13, rax                                    ; Updates base address of destination buffer
    lea     r15, [rax + rdx - 1]                        ; Updates end address of destination buffer

    mov     rdi, r9                                     ; rdi = saved offset
    add     rdi, rax                                    ; rdi = new destination pointer
    mov     rsi, rbp                                    ; Restores source pointer (Buffer A)
    movzx   edx, byte [rsi - 1]                         ; Restores the current character to rdx
    jmp     .write_ready                                ; Resumes processing after buffer expansion

.iteration_end:
    mov     byte [rdi], 0                               ; Writes '\0' at the end of the newly generated sequence

    mov     r9, rdi                                     ; r9 stores current end of the destination buffer

    xchg    r12, r13                                    ; Swaps Buffer A and Buffer B base addresses
    xchg    r14, r15                                    ; Swaps Buffer A and Buffer B end addresses

    dec     rbx                                         ; Decrements iteration counter n
    jnz     main_loop                                   ; If n > 0, loops to perform the next iteration

print_result:
    mov     rdx, r9                                     ; rdx = address of the end of the string
    sub     rdx, r12                                    ; rdx = string size
    mov     eax, SYS_WRITE                              ; syscall: 1 (sys_write)
    mov     edi, STDOUT                                 ; file descriptor: 1 (stdout)
    mov     rsi, r12                                    ; addr: start of the sequence to print
    syscall                                             ; Executes the write system call

free_memory:
    ; --- Clears A buffer ---;
    mov     rdi, r12                                    ; base_addr of the first buffer
    mov     rsi, r14                                    ; rsi = pointer to the end of the buffer
    sub     rsi, r12                                    ; Calculates buffer size minus 1
    inc     rsi                                         ; rsi = exact length (r14 - r12 + 1)
    mov     eax, SYS_MUNMAP                             ; syscall: 11 (sys_munmap)
    syscall                                             ; Executes the munmap system call

    ; --- Clears rule buffer ---
    mov     rdi, [rel rules_buf_base]                   ; rdi = rule buffer base address
    mov     rsi, [rel rules_buf_end]                    ; rsi = rule buffer end address
    sub     rsi, rdi                                    ; Calculates buffer size minus 1
    inc     rsi                                         ; rsi = exact length
    mov     eax, SYS_MUNMAP                             ; syscall: 11 (sys_munmap)
    syscall                                             ; Executes the munmap system call

    ; -- Clears B buffer if exists --- 
    cmp     r13, [rel rules_buf_base]                   ; If r13 still points to rules, Buffer B does not exist
    je      .exit_program                               ; Jumps to program exit if Buffer B was never created
    
    mov     rdi, r13                                    ; rdi = Buffer B base address
    mov     rsi, r15                                    ; rsi = Buffer B end address
    sub     rsi, r13                                    ; Calculates Buffer B size minus 1
    inc     rsi                                         ; rsi = exact length
    mov     eax, SYS_MUNMAP                             ; syscall: 11 (sys_munmap)
    syscall                                             ; Executes the munmap system call

.exit_program:
    mov     eax, SYS_EXIT                               ; syscall: 60 (sys_exit)
    xor     edi, edi                                    ; exit code: 0 (success)
    syscall                                             ; Executes the sys_exit system call

; ========================================================================
; Doubles buffer size using mremap.
; Parameters:
;   rdi = base address of a buffer
;   rsi = current size of a buffer
; Return:
;   rax = new buffer address
;   rdx = new buffer size
; ========================================================================
expand_memory:
    lea     rdx, [rsi + rsi]                            ; rdx = new_size (old_size * 2)
    mov     eax, SYS_MREMAP                             ; syscall: 25 (sys_mremap)
    mov     r10d, MREMAP_MAYMOVE                        ; flags: 1 (MREMAP_MAYMOVE)
    syscall                                             ; Executes the mremap system call

    test    rax, rax                                    ; Checks for mremap errors
    js      exit_error                                  ; If rax < 0, jump to error handler

    ret                                                 ; Returns from the subroutine

exit_error:
    mov     eax, SYS_EXIT                               ; syscall: 60 (sys_exit)
    mov     edi, 1                                      ; exit code: 1 (error)
    syscall                                             ; Executes the sys_exit system call