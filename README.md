# asm-entropy-daemon

A high-performance, bare-metal Linux Pseudo-Random Number Generator (PRNG) service written entirely in x86_64 assembly (System V ABI compliant). The system operates as a low-overhead, multi-slot IPC service utilizing shared memory (mmap) to distribute statistically complex entropy arrays to concurrent client vectors with zero reliance on standard C runtimes (libc).

The core generation architecture has been exhaustively evaluated and validated against TestU01's rigorous empirical statistical test batteries (SmallCrush, Crush, and BigCrush).

---

## Architectural Layout

  [ Client 1 ] <--- Shared Memory (MMAP) ---> [ Slot 0 ] ---> 
  
  [ Client 2 ] <--- Shared Memory (MMAP) ---> [ Slot 1 ] ---> [ asm-entropy-daemon ] --->  [ TestU01 Battery Gates ] --- (SmallCrush / Crush / BigCrush)
  
  [ Client N ] <--- Shared Memory (MMAP) ---> [ Slot N ] --->             |
                                                                    v
                                                      

* Host Service Daemon: Monitors incoming request flags via shared memory segments, manages MT19937-64 state, and delivers results with nanosecond-level latency.
* Low-Overhead Client Logic: A lightweight assembly diagnostic tool designed to bind directly to the shared memory channels, stream random 64-bit blocks, and process real-time hexadecimal output metrics.
* Statistical Validation: C integration interfaces pipeline raw generated integers into the automated TestU01 suite, logging mathematical performance across all testing profiles.

---

## The "Revolver" Architecture

The asm-entropy-daemon utilizes a "Revolver" architecture to maximize throughput and minimize latency:

* The Chambers (Slots): We allocate 64 fixed-size memory slots (64 bytes each) in shared memory. Each slot functions as an independent chamber in a revolver.
* The Bullets (Requests): Clients load a "bullet" by setting a request flag in an idle slot. 
* The Hammer (Daemon): The daemon spins through the slots in a high-speed round-robin loop. When it finds a chamber with a request, it performs an atomic swap, generates the Mersenne Twister sequence, and fires the random 64-bit result back into the slot.
* Non-Blocking Fire: By utilizing atomic memory operations, the Revolver achieves near-zero lock contention. This allows the generator to maintain consistent, nanosecond-level delivery even under extreme concurrent client load.

---

## Workspace Layout

.
├── bin/                    # Compiled native systems binaries
│   └── x86_64/
├── build/                  # Transient assembly object outputs
├── src/                    # Core System V assembly source files
│   └── x86_64/
│       ├── common/         # Shared diagnostic formatting vectors
│       ├── service/        # Core server SHM framework
│       └── client/         # Interprocess channel interfaces
├── test/                   # Regression testing & TestU01 suites
│   ├── run_tests.sh        # E2E integration verification script
│   └── stress/             # TestU01 harness files and logs
└── Makefile                # Production build definitions

---

## Setup & Build

To initialize submodules (such as TestU01), build the daemon and client binaries, and execute the automated verification test run:

# 1. Initialize and update submodules
git submodule update --init --recursive

# 2. Build the engine and test suites
make

# 3. Run automated verification test suite
./test/run_tests.sh

---

## Hardware & Performance

While the asm-entropy-daemon is designed for low-overhead operation, it is optimized for high-performance hardware. Testing confirms:
* Latency: Near-zero overhead for shared memory (mmap) slot-swapping.
* Throughput: Sustained high-frequency delivery of random bit-streams, even under heavy multi-client concurrent load.
* Stability: The core daemon consumes minimal resources, leaving processor cores available for high-throughput client computation, making it ideal for large-scale Monte Carlo simulations.

---

## License

This system is licensed under the Apache License, Version 2.0.
