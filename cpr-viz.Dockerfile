ARG CPR_BASE_IMAGE=ghcr.io/clearpathrobotics/clearpath_docker
ARG CPR_BASE_TAG=jazzy-dev-latest
ARG ROS_DISTRO=jazzy

FROM ${CPR_BASE_IMAGE}:${CPR_BASE_TAG}

# Install clearpath-viz and yaml parsing tool
RUN apt-get update \
  && apt-get install -y \
    ros-${ROS_DISTRO}-clearpath-viz \
    ros-${ROS_DISTRO}-clearpath-description \
    python3-yaml \
  && apt-get autoremove -y \
  && apt-get clean -y \
  && rm -rf /var/lib/apt/lists/*

COPY cpr-viz-launch.sh /usr/local/bin/cpr-viz-launch
RUN chmod 0755 /usr/local/bin/cpr-viz-launch

ENV DEBIAN_FRONTEND=noninteractive

USER ros
CMD ["/usr/local/bin/cpr-viz-launch"]
