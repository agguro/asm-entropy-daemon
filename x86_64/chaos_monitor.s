# =============================================================================
# Project:     asm-entropy-daemon
# File:        chaos_monitor.s
# Author:      agguro
# Date:        August 23, 2026 
# Description:
#   A clean, flicker-free live terminal HUD monitor for the Chaos Engine 
#   shared memory space, featuring a framed layout, toggle heartbeat, 
#   aligned slot grid, and non-blocking termios 'q' exit mechanism.
#
# Shared Memory Layout (4 KB total):
#   File: /dev/shm/chaos_shm
#
#   Slots (0..63), each 64 bytes:
#     base_i = shm_base + i * 64
#        offset 0:  slot_flag (int64)
#                   -  0  = request pending
#                   - -1  = slot free / idle
#        offset 8:  result (uint64)
#
#   Heartbeat:
#        offset 4088: uint64 heartbeat counter (toggles or updates)
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

# --- UI LAYOUT CONSTANTS (.equ) ---
.equ BOX_WIDTH,     57          # Total inner width of the box lines
.equ SLOT_WIDTH,    6           # Fixed width per slot text (e.g. "FREE ")
.equ NUM_COLS,      8           # Number of slots per row
.equ ROW_PREFIX_LEN,2           # Length of row prefix ("| ")
.equ ROW_SUFFIX_LEN,3           # Length of row suffix (" |\n")

.section .rodata
    shm_path:       .asciz "/dev/shm/chaos_shm"
    
    # ANSI Escape Sequences
    clear_screen:   .asciz "\033[2J\033[H"
    cursor_home:    .asciz "\033[H"
    hide_cursor:    .asciz "\033[?25l"
    show_cursor:    .asciz "\033[?25h"

    str_pad:        .asciz "\n\n"
    box_line:       .asciz "+-------------------------------------------------------+\n"
    str_title:      .asciz "|        === CHAOS ENGINE LIVE MONITOR (8x8) ===        |\n"

    # Part 2 Strings (Legend & Hints)
    str_legend_t:   .asciz "+------------------- LEGEND ----------------------------+\n"
    str_leg1:       .asciz "|  FREE (-1) = Slot is idle / available                 |\n"
    str_leg2:       .asciz "|  PEND ( 0) = Request pending / generating             |\n"
    str_leg3:       .asciz "|  RDY  (+) = Result ready                              |\n"
    str_hint:       .asciz "|  (Press 'q' to exit safely)                           |\n"
    
    row_prefix:     .asciz "|  "
    row_suffix:     .asciz "  |\n"

    txt_free:       .asciz " FREE "
    txt_pend:       .asciz " PEND "
    txt_rdy:        .asciz " RDY  "

.section .data
    # In-place mutable heartbeat line (Total length perfectly matches BOX_WIDTH + 1 for \n)
    hb_line:        .ascii "| Heartbeat: [ "
    hb_char:        .ascii "0"
    hb_tail:        .asciz " ]                                      |\n"

    termios_orig:   .space 60
    termios_work:   .space 60

.section .bss
    key_buffer:     .byte 0

.section .text
.globl _start

_start:
    # Open Shared Memory file descriptor
    movq    $2,             %rax
    leaq    shm_path(%rip), %rdi
    movq    $2,             %rsi
    syscall
    testq   %rax,           %rax
    js      .error_exit
    movq    %rax,           %r8

    # Map Shared Memory into virtual address space
    movq    $9,             %rax
    xorq    %rdi,           %rdi
    movq    $4096,          %rsi
    movq    $3,             %rdx
    movq    $1,             %r10
    movq    %r8,            %r8
    xorq    %r9,            %r9
    syscall
    testq   %rax,           %rax
    js      .error_exit
    movq    %rax,           %r12        # %r12 = SHM Base Pointer

    # Setup Terminal (Raw mode, non-blocking)
    call    termios_init

    # Hide terminal cursor for clean UI
    movq    $SYS_WRITE,     %rax
    movq    $STDOUT_FILENO, %rdi
    leaq    hide_cursor(%rip), %rsi
    movq    $6,             %rdx
    syscall

    # Clear screen once at startup
    movq    $SYS_WRITE,     %rax
    movq    $STDOUT_FILENO, %rdi
    leaq    clear_screen(%rip), %rsi
    movq    $7,             %rdx
    syscall

