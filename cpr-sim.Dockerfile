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

COPY cpr-common.sh /usr/local/bin/cpr-common.sh
COPY cpr-sim-launch.sh /usr/local/bin/cpr-sim-launch
RUN chmod 0755 /usr/local/bin/cpr-common.sh /usr/local/bin/cpr-sim-launch

# Healthcheck: passes once the Gazebo→ROS clock bridge is publishing /clock.
# nav2 and viz services use this via depends_on: condition: service_healthy
# to avoid starting before Gazebo is ready.
HEALTHCHECK --interval=5s --timeout=10s --start-period=120s --retries=3 \
  CMD bash -c '\
    source /opt/ros/${ROS_DISTRO}/setup.bash && \
    if [[ "${RMW_IMPLEMENTATION:-}" == "rmw_cyclonedds_cpp" ]]; then \
      export CYCLONEDDS_URI="<CycloneDDS><Domain><Discovery><ParticipantIndex>none</ParticipantIndex></Discovery></Domain></CycloneDDS>"; \
    fi && \
    timeout 8 ros2 topic echo /clock --once 2>/dev/null | grep -q "sec:"'

ENV DEBIAN_FRONTEND=
USER ros
WORKDIR /home/ros

CMD ["/usr/local/bin/cpr-sim-launch"]