===============================================================================
                  TestU01: Testing Random Number Generators
              (Modernized Native Build & Linux-Only Distribution)
===============================================================================

TestU01 is a comprehensive software library implemented in ANSI C designed to
perform empirical statistical testing on arbitrary Pseudorandom Number Generators
(PRNG) and Hardware Random Number Generators (TRNG / Entropy sources).

Original Author & Copyright:
    Pierre L'Ecuyer & Richard Simard
    Université de Montréal
    http://www.iro.umontreal.ca/~lecuyer/

Repository Maintainer & Modernization:
    Roberto Aguas Guerreiro (agguro)
    https://github.com/agguro/TestU01-2009

-------------------------------------------------------------------------------
MODERNIZATION & CLEANUP (Linux-Only Native Build)
-------------------------------------------------------------------------------

The legacy GNU Autotools build system and all obsolete Windows/Win32/MSVC 
artifacts have been completely removed in favor of a lean, deterministic Linux 
development tree.

Key modifications:
  * Pure Linux / POSIX: Removed all Windows/MSYS/MinGW legacy wrappers, 
    32-bit Win32 shims, and batch files.
  * Native Build: Zero dependencies on autoconf, automake, libtool, or autoheader.
  * Static Archiving: Generates static libraries directly into build/libs/.
  * Multi-Arch Ready: Compiled with -fPIC by default for x86_64, AArch64, 
    and RISC-V targets.
  * Complete Header Tree: All module headers (*.h) are fully vendored in 
    include/, eliminating LaTeX/tcode preprocessing requirements.
  * Modern Toolchains: Builds cleanly under modern GCC (>= 8.0) and Clang.

-------------------------------------------------------------------------------
PLATFORM SUPPORT & REQUIREMENTS
-------------------------------------------------------------------------------

Target Environment: GNU/Linux (POSIX x86_64, AArch64, RISC-V)

Requirements:
  - Linux Kernel >= 3.x / glibc
  - GCC or Clang
  - GNU Make, ar, ranlib

(Note: Windows users must build inside WSL2 or a Linux container)

-------------------------------------------------------------------------------
DIRECTORY STRUCTURE
-------------------------------------------------------------------------------

  -- testu01/   : Core statistical test batteries (SmallCrush, Crush, BigCrush),
                  generator interfaces, and family testing harnesses.
  -- probdist/  : Continuous and discrete probability distributions, goodness-of-fit,
                  and statistical computation tools.
  -- mylib/     : Low-level mathematical routines, bitset operations, POSIX timing,
                  string manipulation, and memory management.
  -- include/   : Consolidated C header files required for all modules.
  -- examples/  : Sample programs demonstrating battery execution and generator tests.
  -- param/     : Parameter files for predefined generator families.
  -- doc/       : PDF user guides and technical references.
  -- build/     : Output directory containing compiled static archives (build/libs/).

-------------------------------------------------------------------------------
BUILDING THE LIBRARIES
-------------------------------------------------------------------------------

To compile all modules and build the static archives in parallel:

    make -j$(nproc)

This produces the following archives in build/libs/:
  - build/libs/libmylib.a
  - build/libs/libprobdist.a
  - build/libs/libtestu01.a

To clean all build artifacts:

    make clean

-------------------------------------------------------------------------------
LINKING & USAGE IN EXTERNAL PROJECTS
-------------------------------------------------------------------------------

1. Direct Compiler Invocation:

    gcc -O3 main.c -o entropy_test \
        -I/path/to/TestU01-2009/include \
        -I/path/to/TestU01-2009/mylib \
        -I/path/to/TestU01-2009/probdist \
        -I/path/to/TestU01-2009/testu01 \
        -L/path/to/TestU01-2009/build/libs \
        -ltestu01 -lprobdist -lmylib -lm

2. Integration in Parent Makefiles (e.g. asm-entropy-daemon):

    TESTU01_DIR = external/TestU01-2009
    INCLUDES    += -I$(TESTU01_DIR)/include \
                   -I$(TESTU01_DIR)/mylib \
                   -I$(TESTU01_DIR)/probdist \
                   -I$(TESTU01_DIR)/testu01
    LIBS        += $(TESTU01_DIR)/build/libs/libtestu01.a \
                   $(TESTU01_DIR)/build/libs/libprobdist.a \
                   $(TESTU01_DIR)/build/libs/libmylib.a -lm

-------------------------------------------------------------------------------
QUICK EXAMPLE (Running SmallCrush on custom PRNG)
-------------------------------------------------------------------------------

#include "unif01.h"
#include "bbattery.h"
#include <stdint.h>

static uint32_t state = 0x12345678;

static unsigned int xorshift32(void) {
    uint32_t x = state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    state = x;
    return x;
}

int main(void) {
    unif01_Gen *gen = unif01_CreateExternGenBits("Xorshift32", xorshift32);
    bbattery_SmallCrush(gen);
    unif01_DeleteExternGenBits(gen);
    return 0;
}

-------------------------------------------------------------------------------
DOCUMENTATION
-------------------------------------------------------------------------------

PDF documentation is located in the doc/ directory:
  - doc/guideshorttestu01.pdf : Quick-start guide for standard battery testing.
  - doc/guidelongtestu01.pdf  : Full technical documentation.
===============================================================================
