ARG ROS_DISTRO=jazzy
FROM ros:${ROS_DISTRO}-ros-base AS cpr-ros-base
ARG ROS_DISTRO

# Fix issue with new ubuntu user
RUN userdel -r ubuntu || true

ENV DEBIAN_FRONTEND=noninteractive
RUN echo '\
  APT::Install-Recommends "0";\n\
  APT::Install-Suggests "0";\n\
  ' > /etc/apt/apt.conf.d/01norecommend

RUN apt-get update && apt-get install -y \
  wget \
  git \
  gnupg \
  python3-yaml \
  curl \
  && apt-get upgrade -y --with-new-pkgs \
  && apt-get autoremove -y \
  && apt-get clean -y \
  && rm -rf /var/lib/apt/lists/*

# # Index both private and public images
WORKDIR /etc/ros/rosdep
# Random fork below for python3.  Should make our own fork from that.
RUN git clone https://github.com/mikekaram/rosdep-generator.git \
  && python3 rosdep-generator/rosdep-generator \
  --org clearpathrobotics \
  --repo public-rosdistro \
  --distro ${ROS_DISTRO} \
  && rm -rf rosdep-generator
RUN echo "yaml file:///etc/ros/rosdep/clearpathrobotics-public-rosdistro-${ROS_DISTRO}.yaml ${ROS_DISTRO}" > /etc/ros/rosdep/sources.list.d/90-clearpathrobotics-public-rosdistro-${ROS_DISTRO}.list

RUN mkdir -p /etc/apt/keyrings \
  && wget https://packages.clearpathrobotics.com/public.key -qO- \
    | gpg --dearmor -o /etc/apt/keyrings/clearpathrobotics.gpg
# Only add the Clearpath apt source if the stable repo exists for this Ubuntu codename.
# Newer Ubuntu releases (e.g. resolute) may not yet be published in the stable repo,
# which would otherwise cause `apt-get update` to fail with a 404.
RUN UBUNTU_CODENAME="$(lsb_release -cs)" \
  && if curl -fsSL --retry 5 --retry-delay 5 -o /dev/null "https://packages.clearpathrobotics.com/stable/ubuntu/dists/${UBUNTU_CODENAME}/Release"; then \
       echo "deb [signed-by=/etc/apt/keyrings/clearpathrobotics.gpg] https://packages.clearpathrobotics.com/stable/ubuntu ${UBUNTU_CODENAME} main" \
         > /etc/apt/sources.list.d/clearpath-latest.list; \
     else \
       echo "Clearpath stable repo not available for Ubuntu ${UBUNTU_CODENAME}; skipping apt source."; \
     fi
RUN wget https://raw.githubusercontent.com/clearpathrobotics/public-rosdistro/master/rosdep/50-clearpath.list -O /etc/ros/rosdep/sources.list.d/50-clearpath.list

ENV DEBIAN_FRONTEND=

LABEL com.clearpathrobotics.vendor="Clearpath Robotics"
LABEL org.opencontainers.image.source="https://github.com/clearpathrobotics/clearpath_docker"
