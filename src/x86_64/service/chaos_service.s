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
# Name: chaos_service.s
# Author: Aguas Guerreiro Roberto [agguro]
# Date: 2026-07-05
# Description: MT19937-64 Chaos Service — The High Performance Engine
# =============================================================================
# Description:
#   A high‑throughput MT19937‑64 random number service using shared memory,
#   structured as a clean “engine + slots” design:
#
#     • MT19937‑64 implemented as separate init/twist/rand functions
#     • 64 fixed‑size request slots (64 bytes each) in /dev/shm/chaos_shm
#     • Heartbeat counter for liveness monitoring
#     • Lockdown phase to clear all shared memory before use
#     • Busy‑wait + pause loop for low‑latency response
#
#   Intended use:
#     - Local processes (or a GPU feeder) request random numbers by writing
#       to shared memory slots.
#     - The service continuously scans slots, generates MT19937‑64 values,
#       and delivers them with minimal latency.
#
# Shared Memory Layout (4 KB total):
#   File: /dev/shm/chaos_shm
#
#   Slots (0..63), each 64 bytes:
#     base_i = shm_base + i * 64
#
#       offset 0:  slot_flag (int64)
#                  -  0  = request pending (service should generate)
#                  - -1  = slot free / idle
#
#       offset 8:  result (uint64)
#                  - one 64‑bit random value per request
#
#       offset 16–63: reserved for future use (e.g. batch size, engine ID, etc.)
#
#   Heartbeat:
#       offset 4088: uint64 heartbeat counter
#                    - incremented every main loop iteration
#                    - clients can poll this to verify the service is alive
#
# Protocol (per slot):
#   1. Client waits until slot_flag == -1 (slot free).
#   2. Client writes 0 to slot_flag to request a new random value.
#   3. Service loop:
#        - scans slots in round‑robin (0..63)
#        - when it sees flag == 0:
#            * calls mt_rand_64() to get a 64‑bit random
#            * writes result to offset +8
#            * sets flag back to -1
#   4. Client waits until flag == -1 again, then reads result at offset +8.
#
# Build:
#   as chaos_engine.s -o chaos_engine.o
#   ld chaos_engine.o -o chaos_engine
#
# Notes:
#   - Uses RDRAND once at startup to seed MT19937‑64.
#   - MT state (312 × 64‑bit) lives in mt_state (BSS).
#   - mt_index in .data tracks the current position in the MT state array.
#   - All shared memory is zeroed once (“lockdown”) before slots are released.
#   - Heartbeat is stored at offset 4088 (last 8 bytes of the 4 KB region).
# =============================================================================

.section .rodata
    shm_path: .asciz "/dev/shm/chaos_shm"

.section .data
    .align 8
    mt_index: .quad 313           # In .data omdat het een startwaarde heeft

.section .bss
    .align 16
    mt_state: .space 2496         # 312 * 8 bytes

.section .text
.globl _start

_start:
    # 1. Open/Create de Shared Memory file
    movq $2, %rax               # sys_open
    leaq shm_path(%rip), %rdi
    movq $66, %rsi              # O_RDWR | O_CREAT
    movq $0666, %rdx            # rw-rw-rw-
    syscall
    testq %rax, %rax
    js .error_exit
    movq %rax, %r8              # FD in %r8

    # 2. Stel de grootte in (4096 bytes)
    movq $77, %rax              # sys_ftruncate
    movq %r8, %rdi
    movq $4096, %rsi
    syscall

    # 3. Map de file in het geheugen
    movq $9, %rax               # sys_mmap
    xorq %rdi, %rdi
    movq $4096, %rsi
    movq $3, %rdx               # PROT_READ | PROT_WRITE
    movq $1, %r10               # MAP_SHARED
    movq %r8, %r8
    xorq %r9, %r9
    syscall
    testq %rax, %rax
    js .error_exit
    movq %rax, %r12             # %r12 = SHM Base Pointer

    # 4. Lockdown: initialiseer geheugen op 0
    xorq %rcx, %rcx
.lockdown:
    movq $0, (%r12, %rcx, 8)
    incq %rcx
    cmpq $512, %rcx             # 512 * 8 = 4096
    jne .lockdown

    # 5. Seeding met RDRAND
