# =============================================================================
# Project:     asm-entropy-daemon
# File:        chaos_logger.s
# Author:      agguro
# Date:        August 21, 2026 
# Description: High-throughput logger with a watchdog child process checking 
#              if the Chaos Engine is actively ticking before committing.
# =============================================================================

.equ SYS_READ,      0
.equ SYS_WRITE,     1
.equ SYS_OPEN,      2
.equ SYS_MMAP,      9
.equ SYS_EXIT,      60

.equ STDOUT_FILENO, 1

.section .data
    shm_path:       .asciz "/dev/shm/chaos_shm"
    output_path:    .asciz "/tmp/chaos_buffer.bin"

    msg_connecting: .ascii "[*] Connecting to Chaos Service...\n"
    len_conn = .-msg_connecting

    msg_connected:  .ascii "[+] Connected to Chaos Engine. Checking listener activity...\n"
    len_conn_ok = .-msg_connected

    msg_err_shm:    .ascii "[-] ERROR: Chaos Service not running or shm missing!\n"
    len_err_shm = .-msg_err_shm

    msg_abort:      .ascii "\n[-] WATCHDOG: No listener or engine activity detected. Shutting down gracefully.\n"
    len_abort = .-msg_abort

.section .text
.globl _start

_start:
    # 1. Startmelding
    movq $SYS_WRITE, %rax
    movq $STDOUT_FILENO, %rdi
    movq $msg_connecting, %rsi
    movq $len_conn, %rdx
    syscall

    # Open SHM
    movq $SYS_OPEN, %rax
    leaq shm_path(%rip), %rdi
    movq $2, %rsi                   # O_RDWR
    syscall
    testq %rax, %rax
    js error_shm_missing
    movq %rax, %r8                  # FD van SHM

    movq $SYS_WRITE, %rax
    movq $STDOUT_FILENO, %rdi
    movq $msg_connected, %rsi
    movq $len_conn_ok, %rdx
    syscall

    # Map SHM (4096 bytes)
    movq $SYS_MMAP, %rax
    xorq %rdi, %rdi
    movq $4096, %rsi
    movq $3, %rdx                   # PROT_READ | PROT_WRITE
    movq $1, %r10                   # MAP_SHARED
    movq %r8, %r8
    xorq %r9, %r9
    syscall
    testq %rax, %rax
    js error_exit
    movq %rax, %r12                 # %r12 = SHM Base Pointer

    # 2. De "Kind-Proces" / Watchdog Opstartcheck (10x heartbeat check)
    # We controleren of de heartbeat op offset 4088 effectief oploopt.
    movq $10, %rcx                  # Check 10 keer
    movq 4088(%r12), %r14           # Huidige heartbeat ophalen

.watchdog_startup_loop:
    movq 4088(%r12), %rax
    cmpq %r14, %rax
    jne .heartbeat_verified         # Als hij verandert, leeft de service!
    
    # Korte pauze / lus om de service tijd te geven te tikken
    xorq %rdx, %rdx
    movq $1000000, %rdx             # Kleine wacht-iteratie
.wait_ticking:
    decq %rdx
    jnz .wait_ticking

    decq %rcx
    jnz .watchdog_startup_loop

    # Als we hier komen, is de heartbeat 10 keer exact gelijk gebleven (geen activiteit)
    jmp watchdog_abort

.heartbeat_verified:
    # Open/Maak Output Buffer in /tmp
    movq $SYS_OPEN, %rax
    leaq output_path(%rip), %rdi
    movq $66, %rsi                  # O_RDWR | O_CREAT
    movq $0666, %rdx
    syscall
    testq %rax, %rax
    js error_exit
    movq %rax, %r9                  # FD van Buffer

    # Forceer grootte naar 8000 bytes
    movq $77, %rax                  # sys_ftruncate
    movq %r9, %rdi
    movq $8000, %rsi                
    syscall

    # Map buffer file
    movq $SYS_MMAP, %rax
    xorq %rdi, %rdi
    movq $8000, %rsi
    movq $3, %rdx
    movq $1, %r10                   # MAP_SHARED
    movq %r9, %r8
    xorq %r9, %r9
    syscall
    testq %rax, %rax
    js error_exit
    movq %rax, %r13                 # %r13 = Buffer Base Pointer

    # Initialisatie voor de hoofdloop
    movq 4088(%r12), %r14           # Start heartbeat referentie
    xorq %r15, %r15                 # Schrijf-index (0-999)
    xorq %rcx, %rcx                 # Stagnatie teller

.main_loop:
    # --- Doorlopende Watchdog Check ---
    movq 4088(%r12), %rax
    cmpq %r14, %rax
    jne .service_is_alive
    
    incq %rcx
    cmpq $5000000, %rcx             # Timeout tijdens runtime
    ja watchdog_abort
    jmp .find_slot

.service_is_alive:
    movq %rax, %r14                 # Update heartbeat
    xorq %rcx, %rcx                 # Reset stagnatie

.find_slot:
    xorq %rbx, %rbx                 # Scan slots 0-63
.scan_loop:
    movq %rbx, %rax
    shlq $6, %rax                   # Index * 64 bytes
    leaq (%r12, %rax), %rdi         # Vlag adres

    # Claim slot atomically (-1 -> 0)
    movq $-1, %rax
    movq $0, %rdx
    lock cmpxchgq %rdx, (%rdi)
    jz .wait_for_service

    incq %rbx
    andq $63, %rbx
    pause
    testq $63, %rbx
    jz .main_loop
    jmp .scan_loop

.wait_for_service:
    pause
    cmpq $-1, (%rdi)
    jne .wait_for_service

    # Pak resultaat (+8) en schrijf naar cirkelbuffer
    movq 8(%rdi), %rax
    movq %rax, (%r13, %r15, 8)

    incq %r15
    cmpq $1000, %r15
    jne .main_loop
    xorq %r15, %r15                 
    jmp .main_loop

error_shm_missing:
    movq $SYS_WRITE, %rax
    movq $STDOUT_FILENO, %rdi
    movq $msg_err_shm, %rsi
    movq $len_err_shm, %rdx
    syscall
    jmp error_exit

watchdog_abort:
    # Kind roept naar papa: "Niemand luistert of de service slaapt!"
    movq $SYS_WRITE, %rax
    movq $STDOUT_FILENO, %rdi
    movq $msg_abort, %rsi
    movq $len_abort, %rdx
    syscall

error_exit:
    movq $SYS_EXIT, %rax
    xorq %rdi, %rdi                 # Gracious exit (code 0 of 1 afhankelijk van keuze, hier netjes 0 bij abort)
    syscall

.size _start, . - _start
.section .note.GNU-stack,"",@progbits
