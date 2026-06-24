ARG ROS_DISTRO=jazzy
ARG CPR_BASE_IMAGE=ghcr.io/clearpathrobotics/clearpath_docker
ARG CPR_BASE_TAG=${ROS_DISTRO}-dev-latest
FROM ${CPR_BASE_IMAGE}:${CPR_BASE_TAG} AS cpr-sim
ARG ROS_DISTRO

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y \
    ros-${ROS_DISTRO}-clearpath-gz \
  && apt-get autoremove -y \
  && apt-get clean -y \
  && rm -rf /var/lib/apt/lists/*

COPY cpr-sim-launch.sh /usr/local/bin/cpr-sim-launch
RUN chmod 0755 /usr/local/bin/cpr-sim-launch

ENV DEBIAN_FRONTEND=
USER ros
WORKDIR /home/ros

CMD ["/usr/local/bin/cpr-sim-launch"]