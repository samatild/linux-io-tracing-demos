#!/usr/bin/env bash
set -euo pipefail


WORKDIR="/opt/iolab"
WWW_DIR="$WORKDIR/www"
PORT=${1:-8000}


if [ ! -d "$WWW_DIR" ]; then
echo "Web directory $WWW_DIR not found. Run 1_prepare_lab.sh first." >&2
exit 1
fi


# Start a simple Python HTTP server in background and save PID
cd "$WWW_DIR"
# Use nohup so it remains when you close the shell; put it in background
nohup python3 /opt/iolab/webserver.py > "$WORKDIR/http-server.log" 2>&1 &
PID=$!
echo $PID > "$WORKDIR/http-server.pid"


