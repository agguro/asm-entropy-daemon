# =============================================================================
# Project:      asm-entropy-daemon
# File:         chaos_engine.s
# Author:       agguro
# Date:         August 2026 
# Description:
#   A high-throughput MT19937-64 random number service using shared memory,
#   structured as a clean engine and slots design:
#
#     - MT19937-64 implemented as separate init/twist/rand functions
#     - 64 fixed-size request slots (64 bytes each) in /dev/shm/chaos_shm
#     - Heartbeat counter for liveness monitoring
#     - Lockdown phase to clear all shared memory before use
#     - Busy-wait loop with pause instruction for low-latency response
#
# Shared Memory Layout (4 KB total):
#   File: /dev/shm/chaos_shm
#
#   Slots (0..63), each 64 bytes:
#     base_i = shm_base + i * 64
#       offset 0:  slot_flag (int64)
#                  -  0 = request pending (service generates result)
#                  - -1 = slot free / idle
#       offset 8:  result (uint64)
#                  - one 64-bit random value per request
#       offset 16-63: reserved
#
#   Heartbeat:
#       offset 4088: uint64 heartbeat counter
#                    - incremented on every main loop iteration
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

.equ SYS_OPEN,       2
.equ SYS_MMAP,       9
.equ SYS_FTRUNCATE,  77
.equ SYS_EXIT,       60

.equ O_RDWR_CREAT,   0x42                   # O_RDWR (0x2) | O_CREAT (0x40) = 0x42 (66 decimal)
.equ S_IRUGO_IWUGO,  0x1B6                  # 0666 octal = 0x1B6 (438 decimal) - rw-rw-rw- permissions
.equ PROT_READ_WRITE,0x3                    # PROT_READ (0x1) | PROT_WRITE (0x2) = 0x3
.equ MAP_SHARED,     0x1

.section .rodata
    shm_path:       .asciz "/dev/shm/chaos_shm"

.section .data
    .align 8
    mt_index:       .quad 313               # State index initialized beyond 312 to trigger twist on first read

.section .bss
    .align 16
    mt_state:       .space 2496             # 312 elements * 8 bytes = 2496 bytes state array

.section .text
.globl _start

_start:
    # -------------------------------------------------------------------------
    # 1. Open or create shared memory backing file (/dev/shm/chaos_shm)
    # -------------------------------------------------------------------------
    movq    $SYS_OPEN,          %rax
    leaq    shm_path(%rip),     %rdi
    movq    $O_RDWR_CREAT,      %rsi
    movq    $S_IRUGO_IWUGO,     %rdx
    syscall
    testq   %rax,               %rax
    js      .error_exit
    movq    %rax,               %r8         # Store shared memory file descriptor in %r8

    # -------------------------------------------------------------------------
    # 2. Configure shared memory region size to 4096 bytes (4 KB page)
    # -------------------------------------------------------------------------
    movq    $SYS_FTRUNCATE,     %rax
    movq    %r8,                %rdi
    movq    $4096,              %rsi
    syscall
    testq   %rax,               %rax
    js      .error_exit

    # -------------------------------------------------------------------------
    # 3. Map shared memory file descriptor into process address space
    # -------------------------------------------------------------------------
    movq    $SYS_MMAP,          %rax
    xorq    %rdi,               %rdi
    movq    $4096,              %rsi
    movq    $PROT_READ_WRITE,   %rdx
    movq    $MAP_SHARED,        %r10
    movq    %r8,                %r8
    xorq    %r9,                %r9
    syscall
    testq   %rax,               %rax
    js      .error_exit
    movq    %rax,               %r12        # %r12 = Base pointer to mapped shared memory space

    # -------------------------------------------------------------------------
    # 4. Lockdown phase: zero out entire 4096-byte memory page
    # -------------------------------------------------------------------------
    xorq    %rcx,               %rcx

.lockdown:
    movq    $0,                 (%r12, %rcx, 8)
    incq    %rcx
    cmpq    $512,               %rcx        # 512 quadwords * 8 bytes = 4096 bytes
    jne     .lockdown

    # -------------------------------------------------------------------------
    # 5. Initialize MT19937-64 state seeded with hardware random number (RDRAND)
    # -------------------------------------------------------------------------
.get_seed:
    rdrand  %rax
    jnc     .get_seed
    call    mt_init_64

    # -------------------------------------------------------------------------
    # 6. Initialize all 64 request slots to free state (flag = -1)
    # -------------------------------------------------------------------------
    xorq    %rcx,               %rcx

.release_slots:
    movq    %rcx,               %rax
    shlq    $6,                 %rax        # Multiply slot index by 64 bytes
    movq    $-1,                (%r12, %rax)
    incq    %rcx
    cmpq    $64,                %rcx
    jne     .release_slots

    xorq    %r14,               %r14        # %r14 = Current slot scan index (0..63)
    xorq    %r15,               %r15        # %r15 = Heartbeat counter value

    # -------------------------------------------------------------------------
    # 7. Main Service Engine Polling Loop
    # -------------------------------------------------------------------------
