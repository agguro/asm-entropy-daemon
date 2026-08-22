# =============================================================================
# Project:     asm-entropy-daemon
# File:        chaos_logger.s
# Author:      agguro
# Date:        August 2026 
# Description:
#   A high-throughput MT19937-64 random number stress-test client using shared memory,
#   structured with a clean parent-worker process architecture:
#
#      • Command-line argument parsing (-p for processes, -n for numbers per process, --stats, -h, --help)
#      • Automatically creates 'chaos_dumps/' directory via sys_mkdir if missing
#      • Spawns multiple parallel child workers (forks) requesting numbers concurrently
#      • Each worker writes its unique stream into local directory: chaos_dumps/dump_[PID].bin
#      • Optional --stats tracking elapsed execution time using CLOCK_MONOTONIC and u64toa
#      • Licensed under the Apache License, Version 2.0
#      • Fully compliant with SysV ABI and stack alignment requirements
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

.equ SYS_READ,          0
.equ SYS_WRITE,         1
.equ SYS_OPEN,          2
.equ SYS_CLOSE,         3
.equ SYS_MKDIR,         83
.equ SYS_FORK,          57
.equ SYS_GETPID,        39
.equ SYS_MMAP,          9
.equ SYS_MUNMAP,        11
.equ SYS_FTRUNCATE,     77
.equ SYS_CLOCK_GETTIME, 228
.equ SYS_EXIT,          60

.equ STDOUT_FILENO,     1
.equ STDERR_FILENO,     2
.equ CLOCK_MONOTONIC,   1

.extern u64toa

.section .bss
    .comm num_processes, 8
    .comm nums_per_process, 8
    .comm stats_enabled, 8
    .comm time_start_sec, 8
    .comm time_start_nsec, 8
    .comm time_end_sec, 8
    .comm time_end_nsec, 8

.section .rodata
    shm_path:           .asciz "/dev/shm/chaos_shm"
    dir_name:           .asciz "chaos_dumps"
    
    file_prefix:        .asciz "chaos_dumps/dump_"
    file_suffix:        .asciz ".bin"

    str_help_flag:      .asciz "--help"
    str_short_flag:     .asciz "-h"
    str_p_flag:         .asciz "-p"
    str_n_flag:         .asciz "-n"
    str_stats_flag:     .asciz "--stats"

    msg_usage:          .ascii "Usage: chaos_logger -p <processes> -n <numbers> [--stats]\nTry 'chaos_logger --help' for more information.\n"
    len_usage = .-msg_usage

    msg_help:           .ascii "Chaos Logger Benchmark & Stress-Test Client\n"
                        .ascii "Copyright (C) 2026 agguro. Licensed under Apache License 2.0.\n\n"
                        .ascii "Options:\n"
                        .ascii "  -p <num>     Number of parallel worker processes (forks)\n"
                        .ascii "  -n <num>     Number of 64-bit random numbers per process\n"
                        .ascii "  --stats      Print execution timing and performance statistics\n"
                        .ascii "  -h           Show short usage summary\n"
                        .ascii "  --help       Show this detailed help message\n\n"
                        .ascii "Note: Dumps are automatically saved as chaos_dumps/dump_[PID].bin\n"
    len_help = .-msg_help

    msg_connecting:     .ascii "[*] Connecting to Chaos Service...\n"
    len_conn = .-msg_connecting

    msg_connected:      .ascii "[+] Connected to Chaos Engine. Initializing storage and workers...\n"
    len_conn_ok = .-msg_connected

    msg_success:        .ascii "[+] Success: Worker completed writing local dump file.\n"
    len_success = .-msg_success

    msg_stats_header:   .ascii "\n=== BENCHMARK STATISTICS ===\n"
    len_stats_hdr = .-msg_stats_header

    msg_stats_time:     .ascii "Elapsed execution time: "
    len_stats_time = .-msg_stats_time

    msg_stats_sec:      .ascii " seconds.\n"
    len_stats_sec = .-msg_stats_sec

    msg_err_shm:        .ascii "[-] ERROR: Chaos Service not running or shm missing!\n"
    len_err_shm = .-msg_err_shm

    msg_err_args:       .ascii "[-] ERROR: Invalid or missing command-line arguments!\n"
    len_err_args = .-msg_err_args

    msg_lost:           .ascii "[-] ERROR: Connection lost! Engine heartbeat stopped.\n"
    len_lost = .-msg_lost

.section .text
.globl _start

