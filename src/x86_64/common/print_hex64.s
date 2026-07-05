# =============================================================================
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# =============================================================================
# Name: print_hex64.s
# Author: Aguas Guerreiro Roberto [agguro]
# Date: 2026-07-05
# Description: Subroutine to print a 64-bit register value as 16 hex characters.
# =============================================================================

.section .bss
    .align 16
    hex_buffer: .skip 16

.section .rodata
    newline: .ascii "\n"

.section .text
.globl print_hex_64

# Input: %rdi contains the 64-bit value to print
print_hex_64:
    movq    $hex_buffer, %rsi
    movq    $15, %rcx           # Start at the last index (15 down to 0)

.hex_loop:
    movq    %rdi, %rdx
    andq    $0xF, %rdx          # Isolate the lowest 4 bits (one hex digit)
    
    cmpb    $10, %dl
    jl      .is_digit
    addb    $87, %dl            # Convert 10-15 to 'a'-'f'
    jmp     .save_char
.is_digit:
    addb    $48, %dl            # Convert 0-9 to '0'-'9'
.save_char:
    movb    %dl, (%rsi, %rcx)
    shrq    $4, %rdi            # Shift right to process next nibble
    decq    %rcx
    jns     .hex_loop           # Continue until all 16 nibbles are processed

    # Write hex buffer to STDOUT (FD 1)
    movq    $1, %rax            # sys_write
    movq    $1, %rdi
    movq    $hex_buffer, %rsi
    movq    $16, %rdx
    syscall

    # Write newline
    movq    $1, %rax            # sys_write
    movq    $1, %rdi
    leaq    newline(%rip), %rsi
    movq    $1, %rdx
    syscall
    
    ret

.size print_hex_64, . - print_hex_64
.section .note.GNU-stack,"",@progbits
