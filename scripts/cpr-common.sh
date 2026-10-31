#!/usr/bin/env bash
# Common utilities shared by Clearpath launch scripts.
# Source this file before use:
#   source "$(dirname "${BASH_SOURCE[0]}")/cpr-common.sh"

# Setup path must be provided via SETUP_PATH environment variable (typically set in docker-compose).
# Strip any trailing slashes so path joins (e.g. ${setup_path}/robot.yaml) are clean.
setup_path="${SETUP_PATH}"
setup_path="${setup_path%/}"

# log_env [VAR ...]
#
# Prints the running user, the common ROS settings, and any extra variables named, to stderr.
log_env() {
  local var
  echo "[cpr] user=$(id -un) uid=$(id -u) gid=$(id -g)" >&2
  for var in ROS_DISTRO RMW_IMPLEMENTATION ROS_DOMAIN_ID ROS_AUTOMATIC_DISCOVERY_RANGE \
             CYCLONEDDS_URI SETUP_PATH "$@"; do
    echo "[cpr] ${var}=${!var-<unset, script default>}" >&2
  done
}

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
#   5. serial_number with '-' -> '_' (clearpath_config's default)
# Prints an empty string when nothing is found.
detect_namespace() {
  local yaml_file="${1:-${setup_path}/robot.yaml}"
  local ns
  ns="${ROBOT_NAMESPACE:-}"

  if [[ -n "${ns}" ]]; then
    ns="${ns#/}"
    printf '%s\n' "${ns%/}"
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
    print(str(ns).strip('/'))
    raise SystemExit(0)

# 2. system.<key>.namespace
for _, info in data.get('system', {}).items():
    if isinstance(info, dict) and info.get('namespace'):
        print(str(info['namespace']).strip('/'))
        raise SystemExit(0)

# 3. top-level namespace / id, 4. serial_number
ns = data.get('namespace') or data.get('id') or str(data.get('serial_number') or '').replace('-', '_')
print(str(ns).strip('/'))
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
    if ros2 service list --no-daemon 2>/dev/null | grep -qx "${service}"; then
      return 0
    fi
    sleep 1
  done

  return 1
}

# ---------------------------------------------------------------------------
# wait_for_sim_if_enabled [namespace]
#
# Blocks until /clock and <namespace>/platform/odom/filtered are publishing,
# or the timeout elapses (then proceeds anyway).
#
# Environment variables (all optional):
#   WAIT_FOR_SIM         true | false   (default: true)
#   WAIT_FOR_TIMEOUT_SEC <seconds>      (default: 120)
# ---------------------------------------------------------------------------
wait_for_sim_if_enabled() {
  if [[ "${WAIT_FOR_SIM:-true}" != "true" ]]; then
    return 0
  fi

  local timeout_sec="${WAIT_FOR_TIMEOUT_SEC:-120}"
  local ns="${1-$(detect_namespace)}"
  local topic

  echo "[cpr-common] WAIT_FOR_SIM=true, waiting for simulation topics..."
  for topic in /clock "${ns:+/${ns}}/platform/odom/filtered"; do
    echo "[cpr-common] waiting for ${topic}"
    if ! wait_for_topic_publishing "${topic}" "${timeout_sec}"; then
      echo "[cpr-common] Timeout after ${timeout_sec}s waiting for ${topic}; proceeding anyway." >&2
      return 0
    fi
  done
  echo "[cpr-common] Simulation topics detected. Proceeding."
}

# have_namespace <namespace> <what>
#
# Returns 0 when <namespace> is set; otherwise warns that <what> is skipped and returns 1.
have_namespace() {
  [[ -n "$1" ]] && return 0
  echo "[cpr] Robot namespace not found in ${setup_path}/robot.yaml; skipping $2" >&2
  return 1
}

# topic_publishing <topic> [timeout_s]
#
# Returns 0 once a message arrives on <topic> within <timeout_s> (default 8).
# Unlike checking `ros2 topic list`, this fails for topics that only have subscribers.
topic_publishing() {
  timeout "${2:-8}" ros2 topic echo --no-daemon --once "$1" >/dev/null 2>&1
}

# wait_for_topic_publishing <topic> <total_timeout_s> [per_try_timeout_s]
#
# Blocks until a message arrives on <topic>. Returns 0 when one does, 1 on timeout.
wait_for_topic_publishing() {
  local topic="$1"
  local total_timeout_s="$2"
  local per_try_timeout_s="${3:-5}"
  local start="${SECONDS}"

  while (( SECONDS - start < total_timeout_s )); do
    topic_publishing "${topic}" "${per_try_timeout_s}" && return 0
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
  ros2 lifecycle get --no-daemon "${node_fqn}" 2>/dev/null | awk 'NR==1 {print $1}'
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
        timeout "${_timeout}" ros2 lifecycle set --no-daemon "${node_fqn}" configure >/dev/null 2>&1 || true
        ;;
      inactive)
        timeout "${_timeout}" ros2 lifecycle set --no-daemon "${node_fqn}" activate >/dev/null 2>&1 || true
        ;;
      *)
        ;;
    esac
    sleep 1
  done

  state="$(get_node_state "${node_fqn}")"
  [[ "${state}" == "active" ]]
}
