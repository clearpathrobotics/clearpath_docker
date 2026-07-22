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
wait_for_sim="${WAIT_FOR_SIM:-false}"
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
  "setup_path:=${setup_path}"
)

if [[ -n "${scan_topic}" ]]; then
  args+=("scan_topic:=${scan_topic}")
fi

log_robot_identity() {
  echo "[cpr-nav2-launch] robot namespace=$(detect_namespace || echo unknown)"
}

wait_for_topic_once() {
  local topic="$1"
  local per_try_timeout_s="${2:-5}"
  local total_timeout_s="${3:-${topic_wait_timeout_s}}"
  local waited=0

  while (( waited < total_timeout_s )); do
    if timeout "${per_try_timeout_s}" ros2 topic echo --once "${topic}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
    waited=$(( waited + 1 ))
  done

  return 1
}

wait_for_nav2_inputs() {
  local namespace="$1"

  if [[ -z "${namespace}" ]]; then
    echo "[cpr-nav2-launch] Namespace not found, skipping pre-nav2 topic gates" >&2
    return 0
  fi

  echo "[cpr-nav2-launch] waiting for odom and TF topics before Nav2 bringup..." >&2

  echo "[cpr-nav2-launch] waiting for /${namespace}/platform/odom/filtered" >&2
  if ! wait_for_topic_once "/${namespace}/platform/odom/filtered" 5 "${topic_wait_timeout_s}"; then
    echo "[cpr-nav2-launch] timed out waiting for /${namespace}/platform/odom/filtered; continuing" >&2
  fi

  echo "[cpr-nav2-launch] waiting for /${namespace}/tf_static" >&2
  if ! wait_for_topic_once "/${namespace}/tf_static" 5 "${topic_wait_timeout_s}"; then
    echo "[cpr-nav2-launch] timed out waiting for /${namespace}/tf_static; continuing" >&2
  fi

  echo "[cpr-nav2-launch] waiting for /${namespace}/tf" >&2
  if ! wait_for_topic_once "/${namespace}/tf" 5 "${topic_wait_timeout_s}"; then
    echo "[cpr-nav2-launch] timed out waiting for /${namespace}/tf; continuing" >&2
  fi

  echo "[cpr-nav2-launch] waiting briefly for /${namespace}/map (best effort)" >&2
  for _ in $(seq 1 5); do
    if timeout 2 ros2 topic echo --once "/${namespace}/map" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
}

bootstrap_lifecycle() {
  local namespace="$1"
  local service
  local node
  local state
  local i
  local all_active

  if [[ -z "${namespace}" ]]; then
    echo "[cpr-nav2-launch] Namespace not found, skipping automatic lifecycle bootstrap" >&2
    return 0
  fi

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
      state="$(ros2 lifecycle get "/${namespace}/${node}" 2>/dev/null | awk -F'[][]' '/^active/ {print $2}')"
      if [[ "${state}" != "3" ]]; then
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
  namespace="$(detect_namespace)"
  (
    bootstrap_lifecycle "${namespace}"
  ) &
fi

# --- Optional sim-readiness gate ---
if [[ "${wait_for_sim}" == "true" ]]; then
  echo "[cpr-nav2-launch] WAIT_FOR_SIM=true, waiting for /clock..." >&2
  if ! wait_for_topic_once "/clock" 5 "${topic_wait_timeout_s}"; then
    echo "[cpr-nav2-launch] timed out waiting for /clock; continuing" >&2
  fi
fi

slam_pid=""
namespace="$(detect_namespace)"

if [[ "${enable_slam}" == "true" && "${launch_file}" != "slam.launch.py" ]]; then
  ros2 launch clearpath_nav2_demos slam.launch.py "${args[@]}" "sync:=${slam_sync}" &
  slam_pid="$!"

  wait_for_nav2_inputs "${namespace}"
fi

cleanup() {
  if [[ -n "${slam_pid}" ]]; then
    kill "${slam_pid}" >/dev/null 2>&1 || true
    wait "${slam_pid}" >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT INT TERM

log_robot_yaml
log_robot_identity

ros2 launch clearpath_nav2_demos "${launch_file}" "${args[@]}" "$@"