#!/usr/bin/env bash
set -euo pipefail

# --- DEMO: Synchronous vs Asynchronous I/O ---
# This script demonstrates the performance differences between synchronous and asynchronous I/O
# using fio (Flexible I/O tester) with system monitoring
#
# Author: Samuel Matildes (Linux I/O Training)
# Git repo: github.com/samatild/linux-io-tracing-demos

# --- Config ---
TESTFILE_SYNC="${TESTFILE_SYNC:-/tmp/sync_test.dat}"
TESTFILE_ASYNC="${TESTFILE_ASYNC:-/tmp/async_test.dat}"
RUNTIME="${RUNTIME:-30}"      # seconds for each fio test
BLOCK_SIZE="${BLOCK_SIZE:-4k}"
NUM_JOBS="${NUM_JOBS:-1}"
IO_DEPTH="${IO_DEPTH:-32}"    # queue depth for async I/O

# --- Helpers ---
is_root() { [ "${EUID:-$(id -u)}" -eq 0 ]; }
log() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
warn(){ printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[ERR ]\033[0m %s\n' "$*"; exit 1; }

# Check for required tools
check_tools() {
    local missing_tools=()

    if ! command -v fio >/dev/null 2>&1; then
        missing_tools+=("fio")
    fi
    if ! command -v vmstat >/dev/null 2>&1; then
        missing_tools+=("procps")  # vmstat package
    fi

    if [ ${#missing_tools[@]} -ne 0 ]; then
        err "Missing tools: ${missing_tools[*]}. Install with: apt-get install ${missing_tools[*]}"
    fi
}

# Create test files
create_test_files() {
    log "Creating test files..."
    # Pre-allocate files to avoid allocation overhead during tests
    dd if=/dev/zero of="${TESTFILE_SYNC}" bs=1M count=100 status=none
    dd if=/dev/zero of="${TESTFILE_ASYNC}" bs=1M count=100 status=none
    log "Test files created (${TESTFILE_SYNC}, ${TESTFILE_ASYNC})"
}

# Run synchronous I/O test
run_sync_test() {
    log ""
    log "=== SYNCHRONOUS I/O TEST ==="
    log "Running fio with synchronous I/O (sync=1)..."
    log "Characteristics: Each write waits for completion before next write"

    # Start system monitoring in background
    vmstat 1 ${RUNTIME} > /tmp/vmstat_sync.log 2>&1 &
    VMSTAT_PID=$!

    log "fio command: fio --name=sync_test --filename=${TESTFILE_SYNC} --rw=randwrite --bs=${BLOCK_SIZE} --numjobs=${NUM_JOBS} --runtime=${RUNTIME} --ioengine=sync --sync=1 --direct=1 --group_reporting --output=/tmp/fio_sync_results.txt"
    # Run fio with synchronous I/O
    fio --name=sync_test \
        --filename="${TESTFILE_SYNC}" \
        --rw=randwrite \
        --bs="${BLOCK_SIZE}" \
        --numjobs="${NUM_JOBS}" \
        --runtime="${RUNTIME}" \
        --ioengine=sync \
        --sync=1 \
        --direct=1 \
        --group_reporting \
        --output=/tmp/fio_sync_results.txt

    # Wait for vmstat to finish
    wait $VMSTAT_PID 2>/dev/null || true

    log "Sync I/O results:"
    if [ -f /tmp/fio_sync_results.txt ]; then
        cat /tmp/fio_sync_results.txt | grep -A 20 "WRITE:" || echo "No WRITE section found"
    else
        echo "Results file not found"
    fi

    log "Sync I/O system stats (last 5 seconds):"
    tail -10 /tmp/vmstat_sync.log | head -5
}

# Run asynchronous I/O test
run_async_test() {
    log ""
    log "=== ASYNCHRONOUS I/O TEST ==="
    log "Running fio with asynchronous I/O (libaio, iodepth=${IO_DEPTH})..."
    log "Characteristics: Multiple write operations in flight simultaneously"

    # Start system monitoring in background
    vmstat 1 ${RUNTIME} > /tmp/vmstat_async.log 2>&1 &
    VMSTAT_PID=$!
    log "fio command: fio --name=async_test --filename=${TESTFILE_ASYNC} --rw=randwrite --bs=${BLOCK_SIZE} --numjobs=${NUM_JOBS} --runtime=${RUNTIME} --ioengine=libaio --iodepth=${IO_DEPTH} --direct=1 --group_reporting --output=/tmp/fio_async_results.txt"
    # Run fio with asynchronous I/O
    fio --name=async_test \
        --filename="${TESTFILE_ASYNC}" \
        --rw=randwrite \
        --bs="${BLOCK_SIZE}" \
        --numjobs="${NUM_JOBS}" \
        --runtime="${RUNTIME}" \
        --ioengine=libaio \
        --iodepth="${IO_DEPTH}" \
        --direct=1 \
        --group_reporting \
        --output=/tmp/fio_async_results.txt

    # Wait for vmstat to finish
    wait $VMSTAT_PID 2>/dev/null || true

    log "Async I/O results:"
    if [ -f /tmp/fio_async_results.txt ]; then
        cat /tmp/fio_async_results.txt | grep -A 20 "WRITE:" || echo "No WRITE section found"
    else
        echo "Results file not found"
    fi

    log "Async I/O system stats (last 5 seconds):"
    tail -10 /tmp/vmstat_async.log | head -5
}

# Compare results
compare_results() {
    log ""
    log "=== PERFORMANCE COMPARISON ==="

    # Extract key metrics from fio results
    echo "=== FIO PERFORMANCE RESULTS ==="
    echo "Synchronous I/O:"
    if [ -f /tmp/fio_sync_results.txt ]; then
        cat /tmp/fio_sync_results.txt
    else
        echo "Sync results file not found"
    fi

    echo ""
    echo "Asynchronous I/O:"
    if [ -f /tmp/fio_async_results.txt ]; then
        cat /tmp/fio_async_results.txt
    else
        echo "Async results file not found"
    fi

}

# --- Main Demo ---
check_tools

cat << 'INTRO'

=== SYNCHRONOUS vs ASYNCHRONOUS I/O DEMONSTRATION ===

This script compares synchronous and asynchronous I/O write performance using fio.

SYNCHRONOUS I/O:
- Each write operation waits for completion before starting the next
- Process blocks until write completes and data is durable
- Simple but can be inefficient for high-throughput workloads

ASYNCHRONOUS I/O:
- Multiple write operations can be in flight simultaneously
- Process continues execution while writes complete in background
- More complex but enables higher throughput and efficiency

INTRO

# Setup
create_test_files

# Run tests
run_sync_test
run_async_test

# Compare and analyze
compare_results

# --- Cleanup ---
log ""
log "=== Cleanup ==="
rm -f "${TESTFILE_SYNC}" "${TESTFILE_ASYNC}"
rm -f /tmp/fio_sync_results.txt /tmp/fio_async_results.txt
rm -f /tmp/vmstat_sync.log /tmp/vmstat_async.log

log "Demo complete. Key takeaway:"
echo "  • Asynchronous I/O enables higher throughput and efficiency"
echo "  • Synchronous I/O is simpler but blocks processes"
echo "  • Choose based on application requirements and performance needs"
