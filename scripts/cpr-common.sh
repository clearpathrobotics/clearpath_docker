#!/usr/bin/env bash
# Common utilities shared by Clearpath launch scripts.
# Source this file before use:
#   source "$(dirname "${BASH_SOURCE[0]}")/cpr-common.sh"

# Setup path must be provided via SETUP_PATH environment variable (typically set in docker-compose).
# Strip any trailing slashes so path joins (e.g. ${setup_path}/robot.yaml) are clean.
setup_path="${SETUP_PATH:-/etc/clearpath}"
setup_path="${setup_path%/}"
cpr_default_cyclonedds_uri="file:///etc/cpr/cyclonedds.xml"

# split_subcommand <default> [args...]
#
# Sets subcommand to the first argument, or <default> when there is none or it's a launch argument
# (name:=value), and subcommand_args to the remaining arguments.
# shellcheck disable=SC2034  # the variables are for the caller
split_subcommand() {
  subcommand="$1"
  shift
  if [[ $# -gt 0 && "$1" != *:=* ]]; then
    subcommand="$1"
    shift
  fi
  subcommand_args=("$@")
}

# source_ros
#
# Sources the ROS installation, which fails under set -u.
source_ros() {
  local shell_opts
  shell_opts="$(set +o)"
  set +u
  # shellcheck disable=SC1090
  source "/opt/ros/${ROS_DISTRO}/setup.bash"
  eval "${shell_opts}"
}

# load_ros_env
#
# Exports the ROS settings in robot.yaml's system.ros2 section, as a robot's generated setup.bash
# does: ROS_DOMAIN_ID, RMW_IMPLEMENTATION, ROS_AUTOMATIC_DISCOVERY_RANGE, the middleware profile,
# and discovery server settings. Values already in the environment win, except empty ones and the
# defaults the image (its CycloneDDS profile) and the ROS setup (SUBNET discovery) export. Without
# a profile, CycloneDDS uses the image's.
load_ros_env() {
  local yaml="${setup_path}/robot.yaml"
  local env_dir var shell_opts
  local -A keep=()
  local -A defaults=(
    [CYCLONEDDS_URI]="${cpr_default_cyclonedds_uri}"
    [ROS_AUTOMATIC_DISCOVERY_RANGE]=SUBNET
  )
  env_dir="${TMPDIR:-/tmp}/cpr-ros-env-$(id -u)"

  for var in ROS_DOMAIN_ID RMW_IMPLEMENTATION ROS_AUTOMATIC_DISCOVERY_RANGE CYCLONEDDS_URI; do
    if [[ -z "${!var:-}" ]]; then
      unset "${var}"
    elif [[ "${!var}" != "${defaults[${var}]:-}" ]]; then
      keep["${var}"]="${!var}"
    fi
  done

  if [[ -f "${yaml}" ]]; then
    # Generated from a copy, since the setup path is often mounted read-only
    if [[ ! -f "${env_dir}/setup.bash" || "${yaml}" -nt "${env_dir}/setup.bash" ]]; then
      rm -f "${env_dir}/setup.bash"
      if ! { mkdir -p "${env_dir}" && cp "${yaml}" "${env_dir}/robot.yaml" &&
        (source_ros && ros2 run clearpath_generator_common generate_bash -s "${env_dir}") >/dev/null 2>&1; }; then
        echo "[cpr] couldn't read the ROS settings from ${yaml}; using the environment's" >&2
      fi
    fi
    if [[ -f "${env_dir}/setup.bash" ]]; then
      shell_opts="$(set +o)"
      set +eu
      # shellcheck disable=SC1091
      source "${env_dir}/setup.bash" >/dev/null 2>&1
      eval "${shell_opts}"
    fi
  fi

  for var in "${!keep[@]}"; do
    export "${var}=${keep[${var}]}"
  done
  if [[ -z "${CYCLONEDDS_URI:-}" && -f "${cpr_default_cyclonedds_uri#file://}" ]]; then
    export CYCLONEDDS_URI="${cpr_default_cyclonedds_uri}"
  fi
  cpr_ros_env_loaded=1
}

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
  if [[ -n "${cpr_ros_env_loaded:-}" && "${RMW_IMPLEMENTATION:-}" != rmw_cyclonedds_cpp ]]; then
    echo "[cpr] WARNING: these images expect CycloneDDS; set system.ros2.middleware.implementation:" \
      "rmw_cyclonedds_cpp in robot.yaml (Fast DDS can't share memory between containers)" >&2
  fi
}

# log_robot_yaml [yaml_file]
#
# Prints the resolved path to robot.yaml and its contents to stderr.
log_robot_yaml() {
  local yaml_file="${1:-${setup_path}/robot.yaml}"
  local host_path=""

  # If SETUP_PATH_HOST is set, show the host path for easier debugging
  if [[ -n "${SETUP_PATH_HOST:-}" ]]; then
    local rel_path="${yaml_file#"${setup_path}"/}"
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
