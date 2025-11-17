#!/usr/bin/env bash
set -euo pipefail

# --- DEMO: System Call Interface → VFS → Block Layer Queueing/Completion ---
# This script demonstrates the I/O path from system calls through VFS to block device queueing
#
# Author: Samuel Matildes (Linux I/O Training)
# Git repo: github.com/samatild/linux-io-tracing-demos

# --- Config ---
TESTFILE="${TESTFILE:-/tmp/testfile}"
READ_SIZE="${READ_SIZE:-1M}"
READ_COUNT="${READ_COUNT:-10}"
WRITE_SIZE="${WRITE_SIZE:-1M}"
WRITE_COUNT="${WRITE_COUNT:-1}"
STRACE_OUT="${STRACE_OUT:-/tmp/strace_output.txt}"

# --- Helpers ---
is_root() { [ "${EUID:-$(id -u)}" -eq 0 ]; }
log() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
warn(){ printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[ERR ]\033[0m %s\n' "$*" ; exit 1; }

# --- 0) Prepare test file ---
log "Preparing test file with direct I/O (${READ_SIZE}x${READ_COUNT} = $((${READ_COUNT})) MiB)..."
log "Command: sudo dd if=/dev/zero of="${TESTFILE}" bs="${READ_SIZE}" count="${READ_COUNT}" oflag=direct status=none && sync"
sudo dd if=/dev/zero of="${TESTFILE}" bs="${READ_SIZE}" count="${READ_COUNT}" oflag=direct status=none && sync

# --- 1) System Call → VFS Path (Read Operation) ---
log "=== PART 1: System Call → VFS Path (Read Operation) ==="
log "Tracing system calls for read operation..."
# Drop caches to ensure block I/O happens
log "Dropping page cache to ensure block I/O..."
echo 3 > /proc/sys/vm/drop_caches
log "Command: sudo strace -ttT -f -e trace=open,openat,read,close -o "${STRACE_OUT}" dd if="${TESTFILE}" of=/dev/null bs="${READ_SIZE}" count="${READ_COUNT}" status=none"
sudo strace -ttT -f -e trace=open,openat,read,close \
  -o "${STRACE_OUT}" \
  dd if="${TESTFILE}" of=/dev/null bs="${READ_SIZE}" count="${READ_COUNT}" status=none

log "System call trace (read):"
grep -E "openat|read|close" "${STRACE_OUT}" | grep -v "ld.so.cache\|libc.so.6\|locale"  || true

cat << 'READ_NOTES'

=== READ OPERATION ANALYSIS ===
- openat(): System call opens the file, triggers VFS path
- read(): User requests data, goes through VFS → filesystem → block layer
- close(): Releases file descriptor

Key Point: Each read() syscall triggers the full VFS→block layer path
READ_NOTES

# --- 2) System Call → VFS Path (Write Operation) ---
log ""
log "=== PART 2: System Call → VFS Path (Write Operation) ==="
log "Tracing system calls for write operation..."
log "Command: sudo strace -ttT -f -e trace=open,openat,write,fdatasync,close -o "${STRACE_OUT}.write" dd if=/dev/zero of="${TESTFILE}.write" bs="${WRITE_SIZE}" count="${WRITE_COUNT}" conv=fsync status=none"
sudo strace -ttT -f -e trace=open,openat,write,fdatasync,close \
  -o "${STRACE_OUT}.write" \
  dd if=/dev/zero of="${TESTFILE}.write" bs="${WRITE_SIZE}" count="${WRITE_COUNT}" conv=fsync status=none

log "System call trace (write):"
grep -E "openat|write|fdatasync|close" "${STRACE_OUT}.write" | grep -v "ld.so.cache\|libc.so.6\|locale" || true

cat << 'WRITE_NOTES'

=== WRITE OPERATION ANALYSIS ===
- openat(): Opens file for writing
- write(): Data written to page cache first
- fdatasync(): Forces pending writes to disk (sync on completion)

Key Point: conv=fsync ensures synchronous writes with cache flushing
WRITE_NOTES

# --- 3) Block Layer Queueing & Completion ---
if ! command -v trace-cmd >/dev/null 2>&1; then
  warn "trace-cmd not installed. Install with: apt-get install trace-cmd"
  exit 0
fi

log ""
log "=== PART 3: Block Layer Queueing & Completion ==="

# Prepare fresh test data
log "Preparing fresh test data..."
sudo dd if=/dev/zero of="${TESTFILE}.block" bs=1M count=10 oflag=direct status=none && sync
sudo sh -c 'sync; echo 3 > /proc/sys/vm/drop_caches'
log "Command: sudo trace-cmd record -e block:block_rq_issue -e block:block_rq_complete -e block:block_bio_queue -e block:block_rq_merge -F dd if="${TESTFILE}.block" of=/dev/null bs=1M count=10 status=none"
log "Tracing block layer events (queueing & completion)..."
sudo trace-cmd record -e block:block_rq_issue -e block:block_rq_complete \
  -e block:block_bio_queue -e block:block_rq_merge \
  -F dd if="${TESTFILE}.block" of=/dev/null bs=1M count=10 status=none

log "Block layer trace analysis:"
sudo trace-cmd report | head -20

cat << 'BLOCK_NOTES'

=== BLOCK LAYER ANALYSIS ===

Key Events to Look For:

1) block_rq_issue: I/O request handed to device/driver
   - Queue depth grows as requests are issued
   - Shows when device starts working on I/O

2) block_rq_complete: Device finished processing
   - Kernel can wake sleepers waiting for I/O
   - Queue depth decreases

3) Time delta between issue→complete = device service time
   - This is the actual disk/SSD access time
   - Critical for performance analysis

4) block_bio_queue: Bio submitted to block layer
5) block_rq_merge: Multiple bios merged into single request

BLOCK_NOTES

# --- Cleanup ---
log ""
log "=== Cleanup ==="
rm -f "${TESTFILE}" "${TESTFILE}.write" "${TESTFILE}.block" "${STRACE_OUT}" "${STRACE_OUT}.write"
sudo rm -f /tmp/trace.dat 2>/dev/null || true

log "Demo complete."
