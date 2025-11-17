#!/usr/bin/env bash
set -euo pipefail


# Config
WORKDIR="/opt/iolab"
WWW_DIR="$WORKDIR/www"
UPLOAD_DIR="$WORKDIR/uploads"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Clean up old files from previous versions
echo "Cleaning up old lab files..."
rm -rf "$WWW_DIR" 2>/dev/null || true
rm -rf "$WORKDIR/dummy_files" 2>/dev/null || true

mkdir -p "$WWW_DIR"
mkdir -p "$UPLOAD_DIR"
chown $(id -u):$(id -g) "$WORKDIR" || true

# Copy webserver.py to the working directory
echo "Installing webserver..."
if [ -f "$SCRIPT_DIR/webserver.py" ]; then
    cp "$SCRIPT_DIR/webserver.py" "$WORKDIR/webserver.py"
    chmod +x "$WORKDIR/webserver.py"
    echo "✓ Webserver installed"
else
    echo "ERROR: webserver.py not found in $SCRIPT_DIR" >&2
    exit 1
fi


echo ""
echo "Lab preparation complete!"
echo "- Webroot: $WWW_DIR"