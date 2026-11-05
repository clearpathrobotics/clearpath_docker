ARG CPR_BASE_IMAGE=ghcr.io/clearpathrobotics/clearpath_docker
ARG CPR_BASE_TAG=humble-latest
ARG USERNAME=administrator
FROM ${CPR_BASE_IMAGE}:${CPR_BASE_TAG} AS cpr-robot-humble
ARG USERNAME

ENV DEBIAN_FRONTEND=noninteractive

# Install systemd and remove unnecessary units
RUN apt-get update \
  && apt-get install -y \
    systemd \
    systemd-sysv \
  && rm -f /lib/systemd/system/multi-user.target.wants/* \
  && rm -f /etc/systemd/system/*.wants/* \
  && rm -f /lib/systemd/system/local-fs.target.wants/* \
  && rm -f /lib/systemd/system/sockets.target.wants/*udev* \
  && rm -f /lib/systemd/system/sockets.target.wants/*initctl* \
  && rm -f /lib/systemd/system/basic.target.wants/* \
  && rm -f /lib/systemd/system/anaconda.target.wants/* \
  && apt-get clean -y \
  && rm -rf /var/lib/apt/lists/*

# Mask logind and all shutdown/reboot/halt targets so the container cannot
# interfere with the host session (cgroup: host + privileged).
RUN systemctl mask \
    systemd-logind.service \
    shutdown.target \
    poweroff.target \
    reboot.target \
    halt.target \
    sleep.target \
    suspend.target \
    hibernate.target

# Install Clearpath robot packages, CAN utilities, and network tools
RUN apt-get update \
  && apt-get install -y \
    ros-humble-clearpath-robot \
    can-utils \
    iproute2 \
    sudo \
    udev \
    usbutils \
    python3-yaml \
  && apt-get autoremove -y \
  && apt-get clean -y \
  && rm -rf /var/lib/apt/lists/*

# Humble ships clearpath_robot with User=administrator in all systemd units
# and start scripts, so create that user, with passwordless sudo.
RUN useradd -m -s /bin/bash "${USERNAME}" && \
    echo "${USERNAME}" > /etc/clearpath_username && \
    echo "${USERNAME} ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} && \
    chmod 0440 /etc/sudoers.d/${USERNAME}

# Setup directory for robot configuration
RUN mkdir -p /etc/clearpath

COPY scripts/cpr-common.sh /usr/local/bin/cpr-common.sh
COPY scripts/cpr-healthcheck.sh /usr/local/bin/cpr-healthcheck
RUN chmod 0755 /usr/local/bin/cpr-common.sh /usr/local/bin/cpr-healthcheck

# Install the entrypoint that validates robot.yaml and starts systemd
COPY scripts/cpr-robot-entrypoint.sh /usr/local/bin/cpr-robot-entrypoint
RUN chmod 0755 /usr/local/bin/cpr-robot-entrypoint

# Healthy once the platform MCU status is publishing
HEALTHCHECK --interval=10s --timeout=10s --start-period=60s --retries=12 \
  CMD ["/usr/local/bin/cpr-healthcheck", "robot"]

ENV DEBIAN_FRONTEND=

VOLUME ["/sys/fs/cgroup"]
STOPSIGNAL SIGRTMIN+3

ENTRYPOINT ["/usr/local/bin/cpr-robot-entrypoint"]
CMD ["/sbin/init"]
