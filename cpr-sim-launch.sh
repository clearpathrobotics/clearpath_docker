#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=cpr-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/cpr-common.sh"

startup_timeout_s="${SIM_STARTUP_TIMEOUT_S:-120}"
gazebo_startup_timeout="${GAZEBO_STARTUP_TIMEOUT:-120}"
max_restarts="${GAZEBO_MAX_RESTARTS:-3}"

# --- Controller recovery (background loop) ---
# Continuously ensures joint_state_broadcaster and platform_velocity_controller
# are active.  This handles both initial activation after Gazebo starts and
# recovery if a controller is deactivated or the controller_manager restarts.
controller_recovery_loop() {
	local namespace="$1"
	local cm

	if [[ -z "${namespace}" ]]; then
		echo "[cpr-sim-launch] Namespace not found, skipping controller recovery" >&2
		return 0
	fi

	cm="/${namespace}/controller_manager"
	echo "[cpr-sim-launch] Controller recovery enabled for ${cm}" >&2

	while true; do
		if ! ros2 service list --no-daemon 2>/dev/null | grep -qx "${cm}/list_controllers"; then
			sleep 2
			continue
		fi

		local list_out
		list_out="$(timeout 8 ros2 service call "${cm}/list_controllers" \
			controller_manager_msgs/srv/ListControllers "{}" 2>/dev/null || true)"

		if printf "%s" "$list_out" | grep -q "name='joint_state_broadcaster', state='active'" &&
		   printf "%s" "$list_out" | grep -q "name='platform_velocity_controller', state='active'"; then
			sleep 10
			continue
		fi

		echo "[cpr-sim-launch] Ensuring joint_state_broadcaster active" >&2
		timeout 90 ros2 run controller_manager spawner -c "${cm}" \
			joint_state_broadcaster --controller-manager-timeout 60 >/dev/null 2>&1 || true
		echo "[cpr-sim-launch] Ensuring platform_velocity_controller active" >&2
		timeout 90 ros2 run controller_manager spawner -c "${cm}" \
			platform_velocity_controller --controller-manager-timeout 60 >/dev/null 2>&1 || true

		sleep 3
	done
}

namespace="$(detect_namespace)"
log_robot_yaml
controller_recovery_loop "${namespace}" &

# --- Gazebo launch with watchdog ---
# If Gazebo hangs during GPU/rendering initialization (no /clock published),
# the watchdog kills it and retries up to GAZEBO_MAX_RESTARTS times.
restart_count=0
while true; do
	echo "[cpr-sim-launch] Starting Gazebo (attempt $((restart_count + 1))/$((max_restarts + 1)))" >&2

	ros2 launch clearpath_gz simulation.launch.py "setup_path:=${setup_path}" "$@" &
	gz_pid=$!

	# Wait for /clock to appear
	clock_found=false
	for _ in $(seq 1 "${gazebo_startup_timeout}"); do
		if ! kill -0 "${gz_pid}" 2>/dev/null; then
			echo "[cpr-sim-launch] Gazebo process exited unexpectedly" >&2
			break
		fi
		if timeout 1 ros2 topic echo /clock --once >/dev/null 2>&1; then
			clock_found=true
			break
		fi
		sleep 1
	done

	if ${clock_found}; then
		echo "[cpr-sim-launch] /clock detected, Gazebo is running" >&2
		wait "${gz_pid}" || true
		echo "[cpr-sim-launch] Gazebo exited (code: $?)" >&2
		exit 0
	fi

	# /clock never appeared — kill and retry
	restart_count=$((restart_count + 1))
	echo "[cpr-sim-launch] /clock not detected after ${gazebo_startup_timeout}s, killing Gazebo (restart ${restart_count}/${max_restarts})" >&2

	kill "${gz_pid}" 2>/dev/null || true
	pkill -9 -f "gz sim" 2>/dev/null || true
	sleep 3

	if (( restart_count > max_restarts )); then
		echo "[cpr-sim-launch] Max restarts exceeded, giving up" >&2
		exit 1
	fi
done