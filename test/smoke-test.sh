#!/usr/bin/env bash
# Quick checks that a built image is usable.
# Usage: test/smoke-test.sh <image> <variant> <ros_distro>
# Single-quoted snippets expand inside the container; helpers are called through check().
# shellcheck disable=SC2016,SC2329
set -euo pipefail

image=$1
variant=$2
distro=$3
user=robot
[[ "${distro}" == humble ]] && user=administrator
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

# in_image <image> <bash snippet>: runs as the image's default user
in_image() {
  docker run --rm --entrypoint bash "$1" -c "$2"
}

has_ros_pkg() {
  in_image "${image}" "source /opt/ros/${distro}/setup.bash && ros2 pkg prefix $1"
}

docker image inspect "${image}" >/dev/null 2>&1 || docker pull -q "${image}" >/dev/null

check "ROS ${distro} installed" in_image "${image}" "test -f /opt/ros/${distro}/setup.bash"
check "CycloneDDS profile present" in_image "${image}" 'test -f "${CYCLONEDDS_URI#file://}"'

case "${variant}" in
  dev | sim | nav2 | viz | foxglove-bridge)
    check "runs as ${user} (uid 1000)" in_image "${image}" "[[ \$(id -un) == ${user} && \$(id -u) == 1000 ]]"
    check "rmw_cyclonedds_cpp installed" has_ros_pkg rmw_cyclonedds_cpp
    ;;
esac

case "${variant}" in
  dev | sim | nav2 | viz)
    check "passwordless sudo" in_image "${image}" "sudo -n true"
    ;;
esac

case "${variant}" in
  sim | nav2 | viz | foxglove-bridge | robot)
    check "health check configured" bash -c \
      "docker image inspect -f '{{json .Config.Healthcheck.Test}}' '${image}' | grep -q cpr-healthcheck"
    check "cpr-healthcheck installed" in_image "${image}" "test -x /usr/local/bin/cpr-healthcheck"
    ;;
esac

case "${variant}" in
  ci | ci-common | ci-robot)
    check "colcon installed" in_image "${image}" "command -v colcon"
    ;;
esac

case "${variant}" in
  ci-common) check "clearpath_common installed" has_ros_pkg clearpath_common ;;
  ci-robot) check "clearpath_robot installed" has_ros_pkg clearpath_robot ;;
  sim) check "clearpath_gz installed" has_ros_pkg clearpath_gz ;;
  nav2) check "clearpath_nav2_demos installed" has_ros_pkg clearpath_nav2_demos ;;
  viz) check "clearpath_viz installed" has_ros_pkg clearpath_viz ;;
  foxglove-bridge) check "foxglove_bridge installed" has_ros_pkg foxglove_bridge ;;
  robot)
    check "runs as root" in_image "${image}" '[[ $(id -u) == 0 ]]'
    check "Clearpath user is ${user}" in_image "${image}" "[[ \$(cat /etc/clearpath_username) == ${user} ]]"
    check "${user} has passwordless sudo" in_image "${image}" "sudo -n -l -U ${user} | grep -q NOPASSWD"
    check "clearpath_robot installed" has_ros_pkg clearpath_robot
    ;;
esac

# The *-local services rebuild these images with the host user's uid/gid
case "${variant}" in
  dev | sim | nav2 | viz)
    local_image="cpr-smoke-local:${variant}-${distro}"
    docker tag "${image}" cpr-smoke-parent:latest
    if docker buildx build --builder default -q --load \
        -f "$(dirname "$0")/../docker/cpr-local-user.Dockerfile" \
        --build-arg CPR_BASE_IMAGE=cpr-smoke-parent --build-arg CPR_BASE_TAG=latest \
        --build-arg USER_UID=4242 --build-arg USER_GID=4242 \
        -t "${local_image}" "$(dirname "$0")/.." >/dev/null; then
      echo "ok   local-user build"
      check "local-user runs as ${user} (uid 4242)" in_image "${local_image}" \
        "[[ \$(id -un) == ${user} && \$(id -u) == 4242 ]]"
      check "local-user owns its home" in_image "${local_image}" '[[ $(stat -c %u "$HOME") == 4242 ]]'
      docker rmi -f "${local_image}" >/dev/null
    else
      echo "FAIL local-user build"
      failed=1
    fi
    docker rmi cpr-smoke-parent:latest >/dev/null
    ;;
esac

exit "${failed}"
