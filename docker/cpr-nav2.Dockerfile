ARG ROS_DISTRO=jazzy
ARG CPR_BASE_IMAGE=ghcr.io/clearpathrobotics/clearpath_docker
ARG CPR_BASE_TAG=${ROS_DISTRO}-dev-latest
FROM ${CPR_BASE_IMAGE}:${CPR_BASE_TAG} AS cpr-nav2
ARG ROS_DISTRO

USER root
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y \
    ros-${ROS_DISTRO}-clearpath-nav2-demos \
    ros-${ROS_DISTRO}-clearpath-common \
  && apt-get autoremove -y \
  && apt-get clean -y \
  && rm -rf /var/lib/apt/lists/*


COPY scripts/cpr-common.sh /usr/local/bin/cpr-common.sh
COPY scripts/cpr-nav2.sh /usr/local/bin/cpr-nav2
RUN chmod 0755 /usr/local/bin/cpr-common.sh /usr/local/bin/cpr-nav2

# Healthy once Nav2's lifecycle manager reports its nodes active and, with SLAM, a map is
# published.
HEALTHCHECK --interval=10s --timeout=20s --start-period=150s --retries=24 \
  CMD ["/usr/local/bin/cpr-nav2", "healthcheck"]

ENV DEBIAN_FRONTEND=
USER ${CPR_USER}
WORKDIR /home/${CPR_USER}

CMD ["/usr/local/bin/cpr-nav2", "launch"]
