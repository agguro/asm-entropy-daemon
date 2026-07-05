#!/bin/bash
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
# Description:
#   Launches the Chaos Engine daemon, verifies the IPC pipeline with a client,
#   and handles process cleanup.
# =============================================================================

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

# Allow the background shared-memory state to bind cleanly
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
