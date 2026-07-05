#!/bin/bash
# Description: Scientific validation and stress testing.
set -e

DAEMON="./bin/release/x86_64/chaos_service"
RESULT_DIR="./results"
mkdir -p "$RESULT_DIR"

# Metadata helper
get_hw_info() {
    echo "--- TEST METADATA ---"
    echo "Hostname: $(hostname)"
    echo "CPU Model: $(grep -m 1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)"
    echo "CPU Cores: $(nproc)"
    echo "RAM: $(free -h | grep Mem | awk '{print $2}')"
    echo "---------------------"
}

echo "=== STRESS TEST SUITE ==="
read -p "Start the Daemon? (y/n): " start_daemon
if [[ "$start_daemon" == "y" ]]; then
    $DAEMON &
    DAEMON_PID=$!
    sleep 1
fi

TESTS=(
    "bin/release/x86_64/chaos_test_small:bbattery_smallcrush"
    "bin/release/x86_64/chaos_test_crush:bbattery_crush"
    "bin/release/x86_64/chaos_test_big:bbattery_bigcrush"
)

for t in "${TESTS[@]}"; do
    bin="${t%%:*}"
    name="${t##*:}"
    if [ -f "$bin" ]; then
        read -p "Run $name? (y/n): " choice
        if [[ "$choice" == "y" ]]; then
            echo "Running $name... check $RESULT_DIR/${name}.txt"
            { get_hw_info; $bin; } > "$RESULT_DIR/${name}.txt" 2>&1
        fi
    fi
done

if [ ! -z "$DAEMON_PID" ]; then
    kill $DAEMON_PID 2>/dev/null
    echo "Daemon stopped."
fi
