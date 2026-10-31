ARG ROS_DISTRO=jazzy
ARG CPR_BASE_IMAGE=ghcr.io/clearpathrobotics/clearpath_docker
ARG CPR_BASE_TAG=${ROS_DISTRO}-dev-latest
FROM ${CPR_BASE_IMAGE}:${CPR_BASE_TAG} AS cpr-sim
ARG ROS_DISTRO

USER root
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y \
    ros-${ROS_DISTRO}-clearpath-gz \
  && apt-get autoremove -y \
  && apt-get clean -y \
  && rm -rf /var/lib/apt/lists/*

COPY scripts/cpr-common.sh /usr/local/bin/cpr-common.sh
COPY scripts/cpr-dev.sh /usr/local/bin/cpr-dev.sh
COPY scripts/cpr-healthcheck.sh /usr/local/bin/cpr-healthcheck
COPY scripts/cpr-sim-launch.sh /usr/local/bin/cpr-sim-launch
RUN chmod 0755 /usr/local/bin/cpr-common.sh /usr/local/bin/cpr-dev.sh /usr/local/bin/cpr-healthcheck /usr/local/bin/cpr-sim-launch

# Healthy once /clock and the robot's odometry are publishing; downstream
# services wait on it with depends_on: condition: service_healthy.
HEALTHCHECK --interval=10s --timeout=20s --start-period=120s --retries=24 \
  CMD ["/usr/local/bin/cpr-healthcheck", "sim"]

ENV DEBIAN_FRONTEND=

# Gazebo model cache at a user-independent path (GZ_ for Harmonic, IGN_ for Fortress/Humble).
# Pre-created so a volume mounted here starts owned by CPR_USER instead of root.
ENV GZ_FUEL_CACHE_PATH=/var/cache/gz/fuel \
    IGN_FUEL_CACHE_PATH=/var/cache/gz/fuel
RUN mkdir -p /var/cache/gz/fuel && chown -R ${CPR_USER}:${CPR_USER} /var/cache/gz

USER ${CPR_USER}
WORKDIR /home/${CPR_USER}

CMD ["/usr/local/bin/cpr-sim-launch"]