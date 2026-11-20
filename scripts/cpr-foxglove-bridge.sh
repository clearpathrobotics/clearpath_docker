#!/usr/bin/env bash
# cpr-foxglove-bridge: the foxglove-bridge image's command.
#
#   cpr-foxglove-bridge [launch] [launch args]   Start foxglove_bridge (the image's default command)
#   cpr-foxglove-bridge healthcheck              Exit 0 once its WebSocket port accepts connections
set -euo pipefail

# shellcheck source=cpr-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/cpr-common.sh"

port="${FOXGLOVE_BRIDGE_PORT:-8765}"

usage() {
  echo "usage: cpr-foxglove-bridge [launch] [launch args]" >&2
  echo "       cpr-foxglove-bridge healthcheck" >&2
}

split_subcommand launch "$@"
set -- "${subcommand_args[@]}"
case "${subcommand}" in
  launch) ;;
  healthcheck) : 2>/dev/null </dev/tcp/127.0.0.1/"${port}"; exit ;;
  -h | --help | help) usage; exit 0 ;;
  *) usage; exit 2 ;;
esac

load_ros_env

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

log_env FOXGLOVE_BRIDGE_PORT WAIT_FOR_SIM WAIT_FOR_TIMEOUT_SEC

wait_for_sim_if_enabled

echo "Starting foxglove_bridge on port ${port}..."
exec ros2 launch foxglove_bridge foxglove_bridge_launch.xml \
  port:="${port}" "$@"
