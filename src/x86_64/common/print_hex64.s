# print_hex64.s
.section .bss
    .align 16
    hex_buffer: .skip 20

.section .rodata
    newline: .ascii "\n"

.section .text
.globl print_hex_64

print_hex_64:
    # Argument zit in %rdi
    movq $hex_buffer, %rsi
    movq $15, %rcx
.h_loop:
    movq %rdi, %rdx
    andq $0xF, %rdx
    cmpb $10, %dl
    jl .is_num
    addb $87, %dl           # ASCII 'a' - 10
    jmp .save
.is_num:
    addb $48, %dl           # ASCII '0'
.save:
    movb %dl, (%rsi, %rcx)
    shrq $4, %rdi
    decq %rcx
    jns .h_loop

    # Write hex
    movq $1, %rax
    movq $1, %rdi
    movq $hex_buffer, %rsi
    movq $16, %rdx
    syscall

    # Write newline
    movq $1, %rax
    movq $1, %rdi
    leaq newline(%rip), %rsi
    movq $1, %rdx
    syscall
    ret

.size _print_hex_64, . - print_hex_64
.section .note.GNU-stack,"",@progbits
