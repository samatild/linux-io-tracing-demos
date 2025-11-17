#!/usr/bin/env bash
set -euo pipefail
WORKDIR="/opt/iolab"

if [ -f "$WORKDIR/BackupJob.pid" ]; then
  PID=$(cat "$WORKDIR/BackupJob.pid")
  echo "Stopping BackupJob (PID $PID) and all child processes..."
  
  # Kill the entire process group (negative PID)
  # This ensures all child worker processes are killed
  kill -- -"$PID" 2>/dev/null || true
  
  # Give processes time to exit gracefully
  sleep 1
  
  # Force kill if still running
  kill -9 -- -"$PID" 2>/dev/null || true
  
  # Also try direct PID kill
  kill -9 "$PID" 2>/dev/null || true
  
  # Clean up any orphaned processes
  pkill -f "backupjob_runner.sh" 2>/dev/null || true
  pkill -f "backupjob_worker" 2>/dev/null || true
  
  rm -f "$WORKDIR/BackupJob.pid"
  
  # Clean up temp files
  rm -f "$WORKDIR/io_tmp/"*.tmp 2>/dev/null || true
  
  echo "BackupJob stopped"
else
  echo "No BackupJob.pid found; attempting cleanup of any running processes"
  pkill -f "backupjob_runner.sh" 2>/dev/null || echo "No BackupJob processes found"
  rm -f "$WORKDIR/io_tmp/"*.tmp 2>/dev/null || true
fi
