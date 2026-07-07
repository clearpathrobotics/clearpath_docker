ARG ROS_DISTRO=jazzy
ARG CPR_BASE_IMAGE=ghcr.io/clearpathrobotics/clearpath_docker
ARG CPR_BASE_TAG=${ROS_DISTRO}-dev-latest
FROM ${CPR_BASE_IMAGE}:${CPR_BASE_TAG} AS cpr-nav2
ARG ROS_DISTRO

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y \
    ros-${ROS_DISTRO}-clearpath-nav2-demos \
    ros-${ROS_DISTRO}-rmw-cyclonedds-cpp \
  && apt-get autoremove -y \
  && apt-get clean -y \
  && rm -rf /var/lib/apt/lists/*


COPY cpr-common.sh /usr/local/bin/cpr-common.sh
COPY cpr-nav2-launch.sh /usr/local/bin/cpr-nav2-launch
# TODO: remove once ros-${ROS_DISTRO}-clearpath-nav2-demos is released with rolling global costmap fix
COPY nav2_config/ /opt/ros/${ROS_DISTRO}/share/clearpath_nav2_demos/config/
RUN chmod 0755 /usr/local/bin/cpr-common.sh /usr/local/bin/cpr-nav2-launch

ENV DEBIAN_FRONTEND=
USER ros
WORKDIR /home/ros

CMD ["/usr/local/bin/cpr-nav2-launch"]