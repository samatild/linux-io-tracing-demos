#!/usr/bin/env bash
set -euo pipefail

WORKDIR="/opt/iolab2"

if [ -f "$WORKDIR/http-server.pid" ]; then
  PID=$(cat "$WORKDIR/http-server.pid")
  echo "Stopping Lab 2 webserver (PID $PID)..."
  kill "$PID" 2>/dev/null || true
  sleep 1
  kill -9 "$PID" 2>/dev/null || true
  rm -f "$WORKDIR/http-server.pid"
  echo "Webserver stopped"
else
  echo "No http-server.pid found; attempting cleanup"
  pkill -f "python3 $WORKDIR/webserver.py" 2>/dev/null || echo "No Lab 2 webserver process found"
fi


