global _start

BUFFER_SIZE equ 4096
RULES_TABLE_SIZE equ 128
SEQUENCE_SIZE equ 4194304

SYS_WRITE equ 1
SYS_EXIT equ 60
SYS_MMAP equ 9
SYS_MREMAP equ 25
SYS_MUNMAP equ 11
RULES_SIZE equ 1048576

ASCII_ZERO equ 48
ASCII_NINE equ 57
ASCII_NEWLINE equ 10
ASCII_LOW equ 33
ASCII_HIGH equ 126

section .data
    max_rule_size dq 1                      ; Maximal rule size (used in memory allocation)
    buf_A_size  dq 4194304                  ; Start buffer A used for writing, size 4MB
    buf_B_size  dq 4194304                  ; Start buffer B used for writing, size 4MB

section .bss 
    read_buffer resb BUFFER_SIZE            ; Allocates memory for reading buffer
    rules_table resq RULES_TABLE_SIZE       ; Allocates memory for rules table

section .text

_start:
    ; --- BASE POINTERS INITIALIZATION ---
    xor     r14, r14                        ; r14 = Base pointer for Array A
    xor     r12, r12                        ; r12 = Base pointer for Array B (or temporary parsing pointer)
    xor     r15, r15                        ; r15 = Base pointer for rules
    xor     rbp, rbp                        ; rbp = Zeroed out, so ebp can be used as a state counter

    cmp     qword [rsp], 2                  ; Checks whether the param number is equal to 2 (program name, n)
    jne     exit_error                      

    mov     rsi, [rsp + 16]                 ; rsi = pointer to digits of n
    xor     rbx, rbx                        ; rbx stores n as a number (initially set to 0)
    mov     r8d, -1                         ; Used in the loop to verify the range of n 

parse_n_loop:
    movzx   ecx, byte [rsi]                 ; Reads a single char (ecx for optimization)
    test    ecx, ecx                        ; Checks whether it is the end of the sequence
    jz      allocate_memory
    
    cmp     cl, ASCII_ZERO                  ; Verifies whether a character is a number
    jb      exit_error                      ; Returns an error if the character's ASCII code is below zero
    cmp     cl, ASCII_NINE                  ; or above nine
    ja      exit_error

    sub     cl, 48                          ; Converts ASCII to digit
    imul    rbx, rbx, 10                    ; Multiplies the current number by 10 and 
    add     rbx, rcx                        ; adds the digit 

    cmp     rbx, r8                         ; Checks if n = rbx > 4294967295
    ja      exit_error                      ; if so, returns an error

    inc     rsi                             ; Goes to the next character
    jmp     parse_n_loop

allocate_memory:
    ; Allocates memory for initial sequence (Buffer A)
    mov     eax, SYS_MMAP                   ; syscall: SYS_MMAP
    xor     rdi, rdi                        ; addr: NULL (sets preferred address to NULL) 
    mov     rsi, SEQUENCE_SIZE              ; length: 4 MB
    mov     rdx, 3                          ; prot: PROT_READ (1) | PROT_WRITE (2) = 3
    mov     r10, 34                         ; flags: MAP_PRIVATE (2) | MAP_ANONYMOUS (32) = 34
    mov     r8, -1                          ; fd: -1
    xor     r9, r9                          ; offset: 0
    syscall
    
    test    rax, rax                        ; Checks for an error (rax < 0)
    js      exit_error
    mov     r12, rax                        ; r12 = moving pointer to the sequence
    mov     r14, rax                        ; r14 = BASE pointer for Buffer A (array 1)

    ; Allocates memory for the rules
    mov     eax, SYS_MMAP                   ; syscall: sys_mmap
    xor     rdi, rdi                        ; addr: NULL
    mov     rsi, RULES_SIZE                 ; length: 1 MB
    mov     rdx, 3                          ; prot: PROT_READ | PROT_WRITE
    mov     r10, 34                         ; flags: MAP_PRIVATE | MAP_ANONYMOUS
    mov     r8, -1                          ; fd: -1
    xor     r9, r9                          ; offset: 0
    syscall
    
    test    rax, rax                        ; Checks for an error (rax < 0)
    js      exit_error
    mov     r13, rax                        ; r13 = moving pointer for rules memory
    mov     r15, rax                        ; r15 = BASE pointer for rules memory

    xor     ebp, ebp                        ; ebp represents current state:
                                            ; 0 reads start sequence
                                            ; 1 reads symbol
                                            ; 2 read rules 

