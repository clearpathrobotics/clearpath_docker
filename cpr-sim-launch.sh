#!/usr/bin/env bash
set -euo pipefail

setup_path="${SETUP_PATH:-$HOME/setup/path/}"

exec ros2 launch clearpath_gz simulation.launch.py "setup_path:=${setup_path}" "$@"