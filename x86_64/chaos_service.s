# =============================================================================
# Project:      asm-entropy-daemon
# File:         chaos_client.s
# Author:       agguro
# Date:         August 20, 2026 
# Description:  High-throughput client logger template that continuously reads random 
#               64-bit entropy values from the Chaos Engine service via shared memory (mmap)
#               and writes them into a circular memory-mapped output buffer file.
#
#               NOTE: This file serves as a robust IPC architecture template for 
#               future assembly (.s) programs requiring zero-latency communication 
#               and atomic slot synchronization via shared memory.
#
#   MATHEMATICAL & STRUCTURAL PROPERTIES:
#   - Circular Buffer Capacity: 1000 entries * 8 bytes = 8000 bytes total.
#   - Index Wrapping: Modulo arithmetic using bitmasking / conditional reset 
#     ensures indices map strictly within the discrete interval [0, 999].
#   - IPC Synchronization Protocol (State Machine):
#     • -1 = Slot is free/idle (ready to be claimed)
#     •  1 = Request pending (client set flag to request entropy)
#     •  0 = Result ready (service generated value and stored payload)
#   - Watchdog & Liveness: Monitors heartbeat at offset 4088 to detect daemon stalls.
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

.section .rodata
    shm_path:    .asciz "/dev/shm/chaos_shm"
    output_path: .asciz "/tmp/chaos_buffer.bin"

.section .text
.globl _start

_start:
    # -------------------------------------------------------------------------
    # 1. Establish Shared Memory Connection (Chaos Engine IPC)
    # -------------------------------------------------------------------------
    movq $2, %rax                   # System call: sys_open (NR 2)
    leaq shm_path(%rip), %rdi       # Pointer to shared memory path string
    movq $2, %rsi                   # Flags: O_RDWR (Read/Write access)
    xorq %rdx, %rdx                 # Mode: 0 (existing file descriptor open)
    syscall                         # Open connection
    testq %rax, %rax                # Validate file descriptor
    js .error_exit                  # Jump on failure
    movq %rax, %r8                  # Store shared memory file descriptor in %r8

    # Map the 4 KB shared memory region into client address space
    movq $9, %rax                   # System call: sys_mmap (NR 9)
    xorq %rdi, %rdi                 # Address hint: NULL (kernel decides)
    movq $4096, %rsi                # Length: 4096 bytes (1 virtual memory page)
    movq $3, %rdx                   # Protection: PROT_READ (1) | PROT_WRITE (2)
    movq $1, %r10                   # Flags: MAP_SHARED (changes visible globally)
    movq %r8, %r8                   # File descriptor argument
    xorq %r9, %r9                   # Offset: 0 bytes from start
    syscall                         # Map segment
    testq %rax, %rax                # Validate return pointer
    js .error_exit                  # Jump on failure
    movq %rax, %r12                 # %r12 = Absolute base pointer of Chaos SHM

    # -------------------------------------------------------------------------
    # 2. Establish Circular Output Buffer File (/tmp/chaos_buffer.bin)
    # -------------------------------------------------------------------------
    movq $2, %rax                   # System call: sys_open (NR 2)
    leaq output_path(%rip), %rdi    # Pointer to output path string
    movq $66, %rsi                  # Flags: O_RDWR (2) | O_CREAT (64) = 66
    movq $0666, %rdx                # File permissions: rw-rw-rw- (octal 0666)
    syscall                         # Create/open file
    testq %rax, %rax                # Validate file descriptor
    js .error_exit                  # Jump on failure
    movq %rax, %r9                  # Store output file descriptor in %r9

    # Enforce exact output size of 8000 bytes (1000 items * 8 bytes)
    movq $77, %rax                  # System call: sys_ftruncate (NR 77)
    movq %r9, %rdi                  # File descriptor argument
    movq $8000, %rsi                # Target size: 8000 bytes
    syscall                         # Truncate file structure

    # Map the output buffer into process memory for zero-copy file I/O
    movq $9, %rax                   # System call: sys_mmap (NR 9)
    xorq %rdi, %rdi                 # Address hint: NULL
    movq $8000, %rsi                # Length: 8000 bytes
    movq $3, %rdx                   # Protection: PROT_READ | PROT_WRITE
    movq $1, %r10                   # Flags: MAP_SHARED (auto-flushes to disk)
    movq %r9, %r8                   # File descriptor argument placed in %r8 for mmap ABI
    xorq %r9, %r9                   # Offset: 0 bytes
    syscall                         # Map output buffer
    testq %rax, %rax                # Validate return pointer
    js .error_exit                  # Jump on failure
    movq %rax, %r13                 # %r13 = Absolute base pointer of circular buffer

    # -------------------------------------------------------------------------
    # 3. Initialize Execution Loop Counters & Registers
    # -------------------------------------------------------------------------
    xorq %r15, %r15                 # %r15 = Total iteration counter (0 to 100,000)
    xorq %r14, %r14                 # %r14 = Circular buffer index pointer (0 to 999)

