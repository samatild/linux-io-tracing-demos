#!/usr/bin/env bash
set -euo pipefail

# --- DEMO: Hyper-V StorVSC Kernel Module Activity ---
# This script demonstrates Hyper-V storage VSC (hv_storvsc) kernel module activity
# Shows I/O operations through the Hyper-V virtual storage driver
#
# Author: Samuel Matildes (Linux I/O Training)
# Git repo: github.com/samatild/linux-io-tracing-demos

# --- Config ---
TESTFILE="${TESTFILE:-/tmp/hv_test.dat}"
WORKLOAD_DURATION="${WORKLOAD_DURATION:-10}"

# --- Helpers ---
is_root() { [ "${EUID:-$(id -u)}" -eq 0 ]; }
log() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
warn(){ printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[ERR ]\033[0m %s\n' "$*"; exit 1; }
press_key_continue() {
    printf '\033[1;33m[PAUSE]\033[0m Press Enter to continue...'
    read -r
}

# Check for required tools
check_tools() {
    local missing_tools=()

    if ! command -v perf >/dev/null 2>&1; then
        missing_tools+=("perf")
    fi

    if [ ${#missing_tools[@]} -ne 0 ]; then
        err "Missing tools: ${missing_tools[*]}. Install with: apt-get install linux-perf"
    fi

    # Check if hv_storvsc module is loaded
    if ! lsmod | grep -q hv_storvsc; then
        err "hv_storvsc module not loaded. This script is for Hyper-V environments."
    fi

    # Root required for perf kernel tracing
    if ! is_root; then
        err "Root privileges required for kernel tracing"
    fi
}

# Show hv_storvsc module information
show_module_info() {
    log "Hyper-V StorVSC Module Information:"
    echo "=== LSMOD OUTPUT ==="
    lsmod | grep hv_storvsc
    echo ""

    echo "=== MODULE PARAMETERS ==="
    if [ -d /sys/module/hv_storvsc ]; then
        find /sys/module/hv_storvsc -name "parameters" -type d -exec find {} -type f \; | while read param; do
            echo -n "$(basename $param): "
            cat "$param" 2>/dev/null || echo "N/A"
        done
    fi
    echo ""

    echo "=== DRIVER INFO ==="
    modinfo hv_storvsc 2>/dev/null | head -10
}

# Add perf probes to hv_storvsc functions
setup_perf_probes() {
    log "Setting up perf probes for hv_storvsc functions..."

    # Remove existing probes if any
    perf probe -d probe:storvsc_queuecommand 2>/dev/null || true
    perf probe -d probe:storvsc_execute_vstor_op 2>/dev/null || true
    perf probe -d probe:handle_sc_creation 2>/dev/null || true
    perf probe -d probe:storvsc_device_configure 2>/dev/null || true

    # Add probes to key hv_storvsc functions with arguments
    # scmnd parameter captures SCSI command details (allows read/write differentiation)
    perf probe -m hv_storvsc 'storvsc_queuecommand scmnd=%di' 2>/dev/null || warn "Could not probe storvsc_queuecommand"
    perf probe -m hv_storvsc storvsc_execute_vstor_op 2>/dev/null || warn "Could not probe storvsc_execute_vstor_op"
    perf probe -m hv_storvsc handle_sc_creation 2>/dev/null || warn "Could not probe handle_sc_creation"

    echo "=== PERF PROBES INSTALLED ==="
    perf probe -l | grep storvsc || echo "No hv_storvsc probes found"
}

# Monitor hv_storvsc activity
monitor_hv_activity() {
    log ""
    log "=== MONITORING HV_STORVSC ACTIVITY ==="

    # Start perf recording with hv_storvsc probes
    log "Starting perf recording of hv_storvsc functions..."
    log "Command: perf record -e probe:storvsc_queuecommand -e probe:storvsc_execute_vstor_op -e probe:handle_sc_creation -a -o "hv_storvsc.perf" -- sleep "$WORKLOAD_DURATION""
    perf record -e probe:storvsc_queuecommand -e probe:storvsc_execute_vstor_op -e probe:handle_sc_creation -a -o "hv_storvsc.perf" -- sleep "$WORKLOAD_DURATION" &
    PERF_PID=$!

    # Give perf time to start
    sleep 1

    # Run workload
    log "Running sequential I/O workload..."
    log "Command: dd if=/dev/zero of="${TESTFILE}.seq" bs=1M count=20 oflag=direct status=none"
    dd if=/dev/zero of="${TESTFILE}.seq" bs=1M count=20 oflag=direct status=none

    # Wait for perf to finish
    wait $PERF_PID 2>/dev/null || true

    # Show perf results
    perf report -i "hv_storvsc.perf" --stdio | head -20
}

# Monitor hv_storvsc activity using ftrace function tracing
monitor_hv_activity_ftrace() {
    log ""
    log "=== MONITORING HV_STORVSC ACTIVITY WITH FTRACE ==="

    # Setup ftrace function tracing
    log "Setting up ftrace function tracing..."
    echo 0 > /sys/kernel/tracing/tracing_on
    echo > /sys/kernel/tracing/trace

    # Set function tracer and filter to storvsc functions
    echo function > /sys/kernel/tracing/current_tracer
    echo "storvsc*" > /sys/kernel/tracing/set_ftrace_filter

    # Start tracing
    echo 1 > /sys/kernel/tracing/tracing_on

    # Run workload
    log "Running sequential I/O workload with ftrace..."
    log "Command: dd if=/dev/zero of="${TESTFILE}.ftrace" bs=1M count=20 oflag=direct status=none"
    dd if=/dev/zero of="${TESTFILE}.ftrace" bs=1M count=20 oflag=direct status=none

    # Stop tracing
    echo 0 > /sys/kernel/tracing/tracing_on

    # Show trace results
    log "hv_storvsc function calls via ftrace:"
    grep storvsc /sys/kernel/tracing/trace | head -20 || echo "No storvsc traces found"

    # Cleanup - restore default tracing (make sure this doesn't fail)
    if [ -w /sys/kernel/tracing/current_tracer ]; then
        echo nop > /sys/kernel/tracing/current_tracer || true
    fi
    if [ -w /sys/kernel/tracing/set_ftrace_filter ]; then
        echo > /sys/kernel/tracing/set_ftrace_filter || true
    fi
    if [ -w /sys/kernel/tracing/tracing_on ]; then
        echo 0 > /sys/kernel/tracing/tracing_on || true
    fi
}

# --- Main Demo ---
check_tools

cat << 'INTRO'

=== HYPER-V STORVSC KERNEL MODULE ACTIVITY ===

This script demonstrates activity in the hv_storvsc kernel module

Tests
- Test 1: perf probes (selective function tracing with arguments)
- Test 2: ftrace function tracer (comprehensive function call tracing)

INTRO

# Setup
log "Setting up test environment..."
dd if=/dev/zero of="$TESTFILE" bs=1M count=5 status=none

# Show module information
show_module_info

press_key_continue

# Setup perf probes
setup_perf_probes

# Monitor activity with perf probes
monitor_hv_activity

# Pause before second test
log ""
press_key_continue

# Monitor activity with ftrace
monitor_hv_activity_ftrace

# Cleanup
log ""
log "=== CLEANUP ==="
perf probe -d probe:storvsc_queuecommand 2>/dev/null || true
perf probe -d probe:storvsc_execute_vstor_op 2>/dev/null || true
perf probe -d probe:handle_sc_creation 2>/dev/null || true
perf probe -d probe:storvsc_device_configure 2>/dev/null || true
rm -f "${TESTFILE}"* hv_storvsc_*.perf

log "hv_storvsc monitoring complete."
