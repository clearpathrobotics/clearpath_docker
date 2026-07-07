#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=cpr-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/cpr-common.sh"

startup_timeout_s="${SIM_STARTUP_TIMEOUT_S:-120}"

ensure_joint_state_broadcaster_active() {
	local namespace="$1"
	local cm
	local i

	if [[ -z "${namespace}" ]]; then
		echo "[cpr-sim-launch] Namespace not found, skipping joint_state_broadcaster activation" >&2
		return 0
	fi

	cm="/${namespace}/controller_manager"

	if ! wait_for_service "${cm}/list_controllers" "${startup_timeout_s}"; then
		echo "[cpr-sim-launch] controller_manager not available within ${startup_timeout_s}s: ${cm}" >&2
		return 0
	fi

	if ros2 service call "${cm}/list_controllers" controller_manager_msgs/srv/ListControllers '{}' 2>/dev/null | grep -q "name='joint_state_broadcaster', state='active'"; then
		echo "[cpr-sim-launch] joint_state_broadcaster already active" >&2
		return 0
	fi

	if ros2 run controller_manager spawner -c "${cm}" joint_state_broadcaster >/dev/null 2>&1; then
		echo "[cpr-sim-launch] Activated joint_state_broadcaster" >&2
		return 0
	fi

	echo "[cpr-sim-launch] Failed to activate joint_state_broadcaster" >&2
}

namespace="$(detect_namespace)"
(
	ensure_joint_state_broadcaster_active "${namespace}"
) &

exec ros2 launch clearpath_gz simulation.launch.py "setup_path:=${setup_path}" "$@"