.main_loop:
    # -------------------------------------------------------------------------
    # Step A: Atomic Slot Scanning & Claiming Protocol
    # -------------------------------------------------------------------------
    xorq %rbx, %rbx                 # Reset slot search index to 0

.scan_loop:
    movq %rbx, %rax                 # Move current slot index into %rax
    shlq $6, %rax                   # Multiply by 64 bytes per slot (2^6 = 64)
    leaq (%r12, %rax), %rdi         # %rdi = Exact memory address of target slot_flag

    # Attempt to claim a free slot (-1) using atomic compare-and-swap:
    # If memory value at [%rdi] equals -1 (free), replace it atomically with 1 (request pending)
    movq $-1, %rax                  # Expected value: -1 (free slot state)
    movq $1, %rdx                   # Desired value to write: 1 (request pending flag)
    lock cmpxchgq %rdx, (%rdi)      # Atomic CAS hardware instruction
    jz .wait_for_service            # If ZF (Zero Flag) is set, swap succeeded!

    # Slot was busy; advance to next slot index in round-robin sequence
    incq %rbx                       # Increment slot index counter
    andq $63, %rbx                  # Bitwise modulo 64 restriction (indices range 0..63)
    pause                           # Low-power execution hint for hardware thread spin-loops
    jmp .scan_loop                  # Retry scanning subsequent slots

.wait_for_service:
    # -------------------------------------------------------------------------
    # Step B: Wait for Engine Completion (slot_flag becomes 0 -> result ready)
    # -------------------------------------------------------------------------
    movq (%rdi), %rax               # Read current slot flag state from shared memory
    cmpq $0, %rax                   # Check if flag == 0 (result ready indicator)
    je .store_data                  # Proceed to data extraction if ready

    # Watchdog Check (Optional expansion point): 
    # Can poll 4088(%r12) here to verify daemon heartbeat hasn't frozen.
    jmp .wait_for_service           # Spin-wait until service updates flag to 0

.store_data:
    # -------------------------------------------------------------------------
    # Step C: Extract Payload and Store in Circular Buffer
    # -------------------------------------------------------------------------
    movq 8(%rdi), %rax              # Read 64-bit random quadword payload from slot offset +8
    movq %rax, (%r13, %r14, 8)      # Write value into circular buffer: base + (index * 8)

    # Reset slot flag back to -1 (free) to release the slot back to the daemon engine
    movq $-1, (%rdi)                # Write -1 to slot flag

    # -------------------------------------------------------------------------
    # Step D: Advance Circular Buffer Index & Iteration Limits
    # -------------------------------------------------------------------------
    incq %r14                       # Increment circular buffer write position index
    cmpq $1000, %r14                # Check if buffer end boundary (1000 entries) is reached
    jl .no_wrap                     # If index < 1000, skip wraparound logic
    xorq %r14, %r14                 # Wrap circular index back to 0

.no_wrap:
    incq %r15                       # Increment main execution loop iteration count
    cmpq $100000, %r15              # Target run limit: 100,000 iterations
    jl .main_loop                   # Continue processing loop if limit not reached

.done_exit:
    # -------------------------------------------------------------------------
    # Successful Termination Exit Sequence
    # -------------------------------------------------------------------------
    movq $60, %rax                  # System call: sys_exit (NR 60)
    xorq %rdi, %rdi                 # Exit status code 0 (success)
    syscall                         # Terminate client process safely

.error_exit:
    # -------------------------------------------------------------------------
    # Error Failure Exit Sequence
    # -------------------------------------------------------------------------
    movq $60, %rax                  # System call: sys_exit (NR 60)
    movq $1, %rdi                   # Exit status code 1 (failure)
    syscall                         # Terminate process with error status code

.size _start, . - _start
.section .note.GNU-stack,"",@progbits