.main_loop:
    incq    %r15
    movq    %r15,               4088(%r12)  # Write heartbeat to offset 4088

    # Calculate memory address of current slot flag
    movq    %r14,               %rax
    shlq    $6,                 %rax        # Slot offset = index * 64
    leaq    (%r12, %rax),       %rbx        # %rbx = Pointer to slot flag

    # Verify if slot flag is zero (pending request from client)
    cmpq    $0,                 (%rbx)
    jne     .next_slot

    # Generate 64-bit random number and deliver to slot
    call    mt_rand_64
    movq    %rax,               8(%rbx)     # Store random value at slot offset +8
    movq    $-1,                (%rbx)      # Set slot flag to free / completed state

.next_slot:
    incq    %r14
    andq    $63,                %r14        # Wrap index around 64 slots modulo
    pause
    jmp     .main_loop

.error_exit:
    movq    $SYS_EXIT,          %rax
    movq    $1,                 %rdi
    syscall

# =============================================================================
# Subroutine: mt_init_64
# Description: Initializes MT19937-64 state array using a 64-bit seed in %rax
# Modifies: %rax, %rcx, %rdx, %rdi
# =============================================================================
mt_init_64:
    leaq    mt_state(%rip),     %rdi
    movq    %rax,               (%rdi)      # Store initial seed at index 0
    movq    $1,                 %rcx        # Initialize loop index to 1

.init_loop:
    movq    -8(%rdi, %rcx, 8),  %rax        # Load state[i - 1]
    movq    %rax,               %rdx
    shrq    $62,                %rdx
    xorq    %rdx,               %rax
    movabsq $0x5851F42D4C957F2D,%rdx        # MT multiplier constant (6364136223846793005)
    imulq   %rdx,               %rax
    addq    %rcx,               %rax        # Add current index value
    movq    %rax,               (%rdi, %rcx, 8)
    incq    %rcx
    cmpq    $312,               %rcx
    jne     .init_loop

    movq    %rcx,               mt_index(%rip)
    ret

# =============================================================================
# Subroutine: mt_rand_64
# Description: Generates next pseudo-random 64-bit unsigned integer with tempering
# Output: %rax contains the 64-bit random number
# Modifies: %rax, %rdx, %r8, %r9
# =============================================================================
mt_rand_64:
    movq    mt_index(%rip),     %rax
    cmpq    $312,               %rax
    jl      .no_twist
    call    mt_twist
    xorq    %rax,               %rax

.no_twist:
    leaq    mt_state(%rip),     %rdx
    movq    (%rdx, %rax, 8),    %r8         # Load raw state value
    incq    %rax
    movq    %rax,               mt_index(%rip)

    # MT19937-64 Tempering Transform
    movq    %r8,                %rax
    shrq    $29,                %rax
    movabsq $0x5555555555555555,%r9         # Tempering bitmask A
    andq    %r9,                %rax
    xorq    %rax,               %r8

    movq    %r8,                %rax
    shlq    $17,                %rax
    movabsq $0x71D67FFFEDA60000,%r9         # Tempering bitmask B
    andq    %r9,                %rax
    xorq    %rax,               %r8

    movq    %r8,                %rax
    shlq    $37,                %rax
    movabsq $0xFFF7EEE000000000,%r9         # Tempering bitmask C
    andq    %r9,                %rax
    xorq    %rax,               %r8

    movq    %r8,                %rax
    shrq    $43,                %rax
    xorq    %rax,               %r8

    movq    %r8,                %rax
    ret

# =============================================================================
# Subroutine: mt_twist
# Description: Generates 312 untempered numbers in MT state array
# Modifies: %rax, %rcx, %rdx, %rbp, %rdi
# =============================================================================
mt_twist:
    pushq   %rbp
    xorq    %rcx,               %rcx
    leaq    mt_state(%rip),     %rdi

.twist_loop:
    movq    (%rdi, %rcx, 8),    %rax
    movabsq $0xFFFFFFFF80000000,%rdx        # Most significant 33 bits mask (Upper mask)
    andq    %rdx,               %rax

    movq    %rcx,               %rdx
    incq    %rdx
    cmpq    $312,               %rdx
    jne     .no_wrap
    xorq    %rdx,               %rdx

.no_wrap:
    movq    (%rdi, %rdx, 8),    %rbp
    andq    $0x7FFFFFFF,        %rbp        # Least significant 31 bits mask (Lower mask)
    orq     %rbp,               %rax

    movq    %rax,               %rdx
    shrq    $1,                 %rdx
    andq    $1,                 %rax
    jz      .no_xor
    movabsq $0xB5026F5AA96619E9,%rbp        # MT19937-64 matrix A constant
    xorq    %rbp,               %rdx

.no_xor:
    movq    %rcx,               %rbp
    addq    $156,               %rbp        # Middle offset constant (M = 156)
    cmpq    $312,               %rbp
    jl      .no_m_wrap
    subq    $312,               %rbp

.no_m_wrap:
    xorq    (%rdi, %rbp, 8),    %rdx
    movq    %rdx,               (%rdi, %rcx, 8)

    incq    %rcx
    cmpq    $312,               %rcx
    jne     .twist_loop

    movq    $0,                 mt_index(%rip)
    popq    %rbp
    ret

.size _start, . - _start
.section .note.GNU-stack,"",@progbits

