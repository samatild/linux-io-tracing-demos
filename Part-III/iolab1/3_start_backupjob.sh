#!/usr/bin/env bash
set -euo pipefail

WORKDIR="/opt/iolab"
IO_TMPDIR="$WORKDIR/io_tmp"
CONCURRENCY=${1:-3}
MAX_WRITE_MB=1024
MIN_WRITE_MB=64
# Legacy SLEEP_MAX kept for compatibility but no longer used directly; see burst/idle logic below.
SLEEP_MAX=3

mkdir -p "$IO_TMPDIR"

# Create a wrapper script that will run all workers
# This allows us to properly kill all children using process group
cat > "$WORKDIR/backupjob_runner.sh" << 'RUNNER_SCRIPT'
#!/usr/bin/env bash

# Trap to kill all children when this script exits
trap 'kill $(jobs -p) 2>/dev/null' EXIT

worker() {
  idx="$1"
  IO_TMPDIR="$2"
  MAX_WRITE_MB="$3"
  MIN_WRITE_MB="$4"
  SLEEP_MAX="$5"

  # Time-based burst pattern:
  # - High phase: 10 seconds of continuous writes
  # - Idle phase: 10–20 seconds of no writes
  # All workers follow the same pattern, so the overall disk load clearly
  # alternates between "busy" and "quiet" periods.
  CHUNK_MB="$MIN_WRITE_MB"
  
  while true; do
    # Durations for this cycle
    HIGH_SEC=10                         # 10s of high activity
    IDLE_SEC=$(( (RANDOM % 11) + 10 ))  # 10–20s idle

    start_ts=$(date +%s)

    # High-activity phase: keep writing until HIGH_SEC has elapsed
    while true; do
      now_ts=$(date +%s)
      elapsed=$(( now_ts - start_ts ))
      if [ "$elapsed" -ge "$HIGH_SEC" ]; then
        break
      fi

      outfile="$IO_TMPDIR/backupjob_worker_${idx}_$(date +%s%N).tmp"
      # Use oflag=direct to bypass page cache and conv=fdatasync to ensure data hits disk
      dd if=/dev/zero of="$outfile" bs=1M count="$CHUNK_MB" oflag=direct status=none conv=fdatasync 2>/dev/null || true
      sync
      rm -f "$outfile" 2>/dev/null || true
    done

    # Idle phase: no disk activity, just sleep
    sleep "$IDLE_SEC"
  done
}

# Start workers
for i in $(seq 1 $1); do
  worker "$i" "$2" "$3" "$4" "$5" &
done

# Wait for all background jobs
wait
RUNNER_SCRIPT

chmod +x "$WORKDIR/backupjob_runner.sh"

# Start the BackupJob in its own process group so we can kill all children
setsid "$WORKDIR/backupjob_runner.sh" "$CONCURRENCY" "$IO_TMPDIR" "$MAX_WRITE_MB" "$MIN_WRITE_MB" "$SLEEP_MAX" > /dev/null 2>&1 &
PID=$!

sleep 1
if ps -p "$PID" > /dev/null 2>&1; then
  echo "$PID" > "$WORKDIR/BackupJob.pid"
  echo "BackupJob started (PID $PID, $CONCURRENCY workers)"
  echo "IO temp dir: $IO_TMPDIR"
  echo ""
  echo "Monitor with: watch -n 1 'ls -lh $IO_TMPDIR; iostat -x 1 1'"
else
  echo "Failed to start BackupJob" >&2
  exit 1
fi

