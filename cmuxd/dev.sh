#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

pkill -f 'cmuxd.*--port' 2>/dev/null || true
sleep 0.1

zig build -Doptimize=ReleaseFast
exec ./zig-out/bin/cmuxd "$@"
