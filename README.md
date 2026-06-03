# asm-entropy-daemon

A high-performance, bare-metal Linux Pseudo-Random Number Generator (PRNG) service written entirely in **x86_64 assembly** (System V ABI compliant). The system operates as a low-overhead, multi-slot IPC service utilizing raw Linux socket mechanics to distribute statistically complex entropy arrays to concurrent client vectors with zero reliance on standard C runtimes (`libc`).

The core generation architecture has been exhaustively evaluated and validated against **TestU01's** rigorous empirical statistical test batteries (`SmallCrush`, `Crush`, and `BigCrush`).

---

## Architectural Layout

```text
  [ Client Runtime 1 ] <--- Unix Domain Socket ---> [ Slot 0 ]
  [ Client Runtime 2 ] <--- Unix Domain Socket ---> [ Slot 1 ] ---> [ asm-entropy-daemon ]
  [ Client Runtime N ] <--- Unix Domain Socket ---> [ Slot N ]              |
                                                                            v
                                                                 [ TestU01 Battery Gates ]
                                                               (SmallCrush / Crush / BigCrush)
```

* **Host Service Daemon:** Monitors incoming Unix domain communication frames, allocates tracking state segments, and manages multi-slot execution queues using direct kernel system calls.
* **Low-Overhead Client Logic:** A lightweight assembly diagnostic tool designed to bind directly to the service socket channels, stream random 64-bit blocks, and process real-time hexadecimal output metrics.
* **Statistical Validation:** Direct C integration interfaces built to pipeline millions of raw generated integers into the automated TestU01 suite, logging mathematical performance across all testing profiles.

---

## Workspace Layout

```text
.
├── bin/                        # Compiled native systems binaries
│   └── x86_64/
│       ├── chaos_service       # Master multi-slot daemon
│       └── chaos_client        # Bare-metal diagnostic client
├── build/                      # Transient assembly object outputs
├── src/                        # Core System V assembly source files
│   └── x86_64/
│       ├── common/             # Shared diagnostic formatting vectors
│       ├── service/            # Core server socket framework
│       └── client/             # Interprocess channel interfaces
├── test/                       # Regression testing & TestU01 suites
│   ├── run_tests.sh            # E2E integration verification script
│   └── stress/                 # TestU01 harness files and logs
└── Makefile                    # Production build definitions
```

---

## Build and Automated Verification

The project includes an end-to-end testing harness that completely sweeps old object artifacts, compiles the production daemon and client binaries from source, maps sockets, and executes an automated inter-process verification cycle:

```bash
./test/run_tests.sh
```

---

## License

This system is licensed under the Apache 2.0 open-source tracking terms.
