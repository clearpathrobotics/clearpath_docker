#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=cpr-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/cpr-common.sh"

port="${FOXGLOVE_BRIDGE_PORT:-8765}"

echo "============================================="
echo " Clearpath foxglove_bridge container"
echo "============================================="
echo ""
echo "  Foxglove WebSocket URL: ws://localhost:${port}"
echo ""
echo "  Open Lichtblick and connect using:"
echo "    Open connection → Foxglove WebSocket → ws://localhost:${port}"
echo ""
echo "============================================="

wait_for_sim_if_enabled

echo "Starting foxglove_bridge on port ${port}..."
exec ros2 launch foxglove_bridge foxglove_bridge_launch.xml \
  port:="${port}" "$@"