_start:
    movq    (%rsp), %rax                # Load argc
    cmpq    $2, %rax                    # Check arguments
    jl      show_usage_and_exit

    xorq    %r8, %r8
    movq    %r8, num_processes(%rip)
    movq    %r8, nums_per_process(%rip)
    movq    %r8, stats_enabled(%rip)

    leaq    8(%rsp), %r9                # Points to argv[0]

.parse_args_loop:
    movq    (%r9), %rsi
    testq   %rsi, %rsi
    jz      .validate_args

    movq    (%r9), %rdi
    leaq    str_help_flag(%rip), %rsi
    call    strcmp_custom
    testq   %rax, %rax
    jz      show_help_and_exit

    movq    (%r9), %rdi
    leaq    str_short_flag(%rip), %rsi
    call    strcmp_custom
    testq   %rax, %rax
    jz      show_usage_and_exit

    movq    (%r9), %rdi
    leaq    str_stats_flag(%rip), %rsi
    call    strcmp_custom
    testq   %rax, %rax
    jz      .parse_stats_flag

    movq    (%r9), %rdi
    leaq    str_p_flag(%rip), %rsi
    call    strcmp_custom
    testq   %rax, %rax
    jz      .parse_p_value

    movq    (%r9), %rdi
    leaq    str_n_flag(%rip), %rsi
    call    strcmp_custom
    testq   %rax, %rax
    jz      .parse_n_value

    addq    $8, %r9
    jmp     .parse_args_loop

.parse_stats_flag:
    movq    $1, %rax
    movq    %rax, stats_enabled(%rip)
    addq    $8, %r9
    jmp     .parse_args_loop

.parse_p_value:
    addq    $8, %r9
    movq    (%r9), %rdi
    testq   %rdi, %rdi
    jz      error_args_exit
    call    atoi_custom
    movq    %rax, num_processes(%rip)
    addq    $8, %r9
    jmp     .parse_args_loop

.parse_n_value:
    addq    $8, %r9
    movq    (%r9), %rdi
    testq   %rdi, %rdi
    jz      error_args_exit
    call    atoi_custom
    movq    %rax, nums_per_process(%rip)
    addq    $8, %r9
    jmp     .parse_args_loop

.validate_args:
    movq    num_processes(%rip), %rax
    testq   %rax, %rax
    jle     error_args_exit
    
    movq    nums_per_process(%rip), %rax
    testq   %rax, %rax
    jle     error_args_exit

    # Record start time if stats enabled
    movq    stats_enabled(%rip), %rax
    testq   %rax, %rax
    jz      .skip_start_time

    movq    $SYS_CLOCK_GETTIME, %rax
    movq    $CLOCK_MONOTONIC, %rdi
    leaq    time_start_sec(%rip), %rsi
    syscall

.skip_start_time:
    movq    $SYS_WRITE, %rax
    movq    $STDOUT_FILENO, %rdi
    leaq    msg_connecting(%rip), %rsi
    movq    $len_conn, %rdx
    syscall

    # Automatically create 'chaos_dumps' directory
    movq    $SYS_MKDIR, %rax
    leaq    dir_name(%rip), %rdi
    movq    $0777, %rsi
    syscall

    # Open shared memory
    movq    $SYS_OPEN, %rax
    leaq    shm_path(%rip), %rdi
    movq    $2, %rsi
    syscall
    testq   %rax, %rax
    js      error_shm_missing
    movq    %rax, %r8

    movq    $SYS_WRITE, %rax
    movq    $STDOUT_FILENO, %rdi
    leaq    msg_connected(%rip), %rsi
    movq    $len_conn_ok, %rdx
    syscall

    # Map shared memory (4 KB)
    movq    $SYS_MMAP, %rax
    xorq    %rdi, %rdi
    movq    $4096, %rsi
    movq    $3, %rdx
    movq    $1, %r10
    movq    %r8, %r8
    xorq    %r9, %r9
    syscall
    testq   %rax, %rax
    js      error_exit
    movq    %rax, %r12

    movq    $1, 4080(%r12)

    # Spawn workers
    xorq    %r13, %r13

.spawn_workers_loop:
    movq    num_processes(%rip), %rax
    cmpq    %r13, %rax
    jle     .parent_wait_all_children

    incq    %r13

    movq    $SYS_FORK, %rax
    syscall
    testq   %rax, %rax
    js      error_exit
    jz      .worker_child_process

    jmp     .spawn_workers_loop

.parent_wait_all_children:
    movq    num_processes(%rip), %rcx
