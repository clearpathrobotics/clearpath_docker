#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=cpr-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/cpr-common.sh"

use_sim_time="${USE_SIM_TIME:-true}"
scan_topic="${SCAN_TOPIC:-}"
launch_file="${NAV2_LAUNCH_FILE:-nav2.launch.py}"
enable_slam="${NAV2_ENABLE_SLAM:-false}"
slam_sync="${NAV2_SLAM_SYNC:-false}"
auto_nav2_startup="${AUTO_NAV2_STARTUP:-true}"
startup_timeout_s="${NAV2_STARTUP_TIMEOUT_S:-120}"
service_call_timeout_s="${NAV2_SERVICE_CALL_TIMEOUT_S:-8}"
active_wait_timeout_s="${NAV2_ACTIVE_WAIT_TIMEOUT_S:-60}"
topic_wait_timeout_s="${NAV2_TOPIC_WAIT_TIMEOUT_S:-120}"

lifecycle_nodes=(
  "bt_navigator"
  "planner_server"
  "controller_server"
  "behavior_server"
  "smoother_server"
  "velocity_smoother"
  "waypoint_follower"
  "collision_monitor"
)

args=(
  "use_sim_time:=${use_sim_time}"
  # Humble's launch files append "robot.yaml" without a separator
  "setup_path:=${setup_path}/"
)

if [[ -n "${scan_topic}" ]]; then
  args+=("scan_topic:=${scan_topic}")
fi

namespace="$(detect_namespace)"

log_env ROBOT_NAMESPACE USE_SIM_TIME NAV2_LAUNCH_FILE NAV2_ENABLE_SLAM NAV2_SLAM_SYNC \
  SCAN_TOPIC AUTO_NAV2_STARTUP WAIT_FOR_SIM
log_robot_yaml
echo "[cpr-nav2-launch] robot namespace=${namespace:-unknown}"

wait_for_nav2_inputs() {
  local topic

  have_namespace "${namespace}" "pre-Nav2 topic gates" || return 0

  echo "[cpr-nav2-launch] waiting for odom and TF topics before Nav2 bringup..." >&2
  for topic in platform/odom/filtered tf_static tf; do
    echo "[cpr-nav2-launch] waiting for /${namespace}/${topic}" >&2
    wait_for_topic_publishing "/${namespace}/${topic}" "${topic_wait_timeout_s}" ||
      echo "[cpr-nav2-launch] timed out waiting for /${namespace}/${topic}; continuing" >&2
  done

  echo "[cpr-nav2-launch] waiting briefly for /${namespace}/map (best effort)" >&2
  wait_for_topic_publishing "/${namespace}/map" 30 || true
}

bootstrap_lifecycle() {
  local service
  local node
  local i
  local all_active

  have_namespace "${namespace}" "automatic lifecycle bootstrap" || return 0

  service="/${namespace}/lifecycle_manager_navigation/manage_nodes"
  if ! wait_for_service "${service}" "${startup_timeout_s}"; then
    echo "[cpr-nav2-launch] Lifecycle service not available within ${startup_timeout_s}s: ${service}" >&2
    return 0
  fi

  # Startup, then pause/resume to converge mixed lifecycle states after startup races.
  timeout "${service_call_timeout_s}" ros2 service call "${service}" nav2_msgs/srv/ManageLifecycleNodes '{command: 0}' >/dev/null 2>&1 || true
  sleep 1
  timeout "${service_call_timeout_s}" ros2 service call "${service}" nav2_msgs/srv/ManageLifecycleNodes '{command: 1}' >/dev/null 2>&1 || true
  sleep 1
  timeout "${service_call_timeout_s}" ros2 service call "${service}" nav2_msgs/srv/ManageLifecycleNodes '{command: 2}' >/dev/null 2>&1 || true

  # Keep nudging lifecycle until the key navigation nodes report active.
  for ((i=0; i<active_wait_timeout_s; i++)); do
    all_active="true"
    for node in "${lifecycle_nodes[@]}"; do
      if [[ "$(get_node_state "/${namespace}/${node}")" != "active" ]]; then
        all_active="false"
        break
      fi
    done

    if [[ "${all_active}" == "true" ]]; then
      echo "[cpr-nav2-launch] Navigation lifecycle nodes are active" >&2
      return 0
    fi

    # Retry resume periodically in case startup races leave nodes inactive.
    if (( i % 5 == 0 )); then
      timeout "${service_call_timeout_s}" ros2 service call "${service}" nav2_msgs/srv/ManageLifecycleNodes '{command: 2}' >/dev/null 2>&1 || true

      # Fallback when lifecycle manager calls are slow or unresponsive.
      for node in "${lifecycle_nodes[@]}"; do
        activate_node_direct "/${namespace}/${node}" || true
      done
    fi
    sleep 1
  done

  echo "[cpr-nav2-launch] Timed out waiting for active lifecycle nodes; navigation goals may be rejected" >&2
}

if [[ "${auto_nav2_startup}" == "true" ]]; then
  bootstrap_lifecycle &
fi

WAIT_FOR_SIM="${WAIT_FOR_SIM:-false}" wait_for_sim_if_enabled "${namespace}"

slam_pid=""

if [[ "${enable_slam}" == "true" && "${launch_file}" != "slam.launch.py" ]]; then
  ros2 launch clearpath_nav2_demos slam.launch.py "${args[@]}" "sync:=${slam_sync}" &
  slam_pid="$!"

  wait_for_nav2_inputs
fi

cleanup() {
  if [[ -n "${slam_pid}" ]]; then
    kill "${slam_pid}" >/dev/null 2>&1 || true
    wait "${slam_pid}" >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT INT TERM

ros2 launch clearpath_nav2_demos "${launch_file}" "${args[@]}" "$@"
