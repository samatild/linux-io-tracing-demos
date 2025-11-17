#!/usr/bin/env bash
set -euo pipefail

WORKDIR="/opt/iolab2"

"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"/5_stop_webserver.sh || true

echo ""
read -p "Do you want to delete $WORKDIR and all generated files for Lab 2? [y/N] " yn
if [[ "$yn" =~ ^[Yy]$ ]]; then
  rm -rf "$WORKDIR"
  echo "Removed $WORKDIR"
else
  echo "Left files in place at $WORKDIR"
fi


