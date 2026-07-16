ARG ROS_DISTRO=jazzy
ARG CPR_BASE_IMAGE=ghcr.io/clearpathrobotics/clearpath_docker
ARG CPR_BASE_TAG=${ROS_DISTRO}-dev-latest
FROM ${CPR_BASE_IMAGE}:${CPR_BASE_TAG} AS cpr-nav2
ARG ROS_DISTRO

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y \
    ros-${ROS_DISTRO}-clearpath-nav2-demos \
    ros-${ROS_DISTRO}-clearpath-common \
  && apt-get autoremove -y \
  && apt-get clean -y \
  && rm -rf /var/lib/apt/lists/*


COPY cpr-common.sh /usr/local/bin/cpr-common.sh
COPY cpr-nav2-launch.sh /usr/local/bin/cpr-nav2-launch
# TODO: remove once ros-${ROS_DISTRO}-clearpath-nav2-demos is released with rolling global costmap fix
COPY nav2_config/ /opt/ros/${ROS_DISTRO}/share/clearpath_nav2_demos/config/
RUN chmod 0755 /usr/local/bin/cpr-common.sh /usr/local/bin/cpr-nav2-launch

# Healthcheck: passes once bt_navigator and (optionally) slam_toolbox are alive.
HEALTHCHECK --interval=10s --timeout=10s --start-period=120s --retries=24 \
  CMD bash -c '\
    source /opt/ros/${ROS_DISTRO}/setup.bash && \
    if [[ "${RMW_IMPLEMENTATION:-}" == "rmw_cyclonedds_cpp" ]]; then \
      export CYCLONEDDS_URI="<CycloneDDS><Domain><Discovery><ParticipantIndex>none</ParticipantIndex></Discovery></Domain></CycloneDDS>"; \
    fi && \
    ros2 node list --no-daemon 2>/dev/null | grep -qE "/[^/]+/bt_navigator$" && \
    ( [[ "${NAV2_ENABLE_SLAM:-false}" != "true" ]] || ros2 node list --no-daemon 2>/dev/null | grep -qE "slam_toolbox" )'

ENV DEBIAN_FRONTEND=
USER ros
WORKDIR /home/ros

CMD ["/usr/local/bin/cpr-nav2-launch"]