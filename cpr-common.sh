#!/usr/bin/env bash
# Common utilities shared by Clearpath launch scripts.
# Source this file before use:
#   source "$(dirname "${BASH_SOURCE[0]}")/cpr-common.sh"

# Setup path must be provided via SETUP_PATH environment variable (typically set in docker-compose).
# Strip any trailing slashes so path joins (e.g. ${setup_path}/robot.yaml) are clean.
setup_path="${SETUP_PATH}"
setup_path="${setup_path%/}"

# log_robot_yaml [yaml_file]
#
# Prints the resolved path to robot.yaml and its contents to stderr.
log_robot_yaml() {
  local yaml_file="${1:-${setup_path}/robot.yaml}"
  local host_path=""
  
  # If SETUP_PATH_HOST is set, show the host path for easier debugging
  if [[ -n "${SETUP_PATH_HOST:-}" ]]; then
    local rel_path="${yaml_file#${setup_path}/}"
    host_path=" (host: ${SETUP_PATH_HOST}/${rel_path})"
  fi
  
  echo "[cpr] robot.yaml path: ${yaml_file}${host_path}" >&2
  if [[ -f "${yaml_file}" ]]; then
    echo "[cpr] robot.yaml contents:" >&2
    cat "${yaml_file}" >&2
  else
    echo "[cpr] robot.yaml not found at ${yaml_file}" >&2
  fi
}

# detect_namespace [yaml_file]
#
# Prints the robot namespace and returns 0.
# Resolution order:
#   1. ROBOT_NAMESPACE environment variable
#   2. platform.id in robot.yaml   (e.g. "a200_0000")
#   3. system.<key>.namespace in robot.yaml
#   4. top-level namespace / id key in robot.yaml
# Prints an empty string when nothing is found.
detect_namespace() {
  local yaml_file="${1:-${setup_path}/robot.yaml}"
  local ns
  ns="${ROBOT_NAMESPACE:-}"

  if [[ -n "${ns}" ]]; then
    printf '%s\n' "${ns}"
    return 0
  fi

  if [[ ! -f "${yaml_file}" ]]; then
    printf '\n'
    return 0
  fi

  python3 - <<'PY' "${yaml_file}"
import sys
from pathlib import Path
import yaml

path = Path(sys.argv[1])
try:
    data = yaml.safe_load(path.read_text()) or {}
except Exception as e:
    print(f"Error parsing {path}: {e}", file=sys.stderr)
    raise SystemExit(0)

# 1. platform.id  (e.g. "a300_00000")
ns = data.get('platform', {}).get('id', '')
if ns:
    print(ns)
    raise SystemExit(0)

# 2. system.<key>.namespace
for _, info in data.get('system', {}).items():
    if isinstance(info, dict) and info.get('namespace'):
        print(info['namespace'])
        raise SystemExit(0)

# 3. top-level namespace / id
print(data.get('namespace') or data.get('id') or '')
PY
}

# wait_for_service <service_name> [timeout_s]
#
# Blocks until the named ROS 2 service appears or <timeout_s> seconds elapse.
# Returns 0 when found, 1 on timeout.
wait_for_service() {
  local service="$1"
  local timeout_s="${2:-30}"
  local i

  for ((i = 0; i < timeout_s; i++)); do
    if ros2 service list 2>/dev/null | grep -qx "${service}"; then
      return 0
    fi
    sleep 1
  done

  return 1
}

# ---------------------------------------------------------------------------
# wait_for_sim_if_enabled
#
# Blocks until the Gazebo simulation is ready (i.e. /clock and a
# */platform/odom/filtered topic are visible) or the timeout elapses.
#
# Environment variables (all optional):
#   WAIT_FOR_SIM         true | false   (default: true)
#   WAIT_FOR_TIMEOUT_SEC <seconds>      (default: 120)
# ---------------------------------------------------------------------------
wait_for_sim_if_enabled() {
  local wait_for_sim="${WAIT_FOR_SIM:-true}"
  if [[ "${wait_for_sim}" != "true" ]]; then
    return 0
  fi

  local timeout_sec="${WAIT_FOR_TIMEOUT_SEC:-120}"
  local sleep_sec=1
  local waited=0

  echo "[cpr-common] WAIT_FOR_SIM=true, waiting for simulation topics..."
  echo "[cpr-common] expecting: /clock and */platform/odom/filtered"

  while (( waited < timeout_sec )); do
    local topics
    topics="$(ros2 topic list 2>/dev/null || true)"

    if echo "${topics}" | grep -Fxq "/clock" && \
       echo "${topics}" | grep -Eq '/platform/odom/filtered$'; then
      echo "[cpr-common] Simulation topics detected. Proceeding."
      return 0
    fi

    sleep "${sleep_sec}"
    waited=$(( waited + sleep_sec ))
  done

  echo "[cpr-common] Timeout after ${timeout_sec}s waiting for simulation topics; proceeding anyway." >&2
  return 0
}

# activate_node_direct <fully_qualified_node_name>
#
# Attempts to transition a lifecycle node to the active state directly.
# Returns 0 on success, 1 on failure.
activate_node_direct() {
  local node="$1"
  ros2 lifecycle set "${node}" activate >/dev/null 2>&1
}

# wait_for_topic <topic_name> [timeout_s]
#
# Blocks until the named ROS 2 topic appears or <timeout_s> seconds elapse.
# Returns 0 when found, 1 on timeout.
wait_for_topic() {
  local topic="$1"
  local timeout_s="${2:-30}"
  local i

  for ((i = 0; i < timeout_s; i++)); do
    if ros2 topic list 2>/dev/null | grep -q "^${topic}$"; then
      return 0
    fi
    sleep 1
  done

  return 1
}

# get_node_state <node_fqn>
#
# Prints the current lifecycle state name of a ROS 2 managed node (e.g. "active").
# Returns 0; prints nothing if the node is unreachable.
get_node_state() {
  local node_fqn="$1"
  ros2 lifecycle get "${node_fqn}" 2>/dev/null | awk 'NR==1 {print $1}'
}

# activate_node_direct <node_fqn>
#
# Drives a ROS 2 managed node through configure -> activate with up to 4 retries.
# Uses ${service_call_timeout_s} from the calling scope (default 8 s if unset).
# Returns 0 when the node reaches active, 1 otherwise.
activate_node_direct() {
  local node_fqn="$1"
  local _timeout="${service_call_timeout_s:-8}"
  local state
  local i

  for ((i=0; i<4; i++)); do
    state="$(get_node_state "${node_fqn}")"
    case "${state}" in
      active)
        return 0
        ;;
      unconfigured)
        timeout "${_timeout}" ros2 lifecycle set "${node_fqn}" configure >/dev/null 2>&1 || true
        ;;
      inactive)
        timeout "${_timeout}" ros2 lifecycle set "${node_fqn}" activate >/dev/null 2>&1 || true
        ;;
      *)
        ;;
    esac
    sleep 1
  done

  state="$(get_node_state "${node_fqn}")"
  [[ "${state}" == "active" ]]
}
