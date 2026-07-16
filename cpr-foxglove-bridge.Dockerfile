ARG ROS_DISTRO=jazzy
ARG CPR_BASE_IMAGE=ghcr.io/clearpathrobotics/clearpath_docker
ARG CPR_BASE_TAG=${ROS_DISTRO}-latest
FROM ${CPR_BASE_IMAGE}:${CPR_BASE_TAG}
ARG ROS_DISTRO

# Install foxglove_bridge (native Lichtblick/Foxglove protocol) and dependencies
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ros-${ROS_DISTRO}-foxglove-bridge \
    ros-${ROS_DISTRO}-clearpath-config \
    ros-${ROS_DISTRO}-clearpath-common \
  && apt-get autoremove -y \
  && apt-get clean -y \
  && rm -rf /var/lib/apt/lists/*

COPY cpr-common.sh /usr/local/bin/cpr-common.sh
COPY cpr-foxglove-bridge-launch.sh /usr/local/bin/cpr-foxglove-bridge-launch
RUN chmod 0755 /usr/local/bin/cpr-common.sh /usr/local/bin/cpr-foxglove-bridge-launch

EXPOSE 8765

CMD ["/usr/local/bin/cpr-foxglove-bridge-launch"]
