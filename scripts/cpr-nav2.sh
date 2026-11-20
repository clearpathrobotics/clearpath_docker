#!/usr/bin/env bash
# cpr-nav2: the nav2 image's command.
#
#   cpr-nav2 [launch] [launch args]                  Start Nav2 (the image's default command)
#   cpr-nav2 healthcheck                             Exit 0 once Nav2 is up (the image's health check)
#   cpr-nav2 save-map <name|path> [map_saver_cli options]
#       Save the robot's map (from SLAM or a loaded map) as <name>.yaml and <name>.pgm in
#       ${SETUP_PATH}/maps, ready to load with NAV2_MAP. A path containing "/" is used as given.
set -euo pipefail

# shellcheck source=cpr-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/cpr-common.sh"

load_ros_env

usage() {
  echo "usage: cpr-nav2 [launch] [launch args]" >&2
  echo "       cpr-nav2 healthcheck" >&2
  echo "       cpr-nav2 save-map <name|path> [map_saver_cli options]" >&2
}

# nav2_lifecycle_manager [launch_file]
#
# Prints the Nav2 lifecycle manager that brings up the given clearpath_nav2_demos launch file
# (NAV2_LAUNCH_FILE by default), or nothing for slam.launch.py, which has none.
nav2_lifecycle_manager() {
  case "${1:-${NAV2_LAUNCH_FILE:-nav2.launch.py}}" in
    slam.launch.py) ;;
    localization.launch.py) echo lifecycle_manager_localization ;;
    *) echo lifecycle_manager_navigation ;;
  esac
}

# nav2_lifecycle_managers
#
# Prints every Nav2 lifecycle manager the nav2 container runs for NAV2_LAUNCH_FILE, including
# localization's when NAV2_MAP loads a map for navigation.
nav2_lifecycle_managers() {
  local launch_file="${NAV2_LAUNCH_FILE:-nav2.launch.py}"
  if [[ -n "${NAV2_MAP:-}" && "${launch_file}" == "nav2.launch.py" ]]; then
    echo lifecycle_manager_localization
  fi
  nav2_lifecycle_manager "${launch_file}"
}

# lifecycle_manager_state <manager_fqn> [timeout_s]
#
# Prints the state of a Nav2 lifecycle manager's nodes from its is_active service:
#   active    all managed nodes are active
#   inactive  the manager is idle but its nodes aren't active, e.g. after a failed bringup
#   busy      no reply: the manager isn't up yet or is still transitioning nodes, which blocks
#             its services
lifecycle_manager_state() {
  local reply
  reply="$(timeout "${2:-8}" ros2 service call "$1/is_active" std_srvs/srv/Trigger 2>/dev/null)"
  case "${reply}" in
    *success=True*) echo active ;;
    *success=False*) echo inactive ;;
    *) echo busy ;;
  esac
}

# Healthy once every lifecycle manager reports its nodes active and, with SLAM, a map is publishing
healthcheck() {
  local prefix manager
  source_ros
  prefix="$(detect_namespace)"
  prefix="${prefix:+/${prefix}}"
  for manager in $(nav2_lifecycle_managers); do
    [[ "$(lifecycle_manager_state "${prefix}/${manager}")" == active ]] || exit 1
  done
  if [[ "${NAV2_ENABLE_SLAM:-false}" == "true" || "${NAV2_LAUNCH_FILE:-}" == "slam.launch.py" ]]; then
    topic_publishing "${prefix}/map"
  fi
}