.wait_children_loop:
    movq    $-1, %rdi
    xorq    %rsi, %rsi
    movq    $61, %rax
    xorq    %rdx, %rdx
    xorq    %r10, %r10
    syscall
    testq   %rax, %rax
    js      .parent_done_waiting
    decq    %rcx
    jnz     .wait_children_loop

.parent_done_waiting:
    movq    stats_enabled(%rip), %rax
    testq   %rax, %rax
    jz      .exit_program

    movq    $SYS_CLOCK_GETTIME, %rax
    movq    $CLOCK_MONOTONIC, %rdi
    leaq    time_end_sec(%rip), %rsi
    syscall

    movq    $SYS_WRITE, %rax
    movq    $STDOUT_FILENO, %rdi
    leaq    msg_stats_header(%rip), %rsi
    movq    $len_stats_hdr, %rdx
    syscall

    movq    $SYS_WRITE, %rax
    movq    $STDOUT_FILENO, %rdi
    leaq    msg_stats_time(%rip), %rsi
    movq    $len_stats_time, %rdx
    syscall

    # Calculate elapsed seconds
    movq    time_end_sec(%rip), %rax
    subq    time_start_sec(%rip), %rax

    # Convert seconds to ASCII string via u64toa
    subq    $32, %rsp
    movq    %rax, %rdi                  # Value to convert
    movq    %rsp, %rsi                  # Buffer pointer
    movq    $32, %rdx                   # Buffer length
    call    u64toa                      # Returns %rsi = string ptr, %rdx = length

    # Print elapsed seconds string
    movq    $SYS_WRITE, %rax
    movq    $STDOUT_FILENO, %rdi
    # %rsi and %rdx are already correctly set by u64toa
    syscall
    addq    $32, %rsp

    movq    $SYS_WRITE, %rax
    movq    $STDOUT_FILENO, %rdi
    leaq    msg_stats_sec(%rip), %rsi
    movq    $len_stats_sec, %rdx
    syscall

.exit_program:
    xorq    %rdi, %rdi
    movq    $SYS_EXIT, %rax
    syscall


# --- WORKER CHILD PROCESS ---
.worker_child_process:
.worker_watchdog_init:
    movq    4088(%r12), %r14

.worker_watchdog_check_loop:
    movq    4088(%r12), %rax
    cmpq    %r14, %rax
    jne     .worker_heartbeat_advanced

    xorq    %rdx, %rdx
    movq    $1000000, %rdx
.worker_delay_tick:
    decq    %rdx
    jnz     .worker_delay_tick
    jmp     .worker_watchdog_check_loop

.worker_heartbeat_advanced:
    movq    %rax, %r14
    movq    $2, 4080(%r12)

    # Build dynamic filename: chaos_dumps/dump_[PID].bin
    subq    $128, %rsp

    # Copy prefix "chaos_dumps/dump_" into stack buffer
    leaq    file_prefix(%rip), %rsi
    movq    0(%rsi), %rax
    movq    %rax, 0(%rsp)
    movq    8(%rsi), %rax
    movq    %rax, 8(%rsp)
    movq    16(%rsi), %rax
    movq    %rax, 16(%rsp)

    # Get PID and convert via u64toa
    movq    $SYS_GETPID, %rax
    syscall
    
    movq    %rax, %rdi                  # PID value
    leaq    32(%rsp), %rsi              # Scratch buffer for PID string
    movq    $32, %rdx                   # Buffer capacity
    call    u64toa                      # Returns %rsi = ptr, %rdx = length

    # Copy PID string right after prefix (at offset 17)
    movq    %rsi, %r8                   # Source pointer
    movq    %rdx, %rcx                  # Length in bytes
    leaq    17(%rsp), %rdi              # Target position (after prefix)
    
.copy_pid_loop:
    movb    (%r8), %al
    movb    %al, (%rdi)
    incq    %r8
    incq    %rdi
    decq    %rcx
    jnz     .copy_pid_loop

    # Null-terminate before appending file suffix
    movb    $0, (%rdi)

    # Append ".bin" suffix
    leaq    file_suffix(%rip), %rsi
    movl    (%rsi), %eax
    movl    %eax, (%rdi)

    # Open / create dump file
    movq    $SYS_OPEN, %rax
    movq    %rsp, %rdi
    movq    $66, %rsi
    movq    $0666, %rdx
    syscall
    testq   %rax, %rax
    js      error_exit
    movq    %rax, %r9

    # Set file size
    movq    nums_per_process(%rip), %rsi
    shlq    $3, %rsi
    movq    %rsi, %r8

    movq    $SYS_FTRUNCATE, %rax
    movq    %r9, %rdi
    syscall

    # Map file
    movq    $SYS_MMAP, %rax
    xorq    %rdi, %rdi
    movq    $3, %rdx
    movq    $1, %r10
    movq    %r9, %r8
    xorq    %r9, %r9
    syscall
    testq   %rax, %rax
    js      error_exit
    movq    %rax, %r11

    xorq    %r15, %r15

