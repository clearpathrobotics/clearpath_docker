#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=cpr-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/cpr-common.sh"

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

namespace="$(detect_namespace)"
tf_topic="/${namespace}/tf"
description_topic="/${namespace}/robot_description"

echo "Waiting for simulation topics before starting RViz..."
wait_for_topic "$description_topic" 45 || echo "Warning: ${description_topic} not found yet" >&2
wait_for_topic "$tf_topic" 45 || echo "Warning: ${tf_topic} not found yet" >&2

echo "Launching clearpath visualization config '$viz_config' for namespace: ${namespace:-unknown}"
exec ros2 launch clearpath_viz "$launch_file" "namespace:=${namespace}" "use_sim_time:=${use_sim_time}" "$@"