read_loop:
    xor     rax, rax                        ; syscall: sys_read
    xor     rdi, rdi                        ; fd: stdin (0)
    lea     rsi, [rel read_buffer]          ; Passes buffer address
    mov     rdx, BUFFER_SIZE                ; Max input size
    syscall

    test    rax, rax                        ; Checks for an error / eof
    js      exit_error                      ; If rax < 0 return error
    jz      eof_reached                     ; If rax = 0 eof 
    jmp     parse_loop                      ; If rax > 0 (length of a sequence) continue reading 

eof_reached:
    cmp     ebp, 1                          ; Checks the last state
    js      terminate_state_init            ; Jump if ebp = 0
    jz      finalize_parsing                ; If ebp = 1 do nothing

terminate_state_rule:
    mov     byte [r13], 0                   ; Marks end of a rule with \0

    cmp     r10, [rel max_rule_size]        ; Updates maximum rules size
    jle     .skip_eof_update
    mov     [rel max_rule_size], r10
.skip_eof_update:
    jmp     finalize_parsing

terminate_state_init:
    mov     byte [r12], 0                   ; Marks end of a sequence with \0

finalize_parsing:
    xor     r12, r12                        ; Frees r12, preparing it as a pointer for Array B
    jmp     main_init

parse_loop:
    dec     rax                             ; Decrements the counter
    js      read_loop                       ; If rax < 0 ends the reading
    
    movzx   rdx, byte [rsi]                 ; Moves current character to rdx
    inc     rsi

    cmp     dl, ASCII_NEWLINE               ; If the current symbol is new line use different logic
    jz      parse_newline
    cmp     dl, ASCII_LOW                   ; Checks whether current symbol is correct
    jb      exit_error                      ; If ASCII code < lowest possible, throws an error 
    cmp     dl, ASCII_HIGH
    ja      exit_error                      ; If ASCII code > highest possible, throws an error

    cmp     ebp, 1
    js      parse_state_init                ; If ebp = 0 reads initial sequence
    jz      parse_state_symbol              ; If ebp = 1 reads symbol to change

parse_state_rule:                           ; If ebp = 2 reads the change rule
    mov     [r13], dl                       ; Moves the current char to [r13] 
    inc     r13                             ; Increments the pointer 
    inc     r10                             ; Updates current rule size
    jmp     parse_loop

parse_state_init:
    mov     [r12], dl                       ; Moves the current char to [r12] 
    inc     r12                             ; Increments the pointer
    jmp     parse_loop

parse_state_symbol:
    mov     r9, rdx                         ; Saves current char
    lea     rdi, [rel rules_table]          ; Calculates the address for the current char in rules_table
    lea     rdi, [rdi + r9*8]
    mov     r8, [rdi]                       ; Reads current pointer for rules_table at char index
    test    r8, r8                          ; If r8 != 0, returns error (only one rule can be assigned to a symbol)
    jnz     exit_error
    
    mov     [rdi], r13                      ; Saves current rule pointer (r13) in [rdi]
    inc     ebp                             ; Sets ebp to 2 - prepares for reading the rule
    xor     r10, r10                        ; current rule size = 0
    jmp     parse_loop

