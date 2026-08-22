# =============================================================================
# Project:     asm-entropy-daemon
# File:        chaos_watch.s
# Description: Live terminal HUD monitor for the Chaos Engine shared memory.
# =============================================================================

.section .rodata
    shm_path:       .asciz "/dev/shm/chaos_shm"
    
    # ANSI Escape Sequences
    clear_screen:   .asciz "\033[H\033[J"
    color_reset:    .asciz "\033[0m"
    color_header:   .asciz "\033[1;36m" # Cyan bold
    color_free:     .asciz "\033[0;32m" # Green (-1: Free)
    color_pend:     .asciz "\033[0;33m" # Yellow (1: Pending)
    color_rdy:      .asciz "\033[0;31m" # Red (0: Ready)

    str_title:      .asciz "=== CHAOS ENGINE LIVE MONITOR (8x8 GRID) ===\n"
    str_hb:         .asciz "Heartbeat Counter: "
    str_nl:         .asciz "\n"
    str_sep:        .asciz "---------------------------------------------------\n"
    
    txt_free:       .asciz "FREE "
    txt_pend:       .asciz "PEND "
    txt_rdy:        .asciz "RDY  "

.section .bss
    decimal_buf:    .space 32

.section .text
.globl _start

_start:
    # 1. Open and Map Shared Memory
    movq $2, %rax
    leaq shm_path(%rip), %rdi
    movq $2, %rsi
    syscall
    testq %rax, %rax
    js .error_exit
    movq %rax, %r8

    movq $9, %rax
    xorq %rdi, %rdi
    movq $4096, %rsi
    movq $3, %rdx
    movq $1, %r10
    movq %r8, %r8
    xorq %r9, %r9
    syscall
    testq %rax, %rax
    js .error_exit
    movq %rax, %r12                 # %r12 = SHM Base Pointer

.render_loop:
    # Clear screen
    movq $1, %rax
    movq $1, %rdi
    leaq clear_screen(%rip), %rsi
    movq $7, %rdx
    syscall

    # Print Header Color
    movq $1, %rax
    movq $1, %rdi
    leaq color_header(%rip), %rsi
    movq $7, %rdx
    syscall

    # Print Title
    movq $1, %rax
    movq $1, %rdi
    leaq str_title(%rip), %rsi
    movq $45, %rdx
    syscall

    # Print Heartbeat Label
    movq $1, %rax
    movq $1, %rdi
    leaq str_hb(%rip), %rsi
    movq $19, %rdx
    syscall

    # Convert and Print Heartbeat Value
    movq 4088(%r12), %rdi           # Read heartbeat
    leaq decimal_buf(%rip), %rsi
    call int_to_ascii               # Returns string length in %rdx

    movq $1, %rax
    movq $1, %rdi
    leaq decimal_buf(%rip), %rsi
    # length is already in %rdx from int_to_ascii
    syscall

    # Print newline & separator
    movq $1, %rax
    movq $1, %rdi
    leaq str_nl(%rip), %rsi
    movq $1, %rdx
    syscall

    movq $1, %rax
    movq $1, %rdi
    leaq str_sep(%rip), %rsi
    movq $52, %rdx
    syscall

    # Reset color
    movq $1, %rax
    movq $1, %rdi
    leaq color_reset(%rip), %rsi
    movq $4, %rdx
    syscall

    # 2. Render 8x8 Grid of Slots
    xorq %r13, %r13                 # Slot index: 0 to 63

.grid_row_loop:
    xorq %r14, %r14                 # Column counter: 0 to 7

.grid_col_loop:
    movq %r13, %rax
    shlq $6, %rax                   # index * 64 bytes per slot
    leaq (%r12, %rax), %rbx         # slot flag pointer

    movq (%rbx), %rcx               # Read slot flag

    # Check state (-1 = Free, 0 = Ready, 1 = Pending)
    cmpq $-1, %rcx
    je .state_free
    cmpq $0, %rcx
    je .state_rdy
    
    # State PEND (1)
    leaq color_pend(%rip), %rsi
    leaq txt_pend(%rip), %r15
    jmp .print_slot

.state_free:
    leaq color_free(%rip), %rsi
    leaq txt_free(%rip), %r15
    jmp .print_slot

.state_rdy:
    leaq color_rdy(%rip), %rsi
    leaq txt_rdy(%rip), %r15

.print_slot:
    # Save registers across syscalls
    pushq %r12
    pushq %r13
    pushq %r14
    pushq %rsi                      # Color pointer

    # 1. Print ANSI Color
    movq %rsi, %rdx                 # Temporarily hold color string
    movq $1, %rax
    movq $1, %rdi
    movq %rdx, %rsi
    movq $7, %rdx                   # Color sequence length
    syscall

    # 2. Print Status Text ("FREE ", "PEND ", "RDY  ")
    movq $1, %rax
    movq $1, %rdi
    movq %r15, %rsi
    movq $5, %rdx                   # Text length
    syscall

    # 3. Reset color
    movq $1, %rax
    movq $1, %rdi
    leaq color_reset(%rip), %rsi
    movq $4, %rdx
    syscall

    # Restore registers
    popq %rsi
    popq %r14
    popq %r13
    popq %r12

    incq %r13
    incq %r14
    cmpq $8, %r14
    jl .grid_col_loop

    # End of row newline
    movq $1, %rax
    movq $1, %rdi
    leaq str_nl(%rip), %rsi
    movq $1, %rdx
    syscall

    cmpq $64, %r13
    jl .grid_row_loop

    # 3. Sleep ~100ms
    subq $16, %rsp
    movq $0, (%rsp)
    movq $100000000, 8(%rsp)        # 100ms
    movq $35, %rax
    movq %rsp, %rdi
    xorq %rsi, %rsi
    syscall
    addq $16, %rsp

    jmp .render_loop

.error_exit:
    movq $60, %rax
    movq $1, %rdi
    syscall

# =============================================================================
# Helper: Convert uint64 (%rdi) to ASCII string in buffer (%rsi)
# Returns exact string length in %rdx
# =============================================================================
int_to_ascii:
    pushq %rax
    pushq %rbx
    pushq %rcx
    pushq %rdi
    pushq %r8

    movq %rsi, %r8                  # Buffer start
    movq %rdi, %rax
    movq $10, %rcx
    
    testq %rax, %rax
    jnz .conv_loop
    movb $'0', (%r8)
    movq $1, %rdx
    jmp .conv_done

.conv_loop:
    testq %rax, %rax
    jz .conv_reverse
    xorq %rdx, %rdx
    divq %rcx
    addb $48, %dl
    movb %dl, (%rsi)
    incq %rsi
    jmp .conv_loop

.conv_reverse:
    # Calculate length
    movq %rsi, %rdx
    subq %r8, %rdx                  # Length in bytes
    
    # Reverse string in place
    movq %r8, %rdi                  # Start pointer
    movq %rsi, %rsi                 # End pointer (exclusive)
    decq %rsi                       # Last char pointer

.rev_loop:
    cmpq %rdi, %rsi
    jle .conv_done
    movb (%rdi), %al
    movb (%rsi), %bl
    movb %bl, (%rdi)
    movb %al, (%rsi)
    incq %rdi
    decq %rsi
    jmp .rev_loop

.conv_done:
    popq %r8
    popq %rdi
    popq %rcx
    popq %rbx
    popq %rax
    ret

.size _start, . - _start
.section .note.GNU-stack,"",@progbits

