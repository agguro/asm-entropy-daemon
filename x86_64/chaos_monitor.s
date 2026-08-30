# =============================================================================
# Project:      asm-entropy-daemon
# File:         chaos_monitor.s
# Author:       agguro
# Date:         August 2026
# Description:  Minimalist live terminal HUD monitor for the Chaos Engine SHM.
#               Displays heartbeat and an 8x8 slot matrix in hex (00, 01, FF).
#
# Shared Memory Layout (4 KB):
#   File: /dev/shm/chaos_shm
#   Slots (0..63), 64 bytes each:
#     offset 0: slot_flag (int64) -> -1 (FF: Free), 0 (00: Pend), >0 (01: Ready)
#   Heartbeat:
#     offset 4088: uint64 heartbeat counter
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

.equ SYS_READ,       0
.equ SYS_WRITE,      1
.equ SYS_OPEN,       2
.equ SYS_MMAP,       9
.equ SYS_IOCTL,      16
.equ SYS_NANOSLEEP,  35
.equ SYS_EXIT,       60

.equ STDIN_FILENO,   0
.equ STDOUT_FILENO,  1

.equ O_RDWR,         0x02
.equ PROT_READ_WRITE,0x03                   # PROT_READ (0x01) | PROT_WRITE (0x02) = 0x03
.equ MAP_SHARED,     0x01

.equ TCGETS,         0x5401
.equ TCSETS,         0x5402
.equ ICANON,         0x02
.equ ECHO,           0x08

.section .rodata
    shm_path:       .asciz "/dev/shm/chaos_shm"
    
    # ANSI terminal control escape sequences
    clear_screen:   .asciz "\033[2J\033[H"
    cursor_home:    .asciz "\033[H"
    hide_cursor:    .asciz "\033[?25l"
    show_cursor:    .asciz "\033[?25h"

    # Minimalist UI text blocks
    str_header:     .asciz "\n CHAOS ENGINE LIVE MONITOR (8x8)\n\n"
    str_legend:     .asciz "\n State: FF=Free  00=Pending  01=Ready | [q] Exit\n"

.section .data
    # In-place mutable heartbeat string buffer
    hb_str:         .ascii " Heartbeat: ["
    hb_val:         .byte  0x30                     # 0x30 = ASCII character '0'
    hb_tail:        .asciz "]\n\n"

    termios_orig:   .space 60
    termios_work:   .space 60

.section .bss
    key_buffer:     .byte  0
    # 8 rows * (1 leading indent space + 8 slots * 3 chars + 1 newline) = 8 * 26 = 208 bytes
    grid_buffer:    .skip  208

.section .text
.globl _start

_start:
    # -------------------------------------------------------------------------
    # 1. Open Shared Memory file descriptor (/dev/shm/chaos_shm)
    # -------------------------------------------------------------------------
    movq    $SYS_OPEN,          %rax
    leaq    shm_path(%rip),     %rdi
    movq    $O_RDWR,            %rsi
    syscall
    testq   %rax,               %rax
    js      .error_exit
    movq    %rax,               %r8                 # %r8 = Shared memory file descriptor

    # -------------------------------------------------------------------------
    # 2. Map Shared Memory space (4096 bytes / 4 KB page)
    # -------------------------------------------------------------------------
    movq    $SYS_MMAP,          %rax
    xorq    %rdi,               %rdi
    movq    $4096,              %rsi
    movq    $PROT_READ_WRITE,   %rdx
    movq    $MAP_SHARED,        %r10
    xorq    %r9,                %r9
    syscall
    testq   %rax,               %rax
    js      .error_exit
    movq    %rax,               %r12                # %r12 = Base pointer to mapped shared memory space

    # -------------------------------------------------------------------------
    # 3. Configure Terminal (Raw mode, non-blocking input)
    # -------------------------------------------------------------------------
    call    termios_init

    # Hide terminal cursor for smooth HUD display
    movq    $SYS_WRITE,         %rax
    movq    $STDOUT_FILENO,     %rdi
    leaq    hide_cursor(%rip),  %rsi
    movq    $6,                 %rdx
    syscall

    # Clear terminal screen buffer on initialization
    movq    $SYS_WRITE,         %rax
    movq    $STDOUT_FILENO,     %rdi
    leaq    clear_screen(%rip), %rsi
    movq    $7,                 %rdx
    syscall

