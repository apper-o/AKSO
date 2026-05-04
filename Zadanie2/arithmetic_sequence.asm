section .text

global arithmetic_sequence

; --------------------------------------------------------------------------------------------------------
; int128_t arithmetic_sequence(uint64_t const *A0, uint64_t const *A1, uint64_t *Ak, size_t n, int64_t k);
; --------------------------------------------------------------------------------------------------------
; Initial register usage:
; rdi - Pointer to A_0 array
; rsi - Pointer to A_1 array
; rdx - Pointer to A_k array
; rcx - Array size n
; r8  - Index k
; --------------------------------------------------------------------------------------------------------

arithmetic_sequence:
        mov     r9, rdx                         ; Save destination pointer (A_k)
        mov     r10, rcx                        ; Set up difference loop counter
        xor     r11, r11                        ; Initialize offset to 0 & clear flags

.difference_loop:                               ; Step 1: Compute the difference diff = A_1 - A_0
        mov     rax, [rsi + r11 * 8]            ; rax = A_1[i]
        sbb     rax, [rdi + r11 * 8]            ; rax = A_1[i] - A_0[i] - CF
        mov     [r9 + r11 * 8], rax             ; Store the difference in A_k[i]
        inc     r11
        dec     r10
        jnz     .difference_loop                ; Repeat n times

                                                ; Step 2: Compute sgn(diff)
        sbb     r11, r11                        ; Capture the final borrow (r11 = -CF)
        
        mov     rax, [rdi + rcx * 8 - 8]        ; rax = A_0[n-1]
        sar     rax, 63                         ; rax = sgn(A_0) (0 / -1)
        sub     r11, rax                        ; r11 = -CF - sgn(A_0)
        
        mov     rax, [rsi + rcx * 8 - 8]        ; rax = A_1[n-1]
        sar     rax, 63                         ; rax = sgn(A_1)
        add     r11, rax                        ; r11 = sgn(A_1) - sgn(A_0) - CF

                                                ; Step 3: Prepare for multiplication A_k = A_0 + k * diff
        xor     r10, r10                        ; r10 = multiplication carry
        xor     rsi, rsi                        ; rsi = addition/subtraction carry

        test    r8, r8                          ; Check the sign of k
        jns     .k_positive_loop                
        
        neg     r8                              ; Make k absolute for multiplication
        
.k_negative_loop:
        mov     rax, [r9]                       
        mul     r8                              ; rdx:rax = diff[i] * |k|
        add     rax, r10                        ; Add multiplication carry
        adc     rdx, 0                  
        mov     r10, rdx                        ; Save multiplication carry for the next iteration
        
        mov     rdx, [rdi]                      ; rdx = A_0[i]
        neg     rsi                             ; Restore CF
        sbb     rdx, rax                        ; rdx = A_0[i] - |k| * diff
        sbb     rsi, rsi                        ; Save CF
        mov     [r9], rdx                       ; Store rdx to A_k[i]
        
        add     r9, 8                           ; Prepares for the next iteration
        add     rdi, 8                  
        dec     rcx                     
        jnz     .k_negative_loop        
        
        neg     r8                              ; Restore original negative value of k
        
        mov     rax, r10                        ; Calculate final 128-bit loop carry
        sub     rax, rsi                        ; rax = mul carry + sub carry
        xor     rdx, rdx                
        
        neg     rax                             ; Negate carry because operation was subtraction
        adc     rdx, 0                  
        neg     rdx                     
        jmp     .add_high_bits                  ; Jump to common result section

.k_positive_loop:
        mov     rax, [r9]               
        mul     r8                              ; rdx:rax = diff[i] * k
        add     rax, r10                        ; Add multiplication carry
        adc     rdx, 0                  
        mov     r10, rdx                        ; Save multiplication carry for the next iteration
        
        mov     rdx, [rdi]                      ; rdx = A_0[i]
        neg     rsi                             ; Restore CF
        adc     rdx, rax                        ; rdx = A_0[i] + k * diff
        sbb     rsi, rsi                        ; Save CF
        mov     [r9], rdx                       ; Store rdx to A_k[i]
        
        add     r9, 8                           ; Prepares for the next iteration
        add     rdi, 8                          
        dec     rcx                     
        jnz     .k_positive_loop        
        
        mov     rax, r10                        ; Calculate final 128-bit loop carry
        sub     rax, rsi                        ; rax = mul carry + sub carry
        xor     rdx, rdx                

.add_high_bits:
        mov     rcx, [rdi - 8]                  ; rcx = A_0[n-1]
        sar     rcx, 63                         ; rcx = sign(A_0)
        add     rax, rcx                        ; Add sgn(A_0) to the lower 64 bits
        adc     rdx, rcx                        ; Add sgn(A_0) to the upper 64 bits

        test    r11, r11                        ; Check if diff is 0 or -1
        jz      .return                         ; If 0, no upper multiplication bits to add
        
        mov     rcx, r8                         ; Copy original k to extract its sign
        sar     rcx, 63                         
        sub     rax, r8                         ; Subtract k from the lower 64 bits of result
        sbb     rdx, rcx                        ; Subtract sign extended k from upper 64 bits

.return:
        ret