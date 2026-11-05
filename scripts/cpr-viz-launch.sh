#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=cpr-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/cpr-common.sh"

log_env ROBOT_NAMESPACE USE_SIM_TIME CLEARPATH_VIZ_CONFIG DISPLAY
log_robot_yaml
namespace="$(detect_namespace)"
namespace="${namespace:-a300_00000}"
use_sim_time="${USE_SIM_TIME:-true}"
viz_config="${CLEARPATH_VIZ_CONFIG:-robot}"

case "$viz_config" in
  navigation)
    launch_file="view_navigation.launch.py"
    ;;
  robot)
    launch_file="view_robot.launch.py"
    ;;
  *)
    echo "Warning: unknown CLEARPATH_VIZ_CONFIG='$viz_config', defaulting to robot" >&2
    launch_file="view_robot.launch.py"
    ;;
esac

echo "Waiting for robot topics before starting RViz..."
for topic in "/${namespace}/robot_description" "/${namespace}/tf"; do
  wait_for_topic_publishing "${topic}" 45 || echo "Warning: ${topic} not publishing yet" >&2
done

echo "Launching clearpath visualization config '$viz_config' for namespace: ${namespace}"
exec ros2 launch clearpath_viz "$launch_file" "namespace:=${namespace}" "use_sim_time:=${use_sim_time}" "$@"