save_map() {
  local target dir namespace start
  if [[ $# -lt 1 || "$1" == -* ]]; then
    usage
    exit 2
  fi

  target="${1%.yaml}"
  shift
  [[ "${target}" == */* ]] || target="${setup_path}/maps/${target}"
  dir="$(dirname "${target}")"

  if [[ ! -d "${dir}" || ! -w "${dir}" ]]; then
    echo "[cpr-nav2] ${dir} isn't a writable directory for $(id -un) (uid $(id -u))." >&2
    echo "[cpr-nav2] On the host, create the maps directory and make it writable," \
      "e.g. mkdir -p ~/clearpath/maps && chmod a+w ~/clearpath/maps" >&2
    exit 1
  fi

  namespace="$(detect_namespace)"
  have_namespace "${namespace}" "the namespaced map topic; using /map" || true

  source_ros

  start="$(date +%s)"
  ros2 run nav2_map_server map_saver_cli -f "${target}" "$@" \
    --ros-args -p save_map_timeout:=10.0 -r "map:=${namespace:+/${namespace}}/map"

  if [[ ! -f "${target}.yaml" ]] || (( $(stat -c %Y "${target}.yaml") < start )); then
    echo "[cpr-nav2] the map wasn't saved; is a map publishing on" \
      "${namespace:+/${namespace}}/map?" >&2
    exit 1
  fi
  echo "[cpr-nav2] saved ${target}.yaml; load it with NAV2_MAP=${target}.yaml" >&2
}

split_subcommand launch "$@"
set -- "${subcommand_args[@]}"
case "${subcommand}" in
  launch) ;;
  healthcheck) healthcheck; exit ;;
  save-map) save_map "$@"; exit 0 ;;
  -h | --help | help) usage; exit 0 ;;
  *) usage; exit 2 ;;
esac

# The rest is `cpr-nav2 launch`; "$@" holds the launch args.
use_sim_time="${USE_SIM_TIME:-true}"
scan_topic="${SCAN_TOPIC:-}"
launch_file="${NAV2_LAUNCH_FILE:-nav2.launch.py}"
enable_slam="${NAV2_ENABLE_SLAM:-false}"
slam_sync="${NAV2_SLAM_SYNC:-false}"
auto_nav2_startup="${AUTO_NAV2_STARTUP:-true}"
start_attempts="${NAV2_START_ATTEMPTS:-3}"
service_call_timeout_s="${NAV2_SERVICE_CALL_TIMEOUT_S:-8}"
active_wait_timeout_s="${NAV2_ACTIVE_WAIT_TIMEOUT_S:-300}"
topic_wait_timeout_s="${NAV2_TOPIC_WAIT_TIMEOUT_S:-120}"
nav2_map="${NAV2_MAP:-}"
initial_pose="${NAV2_INITIAL_POSE:-}"
manager="$(nav2_lifecycle_manager "${launch_file}")"

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
  NAV2_MAP NAV2_INITIAL_POSE SCAN_TOPIC AUTO_NAV2_STARTUP NAV2_START_ATTEMPTS \
  NAV2_ACTIVE_WAIT_TIMEOUT_S WAIT_FOR_SIM
log_robot_yaml
echo "[cpr-nav2] robot namespace=${namespace:-unknown}"

fail() {
  echo "[cpr-nav2] ERROR: $*" >&2
  exit 1
}

if [[ -n "${nav2_map}" ]]; then
  [[ -f "${nav2_map}" ]] ||
    fail "NAV2_MAP=${nav2_map} doesn't exist in the container; put the map in the setup directory"
  [[ "${enable_slam}" != "true" && "${launch_file}" != "slam.launch.py" ]] ||
    fail "NAV2_MAP loads a map for localization and can't be combined with SLAM"
fi
if [[ -n "${initial_pose}" ]]; then
  [[ "${initial_pose}" =~ ^[[:space:]]*(-?[0-9.]+[[:space:]]+){2}-?[0-9.]+[[:space:]]*$ ]] ||
    fail "NAV2_INITIAL_POSE must be \"x y yaw\" in the map frame, got \"${initial_pose}\""
fi

wait_for_nav2_inputs() {
  local topic

  have_namespace "${namespace}" "pre-Nav2 topic gates" || return 0

  echo "[cpr-nav2] waiting for odom and TF topics before Nav2 bringup..." >&2
  for topic in platform/odom/filtered tf_static tf; do
    echo "[cpr-nav2] waiting for /${namespace}/${topic}" >&2
    wait_for_topic_publishing "/${namespace}/${topic}" "${topic_wait_timeout_s}" ||
      echo "[cpr-nav2] timed out waiting for /${namespace}/${topic}; continuing" >&2
  done

  echo "[cpr-nav2] waiting briefly for /${namespace}/map (best effort)" >&2
  wait_for_topic_publishing "/${namespace}/map" 30 || true
}

slam_pid=""
localization_pid=""
nav2_pid=""

# stop_group <pid>: stops a process group started with setsid
stop_group() {
  kill -TERM -- "-$1" 2>/dev/null || return 0
  for _ in {1..20}; do
    kill -0 "$1" 2>/dev/null || break
    sleep 0.5
  done
  kill -KILL -- "-$1" 2>/dev/null || true
  wait "$1" 2>/dev/null || true
}

cleanup() {
  local pid
  for pid in "${nav2_pid}" "${localization_pid}" "${slam_pid}"; do
    [[ -z "${pid}" ]] || stop_group "${pid}"
  done
}

trap cleanup EXIT
trap 'exit 143' INT TERM

# launch_group <launch file> [args...]: starts a clearpath_nav2_demos launch in its own process
# group, so a restart stops every node it started; its pid is left in launched_pid
launch_group() {
  setsid ros2 launch clearpath_nav2_demos "$1" "${args[@]}" "${@:2}" &
  launched_pid="$!"
}

# wait_for_active <pid> <manager> <timeout_s>: returns 0 once the lifecycle manager reports its
# nodes active. Returns 1, with the reason in startup_failure, if the launch exits, the manager
# reports its nodes inactive (its bringup failed), or timeout_s passes (0 waits indefinitely). A
# manager that is still busy, e.g. with a costmap waiting for its transform, is left to finish.
wait_for_active() {
  local pid="$1" manager_fqn="/${namespace}/$2" timeout_s="$3"
  local start="${SECONDS}"
  local inactive=0

  while kill -0 "${pid}" 2>/dev/null; do
    case "$(lifecycle_manager_state "${manager_fqn}" "${service_call_timeout_s}")" in
      active) return 0 ;;
      # Twice in a row, so a reply from just before autostart begins doesn't count
      inactive) (( ++inactive < 2 )) || { startup_failure="its bringup failed"; return 1; } ;;
      *) inactive=0 ;;
    esac
    if (( timeout_s > 0 && SECONDS - start >= timeout_s )); then
      startup_failure="it wasn't active after ${timeout_s}s"
      return 1
    fi
    sleep 2
  done

  startup_failure="its launch exited"
  return 1
}

# start_launch <pid variable> <manager> <timeout_s> <launch file> [args...]
# Starts the launch. When supervising, waits for its lifecycle manager to report its nodes active
# and restarts the launch if it fails, up to NAV2_START_ATTEMPTS times.
start_launch() {
  local -n pid_ref="$1"
  local manager_name="$2" timeout_s="$3" file="$4"
  local attempt
  shift 4

  if [[ "${supervise}" != "true" ]]; then
    launch_group "${file}" "$@"
    pid_ref="${launched_pid}"
    return 0
  fi

  for (( attempt = 1; ; attempt++ )); do
    echo "[cpr-nav2] starting ${file} (attempt ${attempt}/${start_attempts})" >&2
    launch_group "${file}" "$@"
    pid_ref="${launched_pid}"
    if wait_for_active "${pid_ref}" "${manager_name}" "${timeout_s}"; then
      echo "[cpr-nav2] ${file}: lifecycle nodes are active" >&2
      return 0
    fi
    if (( attempt >= start_attempts )); then
      echo "[cpr-nav2] ${file} not active after ${start_attempts} attempts; leaving it running" >&2
      return 0
    fi
    echo "[cpr-nav2] Restarting ${file} because ${startup_failure}" >&2
    stop_group "${pid_ref}"
    pid_ref=""
  done
}

# set_initial_pose: sends NAV2_INITIAL_POSE ("x y yaw" in the map frame) to AMCL, retrying until
# AMCL publishes a pose
set_initial_pose() {
  local x y yaw qz qw pose
  read -r x y yaw <<< "${initial_pose}"
  read -r qz qw < <(awk -v t="${yaw}" 'BEGIN { printf "%.6f %.6f\n", sin(t / 2), cos(t / 2) }')
  pose="{header: {frame_id: map}, pose: {pose: {position: {x: ${x}, y: ${y}}, \
orientation: {z: ${qz}, w: ${qw}}}, covariance: [0.25, 0, 0, 0, 0, 0, 0, 0.25, 0, 0, 0, 0, \
0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.0685]}}"

  for _ in {1..5}; do
    timeout "${service_call_timeout_s}" ros2 topic pub --once -w 1 "/${namespace}/initialpose" \
      geometry_msgs/msg/PoseWithCovarianceStamped "${pose}" >/dev/null 2>&1 || true
    if topic_publishing "/${namespace}/amcl_pose" 10; then
      echo "[cpr-nav2] initial pose set to (${x}, ${y}, ${yaw})" >&2
      return 0
    fi
  done
  echo "[cpr-nav2] AMCL didn't accept NAV2_INITIAL_POSE" >&2
  return 1
}

# Navigation can't activate without the map -> odom transform AMCL publishes once it has a pose, and
# the lifecycle manager gives up after about a minute, so only start navigation once that's set.
wait_for_initial_pose() {
  echo "[cpr-nav2] Set the robot's initial pose (e.g. RViz 2D Pose Estimate);" \
    "navigation starts once AMCL has it" >&2
  until topic_publishing "/${namespace}/amcl_pose" 10; do
    kill -0 "${localization_pid}" 2>/dev/null || fail "localization.launch.py exited"
  done
  echo "[cpr-nav2] AMCL has an initial pose" >&2
}

WAIT_FOR_SIM="${WAIT_FOR_SIM:-false}" wait_for_sim_if_enabled "${namespace}"

if [[ "${enable_slam}" == "true" && "${launch_file}" != "slam.launch.py" ]]; then
  setsid ros2 launch clearpath_nav2_demos slam.launch.py "${args[@]}" "sync:=${slam_sync}" &
  slam_pid="$!"

  wait_for_nav2_inputs
fi

# The lifecycle managers start their nodes themselves (autostart). Supervising only watches for
# that to finish, and restarts a launch whose bringup fails or whose launch exits.
startup_failure=""
supervise="false"
if [[ "${auto_nav2_startup}" == "true" && -n "${manager}" ]] &&
  have_namespace "${namespace}" "Nav2 startup supervision"; then
  supervise="true"
fi

main_args=()
if [[ -n "${nav2_map}" && "${launch_file}" == "localization.launch.py" ]]; then
  main_args=("map:=${nav2_map}")
elif [[ -n "${nav2_map}" ]]; then
  # Localization provides the map and the map -> odom transform navigation needs
  start_launch localization_pid lifecycle_manager_localization "${active_wait_timeout_s}" \
    localization.launch.py "map:=${nav2_map}"
  if have_namespace "${namespace}" "waiting for the initial pose"; then
    if [[ -z "${initial_pose}" ]] || ! set_initial_pose; then
      wait_for_initial_pose
    fi
  fi
fi

start_launch nav2_pid "${manager}" "${active_wait_timeout_s}" "${launch_file}" "${main_args[@]}" "$@"
if [[ -n "${nav2_map}" && "${launch_file}" == "localization.launch.py" && -n "${initial_pose}" ]] &&
  have_namespace "${namespace}" "setting the initial pose"; then
  set_initial_pose || echo "[cpr-nav2] Set the initial pose manually" >&2
fi

wait "${nav2_pid}"