parse_newline:
    cmp     ebp, 1                          ; Checks current state
    js      parse_newline_init              ; If ebp = 0 jump  
    jz      parse_loop                      ; If ebp = 1 goes back to the loop (ignores new lines).

    mov     byte [r13], 0                   ; If ebp = 2 marks last symbol "\0",
    inc     r13                             ; increments the rule pointer, 
    dec     ebp                             ; sets ebp = 1
    
    cmp     r10, [rel max_rule_size]        ; Updates maximum rule size
    jle     .skip_update
    mov     [rel max_rule_size], r10
.skip_update:
    jmp     parse_loop                      ; and goes back to the loop.
    
parse_newline_init:
    mov     byte [r12], 0                   ; Marks last symbol "\0"
    inc     r12                             ; Increments the sequence pointer 
    inc     ebp                             ; State swap to parse_state_symbol (ebp = 1)
    jmp     parse_loop

main_init:
    test    rbx, rbx                        ; Special case: n = 0 (skips main_loop)
    jz      print_result

    ; Allocates buffer B (array 2)
    mov     eax, SYS_MMAP
    xor     rdi, rdi
    mov     rsi, [rel buf_B_size] 
    mov     rdx, 3
    mov     r10, 34
    mov     r8, -1
    xor     r9, r9
    syscall
    
    test    rax, rax                        ; Check for an error in allocation
    js      exit_error
    mov     r12, rax                        ; r12 = pointer to Buffer B

main_loop:
    mov     r13, r14                        ; r13 = Safe read pointer (Buffer A)
    mov     rbp, r12                        ; rbp = Safe write pointer (Buffer B)

process_char:
    movzx   rdx, byte [r13]                 ; Gets a single character from the old buffer
    test    rdx, rdx                        ; Checks if a symbol "\0" was detected
    jz      iteration_done                  ; If so, end iteration
    inc     r13                             ; Increments Buffer A pointer 

    lea     rcx, [rel rules_table]          ; Calculates the address to the rules_table for a given symbol
    mov     rcx, [rcx + rdx*8]              
    test    rcx, rcx                        ; Checks if there exists a rule for a given symbol
    jnz     prepare_copy_rule               ; If there is a rule - handles it

    ; --- Capacity check (Regular char) ---
    mov     rax, rbp                        
    sub     rax, r12                        ; rax = current write offset (required by do_expand_memory)
    mov     r9, [rel buf_B_size]
    sub     r9, rax                         ; r9 = remaining space
    
    cmp     r9, [rel max_rule_size]
    jge     back_to_char                    ; HOT PATH: Enough space? Jump down, skip allocation!
    
    ; COLD PATH (Regular char): Not enough space!
    lea     r8, [rel back_to_char]          ; 1. Save "return ticket" (return address) in r8
    jmp     do_expand_memory                ; 2. Indirect jump to relocation
    
back_to_char:                               
    mov     dl, byte [r13 - 1]              ; Restore character (always safe from r13)
    mov     [rbp], dl                       
    inc     rbp                             
    jmp     process_char            

prepare_copy_rule:
    ; --- Capacity check (Rule) ---
    mov     rax, rbp
    sub     rax, r12                        ; rax = write offset
    mov     r9, [rel buf_B_size]            
    sub     r9, rax                         ; r9 = remaining space
    
    cmp     r9, [rel max_rule_size]         
    jge     copy_rule                       ; HOT PATH: Enough space? Jump straight to the loop!
    
    ; COLD PATH (Rule): Not enough space!
    lea     r8, [rel .restore_state]        ; 1. Save "return ticket" (return address) in r8
    jmp     do_expand_memory                ; 2. Indirect jump to relocation
    
.restore_state:
    movzx   rdx, byte [r13 - 1]             ; Restore character after syscall
    lea     rcx, [rel rules_table]
    mov     rcx, [rcx + rdx*8]              ; Restore rule pointer

