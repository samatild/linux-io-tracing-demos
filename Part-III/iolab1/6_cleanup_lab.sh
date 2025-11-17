#!/usr/bin/env bash
set -euo pipefail
WORKDIR="/opt/iolab"


./5_stop_webserver.sh || true
./4_stop_backupjob.sh || true


read -p "Do you want to delete $WORKDIR and all generated files? [y/N] " yn
if [[ "$yn" =~ ^[Yy]$ ]]; then
rm -rf "$WORKDIR"
echo "Removed $WORKDIR"
else
echo "Left files in place at $WORKDIR"
fi
