ARG ROS_DISTRO=jazzy
ARG CPR_BASE_IMAGE=ghcr.io/clearpathrobotics/clearpath_docker
ARG CPR_BASE_TAG=${ROS_DISTRO}-latest
FROM ${CPR_BASE_IMAGE}:${CPR_BASE_TAG} AS cpr-dev
ARG ROS_DISTRO

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
  python3-pip \
  python3-pep8 \
  python3-autopep8 \
  pylint \
  bash-completion \
  nano \
  vim \
  inetutils-ping \
  ros-build-essential \
  ros-${ROS_DISTRO}-rmw-cyclonedds-cpp \
  && apt-get autoremove -y \
  && apt-get clean -y \
  && rm -rf /var/lib/apt/lists/*

COPY scripts/cpr-dev.sh /usr/local/bin/cpr-dev.sh
RUN chmod 0755 /usr/local/bin/cpr-dev.sh

ARG USER_UID=1000
ARG USER_GID=$USER_UID

# Create a non-root user with passwordless sudo
# -l: large (e.g. domain) UIDs otherwise create a ~600 GB sparse lastlog on jammy
RUN groupadd --gid $USER_GID $CPR_USER \
  && useradd -l -s /bin/bash --uid $USER_UID --gid $USER_GID -m $CPR_USER \
  && apt-get update \
  && apt-get install -y sudo \
  && echo $CPR_USER ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$CPR_USER \
  && chmod 0440 /etc/sudoers.d/$CPR_USER \
  && rm -rf /var/lib/apt/lists/* \
  && echo "source /usr/share/bash-completion/completions/git" >> /home/$CPR_USER/.bashrc \
  && echo "if [ -f /opt/ros/${ROS_DISTRO}/setup.bash ]; then source /opt/ros/${ROS_DISTRO}/setup.bash; fi" >> /home/$CPR_USER/.bashrc \
  && echo "source /usr/local/bin/cpr-dev.sh" >> /home/$CPR_USER/.bashrc

# Persist bash history via a mountable volume
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
    && mkdir /commandhistory \
    && touch /commandhistory/.bash_history \
    && chown -R $CPR_USER /commandhistory \
    && echo "$SNIPPET" >> "/home/$CPR_USER/.bashrc"

# Workspaces: /ros2_ws is the compose mount point, /colcon_ws is sourced by cpr-dev.sh
RUN mkdir -p /ros2_ws /colcon_ws/src \
    && chown -R $CPR_USER:$CPR_USER /ros2_ws /colcon_ws

ENV DEBIAN_FRONTEND=
USER ${CPR_USER}
WORKDIR /ros2_ws
