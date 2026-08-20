# =============================================================================
# Project:      asm-entropy-daemon
# File:         print_hex64.s
# Author:       agguro
# Date:         August 20, 2026 
# Description:  Subroutine to format and print a 64-bit register value as 16 
#               uppercase/lowercase hexadecimal characters to standard output.
#
#   MATHEMATICAL & STRUCTURAL PROPERTIES:
#   - Nibble Extraction: Uses bitwise masking (`& 0xF`) to isolate 4-bit chunks.
#   - ASCII Conversion: Maps numeric nibbles [0-9] via offset 48 ('0') and 
#     alphabetical nibbles [10-15] via offset 87 ('a'-'f').
#   - Endianness Handling: Processes nibbles right-to-left into a 16-byte buffer.
#
# Architecture: x86_64 | Linux SysV ABI | AT&T Syntax
#
# Copyright 2026 agguro
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# =============================================================================

.section .bss
    .align 16
    hex_buffer: .skip 16            # Temporary storage buffer for 16 hex ASCII bytes

.section .rodata
    newline:    .ascii "\n"         # Terminal newline character delimiter

.section .text
.globl print_hex_64

# =============================================================================
# Subroutine: print_hex_64
# Input:    %rdi contains the raw 64-bit integer value to be formatted and printed
# Modifies: %rax, %rcx, %rdx, %rsi, %rdi
# =============================================================================
print_hex_64:
    movq    $hex_buffer, %rsi       # Load base address of hex output buffer into %rsi
    movq    $15, %rcx               # Initialize loop counter index to 15 (rightmost nibble)

.hex_loop:
    movq    %rdi, %rdx              # Copy current 64-bit value into %rdx for bit manipulation
    andq    $0xF, %rdx              # Isolate the lowest 4 bits (one hexadecimal nibble: 0..15)
    
    cmpb    $10, %dl                # Compare isolated nibble value against decimal 10
    jl      .is_digit               # If < 10, it is a numeric digit ('0'-'9')
    addb    $87, %dl                # Convert values 10-15 to ASCII characters 'a'-'f' (10 + 87 = 97 / 'a')
    jmp     .save_char              # Skip numeric conversion branch

.is_digit:
    addb    $48, %dl                # Convert values 0-9 to ASCII characters '0'-'9' (0 + 48 = 48 / '0')

.save_char:
    movb    %dl, (%rsi, %rcx)       # Store computed ASCII byte into buffer at offset %rcx
    shrq    $4, %rdi                # Shift 64-bit input value right by 4 bits to target next nibble
    decq    %rcx                    # Decrement buffer index pointer
    jns     .hex_loop               # Continue loop while %rcx >= 0 (until all 16 nibbles are processed)

    # -------------------------------------------------------------------------
    # Write formatted hex buffer to STDOUT (File Descriptor 1)
    # -------------------------------------------------------------------------
    movq    $1, %rax                # System call: sys_write (NR 1)
    movq    $1, %rdi                # File descriptor argument: STDOUT (1)
    movq    $hex_buffer, %rsi       # Pointer to formatted hex character buffer
    movq    $16, %rdx               # Length of buffer: exactly 16 bytes
    syscall                         # Invoke kernel write operation

    # -------------------------------------------------------------------------
    # Write trailing newline character to STDOUT
    # -------------------------------------------------------------------------
    movq    $1, %rax                # System call: sys_write (NR 1)
    movq    $1, %rdi                # File descriptor argument: STDOUT (1)
    leaq    newline(%rip), %rsi     # Pointer to newline character string
    movq    $1, %rdx                # Length: 1 byte
    syscall                         # Invoke kernel write operation
    
    ret                             # Return control to calling procedure

.size print_hex_64, . - print_hex_64
.section .note.GNU-stack,"",@progbits
