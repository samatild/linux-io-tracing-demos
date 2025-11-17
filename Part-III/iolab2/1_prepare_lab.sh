#!/usr/bin/env bash
set -euo pipefail

WORKDIR="/opt/iolab2"
WWW_DIR="$WORKDIR/www"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Preparing Lab 2 environment..."

mkdir -p "$WWW_DIR"
mkdir -p "$WORKDIR"

chown "$(id -u)":"$(id -g)" "$WORKDIR" || true

echo "Installing Lab 2 webserver..."
if [ -f "$SCRIPT_DIR/webserver.py" ]; then
  cp "$SCRIPT_DIR/webserver.py" "$WORKDIR/webserver.py"
  chmod +x "$WORKDIR/webserver.py"
  echo "Webserver installed at $WORKDIR/webserver.py"
else
  echo "ERROR: webserver.py not found in $SCRIPT_DIR" >&2
  exit 1
fi

echo ""
echo "Lab 2 preparation complete."
echo "- Working directory: $WORKDIR"
echo "- Web root: $WWW_DIR"


