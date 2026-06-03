#!/bin/bash
set -e

echo "============================================================"
echo "LAUNCHING SYSTEM DAEMON INTEGRATION SWEEP"
echo "============================================================"

# Trigger pristine compilation
make clean
make

echo -e "\n[STEP 1/2] Initializing Chaos PRNG Engine Daemon in background..."
./bin/x86_64/chaos_service &
DAEMON_PID=$!

# Allow the background system socket/shared-memory state to bind cleanly
sleep 0.5

echo -e "\n[STEP 2/2] Firing high-speed assembly client interrogation vector..."
if ./bin/x86_64/chaos_client; then
    echo -e "\n>>> SUCCESS: IPC pipeline, slots mapping, and entropy collection verified."
    kill $DAEMON_PID 2>/dev/null || true
    exit 0
else
    echo -e "\n>>> FAILURE: Inter-process state connection split or drop caught."
    kill $DAEMON_PID 2>/dev/null || true
    exit 1
fi
