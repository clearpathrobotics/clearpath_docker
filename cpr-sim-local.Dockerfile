# Build a local sim image with host user's UID/GID to avoid permission issues
ARG ROS_DISTRO=jazzy
ARG CPR_BASE_IMAGE=ghcr.io/clearpathrobotics/clearpath_docker
ARG CPR_BASE_TAG=${ROS_DISTRO}-sim-latest
FROM ${CPR_BASE_IMAGE}:${CPR_BASE_TAG}

ARG USERNAME=robot
ARG USER_UID=1000
ARG USER_GID=$USER_UID

# Modify existing robot user/group to use host UID/GID
RUN groupmod -g $USER_GID $USERNAME || groupadd --gid $USER_GID $USERNAME \
  && usermod -u $USER_UID -g $USER_GID $USERNAME || useradd -s /bin/bash --uid $USER_UID --gid $USER_GID -m $USERNAME \
  && chown -R $USERNAME:$USERNAME /home/$USERNAME

USER $USERNAME
