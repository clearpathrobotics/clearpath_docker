#!/usr/bin/env bash
# Container healthcheck: cpr-healthcheck <sim|nav2|viz|robot|foxglove-bridge>
# Exits 0 when the service is ready; names are resolved in the robot namespace.

# shellcheck source=cpr-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/cpr-common.sh"
# shellcheck disable=SC1090
source "/opt/ros/${ROS_DISTRO}/setup.bash"

ns="$(detect_namespace)"
prefix="${ns:+/${ns}}"

case "${1:-}" in
  sim)
    topic_publishing /clock && topic_publishing "${prefix}/platform/odom/filtered"
    ;;
  nav2)
    [[ "$(get_node_state "${prefix}/bt_navigator")" == "active" ]] || exit 1
    [[ "${NAV2_ENABLE_SLAM:-false}" != "true" ]] || topic_publishing "${prefix}/map"
    ;;
  viz)
    pgrep -x rviz2 >/dev/null
    ;;
  robot)
    # Match the services' middleware, domain, and discovery settings from robot.yaml
    # shellcheck disable=SC1091
    [[ -f "${setup_path}/setup.bash" ]] && source "${setup_path}/setup.bash"
    topic_publishing "${prefix}/platform/mcu/status"
    ;;
  foxglove-bridge)
    : 2>/dev/null </dev/tcp/127.0.0.1/"${FOXGLOVE_BRIDGE_PORT:-8765}"
    ;;
  *)
    echo "usage: cpr-healthcheck <sim|nav2|viz|robot|foxglove-bridge>" >&2
    exit 2
    ;;
esac
