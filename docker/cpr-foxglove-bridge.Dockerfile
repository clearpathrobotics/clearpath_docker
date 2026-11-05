ARG ROS_DISTRO=jazzy
ARG CPR_BASE_IMAGE=ghcr.io/clearpathrobotics/clearpath_docker
ARG CPR_BASE_TAG=${ROS_DISTRO}-latest
FROM ${CPR_BASE_IMAGE}:${CPR_BASE_TAG}
ARG ROS_DISTRO

# Install foxglove_bridge (native Lichtblick/Foxglove protocol) and dependencies.
# rmw-cyclonedds-cpp: clearpath_common pulls it in on Jazzy but not on Humble.
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ros-${ROS_DISTRO}-foxglove-bridge \
    ros-${ROS_DISTRO}-clearpath-config \
    ros-${ROS_DISTRO}-clearpath-common \
    ros-${ROS_DISTRO}-rmw-cyclonedds-cpp \
  && apt-get autoremove -y \
  && apt-get clean -y \
  && rm -rf /var/lib/apt/lists/*

COPY scripts/cpr-common.sh /usr/local/bin/cpr-common.sh
COPY scripts/cpr-healthcheck.sh /usr/local/bin/cpr-healthcheck
COPY scripts/cpr-foxglove-bridge-launch.sh /usr/local/bin/cpr-foxglove-bridge-launch
RUN chmod 0755 /usr/local/bin/cpr-common.sh /usr/local/bin/cpr-healthcheck /usr/local/bin/cpr-foxglove-bridge-launch

HEALTHCHECK --interval=10s --timeout=5s --start-period=60s --retries=24 \
  CMD ["/usr/local/bin/cpr-healthcheck", "foxglove-bridge"]

# CPR_USER comes from the base image (administrator on Humble, robot otherwise)
RUN useradd -l -m -s /bin/bash --uid 1000 "${CPR_USER}"
USER ${CPR_USER}

EXPOSE 8765

CMD ["/usr/local/bin/cpr-foxglove-bridge-launch"]
