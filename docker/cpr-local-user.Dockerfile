# Rebuild a published image (dev, sim, robot, ...) with the host user's UID/GID to avoid permission issues
ARG ROS_DISTRO=jazzy
ARG CPR_BASE_IMAGE=ghcr.io/clearpathrobotics/clearpath_docker
ARG CPR_BASE_TAG=${ROS_DISTRO}-dev-latest
FROM ${CPR_BASE_IMAGE}:${CPR_BASE_TAG}

# Empty: CPR_USER from the parent (dev-based images), else /etc/clearpath_username (robot images)
ARG USERNAME=
ARG USER_UID=1000
ARG USER_GID=$USER_UID
# Empty: CPR_USER; the robot image passes root so systemd can run as PID 1
ARG RUNTIME_USER=

# Parent images such as sim end with a non-root USER
USER root

# Re-number the existing user/group to the host UID/GID; fails if the user doesn't exist.
# usermod -u writes lastlog/faillog entries at an offset of UID; truncate so large
# (e.g. domain) UIDs don't leave ~600 GB sparse files in the layer on jammy.
RUN user="${USERNAME:-${CPR_USER:-$(cat /etc/clearpath_username)}}" \
  && old_uid=$(id -u "$user") && old_gid=$(id -g "$user") \
  && groupmod -g $USER_GID "$user" \
  && usermod -u $USER_UID -g $USER_GID "$user" \
  && find / -xdev \( -uid "$old_uid" -o -gid "$old_gid" \) -exec chown -h $USER_UID:$USER_GID {} + \
  && truncate -s 0 /var/log/lastlog /var/log/faillog

USER ${RUNTIME_USER:-${CPR_USER}}
