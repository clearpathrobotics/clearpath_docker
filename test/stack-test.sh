#!/usr/bin/env bash
# Brings up sim (headless) and nav2 with SLAM through compose, waits for both to be
# healthy, then checks odometry, lidar, and the SLAM map are publishing.
# Usage: test/stack-test.sh <ros_distro> <sim_image> <nav2_image>
# cleanup() and publishing() are called through trap and check()
# shellcheck disable=SC2329
set -euo pipefail

distro=$1
sim_image=$2
nav2_image=$3
repo="$(cd "$(dirname "$0")/.." && pwd)"
project="cprtest-$$"
work="$(mktemp -d)"

export ROS_DISTRO="${distro}"
export SETUP_PATH_HOST="${work}/setup"
export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-42}"
export ROS_AUTOMATIC_DISCOVERY_RANGE=LOCALHOST
# sim is behind a profile; without it, `down` would leave the sim running
export COMPOSE_PROFILES=sim

dc() {
  docker compose -p "${project}" -f "${repo}/compose.yaml" -f "${work}/override.yaml" "$@"
}

cleanup() {
  dc down -v --remove-orphans >/dev/null 2>&1 || true
  # The sim writes generated files into the setup directory as uid 1000
  docker run --rm -v "${SETUP_PATH_HOST}:/setup" --entrypoint find "${sim_image}" \
    /setup -mindepth 1 -delete >/dev/null 2>&1 || true
  rm -rf "${work}"
}
trap cleanup EXIT

mkdir -p "${SETUP_PATH_HOST}"
chmod 777 "${SETUP_PATH_HOST}"
docker run --rm --entrypoint cat "${sim_image}" \
  "/opt/ros/${distro}/share/clearpath_config/sample/j100_dual_laser.yaml" > "${SETUP_PATH_HOST}/robot.yaml"

cat > "${work}/override.yaml" <<EOF
services:
  sim:
    image: ${sim_image}
    container_name: ${project}-sim
    environment:
      GAZEBO_HEADLESS: "true"
      GZ_IP: 127.0.0.1
      GZ_PARTITION: ${project}
      IGN_IP: 127.0.0.1
      IGN_PARTITION: ${project}
  nav2:
    image: ${nav2_image}
    container_name: ${project}-nav2
    build: !reset null
    environment:
      NAV2_ENABLE_SLAM: "true"
EOF

failed=0
check() {
  local desc=$1
  shift
  if "$@" >/dev/null 2>&1; then
    echo "ok   ${desc}"
  else
    echo "FAIL ${desc}"
    failed=1
  fi
}

# publishing <topic> <timeout_s>: a message arrives on the topic, seen from the sim container
publishing() {
  dc exec -T sim bash -c "source /usr/local/bin/cpr-common.sh && source /opt/ros/${distro}/setup.bash \
    && topic_publishing $1 $2"
}

if dc up -d --wait --wait-timeout "${STACK_TIMEOUT:-900}" sim nav2; then
  echo "ok   sim and nav2 healthy"
  ns="$(dc exec -T sim bash -c 'source /usr/local/bin/cpr-common.sh && detect_namespace')"
  check "odometry publishing" publishing "/${ns}/platform/odom/filtered" 20
  check "lidar publishing" publishing "/${ns}/sensors/lidar2d_0/scan" 30
  check "SLAM map publishing" publishing "/${ns}/map" 60
else
  echo "FAIL sim and nav2 healthy"
  failed=1
fi

if (( failed )); then
  dc ps -a
  dc logs --no-color --tail 150
fi
exit "${failed}"
