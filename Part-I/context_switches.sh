#!/usr/bin/env bash
set -euo pipefail

# --- DEMO: Context Switches - Cache Hits vs Misses ---
# This script demonstrates context switches during cache hits (voluntary) vs cache misses (involuntary)
# and compares voluntary vs involuntary context switching patterns
#
# Author: Samuel Matildes (Linux I/O Training)
# Git repo: github.com/samatild/linux-io-tracing-demos

# --- Config ---
TESTFILE_PREFIX="${TESTFILE_PREFIX:-/tmp/cs_test}"
NUM_PROCESSES="${NUM_PROCESSES:-6}"
BLOCK_SIZE="${BLOCK_SIZE:-4k}"
BLOCK_COUNT="${BLOCK_COUNT:-10000}"
MONITOR_DURATION="${MONITOR_DURATION:-15}"

# --- Helpers ---
is_root() { [ "${EUID:-$(id -u)}" -eq 0 ]; }
log() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
warn(){ printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[ERR ]\033[0m %s\n' "$*"; exit 1; }

# Check for required tools
check_tools() {
    local missing_tools=()

    if ! command -v perf >/dev/null 2>&1; then
        missing_tools+=("perf")
    fi
    if ! command -v vmstat >/dev/null 2>&1; then
        missing_tools+=("procps")  # vmstat package
    fi
    if ! command -v pidstat >/dev/null 2>&1; then
        missing_tools+=("sysstat")  # pidstat package
    fi

    if [ ${#missing_tools[@]} -ne 0 ]; then
        err "Missing tools: ${missing_tools[*]}. Install with: apt-get install ${missing_tools[*]}"
    fi
}

# Get process context switch info
get_proc_cs() {
    local pid=$1
    if [ -f "/proc/$pid/status" ]; then
        grep -E "voluntary_context_switches|nonvoluntary_context_switches" "/proc/$pid/status" 2>/dev/null || echo "N/A"
    else
        echo "Process $pid not found"
    fi
}

# --- Main Demo ---
check_tools

cat << 'INTRO'

=== CONTEXT SWITCHES DEMONSTRATION ===

This script demonstrates context switches during:

1. Cache Misses: Disk I/O causing context switches
2. Cache Hits: Memory operations with lower context switching


INTRO

# --- 1) Cache Misses - Disk I/O ---
log ""
log "=== PART 1: Cache Misses (Disk I/O) ==="
log "Creating multiple synchronous I/O processes to force context switches..."

# Clean up any existing test files
rm -f "${TESTFILE_PREFIX}"*.bin

# Start multiple dd processes with dsync (direct synchronous I/O)
log "Starting $NUM_PROCESSES dd processes with dsync..."
for i in $(seq 1 "$NUM_PROCESSES"); do
    dd if=/dev/zero of="${TESTFILE_PREFIX}_${i}.bin" bs="$BLOCK_SIZE" count="$BLOCK_COUNT" oflag=dsync >/dev/null 2>&1 &
    IO_PIDS[$i]=$!
    log "Started dd process $i (PID: ${IO_PIDS[$i]})"
done

# Wait a moment for processes to start
sleep 2

# Monitor system-wide context switches
log "Monitoring system context switches with vmstat..."
vmstat 1 "$MONITOR_DURATION" &
VMSTAT_PID=$!

# Start perf recording for system-wide context switches
log "Recording system-wide performance data with perf..."
perf record -a -e context-switches -o perf_cache_misses.data -- sleep "$MONITOR_DURATION" &
PERF_PID=$!

# Wait for vmstat and perf to finish
wait $VMSTAT_PID 2>/dev/null || true
wait $PERF_PID 2>/dev/null || true

# Kill dd processes
for pid in "${IO_PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
done

cat << 'CACHE_MISS_ANALYSIS'

Look for in vmstat:
- High 'cs' (context switches) column

Perf recording available: perf_cache_misses.data
Analyze with: perf report -i perf_cache_misses.data

CACHE_MISS_ANALYSIS


read -r -p "Press Enter to continue..."

# --- 2) Cache Hits - Memory Operations ---
log ""
log "=== PART 2: Cache Hits (Memory Operations) ==="
log "Running CPU-bound processes that stay in memory..."

# Start multiple CPU-bound processes that run for the monitoring duration
for i in $(seq 1 "$NUM_PROCESSES"); do
    (
        # CPU-bound work with memory access (cache hits) - run for monitoring duration
        end_time=$((SECONDS + MONITOR_DURATION + 5))  # Run a bit longer than monitoring
        while [ $SECONDS -lt $end_time ]; do
            # Memory operations that should hit cache
            for j in {1..1000}; do
                result=$((j * j * i))  # Vary by process ID to avoid cache sharing
                data="test_data_${result}_process_${i}"
            done
        done
    ) &
    CPU_PIDS[$i]=$!
    log "Started CPU process $i (PID: ${CPU_PIDS[$i]})"
done

sleep 2

# Monitor system context switches during CPU work
log "Monitoring system context switches during CPU work..."
vmstat 1 "$MONITOR_DURATION" &
VMSTAT_PID=$!

# Start perf recording for system-wide context switches during CPU work
log "Recording system-wide performance data during CPU work with perf..."
perf record -a -e context-switches -o perf_cache_hits.data -- sleep "$MONITOR_DURATION" &
PERF_CPU_PID=$!

wait $VMSTAT_PID 2>/dev/null || true
wait $PERF_CPU_PID 2>/dev/null || true

# Kill CPU processes
for pid in "${CPU_PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
done

cat << 'CACHE_HIT_ANALYSIS'

Look for in vmstat:
- Lower 'cs' values compared to I/O workload

Perf recording available: perf_cache_hits.data
Analyze with: perf report -i perf_cache_hits.data

CACHE_HIT_ANALYSIS

# --- Cleanup ---
log ""
log "=== Cleanup ==="
rm -f "${TESTFILE_PREFIX}"*.bin 

log "Demo complete."