.render_loop:
    # Non-blocking key check for 'q'
    movq    $SYS_READ,      %rax
    movq    $STDIN_FILENO,  %rdi
    leaq    key_buffer(%rip), %rsi
    movq    $1,             %rdx
    syscall

    testq   %rax,           %rax
    jle     .continue_render
    
    movb    key_buffer(%rip), %al
    cmpb    $'q',           %al
    je      .graceful_exit
    cmpb    $'Q',           %al
    je      .graceful_exit

.continue_render:
    # Move cursor to home position for flicker-free update
    movq    $SYS_WRITE,     %rax
    movq    $STDOUT_FILENO, %rdi
    leaq    cursor_home(%rip), %rsi
    movq    $3,             %rdx
    syscall

    # Print top vertical padding
    movq    $SYS_WRITE,     %rax
    movq    $STDOUT_FILENO, %rdi
    leaq    str_pad(%rip),  %rsi
    movq    $2,             %rdx
    syscall

    # --- PART 1: Top Box, Title, Heartbeat ---
    movq    $SYS_WRITE,     %rax
    movq    $STDOUT_FILENO, %rdi
    leaq    box_line(%rip), %rsi
    movq    $58,            %rdx
    syscall

    movq    $SYS_WRITE,     %rax
    movq    $STDOUT_FILENO, %rdi
    leaq    str_title(%rip), %rsi
    movq    $58,            %rdx
    syscall

    # Update Heartbeat character in-place from shared memory LSB
    movq    4088(%r12),     %rax
    andq    $1,             %rax
    addb    $'0',           %al
    movb    %al,            hb_char(%rip)

    # Print Heartbeat line
    movq    $SYS_WRITE,     %rax
    movq    $STDOUT_FILENO, %rdi
    leaq    hb_line(%rip),  %rsi
    movq    $58,            %rdx
    syscall

    movq    $SYS_WRITE,     %rax
    movq    $STDOUT_FILENO, %rdi
    leaq    box_line(%rip), %rsi
    movq    $58,            %rdx
    syscall

    # --- RENDER 8x8 GRID OF SLOTS ---
    xorq    %r13,           %r13        # Slot index: 0 to 63

.grid_row_loop:
    # Print row prefix ("| ")
    movq    $SYS_WRITE,     %rax
    movq    $STDOUT_FILENO, %rdi
    leaq    row_prefix(%rip), %rsi
    movq    $ROW_PREFIX_LEN, %rdx
    syscall

    xorq    %r14,           %r14        # Column counter: 0 to 7

.grid_col_loop:
    movq    %r13,           %rax
    shlq    $6,             %rax        # index * 64 bytes per slot
    leaq    (%r12, %rax),   %rbx        # slot flag pointer

    movq    (%rbx),         %rcx        # Read slot flag

    cmpq    $-1,            %rcx
    je      .state_free
    cmpq    $0,             %rcx
    je      .state_pend
    
    leaq    txt_rdy(%rip),  %r15
    jmp     .print_slot

.state_free:
    leaq    txt_free(%rip), %r15
    jmp     .print_slot

.state_pend:
    leaq    txt_pend(%rip), %r15

