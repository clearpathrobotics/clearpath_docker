ARG ROS_DISTRO=jazzy
ARG CPR_BASE_IMAGE=ghcr.io/clearpathrobotics/clearpath_docker
ARG CPR_BASE_TAG=${ROS_DISTRO}-ci-latest
FROM ${CPR_BASE_IMAGE}:${CPR_BASE_TAG} AS cpr-ci-common
ARG ROS_DISTRO

ENV DEBIAN_FRONTEND=noninteractive

# Pre-install the released clearpath_common so all of its build, test, and
# runtime dependencies are baked into the image. CI then checks out and builds
# clearpath_common from source on top of this image; because every dependency
# is already present, the in-CI `rosdep install` is a near no-op and the
# source build only needs to compile — cutting CI time substantially.
#
# The from-source overlay workspace shadows this binary copy at runtime, so the
# pre-installed package never masks what CI builds.
RUN apt-get update \
  && apt-get install -y ros-${ROS_DISTRO}-clearpath-common \
  && apt-get autoremove -y \
  && apt-get clean -y \
  && rm -rf /var/lib/apt/lists/*

ENV DEBIAN_FRONTEND=
