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
# Description: Chaos Logger — SHM → MMAP Circular Buffer
# =============================================================================
# Description:
#   A high‑throughput logger that continuously reads random 64‑bit values from
#   the Chaos Engine and writes them into a circular mmap’d buffer file.
#
#   This client:
#     • Opens and maps the Chaos Engine shared memory (/dev/shm/chaos_shm)
#     • Opens/creates a binary output buffer (/tmp/chaos_buffer.bin)
#     • Forces the buffer size to 8000 bytes (1000 × 8 bytes)
#     • Maps the buffer into memory (MAP_SHARED)
#     • Continuously:
#         - Claims a free slot in the Chaos Engine
#         - Waits for the engine to generate a random value
#         - Writes the value into the circular buffer
#         - Advances the write index (0..999)
#     • Includes a watchdog that exits if the Chaos Engine stops updating
#       its heartbeat
#
# Shared Memory Layout (Chaos Engine):
#   slot_base = shm_base + slot_index * 64
#
#     offset 0:   slot_flag (int64)
#                 -1 = free
#                  0 = result ready
#                  1 = request pending
#
#     offset 8:   result (uint64)
#
#   Heartbeat:
#     offset 4088: uint64 heartbeat counter
#                  - incremented by Chaos Engine every loop
#
# Output Buffer Layout (/tmp/chaos_buffer.bin):
#   1000 × 8‑byte entries (8000 bytes total)
#   Written in a circular pattern:
#       index = 0..999, then wraps to 0
#
# Watchdog:
#   - Reads heartbeat at offset 4088
#   - If heartbeat does not change for N iterations, exits
#   - Prevents infinite hangs if Chaos Engine dies
#
# Build:
#   as chaos_logger.s -o chaos_logger.o
#   ld chaos_logger.o -o chaos_logger
#
# Notes:
#   - This logger is ideal for feeding GPU workloads or Monte Carlo pipelines.
#   - The buffer file is mmap’d, so writes are flushed automatically.
#   - No printing; this client is optimized for raw throughput.
# =============================================================================

.section .rodata
    shm_path:    .asciz "/dev/shm/chaos_shm"
    output_path: .asciz "/tmp/chaos_buffer.bin"

.section .text
.globl _start

_start:
    # 1. Open bestaande SHM (Service moet al draaien!)
    movq $2, %rax               # sys_open
    leaq shm_path(%rip), %rdi
    movq $2, %rsi               # O_RDWR
    syscall
    testq %rax, %rax
    js error_exit
    movq %rax, %r8              # FD van SHM

    # Map de 4096 bytes van de Service SHM
    movq $9, %rax               # sys_mmap
    xorq %rdi, %rdi
    movq $4096, %rsi
    movq $3, %rdx               # PROT_READ | PROT_WRITE
    movq $1, %r10               # MAP_SHARED
    movq %r8, %r8
    xorq %r9, %r9
    syscall
    testq %rax, %rax
    js error_exit
    movq %rax, %r12             # %r12 = SHM Base Pointer

    # 2. Open/Maak de Output Buffer in /tmp
    movq $2, %rax               # sys_open
    leaq output_path(%rip), %rdi
    movq $66, %rsi              # O_RDWR | O_CREAT (64 + 2)
    movq $0666, %rdx            # rw-rw-rw-
    syscall
    testq %rax, %rax
    js error_exit
    movq %rax, %r9              # FD van Buffer

    # Forceer de grootte naar 8000 bytes (1000 * 8 bytes)
    movq $77, %rax              # sys_ftruncate
    movq %r9, %rdi
    movq $8000, %rsi            
    syscall

    # Map de buffer file
    movq $9, %rax               # sys_mmap
    xorq %rdi, %rdi
    movq $8000, %rsi
    movq $3, %rdx
    movq $1, %r10               # MAP_SHARED
    movq %r9, %r8
    xorq %r9, %r9
    syscall
    testq %rax, %rax
    js error_exit
    movq %rax, %r13             # %r13 = Buffer Base Pointer

    # Initialisatie
    movq 4088(%r12), %r14       # Eerste heartbeat waarde
    xorq %r15, %r15             # Schrijf-index (0-999)
    xorq %rcx, %rcx             # Stagnatie teller voor watchdog

.main_loop:
    # --- Watchdog Sectie ---
    movq 4088(%r12), %rax
    cmpq %r14, %rax             # Is de service nog aan het tikken?
    jne .service_alive
    
    incq %rcx
    cmpq $5000000, %rcx         # Timeout drempel
    ja error_exit
    jmp .find_slot

.service_alive:
    movq %rax, %r14             # Update heartbeat
    xorq %rcx, %rcx             # Reset stagnatie

.find_slot:
    xorq %rbx, %rbx             # Scan slots 0-63
.scan_loop:
    movq %rbx, %rax
    shlq $6, %rax               # Index * 64 bytes per slot
    leaq (%r12, %rax), %rdi     # Adres van de vlag

    # Claim slot: probeer -1 te vervangen door 0
    movq $-1, %rax
    movq $0, %rdx
    lock cmpxchgq %rdx, (%rdi)
    jz .wait_for_service        # Gelukt!

    incq %rbx
    andq $63, %rbx
    pause
    testq $63, %rbx             # Na een volle ronde (64) even watchdog checken
    jz .main_loop
    jmp .scan_loop

.wait_for_service:
    # Wacht tot service data plaatst en vlag terugzet naar -1
    pause
    cmpq $-1, (%rdi)
    jne .wait_for_service

    # Data ophalen (offset +8)
    movq 8(%rdi), %rax
    
    # Schrijf naar de 1000-getallen cirkel-buffer
    movq %rax, (%r13, %r15, 8)

    # Update index en wrap around bij 1000
    incq %r15
    cmpq $1000, %r15
    jne .main_loop
    xorq %r15, %r15             
    jmp .main_loop

error_exit:
    movq $60, %rax              # sys_exit
    xorq %rdi, %rdi
    syscall

.size _start, . - _start
.section .note.GNU-stack,"",@progbits
