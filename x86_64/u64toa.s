# =============================================================================
# Project:     asm-entropy-daemon / Snippet Library
# File:        u64toa.s
# Author:      agguro
# Date:        August 2026 
# Description:
#   Converts a 64-bit unsigned integer to a decimal ASCII string using reciprocal
#   multiplication (Magic Number: 0xCCCCCCCCCCCCCCCD) to avoid costly hardware
#   division instructions. The buffer is filled from right to left.
#
# Input:
#   - %rdi : Unsigned 64-bit value to convert
#   - %rsi : Pointer to the start of the target buffer
#   - %rdx : Maximum buffer length (capacity)
#
# Output:
#   - %rax : Status code (0 = success, 1 = buffer overflow)
#   - %rsi : Pointer to the first digit of the resulting string
#   - %rdx : Actual length of the resulting string
#   - %rdi : Preserved (unchanged)
#
# Architecture: x86_64 | Linux SysV ABI | AT&T Syntax
#
# Copyright 2026 agguro
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# =============================================================================

.section .text
.globl u64toa
.type u64toa, @function

u64toa:
    # --------------------------------------------------------------------------
    # Setup pointers and magic number for division by 10
    # --------------------------------------------------------------------------
    leaq    (%rsi, %rdx), %rcx          # %rcx = End of buffer (writing backwards)
    movq    %rcx, %r9                   # Save end address for final length calculation
    movq    %rdi, %rax                  # %rax = Working copy of the input value
    movabsq $0xCCCCCCCCCCCCCCCD, %r8    # Magic number for reciprocal division by 10

# ------------------------------------------------------------------------------
# Conversion Loop (Fills buffer from right to left)
# ------------------------------------------------------------------------------
.u64toa_loop:
    decq    %rcx                        # Move buffer pointer one byte to the left
    cmpq    %rsi, %rcx                  # Check for potential buffer overflow
    jl      .u64toa_overflow            # If current pointer < start, jump to error

    movq    %rax, %r11                  # Copy current value for modulo calculation
    mulq    %r8                         # Multiply value by magic number (high 64-bits in %rdx)
    shrq    $3, %rdx                    # %rdx = Quotient (value / 10)
    
    # Calculate remainder (Modulo): %r11 = value - (quotient * 10)
    leaq    (%rdx, %rdx, 4), %r10       # %r10 = quotient * 5
    shlq    $1, %r10                    # %r10 = quotient * 10
    subq    %r10, %r11                  # %r11 = Remainder / digit value (0 through 9)
    
    # Convert numeric digit to ASCII and store in buffer
    addb    $'0', %r11b                 # Add ASCII offset for '0'
    movb    %r11b, (%rcx)               # Store ASCII byte into backward buffer pointer
    
    movq    %rdx, %rax                  # Prepare quotient for next iteration in %rax
    testq   %rax, %rax                  # Check if quotient is zero
    jnz     .u64toa_loop                # If not zero, continue loop

    # --------------------------------------------------------------------------
    # Success Exit
    # --------------------------------------------------------------------------
    movq    %r9, %rdx                   # Load saved end address
    subq    %rcx, %rdx                  # %rdx = Actual string length
    movq    %rcx, %rsi                  # %rsi = Pointer to the first digit
    xorq    %rax, %rax                  # Return status 0 (Success)
    ret

# ------------------------------------------------------------------------------
# Error Path (Buffer Overflow)
# ------------------------------------------------------------------------------
.u64toa_overflow:
    movq    $1, %rax                    # Return status 1 (Overflow error)
    ret

.size u64toa, . - u64toa
.section .note.GNU-stack,"",@progbits