.get_seed:
    rdrand %rax
    jnc .get_seed
    call mt_init_64

    # 6. Geef slots vrij (vlaggen op -1)
    xorq %rcx, %rcx
.release_slots:
    movq %rcx, %rax
    shlq $6, %rax               # Index * 64 bytes per slot
    movq $-1, (%r12, %rax)
    incq %rcx
    cmpq $64, %rcx
    jne .release_slots

    xorq %r14, %r14             # Slot scan index
    xorq %r15, %r15             # Heartbeat counter

.main_loop:
    incq %r15
    movq %r15, 4088(%r12)       # Update heartbeat op offset 4088

    # Scan huidig slot
    movq %r14, %rax
    shlq $6, %rax
    leaq (%r12, %rax), %rbx     # %rbx = Adres van vlag

    cmpq $0, (%rbx)             # Check op aanvraag (vlag == 0)
    jne .next_slot

    # Genereer getal
    call mt_rand_64
    movq %rax, 8(%rbx)          # Schrijf naar slot + 8
    movq $-1, (%rbx)            # Geef terug aan client

.next_slot:
    incq %r14
    andq $63, %r14              # Wrap around 64 slots
    pause
    jmp .main_loop

.error_exit:
    movq $60, %rax
    movq $1, %rdi
    syscall

# --- MT19937-64 IMPLEMENTATION ---

mt_init_64:
    leaq mt_state(%rip), %rdi
    movq %rax, (%rdi)
    movq $1, %rcx
.init_loop:
    movq -8(%rdi, %rcx, 8), %rax
    movq %rax, %rdx
    shrq $62, %rdx
    xorq %rdx, %rax
    movabsq $6364136223846793005, %rdx
    imulq %rdx, %rax
    addq %rcx, %rax
    movq %rax, (%rdi, %rcx, 8)
    incq %rcx
    cmpq $312, %rcx
    jne .init_loop
    movq %rcx, mt_index(%rip)
    ret

mt_rand_64:
    movq mt_index(%rip), %rax
    cmpq $312, %rax
    jl .no_twist
    call mt_twist
    xorq %rax, %rax
.no_twist:
    leaq mt_state(%rip), %rdx
    movq (%rdx, %rax, 8), %r8
    incq %rax
    movq %rax, mt_index(%rip)

    # Tempering (Fix voor 64-bit immediates)
    movq %r8, %rax
    shrq $29, %rax
    movabsq $0x5555555555555555, %r9
    andq %r9, %rax
    xorq %rax, %r8
    
    movq %r8, %rax
    shlq $17, %rax
    movabsq $0x71D67FFFEDA60000, %r9
    andq %r9, %rax
    xorq %rax, %r8
    
    movq %r8, %rax
    shlq $37, %rax
    movabsq $0xFFF7EEE000000000, %r9
    andq %r9, %rax
    xorq %rax, %r8
    movq %r8, %rax
    shrq $43, %rax
    xorq %rax, %r8
    movq %r8, %rax
    ret

mt_twist:
    # No pushq %rbp needed. R9 is volatile and does not need to be saved.
    xorq %rcx, %rcx
    leaq mt_state(%rip), %rdi
.twist_loop:
    movq (%rdi, %rcx, 8), %rax
    movabsq $0xFFFFFFFF80000000, %rdx
    andq %rdx, %rax
    movq %rcx, %rdx
    incq %rdx
    cmpq $312, %rdx
    jne .no_wrap
    xorq %rdx, %rdx
.no_wrap:
    movq (%rdi, %rdx, 8), %r9
    andq $0x7FFFFFFF, %r9
    orq  %r9, %rax
    movq %rax, %rdx
    shrq $1, %rdx
    andq $1, %rax
    jz .no_xor
    movabsq $0xB5026F5AA96619E9, %r9
    xorq %r9, %rdx
.no_xor:
    movq %rcx, %r9
    addq $156, %r9
    cmpq $312, %r9
    jl .no_m_wrap
    subq $312, %r9
.no_m_wrap:
    xorq (%rdi, %r9, 8), %rdx
    movq %rdx, (%rdi, %rcx, 8)
    
    incq %rcx
    cmpq $312, %rcx
    jne .twist_loop
    movq $0, mt_index(%rip)
    ret

.size _start, . - _start
.section .note.GNU-stack,"",@progbits
