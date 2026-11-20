ARG CPR_BASE_IMAGE=ghcr.io/clearpathrobotics/clearpath_docker
ARG CPR_BASE_TAG=jazzy-dev-latest
ARG ROS_DISTRO=jazzy

FROM ${CPR_BASE_IMAGE}:${CPR_BASE_TAG}
USER root

# Install clearpath-viz and yaml parsing tool
RUN apt-get update \
  && apt-get install -y \
    ros-${ROS_DISTRO}-clearpath-viz \
  && apt-get autoremove -y \
  && apt-get clean -y \
  && rm -rf /var/lib/apt/lists/*

COPY scripts/cpr-common.sh /usr/local/bin/cpr-common.sh
COPY scripts/cpr-viz.sh /usr/local/bin/cpr-viz
RUN chmod 0755 /usr/local/bin/cpr-common.sh /usr/local/bin/cpr-viz

HEALTHCHECK --interval=10s --timeout=10s --start-period=60s --retries=24 \
  CMD ["/usr/local/bin/cpr-viz", "healthcheck"]

ENV DEBIAN_FRONTEND=noninteractive

USER ${CPR_USER}
CMD ["/usr/local/bin/cpr-viz", "launch"]
