#!/bin/bash
# =============================================================================
# BUILD ORCHESTRATOR
# =============================================================================
set -e

BUILD_TYPE="${1:-debug}"

echo "=== [1/3] Checking Git submodules ==="
if [ -f ".gitmodules" ]; then
    # Check if the submodule directory is empty; if so, initialize and update
    if [ ! -d "external/TestU01-2009" ] || [ -z "$(ls -A external/TestU01-2009)" ]; then
        echo "Submodules missing or empty. Initializing..."
        git submodule update --init --recursive
    else
        echo "Submodules already present."
    fi
else
    echo "Warning: No .gitmodules found. Skipping submodule check."
fi

echo "=== [2/3] Checking dependencies ==="
for tool in gcc as ld make autoconf automake; do
    if ! command -v "$tool" &> /dev/null; then
        echo "ERROR: Required tool '$tool' is not installed."
        exit 1
    fi
done
echo "All build tools are present."

echo "=== [3/3] Building binaries via Makefile ==="
make BUILD_TYPE="${BUILD_TYPE}" all

echo "Build successful! Binaries are located in build/x86_64/${BUILD_TYPE}/"

