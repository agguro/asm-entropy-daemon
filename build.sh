#!/bin/bash
# =============================================================================
# FINAL BUILD SCRIPT
# =============================================================================
set -e

# 1. Prepare environment
git submodule update --init --recursive
mkdir -p bin/release/x86_64 build/release/x86_64

# 2. Build TestU01 library (Standard build)
if [ ! -f external/TestU01-2009/libtestu01.a ]; then
    echo "[2/4] Building TestU01 library..."
    cd external/TestU01-2009
    ./configure
    make
    # Move the library files up to the submodule root for easier linking
    cp -f testu01/.libs/libtestu01.a .
    cp -f probdist/.libs/libprobdist.a .
    cp -f mylib/.libs/libmylib.a .
    cd ../..
fi

# 3. Build Core binaries
make BUILD_TYPE=release

# 4. Build Test Harnesses
echo "[4/4] Compiling TestU01 harnesses..."
CFLAGS="-O3 -march=native -I./external/TestU01-2009/include"

# Crucial: Link order matters (testu01 -> probdist -> mylib -> math)
LIBS="-ltestu01 -lprobdist -lmylib -lm"
LIB_PATH="-L./external/TestU01-2009"

gcc $CFLAGS test/stress/test_bbattery_smallcrush.c -o bin/release/x86_64/chaos_test_small $LIB_PATH $LIBS
gcc $CFLAGS test/stress/test_bbattery_crush.c      -o bin/release/x86_64/chaos_test_crush $LIB_PATH $LIBS
gcc $CFLAGS test/stress/test_bbattery_bigcrush.c    -o bin/release/x86_64/chaos_test_big $LIB_PATH $LIBS

echo "Build complete. All targets ready."
