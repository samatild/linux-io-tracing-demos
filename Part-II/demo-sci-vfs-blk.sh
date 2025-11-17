#!/usr/bin/env bash
set -euo pipefail

# --- DEMO: System Call Interface → VFS → Filesystem → Block Layer ---
# This script demonstrates the complete I/O path from system calls through VFS,
# filesystem layer, to block layer using strace and ftrace kernel probes
#
# Author: Samuel Matildes (Linux I/O Training)
# Git repo: github.com/samatild/linux-io-tracing-demos

# --- Config ---
FILE="${1:-/tmp/demo.bin}"
BS="${BS:-4K}"          # read block size
COUNT="${COUNT:-1}"     # single read
TRACE_OUT="${TRACE_OUT:-/tmp/demo1.strace}"

# --- Helpers ---
is_root() { [ "${EUID:-$(id -u)}" -eq 0 ]; }
log() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
warn(){ printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[ERR ]\033[0m %s\n' "$*" ; exit 1; }

sudo_if_needed() { if is_root; then "$@"; else sudo "$@"; fi; }

# --- Ensure tracing dir ---
find_tracing_dir() {
  if [ -d /sys/kernel/tracing ]; then
    printf '/sys/kernel/tracing'
  elif [ -d /sys/kernel/debug/tracing ]; then
    printf '/sys/kernel/debug/tracing'
  else
    if mount -t tracefs nodev /sys/kernel/tracing 2>/dev/null; then
      printf '/sys/kernel/tracing'
    else
      err "Cannot find or mount tracefs (/sys/kernel/tracing)"
    fi
  fi
}
TRACING_DIR="$(find_tracing_dir)"

# --- Cleanup on exit ---
cleanup() {
  if [ -d "${TRACING_DIR}" ]; then
    echo 0 > "${TRACING_DIR}/tracing_on" 2>/dev/null || true1000
    [ -e "${TRACING_DIR}/events/kprobes/demo_vfs/enable" ] && echo 0 > "${TRACING_DIR}/events/kprobes/demo_vfs/enable" 2>/dev/null || true
    [ -e "${TRACING_DIR}/events/kprobes/demo_fs/enable" ] && echo 0 > "${TRACING_DIR}/events/kprobes/demo_fs/enable" 2>/dev/null || true
    [ -e "${TRACING_DIR}/events/kprobes/demo_blk/enable" ] && echo 0 > "${TRACING_DIR}/events/kprobes/demo_blk/enable" 2>/dev/null || true
    # remove only our demo probes
    if [ -w "${TRACING_DIR}/kprobe_events" ]; then
      printf "-:demo_vfs\n-:demo_fs\n-:demo_blk\n" >> "${TRACING_DIR}/kprobe_events" 2>/dev/null || true
    fi
    : > "${TRACING_DIR}/trace" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# --- 0) Prepare small test file ---
log "Preparing test file at ${FILE} (1 MiB)..."
dd if=/dev/zero of="${FILE}" bs=1M count=1 status=none

# Drop caches to ensure block I/O happens
log "Dropping page cache to ensure block I/O..."
echo 3 > /proc/sys/vm/drop_caches

# --- 1) Strace demo ---
log "Running strace on a single read of ${FILE} (saving to ${TRACE_OUT})"
env -i LC_ALL=C PATH=/usr/bin:/bin \
strace -ttT -y -o "${TRACE_OUT}" -qq \
  -e trace=open,openat,read,close \
  dd if="${FILE}" of=/dev/null bs="${BS}" count="${COUNT}" status=none

log "Strace interesting lines:"
grep -E 'openat\(|read\(|close\(' "${TRACE_OUT}" || true

# --- 2) VFS → FS probe demo ---
if ! is_root; then
  warn "Not root: skipping ftrace kprobe demo. Run 'sudo $0' to include it."
  exit 0
fi

log "Setting up ftrace kprobe for VFS→FS handoff..."

cd "${TRACING_DIR}" || err "Cannot cd to ${TRACING_DIR}"

# Disable tracing and clear trace
echo 0 > tracing_on 2>/dev/null || true
: > trace 2>/dev/null || true

# Remove any leftover demo probes
if [ -w kprobe_events ]; then
  # Check current kprobe_events and remove our demo probes
  if grep -q "demo_vfs\|demo_fs\|demo_blk" kprobe_events 2>/dev/null; then
    for probe in demo_vfs demo_fs demo_blk; do
      echo "-:$probe" >> kprobe_events 2>/dev/null || true
    done
    sleep 0.1  # Give time for removal
  fi
fi

# Add VFS probe
if [ -w kprobe_events ]; then
  echo "p:demo_vfs vfs_read file=%di count=%dx" >> kprobe_events || err "Failed to add VFS probe"
else
  err "Cannot write to kprobe_events"
fi

# Try to find filesystem read_iter symbol
FS_SYM=""
for sym in ext4_file_read_iter xfs_file_read_iter btrfs_file_read_iter f2fs_file_read_iter generic_file_read_iter; do
  if grep -qw "$sym" /proc/kallsyms 2>/dev/null; then
    FS_SYM="$sym"
    break
  fi
done

if [ -n "$FS_SYM" ]; then
  echo "p:demo_fs $FS_SYM iocb=%di" >> kprobe_events || err "Failed to add FS probe"
  log "Using filesystem symbol: $FS_SYM"
else
  warn "No FS read_iter symbol found; only vfs_read will be shown."
fi

# Add block layer probes
if grep -qw "submit_bio" /proc/kallsyms 2>/dev/null; then
  echo "p:demo_blk submit_bio bio=%di" >> kprobe_events || err "Failed to add block probe"
  log "Added block layer probe: submit_bio"
else
  warn "submit_bio symbol not found"
fi

# Enable tracing first
echo 1 > tracing_on

# Enable probes
[ -e events/kprobes/demo_vfs/enable ] && echo 1 > events/kprobes/demo_vfs/enable
[ -e events/kprobes/demo_fs/enable ] && echo 1 > events/kprobes/demo_fs/enable
[ -e events/kprobes/demo_blk/enable ] && echo 1 > events/kprobes/demo_blk/enable

# Drop caches again to ensure block I/O for the ftrace test
echo 3 > /proc/sys/vm/drop_caches

# Run a single read for tracing
env -i LC_ALL=C PATH=/usr/bin:/bin \
dd if="${FILE}" of=/dev/null bs="${BS}" count="${COUNT}" status=none >/dev/null 2>&1
sleep 0.1

# Disable tracing
echo 0 > tracing_on

log "VFS/FS/Block probe hits (last 30 lines):"
grep -E 'demo_vfs:|demo_fs:|demo_blk:' trace | tail -n 30 || true

log "Done. Strace saved to ${TRACE_OUT}, ftrace saved in ${TRACING_DIR}/trace"

