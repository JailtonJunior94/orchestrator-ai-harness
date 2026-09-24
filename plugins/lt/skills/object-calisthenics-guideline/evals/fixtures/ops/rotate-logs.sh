#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="${LOG_DIR:-/var/log/app}"

find "$LOG_DIR" -type f -name '*.log' -mtime 7 -delete
