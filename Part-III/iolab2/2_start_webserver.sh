#!/usr/bin/env bash
set -euo pipefail

WORKDIR="/opt/iolab2"
WWW_DIR="$WORKDIR/www"
PORT=${1:-8000}

if [ ! -d "$WWW_DIR" ]; then
  echo "Web directory $WWW_DIR not found. Run 1_prepare_lab.sh first." >&2
  exit 1
fi

cd "$WWW_DIR"
nohup python3 "$WORKDIR/webserver.py" > "$WORKDIR/http-server.log" 2>&1 &
PID=$!
echo "$PID" > "$WORKDIR/http-server.pid"

echo "Lab 2 webserver started on port $PORT (PID $PID)"


