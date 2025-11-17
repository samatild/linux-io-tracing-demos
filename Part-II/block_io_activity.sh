#!/usr/bin/env bash
set -euo pipefail

# --- DEMO: Block I/O Level Activity ---
# This script demonstrates detailed block I/O activity using blktrace
# Shows I/O operations at the block device level, queue depths, and timing
#
# Author: Samuel Matildes (Linux I/O Training)
# Git repo: github.com/samatild/linux-io-tracing-demos

# --- Config ---
TESTFILE="${TESTFILE:-/tmp/block_io_test.dat}"
DEVICE="auto"  # Block device to trace (usually sda, sdb, etc.)
TRACE_DURATION="${TRACE_DURATION:-10}"  # seconds to trace
WORKLOAD_DURATION="${WORKLOAD_DURATION:-8}"  # seconds for I/O workload

# --- Helpers ---
is_root() { [ "${EUID:-$(id -u)}" -eq 0 ]; }
log() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
warn(){ printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[ERR ]\033[0m %s\n' "$*"; exit 1; }

# Check for required tools
check_tools() {
    local missing_tools=()

    if ! command -v blktrace >/dev/null 2>&1; then
        missing_tools+=("blktrace")
    fi
    if ! command -v blkparse >/dev/null 2>&1; then
        missing_tools+=("blkparse")
    fi
    if ! command -v btrace >/dev/null 2>&1; then
        missing_tools+=("btrace")
    fi

    if [ ${#missing_tools[@]} -ne 0 ]; then
        err "Missing tools: ${missing_tools[*]}. Install with: apt-get install blktrace"
    fi

    # blktrace requires root
    if ! is_root; then
        err "blktrace requires root privileges. Run with: sudo $0"
    fi
}

# Find the block device for a file
find_device_for_file() {
    local file="$1"
    df "$file" | tail -1 | awk '{print $1}' | sed 's/\/dev\///'
}

# Run sequential write workload
run_sequential_writes() {
    log "Running sequential write workload..."
    log "Command: dd if=/dev/zero of=\"${TESTFILE}.seq\" bs=1M count=50 oflag=direct status=none &"
    dd if=/dev/zero of="${TESTFILE}.seq" bs=1M count=50 oflag=direct status=none &
    WORKLOAD_PID=$!
}

# Run random read/write workload
run_random_io() {
    log "Running random I/O workload..."
    log "Command: fio --name=rand_io --filename=\"${TESTFILE}.rand\" --rw=randrw --rwmixread=70 --bs=4k --size=50M --numjobs=2 --runtime=\"${WORKLOAD_DURATION}\" --direct=1 --group_reporting --output=/dev/null &"

    fio --name=rand_io \
        --filename="${TESTFILE}.rand" \
        --rw=randrw \
        --rwmixread=70 \
        --bs=4k \
        --size=50M \
        --numjobs=2 \
        --runtime="$WORKLOAD_DURATION" \
        --direct=1 \
        --group_reporting \
        --output=/dev/null &
    WORKLOAD_PID=$!
}

# Demonstrate block I/O tracing
demonstrate_blktrace() {
    local workload_type="$1"
    local workload_function="$2"

    log ""
    log "=== BLOCK I/O TRACING: $workload_type ==="

    # Determine device to trace
    if [ "$DEVICE" = "auto" ]; then
        DEVICE=$(find_device_for_file "$TESTFILE")
        log "Auto-detected device: $DEVICE"
    fi

    # Verify device exists
    if [ ! -b "/dev/$DEVICE" ]; then
        err "Block device /dev/$DEVICE not found. Available devices:"
        ls /dev/sd* /dev/nvme* 2>/dev/null || echo "No block devices found"
        exit 1
    fi

    log "Tracing block device: $DEVICE"
    log "Workload: $workload_type (${WORKLOAD_DURATION}s)"
    log "Trace duration: ${TRACE_DURATION}s"

    # Ensure output directory exists
    mkdir -p /tmp

    # Start blktrace in background
    log "Starting blktrace..."
    blktrace -d "/dev/$DEVICE" -D /tmp -o "blktrace_$workload_type" &
    BLKTRACE_PID=$!

    # Give blktrace time to start
    sleep 1

    # Run the workload
    $workload_function

    # Let workload run for specified duration
    sleep "$WORKLOAD_DURATION"

    # Stop blktrace
    log "Stopping blktrace..."
    kill $BLKTRACE_PID 2>/dev/null || true
    wait $BLKTRACE_PID 2>/dev/null || true

    # Kill workload if still running
    kill $WORKLOAD_PID 2>/dev/null || true
    wait $WORKLOAD_PID 2>/dev/null || true

    # Parse and analyze the trace
    log "Parsing blktrace data..."
    blkparse /tmp/blktrace_$workload_type.blktrace.* > "/tmp/blkparse_$workload_type.txt" 2>/dev/null || {
        echo "Warning: No blktrace output files found. This may indicate blktrace failed to start."
        echo "Check that you're running as root and the device exists."
        touch "/tmp/blkparse_$workload_type.txt"
    }

 
}


# --- Main Demo ---
check_tools

cat << 'INTRO'

=== BLOCK I/O LEVEL ACTIVITY ===

This script demonstrates block-level I/O tracing using blktrace.

INTRO

# Setup
log "Setting up test environment..."
dd if=/dev/zero of="$TESTFILE" bs=1M count=10 status=none

# Determine device if not specified
if [ "$DEVICE" = "auto" ] || [ -z "$DEVICE" ]; then
    DEVICE=$(find_device_for_file "$TESTFILE")
    log "Auto-detected device for tracing: $DEVICE"
fi

# Run demonstrations
demonstrate_blktrace "Sequential_Writes" run_sequential_writes
demonstrate_blktrace "Random_IO" run_random_io

# Cleanup
#rm -f "${TESTFILE}"* /tmp/blktrace_*.blktrace.* /tmp/blkparse_*.txt

log "Block I/O tracing complete."
log "Check the blktrace_*.blktrace.* and blkparse_*.txt files in the /tmp directory for the results."
log "Alternatively, run blkparse manually: blkparse /tmp/blktrace*"