.render_loop:
    # -------------------------------------------------------------------------
    # 4. Check for exit key ('q' = 0x71, 'Q' = 0x51) without blocking
    # -------------------------------------------------------------------------
    movq    $SYS_READ,          %rax
    movq    $STDIN_FILENO,      %rdi
    leaq    key_buffer(%rip),   %rsi
    movq    $1,                 %rdx
    syscall

    testq   %rax,               %rax
    jle     .continue_render
    
    movb    key_buffer(%rip),   %al
    cmpb    $0x71,              %al                 # 0x71 = ASCII 'q'
    je      .graceful_exit
    cmpb    $0x51,              %al                 # 0x51 = ASCII 'Q'
    je      .graceful_exit

.continue_render:
    # Reposition cursor to home (top-left) for flicker-free redrawing
    movq    $SYS_WRITE,         %rax
    movq    $STDOUT_FILENO,     %rdi
    leaq    cursor_home(%rip),  %rsi
    movq    $3,                 %rdx
    syscall

    # Print monitor title header
    movq    $SYS_WRITE,         %rax
    movq    $STDOUT_FILENO,     %rdi
    leaq    str_header(%rip),   %rsi
    movq    $35,                %rdx
    syscall

    # Extract heartbeat counter LSB and format output character
    movq    4088(%r12),         %rax                # Load heartbeat counter from offset 4088
    andq    $1,                 %rax                # Mask least significant bit
    addb    $0x30,              %al                 # 0x30 = ASCII '0' -> yields '0' (0x30) or '1' (0x31)
    movb    %al,                hb_val(%rip)

    # Print heartbeat string line
    movq    $SYS_WRITE,         %rax
    movq    $STDOUT_FILENO,     %rdi
    leaq    hb_str(%rip),       %rsi
    movq    $16,                %rdx
    syscall

    # -------------------------------------------------------------------------
    # 5. Assemble the 8x8 Hex Status Grid into grid_buffer
    # -------------------------------------------------------------------------
    leaq    grid_buffer(%rip),  %rdi                # Output buffer write cursor
    xorq    %r13,               %r13                # Slot index (0..63)

.row_loop:
    # Indent matrix row with a single space character
    movb    $0x20,              (%rdi)              # 0x20 = ASCII space ' '
    incq    %rdi
    xorq    %r14,               %r14                # Column index counter (0..7)

.col_loop:
    movq    %r13,               %rax
    shlq    $6,                 %rax                # Multiply index by 64 bytes per slot
    movq    (%r12, %rax),       %rcx                # Read slot_flag (int64)

    cmpq    $-1,                %rcx
    je      .fmt_free
    cmpq    $0,                 %rcx
    je      .fmt_pend

    # State: Ready (Flag > 0) -> "01"
    movb    $0x30,              (%rdi)              # 0x30 = ASCII '0'
    movb    $0x31,              1(%rdi)             # 0x31 = ASCII '1'
    jmp     .fmt_next

.fmt_free:
    # State: Free (Flag == -1) -> "FF"
    movb    $0x46,              (%rdi)              # 0x46 = ASCII 'F'
    movb    $0x46,              1(%rdi)             # 0x46 = ASCII 'F'
    jmp     .fmt_next

.fmt_pend:
    # State: Pending (Flag == 0) -> "00"
    movb    $0x30,              (%rdi)              # 0x30 = ASCII '0'
    movb    $0x30,              1(%rdi)             # 0x30 = ASCII '0'

