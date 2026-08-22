# =============================================================================
# Project:     asm-entropy-daemon
# File:        wait_until_keypressed.s
# Author:      agguro
# Date:        August 21, 2026 
# Description: Wait until a specific key is pressed by managing termios flags.
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

# =============================================================================
# Project:     asm-entropy-daemon
# File:        wait_until_keypressed.s
# Author:      agguro
# Date:        August 21, 2026 
# Description: Wait until a specific key is pressed by managing termios flags.
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

.equ SYS_READ,      0
.equ SYS_WRITE,     1
.equ SYS_IOCTL,     16
.equ SYS_EXIT,      60

.equ STDIN_FILENO,  0
.equ STDOUT_FILENO, 1

.equ TCGETS,        0x5401
.equ TCSETS,        0x5402
.equ ICANON,        2
.equ ECHO,          8

.section .data
    # Termios structure (60 bytes)
    termios:        .space 60

.section .bss
    key_buffer:     .byte 0

.section .text
.global wait_until_key

# ------------------------------------------------------------------------------
# Function: wait_until_key
# Input:    %rdi = ASCII character to wait for (e.g., 'q')
# Output:   None (returns only when the correct key is pressed)
# ------------------------------------------------------------------------------
wait_until_key:
    pushq %r12
    movq %rdi, %r12                 # Save target character in %r12

    # 1. Disable Echo and Canonical mode
    call TermIOS_Canonical_OFF
    call TermIOS_Echo_OFF

.wait_loop:
    # 2. Read a single byte from stdin
    movq $SYS_READ, %rax
    movq $STDIN_FILENO, %rdi
    movq $key_buffer, %rsi
    movq $1, %rdx
    syscall

    # If rax <= 0, no input -> try again
    testq %rax, %rax
    jle .wait_loop

    # 3. Compare pressed character with target character (%r12)
    movb key_buffer, %al
    cmpb %r12b, %al
    jne .wait_loop                  # If not equal, wait for next key

    # 4. Correct key pressed! Immediately restore terminal settings.
    call TermIOS_Canonical_ON
    call TermIOS_Echo_ON

    popq %r12
    ret

# ==============================================================================
# TERMIOS Helper Routines
# ==============================================================================
TermIOS_Canonical_ON:
    movq $ICANON, %rax
    jmp TermIOS_LocalModeFlag_SET

TermIOS_Canonical_OFF:
    movq $ICANON, %rax
    jmp TermIOS_LocalModeFlag_CLEAR

TermIOS_Echo_ON:
    movq $ECHO, %rax
    jmp TermIOS_LocalModeFlag_SET

TermIOS_Echo_OFF:
    movq $ECHO, %rax
    jmp TermIOS_LocalModeFlag_CLEAR

TermIOS_LocalModeFlag_SET:
    call TermIOS_STDIN_READ
    orl %eax, termios + 12          # c_lflag is at offset 12
    call TermIOS_STDIN_WRITE
    ret

TermIOS_LocalModeFlag_CLEAR:
    call TermIOS_STDIN_READ
    notl %eax
    andl %eax, termios + 12
    call TermIOS_STDIN_WRITE
    ret

TermIOS_STDIN_READ:
    pushq %rax
    pushq %rsi
    pushq %rdx
    movq $SYS_IOCTL, %rax
    movq $STDIN_FILENO, %rdi
    movq $TCGETS, %rsi
    movq $termios, %rdx
    syscall
    popq %rdx
    popq %rsi
    popq %rax
    ret

TermIOS_STDIN_WRITE:
    pushq %rax
    pushq %rsi
    pushq %rdx
    movq $SYS_IOCTL, %rax
    movq $STDIN_FILENO, %rdi
    movq $TCSETS, %rsi
    movq $termios, %rdx
    syscall
    popq %rdx
    popq %rsi
    popq %rax
    ret

.size wait_until_key, . - wait_until_key
.section .note.GNU-stack,"",@progbits