.worker_acquisition_loop:
    movq    nums_per_process(%rip), %rax
    cmpq    %r15, %rax
    jle     .worker_finished_writing

    movq    4080(%r12), %rax
    cmpq    $2, %rax
    jne     error_connection_lost

    xorq    %rbx, %rbx

.worker_scan_slots:
    movq    %rbx, %rax
    shlq    $6, %rax
    leaq    (%r12, %rax), %rdi

    movq    $-1, %rax
    movq    $0, %rdx
    lock cmpxchgq %rdx, (%rdi)
    jz      .worker_wait_slot_result

    incq    %rbx
    andq    $63, %rbx
    pause
    testq   $63, %rbx
    jz      .worker_acquisition_loop
    jmp     .worker_scan_slots

.worker_wait_slot_result:
    pause
    cmpq    $-1, (%rdi)
    jne     .worker_wait_slot_result

    movq    8(%rdi), %rax
    movq    %rax, (%r11, %r15, 8)

    incq    %r15
    jmp     .worker_acquisition_loop

.worker_finished_writing:
    movq    $SYS_WRITE, %rax
    movq    $STDOUT_FILENO, %rdi
    leaq    msg_success(%rip), %rsi
    movq    $len_success, %rdx
    syscall

    xorq    %rdi, %rdi
    movq    $SYS_EXIT, %rax
    syscall


# --- HELPER FUNCTIONS ---
strcmp_custom:
.strcmp_loop:
    movb    (%rdi), %al
    movb    (%rsi), %bl
    cmpb    %bl, %al
    jne     .strcmp_diff
    testb   %al, %al
    jz      .strcmp_equal
    incq    %rdi
    incq    %rsi
    jmp     .strcmp_loop
.strcmp_diff:
    movq    $1, %rax
    ret
.strcmp_equal:
    xorq    %rax, %rax
    ret

atoi_custom:
    xorq    %rax, %rax
    xorq    %rcx, %rcx
.atoi_loop:
    movzbq  (%rdi), %rdx
    testq   %rdx, %rdx
    jz      .atoi_done
    subq    $'0', %rdx
    imulq   $10, %rax
    addq    %rdx, %rax
    incq    %rdi
    jmp     .atoi_loop
.atoi_done:
    ret


# --- USAGE & HELP HANDLERS ---
show_usage_and_exit:
    movq    $SYS_WRITE, %rax
    movq    $STDOUT_FILENO, %rdi
    leaq    msg_usage(%rip), %rsi
    movq    $len_usage, %rdx
    syscall
    xorq    %rdi, %rdi
    movq    $SYS_EXIT, %rax
    syscall

show_help_and_exit:
    movq    $SYS_WRITE, %rax
    movq    $STDOUT_FILENO, %rdi
    leaq    msg_help(%rip), %rsi
    movq    $len_help, %rdx
    syscall
    xorq    %rdi, %rdi
    movq    $SYS_EXIT, %rax
    syscall


# --- ERROR & EXIT HANDLERS ---
error_shm_missing:
    movq    $SYS_WRITE, %rax
    movq    $STDERR_FILENO, %rdi
    leaq    msg_err_shm(%rip), %rsi
    movq    $len_err_shm, %rdx
    syscall
    jmp     error_exit

error_args_exit:
    movq    $SYS_WRITE, %rax
    movq    $STDERR_FILENO, %rdi
    leaq    msg_err_args(%rip), %rsi
    movq    $len_err_args, %rdx
    syscall
    jmp     error_exit

error_connection_lost:
    movq    $SYS_WRITE, %rax
    movq    $STDERR_FILENO, %rdi
    leaq    msg_lost(%rip), %rsi
    movq    $len_lost, %rdx
    syscall

error_exit:
    movq    $SYS_EXIT, %rax
    movq    $1, %rdi
    syscall

.size _start, . - _start
.section .note.GNU-stack,"",@progbits
