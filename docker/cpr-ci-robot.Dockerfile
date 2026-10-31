ARG ROS_DISTRO=jazzy
ARG CPR_BASE_IMAGE=ghcr.io/clearpathrobotics/clearpath_docker
ARG CPR_BASE_TAG=${ROS_DISTRO}-ci-latest
FROM ${CPR_BASE_IMAGE}:${CPR_BASE_TAG} AS cpr-ci-robot
ARG ROS_DISTRO

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y ros-${ROS_DISTRO}-clearpath-robot \
  && apt-get autoremove -y \
  && apt-get clean -y \
  && rm -rf /var/lib/apt/lists/*

ENV DEBIAN_FRONTEND=