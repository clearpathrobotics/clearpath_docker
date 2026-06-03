ARG ROS_DISTRO=jazzy
ARG CPR_BASE_IMAGE=ghcr.io/clearpathrobotics/clearpath_docker
ARG CPR_BASE_TAG=${ROS_DISTRO}-latest
FROM ${CPR_BASE_IMAGE}:${CPR_BASE_TAG} AS cpr-ci
ARG ROS_DISTRO

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8
ENV PIP_BREAK_SYSTEM_PACKAGES=1

# Locale + timezone (CI logs and timestamp-sensitive tests expect a sane locale).
RUN apt-get update && apt-get install -y \
    locales \
    tzdata \
  && locale-gen en_US en_US.UTF-8 \
  && update-locale LANG=en_US.UTF-8 \
  && ln -sf /usr/share/zoneinfo/Etc/UTC /etc/localtime \
  && echo 'Etc/UTC' > /etc/timezone \
  && rm -rf /var/lib/apt/lists/*

# Pick the RTI Connext DDS package version matching the ROS distro, mirroring
# rostooling/setup-ros-docker. Skip if the distro is not known to ship a build.
RUN UBUNTU_CODENAME="$(lsb_release -cs)" \
  && case "${ROS_DISTRO}" in \
       humble|jazzy)    RTI_CONNEXT_DDS="rti-connext-dds-6.0.1" ;; \
       kilted)          RTI_CONNEXT_DDS="rti-connext-dds-7.3.0-ros" ;; \
       rolling|lyrical) RTI_CONNEXT_DDS="rti-connext-dds-7.7.0-ros" ;; \
       *)               RTI_CONNEXT_DDS="" ;; \
     esac \
  && apt-get update \
  && apt-get install -y \
       build-essential \
       clang \
       lcov \
       libasio-dev \
       libssl-dev \
       libtinyxml2-dev \
       python3-dev \
       python3-pip \
       ros-dev-tools \
       python3-pytest-cov \
       python3-pytest-repeat \
       python3-pytest-rerunfailures \
       python3-flake8-blind-except \
       python3-flake8-class-newline \
       python3-flake8-deprecated \
       python3-flake8-docstrings \
       python3-flake8-builtins \
       python3-flake8-comprehensions \
       python3-flake8-import-order \
       python3-flake8-quotes \
       python3-colcon-coveragepy-result \
       python3-colcon-lcov-result \
       python3-colcon-meson \
       python3-colcon-metadata \
       python3-colcon-mixin \
  && if [ -n "${RTI_CONNEXT_DDS}" ]; then \
       RTI_NC_LICENSE_ACCEPTED=yes apt-get install -y "${RTI_CONNEXT_DDS}" || \
         echo "Warning: ${RTI_CONNEXT_DDS} not available for ${UBUNTU_CODENAME}, skipping."; \
     fi \
  && apt-get autoremove -y \
  && apt-get clean -y \
  && rm -rf /var/lib/apt/lists/*

# Register the default colcon mixin/metadata repositories so `colcon mixin` /
# `colcon metadata` work out of the box in CI.
RUN (colcon mixin add default \
        https://raw.githubusercontent.com/colcon/colcon-mixin-repository/master/index.yaml \
      || true) \
  && colcon mixin update default \
  && (colcon metadata add default \
        https://raw.githubusercontent.com/colcon/colcon-metadata-repository/master/index.yaml \
      || true) \
  && colcon metadata update default

ENV DEBIAN_FRONTEND=