.fmt_next:
    movb    $0x20,              2(%rdi)             # 0x20 = ASCII delimiter space ' '
    addq    $3,                 %rdi

    incq    %r13
    incq    %r14
    cmpq    $8,                 %r14
    jl      .col_loop

    # Terminate matrix row with newline character
    movb    $0x0A,              (%rdi)              # 0x0A = ASCII newline '\n'
    incq    %rdi

    cmpq    $64,                %r13
    jl      .row_loop

    # Flush entire 8x8 grid buffer to standard output in a single write operation
    movq    $SYS_WRITE,         %rax
    movq    $STDOUT_FILENO,     %rdi
    leaq    grid_buffer(%rip),  %rsi
    movq    $208,               %rdx                # 8 rows * 26 bytes per row = 208 bytes total
    syscall

    # Print state legend and key binding instructions
    movq    $SYS_WRITE,         %rax
    movq    $STDOUT_FILENO,     %rdi
    leaq    str_legend(%rip),   %rsi
    movq    $49,                %rdx
    syscall

    # -------------------------------------------------------------------------
    # 6. Throttle frame rate: sleep 100 ms (100,000,000 ns)
    # -------------------------------------------------------------------------
    subq    $16,                %rsp
    movq    $0,                 (%rsp)              # tv_sec = 0 seconds
    movq    $100000000,         8(%rsp)             # tv_nsec = 100,000,000 nanoseconds
    movq    $SYS_NANOSLEEP,     %rax
    movq    %rsp,               %rdi
    xorq    %rsi,               %rsi
    syscall
    addq    $16,                %rsp

    jmp     .render_loop

.graceful_exit:
    call    termios_restore
    movq    $SYS_WRITE,         %rax
    movq    $STDOUT_FILENO,     %rdi
    leaq    show_cursor(%rip),  %rsi
    movq    $6,                 %rdx
    syscall
    movq    $SYS_EXIT,          %rax
    xorq    %rdi,               %rdi
    syscall

.error_exit:
    call    termios_restore
    movq    $SYS_WRITE,         %rax
    movq    $STDOUT_FILENO,     %rdi
    leaq    show_cursor(%rip),  %rsi
    movq    $6,                 %rdx
    syscall
    movq    $SYS_EXIT,          %rax
    movq    $1,                 %rdi
    syscall

# -----------------------------------------------------------------------------
# Subroutines: Terminal State Management
# -----------------------------------------------------------------------------
termios_init:
    movq    $SYS_IOCTL,         %rax
    movq    $STDIN_FILENO,      %rdi
    movq    $TCGETS,            %rsi
    leaq    termios_orig(%rip), %rdx
    syscall

    leaq    termios_orig(%rip), %rsi
    leaq    termios_work(%rip), %rdi
    movq    $8,                 %rcx
.copy_term:
    movq    (%rsi),             %rax
    movq    %rax,               (%rdi)
    addq    $8,                 %rsi
    addq    $8,                 %rdi
    decq    %rcx
    jnz     .copy_term

    # Disable ICANON and ECHO flags in local termios work structure
    movq    $ICANON,            %rax
    notq    %rax
    movq    termios_work + 12(%rip), %rdx
    andq    %rax,               %rdx
    movq    $ECHO,              %rax
    notq    %rax
    andq    %rax,               %rdx
    movq    %rdx,               termios_work + 12(%rip)

    # Set non-blocking read timeouts: VTIME = 0, VMIN = 0
    movb    $0,                 termios_work + 23(%rip)
    movb    $0,                 termios_work + 24(%rip)

    movq    $SYS_IOCTL,         %rax
    movq    $STDIN_FILENO,      %rdi
    movq    $TCSETS,            %rsi
    leaq    termios_work(%rip), %rdx
    syscall
    ret

termios_restore:
    movq    $SYS_IOCTL,         %rax
    movq    $STDIN_FILENO,      %rdi
    movq    $TCSETS,            %rsi
    leaq    termios_orig(%rip), %rdx
    syscall
    ret

.size _start, . - _start
.section .note.GNU-stack,"",@progbits

