#!/usr/bin/env bash
set -euo pipefail
WORKDIR="/opt/iolab"

if [ -f "$WORKDIR/http-server.pid" ]; then
  PID=$(cat "$WORKDIR/http-server.pid")
  echo "Stopping webserver (PID $PID)..."
  kill "$PID" 2>/dev/null || true
  sleep 1
  kill -9 "$PID" 2>/dev/null || true
  rm -f "$WORKDIR/http-server.pid"
  echo "Webserver stopped"
else
  echo "No http-server.pid found; attempting cleanup"
  pkill -f "python3 /opt/iolab/webserver.py" 2>/dev/null || echo "No webserver found"
fi

# Clean up any uploaded files
rm -f "$WORKDIR/uploads/"*.tmp 2>/dev/null || true