copy_rule:
    movzx   r8, byte [rcx]                  
    test    r8, r8                          
    jz      process_char                    
    
    mov     [rbp], r8b                      
    inc     rbp                             
    inc     rcx                             
    jmp     copy_rule

iteration_done:
    mov     byte [rbp], 0                   ; Add "\0" at the end of the generated sequence

    ; Ping-Pong mechanism (swap buffers)
    mov     r8, r14                         ; Replaces A buffer with B buffer
    mov     r14, r12
    mov     r12, r8

    mov     rax, [rel buf_A_size]           ; Changes sizes of the buffers
    mov     r9, [rel buf_B_size]
    mov     [rel buf_A_size], r9
    mov     [rel buf_B_size], rax

    dec     rbx                             ; Decrement n counter 
    jz      print_result                    
    jmp     main_loop                       

; =====================================================================
; SINGLE SHARED MREMAP PROCEDURE WITHOUT CALL AND RET INSTRUCTIONS
; =====================================================================
do_expand_memory:
    mov     r9, rax                         ; rax still holds current offset (rbp - r12)
    
    mov     rsi, [rel buf_B_size]           ; Old size
    lea     rdx, [rsi + rsi]                ; New size (rsi * 2)
    mov     [rel buf_B_size], rdx           
    
    mov     eax, SYS_MREMAP                 
    mov     rdi, r12                        ; Old address
    mov     r10, 1                          ; MREMAP_MAYMOVE
    syscall
    
    test    rax, rax
    js      exit_error                      
    
    mov     r12, rax                        ; Update Buffer B base
    lea     rbp, [rax + r9]                 ; NATIVE RESTORE: Restore write pointer!
    
    jmp     r8                              ; INDIRECT JUMP: Return based on "ticket" in r8

print_result:
    mov     rax, r14                        ; Final sequence always lands in r14 (Array A)

find_null:
    cmp     byte [rax], 0                   ; Check if the byte under pointer is zero (\0)
    jz      length_found                    ; If so, break the loop
    inc     rax                             ; If not, advance pointer by 1 byte
    jmp     find_null                       ; Go back to the loop start

length_found:
    ; At this point rax points exactly to '\0'
    sub     rax, r14                        ; rax = sequence length in bytes (subtract base)
    mov     rdx, rax                        ; rdx = target size for sys_write

    mov     byte [r14 + rdx], ASCII_NEWLINE ; Replace '\0' with '\n'
    inc     rdx                             ; Increase print length by 1 (to include '\n')

    mov     eax, SYS_WRITE                  ; syscall: sys_write (1)
    mov     rdi, 1                          ; File descriptor: 1 (stdout)
    mov     rsi, r14                        ; Start address of our string
    syscall

exit_program:
    mov     r14, 0                          ; Exit code = 0 (Success)
    jmp     perform_cleanup
exit_error:
    mov     r14, 1                          ; Exit code = 1 (Error)

perform_cleanup:
    ; --- 1. Free rules memory (Base in r15) ---
    test    r15, r15
    jz      skip_rules                      ; If r15 == 0, skip
    mov     eax, SYS_MUNMAP                 ; syscall: sys_munmap
    mov     rdi, r15                        ; Rules base address
    mov     rsi, RULES_SIZE                 ; 1 MB
    syscall
skip_rules:
    ; --- 2. Free Array A (Base in r14) ---
    test    r14, r14
    jz      skip_buf_a
    mov     rax, 11
    mov     rdi, r14
    mov     rsi, [rel buf_A_size]
    syscall
skip_buf_a:
    ; --- 3. Free Array B (Base in r12) ---
    test    r12, r12
    jz      skip_buf_b
    mov     rax, 11
    mov     rdi, r12
    mov     rsi, [rel buf_B_size]
    syscall
skip_buf_b:
    ; --- PROCESS TERMINATION (sys_exit) ---
    mov     rax, SYS_EXIT                   
    mov     rdi, r14                        ; Return previously saved code (0 or 1)
    syscall