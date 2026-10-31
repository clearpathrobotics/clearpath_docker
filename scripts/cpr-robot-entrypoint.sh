#!/usr/bin/env bash
set -euo pipefail

# Entrypoint for the Clearpath robot container.
# Validates that robot.yaml is present, generates the clearpath config,
# enables the systemd services, then hands off to systemd (PID 1).

SETUP_PATH="${SETUP_PATH:-/etc/clearpath/}"
ROBOT_YAML="${SETUP_PATH}/robot.yaml"

# shellcheck source=cpr-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/cpr-common.sh"

# Determine the system user for this distro (written into the image at build time).
CLEARPATH_USER=$(cat /etc/clearpath_username 2>/dev/null || echo "robot")
export CLEARPATH_USER

# --- Validate robot.yaml ---
if [[ ! -f "${ROBOT_YAML}" ]]; then
  echo "========================================================" >&2
  echo " ERROR: robot.yaml not found at ${ROBOT_YAML}" >&2
  echo "" >&2
  echo " You MUST mount your robot.yaml into the container." >&2
  echo " Example:" >&2
  echo "   -v /path/to/your/robot.yaml:${ROBOT_YAML}:ro" >&2
  echo "" >&2
  echo " Or set SETUP_PATH and mount the directory:" >&2
  echo "   -v /path/to/clearpath/:${SETUP_PATH}:ro" >&2
  echo "========================================================" >&2
  exit 1
fi

echo "[cpr-robot] Found robot.yaml at ${ROBOT_YAML}"
log_robot_yaml "${ROBOT_YAML}"

# --- Run the clearpath_robot install script ---
# This generates launch files and installs ALL systemd services:
#   clearpath-robot.service        (orchestrator)
#   clearpath-platform.service     (platform drivers)
#   clearpath-platform-extras.service
#   clearpath-sensors.service      (sensor drivers)
#   clearpath-manipulators.service (manipulator drivers)
#   clearpath-vcan.service         (virtual CAN)
#   clearpath-discovery.service    (discovery server)
#   clearpath-zenoh-router.service (zenoh router)
#   clearpath-shutdown.service     (shutdown handler)
echo "[cpr-robot] Running clearpath_robot install script..."
set +u
source /opt/ros/${ROS_DISTRO}/setup.bash
set -u

# Humble defaults to CycloneDDS which may not be installed; force FastDDS
# (ships with every ROS 2 distro) only for the install step on Humble.
if [[ "${ROS_DISTRO}" == "humble" ]]; then
  export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
fi

ros2 run clearpath_robot install -s "${SETUP_PATH}"

# Fix the generated setup.bash to reference the correct ROS distro.
# When switching between Humble/Jazzy the host-mounted setup.bash may
# reference the wrong /opt/ros/<distro>/setup.bash.
if [[ -f "${SETUP_PATH}/setup.bash" ]]; then
  sed -i "s|source /opt/ros/[^/]*/setup.bash|source /opt/ros/${ROS_DISTRO}/setup.bash|" \
    "${SETUP_PATH}/setup.bash"
fi

# The clearpath_robot package ships systemd units with the correct username for
# each distro (administrator on Humble, robot on Jazzy+), so no patching needed.
# daemon-reload is a no-op here since systemd isn't PID 1 yet.
systemctl daemon-reload 2>/dev/null || true

echo "[cpr-robot] Clearpath systemd services installed successfully (user: ${CLEARPATH_USER})."
echo "[cpr-robot] Enabling clearpath-robot.service..."
systemctl enable clearpath-robot.service 2>/dev/null || true

# Prevent the shutdown handler from commanding the MCU to power off the robot
# when the container is stopped.
echo "[cpr-robot] Masking clearpath-shutdown.service..."
systemctl mask clearpath-shutdown.service 2>/dev/null || true

echo "[cpr-robot] Handing off to systemd (PID 1)..."
exec "$@"