.print_slot:
    pushq   %r12
    pushq   %r13
    pushq   %r14
    pushq   %r15

    movq    $SYS_WRITE,     %rax
    movq    $STDOUT_FILENO, %rdi
    movq    %r15,           %rsi
    movq    $SLOT_WIDTH,    %rdx
    syscall

    popq    %r15
    popq    %r14
    popq    %r13
    popq    %r12

    incq    %r13
    incq    %r14
    cmpq    $NUM_COLS,      %r14
    jl      .grid_col_loop

    # Print row suffix (" |\n")
    movq    $SYS_WRITE,     %rax
    movq    $STDOUT_FILENO, %rdi
    leaq    row_suffix(%rip), %rsi
    movq    $ROW_SUFFIX_LEN, %rdx
    syscall

    cmpq    $64,            %r13
    jl      .grid_row_loop

    # --- PART 2: Legend & Bottom Box ---
    movq    $SYS_WRITE,     %rax
    movq    $STDOUT_FILENO, %rdi
    leaq    box_line(%rip), %rsi
    movq    $58,            %rdx
    syscall

    movq    $SYS_WRITE,     %rax
    movq    $STDOUT_FILENO, %rdi
    leaq    str_legend_t(%rip), %rsi
    movq    $58,            %rdx
    syscall

    movq    $SYS_WRITE,     %rax
    movq    $STDOUT_FILENO, %rdi
    leaq    str_leg1(%rip), %rsi
    movq    $58,            %rdx
    syscall

    movq    $SYS_WRITE,     %rax
    movq    $STDOUT_FILENO, %rdi
    leaq    str_leg2(%rip), %rsi
    movq    $58,            %rdx
    syscall

    movq    $SYS_WRITE,     %rax
    movq    $STDOUT_FILENO, %rdi
    leaq    str_leg3(%rip), %rsi
    movq    $58,            %rdx
    syscall

    movq    $SYS_WRITE,     %rax
    movq    $STDOUT_FILENO, %rdi
    leaq    str_hint(%rip), %rsi
    movq    $58,            %rdx
    syscall

    movq    $SYS_WRITE,     %rax
    movq    $STDOUT_FILENO, %rdi
    leaq    box_line(%rip), %rsi
    movq    $58,            %rdx
    syscall

    # Sleep ~100ms using nanosleep syscall
    subq    $16,            %rsp
    movq    $0,             (%rsp)
    movq    $100000000,     8(%rsp)
    movq    $35,            %rax
    movq    %rsp,           %rdi
    xorq    %rsi,           %rsi
    syscall
    addq    $16,            %rsp

    jmp     .render_loop

.graceful_exit:
    call    termios_restore
    movq    $SYS_WRITE,     %rax
    movq    $STDOUT_FILENO, %rdi
    leaq    show_cursor(%rip), %rsi
    movq    $6,             %rdx
    syscall
    movq    $SYS_EXIT,      %rax
    xorq    %rdi,           %rdi
    syscall

.error_exit:
    call    termios_restore
    movq    $SYS_WRITE,     %rax
    movq    $STDOUT_FILENO, %rdi
    leaq    show_cursor(%rip), %rsi
    movq    $6,             %rdx
    syscall
    movq    $SYS_EXIT,      %rax
    movq    $1,             %rdi
    syscall

termios_init:
    movq    $SYS_IOCTL,     %rax
    movq    $STDIN_FILENO,  %rdi
    movq    $TCGETS,        %rsi
    leaq    termios_orig(%rip), %rdx
    syscall

    leaq    termios_orig(%rip), %rsi
    leaq    termios_work(%rip), %rdi
    movq    $8,             %rcx
.copy_term:
    movq    (%rsi),         %rax
    movq    %rax,           (%rdi)
    addq    $8,             %rsi
    addq    $8,             %rdi
    decq    %rcx
    jnz     .copy_term

    movq    $ICANON,        %rax
    notq    %rax
    movq    termios_work + 12(%rip), %rdx
    andq    %rax,           %rdx
    movq    $ECHO,          %rax
    notq    %rax
    andq    %rax,           %rdx
    movq    %rdx,           termios_work + 12(%rip)

    movb    $0,             termios_work + 23(%rip)
    movb    $0,             termios_work + 24(%rip)

    movq    $SYS_IOCTL,     %rax
    movq    $STDIN_FILENO,  %rdi
    movq    $TCSETS,        %rsi
    leaq    termios_work(%rip), %rdx
    syscall
    ret

termios_restore:
    movq    $SYS_IOCTL,     %rax
    movq    $STDIN_FILENO,  %rdi
    movq    $TCSETS,        %rsi
    leaq    termios_orig(%rip), %rdx
    syscall
    ret

.size _start, . - _start
.section .note.GNU-stack,"",@progbits
