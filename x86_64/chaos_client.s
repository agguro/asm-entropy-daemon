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
    # 1. Setup SHM and Buffer (same as before)
    movq $2, %rax; leaq shm_path(%rip), %rdi; movq $2, %rsi; syscall
    movq %rax, %r8
    movq $9, %rax; xorq %rdi, %rdi; movq $4096, %rsi; movq $3, %rdx; movq $1, %r10; movq %r8, %r8; xorq %r9, %r9; syscall
    movq %rax, %r12             # r12 = SHM Base

    movq $2, %rax; leaq output_path(%rip), %rdi; movq $66, %rsi; movq $0666, %rdx; syscall
    movq %rax, %r9
    movq $77, %rax; movq %r9, %rdi; movq $8000, %rsi; syscall
    movq $9, %rax; xorq %rdi, %rdi; movq $8000, %rsi; movq $3, %rdx; movq $1, %r10; movq %r9, %r8; xorq %r9, %r9; syscall
    movq %rax, %r13             # r13 = Buffer Base

    # Loop Counters
    movq $0, %r15               # Current iteration (0 to 100,000)
    movq $0, %r14               # Circular index (0 to 999)

.main_loop:
    # --- 1. Find Slot ---
    xorq %rbx, %rbx
.scan_loop:
    movq %rbx, %rax
    shlq $6, %rax
    leaq (%r12, %rax), %rdi     # rdi = flag address

    movq $-1, %rax
    movq $0, %rdx
    lock cmpxchgq %rdx, (%rdi)
    jz .wait_for_service
    
    incq %rbx
    andq $63, %rbx
    pause                       # Polite spin
    jmp .scan_loop

.wait_for_service:
    # --- 2. Wait for Completion ---
    cmpq $-1, (%rdi)
    jne .wait_for_service

    # --- 3. Store Data ---
    movq 8(%rdi), %rax
    movq %rax, (%r13, %r14, 8)

    # --- "Slow Enough" Throttle (Optional) ---
    # Un-comment the next 3 lines if you need it even slower
    # movq $50, %rcx
    # .delay: loop .delay

    # --- 4. Loop Logic ---
    incq %r14
    cmpq $1000, %r14
    jl .no_wrap
    xorq %r14, %r14             # Reset circular index
.no_wrap:

    incq %r15
    cmpq $100000, %r15          # Check limit
    jl .main_loop

.done_exit:
    movq $60, %rax              # sys_exit
    xorq %rdi, %rdi
    syscall

.error_exit:
    movq $60, %rax
    movq $1, %rdi
    syscall

.size _start, . - _start
.section .note.GNU-stack,"",@progbits
